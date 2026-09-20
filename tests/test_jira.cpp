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

// ── HEAP-117: the identity and context a card needs ──

TEST(JiraParse, ParsesAssigneeReporterDueTypeProjectAndFixVersion) {
  const QByteArray json = R"({
    "issues": [
      {
        "key": "LTE-77",
        "fields": {
          "summary": "s",
          "status": { "name": "To Do" },
          "created": "2026-06-01T09:00:00.000+0000",
          "updated": "2026-07-02T12:34:56.000+0000",
          "duedate": "2026-08-15",
          "assignee": { "displayName": "Ada Lovelace" },
          "reporter": { "displayName": "Grace Hopper" },
          "issuetype": { "name": "Bug" },
          "project": { "key": "LTE" },
          "fixVersions": [ { "name": "24.10" }, { "name": "24.11" } ]
        }
      }
    ]
  })";
  const QVector<ExternalTask> tasks = parseJiraIssues(json, "https://acme.atlassian.net");
  ASSERT_EQ(tasks.size(), 1);
  const ExternalTask& t = tasks[0];
  EXPECT_EQ(t.assignee, QString("Ada Lovelace"));
  EXPECT_EQ(t.author, QString("Grace Hopper"));
  EXPECT_EQ(t.issueType, QString("Bug"));
  EXPECT_EQ(t.project, QString("LTE"));
  EXPECT_EQ(t.milestone, QString("24.10"));  // the first fix version
  EXPECT_TRUE(t.createdAt.isValid());
  ASSERT_TRUE(t.dueAt.isValid());
  EXPECT_EQ(t.dueAt.date(), QDate(2026, 8, 15));
  EXPECT_FALSE(t.dueHasTime);
  // Comments are not requested, so the count stays "unknown".
  EXPECT_EQ(t.commentCount, -1);
}

TEST(JiraParse, TimestampWithColonlessOffsetIsValid) {
  // Jira sends "+0000" without the colon Qt::ISODate expects; the shared
  // timestamp parser has to accept it or every Jira date silently vanishes.
  const QByteArray json = R"({"issues":[{"key":"A-1","fields":{"summary":"s","updated":"2026-07-02T12:34:56.000+0000"}}]})";
  const QVector<ExternalTask> tasks = parseJiraIssues(json, "https://x");
  ASSERT_EQ(tasks.size(), 1);
  ASSERT_TRUE(tasks[0].updatedAt.isValid());
  EXPECT_EQ(tasks[0].updatedAt.toUTC().date(), QDate(2026, 7, 2));
  EXPECT_EQ(tasks[0].updatedAt.toUTC().time(), QTime(12, 34, 56));
}

TEST(JiraParse, MissingOptionalFieldsStayDefault) {
  const QByteArray json = R"({"issues":[{"key":"A-1","fields":{"summary":"s"}}]})";
  const QVector<ExternalTask> tasks = parseJiraIssues(json, "https://x");
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_TRUE(tasks[0].assignee.isEmpty());
  EXPECT_TRUE(tasks[0].author.isEmpty());
  EXPECT_TRUE(tasks[0].milestone.isEmpty());
  EXPECT_FALSE(tasks[0].dueAt.isValid());
}

TEST(JiraComments, FlattensAdfAndPlainStringBodies) {
  // Cloud sends ADF; Server/DC sends a plain string. Both have to read.
  const QByteArray json = R"({
    "comments": [
      {
        "author": { "displayName": "Ada Lovelace" },
        "created": "2026-07-02T12:34:56.000+0000",
        "body": { "type": "doc", "content": [
          { "type": "paragraph", "content": [ { "type": "text", "text": "Reproduced on trunk." } ] } ] }
      },
      { "author": { "displayName": "Grace Hopper" }, "created": "2026-07-01T09:00:00.000+0000",
        "body": "plain server comment" },
      { "author": { "displayName": "nobody" }, "created": "2026-07-01T09:00:00.000+0000", "body": "" }
    ]
  })";
  const QVector<heap::integrations::ExternalComment> comments = heap::integrations::parseJiraComments(json);
  ASSERT_EQ(comments.size(), 2) << "an empty body was kept";
  EXPECT_EQ(comments[0].author, QString("Ada Lovelace"));
  EXPECT_TRUE(comments[0].body.contains("Reproduced on trunk."));
  EXPECT_TRUE(comments[0].createdAt.isValid()) << "the colon-less offset did not parse";
  EXPECT_EQ(comments[1].body, QString("plain server comment"));
}

