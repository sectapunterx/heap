#pragma once

#include "Models.h"

#include <QString>
#include <QStringList>
#include <QVector>

// Which task a git branch names, given a profile's tasks. Pure, so the running
// app (its focus banner and git badges) and `heap now` on the command line
// answer the same question the same way.
namespace heap::git {

// Task-id prefixes the branch matcher should recognise: the configured local
// one (`idPrefix`, uppercased), plus the project key of every mirrored issue
// in `tasks`.
QStringList branchPrefixes(const QString& idPrefix, const QVector<Task>& tasks);

// Turn what the matcher found in a branch name into a task id. For a local
// task the key IS the id; a mirrored issue's id carries the provider, so it is
// resolved through the tracker key instead. An unknown key comes back as is.
QString taskIdForBranchMatch(const QString& matchedId, const QVector<Task>& tasks);

// The id of the task `branch` names, or "" when it names none that exists.
QString taskIdForBranch(const QString& branch, const QString& idPrefix, const QVector<Task>& tasks);

}  // namespace heap::git
