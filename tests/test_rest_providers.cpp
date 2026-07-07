// Unit tests for the descriptor-driven tracker sync: the generic FieldMap
// parser (RestIssueProvider), the provider registry's field mappings, the
// bespoke Trello parsers, and the SecretStore cache. No network.

#include "integrations/ProviderRegistry.h"
#include "integrations/RestIssueProvider.h"
#include "integrations/SecretStore.h"
#include "integrations/TrelloProvider.h"

#include <gtest/gtest.h>

using namespace heap::integrations;

namespace {

QVector<ExternalTask> parseVia(const QString& providerId, const QByteArray& json, const QString& baseUrl = QString()) {
  const ProviderDescriptor* d = findDescriptor(providerId);
  EXPECT_NE(d, nullptr) << "no descriptor for " << providerId.toStdString();
  if(!d) {
    return {};
  }
  if(d->parser) {
    return d->parser(json, baseUrl);
  }
  return parseWithFieldMap(json, d->fields, d->id, baseUrl);
}

}  // namespace

TEST(FieldMapParse, DotPathsBoolStatusAndUrlTemplate) {
  // Exercises nested dot-paths (status.name), an object-array label, and the
  // {baseUrl}/{id} url template — the Redmine shape.
  const QByteArray json = R"({"issues":[
    {"id":42,"subject":"Do thing","description":"body","status":{"name":"In Progress"},
     "priority":{"name":"High"},"updated_on":"2026-01-02T03:04:05Z"}]})";
  const QVector<ExternalTask> tasks = parseVia(QStringLiteral("redmine"), json, QStringLiteral("https://redmine.example.com/"));
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].providerId, QStringLiteral("redmine"));
  EXPECT_EQ(tasks[0].externalId, QStringLiteral("42"));  // numeric id stringified
  EXPECT_EQ(tasks[0].title, QStringLiteral("Do thing"));
  EXPECT_EQ(tasks[0].status, QStringLiteral("In Progress"));  // dot-path status.name
  EXPECT_EQ(tasks[0].priority, QStringLiteral("High"));
  EXPECT_EQ(tasks[0].url, QStringLiteral("https://redmine.example.com/issues/42"));  // trailing slash trimmed
}

TEST(FieldMapParse, GiteaIssuesWithLabels) {
  const QByteArray json = R"([
    {"number":7,"title":"Fix build","body":"desc","state":"open",
     "html_url":"https://gitea.com/o/r/issues/7","updated_at":"2026-01-02T03:04:05Z",
     "labels":[{"name":"bug"},{"name":"ci"}]}])";
  const QVector<ExternalTask> tasks = parseVia(QStringLiteral("gitea"), json);
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].externalId, QStringLiteral("7"));
  EXPECT_EQ(tasks[0].status, QStringLiteral("open"));
  EXPECT_EQ(tasks[0].url, QStringLiteral("https://gitea.com/o/r/issues/7"));
  ASSERT_EQ(tasks[0].labels.size(), 2);
  EXPECT_EQ(tasks[0].labels[0], QStringLiteral("bug"));
  EXPECT_TRUE(tasks[0].updatedAt.isValid());
}

TEST(FieldMapParse, TodoistBoolStatusFalseIsOpen) {
  const QByteArray json = R"({"results":[
    {"id":"abc","content":"Buy milk","description":"d","is_completed":false,"url":"https://todoist.com/app/task/abc"}]})";
  const QVector<ExternalTask> tasks = parseVia(QStringLiteral("todoist"), json);
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].externalId, QStringLiteral("abc"));
  EXPECT_EQ(tasks[0].title, QStringLiteral("Buy milk"));
  EXPECT_EQ(tasks[0].status, QStringLiteral("open"));  // boolFalseStatus
}

TEST(FieldMapParse, AsanaCompletedIsClosed) {
  const QByteArray json = R"({"data":[
    {"gid":"111","name":"Task A","notes":"n","completed":true,
     "permalink_url":"https://app.asana.com/0/0/111","modified_at":"2026-01-02T03:04:05Z"}]})";
  const QVector<ExternalTask> tasks = parseVia(QStringLiteral("asana"), json);
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].externalId, QStringLiteral("111"));
  EXPECT_EQ(tasks[0].status, QStringLiteral("closed"));  // boolTrueStatus
  EXPECT_EQ(tasks[0].url, QStringLiteral("https://app.asana.com/0/0/111"));
}

TEST(FieldMapParse, ClickUpNestedStatusAndPriority) {
  const QByteArray json = R"({"tasks":[
    {"id":"9x","name":"CU task","description":"d","status":{"status":"in progress"},
     "priority":{"priority":"high"},"url":"https://app.clickup.com/t/9x"}]})";
  const QVector<ExternalTask> tasks = parseVia(QStringLiteral("clickup"), json);
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].status, QStringLiteral("in progress"));
  EXPECT_EQ(tasks[0].priority, QStringLiteral("high"));
}

