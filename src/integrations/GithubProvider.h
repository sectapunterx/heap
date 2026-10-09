#pragma once

#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QString>
#include <QVector>

namespace heap::integrations {

// GitHub tracker sync (HEAP-74) is driven by the generic RestIssueProvider from
// a ProviderDescriptor; only the pure, unit-tested helpers live here now.

// Parse a GitHub "list issues" JSON array into ExternalTasks. Pull requests
// (issues carrying a "pull_request" node) are skipped — the issues endpoint
// returns both. Pure, no network — unit-tested with canned JSON.
QVector<ExternalTask> parseGithubIssues(const QByteArray& json);

// Parse pull requests (APP-242): a search answer ({"items": [...]}) or a
// pulls list (an array). externalId is the PR number; status is "PR open" /
// "PR draft" / "PR merged" / "PR closed"; branches, reviewers and the issues it
// closes go to `details`. Entries that are not pull requests are skipped.
// Pure, no network.
QVector<ExternalTask> parseGithubPulls(const QByteArray& json);

// Push-direction inverse of StatusMap: a heap column → the GitHub issue state.
// Only "done" closes an issue; every other column (re)opens it.
QString githubStateForColumn(const QString& column);

}  // namespace heap::integrations
