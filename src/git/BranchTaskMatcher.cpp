#include "BranchTaskMatcher.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>

namespace heap::git {

BranchTaskMatcher::BranchTaskMatcher(QStringList prefixes)
    : m_prefixes(std::move(prefixes)),
      m_loneDigitsRx(QStringLiteral("(?:^|[-/_])(\\d{3,7})(?:[-/_]|$)"))
{
    rebuildRegexes();
}

void BranchTaskMatcher::setPrefixes(QStringList prefixes) {
    m_prefixes = std::move(prefixes);
    rebuildRegexes();
}

void BranchTaskMatcher::rebuildRegexes() {
    m_prefixRx.clear();
    m_prefixRx.reserve(m_prefixes.size());
    for (const QString &raw : m_prefixes) {
        const QString p = raw.trimmed();
        if (p.isEmpty()) continue;
        // (?:^|[-/_]) <PREFIX>-<digits> (?:[-/_]|$), case-insensitive
        QRegularExpression rx(
            QStringLiteral("(?:^|[-/_])(") + QRegularExpression::escape(p)
                + QStringLiteral(")-(\\d+)(?:[-/_]|$)"),
            QRegularExpression::CaseInsensitiveOption);
        m_prefixRx.push_back(rx);
    }
}

MatchResult BranchTaskMatcher::extract(const QString &branch) const {
    MatchResult out;
    if (branch.isEmpty() || branch == QStringLiteral("(detached HEAD)"))
        return out;
    if (m_prefixes.isEmpty()) return out;

    // Rule 1: explicit "<prefix>-<digits>" anywhere (case-insensitive).
    for (int i = 0; i < m_prefixRx.size(); ++i) {
        const auto m = m_prefixRx.at(i).match(branch);
        if (m.hasMatch()) {
            const QString prefix = m_prefixes.at(i).trimmed().toUpper();
            const int     n      = m.captured(2).toInt();
            out.matchedPrefix    = prefix;
            out.numericPart      = n;
            out.taskId           = prefix + QChar('-') + QString::number(n);
            out.matched          = true;
            return out;
        }
    }

    // Rule 2: numeric-only fallback — only if exactly one registered prefix.
    QStringList nonEmpty;
    for (const QString &p : m_prefixes)
        if (!p.trimmed().isEmpty()) nonEmpty << p.trimmed();
    if (nonEmpty.size() != 1) return out;

    const auto dm = m_loneDigitsRx.match(branch);
    if (!dm.hasMatch()) return out;
    const QString prefix = nonEmpty.first().toUpper();
    const int     n      = dm.captured(1).toInt();
    out.matchedPrefix    = prefix;
    out.numericPart      = n;
    out.taskId           = prefix + QChar('-') + QString::number(n);
    out.matched          = true;
    return out;
}

QString BranchTaskMatcher::branchFromHeadText(QStringView headFileContents) {
    QString t = headFileContents.trimmed().toString();
    static const QString kRef = QStringLiteral("ref: refs/heads/");
    if (t.startsWith(kRef)) return t.mid(kRef.size());
    static const QRegularExpression rxSha(QStringLiteral("^[0-9a-fA-F]{40}$"));
    if (rxSha.match(t).hasMatch())
        return QStringLiteral("(detached HEAD)");
    return QString();
}

QString BranchTaskMatcher::resolveGitDir(const QString &repoPath) {
    if (repoPath.isEmpty()) return QString();
    QFileInfo gi(QDir(repoPath).filePath(QStringLiteral(".git")));
    if (gi.isDir()) return gi.absoluteFilePath();
    if (gi.isFile()) {
        QFile f(gi.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return QString();
        const QString line = QString::fromUtf8(f.readLine()).trimmed();
        static const QString kPrefix = QStringLiteral("gitdir:");
        if (!line.startsWith(kPrefix)) return QString();
        QString p = line.mid(kPrefix.size()).trimmed();
        if (p.isEmpty()) return QString();
        QFileInfo pi(p);
        if (pi.isAbsolute()) return QDir::cleanPath(pi.absoluteFilePath());
        return QDir::cleanPath(QDir(repoPath).absoluteFilePath(p));
    }
    return QString();
}

} // namespace heap::git
