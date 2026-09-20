#pragma once

#include <QDateTime>
#include <QHash>
#include <QString>
#include <QStringList>

namespace heap::integrations {

// A task pulled from an external tracker (any of the providers in
// ProviderRegistry). Kept as a plain value type — no QObject — so it can be
// serialized, compared and unit-tested without an event loop.
struct ExternalTask {
  QString providerId;  // "jira" | "github" | "gitlab" | …
  QString externalId;  // Jira "PROJ-123", GH issue number as string
  QString url;
  QString title;
  QString body;
  QString status;    // provider-native status (map with StatusMap on use)
  QString priority;  // provider-native priority (map with StatusMap on use)
  QStringList labels;
  QDateTime updatedAt;
  // Identity and context the trackers hand out alongside the issue (HEAP-117).
  // Every one of these is optional: a provider that does not expose a field, or
  // an issue that has none, leaves it default.
  QString assignee;  // display name / handle of the current owner
  QString author;    // who reported it
  QDateTime dueAt;   // tracker-side due date, local time
  bool dueHasTime = false;
  QDateTime createdAt;
  int commentCount = -1;  // -1 = the provider did not say
  QString issueType;      // "Bug" | "task" | Sentry level | …
  // Which project/repo the issue belongs to: "owner/name" for the git forges,
  // the project key for Jira, a list/project name elsewhere. Needed to tell two
  // issues that share a number apart when pulling across projects.
  QString project;
  QString milestone;                    // milestone / fix version / iteration
  QHash<QString, QString> labelColors;  // label name → "#rrggbb"
  // True when this issue came from the provider's "assigned to me" endpoint,
  // which spans projects — so its externalId is only unique within its project
  // and it must never be written back through the configured-project path.
  bool crossProject = false;
};

// A person pulled from a chat/directory integration (Mattermost). Separate from
// ExternalTask because nothing about it is issue-shaped: there is no status to
// map to a column and nothing to push back. Also a plain value type.
struct ExternalContact {
  QString providerId;    // "mattermost"
  QString externalId;    // the provider's stable user id
  QString username;      // the @handle, as typed in chat
  QString displayName;   // full name, nickname, or the username as a last resort
  QString position;      // the job title the person set on their own profile
  QString role;          // what heap shows when there is no position: "System admin", "Member", …
  QString channelLabel;  // where we met them: "@pavel", "#backend"
  QString email;
  bool isBot = false;
  bool deactivated = false;
};

// Outcome of one sync cycle for a provider.
struct SyncResult {
  int pulled = 0;
  int pushed = 0;
  QStringList errors;

  bool ok() const {
    return errors.isEmpty();
  }
};

}  // namespace heap::integrations
