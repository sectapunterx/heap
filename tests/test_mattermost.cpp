// The Mattermost directory client: the pure parsers over canned JSON, and the
// request choreography driven against a local fake server.
//
// Mattermost is the one integration that imports people rather than issues, so
// the interesting cases are about who gets skipped (bots, deactivated accounts,
// yourself, channels you never used) and about the two ways of signing in.

#include "FakeHttpServer.h"

#include "integrations/MattermostClient.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>

#include <gtest/gtest.h>

using heap::integrations::dmPeerId;
using heap::integrations::ExternalContact;
using heap::integrations::MattermostClient;
using heap::integrations::mattermostDisplayName;
using heap::integrations::mattermostRoleLabel;
using heap::integrations::parseMattermostUser;
using heap::integrations::parseMattermostUsers;
using heap::testing::FakeHttpServer;
using heap::testing::waitFor;

// ── Pure helpers ────────────────────────────────────────────────────────────

TEST(MattermostName, PrefersFullNameThenNicknameThenUsername) {
  EXPECT_EQ(mattermostDisplayName(R"({"username":"o.t","first_name":"Olga","last_name":"Titova","nickname":"olya"})"),
            QStringLiteral("Olga Titova"));
  // Half a name is still a name.
  EXPECT_EQ(mattermostDisplayName(R"({"username":"o.t","first_name":"Olga","last_name":"","nickname":"olya"})"), QStringLiteral("Olga"));
  EXPECT_EQ(mattermostDisplayName(R"({"username":"o.t","first_name":"","last_name":"","nickname":"olya"})"), QStringLiteral("olya"));
  // Every optional field blank, which is the default for a fresh account.
  EXPECT_EQ(mattermostDisplayName(R"({"username":"o.t"})"), QStringLiteral("o.t"));
}

TEST(MattermostRole, FallsBackToTheRolesWhenThereIsNoJobTitle) {
  EXPECT_EQ(mattermostRoleLabel(QStringLiteral("system_user system_admin"), QString()), QStringLiteral("System admin"));
  EXPECT_EQ(mattermostRoleLabel(QStringLiteral("system_user"), QStringLiteral("channel_user channel_admin")),
            QStringLiteral("Channel admin"));
  EXPECT_EQ(mattermostRoleLabel(QStringLiteral("system_guest"), QString()), QStringLiteral("Guest"));
  EXPECT_EQ(mattermostRoleLabel(QStringLiteral("system_user"), QStringLiteral("channel_user")), QStringLiteral("Member"));
  // A system admin is a system admin wherever you met them.
  EXPECT_EQ(mattermostRoleLabel(QStringLiteral("system_admin"), QStringLiteral("channel_user")), QStringLiteral("System admin"));
}

TEST(MattermostUser, MapsTheFieldsHeapActuallyShows) {
  const ExternalContact c = parseMattermostUser(R"({
    "id":"u1","username":"olga.t","first_name":"Olga","last_name":"Titova",
    "position":"Tech Lead","roles":"system_user","email":"olga@acme.com","delete_at":0})");
  EXPECT_EQ(c.providerId, QStringLiteral("mattermost"));
  EXPECT_EQ(c.externalId, QStringLiteral("u1"));
  EXPECT_EQ(c.username, QStringLiteral("olga.t"));
  EXPECT_EQ(c.displayName, QStringLiteral("Olga Titova"));
  EXPECT_EQ(c.role, QStringLiteral("Tech Lead")) << "a job title the person set beats anything derived";
  EXPECT_EQ(c.email, QStringLiteral("olga@acme.com"));
  EXPECT_FALSE(c.isBot);
  EXPECT_FALSE(c.deactivated);
}

TEST(MattermostUser, FlagsBotsAndDeactivatedAccounts) {
  EXPECT_TRUE(parseMattermostUser(R"({"id":"b1","username":"jenkins","is_bot":true})").isBot);
  // Mattermost never deletes a user — it stamps delete_at instead.
  EXPECT_TRUE(parseMattermostUser(R"({"id":"u9","username":"former","delete_at":1699999999000})").deactivated);
  EXPECT_FALSE(parseMattermostUser(R"({"id":"u9","username":"current","delete_at":0})").deactivated);
}

