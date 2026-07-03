#include "GitWatcher.h"

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

namespace {

// Collapse GitHub's statusCheckRollup array into one CI verdict. Handles both
// CheckRun nodes (status QUEUED/IN_PROGRESS/COMPLETED + conclusion) and legacy
// StatusContext nodes (state SUCCESS/PENDING/FAILURE/ERROR). Any failure wins,
// then any pending, else passing; empty when there are no checks.
QString rollupChecks(const QJsonArray& arr) {
  if(arr.isEmpty()) {
    return QString();
  }
  bool anyFail = false;
  bool anyPending = false;
  bool anySuccess = false;
  for(const auto& v : arr) {
    const auto o = v.toObject();
    const QString status = o.value(QStringLiteral("status")).toString().toUpper();
    const QString state = o.value(QStringLiteral("state")).toString().toUpper();
    QString concl = o.value(QStringLiteral("conclusion")).toString().toUpper();
    if(!state.isEmpty()) {
      concl = state;  // StatusContext carries no conclusion
    }
    if(status == QLatin1String("QUEUED") || status == QLatin1String("IN_PROGRESS") || status == QLatin1String("PENDING") ||
       state == QLatin1String("PENDING") || state == QLatin1String("EXPECTED")) {
      anyPending = true;
    } else if(concl == QLatin1String("FAILURE") || concl == QLatin1String("ERROR") || concl == QLatin1String("CANCELLED") ||
              concl == QLatin1String("TIMED_OUT") || concl == QLatin1String("ACTION_REQUIRED")) {
      anyFail = true;
    } else if(concl == QLatin1String("SUCCESS") || concl == QLatin1String("NEUTRAL") || concl == QLatin1String("SKIPPED")) {
      anySuccess = true;
    }
  }
  if(anyFail) {
    return QStringLiteral("failing");
  }
  if(anyPending) {
    return QStringLiteral("pending");
  }
  if(anySuccess) {
    return QStringLiteral("passing");
  }
  return QString();
}

}  // namespace

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
  const RepoConfig cfg{.path = path, .resolvedGitDir = gitDir};
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
  const QString gitDir = it->resolvedGitDir;
  for(const QString& f : {QStringLiteral("HEAD"), QStringLiteral("packed-refs"), QStringLiteral("index")}) {
    const QString fp = gitDir + QChar('/') + f;
    m_fsw->removePath(fp);
    m_watchedFileOwner.remove(fp);
  }
  m_configs.erase(it);
  m_state.remove(path);
}

void GitWatcher::rewatchFiles(const RepoConfig& cfg) {
  for(const QString& f : {QStringLiteral("HEAD"), QStringLiteral("packed-refs"), QStringLiteral("index")}) {
    const QString fp = cfg.resolvedGitDir + QChar('/') + f;
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
  const QString refsHeads = cfg.resolvedGitDir + QStringLiteral("/refs/heads");
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
  const QString sha = readShaForBranch(cfg.resolvedGitDir, branch);

  RepoState& st = m_state[path];
  const QString oldBranch = st.branch;
  const QString oldSha = st.headSha;
  if(oldBranch == branch && oldSha == sha) {
    return;
  }

  st.branch = branch;
  st.headSha = sha;
  st.upstream = upstreamForBranch(cfg.resolvedGitDir, branch);

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
                   QStringLiteral("--pretty=format:%H%x1f%s")});
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
  const auto fail = [errorOut](const QString& e) {
    if(errorOut) {
      *errorOut = e;
    }
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

  QProcess p;
  p.setWorkingDirectory(repoPath);
  p.setProgram(m_gitPath);
  p.setArguments({QStringLiteral("checkout"), QStringLiteral("-b"), branchName});
  p.start();
  if(!p.waitForStarted(5000)) {
    return fail(QStringLiteral("failed to start git"));
  }
  if(!p.waitForFinished(15000)) {
    p.kill();
    return fail(QStringLiteral("git checkout timed out"));
  }
  if(p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
    QString err = QString::fromUtf8(p.readAllStandardError()).trimmed();
    if(err.isEmpty()) {
      err = QStringLiteral("git checkout -b failed");
    }
    return fail(err);
  }
  // Reflect the new checkout immediately (the FS watcher would catch up too,
  // but an explicit recompute makes the banner/card update deterministic).
  const QString abs = QDir(repoPath).absolutePath();
  if(m_configs.contains(abs)) {
    rewatchFiles(m_configs.value(abs));
    recomputeForRepo(abs);
  }
  return true;
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
  if(!tool.isEmpty()) {
    args = {QStringLiteral("pr"),
            QStringLiteral("view"),
            QStringLiteral("--json"),
            QStringLiteral("state,number,url,title,isDraft,statusCheckRollup"),
            branch};
  } else if(!m_glabPath.isEmpty()) {
    tool = m_glabPath;
    args = {QStringLiteral("mr"), QStringLiteral("view"), QStringLiteral("--output"), QStringLiteral("json"), branch};
  } else {
    return;
  }

  auto* p = new QProcess(this);
  m_inflight.insert(key, p);
  p->setWorkingDirectory(repoPath);
  p->setProgram(tool);
  p->setArguments(args);
  connect(p, &QProcess::finished, this, [this, p, key, repoPath, branch, emitOneShot](int code, QProcess::ExitStatus) {
    m_inflight.remove(key);
    PrInfo info;
    info.fetchedAt = QDateTime::currentDateTime();
    if(code == 0) {
      const QByteArray raw = p->readAllStandardOutput();
      QJsonParseError err{};
      const auto doc = QJsonDocument::fromJson(raw, &err);
      if(err.error == QJsonParseError::NoError && doc.isObject()) {
        const auto o = doc.object();
        info.state = o.value(QStringLiteral("state")).toString().toLower();
        info.number = o.value(QStringLiteral("number")).toInt();
        info.url = o.value(QStringLiteral("url")).toString();
        info.title = o.value(QStringLiteral("title")).toString();
        info.draft = o.value(QStringLiteral("isDraft")).toBool();
        info.checks = rollupChecks(o.value(QStringLiteral("statusCheckRollup")).toArray());
      }
    }
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