TEST(FieldMapParse, SentryRootArray) {
  const QByteArray json = R"([
    {"id":"55","title":"TypeError","culprit":"foo","status":"unresolved",
     "permalink":"https://sentry.io/i/55/","lastSeen":"2026-01-02T03:04:05Z"}])";
  const QVector<ExternalTask> tasks = parseVia(QStringLiteral("sentry"), json);
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].externalId, QStringLiteral("55"));
  EXPECT_EQ(tasks[0].status, QStringLiteral("unresolved"));
  EXPECT_EQ(tasks[0].url, QStringLiteral("https://sentry.io/i/55/"));
}

TEST(FieldMapParse, BitbucketDeepDotPaths) {
  const QByteArray json = R"({"values":[
    {"id":3,"title":"BB issue","content":{"raw":"body text"},"state":"new","priority":"major",
     "links":{"html":{"href":"https://bitbucket.org/ws/repo/issues/3"}},"updated_on":"2026-01-02T03:04:05Z"}]})";
  const QVector<ExternalTask> tasks = parseVia(QStringLiteral("bitbucket"), json);
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].externalId, QStringLiteral("3"));
  EXPECT_EQ(tasks[0].body, QStringLiteral("body text"));  // content.raw
  EXPECT_EQ(tasks[0].status, QStringLiteral("new"));
  EXPECT_EQ(tasks[0].priority, QStringLiteral("major"));
  EXPECT_EQ(tasks[0].url, QStringLiteral("https://bitbucket.org/ws/repo/issues/3"));  // links.html.href
}

TEST(FieldMapParse, HandlesEmptyAndMismatchedShape) {
  const ProviderDescriptor* d = findDescriptor(QStringLiteral("bitbucket"));
  ASSERT_NE(d, nullptr);
  EXPECT_TRUE(parseWithFieldMap(QByteArray(), d->fields, d->id, QString()).isEmpty());
  EXPECT_TRUE(parseWithFieldMap("[]", d->fields, d->id, QString()).isEmpty());  // array, wanted object envelope
  EXPECT_TRUE(parseWithFieldMap("not json", d->fields, d->id, QString()).isEmpty());
}

TEST(RegistryDescriptors, GithubAndGitlabReuseTestedParsers) {
  const QByteArray gh = R"([{"number":12,"title":"t","state":"open","html_url":"u","updated_at":"2026-01-02T03:04:05Z"}])";
  const QVector<ExternalTask> ghTasks = parseVia(QStringLiteral("github"), gh);
  ASSERT_EQ(ghTasks.size(), 1);
  EXPECT_EQ(ghTasks[0].providerId, QStringLiteral("github"));
  EXPECT_EQ(ghTasks[0].externalId, QStringLiteral("12"));

  const QByteArray gl = R"([{"iid":42,"title":"t","state":"opened","web_url":"u","updated_at":"2026-01-02T03:04:05Z"}])";
  const QVector<ExternalTask> glTasks = parseVia(QStringLiteral("gitlab"), gl);
  ASSERT_EQ(glTasks.size(), 1);
  EXPECT_EQ(glTasks[0].externalId, QStringLiteral("42"));  // iid, not internal id
}

TEST(RegistryCatalog, HasExpectedProvidersAndSecrets) {
  const auto& cat = providerCatalog();
  EXPECT_GE(cat.size(), 12);
  // Jira and Trello are bespoke; the rest are generic.
  EXPECT_TRUE(findDescriptor(QStringLiteral("jira"))->bespoke);
  EXPECT_TRUE(findDescriptor(QStringLiteral("trello"))->bespoke);
  EXPECT_FALSE(findDescriptor(QStringLiteral("gitea"))->bespoke);
  // Every provider marks its token/key field secret.
  for(const ProviderDescriptor& d : cat) {
    EXPECT_FALSE(d.secretKeys.isEmpty()) << d.id.toStdString();
  }
  EXPECT_EQ(findDescriptor(QStringLiteral("github")), &cat.at(0));
}

