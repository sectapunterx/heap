#include "integrations/GithubProvider.h"
#include "integrations/GitlabProvider.h"
#include "integrations/JiraProvider.h"
#include "integrations/OAuthClients.h"
#include "integrations/ProviderRegistry.h"
#include "integrations/RestIssueProvider.h"
#include "integrations/TrelloProvider.h"

namespace heap::integrations {

namespace {

// ── Baked-in OAuth app credentials ──────────────────────────────────────────
// One-click "Connect with browser" needs an OAuth app registered with each
// provider; only the maintainer can create those. Public client IDs are
// committed in OAuthClients.h; the secrets some providers insist on come from
// the release workflow. Register the redirect URI reported by
// OAuthManager::redirectUri() (http://127.0.0.1:51789/). See docs/INTEGRATIONS.md.
//
// An empty value falls back to manual entry under Advanced (still works, just
// not one-click), which is what local builds and forks get.
constexpr const char* kGithubClientId = HEAP_OAUTH_GITHUB_CLIENT_ID;
constexpr const char* kGithubClientSecret = HEAP_OAUTH_GITHUB_CLIENT_SECRET;
constexpr const char* kGitlabClientId = HEAP_OAUTH_GITLAB_CLIENT_ID;

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

// Fill in an OAuthConfig for a provider that needs a client secret: they all
// refuse public/PKCE-only clients, so one-click only lights up in a build that
// carries the CI credentials (see OAuthClients.h).
OAuthConfig confidentialOAuth(
    const char* clientId, const char* clientSecret, QString authUrl, QString tokenUrl, QString scope, TokenStyle style) {
  OAuthConfig o;
  o.supported = true;
  o.authUrl = std::move(authUrl);
  o.tokenUrl = std::move(tokenUrl);
  o.scope = std::move(scope);
  o.usePkce = false;
  o.needsSecret = true;
  o.tokenStyle = style;
  o.clientId = QString::fromLatin1(clientId);
  o.clientSecret = QString::fromLatin1(clientSecret);
  return o;
}

// The pair of Advanced fields a provider needs when its OAuth app is
// registered by the user rather than shipped with the build.
QVector<FieldSpec> oauthAppFields() {
  return {plain(QStringLiteral("clientId"), QStringLiteral("OAuth client ID"), QStringLiteral("for browser sign-in"), true),
          secret(QStringLiteral("clientSecret"), QStringLiteral("OAuth client secret"))};
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
  d.oauth.flow = OAuthFlow::Device;
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
  d.uiFields += oauthAppFields();
  d.requiredKeys = {QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("token"), QStringLiteral("clientSecret")};
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
  // Todoist separates scopes with commas and issues a token that never expires,
  // so there is nothing to refresh. Sync is pull-only, hence a read-only scope.
  d.oauth = confidentialOAuth(HEAP_OAUTH_TODOIST_CLIENT_ID,
                              HEAP_OAUTH_TODOIST_CLIENT_SECRET,
                              QStringLiteral("https://todoist.com/oauth/authorize"),
                              QStringLiteral("https://todoist.com/oauth/access_token"),
                              QStringLiteral("data:read"),
                              TokenStyle::FormBody);
  d.oauth.scopeSeparator = QStringLiteral(",");
  // Todoist's allowlist documents "localhost is allowed", never the IP literal.
  d.oauth.redirectHost = QStringLiteral("localhost");
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
  d.uiFields += oauthAppFields();
  d.requiredKeys = {QStringLiteral("token"), QStringLiteral("workspace")};
  d.secretKeys = {QStringLiteral("token"), QStringLiteral("clientSecret")};
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
  // Asana does support PKCE, but still wants the secret alongside it, and its
  // access token lives an hour — the refresh token is what keeps the session.
  d.oauth = confidentialOAuth(HEAP_OAUTH_ASANA_CLIENT_ID,
                              HEAP_OAUTH_ASANA_CLIENT_SECRET,
                              QStringLiteral("https://app.asana.com/-/oauth_authorize"),
                              QStringLiteral("https://app.asana.com/-/oauth_token"),
                              QStringLiteral("tasks:read projects:read workspaces:read users:read"),
                              TokenStyle::FormBody);
  d.oauth.usePkce = true;
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
  d.uiFields += oauthAppFields();
  d.requiredKeys = {QStringLiteral("token"), QStringLiteral("listId")};
  d.secretKeys = {QStringLiteral("token"), QStringLiteral("clientSecret")};
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
  // ClickUp scopes the grant in its own consent screen rather than on the
  // authorize URL, and wants the exchange as JSON. Its token does not expire.
  d.oauth = confidentialOAuth(HEAP_OAUTH_CLICKUP_CLIENT_ID,
                              HEAP_OAUTH_CLICKUP_CLIENT_SECRET,
                              QStringLiteral("https://app.clickup.com/api"),
                              QStringLiteral("https://api.clickup.com/api/v2/oauth/token"),
                              QString(),
                              TokenStyle::JsonBody);
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
  d.uiFields += oauthAppFields();
  d.requiredKeys = {QStringLiteral("token"), QStringLiteral("org"), QStringLiteral("project")};
  d.secretKeys = {QStringLiteral("token"), QStringLiteral("clientSecret")};
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
  d.oauth = confidentialOAuth(HEAP_OAUTH_SENTRY_CLIENT_ID,
                              HEAP_OAUTH_SENTRY_CLIENT_SECRET,
                              QStringLiteral("https://sentry.io/oauth/authorize/"),
                              QStringLiteral("https://sentry.io/oauth/token/"),
                              QStringLiteral("org:read project:read event:read"),
                              TokenStyle::FormBody);
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
  d.uiFields += oauthAppFields();
  d.requiredKeys = {QStringLiteral("token"), QStringLiteral("workspace"), QStringLiteral("repo")};
  d.secretKeys = {QStringLiteral("token"), QStringLiteral("clientSecret")};
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
  // Bitbucket takes the client credentials in an HTTP Basic header and rejects
  // them in the body. Its access token lives two hours; scopes are set on the
  // consumer, not on the authorize URL.
  d.oauth = confidentialOAuth(HEAP_OAUTH_BITBUCKET_CLIENT_ID,
                              HEAP_OAUTH_BITBUCKET_CLIENT_SECRET,
                              QStringLiteral("https://bitbucket.org/site/oauth2/authorize"),
                              QStringLiteral("https://bitbucket.org/site/oauth2/access_token"),
                              QString(),
                              TokenStyle::BasicAuthForm);
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
                // Cloud authenticates an email + API token pair; Server/DC
                // authenticates a Personal Access Token on its own, so there
                // the email stays empty. Which one this is is detected, not asked.
                plain(QStringLiteral("email"), QStringLiteral("Email (Cloud only)"), QStringLiteral("you@company.com")),
                secret(QStringLiteral("token"), QStringLiteral("API token / PAT")),
                // The placeholder is the default the provider actually applies
                // when the field is left blank (see defaultJiraJql).
                plain(QStringLiteral("jql"), QStringLiteral("JQL"), defaultJiraJql(), true)};
  d.uiFields += oauthAppFields();
  // Browser sign-in supplies the token and the site, so only the token is
  // always required; the Basic-auth pair is checked by JiraProvider itself.
  d.requiredKeys = {QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("token"), QStringLiteral("clientSecret")};
  // Atlassian OAuth 2.0 (3LO). It has no PKCE-only mode, so one-click needs a
  // client secret. `audience` picks the Jira API and `prompt=consent` is what
  // makes Atlassian hand out a refresh token alongside the 1h access token.
  d.oauth = confidentialOAuth(HEAP_OAUTH_JIRA_CLIENT_ID,
                              HEAP_OAUTH_JIRA_CLIENT_SECRET,
                              QStringLiteral("https://auth.atlassian.com/authorize"),
                              QStringLiteral("https://auth.atlassian.com/oauth/token"),
                              QStringLiteral("read:jira-work write:jira-work read:jira-user offline_access"),
                              TokenStyle::JsonBody);
  d.oauth.extraAuthParams = {{QStringLiteral("audience"), QStringLiteral("api.atlassian.com")},
                             {QStringLiteral("prompt"), QStringLiteral("consent")}};
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
  // Trello has no authorization-code grant: /1/authorize returns the token in
  // the URL fragment, which the loopback listener only sees because the page it
  // serves posts it back. The app key is public (it is in every authorize URL),
  // so no secret is involved — but the key's allowed origins must include
  // http://127.0.0.1:51789. Sync is pull-only, hence the read-only scope.
  d.oauth.supported = true;
  d.oauth.flow = OAuthFlow::ImplicitFragment;
  d.oauth.authUrl = QStringLiteral("https://trello.com/1/authorize");
  d.oauth.scope = QStringLiteral("read");
  d.oauth.scopeSeparator = QStringLiteral(",");
  d.oauth.usePkce = false;
  d.oauth.clientId = QString::fromLatin1(HEAP_OAUTH_TRELLO_CLIENT_ID);
  d.oauth.clientIdParam = QStringLiteral("key");
  d.oauth.redirectParam = QStringLiteral("return_url");
  d.oauth.extraAuthParams = {{QStringLiteral("expiration"), QStringLiteral("never")},
                             {QStringLiteral("name"), QStringLiteral("heap")},
                             {QStringLiteral("response_type"), QStringLiteral("token")},
                             {QStringLiteral("callback_method"), QStringLiteral("fragment")}};
  return d;
}

ProviderDescriptor mattermost() {
  ProviderDescriptor d;
  d.id = QStringLiteral("mattermost");
  d.displayName = QStringLiteral("Mattermost");
  d.color = QStringLiteral("#4a7ec4");
  d.icon = QStringLiteral("◆");
  d.descKey = QStringLiteral("settings.int.mattermost.desc");
  d.kind = ProviderKind::Directory;
  d.bespoke = true;  // not a RestIssueProvider: there are no issues here
  d.uiFields = {plain(QStringLiteral("host"), QStringLiteral("Server URL"), QStringLiteral("https://mm.acme.com")),
                secret(QStringLiteral("token"), QStringLiteral("Personal access token")),
                plain(QStringLiteral("channels"),
                      QStringLiteral("Also import members of"),
                      QStringLiteral("backend, qa — blank = only people you have talked to"))};
  // Most corporate servers have personal access tokens switched off, so signing
  // in with the same credentials as the Mattermost app is the primary path.
  // These are never stored: the session token they return is.
  d.loginFields = {plain(QStringLiteral("loginId"), QStringLiteral("Username or email"), QStringLiteral("you@company.com")),
                   secret(QStringLiteral("password"), QStringLiteral("Password"), QString()),
                   plain(QStringLiteral("mfaToken"), QStringLiteral("MFA code (if enabled)"), QStringLiteral("123456"), true)};
  d.requiredKeys = {QStringLiteral("host"), QStringLiteral("token")};
  d.secretKeys = {QStringLiteral("token")};
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
      // Appended: the catalog order is load-bearing (a test pins github at 0).
      mattermost(),
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
  const bool oauth = cfg.value(QStringLiteral("authMode")).toString() == QStringLiteral("oauth");
  if(id == QStringLiteral("jira")) {
    auto p = std::make_unique<JiraProvider>(parent);
    if(oauth) {
      // cloudId was resolved from accessible-resources when the browser flow
      // finished; without it there is no API base to talk to.
      p->setOAuthConfig(cfg.value(QStringLiteral("cloudId")).toString(),
                        cfg.value(QStringLiteral("siteUrl")).toString(),
                        cfg.value(QStringLiteral("token")).toString(),
                        cfg.value(QStringLiteral("jql")).toString());
    } else {
      p->setConfig(cfg.value(QStringLiteral("baseUrl")).toString(),
                   cfg.value(QStringLiteral("email")).toString(),
                   cfg.value(QStringLiteral("token")).toString(),
                   cfg.value(QStringLiteral("jql")).toString());
    }
    return p->isConfigured() ? std::move(p) : nullptr;
  }
  if(id == QStringLiteral("trello")) {
    auto p = std::make_unique<TrelloProvider>(parent);
    // A browser sign-in only hands back the token; the key is the app's own,
    // which the user never sees.
    QString key = cfg.value(QStringLiteral("key")).toString();
    if(oauth && key.isEmpty()) {
      key = QString::fromLatin1(HEAP_OAUTH_TRELLO_CLIENT_ID);
    }
    p->setConfig(key, cfg.value(QStringLiteral("token")).toString(), cfg.value(QStringLiteral("board")).toString());
    return p->isConfigured() ? std::move(p) : nullptr;
  }
  return nullptr;
}

}  // namespace heap::integrations