TEST(MattermostUsers, SkipsEntriesWithNoId) {
  const auto users = parseMattermostUsers(R"([{"id":"u1","username":"a"},{"username":"nobody"},{"id":"u2","username":"b"}])");
  ASSERT_EQ(users.size(), 2);
  EXPECT_EQ(users[0].externalId, QStringLiteral("u1"));
  EXPECT_EQ(users[1].externalId, QStringLiteral("u2"));
  EXPECT_TRUE(parseMattermostUsers("not json").isEmpty());
}

TEST(MattermostDm, TheOtherHalfOfTheChannelNameIsThePeer) {
  EXPECT_EQ(dmPeerId(QStringLiteral("me__them"), QStringLiteral("me")), QStringLiteral("them"));
  EXPECT_EQ(dmPeerId(QStringLiteral("them__me"), QStringLiteral("me")), QStringLiteral("them"));
  // The self-DM every account has, someone else's conversation, and junk.
  EXPECT_TRUE(dmPeerId(QStringLiteral("me__me"), QStringLiteral("me")).isEmpty());
  EXPECT_TRUE(dmPeerId(QStringLiteral("a__b"), QStringLiteral("me")).isEmpty());
  EXPECT_TRUE(dmPeerId(QStringLiteral("nounderscores"), QStringLiteral("me")).isEmpty());
  EXPECT_TRUE(dmPeerId(QStringLiteral("me__them"), QString()).isEmpty());
}

TEST(MattermostHost, PlainHttpIsOnlyAcceptableOnLoopback) {
  // A password and a session token both go over this connection.
  EXPECT_TRUE(MattermostClient::hostIsAcceptable(QStringLiteral("https://mm.acme.com")));
  EXPECT_TRUE(MattermostClient::hostIsAcceptable(QStringLiteral("http://127.0.0.1:8065")));
  EXPECT_TRUE(MattermostClient::hostIsAcceptable(QStringLiteral("http://localhost:8065")));
  EXPECT_FALSE(MattermostClient::hostIsAcceptable(QStringLiteral("http://mm.acme.com")));
  EXPECT_FALSE(MattermostClient::hostIsAcceptable(QStringLiteral("mm.acme.com")));
  EXPECT_FALSE(MattermostClient::hostIsAcceptable(QString()));
}

TEST(MattermostHost, TrailingSlashesAreTrimmed) {
  EXPECT_EQ(MattermostClient::normalizeHost(QStringLiteral("  https://mm.acme.com///  ")), QStringLiteral("https://mm.acme.com"));
}

// ── The requests ────────────────────────────────────────────────────────────

class MattermostNetwork : public ::testing::Test {
 protected:
  static void SetUpTestSuite() {
    if(QCoreApplication::instance() == nullptr) {
      static int argc = 1;
      static char arg0[] = "heap_mattermost_tests";
      static char* argv[] = {arg0, nullptr};
      new QCoreApplication(argc, argv);
    }
  }

  // The shape every fetchContacts test starts from: me, one team, and whatever
  // channels the test adds.
  static void routeIdentity(FakeHttpServer& s) {
    s.route("GET /api/v4/users/me", {200, R"({"id":"me","username":"alex"})", {}});
    s.route("GET /api/v4/users/me/teams", {200, R"([{"id":"t1","name":"acme"}])", {}});
  }
};

TEST_F(MattermostNetwork, SignsInWithAPasswordAndReadsTheTokenHeader) {
  FakeHttpServer server;
  // Mattermost returns the session token in a header, not in the body.
  server.route("POST /api/v4/users/login", {200, R"({"id":"me","username":"alex"})", {{"Token", "sess-abc"}}});

  MattermostClient client;
  client.setConfig(server.base(), QString(), {});

  bool done = false;
  bool ok = false;
  QString token;
  QObject::connect(&client, &MattermostClient::loggedIn, &client, [&](bool o, const QString& t, const QString&) {
    ok = o;
    token = t;
    done = true;
  });
  client.login(QStringLiteral("alex"), QStringLiteral("hunter2"), QString());
  ASSERT_TRUE(waitFor(done));
  EXPECT_TRUE(ok);
  EXPECT_EQ(token, QStringLiteral("sess-abc"));

  const QJsonObject sent = QJsonDocument::fromJson(server.lastRequest("POST /api/v4/users/login").body).object();
  EXPECT_EQ(sent.value(QStringLiteral("login_id")).toString(), QStringLiteral("alex"));
  EXPECT_EQ(sent.value(QStringLiteral("password")).toString(), QStringLiteral("hunter2"));
  EXPECT_FALSE(sent.contains(QStringLiteral("token"))) << "no MFA code was given";
}