TEST(RegistryCatalog, OAuthConfiguredForGitForges) {
  for(const char* id : {"github", "gitlab", "gitea", "forgejo"}) {
    const ProviderDescriptor* d = findDescriptor(QString::fromLatin1(id));
    ASSERT_NE(d, nullptr) << id;
    EXPECT_TRUE(d->oauth.supported) << id;
    EXPECT_FALSE(d->oauth.authUrl.isEmpty()) << id;
    EXPECT_FALSE(d->oauth.tokenUrl.isEmpty()) << id;
  }
  // GitLab/Gitea use PKCE (no secret); GitHub OAuth Apps need a client secret.
  EXPECT_TRUE(findDescriptor(QStringLiteral("gitlab"))->oauth.usePkce);
  EXPECT_TRUE(findDescriptor(QStringLiteral("gitea"))->oauth.usePkce);
  EXPECT_FALSE(findDescriptor(QStringLiteral("github"))->oauth.usePkce);
  // Self-hosted forges keep the {host} placeholder for their endpoints.
  EXPECT_TRUE(findDescriptor(QStringLiteral("gitlab"))->oauth.authUrl.contains(QStringLiteral("{host}")));
  // Non-forge providers stay PAT-only for v1.
  EXPECT_FALSE(findDescriptor(QStringLiteral("todoist"))->oauth.supported);
}

TEST(RegistryCatalog, SelfEndpointMakesScopeOptional) {
  // GitHub/GitLab expose a "my issues" endpoint so an OAuth-connected user needs
  // no repo/project — the scoping field is dropped from requiredKeys.
  const ProviderDescriptor* gh = findDescriptor(QStringLiteral("github"));
  ASSERT_NE(gh, nullptr);
  EXPECT_EQ(gh->scopeKey, QStringLiteral("repo"));
  EXPECT_FALSE(gh->selfListPathTemplate.isEmpty());
  EXPECT_FALSE(gh->requiredKeys.contains(QStringLiteral("repo")));
  EXPECT_TRUE(gh->requiredKeys.contains(QStringLiteral("token")));

  const ProviderDescriptor* gl = findDescriptor(QStringLiteral("gitlab"));
  ASSERT_NE(gl, nullptr);
  EXPECT_EQ(gl->scopeKey, QStringLiteral("projectId"));
  EXPECT_FALSE(gl->selfListPathTemplate.isEmpty());
  EXPECT_FALSE(gl->requiredKeys.contains(QStringLiteral("projectId")));
  EXPECT_EQ(gl->baseUrlFallback, QStringLiteral("https://gitlab.com"));  // gitlab.com default
}

TEST(TrelloParse, ListsResolveCardStatus) {
  const QByteArray lists = R"([{"id":"L1","name":"In Progress"},{"id":"L2","name":"Done"}])";
  const QHash<QString, QString> byId = parseTrelloLists(lists);
  ASSERT_EQ(byId.size(), 2);
  EXPECT_EQ(byId.value(QStringLiteral("L1")), QStringLiteral("In Progress"));

  const QByteArray cards = R"([
    {"id":"c1","name":"Card one","desc":"d","idList":"L1","url":"https://trello.com/c/c1",
     "dateLastActivity":"2026-01-02T03:04:05Z","labels":[{"name":"red"}]},
    {"id":"c2","name":"Card two","idList":"unknown","url":"https://trello.com/c/c2"}])";
  const QVector<ExternalTask> tasks = parseTrelloCards(cards, byId);
  ASSERT_EQ(tasks.size(), 2);
  EXPECT_EQ(tasks[0].providerId, QStringLiteral("trello"));
  EXPECT_EQ(tasks[0].externalId, QStringLiteral("c1"));
  EXPECT_EQ(tasks[0].status, QStringLiteral("In Progress"));  // resolved from idList
  ASSERT_EQ(tasks[0].labels.size(), 1);
  EXPECT_EQ(tasks[1].status, QString());  // unknown list → empty (StatusMap falls back)
}

TEST(TrelloParse, HandlesGarbage) {
  EXPECT_TRUE(parseTrelloLists("{}").isEmpty());
  EXPECT_TRUE(parseTrelloCards("not json", {}).isEmpty());
}

TEST(SecretStoreCache, SetValueGetHasRemove) {
  SecretStore store;
  store.setValue(QStringLiteral("github"), QStringLiteral("token"), QStringLiteral("ghp_secret"));
  EXPECT_EQ(store.value(QStringLiteral("github"), QStringLiteral("token")), QStringLiteral("ghp_secret"));
  EXPECT_TRUE(store.has(QStringLiteral("github"), QStringLiteral("token")));

  // Setting empty clears it.
  store.setValue(QStringLiteral("github"), QStringLiteral("token"), QString());
  EXPECT_FALSE(store.has(QStringLiteral("github"), QStringLiteral("token")));

  store.setValue(QStringLiteral("jira"), QStringLiteral("token"), QStringLiteral("x"));
  store.remove(QStringLiteral("jira"), QStringLiteral("token"));
  EXPECT_FALSE(store.has(QStringLiteral("jira"), QStringLiteral("token")));
}
