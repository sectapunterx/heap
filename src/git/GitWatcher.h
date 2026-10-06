#pragma once

#include "BranchTaskMatcher.h"
#include "GitTypes.h"

#include <QElapsedTimer>
#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>

#include <functional>

namespace heap::git {

class GitWatcher : public QObject {
  Q_OBJECT
 public:
  explicit GitWatcher(QObject* parent = nullptr);
  ~GitWatcher() override;

  void setWatchedRepos(const QStringList& paths);
  void setPrefixes(const QStringList& prefixes);
  void setPrFetchEnabled(bool on);

  QStringList watchedRepos() const;
  QVariantMap snapshot() const;

  QString lastTaskId() const {
    return m_lastTaskId;
  }

  QString lastBranch() const {
    return m_lastBranch;
  }

  QString lastRepo() const {
    return m_lastRepo;
  }

  void requestPrFetch(const QString& repoPath, const QString& branch);
  // Recomputes every known PR's whose-move against `login`. Public so a test
  // can stand in for `gh api user`.
  void setMyLogin(const QString& login);

  // Create and switch to a new branch (`git checkout -b`).
  //
  // Asynchronous: the result arrives as branchCreated(). It used to block on
  // waitForFinished(15000), which meant a checkout against a cold or large
  // repository froze the whole window — this is the only place in heap that
  // ever waited on a process from the GUI thread.
  //
  // Returns false only when the request could not be started at all (no git
  // on PATH, no repository, empty name), in which case branchCreated() is
  // still emitted with the reason so one handler covers every outcome.
  bool createBranch(const QString& repoPath, const QString& branchName, QString* errorOut);

  // How much is not committed in `repoPath`: `git status --porcelain` and
  // `git stash list`, run asynchronously one after the other (APP-157). The
  // answer arrives as workingTreeChecked(); `ok` is false when git could not
  // be run or failed, and the counts are then zero.
  void checkWorkingTree(const QString& repoPath);

 signals:
  void branchChanged(const QString& repoPath, const QString& branch, const QString& taskId);
  void repoStateUpdated(const QString& repoPath, const QVariantMap& state);
  void prInfoUpdated(const QString& repoPath, const QString& branch, const QVariantMap& pr);
  // Recent commits mentioning a task id, grouped by task:
  // { taskId → [ {sha, subject}, … ] }. Refreshed whenever HEAD moves.
  void commitsUpdated(const QString& repoPath, const QVariantMap& commitsByTask);
  // The outcome of a createBranch() request. `error` is empty on success.
  void branchCreated(const QString& repoPath, const QString& branchName, bool ok, const QString& error);
  // The outcome of a checkWorkingTree() request.
  void workingTreeChecked(const QString& repoPath, int changedFiles, int stashes, bool ok);

 private slots:
  void onFsPathChanged(const QString& path);
  void onDebounceFired();

 private:
  QFileSystemWatcher* m_fsw{};
  QTimer* m_debounce{};
  QSet<QString> m_pendingRepos;

  QHash<QString, RepoConfig> m_configs;        // repoPath → config
  QHash<QString, RepoState> m_state;           // repoPath → state
  QHash<QString, QString> m_watchedFileOwner;  // file path → repoPath

  QString m_lastRepo, m_lastBranch, m_lastTaskId;

  struct CacheEntry {
    PrInfo info;
    QElapsedTimer age;
  };

  QHash<QString, CacheEntry> m_prCache;  // key = repo + '\n' + branch
  static constexpr qint64 kPrTtlMs = 60'000;

  QHash<QString, QPointer<QProcess>> m_inflight;  // dedup spawns by key
  QSet<QString> m_workingTreeChecks;              // checkWorkingTree() in flight

  QString m_ghPath, m_glabPath, m_gitPath;
  bool m_prEnabled = true;

  BranchTaskMatcher m_matcher;

  void addRepo(const QString& path);
  void removeRepo(const QString& path);
  void rewatchFiles(const RepoConfig& cfg);
  void recomputeForRepo(const QString& path);
  void fetchAheadBehindAsync(const QString& repoPath, const QString& branch);
  void fetchCommitsAsync(const QString& repoPath);
  void fetchPrAsync(const QString& repoPath, const QString& branch, bool emitOneShot);
  // One git command in `repoPath`, killed after 15 s; `done` gets the exit
  // code (-1 when it did not start or did not finish) and stdout.
  void runGitAsync(const QString& repoPath, const QStringList& args, const std::function<void(int, const QByteArray&)>& done);
  // Who the user is on the forge, for whose-move (APP-156). Asked once.
  void fetchLoginAsync(const QString& workDir, const QString& tool, bool glab);
  void applyMove(PrInfo& info) const;

  QString m_myLogin;
  bool m_loginAsked = false;

  static QString cacheKey(const QString& repo, const QString& branch);
  static QString readHeadText(const QString& gitDir);

 public:
  // Read from the COMMON git dir (see BranchTaskMatcher::resolveCommonDir):
  // a linked worktree keeps no refs or config of its own.
  static QString upstreamForBranch(const QString& commonGitDir, const QString& branch);
  static QString readShaForBranch(const QString& commonGitDir, const QString& branch);
};

}  // namespace heap::git
