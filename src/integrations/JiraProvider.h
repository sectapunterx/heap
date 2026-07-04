#pragma once

#include "integrations/IntegrationProvider.h"
#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QString>
#include <QVector>

class QNetworkAccessManager;

namespace heap::integrations {

// Parse a Jira Cloud REST v3 search response ({ "issues": [...] }) into
// ExternalTasks. `baseUrl` builds each issue's browse URL. Descriptions arrive
// as ADF (Atlassian Document Format) JSON and are flattened to plain text.
// Pure, no network — unit-tested with canned JSON.
QVector<ExternalTask> parseJiraIssues(const QByteArray& json, const QString& baseUrl);

// Flatten an Atlassian Document Format value (string or ADF object) to plain
// text by concatenating every "text" leaf. Exposed for unit testing.
QString jiraAdfToPlainText(const QByteArray& adfJson);

// Concrete IntegrationProvider backed by the Jira Cloud REST API v3 (HEAP-75).
// Auth is HTTP Basic with an Atlassian account email + API token. Status pushes
// go through the issue's available workflow transitions.
class JiraProvider : public IntegrationProvider {
  Q_OBJECT

 public:
  explicit JiraProvider(QObject* parent = nullptr);
  ~JiraProvider() override;

  // Configure from the Settings → Integrations Jira card. `baseUrl` is the site
  // ("https://acme.atlassian.net"); `email` + `token` form the Basic-auth pair;
  // `jql` selects which issues to pull. All required.
  void setConfig(const QString& baseUrl, const QString& email, const QString& token, const QString& jql);
  bool isConfigured() const;

  QString id() const override {
    return QStringLiteral("jira");
  }

  QString displayName() const override {
    return QStringLiteral("Jira");
  }

  void testConnection() override;
  void pullTasks() override;
  void pushStatusChange(const QString& externalId, const QString& newStatus) override;

 private:
  QNetworkAccessManager* m_nam = nullptr;
  QString m_baseUrl;  // "https://acme.atlassian.net" (no trailing slash)
  QString m_email;
  QString m_token;
  QString m_jql;
};

}  // namespace heap::integrations
