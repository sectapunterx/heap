#pragma once

#include "integrations/IntegrationProvider.h"
#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QString>
#include <QVector>

#include <cstdint>
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

// Which Jira a site is. The two are different products behind the same name:
// Cloud serves /rest/api/3 and authenticates a pair (account email + API
// token); Server and Data Center serve /rest/api/2 and take a Personal Access
// Token as a bearer credential. Picking wrong produces a 401 or a 404 with
// nothing pointing at the real cause, so heap detects it rather than asking.
enum class JiraDeployment : std::uint8_t {
  Unknown,
  Cloud,
  Server,  // covers Data Center — same API, same auth
};

// Read the deploymentType out of a /rest/api/2/serverInfo response. Unknown
// when the body says nothing useful. Pure — unit-tested.
JiraDeployment parseJiraDeployment(const QByteArray& serverInfoJson);

// The deployment to assume when the probe itself fails: only Atlassian runs
// *.atlassian.net, and everything else self-hosted is Server/DC. Pure.
JiraDeployment guessJiraDeployment(const QString& baseUrl);

// Pick which Atlassian site to use out of an accessible-resources response
// ([{ "id": cloudId, "url": …, "name": … }]). Prefers the one matching
// `preferredUrl`; otherwise takes the first. Returns {cloudId, siteUrl} — both
// empty when the response grants no site. Pure — unit-tested.
struct JiraSite {
  QString cloudId;
  QString url;
};

JiraSite pickJiraSite(const QByteArray& accessibleResourcesJson, const QString& preferredUrl);

// Concrete IntegrationProvider backed by the Jira Cloud REST API v3 (HEAP-75).
// Auth is either HTTP Basic (account email + API token) or, after a browser
// sign-in, a Bearer access token through the Atlassian API gateway. Status
// pushes go through the issue's available workflow transitions.
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
  // Browser sign-in (OAuth 2.0 3LO). No email: the token identifies the user,
  // and every call goes to the gateway, which is the only host that accepts a
  // 3LO token. `cloudId` comes from accessible-resources at sign-in time and is
  // cached in the card's config; `siteUrl` only builds browse links.
  void setOAuthConfig(const QString& cloudId, const QString& siteUrl, const QString& token, const QString& jql);
  bool isConfigured() const;

  // Override the auto-detection. Only the tests use this; the app lets
  // detectDeployment() decide on the first request.
  void setDeployment(JiraDeployment deployment) {
    m_deployment = deployment;
  }

  JiraDeployment deployment() const {
    return m_deployment;
  }

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

  // Replace an unauthorized result's message with one naming what to change.
  // Qt renders every 401 as "Host requires authentication" and Jira's own body
  // is no more actionable, so neither tells the user what is wrong.
  ApiResult explainAuthFailure(const ApiResult& result, bool cloudIdResolved) const;

  // Send to <api base>/rest/api/3<path>, retrying once through the Atlassian
  // API gateway if the site host answers 401 (see m_apiBase).
  void send(const QByteArray& method, const QString& path, const QByteArray& body, const ApiCallback& done);
  void sendOnce(const QByteArray& method, const QString& path, const QByteArray& body, const ApiCallback& done);
  // GET {site}/rest/api/2/serverInfo once, to learn Cloud from Server. Falls
  // back to guessJiraDeployment() when the probe fails.
  void detectDeployment(const std::function<void()>& then);
  // Run `then` once the deployment is known, probing for it if need be.
  void ensureDeployment(const std::function<void()>& then);
  // "/rest/api/3" on Cloud, "/rest/api/2" on Server/DC.
  QString apiRoot() const;
  // GET {site}/_edge/tenant_info — unauthenticated, returns the site's cloudId.
  void resolveCloudId(std::function<void(bool)> done);

  QNetworkAccessManager* m_nam = nullptr;
  QString m_baseUrl;  // "https://acme.atlassian.net" (no trailing slash)
  QString m_email;    // empty in OAuth mode
  QString m_token;
  QString m_jql;
  bool m_oauth = false;
  JiraDeployment m_deployment = JiraDeployment::Unknown;

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
