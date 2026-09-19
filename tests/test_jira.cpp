#include "FakeHttpServer.h"

#include "integrations/JiraProvider.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QHostAddress>
#include <QTcpServer>
#include <QTcpSocket>

#include <gtest/gtest.h>

using heap::integrations::ExternalTask;
using heap::integrations::jiraAdfToPlainText;
using heap::integrations::parseJiraIssues;

TEST(JiraParse, ParsesSearchResponse) {
  const QByteArray json = R"({
    "issues": [
      {
        "key": "LTE-2398",
        "fields": {
          "summary": "Handover fails on X2",
          "description": {
            "type": "doc",
            "content": [
              { "type": "paragraph", "content": [ { "type": "text", "text": "First line." } ] },
              { "type": "paragraph", "content": [ { "type": "text", "text": "Second line." } ] }
            ]
          },
          "status": { "name": "In Progress" },
          "priority": { "name": "High" },
          "labels": ["radio", "urgent"],
          "updated": "2026-07-02T12:34:56.000+0000"
        }
      }
    ]
  })";

  const QVector<ExternalTask> tasks = parseJiraIssues(json, "https://acme.atlassian.net/");
  ASSERT_EQ(tasks.size(), 1);

  const ExternalTask& t = tasks.first();
  EXPECT_EQ(t.providerId, QString("jira"));
  EXPECT_EQ(t.externalId, QString("LTE-2398"));
  // Trailing slash on baseUrl is trimmed before building the browse URL.
  EXPECT_EQ(t.url, QString("https://acme.atlassian.net/browse/LTE-2398"));
  EXPECT_EQ(t.title, QString("Handover fails on X2"));
  EXPECT_EQ(t.status, QString("In Progress"));
  EXPECT_EQ(t.priority, QString("High"));
  ASSERT_EQ(t.labels.size(), 2);
  EXPECT_EQ(t.labels[0], QString("radio"));
  // ADF flattened to plain text, paragraphs preserved on separate lines.
  EXPECT_TRUE(t.body.contains("First line."));
  EXPECT_TRUE(t.body.contains("Second line."));
}

TEST(JiraParse, PlainStringDescriptionAndEmpty) {
  // Some responses (or older APIs) carry a plain-string description.
  const QByteArray json = R"({
    "issues": [
      { "key": "AB-1", "fields": { "summary": "s", "description": "just text", "status": { "name": "Done" } } }
    ]
  })";
  const QVector<ExternalTask> tasks = parseJiraIssues(json, "https://x.atlassian.net");
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].body, QString("just text"));
  EXPECT_EQ(tasks[0].status, QString("Done"));

  EXPECT_TRUE(parseJiraIssues(QByteArray(), "https://x").isEmpty());
  EXPECT_TRUE(parseJiraIssues("[]", "https://x").isEmpty());  // array, not the search object
  EXPECT_TRUE(parseJiraIssues("garbage", "https://x").isEmpty());
}

TEST(JiraAdf, FlattensNestedContent) {
  const QByteArray adf = R"({
    "type": "doc",
    "content": [
      { "type": "paragraph", "content": [ { "type": "text", "text": "Hello " }, { "type": "text", "text": "world" } ] }
    ]
  })";
  const QString text = jiraAdfToPlainText(adf);
  EXPECT_TRUE(text.contains("Hello world"));
}

// ── Base URL normalization ──────────────────────────────────────────────────
// People paste whatever their browser showed. Anything that is not a site root
// produced a 404 on every call.

