#pragma once

#include "integrations/IntegrationTypes.h"

#include <QObject>
#include <QString>
#include <QVector>

namespace heap::integrations {

// Abstract interface every tracker connector (Jira / GitHub / GitLab) will
// implement. Defined now as the foundation for the post-release two-way sync;
// concrete providers, the OAuth flow, the SecretStore and the SyncScheduler
// land in follow-up work. All operations are async — results arrive via the
// signals so the UI thread never blocks on the network.
class IntegrationProvider : public QObject {
  Q_OBJECT
 public:
  ~IntegrationProvider() override = default;

  virtual QString id() const = 0;           // "jira" | "github" | "gitlab"
  virtual QString displayName() const = 0;

  // Validate credentials. Emits connectionTested.
  virtual void testConnection() = 0;
  // Pull external tasks matching the configured filter. Emits tasksFetched.
  virtual void pullTasks() = 0;
  // Push a local status change back to the tracker. Emits taskPushed.
  virtual void pushStatusChange(const QString& externalId, const QString& newStatus) = 0;

 signals:
  void connectionTested(bool ok, const QString& error);
  void tasksFetched(const QVector<ExternalTask>& tasks);
  void taskPushed(const QString& externalId, bool ok, const QString& error);

 protected:
  using QObject::QObject;
};

}  // namespace heap::integrations
