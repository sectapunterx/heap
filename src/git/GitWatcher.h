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

namespace heap::git {

class GitWatcher : public QObject {
    Q_OBJECT
public:
    explicit GitWatcher(QObject *parent = nullptr);
    ~GitWatcher() override;

    void setWatchedRepos(const QStringList &paths);
    void setPrefixes(const QStringList &prefixes);
    void setPrFetchEnabled(bool on);

    QStringList watchedRepos() const;
    QVariantMap snapshot() const;

    QString lastTaskId() const { return m_lastTaskId; }
    QString lastBranch() const { return m_lastBranch; }
    QString lastRepo()   const { return m_lastRepo;   }

    void requestPrFetch(const QString &repoPath, const QString &branch);

signals:
    void branchChanged(const QString &repoPath,
                       const QString &branch,
                       const QString &taskId);
    void repoStateUpdated(const QString &repoPath, const QVariantMap &state);
    void prInfoUpdated(const QString &repoPath,
                       const QString &branch,
                       const QVariantMap &pr);

private slots:
    void onFsPathChanged(const QString &path);
    void onDebounceFired();

private:
    QFileSystemWatcher *m_fsw{};
    QTimer             *m_debounce{};
    QSet<QString>       m_pendingRepos;

    QHash<QString, RepoConfig> m_configs;        // repoPath → config
    QHash<QString, RepoState>  m_state;          // repoPath → state
    QHash<QString, QString>    m_watchedFileOwner; // file path → repoPath

    QString m_lastRepo, m_lastBranch, m_lastTaskId;

    struct CacheEntry { PrInfo info; QElapsedTimer age; };
    QHash<QString, CacheEntry> m_prCache;        // key = repo + '\n' + branch
    static constexpr qint64 kPrTtlMs = 60'000;

    QHash<QString, QPointer<QProcess>> m_inflight; // dedup spawns by key

    QString m_ghPath, m_glabPath, m_gitPath;
    bool    m_prEnabled = true;

    BranchTaskMatcher m_matcher;

    void addRepo(const QString &path);
    void removeRepo(const QString &path);
    void rewatchFiles(const RepoConfig &cfg);
    void recomputeForRepo(const QString &path);
    void fetchAheadBehindAsync(const QString &repoPath, const QString &branch);
    void fetchPrAsync(const QString &repoPath,
                      const QString &branch,
                      bool emitOneShot);

    static QString cacheKey(const QString &repo, const QString &branch);
    static QString upstreamForBranch(const QString &gitDir,
                                     const QString &branch);
    static QString readHeadText(const QString &gitDir);
    static QString readShaForBranch(const QString &gitDir,
                                    const QString &branch);
};

} // namespace heap::git