TEST(JiraComments, HandlesGarbage) {
  EXPECT_TRUE(heap::integrations::parseJiraComments(QByteArray()).isEmpty());
  EXPECT_TRUE(heap::integrations::parseJiraComments("[]").isEmpty());
  EXPECT_TRUE(heap::integrations::parseJiraComments("garbage").isEmpty());
  EXPECT_TRUE(heap::integrations::parseJiraComments(R"({"comments":[]})").isEmpty());
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

  // Self-hosted: a pasted ticket URL is the single most likely paste, and
  // keeping its path sent every API call to "<host>/browse/TEL-1/rest/api/…".
  EXPECT_EQ(normalizeJiraBaseUrl("https://j.example.com/browse/TEL-123456"), QStringLiteral("https://j.example.com"));
  EXPECT_EQ(normalizeJiraBaseUrl("j.example.com/browse/TEL-123456"), QStringLiteral("https://j.example.com"));
  EXPECT_EQ(normalizeJiraBaseUrl("https://j.example.com/secure/RapidBoard.jspa?rapidView=7"), QStringLiteral("https://j.example.com"));
  EXPECT_EQ(normalizeJiraBaseUrl("https://j.example.com/projects/TEL/issues"), QStringLiteral("https://j.example.com"));
  // …but a real deployment prefix has to survive, including in front of a route.
  EXPECT_EQ(normalizeJiraBaseUrl("https://corp.example.com/jira/browse/TEL-1"), QStringLiteral("https://corp.example.com/jira"));
  EXPECT_EQ(normalizeJiraBaseUrl("https://corp.example.com/jira/secure/Dashboard.jspa"), QStringLiteral("https://corp.example.com/jira"));
  // An API URL names its own root.
  EXPECT_EQ(normalizeJiraBaseUrl("https://j.example.com/rest/api/2/myself"), QStringLiteral("https://j.example.com"));
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
  // These exercise the Cloud API (/rest/api/3 + Basic); a loopback host would
  // otherwise be detected as Server/DC, which is a different product.
  p.setDeployment(heap::integrations::JiraDeployment::Cloud);

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
  // These exercise the Cloud API (/rest/api/3 + Basic); a loopback host would
  // otherwise be detected as Server/DC, which is a different product.
  p.setDeployment(heap::integrations::JiraDeployment::Cloud);

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
  // Jira's own words survive — they are more specific than anything generic —
  // and the fix to make is appended rather than replacing them.
  EXPECT_TRUE(error.startsWith(QString::fromUtf8("HTTP 401 — Basic auth with password is not allowed"))) << error.toStdString();
  EXPECT_TRUE(error.contains(QStringLiteral("API token"))) << error.toStdString();
}

TEST_F(JiraNetwork, PullPostsTheBoundedDefaultJql) {
  FakeJira server;
  server.route("POST /rest/api/3/search/jql", {200, R"({"issues":[{"key":"LTE-1","fields":{"summary":"S","status":{"name":"Done"}}}]})"});

  heap::integrations::JiraProvider p;
  p.setConfig(server.base(), QStringLiteral("me@example.com"), QStringLiteral("tok"), QString());
  // These exercise the Cloud API (/rest/api/3 + Basic); a loopback host would
  // otherwise be detected as Server/DC, which is a different product.
  p.setDeployment(heap::integrations::JiraDeployment::Cloud);

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
  // The endpoint returns only the fields asked for, so the identity fields the
  // card renders (HEAP-117) have to be in the request or they never arrive.
  for(const char* field : {"assignee", "reporter", "duedate", "created", "issuetype", "project", "fixVersions"}) {
    EXPECT_TRUE(server.lastBody().contains(field)) << field << " missing from " << server.lastBody().toStdString();
  }
  // Asking for `comment` would inline every comment body of all 100 issues.
  EXPECT_FALSE(server.lastBody().contains("\"comment\"")) << server.lastBody().toStdString();
}

