#include "BranchTaskMatcher.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QVariantList>
#include <QVariantMap>

namespace heap::git {

BranchTaskMatcher::BranchTaskMatcher(QStringList prefixes) :
    m_prefixes(std::move(prefixes)), m_loneDigitsRx(QStringLiteral("(?:^|[-/_])(\\d{3,7})(?:[-/_]|$)")) {
  rebuildRegexes();
}

void BranchTaskMatcher::setPrefixes(QStringList prefixes) {
  m_prefixes = std::move(prefixes);
  rebuildRegexes();
}

void BranchTaskMatcher::rebuildRegexes() {
  m_prefixRx.clear();
  m_textRx.clear();
  m_prefixRx.reserve(m_prefixes.size());
  m_textRx.reserve(m_prefixes.size());
  for(const QString& raw : m_prefixes) {
    const QString p = raw.trimmed();
    if(p.isEmpty()) {
      continue;
    }
    // Branch names: (?:^|[-/_]) <PREFIX>-<digits> (?:[-/_]|$).
    const QRegularExpression rx(QStringLiteral("(?:^|[-/_])(") + QRegularExpression::escape(p) + QStringLiteral(")-(\\d+)(?:[-/_]|$)"),
                                QRegularExpression::CaseInsensitiveOption);
    m_prefixRx.push_back(rx);
    // Free text (commit subjects): word-boundary around the id so it is
    // caught amid prose ("fix HEAP-76: …") but not inside another token.
    const QRegularExpression tx(QStringLiteral("(?<![A-Za-z0-9])(") + QRegularExpression::escape(p) + QStringLiteral(")-(\\d+)(?![0-9])"),
                                QRegularExpression::CaseInsensitiveOption);
    m_textRx.push_back(tx);
  }
}

MatchResult BranchTaskMatcher::extract(const QString& branch) const {
  MatchResult out;
  if(branch.isEmpty() || branch == QStringLiteral("(detached HEAD)")) {
    return out;
  }
  if(m_prefixes.isEmpty()) {
    return out;
  }

  // Rule 1: explicit "<prefix>-<digits>" anywhere (case-insensitive).
  for(int i = 0; i < m_prefixRx.size(); ++i) {
    const auto m = m_prefixRx.at(i).match(branch);
    if(m.hasMatch()) {
      const QString prefix = m_prefixes.at(i).trimmed().toUpper();
      const int n = m.captured(2).toInt();
      out.matchedPrefix = prefix;
      out.numericPart = n;
      out.taskId = prefix + QChar('-') + QString::number(n);
      out.matched = true;
      return out;
    }
  }

  // Rule 2: numeric-only fallback — only if exactly one registered prefix.
  QStringList nonEmpty;
  for(const QString& p : m_prefixes) {
    if(!p.trimmed().isEmpty()) {
      nonEmpty << p.trimmed();
    }
  }
  if(nonEmpty.size() != 1) {
    return out;
  }

  const auto dm = m_loneDigitsRx.match(branch);
  if(!dm.hasMatch()) {
    return out;
  }
  const QString prefix = nonEmpty.first().toUpper();
  const int n = dm.captured(1).toInt();
  out.matchedPrefix = prefix;
  out.numericPart = n;
  out.taskId = prefix + QChar('-') + QString::number(n);
  out.matched = true;
  return out;
}

QVariantMap BranchTaskMatcher::groupCommitsByTask(const QByteArray& gitLogOutput) const {
  QVariantMap out;
  const QString text = QString::fromUtf8(gitLogOutput);
  const auto lines = text.split(QChar('\n'), Qt::SkipEmptyParts);
  for(const QString& line : lines) {
    const int sep = line.indexOf(QChar(0x1f));
    if(sep < 0) {
      continue;
    }
    const QString sha = line.left(sep).trimmed();
    const QString subject = line.mid(sep + 1).trimmed();
    if(sha.isEmpty()) {
      continue;
    }
    // Free-text match — the id can sit anywhere in the subject line.
    QString taskId;
    for(int i = 0; i < m_textRx.size(); ++i) {
      const auto m = m_textRx.at(i).match(subject);
      if(m.hasMatch()) {
        taskId = m_prefixes.at(i).trimmed().toUpper() + QChar('-') + QString::number(m.captured(2).toInt());
        break;
      }
    }
    if(taskId.isEmpty()) {
      continue;
    }
    QVariantList list = out.value(taskId).toList();
    if(list.size() >= 20) {
      continue;  // cap per task — cards show a few
    }
    QVariantMap commit;
    commit.insert(QStringLiteral("sha"), sha.left(7));
    commit.insert(QStringLiteral("subject"), subject);
    list.append(commit);
    out.insert(taskId, list);
  }
  return out;
}

QString BranchTaskMatcher::slugifyTitle(const QString& title) {
  QString s;
  s.reserve(title.size());
  bool lastDash = false;
  for(const QChar c : title.toLower()) {
    if(c.isLetterOrNumber()) {
      s.append(c);
      lastDash = false;
    } else if(!s.isEmpty() && !lastDash) {
      s.append(QChar('-'));
      lastDash = true;
    }
  }
  while(s.endsWith(QChar('-'))) {
    s.chop(1);
  }
  constexpr int kMaxSlug = 40;
  if(s.size() > kMaxSlug) {
    s = s.left(kMaxSlug);
    while(s.endsWith(QChar('-'))) {
      s.chop(1);
    }
  }
  return s;
}

QString BranchTaskMatcher::branchNameForTask(const QString& taskId, const QString& title, const QString& templ) {
  QString t = templ.trimmed();
  if(t.isEmpty()) {
    t = QStringLiteral("feature/{id}-{slug}");
  }
  const QString slug = slugifyTitle(title);
  t.replace(QStringLiteral("{type}"), QStringLiteral("feature"));
  t.replace(QStringLiteral("{id}"), taskId.trimmed().toLower());
  t.replace(QStringLiteral("{slug}"), slug);
  // A missing slug/id can leave a dangling separator — trim it.
  while(t.endsWith(QChar('-')) || t.endsWith(QChar('/'))) {
    t.chop(1);
  }
  return t;
}

QString BranchTaskMatcher::branchFromHeadText(QStringView headFileContents) {
  const QString t = headFileContents.trimmed().toString();
  static const QString kRef = QStringLiteral("ref: refs/heads/");
  if(t.startsWith(kRef)) {
    return t.mid(kRef.size());
  }
  static const QRegularExpression rxSha(QStringLiteral("^[0-9a-fA-F]{40}$"));
  if(rxSha.match(t).hasMatch()) {
    return QStringLiteral("(detached HEAD)");
  }
  return QString();
}

QString BranchTaskMatcher::resolveGitDir(const QString& repoPath) {
  if(repoPath.isEmpty()) {
    return QString();
  }
  const QFileInfo gi(QDir(repoPath).filePath(QStringLiteral(".git")));
  if(gi.isDir()) {
    return gi.absoluteFilePath();
  }
  if(gi.isFile()) {
    QFile f(gi.absoluteFilePath());
    if(!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
      return QString();
    }
    const QString line = QString::fromUtf8(f.readLine()).trimmed();
    static const QString kPrefix = QStringLiteral("gitdir:");
    if(!line.startsWith(kPrefix)) {
      return QString();
    }
    const QString p = line.mid(kPrefix.size()).trimmed();
    if(p.isEmpty()) {
      return QString();
    }
    const QFileInfo pi(p);
    if(pi.isAbsolute()) {
      return QDir::cleanPath(pi.absoluteFilePath());
    }
    return QDir::cleanPath(QDir(repoPath).absoluteFilePath(p));
  }
  return QString();
}

}  // namespace heap::git
