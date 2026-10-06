#include "git/BranchTaskMatcher.h"
#include "git/BranchTaskResolve.h"

#include <QRegularExpression>

#include <algorithm>

namespace heap::git {

QStringList branchPrefixes(const QString& idPrefix, const QVector<Task>& tasks) {
  QStringList out;
  const QString def = idPrefix.trimmed().toUpper();
  if(!def.isEmpty()) {
    out << def;
  }
  // A mirrored issue's branch is named after the tracker's key ("PROJ-123"),
  // never after the heap id the merge invented for it ("jira-PROJ-123"). Unless
  // the project keys in play are registered here, such a branch cannot match
  // its own ticket — and, with a single local prefix, the digits-only fallback
  // used to answer with a different task entirely.
  static const QRegularExpression keyStem(QStringLiteral("^([A-Za-z][A-Za-z0-9]*)-\\d+$"));
  for(const Task& t : tasks) {
    if(t.externalId.isEmpty()) {
      continue;
    }
    const QRegularExpressionMatch m = keyStem.match(externalKeyOf(t));
    if(!m.hasMatch()) {
      continue;  // a bare issue number has no key to register
    }
    const QString stem = m.captured(1).toUpper();
    if(!out.contains(stem)) {
      out << stem;
    }
  }
  return out;
}

QString taskIdForBranchMatch(const QString& matchedId, const QVector<Task>& tasks) {
  if(matchedId.isEmpty()) {
    return {};
  }
  // Rule 1 answers with the key it found in the branch. For a local task that
  // is already the task id; for a mirrored issue the id is prefixed with the
  // provider, so resolve through the tracker key instead.
  const bool local = std::any_of(tasks.cbegin(), tasks.cend(), [&matchedId](const Task& t) {
    return t.id == matchedId;
  });
  if(local) {
    return matchedId;
  }
  for(const Task& t : tasks) {
    if(!t.externalId.isEmpty() && externalKeyOf(t).compare(matchedId, Qt::CaseInsensitive) == 0) {
      return t.id;
    }
  }
  return matchedId;
}

QString taskIdForBranch(const QString& branch, const QString& idPrefix, const QVector<Task>& tasks) {
  if(branch.isEmpty() || branch == QLatin1String("HEAD") || branch == QLatin1String("(detached HEAD)")) {
    return {};
  }
  const BranchTaskMatcher matcher(branchPrefixes(idPrefix, tasks));
  const MatchResult mr = matcher.extract(branch);
  if(!mr.matched) {
    return {};
  }
  const QString id = taskIdForBranchMatch(mr.taskId, tasks);
  const bool exists = std::any_of(tasks.cbegin(), tasks.cend(), [&id](const Task& t) {
    return t.id == id;
  });
  return exists ? id : QString();
}

}  // namespace heap::git