TEST_F(MattermostNetwork, SendsTheMfaCodeWhenThereIsOne) {
  FakeHttpServer server;
  server.route("POST /api/v4/users/login", {200, "{}", {{"Token", "sess"}}});

  MattermostClient client;
  client.setConfig(server.base(), QString(), {});
  bool done = false;
  QObject::connect(&client, &MattermostClient::loggedIn, &client, [&](bool, const QString&, const QString&) {
    done = true;
  });
  client.login(QStringLiteral("alex"), QStringLiteral("pw"), QStringLiteral(" 123456 "));
  ASSERT_TRUE(waitFor(done));
  EXPECT_EQ(QJsonDocument::fromJson(server.lastRequest("POST /api/v4/users/login").body).object().value(QStringLiteral("token")).toString(),
            QStringLiteral("123456"));
}

TEST_F(MattermostNetwork, ASignInThatReturnsNoTokenIsAFailure) {
  FakeHttpServer server;
  server.route("POST /api/v4/users/login", {200, R"({"id":"me"})", {}});  // no Token header

  MattermostClient client;
  client.setConfig(server.base(), QString(), {});
  bool done = false;
  bool ok = true;
  QObject::connect(&client, &MattermostClient::loggedIn, &client, [&](bool o, const QString&, const QString&) {
    ok = o;
    done = true;
  });
  client.login(QStringLiteral("alex"), QStringLiteral("pw"), QString());
  ASSERT_TRUE(waitFor(done));
  EXPECT_FALSE(ok);
}

TEST_F(MattermostNetwork, AWrongPasswordSurfacesTheServersMessage) {
  FakeHttpServer server;
  server.route("POST /api/v4/users/login",
               {401, R"({"message":"Enter a valid email or username and/or password.","id":"api.user.login.invalid_credentials"})", {}});

  MattermostClient client;
  client.setConfig(server.base(), QString(), {});
  bool done = false;
  QString error;
  QObject::connect(&client, &MattermostClient::loggedIn, &client, [&](bool, const QString&, const QString& e) {
    error = e;
    done = true;
  });
  client.login(QStringLiteral("alex"), QStringLiteral("wrong"), QString());
  ASSERT_TRUE(waitFor(done));
  EXPECT_TRUE(error.contains(QStringLiteral("valid email or username"))) << error.toStdString();
}

TEST_F(MattermostNetwork, RefusesToSendAPasswordOverPlainHttp) {
  MattermostClient client;
  client.setConfig(QStringLiteral("http://mm.acme.com"), QString(), {});

  bool done = false;
  bool ok = true;
  QObject::connect(&client, &MattermostClient::loggedIn, &client, [&](bool o, const QString&, const QString&) {
    ok = o;
    done = true;
  });
  client.login(QStringLiteral("alex"), QStringLiteral("pw"), QString());
  EXPECT_TRUE(done) << "the guard must answer without a request";
  EXPECT_FALSE(ok);
}

TEST_F(MattermostNetwork, ImportsDirectMessagePeersWithoutAskingForMembers) {
  FakeHttpServer server;
  routeIdentity(server);
  server.route("GET /api/v4/users/me/teams/t1/channels",
               {200,
                R"([
      {"id":"c1","type":"D","name":"me__u1","total_msg_count":42},
      {"id":"c2","type":"D","name":"me__u2","total_msg_count":0},
      {"id":"c3","type":"D","name":"me__me","total_msg_count":5},
      {"id":"c4","type":"O","name":"town-square","total_msg_count":900}])",
                {}});
  server.route("POST /api/v4/users/ids", {200, R"([{"id":"u1","username":"olga.t","position":"Tech Lead"}])", {}});

  MattermostClient client;
  client.setConfig(server.base(), QStringLiteral("tok"), {});
  QVector<ExternalContact> got;
  bool done = false;
  QObject::connect(&client, &MattermostClient::contactsFetched, &client, [&](const QVector<ExternalContact>& c) {
    got = c;
    done = true;
  });
  client.fetchContacts();
  ASSERT_TRUE(waitFor(done));

  ASSERT_EQ(got.size(), 1);
  EXPECT_EQ(got[0].username, QStringLiteral("olga.t"));
  EXPECT_EQ(got[0].channelLabel, QStringLiteral("direct message"));
  // A DM names its peer, so no member lookup is needed; an unused DM and the
  // self-DM are not people worth importing; and an ordinary channel nobody
  // asked for would drag in the whole company.
  EXPECT_FALSE(server.seen().contains("GET /api/v4/channels/c1/members"));
  EXPECT_FALSE(server.seen().contains("GET /api/v4/channels/c4/members"));
  const QJsonArray asked = QJsonDocument::fromJson(server.lastRequest("POST /api/v4/users/ids").body).array();
  ASSERT_EQ(asked.size(), 1);
  EXPECT_EQ(asked.first().toString(), QStringLiteral("u1"));
}