TEST_F(JiraNetwork, ReportsAFailedPullInsteadOfAnEmptyList) {
  FakeJira server;
  server.route("POST /rest/api/3/search/jql", {400, R"({"errorMessages":["Unbounded JQL queries are not allowed here."]})"});

  heap::integrations::JiraProvider p;
  p.setConfig(server.base(), QStringLiteral("me@example.com"), QStringLiteral("tok"), QStringLiteral("order by updated DESC"));
  // These exercise the Cloud API (/rest/api/3 + Basic); a loopback host would
  // otherwise be detected as Server/DC, which is a different product.
  p.setDeployment(heap::integrations::JiraDeployment::Cloud);

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
  // These exercise the Cloud API (/rest/api/3 + Basic); a loopback host would
  // otherwise be detected as Server/DC, which is a different product.
  p.setDeployment(heap::integrations::JiraDeployment::Cloud);

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

// ── What an unauthorized Jira actually tells the user ───────────────────────
// Qt renders every 401 as "Host requires authentication" and Jira's own body
// ("Client must be authenticated to access this resource") is no better: both
// leave the user with nothing to change. In practice it is one of three things
// — the account password instead of an API token, an email that belongs to a
// different Atlassian account, or a Server/DC site that is not supported.

TEST_F(JiraNetwork, ARejectedTokenNamesWhatToChange) {
  FakeJira server;
  server.route("GET /rest/api/3/myself", {401, R"({"message":"Client must be authenticated to access this resource."})"});
  // A Cloud site would answer this; a Server/DC one 404s, which is the tell.
  server.route("GET /_edge/tenant_info", {404, R"({})"});

  heap::integrations::JiraProvider p;
  p.setGatewayRoot(server.base());
  p.setConfig(server.base(), QStringLiteral("me@example.com"), QStringLiteral("not-a-token"), QString());
  // These exercise the Cloud API (/rest/api/3 + Basic); a loopback host would
  // otherwise be detected as Server/DC, which is a different product.
  p.setDeployment(heap::integrations::JiraDeployment::Cloud);

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
  EXPECT_FALSE(error.contains(QStringLiteral("Host requires authentication"))) << error.toStdString();
  EXPECT_TRUE(error.contains(QStringLiteral("API token"))) << error.toStdString();
  EXPECT_TRUE(error.contains(QStringLiteral("id.atlassian.com"))) << error.toStdString();
  // The site refused us and is not Cloud, so say the thing that is easy to miss.
  EXPECT_TRUE(error.contains(QStringLiteral("Data Center"))) << error.toStdString();
}

TEST_F(JiraNetwork, ACloudSiteThatStillRefusesDoesNotBlameTheEdition) {
  FakeJira server;
  server.route("GET /rest/api/3/myself", {401, R"({"message":"Client must be authenticated to access this resource."})"});
  server.route("GET /_edge/tenant_info", {200, R"({"cloudId":"cid-123"})"});
  // The gateway is the one that has the final say, and it refuses too.
  server.route("GET /ex/jira/cid-123/rest/api/3/myself", {401, R"({"message":"Unauthorized"})"});

  heap::integrations::JiraProvider p;
  p.setGatewayRoot(server.base());
  p.setConfig(server.base(), QStringLiteral("wrong@example.com"), QStringLiteral("tok"), QString());
  // These exercise the Cloud API (/rest/api/3 + Basic); a loopback host would
  // otherwise be detected as Server/DC, which is a different product.
  p.setDeployment(heap::integrations::JiraDeployment::Cloud);

  bool done = false;
  QString error;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool, const QString& e) {
    error = e;
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done));
  EXPECT_TRUE(error.contains(QStringLiteral("API token"))) << error.toStdString();
  EXPECT_FALSE(error.contains(QStringLiteral("Data Center")))
      << "the cloudId resolved, so the edition is not the problem: " << error.toStdString();
}

TEST_F(JiraNetwork, AnExpiredBrowserSessionSaysToSignInAgain) {
  FakeJira server;
  server.route("GET /ex/jira/cid-123/rest/api/3/myself", {401, R"({"message":"Unauthorized"})"});

  heap::integrations::JiraProvider p;
  p.setGatewayRoot(server.base());
  p.setOAuthConfig(QStringLiteral("cid-123"), QStringLiteral("https://acme.atlassian.net"), QStringLiteral("stale"), QString());

  bool done = false;
  QString error;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool, const QString& e) {
    error = e;
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done));
  EXPECT_TRUE(error.contains(QStringLiteral("sign in again"))) << error.toStdString();
  EXPECT_FALSE(error.contains(QStringLiteral("API token"))) << "there is no token to fix in a browser session";
}

