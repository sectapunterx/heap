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
  QString providerId;   // "jira" | "github" | "gitlab"
  QString externalId;   // Jira "PROJ-123", GH issue number as string
  QString url;
  QString title;
  QString body;
  QString status;       // provider-native status (map with StatusMap on use)
  QString priority;     // provider-native priority (map with StatusMap on use)
  QStringList labels;
  QDateTime updatedAt;
  QHash<QString, QString> extra;  // provider-specific fields
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