TEST(JiraBaseUrl, NormalizesWhatPeoplePaste) {
  using heap::integrations::normalizeJiraBaseUrl;
  const QString want = QStringLiteral("https://acme.atlassian.net");
  EXPECT_EQ(normalizeJiraBaseUrl("https://acme.atlassian.net"), want);
  EXPECT_EQ(normalizeJiraBaseUrl("  https://acme.atlassian.net/  "), want);
  EXPECT_EQ(normalizeJiraBaseUrl("acme.atlassian.net"), want);  // scheme added
  EXPECT_EQ(normalizeJiraBaseUrl("https://ACME.atlassian.net"), want);
  // A board / project / issue URL straight out of the address bar.
  EXPECT_EQ(normalizeJiraBaseUrl("https://acme.atlassian.net/jira/software/projects/LTE/boards/1"), want);
  EXPECT_EQ(normalizeJiraBaseUrl("https://acme.atlassian.net/browse/LTE-42"), want);
  EXPECT_EQ(normalizeJiraBaseUrl("https://acme.atlassian.net/jira/your-work?atlOrigin=x"), want);

  // A self-hosted instance may legitimately live under a path prefix, so only
  // trailing slashes are trimmed there.
  EXPECT_EQ(normalizeJiraBaseUrl("https://jira.corp.example.com/jira/"), QStringLiteral("https://jira.corp.example.com/jira"));
  EXPECT_EQ(normalizeJiraBaseUrl("http://127.0.0.1:8080"), QStringLiteral("http://127.0.0.1:8080"));
  EXPECT_EQ(normalizeJiraBaseUrl("   "), QString());
}

TEST(JiraJql, DefaultIsBounded) {
  // /search/jql rejects a query with no search restriction ("Unbounded JQL
  // queries are not allowed here"), which an "order by"-only default is.
  const QString jql = heap::integrations::defaultJiraJql();
  EXPECT_TRUE(jql.contains(QStringLiteral("currentUser()")));
  EXPECT_FALSE(jql.trimmed().startsWith(QStringLiteral("ORDER"), Qt::CaseInsensitive));
}

// ── Scoped-token fallback ───────────────────────────────────────────────────
// Atlassian's newer scoped API tokens are rejected by the site host with a 401
// and only work through https://api.atlassian.com/ex/jira/{cloudId}. The
// provider takes that 401 as the signal to resolve the site's cloudId and retry
// once through the gateway. Driven against a local fake server.

namespace {
using FakeJira = heap::testing::FakeHttpServer;
using heap::testing::waitFor;
}  // namespace

class JiraNetwork : public ::testing::Test {
 protected:
  static void SetUpTestSuite() {
    // QNetworkAccessManager needs an application object; it outlives the suite
    // on purpose.
    if(QCoreApplication::instance() == nullptr) {
      static int argc = 1;
      static char arg0[] = "heap_jira_tests";
      static char* argv[] = {arg0, nullptr};
      new QCoreApplication(argc, argv);
    }
  }
};

TEST_F(JiraNetwork, RetriesThroughTheGatewayWhenTheSiteAnswers401) {
  FakeJira server;
  server.route("GET /rest/api/3/myself", {401, R"({"errorMessages":["Client must be authenticated to access this resource."]})"});
  server.route("GET /_edge/tenant_info", {200, R"({"cloudId":"cid-123"})"});
  server.route("GET /ex/jira/cid-123/rest/api/3/myself", {200, R"({"accountId":"a1"})"});

  heap::integrations::JiraProvider p;
  p.setGatewayRoot(server.base());
  p.setConfig(server.base(), QStringLiteral("me@example.com"), QStringLiteral("scoped-token"), QString());

  bool done = false;
  bool ok = false;
  QString error;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool o, const QString& e) {
    ok = o;
    error = e;
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done)) << "connectionTested never arrived";
  EXPECT_TRUE(ok) << error.toStdString();
  ASSERT_EQ(server.seen().size(), 3);
  EXPECT_EQ(server.seen()[0], QByteArray("GET /rest/api/3/myself"));
  EXPECT_EQ(server.seen()[1], QByteArray("GET /_edge/tenant_info"));
  EXPECT_EQ(server.seen()[2], QByteArray("GET /ex/jira/cid-123/rest/api/3/myself"));
}