TEST_F(JiraNetwork, ANonAuthFailureIsLeftAlone) {
  FakeJira server;
  server.route("POST /rest/api/3/search/jql", {400, R"({"errorMessages":["Unbounded JQL queries are not allowed here."]})"});

  heap::integrations::JiraProvider p;
  p.setConfig(server.base(), QStringLiteral("me@example.com"), QStringLiteral("tok"), QStringLiteral("order by updated DESC"));
  // These exercise the Cloud API (/rest/api/3 + Basic); a loopback host would
  // otherwise be detected as Server/DC, which is a different product.
  p.setDeployment(heap::integrations::JiraDeployment::Cloud);

  bool done = false;
  QString error;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::pullFailed, &p, [&](int, const QString& e) {
    error = e;
    done = true;
  });
  p.pullTasks();
  ASSERT_TRUE(waitFor(done));
  EXPECT_EQ(error, QString::fromUtf8("HTTP 400 — Unbounded JQL queries are not allowed here."))
      << "only 401 is rewritten; everything else keeps the tracker's own words";
}

// ── Jira Server / Data Center ───────────────────────────────────────────────
// A different product behind the same name: /rest/api/2 instead of v3, a
// Personal Access Token as a bearer credential instead of an email+token pair,
// and POST /search instead of Cloud's /search/jql. Getting it wrong produces a
// 401 or a 404 that points at nothing.

TEST(JiraDeploymentDetect, ReadsTheDeploymentTypeFromServerInfo) {
  using heap::integrations::JiraDeployment;
  using heap::integrations::parseJiraDeployment;
  EXPECT_EQ(parseJiraDeployment(R"({"deploymentType":"Cloud","version":"1001.0.0"})"), JiraDeployment::Cloud);
  EXPECT_EQ(parseJiraDeployment(R"({"deploymentType":"Server","version":"9.12.1"})"), JiraDeployment::Server);
  // Atlassian reports Data Center as "Server", but accept the explicit spelling.
  EXPECT_EQ(parseJiraDeployment(R"({"deploymentType":"DataCenter"})"), JiraDeployment::Server);
  EXPECT_EQ(parseJiraDeployment(R"({"deploymentType":"server"})"), JiraDeployment::Server);
  // Nothing usable: the caller falls back to the URL.
  EXPECT_EQ(parseJiraDeployment(R"({"version":"9.12.1"})"), JiraDeployment::Unknown);
  EXPECT_EQ(parseJiraDeployment("not json"), JiraDeployment::Unknown);
}

TEST(JiraDeploymentDetect, TheUrlIsTheFallbackEvidence) {
  using heap::integrations::guessJiraDeployment;
  using heap::integrations::JiraDeployment;
  EXPECT_EQ(guessJiraDeployment(QStringLiteral("https://acme.atlassian.net")), JiraDeployment::Cloud);
  EXPECT_EQ(guessJiraDeployment(QStringLiteral("acme.atlassian.net/browse/X-1")), JiraDeployment::Cloud);
  // Only Atlassian runs atlassian.net; a company domain is self-hosted.
  EXPECT_EQ(guessJiraDeployment(QStringLiteral("https://j.example.com")), JiraDeployment::Server);
  EXPECT_EQ(guessJiraDeployment(QStringLiteral("https://jira.corp.example.com/jira")), JiraDeployment::Server);
  EXPECT_EQ(guessJiraDeployment(QString()), JiraDeployment::Unknown);
}

TEST_F(JiraNetwork, DetectsServerAndUsesV2WithABearerToken) {
  FakeJira server;
  server.route("GET /rest/api/2/serverInfo", {200, R"({"deploymentType":"Server","version":"9.12.1"})"});
  server.route("GET /rest/api/2/myself", {200, R"({"name":"alex"})"});

  heap::integrations::JiraProvider p;
  // No email: a Personal Access Token authenticates on its own.
  p.setConfig(server.base(), QString(), QStringLiteral("pat-abc"), QString());
  ASSERT_TRUE(p.isConfigured()) << "Server/DC needs no account email";

  bool done = false;
  bool ok = false;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool o, const QString&) {
    ok = o;
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done));
  EXPECT_TRUE(ok);
  EXPECT_EQ(p.deployment(), heap::integrations::JiraDeployment::Server);

  EXPECT_EQ(server.lastRequest("GET /rest/api/2/myself").headers.value("authorization"), QByteArray("Bearer pat-abc"));
  // v3 is Cloud-only and would 404 here.
  EXPECT_FALSE(server.seen().contains("GET /rest/api/3/myself"));
}

