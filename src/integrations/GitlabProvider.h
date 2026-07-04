#pragma once

#include "integrations/IntegrationProvider.h"
#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QString>
#include <QVector>

class QNetworkAccessManager;

namespace heap::integrations {

// Parse a GitLab "list project issues" JSON array into ExternalTasks. Pure, no
// network — unit-tested with canned JSON. externalId is the issue `iid` (the
// per-project number), which is what the issues/{iid} endpoints expect.
QVector<ExternalTask> parseGitlabIssues(const QByteArray& json);

// Push-direction map: a heap column → the GitLab `state_event` used to move the
// issue. "done" closes it; every other column reopens it.
QString gitlabStateEventForColumn(const QString& column);

// Concrete IntegrationProvider backed by the GitLab REST API v4 (HEAP-75).
// Auth is a personal-access token sent in the PRIVATE-TOKEN header. Mirrors the
// QNetworkAccessManager pattern of GithubProvider.
class GitlabProvider : public IntegrationProvider {
  Q_OBJECT

 public:
  explicit GitlabProvider(QObject* parent = nullptr);
  ~GitlabProvider() override;

  // Configure from the Settings → Integrations GitLab card. `host` is the
  // instance base (e.g. "https://gitlab.com"); `project` is a numeric id or a
  // URL-encoded "group/name" path; `token` a PAT. All required.
  void setConfig(const QString& host, const QString& project, const QString& token);
  bool isConfigured() const;

  QString id() const override {
    return QStringLiteral("gitlab");
  }

  QString displayName() const override {
    return QStringLiteral("GitLab");
  }

  void testConnection() override;
  void pullTasks() override;
  void pushStatusChange(const QString& externalId, const QString& newStatus) override;

 private:
  QNetworkAccessManager* m_nam = nullptr;
  QString m_host;     // "https://gitlab.com" (no trailing slash)
  QString m_project;  // numeric id or URL-encoded path
  QString m_token;    // PAT
};

}  // namespace heap::integrations
