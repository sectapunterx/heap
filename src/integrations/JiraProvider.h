#pragma once

#include "integrations/IntegrationProvider.h"
#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QString>
#include <QVector>

#include <functional>

class QNetworkAccessManager;
class QNetworkReply;

namespace heap::integrations {

// Parse a Jira Cloud REST v3 search response ({ "issues": [...] }) into
// ExternalTasks. `baseUrl` builds each issue's browse URL. Descriptions arrive
// as ADF (Atlassian Document Format) JSON and are flattened to plain text.
// Pure, no network — unit-tested with canned JSON.
QVector<ExternalTask> parseJiraIssues(const QByteArray& json, const QString& baseUrl);

// Flatten an Atlassian Document Format value (string or ADF object) to plain
// text by concatenating every "text" leaf. Exposed for unit testing.
QString jiraAdfToPlainText(const QByteArray& adfJson);

// Make whatever the user pasted into a site root. People paste the URL from
// their browser ("acme.atlassian.net/jira/software/projects/LTE/boards/1"), and
// every one of those forms has to end up as "https://acme.atlassian.net".
// Pure — unit-tested.
QString normalizeJiraBaseUrl(const QString& raw);

// The JQL used when the user leaves the field empty. Not just "order by updated
// DESC": the search endpoint rejects a query with no search restriction with
// "Unbounded JQL queries are not allowed here", which made every sync on a
// fresh Jira card come back empty.
QString defaultJiraJql();

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
  // `jql` selects which issues to pull. Empty `jql` falls back to
  // defaultJiraJql().
  void setConfig(const QString& baseUrl, const QString& email, const QString& token, const QString& jql);
  bool isConfigured() const;

  // Host the scoped-token fallback goes through. Only tests change it.
  void setGatewayRoot(const QString& root) {
    m_gatewayRoot = root;
  }

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
  // One finished request, already drained — the reply itself is gone by the
  // time a callback runs, because a retry may outlive it.
  struct ApiResult {
    bool ok = false;
    int status = 0;   // 0 = the request never reached the server
    QByteArray body;  // response body (valid on success and on failure)
    QString error;    // human-readable, empty when ok
  };

  using ApiCallback = std::function<void(const ApiResult&)>;

  // Send to <api base>/rest/api/3<path>, retrying once through the Atlassian
  // API gateway if the site host answers 401 (see m_apiBase).
  void send(const QByteArray& method, const QString& path, const QByteArray& body, const ApiCallback& done);
  void sendOnce(const QByteArray& method, const QString& path, const QByteArray& body, const ApiCallback& done);
  // GET {site}/_edge/tenant_info — unauthenticated, returns the site's cloudId.
  void resolveCloudId(std::function<void(bool)> done);

  QNetworkAccessManager* m_nam = nullptr;
  QString m_baseUrl;  // "https://acme.atlassian.net" (no trailing slash)
  QString m_email;
  QString m_token;
  QString m_jql;

  // Where API calls actually go. Starts as the site itself, which is what a
  // classic (unscoped) API token expects. Atlassian's newer scoped tokens are
  // rejected there with a 401 and only work through
  // https://api.atlassian.com/ex/jira/{cloudId}, so the first 401 switches us
  // over for the rest of this provider's life.
  QString m_apiBase;
  QString m_gatewayRoot = QStringLiteral("https://api.atlassian.com");
  bool m_usingGateway = false;
  bool m_gatewayTried = false;
};

}  // namespace heap::integrations