TEST_F(MattermostNetwork, ImportsMembersOfGroupDmsAndTheNamedChannels) {
  FakeHttpServer server;
  routeIdentity(server);
  server.route("GET /api/v4/users/me/teams/t1/channels",
               {200,
                R"([
      {"id":"g1","type":"G","display_name":"olga, pavel","total_msg_count":7},
      {"id":"c9","type":"O","name":"backend","total_msg_count":500},
      {"id":"c8","type":"O","name":"random","total_msg_count":500}])",
                {}});
  server.route("GET /api/v4/channels/g1/members", {200, R"([{"user_id":"u1","roles":"channel_user"},{"user_id":"me"}])", {}});
  server.route("GET /api/v4/channels/c9/members", {200, R"([{"user_id":"u2","roles":"channel_user channel_admin"}])", {}});
  server.route(
      "POST /api/v4/users/ids",
      {200, R"([{"id":"u1","username":"olga.t","roles":"system_user"},{"id":"u2","username":"pavel","roles":"system_user"}])", {}});

  MattermostClient client;
  client.setConfig(server.base(), QStringLiteral("tok"), {QStringLiteral("backend")});
  QVector<ExternalContact> got;
  bool done = false;
  QObject::connect(&client, &MattermostClient::contactsFetched, &client, [&](const QVector<ExternalContact>& c) {
    got = c;
    done = true;
  });
  client.fetchContacts();
  ASSERT_TRUE(waitFor(done));

  ASSERT_EQ(got.size(), 2);
  QHash<QString, ExternalContact> byName;
  for(const ExternalContact& c : got) {
    byName.insert(c.username, c);
  }
  EXPECT_EQ(byName.value(QStringLiteral("olga.t")).channelLabel, QStringLiteral("olga, pavel"));
  EXPECT_EQ(byName.value(QStringLiteral("pavel")).channelLabel, QStringLiteral("#backend"));
  // With no job title, the channel role is what is left to show.
  EXPECT_EQ(byName.value(QStringLiteral("pavel")).role, QStringLiteral("Channel admin"));
  EXPECT_EQ(byName.value(QStringLiteral("olga.t")).role, QStringLiteral("Member"));
  // A channel the user did not name is not walked.
  EXPECT_FALSE(server.seen().contains("GET /api/v4/channels/c8/members"));
}

TEST_F(MattermostNetwork, SkipsBotsDeactivatedAccountsAndYourself) {
  FakeHttpServer server;
  routeIdentity(server);
  server.route("GET /api/v4/users/me/teams/t1/channels",
               {200, R"([{"id":"g1","type":"G","display_name":"crew","total_msg_count":3}])", {}});
  server.route("GET /api/v4/channels/g1/members",
               {200, R"([{"user_id":"u1"},{"user_id":"bot1"},{"user_id":"gone"},{"user_id":"me"}])", {}});
  server.route("POST /api/v4/users/ids",
               {200,
                R"([
      {"id":"u1","username":"olga.t"},
      {"id":"bot1","username":"jenkins","is_bot":true},
      {"id":"gone","username":"former","delete_at":1699999999000},
      {"id":"me","username":"alex"}])",
                {}});

  MattermostClient client;
  client.setConfig(server.base(), QStringLiteral("tok"), {});
  QVector<ExternalContact> got;
  bool done = false;
  QObject::connect(&client, &MattermostClient::contactsFetched, &client, [&](const QVector<ExternalContact>& c) {
    got = c;
    done = true;
  });
  client.fetchContacts();
  ASSERT_TRUE(waitFor(done));

  ASSERT_EQ(got.size(), 1) << "a bot, a former colleague and yourself are not contacts";
  EXPECT_EQ(got[0].username, QStringLiteral("olga.t"));
}

