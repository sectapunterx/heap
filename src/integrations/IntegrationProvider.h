#pragma once

#include "integrations/IntegrationTypes.h"

#include <QHash>
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

  virtual QString id() const = 0;  // "jira" | "github" | "gitlab"
  virtual QString displayName() const = 0;

  // Validate credentials. Emits connectionTested.
  virtual void testConnection() = 0;
  // Pull external tasks matching the configured filter. Emits tasksFetched.
  virtual void pullTasks() = 0;
  // Push a local status change back to the tracker. Emits taskPushed. `project`
  // is the issue's own repo/project, when known: it is written back there, not
  // to the configured one, which may since point somewhere else.
  virtual void pushStatusChange(const QString& externalId, const QString& newStatus, const QString& project) = 0;

  // Read one issue's most recent comments (HEAP-117). `project` is the issue's
  // own repo/project, which in a cross-project pull is not the configured one.
  // Always answers commentsFetched, including with an error. The default says
  // "unsupported" so a provider that has no comment endpoint needs no code.
  virtual void fetchComments(const QString& externalId, const QString& /*project*/) {
    emit commentsFetched(externalId, {}, QStringLiteral("unsupported"));
  }

  // Every status the tracker's workflows can put an issue in, so the mapping
  // UI can offer them before an issue in that status has ever been pulled.
  // Answers statusesFetched; the default has nothing to say.
  virtual void fetchStatuses() {
  }

  // The user's status → column choices, which a push must honour when it
  // picks a target status. The default provider pushes by column name alone.
  virtual void setStatusOverrides(const QHash<QString, QString>& /*overrides*/) {
  }

  // Whether the most recent tasksFetched carried every issue the filter
  // matches. False after a walk cut short by an error or the page cap: an
  // issue missing from such a pull may simply be on a page never fetched, so
  // it must not be read as deleted upstream.
  bool lastPullComplete() const {
    return m_lastPullComplete;
  }

 signals:
  void connectionTested(bool ok, const QString& error);
  // Only emitted for a successful pull. A failed one used to report an empty
  // list, which the UI could not tell apart from an empty backlog ("Synced 0
  // issue(s)") — failures go to pullFailed with the provider's own message.
  void tasksFetched(const QVector<ExternalTask>& tasks);
  void pullFailed(int httpStatus, const QString& error);
  // `project` echoes the one pushStatusChange was given, so two issues that share
  // a number in different repos are told apart. `remoteStatus` is the tracker's
  // status for the issue after a push that went through, as a pull would report
  // it, or empty when the tracker did not say.
  void taskPushed(const QString& externalId, const QString& project, bool ok, const QString& error, const QString& remoteStatus);
  // Newest first. An empty list with an empty error means the issue has none.
  void commentsFetched(const QString& externalId, const QVector<ExternalComment>& comments, const QString& error);
  void statusesFetched(const QStringList& statuses);

 protected:
  using QObject::QObject;

  // Providers set this right before emitting tasksFetched.
  void setLastPullComplete(bool complete) {
    m_lastPullComplete = complete;
  }

 private:
  bool m_lastPullComplete = true;
};

}  // namespace heap::integrations
