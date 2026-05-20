#pragma once

#include <QDateTime>
#include <QString>
#include <QVariantMap>

namespace heap::git {

struct RepoConfig {
    QString path;            // worktree root (absolute)
    QString resolvedGitDir;  // <repo>/.git OR worktree gitdir target
};

struct PrInfo {
    QString   state;         // "open" | "draft" | "merged" | "closed" | ""
    int       number = 0;
    QString   url;
    QString   title;
    QDateTime fetchedAt;

    QVariantMap toVariant() const {
        QVariantMap m;
        m["state"]     = state;
        m["number"]    = number;
        m["url"]       = url;
        m["title"]     = title;
        m["fetchedAt"] = fetchedAt;
        return m;
    }
};

struct RepoState {
    QString repoPath;
    QString branch;          // "" if unset; "(detached HEAD)" if detached
    QString headSha;
    QString upstream;        // "origin/main" if known
    int     ahead  = 0;
    int     behind = 0;
    PrInfo  pr;

    QVariantMap toVariant() const {
        QVariantMap m;
        m["repoPath"] = repoPath;
        m["branch"]   = branch;
        m["headSha"]  = headSha;
        m["upstream"] = upstream;
        m["ahead"]    = ahead;
        m["behind"]   = behind;
        m["pr"]       = pr.toVariant();
        return m;
    }
};

} // namespace heap::git