TEST_F(MattermostNetwork, ReportsAFailedFetchRatherThanAnEmptyResult) {
  FakeHttpServer server;
  server.route("GET /api/v4/users/me", {401, R"({"message":"Invalid or expired session, please login again."})", {}});

  MattermostClient client;
  client.setConfig(server.base(), QStringLiteral("stale"), {});
  bool fetched = false;
  bool failed = false;
  int status = 0;
  QObject::connect(&client, &MattermostClient::contactsFetched, &client, [&](const QVector<ExternalContact>&) {
    fetched = true;
  });
  QObject::connect(&client, &MattermostClient::failed, &client, [&](int s, const QString&) {
    status = s;
    failed = true;
  });
  client.fetchContacts();
  ASSERT_TRUE(waitFor(failed));
  EXPECT_EQ(status, 401) << "the caller needs the status to say 'sign in again'";
  EXPECT_FALSE(fetched) << "a failure must not look like an empty directory";
}

TEST_F(MattermostNetwork, LogoutEndsTheServerSideSession) {
  FakeHttpServer server;
  server.route("POST /api/v4/users/logout", {200, "{}", {}});

  MattermostClient client;
  client.setConfig(server.base(), QStringLiteral("sess"), {});
  client.logout();
  ASSERT_TRUE(heap::testing::waitUntil([&server]() {
    return server.seen().contains("POST /api/v4/users/logout");
  }));
  EXPECT_EQ(server.lastRequest("POST /api/v4/users/logout").headers.value("authorization"), QByteArray("Bearer sess"));
}

// ── Redirects must not carry the credentials off-origin ─────────────────────
// Qt's default policy permits a redirect to another host, and a 307 keeps the
// method and body — so a server could bounce POST /users/login, password and
// all, somewhere else, or collect the Bearer token from any other call.
// hostIsAcceptable() only ever inspects the first URL.

TEST_F(MattermostNetwork, ALoginIsNotRedirectedToAnotherOrigin) {
  FakeHttpServer elsewhere;
  elsewhere.route("POST /api/v4/users/login", {200, R"({"id":"me"})", {{"Token", "stolen"}}});

  FakeHttpServer server;
  FakeHttpServer::Response bounce;
  bounce.status = 302;
  bounce.headers = {{"Location", (elsewhere.base() + QStringLiteral("/api/v4/users/login")).toUtf8()}};
  server.route("POST /api/v4/users/login", bounce);

  MattermostClient client;
  client.setConfig(server.base(), QString(), {});
  bool done = false;
  bool ok = true;
  QObject::connect(&client, &MattermostClient::loggedIn, &client, [&](bool o, const QString&, const QString&) {
    ok = o;
    done = true;
  });
  client.login(QStringLiteral("alex"), QStringLiteral("hunter2"), QString());
  ASSERT_TRUE(waitFor(done));

  EXPECT_FALSE(ok) << "a cross-origin redirect must fail the call, not follow it";
  EXPECT_TRUE(elsewhere.seen().isEmpty()) << "the password was forwarded to another origin";
}

TEST_F(MattermostNetwork, AnAuthenticatedCallIsNotRedirectedToAnotherOrigin) {
  FakeHttpServer elsewhere;
  elsewhere.route("GET /api/v4/users/me", {200, R"({"id":"me"})", {}});

  FakeHttpServer server;
  FakeHttpServer::Response bounce;
  bounce.status = 302;
  bounce.headers = {{"Location", (elsewhere.base() + QStringLiteral("/api/v4/users/me")).toUtf8()}};
  server.route("GET /api/v4/users/me", bounce);

  MattermostClient client;
  client.setConfig(server.base(), QStringLiteral("sess-token"), {});
  bool done = false;
  bool ok = true;
  QObject::connect(&client, &MattermostClient::connectionTested, &client, [&](bool o, const QString&) {
    ok = o;
    done = true;
  });
  client.testConnection();
  ASSERT_TRUE(waitFor(done));

  EXPECT_FALSE(ok);
  EXPECT_TRUE(elsewhere.seen().isEmpty()) << "the session token was handed to another origin";
}
