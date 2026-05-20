#pragma once

#include <QRegularExpression>
#include <QString>
#include <QStringList>
#include <QStringView>
#include <QVector>

namespace heap::git {

struct MatchResult {
    QString taskId;          // e.g. "LTE-2398" (prefix uppercased)
    QString matchedPrefix;   // e.g. "LTE"
    int     numericPart = 0;
    bool    matched = false;
};

class BranchTaskMatcher {
public:
    explicit BranchTaskMatcher(QStringList prefixes = {});

    void setPrefixes(QStringList prefixes);
    const QStringList &prefixes() const noexcept { return m_prefixes; }

    MatchResult extract(const QString &branch) const;

    static QString branchFromHeadText(QStringView headFileContents);
    static QString resolveGitDir(const QString &repoPath);

private:
    QStringList                 m_prefixes;
    QVector<QRegularExpression> m_prefixRx;
    QRegularExpression          m_loneDigitsRx;

    void rebuildRegexes();
};

} // namespace heap::git