TEST_F(JiraNetwork, KeepsTheOriginal401WhenThereIsNoCloudId) {
  FakeJira server;
  server.route("GET /rest/api/3/myself", {401, R"({"errorMessages":["Basic auth with password is not allowed"]})"});
  // /_edge/tenant_info is unrouted → 404, so the fallback cannot proceed.

  heap::integrations::JiraProvider p;
  p.setGatewayRoot(server.base());
  p.setConfig(server.base(), QStringLiteral("me@example.com"), QStringLiteral("bad"), QString());

  bool done = false;
  bool ok = true;
  QString error;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool o, const QString& e) {
    ok = o;
    error = e;
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done));
  EXPECT_FALSE(ok);
  // The user sees Jira's own words, not "server replied: Unauthorized".
  EXPECT_EQ(error, QString::fromUtf8("HTTP 401 — Basic auth with password is not allowed"));
}

TEST_F(JiraNetwork, PullPostsTheBoundedDefaultJql) {
  FakeJira server;
  server.route("POST /rest/api/3/search/jql", {200, R"({"issues":[{"key":"LTE-1","fields":{"summary":"S","status":{"name":"Done"}}}]})"});

  heap::integrations::JiraProvider p;
  p.setConfig(server.base(), QStringLiteral("me@example.com"), QStringLiteral("tok"), QString());

  bool done = false;
  QVector<ExternalTask> got;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::tasksFetched, &p, [&](const QVector<ExternalTask>& t) {
    got = t;
    done = true;
  });
  QObject::connect(&p, &heap::integrations::IntegrationProvider::pullFailed, &p, [&](int, const QString&) {
    done = true;
  });
  p.pullTasks();
  ASSERT_TRUE(waitFor(done));
  ASSERT_EQ(got.size(), 1);
  EXPECT_EQ(got[0].externalId, QStringLiteral("LTE-1"));
  // The browse URL is built from the site, never from the API base.
  EXPECT_EQ(got[0].url, server.base() + QStringLiteral("/browse/LTE-1"));
  // POST, not GET: keeps a long JQL out of the URL and `fields` a real array.
  EXPECT_EQ(server.seen().value(0), QByteArray("POST /rest/api/3/search/jql"));
  EXPECT_TRUE(server.lastBody().contains("currentUser()")) << server.lastBody().toStdString();
}

TEST_F(JiraNetwork, ReportsAFailedPullInsteadOfAnEmptyList) {
  FakeJira server;
  server.route("POST /rest/api/3/search/jql", {400, R"({"errorMessages":["Unbounded JQL queries are not allowed here."]})"});

  heap::integrations::JiraProvider p;
  p.setConfig(server.base(), QStringLiteral("me@example.com"), QStringLiteral("tok"), QStringLiteral("order by updated DESC"));

  bool done = false;
  bool fetched = false;
  int status = 0;
  QString error;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::tasksFetched, &p, [&](const QVector<ExternalTask>&) {
    fetched = true;
    done = true;
  });
  QObject::connect(&p, &heap::integrations::IntegrationProvider::pullFailed, &p, [&](int s, const QString& e) {
    status = s;
    error = e;
    done = true;
  });
  p.pullTasks();
  ASSERT_TRUE(waitFor(done));
  EXPECT_FALSE(fetched) << "a failure must not look like an empty backlog";
  EXPECT_EQ(status, 400);
  EXPECT_EQ(error, QString::fromUtf8("HTTP 400 — Unbounded JQL queries are not allowed here."));
}

// ── Browser sign-in (OAuth 2.0 3LO) ─────────────────────────────────────────
// A 3LO access token is a Bearer credential that the site host never accepts:
// every call has to go through api.atlassian.com/ex/jira/{cloudId}, and the
// cloudId is only knowable by asking accessible-resources at sign-in time.

TEST(JiraSitePick, PrefersTheSiteTheCardAlreadyNames) {
  const QByteArray json = R"([
    {"id":"cid-a","url":"https://a.atlassian.net","name":"A"},
    {"id":"cid-b","url":"https://b.atlassian.net","name":"B"}])";
  const auto picked = heap::integrations::pickJiraSite(json, QStringLiteral("https://b.atlassian.net"));
  EXPECT_EQ(picked.cloudId, QStringLiteral("cid-b")) << "switching sites would repoint every synced issue";
  EXPECT_EQ(picked.url, QStringLiteral("https://b.atlassian.net"));

  // The preference is matched after normalisation, so a pasted browser URL works.
  EXPECT_EQ(heap::integrations::pickJiraSite(json, QStringLiteral("b.atlassian.net/jira/software/projects/X/boards/1")).cloudId,
            QStringLiteral("cid-b"));
}

