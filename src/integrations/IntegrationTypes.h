#pragma once

#include <QDateTime>
#include <QHash>
#include <QString>
#include <QStringList>

namespace heap::integrations {

// A task pulled from an external tracker (Jira / GitHub / GitLab). Kept as a
// plain value type — no QObject — so it can be serialized, compared and unit-
// tested without an event loop.
struct ExternalTask {
  QString providerId;  // "jira" | "github" | "gitlab"
  QString externalId;  // Jira "PROJ-123", GH issue number as string
  QString url;
  QString title;
  QString body;
  QString status;    // provider-native status (map with StatusMap on use)
  QString priority;  // provider-native priority (map with StatusMap on use)
  QStringList labels;
  QDateTime updatedAt;
  QHash<QString, QString> extra;  // provider-specific fields
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