TEST_F(JiraNetwork, ServerPullsThroughTheV2SearchEndpoint) {
  FakeJira server;
  server.route("GET /rest/api/2/serverInfo", {200, R"({"deploymentType":"Server"})"});
  // Server/DC never had /search/jql, and its description is plain text rather
  // than the ADF document Cloud returns.
  server.route("POST /rest/api/2/search", {200, R"({"issues":[
      {"key":"TEL-123","fields":{"summary":"Handover fails","description":"plain text body",
       "status":{"name":"In Progress"},"priority":{"name":"High"},"labels":["ran"],
       "updated":"2026-01-02T03:04:05.000+0300"}}]})"});

  heap::integrations::JiraProvider p;
  p.setConfig(server.base(), QString(), QStringLiteral("pat"), QString());

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
  EXPECT_EQ(got[0].externalId, QStringLiteral("TEL-123"));
  EXPECT_EQ(got[0].body, QStringLiteral("plain text body")) << "a v2 description is a string, not ADF";
  EXPECT_EQ(got[0].url, server.base() + QStringLiteral("/browse/TEL-123"));
  EXPECT_FALSE(server.seen().contains("POST /rest/api/3/search/jql"));
}

TEST_F(JiraNetwork, ServerNeverTriesTheCloudGateway) {
  FakeJira server;
  server.route("GET /rest/api/2/serverInfo", {200, R"({"deploymentType":"Server"})"});
  server.route("GET /rest/api/2/myself", {401, R"({"message":"Unauthorized"})"});

  heap::integrations::JiraProvider p;
  p.setGatewayRoot(server.base());
  p.setConfig(server.base(), QString(), QStringLiteral("bad-pat"), QString());

  bool done = false;
  QString error;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool, const QString& e) {
    error = e;
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done));

  // api.atlassian.com is a Cloud-only thing; chasing it here wastes a request
  // and hides the real answer.
  EXPECT_FALSE(server.seen().contains("GET /_edge/tenant_info"));
  EXPECT_TRUE(error.contains(QStringLiteral("Personal Access Token"))) << error.toStdString();
  EXPECT_FALSE(error.contains(QStringLiteral("id.atlassian.com"))) << "that is the Cloud advice: " << error.toStdString();
}

TEST_F(JiraNetwork, AServerInstanceThatHidesServerInfoIsStillDetectedFromItsUrl) {
  FakeJira server;
  // Behind SSO, anonymous reads refused — the URL is the only evidence left.
  server.route("GET /rest/api/2/serverInfo", {401, R"({})"});
  server.route("GET /rest/api/2/myself", {200, R"({"name":"alex"})"});

  heap::integrations::JiraProvider p;
  p.setConfig(server.base(), QString(), QStringLiteral("pat"), QString());

  bool done = false;
  bool ok = false;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool o, const QString&) {
    ok = o;
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done));
  EXPECT_TRUE(ok);
  EXPECT_EQ(p.deployment(), heap::integrations::JiraDeployment::Server) << "a loopback host is not atlassian.net";
}

TEST_F(JiraNetwork, AnOldServerWithoutPatsStillWorksOnBasicAuth) {
  FakeJira server;
  server.route("GET /rest/api/2/serverInfo", {200, R"({"deploymentType":"Server"})"});
  server.route("GET /rest/api/2/myself", {200, R"({"name":"alex"})"});

  heap::integrations::JiraProvider p;
  // Filling in the username opts back into Basic, for a Jira too old for PATs.
  p.setConfig(server.base(), QStringLiteral("alex"), QStringLiteral("password"), QString());

  bool done = false;
  QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool, const QString&) {
    done = true;
  });
  p.testConnection();
  ASSERT_TRUE(waitFor(done));
  EXPECT_TRUE(server.lastRequest("GET /rest/api/2/myself").headers.value("authorization").startsWith("Basic "));
}

TEST_F(JiraNetwork, TheDeploymentIsProbedOnceNotPerRequest) {
  FakeJira server;
  server.route("GET /rest/api/2/serverInfo", {200, R"({"deploymentType":"Server"})"});
  server.route("GET /rest/api/2/myself", {200, R"({"name":"alex"})"});

  heap::integrations::JiraProvider p;
  p.setConfig(server.base(), QString(), QStringLiteral("pat"), QString());

  for(int i = 0; i < 3; ++i) {
    bool done = false;
    QObject::connect(&p, &heap::integrations::IntegrationProvider::connectionTested, &p, [&](bool, const QString&) {
      done = true;
    });
    p.testConnection();
    ASSERT_TRUE(waitFor(done));
  }
  int probes = 0;
  for(const QByteArray& seen : server.seen()) {
    probes += seen == "GET /rest/api/2/serverInfo" ? 1 : 0;
  }
  EXPECT_EQ(probes, 1) << "the answer does not change between requests";
}