TEST(JiraSitePick, FallsBackToTheFirstSite) {
  const QByteArray json = R"([{"id":"cid-a","url":"https://a.atlassian.net","name":"A"}])";
  EXPECT_EQ(heap::integrations::pickJiraSite(json, QString()).cloudId, QStringLiteral("cid-a"));
  // A site the token was not granted is not honoured.
  EXPECT_EQ(heap::integrations::pickJiraSite(json, QStringLiteral("https://nope.atlassian.net")).cloudId, QStringLiteral("cid-a"));
}

TEST(JiraSitePick, NoGrantedSiteIsEmpty) {
  EXPECT_TRUE(heap::integrations::pickJiraSite("[]", QString()).cloudId.isEmpty());
  EXPECT_TRUE(heap::integrations::pickJiraSite("not json", QString()).cloudId.isEmpty());
  EXPECT_TRUE(heap::integrations::pickJiraSite({}, QStringLiteral("https://a.atlassian.net")).cloudId.isEmpty());
}

TEST_F(JiraNetwork, OAuthModeSendsABearerThroughTheGateway) {
  FakeJira server;
  server.route("GET /ex/jira/cid-123/rest/api/3/myself", {200, R"({"accountId":"a1"})"});

  heap::integrations::JiraProvider p;
  p.setGatewayRoot(server.base());
  p.setOAuthConfig(QStringLiteral("cid-123"), QStringLiteral("https://acme.atlassian.net"), QStringLiteral("at-3lo"), QString());
  ASSERT_TRUE(p.isConfigured()) << "OAuth needs no email and no base URL";

  bool done = false;
  bool ok = false;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool o, const QString&) {
    ok = o;
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done));
  EXPECT_TRUE(ok);

  const auto req = server.lastRequest("GET /ex/jira/cid-123/rest/api/3/myself");
  EXPECT_EQ(req.headers.value("authorization"), QByteArray("Bearer at-3lo")) << "a 3LO token is not a Basic credential";
  // Never the site host: it answers 401 for a 3LO token, and there is no
  // fallback left to run.
  EXPECT_FALSE(server.seen().contains("GET /rest/api/3/myself"));
  EXPECT_FALSE(server.seen().contains("GET /_edge/tenant_info"));
}

TEST_F(JiraNetwork, OAuthModeWithoutACloudIdIsNotConfigured) {
  // The sign-in landed but accessible-resources granted nothing, so there is no
  // API base. Better to stay unconfigured than to send every call to /ex/jira/.
  heap::integrations::JiraProvider p;
  p.setOAuthConfig(QString(), QStringLiteral("https://acme.atlassian.net"), QStringLiteral("at"), QString());
  EXPECT_FALSE(p.isConfigured());
}

TEST_F(JiraNetwork, SwitchingBackToBasicAuthForgetsTheGateway) {
  FakeJira server;
  server.route("GET /rest/api/3/myself", {200, R"({"accountId":"a1"})"});

  heap::integrations::JiraProvider p;
  p.setGatewayRoot(server.base());
  p.setOAuthConfig(QStringLiteral("cid-123"), server.base(), QStringLiteral("at-3lo"), QString());
  // Signing out and pasting an API token instead.
  p.setConfig(server.base(), QStringLiteral("me@example.com"), QStringLiteral("tok"), QString());

  bool done = false;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool, const QString&) {
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done));

  const auto req = server.lastRequest("GET /rest/api/3/myself");
  EXPECT_TRUE(req.headers.value("authorization").startsWith("Basic ")) << "a stale Bearer would 401 forever";
  EXPECT_FALSE(server.seen().contains("GET /ex/jira/cid-123/rest/api/3/myself"));
}
