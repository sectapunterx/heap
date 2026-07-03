#pragma once

#include <QRegularExpression>
#include <QString>
#include <QStringList>
#include <QStringView>
#include <QVariantMap>
#include <QVector>

namespace heap::git {

struct MatchResult {
  QString taskId;         // e.g. "LTE-2398" (prefix uppercased)
  QString matchedPrefix;  // e.g. "LTE"
  int numericPart = 0;
  bool matched = false;
};

class BranchTaskMatcher {
 public:
  explicit BranchTaskMatcher(QStringList prefixes = {});

  void setPrefixes(QStringList prefixes);

  const QStringList& prefixes() const noexcept {
    return m_prefixes;
  }

  MatchResult extract(const QString& branch) const;

  // Group commit subjects by the task id they mention. Input is the raw
  // output of `git log --pretty=format:%H%x1f%s` (SHA, unit-separator 0x1f,
  // subject; one commit per line). Returns { taskId → [ {sha, subject}, … ] }
  // where sha is the abbreviated (7-char) hash. Commits mentioning no known
  // task prefix are dropped. Pure/testable — no git I/O.
  QVariantMap groupCommitsByTask(const QByteArray& gitLogOutput) const;

  static QString branchFromHeadText(QStringView headFileContents);
  static QString resolveGitDir(const QString& repoPath);

  // Slug for a branch name: lowercased, non-alphanumerics collapsed to single
  // '-', trimmed of leading/trailing '-', capped to a sane length.
  static QString slugifyTitle(const QString& title);

  // Compose a branch name for a task from a template. Placeholders {id},
  // {slug} and {type} are substituted; an empty template falls back to
  // "feature/{id}-{slug}". {id} is lowercased for filesystem safety.
  static QString branchNameForTask(const QString& taskId, const QString& title, const QString& templ);

 private:
  QStringList m_prefixes;
  QVector<QRegularExpression> m_prefixRx;  // branch-name boundaries ([-/_])
  QVector<QRegularExpression> m_textRx;    // free-text boundaries (commits)
  QRegularExpression m_loneDigitsRx;

  void rebuildRegexes();
};

}  // namespace heap::git
