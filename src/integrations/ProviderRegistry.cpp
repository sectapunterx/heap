#include "integrations/GithubProvider.h"
#include "integrations/GitlabProvider.h"
#include "integrations/JiraProvider.h"
#include "integrations/ProviderRegistry.h"
#include "integrations/RestIssueProvider.h"
#include "integrations/TrelloProvider.h"

namespace heap::integrations {

namespace {

// ── Baked-in OAuth app credentials ──────────────────────────────────────────
// One-click "Connect with browser" needs an OAuth app registered with each
// provider; only the maintainer can create those. Paste the resulting client IDs
// here and the card drops its manual field automatically. Register the redirect
// URI reported by OAuthManager::redirectUri() (http://127.0.0.1:51789/).
//
//   GitHub : https://github.com/settings/developers  (OAuth App — also needs a
//            client secret; embedding one in an open-source binary is not truly
//            secret, so GitHub stays PAT-first until a proxy/GitHub-App is added)
//   GitLab : https://gitlab.com/-/profile/applications (scope "api", PKCE, no secret)
//   Gitea/Forgejo are per-instance, so their client ID is entered under Advanced.
//
// Empty = fall back to manual entry under Advanced (still works, just not 1-click).
// GitHub OAuth App "heap" (owner: sectapunterx), Device Flow enabled. The client
// ID is public by design for device flow — safe to ship. No client secret needed.
constexpr const char* kGithubClientId = "Ov23ctU4qrY60Ac7lRy9";
constexpr const char* kGithubClientSecret = "";
// GitLab.com OAuth app "heap" (owner: sectapunterx), Confidential=No → PKCE, no
// secret. The Application ID is public by design for PKCE clients — safe to ship.
constexpr const char* kGitlabClientId = "70b8f336ebd850a26e629b82e1388fac9464886befaf85674b402c200fbb9c74";

// ── ParseFn adapters: the tested GitHub/GitLab parsers ignore baseUrl ──
QVector<ExternalTask> githubParse(const QByteArray& body, const QString&) {
  return parseGithubIssues(body);
}

QVector<ExternalTask> gitlabParse(const QByteArray& body, const QString&) {
  return parseGitlabIssues(body);
}

FieldSpec secret(QString key, QString label, QString placeholder = QStringLiteral("***")) {
  return FieldSpec{std::move(key), std::move(label), std::move(placeholder), /*mono*/ true, /*secret*/ true};
}

FieldSpec plain(QString key, QString label, QString placeholder, bool mono = false) {
  return FieldSpec{std::move(key), std::move(label), std::move(placeholder), mono, /*secret*/ false};
}

ProviderDescriptor github() {
  ProviderDescriptor d;
  d.id = QStringLiteral("github");
  d.displayName = QStringLiteral("GitHub");
  d.color = QStringLiteral("#5a6371");
  d.icon = QStringLiteral("◯");
  d.descKey = QStringLiteral("settings.int.github.desc");
  d.uiFields = {plain(QStringLiteral("repo"), QStringLiteral("Repo"), QStringLiteral("org/name"), true),
                secret(QStringLiteral("token"), QStringLiteral("Access token")),
                plain(QStringLiteral("clientId"), QStringLiteral("OAuth client ID"), QStringLiteral("Iv1.… (for browser sign-in)"), true),
                secret(QStringLiteral("clientSecret"), QStringLiteral("OAuth client secret")),
                plain(QStringLiteral("branchTemplate"), QStringLiteral("Branch template"), QStringLiteral("feature/{id}-{slug}"), true)};
  // repo is optional: blank pulls issues assigned to the signed-in user.
  d.requiredKeys = {QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("token"), QStringLiteral("clientSecret")};
  d.baseUrlTemplate = QStringLiteral("https://api.github.com");
  d.auth.kind = AuthKind::HeaderToken;
  d.auth.tokenPrefix = "token ";
  d.auth.extraHeaders = {{"Accept", "application/vnd.github+json"}, {"X-GitHub-Api-Version", "2022-11-28"}};
  d.listPathTemplate = QStringLiteral("/repos/{repo}/issues?state=all&per_page=100");
  d.selfListPathTemplate = QStringLiteral("/issues?filter=assigned&state=all&per_page=100");
  d.scopeKey = QStringLiteral("repo");
  d.parser = githubParse;
  // GitHub OAuth Apps can't do PKCE and would need a client secret for the web
  // flow (unsafe to embed in OSS). Use the Device Authorization Grant instead:
  // client ID only, no secret. Requires "Enable Device Flow" on the OAuth App.
  d.oauth = {true,
             QStringLiteral("https://github.com/login/oauth/authorize"),
             QStringLiteral("https://github.com/login/oauth/access_token"),
             QStringLiteral("repo"),
             false,
             QString::fromLatin1(kGithubClientId),
             QString::fromLatin1(kGithubClientSecret)};
  d.oauth.deviceFlow = true;
  d.oauth.deviceAuthUrl = QStringLiteral("https://github.com/login/device/code");
  d.pushMethod = QStringLiteral("PATCH");
  d.pushPathTemplate = QStringLiteral("/repos/{repo}/issues/{externalId}");
  d.pushBodyTemplate = R"({"state":"{state}"})";
  d.pushMap = githubStateForColumn;
  return d;
}

ProviderDescriptor gitlab() {
  ProviderDescriptor d;
  d.id = QStringLiteral("gitlab");
  d.displayName = QStringLiteral("GitLab");
  d.color = QStringLiteral("#e2683c");
  d.icon = QStringLiteral("▲");
  d.descKey = QStringLiteral("settings.int.gitlab.desc");
  d.uiFields = {plain(QStringLiteral("host"), QStringLiteral("Host"), QStringLiteral("https://gitlab.com")),
                plain(QStringLiteral("projectId"), QStringLiteral("Project"), QStringLiteral("12345 or group/name"), true),
                secret(QStringLiteral("token"), QStringLiteral("Access token")),
                plain(QStringLiteral("clientId"), QStringLiteral("OAuth application ID"), QStringLiteral("for browser sign-in"), true)};
  // host defaults to gitlab.com and projectId is optional (blank = my issues).
  d.requiredKeys = {QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("token")};
  d.baseUrlTemplate = QStringLiteral("{host}");
  d.baseUrlFallback = QStringLiteral("https://gitlab.com");
  d.auth.kind = AuthKind::CustomHeader;
  d.auth.headerName = "PRIVATE-TOKEN";
  d.auth.extraHeaders = {{"Accept", "application/json"}};
  d.listPathTemplate = QStringLiteral("/api/v4/projects/{projectId:enc}/issues?per_page=100&scope=all");
  d.selfListPathTemplate = QStringLiteral("/api/v4/issues?scope=assigned_to_me&per_page=100");
  d.scopeKey = QStringLiteral("projectId");
  d.parser = gitlabParse;
  // GitLab supports OAuth 2.0 with PKCE (no secret needed).
  d.oauth = {true,
             QStringLiteral("{host}/oauth/authorize"),
             QStringLiteral("{host}/oauth/token"),
             QStringLiteral("api"),
             true,
             QString::fromLatin1(kGitlabClientId),
             QString()};
  d.pushMethod = QStringLiteral("PUT");
  d.pushPathTemplate = QStringLiteral("/api/v4/projects/{projectId:enc}/issues/{externalId}?state_event={state}");
  d.pushMap = gitlabStateEventForColumn;
  return d;
}

// Gitea and Forgejo share the same REST API (Forgejo is a Gitea fork). Only the
// card identity and default host differ.
ProviderDescriptor giteaLike(const QString& id,
                             const QString& name,
                             const QString& color,
                             const QString& icon,
                             const QString& descKey,
                             const QString& hostPlaceholder) {
  ProviderDescriptor d;
  d.id = id;
  d.displayName = name;
  d.color = color;
  d.icon = icon;
  d.descKey = descKey;
  d.uiFields = {plain(QStringLiteral("host"), QStringLiteral("Host"), hostPlaceholder),
                plain(QStringLiteral("repo"), QStringLiteral("Repo"), QStringLiteral("owner/name"), true),
                secret(QStringLiteral("token"), QStringLiteral("Access token")),
                plain(QStringLiteral("clientId"), QStringLiteral("OAuth client ID"), QStringLiteral("for browser sign-in"), true)};
  // repo optional: blank pulls issues across repos the user can access.
  d.requiredKeys = {QStringLiteral("host"), QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("token")};
  d.baseUrlTemplate = QStringLiteral("{host}");
  d.auth.kind = AuthKind::HeaderToken;
  d.auth.tokenPrefix = "token ";
  d.auth.extraHeaders = {{"Accept", "application/json"}};
  d.listPathTemplate = QStringLiteral("/api/v1/repos/{repo}/issues?state=all&type=issues&limit=50");
  d.selfListPathTemplate = QStringLiteral("/api/v1/repos/issues/search?state=all&type=issues&limit=50");
  d.scopeKey = QStringLiteral("repo");
  // Gitea/Forgejo support OAuth 2.0 with PKCE.
  d.oauth = {true,
             QStringLiteral("{host}/login/oauth/authorize"),
             QStringLiteral("{host}/login/oauth/access_token"),
             QStringLiteral("read:issue write:issue read:user"),
             true};
  d.fields.id = QStringLiteral("number");
  d.fields.title = QStringLiteral("title");
  d.fields.body = QStringLiteral("body");
  d.fields.status = QStringLiteral("state");
  d.fields.url = QStringLiteral("html_url");
  d.fields.updatedAt = QStringLiteral("updated_at");
  d.fields.labels = QStringLiteral("labels");
  d.fields.labelNameKey = QStringLiteral("name");
  d.pushMethod = QStringLiteral("PATCH");
  d.pushPathTemplate = QStringLiteral("/api/v1/repos/{repo}/issues/{externalId}");
  d.pushBodyTemplate = R"({"state":"{state}"})";
  d.pushMap = githubStateForColumn;  // Gitea state is "open"/"closed" like GitHub
  return d;
}

ProviderDescriptor redmine() {
  ProviderDescriptor d;
  d.id = QStringLiteral("redmine");
  d.displayName = QStringLiteral("Redmine");
  d.color = QStringLiteral("#b32024");
  d.icon = QStringLiteral("R");
  d.descKey = QStringLiteral("settings.int.redmine.desc");
  d.uiFields = {plain(QStringLiteral("host"), QStringLiteral("Host"), QStringLiteral("https://redmine.example.com")),
                secret(QStringLiteral("token"), QStringLiteral("API key"))};
  d.requiredKeys = {QStringLiteral("host"), QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("token")};
  d.baseUrlTemplate = QStringLiteral("{host}");
  d.auth.kind = AuthKind::CustomHeader;
  d.auth.headerName = "X-Redmine-API-Key";
  d.auth.extraHeaders = {{"Accept", "application/json"}};
  d.listPathTemplate = QStringLiteral("/issues.json?assigned_to_id=me&status_id=open&limit=100");
  d.fields.arrayPointer = QStringLiteral("issues");
  d.fields.id = QStringLiteral("id");
  d.fields.title = QStringLiteral("subject");
  d.fields.body = QStringLiteral("description");
  d.fields.status = QStringLiteral("status.name");
  d.fields.priority = QStringLiteral("priority.name");
  d.fields.urlTemplate = QStringLiteral("{baseUrl}/issues/{id}");
  d.fields.updatedAt = QStringLiteral("updated_on");
  return d;  // pull-only
}

ProviderDescriptor todoist() {
  ProviderDescriptor d;
  d.id = QStringLiteral("todoist");
  d.displayName = QStringLiteral("Todoist");
  d.color = QStringLiteral("#e44332");
  d.icon = QStringLiteral("T");
  d.descKey = QStringLiteral("settings.int.todoist.desc");
  d.uiFields = {secret(QStringLiteral("token"), QStringLiteral("API token"))};
  d.requiredKeys = {QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("token")};
  d.baseUrlTemplate = QStringLiteral("https://api.todoist.com");
  d.auth.kind = AuthKind::HeaderToken;
  d.auth.tokenPrefix = "Bearer ";
  d.auth.extraHeaders = {{"Accept", "application/json"}};
  // Unified v1 API (REST v2 was retired). Active tasks come back under "results".
  d.listPathTemplate = QStringLiteral("/api/v1/tasks");
  d.fields.arrayPointer = QStringLiteral("results");
  d.fields.id = QStringLiteral("id");
  d.fields.title = QStringLiteral("content");
  d.fields.body = QStringLiteral("description");
  d.fields.boolStatusField = QStringLiteral("is_completed");
  d.fields.url = QStringLiteral("url");
  return d;  // pull-only
}

ProviderDescriptor asana() {
  ProviderDescriptor d;
  d.id = QStringLiteral("asana");
  d.displayName = QStringLiteral("Asana");
  d.color = QStringLiteral("#f06a6a");
  d.icon = QStringLiteral("A");
  d.descKey = QStringLiteral("settings.int.asana.desc");
  d.uiFields = {secret(QStringLiteral("token"), QStringLiteral("Access token")),
                plain(QStringLiteral("workspace"), QStringLiteral("Workspace GID"), QStringLiteral("1200000000000000"), true)};
  d.requiredKeys = {QStringLiteral("token"), QStringLiteral("workspace")};
  d.secretKeys = {QStringLiteral("token")};
  d.baseUrlTemplate = QStringLiteral("https://app.asana.com");
  d.auth.kind = AuthKind::HeaderToken;
  d.auth.tokenPrefix = "Bearer ";
  d.auth.extraHeaders = {{"Accept", "application/json"}};
  d.listPathTemplate = QStringLiteral(
      "/api/1.0/tasks?assignee=me&workspace={workspace}&opt_fields=name,completed,permalink_url,notes,modified_at&limit=100");
  d.fields.arrayPointer = QStringLiteral("data");
  d.fields.id = QStringLiteral("gid");
  d.fields.title = QStringLiteral("name");
  d.fields.body = QStringLiteral("notes");
  d.fields.boolStatusField = QStringLiteral("completed");
  d.fields.url = QStringLiteral("permalink_url");
  d.fields.updatedAt = QStringLiteral("modified_at");
  return d;  // pull-only
}

ProviderDescriptor clickup() {
  ProviderDescriptor d;
  d.id = QStringLiteral("clickup");
  d.displayName = QStringLiteral("ClickUp");
  d.color = QStringLiteral("#7b68ee");
  d.icon = QStringLiteral("U");
  d.descKey = QStringLiteral("settings.int.clickup.desc");
  d.uiFields = {secret(QStringLiteral("token"), QStringLiteral("API token")),
                plain(QStringLiteral("listId"), QStringLiteral("List ID"), QStringLiteral("901000000000"), true)};
  d.requiredKeys = {QStringLiteral("token"), QStringLiteral("listId")};
  d.secretKeys = {QStringLiteral("token")};
  d.baseUrlTemplate = QStringLiteral("https://api.clickup.com");
  d.auth.kind = AuthKind::CustomHeader;  // raw token in Authorization, no prefix
  d.auth.headerName = "Authorization";
  d.auth.extraHeaders = {{"Accept", "application/json"}};
  d.listPathTemplate = QStringLiteral("/api/v2/list/{listId}/task");
  d.fields.arrayPointer = QStringLiteral("tasks");
  d.fields.id = QStringLiteral("id");
  d.fields.title = QStringLiteral("name");
  d.fields.body = QStringLiteral("description");
  d.fields.status = QStringLiteral("status.status");
  d.fields.priority = QStringLiteral("priority.priority");
  d.fields.url = QStringLiteral("url");
  return d;  // pull-only
}

ProviderDescriptor sentry() {
  ProviderDescriptor d;
  d.id = QStringLiteral("sentry");
  d.displayName = QStringLiteral("Sentry");
  d.color = QStringLiteral("#8d5494");
  d.icon = QStringLiteral("S");
  d.descKey = QStringLiteral("settings.int.sentry.desc");
  d.uiFields = {secret(QStringLiteral("token"), QStringLiteral("Auth token")),
                plain(QStringLiteral("org"), QStringLiteral("Org slug"), QStringLiteral("acme")),
                plain(QStringLiteral("project"), QStringLiteral("Project slug"), QStringLiteral("backend"))};
  d.requiredKeys = {QStringLiteral("token"), QStringLiteral("org"), QStringLiteral("project")};
  d.secretKeys = {QStringLiteral("token")};
  d.baseUrlTemplate = QStringLiteral("https://sentry.io");
  d.auth.kind = AuthKind::HeaderToken;
  d.auth.tokenPrefix = "Bearer ";
  d.auth.extraHeaders = {{"Accept", "application/json"}};
  d.listPathTemplate = QStringLiteral("/api/0/projects/{org}/{project}/issues/?query=is:unresolved&limit=50");
  d.fields.id = QStringLiteral("id");
  d.fields.title = QStringLiteral("title");
  d.fields.body = QStringLiteral("culprit");
  d.fields.status = QStringLiteral("status");
  d.fields.url = QStringLiteral("permalink");
  d.fields.updatedAt = QStringLiteral("lastSeen");
  return d;  // pull-only
}

ProviderDescriptor bitbucket() {
  ProviderDescriptor d;
  d.id = QStringLiteral("bitbucket");
  d.displayName = QStringLiteral("Bitbucket");
  d.color = QStringLiteral("#2684ff");
  d.icon = QStringLiteral("B");
  d.descKey = QStringLiteral("settings.int.bitbucket.desc");
  d.uiFields = {secret(QStringLiteral("token"), QStringLiteral("Access token")),
                plain(QStringLiteral("workspace"), QStringLiteral("Workspace"), QStringLiteral("acme"), true),
                plain(QStringLiteral("repo"), QStringLiteral("Repo slug"), QStringLiteral("backend"), true)};
  d.requiredKeys = {QStringLiteral("token"), QStringLiteral("workspace"), QStringLiteral("repo")};
  d.secretKeys = {QStringLiteral("token")};
  d.baseUrlTemplate = QStringLiteral("https://api.bitbucket.org");
  d.auth.kind = AuthKind::HeaderToken;
  d.auth.tokenPrefix = "Bearer ";
  d.auth.extraHeaders = {{"Accept", "application/json"}};
  d.listPathTemplate = QStringLiteral("/2.0/repositories/{workspace}/{repo}/issues?pagelen=50");
  d.fields.arrayPointer = QStringLiteral("values");
  d.fields.id = QStringLiteral("id");
  d.fields.title = QStringLiteral("title");
  d.fields.body = QStringLiteral("content.raw");
  d.fields.status = QStringLiteral("state");
  d.fields.priority = QStringLiteral("priority");
  d.fields.url = QStringLiteral("links.html.href");
  d.fields.updatedAt = QStringLiteral("updated_on");
  return d;  // pull-only
}

ProviderDescriptor jira() {
  ProviderDescriptor d;
  d.id = QStringLiteral("jira");
  d.displayName = QStringLiteral("Jira");
  d.color = QStringLiteral("#5aa3e6");
  d.icon = QStringLiteral("J");
  d.descKey = QStringLiteral("settings.int.jira.desc");
  d.bespoke = true;
  d.uiFields = {plain(QStringLiteral("baseUrl"), QStringLiteral("Base URL"), QStringLiteral("https://acme.atlassian.net")),
                plain(QStringLiteral("email"), QStringLiteral("Email"), QStringLiteral("you@company.com")),
                secret(QStringLiteral("token"), QStringLiteral("API token")),
                plain(QStringLiteral("jql"), QStringLiteral("JQL"), QStringLiteral("project = LTE ORDER BY updated DESC"), true)};
  d.requiredKeys = {QStringLiteral("baseUrl"), QStringLiteral("email"), QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("token")};
  return d;
}

ProviderDescriptor trello() {
  ProviderDescriptor d;
  d.id = QStringLiteral("trello");
  d.displayName = QStringLiteral("Trello");
  d.color = QStringLiteral("#0079bf");
  d.icon = QStringLiteral("▤");
  d.descKey = QStringLiteral("settings.int.trello.desc");
  d.bespoke = true;
  d.uiFields = {secret(QStringLiteral("key"), QStringLiteral("API key")),
                secret(QStringLiteral("token"), QStringLiteral("Token")),
                plain(QStringLiteral("board"), QStringLiteral("Board ID (optional)"), QStringLiteral("5f...  — blank = all cards"), true)};
  d.requiredKeys = {QStringLiteral("key"), QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("key"), QStringLiteral("token")};
  return d;
}

}  // namespace

const QVector<ProviderDescriptor>& providerCatalog() {
  static const QVector<ProviderDescriptor> kCatalog = {
      github(),
      gitlab(),
      jira(),
      giteaLike(QStringLiteral("gitea"),
                QStringLiteral("Gitea"),
                QStringLiteral("#609926"),
                QStringLiteral("G"),
                QStringLiteral("settings.int.gitea.desc"),
                QStringLiteral("https://gitea.com")),
      giteaLike(QStringLiteral("forgejo"),
                QStringLiteral("Forgejo"),
                QStringLiteral("#fb923c"),
                QStringLiteral("F"),
                QStringLiteral("settings.int.forgejo.desc"),
                QStringLiteral("https://codeberg.org")),
      redmine(),
      todoist(),
      trello(),
      asana(),
      clickup(),
      sentry(),
      bitbucket(),
  };
  return kCatalog;
}

const ProviderDescriptor* findDescriptor(const QString& id) {
  for(const ProviderDescriptor& d : providerCatalog()) {
    if(d.id == id) {
      return &d;
    }
  }
  return nullptr;
}

std::unique_ptr<IntegrationProvider> makeBespokeProvider(const QString& id, const QVariantMap& cfg, QObject* parent) {
  if(id == QStringLiteral("jira")) {
    auto p = std::make_unique<JiraProvider>(parent);
    p->setConfig(cfg.value(QStringLiteral("baseUrl")).toString(),
                 cfg.value(QStringLiteral("email")).toString(),
                 cfg.value(QStringLiteral("token")).toString(),
                 cfg.value(QStringLiteral("jql")).toString());
    return p->isConfigured() ? std::move(p) : nullptr;
  }
  if(id == QStringLiteral("trello")) {
    auto p = std::make_unique<TrelloProvider>(parent);
    p->setConfig(cfg.value(QStringLiteral("key")).toString(),
                 cfg.value(QStringLiteral("token")).toString(),
                 cfg.value(QStringLiteral("board")).toString());
    return p->isConfigured() ? std::move(p) : nullptr;
  }
  return nullptr;
}

}  // namespace heap::integrations
