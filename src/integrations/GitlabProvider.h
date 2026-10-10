#pragma once

#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QString>
#include <QVector>

namespace heap::integrations {

// GitLab tracker sync (HEAP-75) is driven by the generic RestIssueProvider from
// a ProviderDescriptor; only the pure, unit-tested helpers live here now.

// Parse a GitLab "list project issues" JSON array into ExternalTasks. Pure, no
// network — unit-tested with canned JSON. externalId is the issue `iid` (the
// per-project number), which is what the issues/{iid} endpoints expect.
QVector<ExternalTask> parseGitlabIssues(const QByteArray& json);

// Parse a GitLab "list merge requests" JSON array (APP-242). externalId is
// "!" + iid, so a merge request never takes the card of the issue with the
// same number; status is "MR open" / "MR draft" / "MR merged" / "MR closed";
// the branches, merge status, conflicts, pipeline, reviewers and the issues it
// closes go to `details`. Pure, no network.
QVector<ExternalTask> parseGitlabMergeRequests(const QByteArray& json);

// Push-direction map: a heap column → the GitLab `state_event` used to move the
// issue. "done" closes it; every other column reopens it.
QString gitlabStateEventForColumn(const QString& column);

}  // namespace heap::integrations
