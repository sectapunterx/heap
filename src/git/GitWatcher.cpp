#include "GitWatcher.h"
#include "PrFacts.h"

#include "safety/EndOfDay.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTextStream>
#include <QtGlobal>

namespace heap::git {

GitWatcher::GitWatcher(QObject* parent) : QObject(parent), m_fsw(new QFileSystemWatcher(this)), m_debounce(new QTimer(this)) {
  m_debounce->setSingleShot(true);
  m_debounce->setInterval(250);
  connect(m_debounce, &QTimer::timeout, this, &GitWatcher::onDebounceFired);
  connect(m_fsw, &QFileSystemWatcher::fileChanged, this, &GitWatcher::onFsPathChanged);
  connect(m_fsw, &QFileSystemWatcher::directoryChanged, this, &GitWatcher::onFsPathChanged);

  m_gitPath = QStandardPaths::findExecutable(QStringLiteral("git"));
  m_ghPath = QStandardPaths::findExecutable(QStringLiteral("gh"));
  m_glabPath = QStandardPaths::findExecutable(QStringLiteral("glab"));
  if(m_ghPath.isEmpty() && m_glabPath.isEmpty()) {
    qInfo("GitWatcher: neither 'gh' nor 'glab' on PATH — PR state disabled");
  }
  if(m_gitPath.isEmpty()) {
    qInfo("GitWatcher: 'git' not on PATH — ahead/behind disabled");
  }
}

GitWatcher::~GitWatcher() = default;

QStringList GitWatcher::watchedRepos() const {
  return m_configs.keys();
}

QVariantMap GitWatcher::snapshot() const {
  QVariantMap out;
  for(auto it = m_state.constBegin(); it != m_state.constEnd(); ++it) {
    out.insert(it.key(), it.value().toVariant());
  }
  return out;
}

QString GitWatcher::cacheKey(const QString& repo, const QString& branch) {
  return repo + QChar('\n') + branch;
}

void GitWatcher::setWatchedRepos(const QStringList& paths) {
  QSet<QString> wanted;
  for(const QString& p : paths) {
    const QString abs = QDir(p).absolutePath();
    if(!abs.isEmpty()) {
      wanted.insert(abs);
    }
  }
  const auto current = QSet<QString>(m_configs.keyBegin(), m_configs.keyEnd());
  for(const QString& p : current) {
    if(!wanted.contains(p)) {
      removeRepo(p);
    }
  }
  for(const QString& p : wanted) {
    if(!m_configs.contains(p)) {
      addRepo(p);
    }
  }
}

void GitWatcher::setPrefixes(const QStringList& prefixes) {
  m_matcher.setPrefixes(prefixes);
}

void GitWatcher::setPrFetchEnabled(bool on) {
  m_prEnabled = on;
}

void GitWatcher::addRepo(const QString& path) {
  const QString gitDir = BranchTaskMatcher::resolveGitDir(path);
  if(gitDir.isEmpty()) {
    qInfo("GitWatcher: skipping '%s' — no .git found", qUtf8Printable(path));
    return;
  }
  const RepoConfig cfg{.path = path, .resolvedGitDir = gitDir, .commonGitDir = BranchTaskMatcher::resolveCommonDir(gitDir)};
  m_configs.insert(path, cfg);
  RepoState st;
  st.repoPath = path;
  m_state.insert(path, st);
  rewatchFiles(cfg);
  recomputeForRepo(path);
}

void GitWatcher::removeRepo(const QString& path) {
  auto it = m_configs.find(path);
  if(it == m_configs.end()) {
    return;
  }
  for(const QString& fp : {it->resolvedGitDir + QStringLiteral("/HEAD"),
                           it->resolvedGitDir + QStringLiteral("/index"),
                           it->commonGitDir + QStringLiteral("/packed-refs")}) {
    m_fsw->removePath(fp);
    m_watchedFileOwner.remove(fp);
  }
  m_configs.erase(it);
  m_state.remove(path);
}

void GitWatcher::rewatchFiles(const RepoConfig& cfg) {
  // HEAD and index belong to the worktree; packed-refs and refs/heads to the
  // common dir, which is the same place for a plain clone.
  for(const QString& fp : {cfg.resolvedGitDir + QStringLiteral("/HEAD"),
                           cfg.resolvedGitDir + QStringLiteral("/index"),
                           cfg.commonGitDir + QStringLiteral("/packed-refs")}) {
    if(!QFile::exists(fp)) {
      continue;
    }
    if(!m_fsw->files().contains(fp)) {
      m_fsw->addPath(fp);
    }
    m_watchedFileOwner.insert(fp, cfg.path);
  }
  // Also watch the refs/heads directory: branch SHA file is created on
  // first checkout and may not exist yet.
  const QString refsHeads = cfg.commonGitDir + QStringLiteral("/refs/heads");
  if(QFileInfo(refsHeads).isDir() && !m_fsw->directories().contains(refsHeads)) {
    m_fsw->addPath(refsHeads);
    m_watchedFileOwner.insert(refsHeads, cfg.path);
  }
}

void GitWatcher::onFsPathChanged(const QString& path) {
  const QString repo = m_watchedFileOwner.value(path);
  if(!repo.isEmpty()) {
    m_pendingRepos.insert(repo);
  }

  // Re-arm watch in case of atomic-rename replacement (Windows).
  if(QFile::exists(path) && !m_fsw->files().contains(path) && !m_fsw->directories().contains(path)) {
    m_fsw->addPath(path);
  }
  m_debounce->start();
}

void GitWatcher::onDebounceFired() {
  const auto repos = m_pendingRepos;
  m_pendingRepos.clear();
  for(const QString& r : repos) {
    if(m_configs.contains(r)) {
      // Re-arm files for the repo before recomputing.
      rewatchFiles(m_configs.value(r));
      recomputeForRepo(r);
    }
  }
}

QString GitWatcher::readHeadText(const QString& gitDir) {
  QFile f(gitDir + QStringLiteral("/HEAD"));
  if(!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return QString();
  }
  return QString::fromUtf8(f.readAll());
}

QString GitWatcher::readShaForBranch(const QString& gitDir, const QString& branch) {
  if(branch.isEmpty() || branch == QStringLiteral("(detached HEAD)")) {
    return QString();
  }
  {
    QFile f(gitDir + QStringLiteral("/refs/heads/") + branch);
    if(f.open(QIODevice::ReadOnly | QIODevice::Text)) {
      return QString::fromUtf8(f.readAll()).trimmed();
    }
  }
  QFile pr(gitDir + QStringLiteral("/packed-refs"));
  if(!pr.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return QString();
  }
  QTextStream ts(&pr);
  const QString needle = QStringLiteral(" refs/heads/") + branch;
  while(!ts.atEnd()) {
    const QString line = ts.readLine();
    if(line.startsWith('#') || line.startsWith('^')) {
      continue;
    }
    if(line.endsWith(needle)) {
      return line.left(line.indexOf(' '));
    }
  }
  return QString();
}

QString GitWatcher::upstreamForBranch(const QString& gitDir, const QString& branch) {
  if(branch.isEmpty() || branch == QStringLiteral("(detached HEAD)")) {
    return QString();
  }
  QFile f(gitDir + QStringLiteral("/config"));
  if(!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return QString();
  }
  QTextStream ts(&f);
  const QString header = QStringLiteral("[branch \"") + branch + QChar('"');
  bool inSection = false;
  QString remote;
  QString merge;
  while(!ts.atEnd()) {
    const QString line = ts.readLine().trimmed();
    if(line.startsWith('[')) {
      inSection = line.startsWith(header);
      continue;
    }
    if(!inSection) {
      continue;
    }
    if(line.startsWith(QStringLiteral("remote"))) {
      const int eq = line.indexOf('=');
      if(eq > 0) {
        remote = line.mid(eq + 1).trimmed();
      }
    } else if(line.startsWith(QStringLiteral("merge"))) {
      const int eq = line.indexOf('=');
      if(eq > 0) {
        merge = line.mid(eq + 1).trimmed();
      }
    }
  }
  if(remote.isEmpty() || merge.isEmpty()) {
    return QString();
  }
  QString mergeBranch = merge;
  const QString p = QStringLiteral("refs/heads/");
  if(mergeBranch.startsWith(p)) {
    mergeBranch = mergeBranch.mid(p.size());
  }
  return remote + QChar('/') + mergeBranch;
}

void GitWatcher::recomputeForRepo(const QString& path) {
  auto cit = m_configs.constFind(path);
  if(cit == m_configs.constEnd()) {
    return;
  }
  const RepoConfig& cfg = *cit;

  const QString headText = readHeadText(cfg.resolvedGitDir);
  const QString branch = BranchTaskMatcher::branchFromHeadText(headText);
  const QString sha = readShaForBranch(cfg.commonGitDir, branch);

  RepoState& st = m_state[path];
  const QString oldBranch = st.branch;
  const QString oldSha = st.headSha;
  if(oldBranch == branch && oldSha == sha) {
    return;
  }

  st.branch = branch;
  st.headSha = sha;
  st.upstream = upstreamForBranch(cfg.commonGitDir, branch);

  const bool branchActuallyChanged = (oldBranch != branch);
  if(branchActuallyChanged) {
    // Reset ahead/behind until rev-list returns.
    st.ahead = 0;
    st.behind = 0;

    const auto mr = m_matcher.extract(branch);
    const QString taskId = mr.matched ? mr.taskId : QString();
    m_lastRepo = path;
    m_lastBranch = branch;
    m_lastTaskId = taskId;
    emit branchChanged(path, branch, taskId);
  }

  emit repoStateUpdated(path, st.toVariant());

  if(branchActuallyChanged) {
    if(!m_gitPath.isEmpty()) {
      fetchAheadBehindAsync(path, branch);
    }
    if(m_prEnabled && (!m_ghPath.isEmpty() || !m_glabPath.isEmpty())) {
      fetchPrAsync(path, branch, /*emitOneShot=*/false);
    }
  }
  // HEAD moved (branch and/or SHA) → recent commit↔task links may have
  // changed. Refresh them regardless of whether the branch name changed.
  if(!m_gitPath.isEmpty()) {
    fetchCommitsAsync(path);
  }
}

void GitWatcher::fetchCommitsAsync(const QString& repoPath) {
  if(m_gitPath.isEmpty()) {
    return;
  }
  const QString key = QStringLiteral("log:") + repoPath;
  if(m_inflight.contains(key) && m_inflight.value(key)) {
    return;
  }

  auto* p = new QProcess(this);
  m_inflight.insert(key, p);
  p->setWorkingDirectory(repoPath);
  p->setProgram(m_gitPath);
  p->setArguments({QStringLiteral("log"),
                   QStringLiteral("--all"),
                   QStringLiteral("--no-color"),
                   QStringLiteral("--max-count=200"),
                   // The commit time rides along as a third field, for the
                   // safety net's "no sign of life" (APP-157).
                   QStringLiteral("--pretty=format:%H%x1f%s%x1f%cI")});
  connect(p, &QProcess::finished, this, [this, p, key, repoPath](int code, QProcess::ExitStatus) {
    m_inflight.remove(key);
    if(code == 0) {
      const QVariantMap byTask = m_matcher.groupCommitsByTask(p->readAllStandardOutput());
      emit commitsUpdated(repoPath, byTask);
    }
    p->deleteLater();
  });
  p->start();
}

bool GitWatcher::createBranch(const QString& repoPath, const QString& branchName, QString* errorOut) {
  const auto fail = [&](const QString& e) {
    if(errorOut) {
      *errorOut = e;
    }
    emit branchCreated(repoPath, branchName, false, e);
    return false;
  };
  if(m_gitPath.isEmpty()) {
    return fail(QStringLiteral("git not found on PATH"));
  }
  if(repoPath.isEmpty()) {
    return fail(QStringLiteral("no repository selected"));
  }
  if(branchName.isEmpty()) {
    return fail(QStringLiteral("empty branch name"));
  }

  // Asynchronous on purpose. `git checkout -b` is fast on a warm repository
  // and not at all fast on a cold or very large one, and waiting for it here
  // froze the window — this was the only blocking process call in heap.
  auto* process = new QProcess(this);
  process->setWorkingDirectory(repoPath);
  process->setProgram(m_gitPath);
  process->setArguments({QStringLiteral("checkout"), QStringLiteral("-b"), branchName});

  // A checkout that never returns must not leave the user without an answer.
  auto* timeout = new QTimer(process);
  timeout->setSingleShot(true);
  timeout->setInterval(30000);
  connect(timeout, &QTimer::timeout, process, [process]() {
    if(process->state() != QProcess::NotRunning) {
      process->kill();
    }
  });

  connect(process, &QProcess::finished, this, [this, process, repoPath, branchName](int exitCode, QProcess::ExitStatus status) {
    process->deleteLater();
    if(status != QProcess::NormalExit || exitCode != 0) {
      QString err = QString::fromUtf8(process->readAllStandardError()).trimmed();
      if(err.isEmpty()) {
        err = QStringLiteral("git checkout -b failed");
      }
      emit branchCreated(repoPath, branchName, false, err);
      return;
    }
    // Reflect the new checkout immediately (the FS watcher would catch
    // up too, but an explicit recompute makes the banner update
    // deterministic).
    const QString abs = QDir(repoPath).absolutePath();
    if(m_configs.contains(abs)) {
      rewatchFiles(m_configs.value(abs));
      recomputeForRepo(abs);
    }
    emit branchCreated(repoPath, branchName, true, QString());
  });
  connect(process, &QProcess::errorOccurred, this, [this, process, repoPath, branchName](QProcess::ProcessError) {
    if(process->state() == QProcess::NotRunning) {
      emit branchCreated(repoPath, branchName, false, QStringLiteral("failed to start git"));
    }
  });

  process->start();
  timeout->start();
  return true;
}

void GitWatcher::runGitAsync(const QString& repoPath, const QStringList& args, const std::function<void(int, const QByteArray&)>& done) {
  auto* p = new QProcess(this);
  p->setWorkingDirectory(repoPath);
  p->setProgram(m_gitPath);
  p->setArguments(args);
  auto* timeout = new QTimer(p);
  timeout->setSingleShot(true);
  timeout->setInterval(15000);
  connect(timeout, &QTimer::timeout, p, [p]() {
    if(p->state() != QProcess::NotRunning) {
      p->kill();
    }
  });
  connect(p, &QProcess::finished, this, [p, done](int code, QProcess::ExitStatus status) {
    p->deleteLater();
    done(status == QProcess::NormalExit ? code : -1, p->readAllStandardOutput());
  });
  connect(p, &QProcess::errorOccurred, this, [p, done](QProcess::ProcessError error) {
    // A process that never started emits no finished(); every other error
    // is followed by one.
    if(error == QProcess::FailedToStart) {
      p->deleteLater();
      done(-1, {});
    }
  });
  p->start();
  timeout->start();
}

void GitWatcher::checkWorkingTree(const QString& repoPath) {
  if(m_gitPath.isEmpty() || repoPath.isEmpty()) {
    emit workingTreeChecked(repoPath, 0, 0, false);
    return;
  }
  const QString key = QStringLiteral("wt:") + repoPath;
  if(m_workingTreeChecks.contains(key)) {
    return;  // the answer to the first request answers this one too
  }
  m_workingTreeChecks.insert(key);
  runGitAsync(repoPath, {QStringLiteral("status"), QStringLiteral("--porcelain")}, [this, repoPath, key](int code, const QByteArray& out) {
    if(code != 0) {
      m_workingTreeChecks.remove(key);
      emit workingTreeChecked(repoPath, 0, 0, false);
      return;
    }
    const int changed = heap::safety::countPorcelainEntries(out);
    runGitAsync(repoPath,
                {QStringLiteral("stash"), QStringLiteral("list")},
                [this, repoPath, key, changed](int stashCode, const QByteArray& stashOut) {
                  m_workingTreeChecks.remove(key);
                  emit workingTreeChecked(repoPath, changed, stashCode == 0 ? heap::safety::countStashEntries(stashOut) : 0, true);
                });
  });
}

void GitWatcher::fetchAheadBehindAsync(const QString& repoPath, const QString& branch) {
  if(branch.isEmpty() || branch == QStringLiteral("(detached HEAD)")) {
    return;
  }
  const RepoState& st = m_state.value(repoPath);
  if(st.upstream.isEmpty()) {
    return;
  }

  const QString key = QStringLiteral("ab:") + cacheKey(repoPath, branch);
  if(m_inflight.contains(key) && m_inflight.value(key)) {
    return;
  }

  auto* p = new QProcess(this);
  m_inflight.insert(key, p);
  p->setWorkingDirectory(repoPath);
  p->setProgram(m_gitPath);
  p->setArguments({QStringLiteral("rev-list"),
                   QStringLiteral("--left-right"),
                   QStringLiteral("--count"),
                   branch + QStringLiteral("...") + st.upstream});
  connect(p, &QProcess::finished, this, [this, p, key, repoPath, branch](int code, QProcess::ExitStatus) {
    m_inflight.remove(key);
    const auto sit = m_state.find(repoPath);
    if(sit == m_state.end() || sit->branch != branch) {
      p->deleteLater();
      return;
    }
    if(code == 0) {
      const QString out = QString::fromUtf8(p->readAllStandardOutput()).trimmed();
      const QStringList parts = out.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
      if(parts.size() == 2) {
        sit->ahead = parts[0].toInt();
        sit->behind = parts[1].toInt();
      }
    }
    emit repoStateUpdated(repoPath, sit->toVariant());
    p->deleteLater();
  });
  p->start();
}

void GitWatcher::fetchPrAsync(const QString& repoPath, const QString& branch, bool emitOneShot) {
  if(branch.isEmpty() || branch == QStringLiteral("(detached HEAD)")) {
    return;
  }

  const QString key = QStringLiteral("pr:") + cacheKey(repoPath, branch);
  if(m_inflight.contains(key) && m_inflight.value(key)) {
    return;
  }

  QString tool = m_ghPath;
  QStringList args;
  bool glab = false;
  if(!tool.isEmpty()) {
    args = {QStringLiteral("pr"), QStringLiteral("view"), QStringLiteral("--json"), ghPrJsonFields(), branch};
  } else if(!m_glabPath.isEmpty()) {
    tool = m_glabPath;
    glab = true;
    args = {QStringLiteral("mr"), QStringLiteral("view"), QStringLiteral("--output"), QStringLiteral("json"), branch};
  } else {
    return;
  }
  // Whose move it is needs to know who "me" is: asked once, the first time a
  // PR is looked at, so a setup with no watched repo never runs the tool.
  fetchLoginAsync(repoPath, glab ? m_glabPath : m_ghPath, glab);

  auto* p = new QProcess(this);
  m_inflight.insert(key, p);
  p->setWorkingDirectory(repoPath);
  p->setProgram(tool);
  p->setArguments(args);
  connect(p, &QProcess::finished, this, [this, p, key, repoPath, branch, emitOneShot, glab](int code, QProcess::ExitStatus) {
    m_inflight.remove(key);
    PrInfo info;
    if(code == 0) {
      info = parsePrJson(p->readAllStandardOutput(), glab);
    }
    info.fetchedAt = QDateTime::currentDateTime();
    applyMove(info);
    CacheEntry& ce = m_prCache[cacheKey(repoPath, branch)];
    ce.info = info;
    ce.age.start();

    const auto sit = m_state.find(repoPath);
    if(sit != m_state.end() && sit->branch == branch) {
      sit->pr = info;
      emit repoStateUpdated(repoPath, sit->toVariant());
    }
    if(emitOneShot) {
      emit prInfoUpdated(repoPath, branch, info.toVariant());
    }
    p->deleteLater();
  });
  p->start();
}

void GitWatcher::applyMove(PrInfo& info) const {
  const MoveVerdict v = whoseMove(info, m_myLogin);
  info.move = moveName(v.move);
  info.moveReason = v.reason;
}

void GitWatcher::fetchLoginAsync(const QString& workDir, const QString& tool, bool glab) {
  if(m_loginAsked || tool.isEmpty()) {
    return;
  }
  m_loginAsked = true;
  auto* p = new QProcess(this);
  p->setWorkingDirectory(workDir);
  p->setProgram(tool);
  p->setArguments(glab ? QStringList{QStringLiteral("api"), QStringLiteral("user")}
                       : QStringList{QStringLiteral("api"), QStringLiteral("user"), QStringLiteral("--jq"), QStringLiteral(".login")});
  connect(p, &QProcess::finished, this, [this, p, glab](int code, QProcess::ExitStatus) {
    p->deleteLater();
    if(code == 0) {
      setMyLogin(parseLogin(p->readAllStandardOutput(), glab));
    }
  });
  p->start();
}

void GitWatcher::setMyLogin(const QString& login) {
  if(login == m_myLogin) {
    return;
  }
  m_myLogin = login;
  // PRs read before the answer came back said nothing about whose move it
  // is: read them again against the login, without asking the tool again.
  for(auto it = m_prCache.begin(); it != m_prCache.end(); ++it) {
    applyMove(it->info);
    emit prInfoUpdated(it.key().section(QChar('\n'), 0, 0), it.key().section(QChar('\n'), 1), it->info.toVariant());
  }
  for(auto it = m_state.begin(); it != m_state.end(); ++it) {
    if(it->pr.state.isEmpty()) {
      continue;
    }
    applyMove(it->pr);
    emit repoStateUpdated(it.key(), it->toVariant());
  }
}

void GitWatcher::requestPrFetch(const QString& repoPath, const QString& branch) {
  if(repoPath.isEmpty() || branch.isEmpty()) {
    return;
  }
  const QString key = cacheKey(repoPath, branch);
  auto it = m_prCache.constFind(key);
  if(it != m_prCache.constEnd() && it->age.isValid() && it->age.elapsed() < kPrTtlMs) {
    emit prInfoUpdated(repoPath, branch, it->info.toVariant());
    return;
  }
  if(m_ghPath.isEmpty() && m_glabPath.isEmpty()) {
    return;
  }
  fetchPrAsync(repoPath, branch, /*emitOneShot=*/true);
}

}  // namespace heap::git
