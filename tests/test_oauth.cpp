// The browser sign-in engine: PKCE, the authorize URL, the loopback receiver
// and the token exchange's four provider dialects.
//
// The authorization-code and fragment flows are hand-rolled (see the comment on
// OAuthManager) precisely so they can be driven here: the loopback listener
// binds an ephemeral port, the consent "browser" is an injected functor, and
// the token endpoint is the local FakeHttpServer. Nothing reaches the network.

#include "FakeHttpServer.h"

#include "integrations/OAuthManager.h"
#include "integrations/OAuthRefresh.h"

#include <QCoreApplication>
#include <QNetworkAccessManager>
#include <QSignalSpy>
#include <QTcpSocket>
#include <QUrlQuery>

#include <gtest/gtest.h>

using heap::integrations::AuthCodeParams;
using heap::integrations::exchangeAuthCode;
using heap::integrations::LoopbackReceiver;
using heap::integrations::OAuthFlow;
using heap::integrations::OAuthManager;
using heap::integrations::OAuthResult;
using heap::integrations::TokenStyle;
using heap::testing::FakeHttpServer;
using heap::testing::waitFor;
using heap::testing::waitUntil;

namespace {

// Speak to the loopback listener the way a browser would. Returns the status
// line plus body; an empty string means the connection produced nothing.
//
// The reply is awaited by pumping the event loop rather than with
// QTcpSocket::waitForReadyRead: the listener under test lives in this same
// thread, so blocking on the client socket would stop it from ever answering.
QByteArray httpRequest(quint16 port, const QByteArray& request) {
  QTcpSocket sock;
  QByteArray out;
  bool closed = false;
  QObject::connect(&sock, &QTcpSocket::readyRead, &sock, [&sock, &out]() {
    out += sock.readAll();
  });
  QObject::connect(&sock, &QTcpSocket::disconnected, &sock, [&closed]() {
    closed = true;
  });

  sock.connectToHost(QHostAddress::LocalHost, port);
  if(!waitUntil([&sock]() {
       return sock.state() == QAbstractSocket::ConnectedState;
     })) {
    return {};
  }
  sock.write(request);
  sock.flush();
  waitFor(closed);
  out += sock.readAll();
  return out;
}

QByteArray httpGet(quint16 port, const QByteArray& target, const QByteArray& hostHeader = {}) {
  const QByteArray host = hostHeader.isEmpty() ? QByteArray("127.0.0.1:") + QByteArray::number(port) : hostHeader;
  return httpRequest(port, "GET " + target + " HTTP/1.1\r\nHost: " + host + "\r\nConnection: close\r\n\r\n");
}

QByteArray httpPostForm(quint16 port, const QByteArray& target, const QByteArray& body) {
  return httpRequest(port,
                     "POST " + target + " HTTP/1.1\r\nHost: 127.0.0.1:" + QByteArray::number(port) +
                         "\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: " + QByteArray::number(body.size()) +
                         "\r\nConnection: close\r\n\r\n" + body);
}

int statusOf(const QByteArray& response) {
  return response.split(' ').value(1).toInt();
}

}  // namespace

class OAuthTest : public ::testing::Test {
 protected:
  static void SetUpTestSuite() {
    // QNetworkAccessManager and QTcpServer need an application object; it
    // outlives the suite on purpose.
    if(QCoreApplication::instance() == nullptr) {
      static int argc = 1;
      static char arg0[] = "heap_oauth_tests";
      static char* argv[] = {arg0, nullptr};
      new QCoreApplication(argc, argv);
    }
  }
};

// ── PKCE (RFC 7636) ─────────────────────────────────────────────────────────

TEST(Pkce, MatchesTheRfc7636TestVector) {
  // RFC 7636 appendix B: the verifier and its expected S256 challenge.
  EXPECT_EQ(OAuthManager::pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            QByteArray("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"));
}

TEST(Pkce, ChallengeIsUnpaddedBase64Url) {
  const QByteArray challenge = OAuthManager::pkceChallenge(OAuthManager::randomToken(48));
  EXPECT_EQ(challenge.size(), 43);  // 32 bytes of SHA-256, base64url, no padding
  EXPECT_FALSE(challenge.contains('='));
  EXPECT_FALSE(challenge.contains('+'));
  EXPECT_FALSE(challenge.contains('/'));
}

TEST(Pkce, RandomTokensAreUrlSafeAndUnpredictable) {
  const QByteArray a = OAuthManager::randomToken();
  const QByteArray b = OAuthManager::randomToken();
  EXPECT_NE(a, b);
  EXPECT_FALSE(a.isEmpty());
  for(const char c : a) {
    EXPECT_TRUE(std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_') << "not url-safe: " << c;
  }
}

// ── The authorize URL ───────────────────────────────────────────────────────

TEST(AuthorizeUrl, CarriesTheStandardParameters) {
  OAuthManager::Params p;
  p.authUrl = QStringLiteral("https://gitlab.com/oauth/authorize");
  p.clientId = QStringLiteral("cid");
  p.scope = QStringLiteral("api read_user");
  const QUrlQuery q{OAuthManager::buildAuthorizeUrl(p, QStringLiteral("http://127.0.0.1:51789/"), "st4te", "ch4llenge").query()};
  EXPECT_EQ(q.queryItemValue(QStringLiteral("client_id")), QStringLiteral("cid"));
  EXPECT_EQ(q.queryItemValue(QStringLiteral("response_type")), QStringLiteral("code"));
  EXPECT_EQ(q.queryItemValue(QStringLiteral("state")), QStringLiteral("st4te"));
  EXPECT_EQ(q.queryItemValue(QStringLiteral("code_challenge")), QStringLiteral("ch4llenge"));
  EXPECT_EQ(q.queryItemValue(QStringLiteral("code_challenge_method")), QStringLiteral("S256"));
  EXPECT_EQ(q.queryItemValue(QStringLiteral("redirect_uri")), QStringLiteral("http://127.0.0.1:51789/"));
  EXPECT_EQ(q.queryItemValue(QStringLiteral("scope")), QStringLiteral("api read_user"));
}

TEST(AuthorizeUrl, OmitsPkceWhenThereIsNoChallenge) {
  OAuthManager::Params p;
  p.authUrl = QStringLiteral("https://example.com/authorize");
  p.clientId = QStringLiteral("cid");
  const QUrlQuery q{OAuthManager::buildAuthorizeUrl(p, QStringLiteral("http://127.0.0.1:1/"), "s", {}).query()};
  EXPECT_FALSE(q.hasQueryItem(QStringLiteral("code_challenge")));
  EXPECT_FALSE(q.hasQueryItem(QStringLiteral("scope")));  // empty scope is not sent at all
}

TEST(AuthorizeUrl, ExtraParamsAndScopeSeparator) {
  // Atlassian needs audience + prompt; Todoist separates scopes with commas.
  OAuthManager::Params p;
  p.authUrl = QStringLiteral("https://auth.atlassian.com/authorize");
  p.clientId = QStringLiteral("cid");
  p.scope = QStringLiteral("data:read data:write");
  p.scopeSeparator = QStringLiteral(",");
  p.extraAuthParams = {{QStringLiteral("audience"), QStringLiteral("api.atlassian.com")},
                       {QStringLiteral("prompt"), QStringLiteral("consent")}};
  const QUrlQuery q{OAuthManager::buildAuthorizeUrl(p, QStringLiteral("http://127.0.0.1:1/"), "s", {}).query()};
  EXPECT_EQ(q.queryItemValue(QStringLiteral("scope")), QStringLiteral("data:read,data:write"));
  EXPECT_EQ(q.queryItemValue(QStringLiteral("audience")), QStringLiteral("api.atlassian.com"));
  EXPECT_EQ(q.queryItemValue(QStringLiteral("prompt")), QStringLiteral("consent"));
}

TEST(AuthorizeUrl, TrelloRenamesClientIdAndRedirectAndAsksForNoCode) {
  OAuthManager::Params p;
  p.flow = OAuthFlow::ImplicitFragment;
  p.authUrl = QStringLiteral("https://trello.com/1/authorize");
  p.clientId = QStringLiteral("appkey");
  p.clientIdParam = QStringLiteral("key");
  p.redirectParam = QStringLiteral("return_url");
  const QUrlQuery q{OAuthManager::buildAuthorizeUrl(p, QStringLiteral("http://127.0.0.1:51789/"), "s", {}).query()};
  EXPECT_EQ(q.queryItemValue(QStringLiteral("key")), QStringLiteral("appkey"));
  EXPECT_EQ(q.queryItemValue(QStringLiteral("return_url")), QStringLiteral("http://127.0.0.1:51789/"));
  EXPECT_FALSE(q.hasQueryItem(QStringLiteral("client_id")));
  // The fragment flow asks for a token, not a code.
  EXPECT_FALSE(q.hasQueryItem(QStringLiteral("response_type")));
}

// ── The loopback receiver ───────────────────────────────────────────────────

TEST_F(OAuthTest, LoopbackAcceptsTheMatchingCallback) {
  LoopbackReceiver receiver(LoopbackReceiver::Mode::Query, "good-state");
  ASSERT_TRUE(receiver.listen(0));
  QSignalSpy got(&receiver, &LoopbackReceiver::received);

  const QByteArray response = httpGet(receiver.port(), "/?code=abc123&state=good-state");
  EXPECT_EQ(statusOf(response), 200);
  EXPECT_TRUE(response.contains("You can close this tab"));
  // A page holding an authorization code must not be cached or leak a referrer.
  EXPECT_TRUE(response.contains("Cache-Control: no-store"));
  EXPECT_TRUE(response.contains("Referrer-Policy: no-referrer"));

  ASSERT_TRUE(waitUntil([&got]() {
    return !got.isEmpty();
  }));
  EXPECT_EQ(got.first().first().toMap().value(QStringLiteral("code")).toString(), QStringLiteral("abc123"));
}

TEST_F(OAuthTest, LoopbackIgnoresAWrongStateAndKeepsListening) {
  // Anything that can reach localhost can hit this port. A forged or stale
  // callback must neither complete the flow nor end it.
  LoopbackReceiver receiver(LoopbackReceiver::Mode::Query, "good-state");
  ASSERT_TRUE(receiver.listen(0));
  QSignalSpy got(&receiver, &LoopbackReceiver::received);
  QSignalSpy failed(&receiver, &LoopbackReceiver::failed);

  EXPECT_EQ(statusOf(httpGet(receiver.port(), "/?code=evil&state=wrong-state")), 400);
  EXPECT_EQ(statusOf(httpGet(receiver.port(), "/?code=evil")), 400);  // no state at all
  EXPECT_EQ(statusOf(httpGet(receiver.port(), "/favicon.ico")), 404);
  EXPECT_TRUE(got.isEmpty());
  EXPECT_TRUE(failed.isEmpty());

  // The real callback still lands.
  EXPECT_EQ(statusOf(httpGet(receiver.port(), "/?code=real&state=good-state")), 200);
  ASSERT_TRUE(waitUntil([&got]() {
    return !got.isEmpty();
  }));
  EXPECT_EQ(got.first().first().toMap().value(QStringLiteral("code")).toString(), QStringLiteral("real"));
}

TEST_F(OAuthTest, LoopbackRejectsAForeignHostHeader) {
  // A DNS-rebinding page resolves its own name to 127.0.0.1 and then talks to
  // this port under that name. The Host header is what gives it away.
  LoopbackReceiver receiver(LoopbackReceiver::Mode::Query, "good-state");
  ASSERT_TRUE(receiver.listen(0));
  QSignalSpy got(&receiver, &LoopbackReceiver::received);

  EXPECT_EQ(statusOf(httpGet(receiver.port(), "/?code=abc&state=good-state", "evil.example.com")), 400);
  EXPECT_TRUE(got.isEmpty());

  // "localhost" with the right port is ours.
  const QByteArray alias = QByteArray("localhost:") + QByteArray::number(receiver.port());
  EXPECT_EQ(statusOf(httpGet(receiver.port(), "/?code=abc&state=good-state", alias)), 200);
}

TEST_F(OAuthTest, LoopbackReportsAProviderError) {
  LoopbackReceiver receiver(LoopbackReceiver::Mode::Query, "good-state");
  ASSERT_TRUE(receiver.listen(0));
  QSignalSpy failed(&receiver, &LoopbackReceiver::failed);

  EXPECT_EQ(statusOf(httpGet(receiver.port(), "/?error=access_denied&state=good-state")), 200);
  ASSERT_TRUE(waitUntil([&failed]() {
    return !failed.isEmpty();
  }));
  EXPECT_TRUE(failed.first().first().toString().contains(QStringLiteral("declined")));
}

TEST_F(OAuthTest, LoopbackFragmentModeTakesTheTokenFromThePagePost) {
  // Trello answers with #token=… , which the browser never sends. The served
  // page posts it back instead.
  LoopbackReceiver receiver(LoopbackReceiver::Mode::Fragment, "good-state");
  ASSERT_TRUE(receiver.listen(0));
  QSignalSpy got(&receiver, &LoopbackReceiver::received);

  const QByteArray page = httpGet(receiver.port(), "/?state=good-state");
  EXPECT_EQ(statusOf(page), 200);
  EXPECT_TRUE(page.contains("location.hash"));
  // The inline script runs only under its nonce, and nothing else may load.
  EXPECT_TRUE(page.contains("Content-Security-Policy: default-src 'none'"));
  EXPECT_TRUE(page.contains("script-src 'nonce-"));
  EXPECT_TRUE(got.isEmpty()) << "serving the page must not finish the flow";

  EXPECT_EQ(statusOf(httpPostForm(receiver.port(), "/token", "token=tok-42&state=good-state")), 200);
  ASSERT_TRUE(waitUntil([&got]() {
    return !got.isEmpty();
  }));
  EXPECT_EQ(got.first().first().toMap().value(QStringLiteral("token")).toString(), QStringLiteral("tok-42"));
}

TEST_F(OAuthTest, LoopbackFragmentModeRejectsATokenWithTheWrongState) {
  LoopbackReceiver receiver(LoopbackReceiver::Mode::Fragment, "good-state");
  ASSERT_TRUE(receiver.listen(0));
  QSignalSpy got(&receiver, &LoopbackReceiver::received);

  EXPECT_EQ(statusOf(httpPostForm(receiver.port(), "/token", "token=stolen&state=wrong")), 400);
  EXPECT_EQ(statusOf(httpPostForm(receiver.port(), "/token", "state=good-state")), 400);  // no token
  EXPECT_TRUE(got.isEmpty());
}

TEST(LoopbackState, ComparisonIsLengthSafe) {
  EXPECT_TRUE(LoopbackReceiver::sameToken("abc", "abc"));
  EXPECT_FALSE(LoopbackReceiver::sameToken("abc", "abd"));
  EXPECT_FALSE(LoopbackReceiver::sameToken("abc", "ab"));
  EXPECT_FALSE(LoopbackReceiver::sameToken({}, {}));  // an empty state never matches
}

TEST_F(OAuthTest, LoopbackReportsABusyPort) {
  LoopbackReceiver first(LoopbackReceiver::Mode::Query, "s");
  ASSERT_TRUE(first.listen(0));
  LoopbackReceiver second(LoopbackReceiver::Mode::Query, "s");
  EXPECT_FALSE(second.listen(first.port()));
}

// ── The token exchange's four dialects ──────────────────────────────────────

namespace {

OAuthResult exchangeAgainst(FakeHttpServer& server, TokenStyle style, const QString& secret = QStringLiteral("sec")) {
  QNetworkAccessManager nam;
  AuthCodeParams p;
  p.tokenUrl = server.base() + QStringLiteral("/token");
  p.clientId = QStringLiteral("cid");
  p.clientSecret = secret;
  p.code = QStringLiteral("the-code");
  p.redirectUri = QStringLiteral("http://127.0.0.1:51789/");
  p.codeVerifier = QStringLiteral("verifier");
  p.style = style;

  OAuthResult out;
  bool done = false;
  exchangeAuthCode(&nam, p, [&out, &done](const OAuthResult& r) {
    out = r;
    done = true;
  });
  waitFor(done);
  return out;
}

}  // namespace

TEST_F(OAuthTest, FormBodyExchangeSendsEverythingInTheBody) {
  FakeHttpServer server;
  server.route("POST /token", {200, R"({"access_token":"at","refresh_token":"rt","expires_in":7200})", {}});

  const OAuthResult r = exchangeAgainst(server, TokenStyle::FormBody);
  ASSERT_TRUE(r.ok) << r.error.toStdString();
  EXPECT_EQ(r.accessToken, QStringLiteral("at"));
  EXPECT_EQ(r.refreshToken, QStringLiteral("rt"));
  EXPECT_TRUE(r.expiresAt.isValid());

  const auto req = server.lastRequest("POST /token");
  EXPECT_EQ(req.headers.value("content-type"), QByteArray("application/x-www-form-urlencoded"));
  EXPECT_TRUE(req.body.contains("grant_type=authorization_code")) << req.body.toStdString();
  EXPECT_TRUE(req.body.contains("code=the-code")) << req.body.toStdString();
  EXPECT_TRUE(req.body.contains("code_verifier=verifier")) << req.body.toStdString();
  EXPECT_TRUE(req.body.contains("client_secret=sec")) << req.body.toStdString();
  EXPECT_FALSE(req.headers.contains("authorization"));
}

TEST_F(OAuthTest, BasicAuthFormExchangeMovesTheCredentialsToAHeader) {
  // Bitbucket rejects client credentials in the body.
  FakeHttpServer server;
  server.route("POST /token", {200, R"({"access_token":"at","expires_in":7200})", {}});

  const OAuthResult r = exchangeAgainst(server, TokenStyle::BasicAuthForm);
  ASSERT_TRUE(r.ok) << r.error.toStdString();

  const auto req = server.lastRequest("POST /token");
  EXPECT_EQ(req.headers.value("authorization"), QByteArray("Basic ") + QByteArray("cid:sec").toBase64());
  EXPECT_FALSE(req.body.contains("client_secret")) << req.body.toStdString();
  EXPECT_FALSE(req.body.contains("client_id")) << req.body.toStdString();
  EXPECT_TRUE(req.body.contains("code=the-code")) << req.body.toStdString();
}

TEST_F(OAuthTest, JsonBodyExchangeSendsAJsonObject) {
  // Atlassian and ClickUp want JSON.
  FakeHttpServer server;
  server.route("POST /token", {200, R"({"access_token":"at","refresh_token":"rt"})", {}});

  const OAuthResult r = exchangeAgainst(server, TokenStyle::JsonBody);
  ASSERT_TRUE(r.ok) << r.error.toStdString();
  EXPECT_FALSE(r.expiresAt.isValid()) << "no expires_in means a non-expiring token";

  const auto req = server.lastRequest("POST /token");
  EXPECT_EQ(req.headers.value("content-type"), QByteArray("application/json"));
  const QJsonObject body = QJsonDocument::fromJson(req.body).object();
  EXPECT_EQ(body.value(QStringLiteral("grant_type")).toString(), QStringLiteral("authorization_code"));
  EXPECT_EQ(body.value(QStringLiteral("code")).toString(), QStringLiteral("the-code"));
  EXPECT_EQ(body.value(QStringLiteral("client_secret")).toString(), QStringLiteral("sec"));
  EXPECT_EQ(body.value(QStringLiteral("redirect_uri")).toString(), QStringLiteral("http://127.0.0.1:51789/"));
}

TEST_F(OAuthTest, PublicClientSendsNoSecret) {
  FakeHttpServer server;
  server.route("POST /token", {200, R"({"access_token":"at"})", {}});

  ASSERT_TRUE(exchangeAgainst(server, TokenStyle::FormBody, QString()).ok);
  EXPECT_FALSE(server.lastRequest("POST /token").body.contains("client_secret"));
}

TEST_F(OAuthTest, ExchangeSurfacesTheProvidersError) {
  FakeHttpServer server;
  server.route("POST /token", {400, R"({"error":"invalid_grant","error_description":"The code has expired."})", {}});

  const OAuthResult r = exchangeAgainst(server, TokenStyle::FormBody);
  EXPECT_FALSE(r.ok);
  EXPECT_TRUE(r.error.contains(QStringLiteral("The code has expired."))) << r.error.toStdString();
}

TEST_F(OAuthTest, ExchangeWithNothingToExchangeFailsWithoutACall) {
  FakeHttpServer server;
  QNetworkAccessManager nam;
  AuthCodeParams p;
  p.tokenUrl = server.base() + QStringLiteral("/token");
  p.clientId = QStringLiteral("cid");  // but no code

  OAuthResult out;
  bool done = false;
  exchangeAuthCode(&nam, p, [&out, &done](const OAuthResult& r) {
    out = r;
    done = true;
  });
  EXPECT_TRUE(done) << "the guard must answer synchronously";
  EXPECT_FALSE(out.ok);
  EXPECT_TRUE(server.seen().isEmpty());
}

// ── End to end, browser and token endpoint both faked ───────────────────────

TEST_F(OAuthTest, FullAuthorizationCodeFlow) {
  FakeHttpServer token;
  token.route("POST /token", {200, R"({"access_token":"at-final","refresh_token":"rt-final","expires_in":3600})", {}});

  QNetworkAccessManager nam;
  OAuthManager mgr;
  mgr.setNetworkAccessManager(&nam);

  OAuthManager::Params p;
  p.authUrl = QStringLiteral("https://provider.example/authorize");
  p.tokenUrl = token.base() + QStringLiteral("/token");
  p.clientId = QStringLiteral("cid");
  p.redirectPort = 0;  // ephemeral: a real flow uses the registered port

  // Stand in for the browser: read the authorize URL, then call the redirect
  // back the way the provider would.
  QUrl seenAuthorizeUrl;
  mgr.setUrlOpener([&seenAuthorizeUrl](const QUrl& url) {
    seenAuthorizeUrl = url;
  });

  OAuthResult result;
  bool done = false;
  QObject::connect(&mgr, &OAuthManager::finished, [&result, &done](const OAuthResult& r) {
    result = r;
    done = true;
  });
  mgr.start(p);

  ASSERT_FALSE(seenAuthorizeUrl.isEmpty());
  const QUrlQuery authQuery{seenAuthorizeUrl.query()};
  const QString redirect = authQuery.queryItemValue(QStringLiteral("redirect_uri"));
  const QString state = authQuery.queryItemValue(QStringLiteral("state"));
  const quint16 port = static_cast<quint16>(QUrl(redirect).port());
  ASSERT_GT(port, 0);

  httpGet(port, "/?code=granted&state=" + state.toUtf8());
  ASSERT_TRUE(waitFor(done));
  ASSERT_TRUE(result.ok) << result.error.toStdString();
  EXPECT_EQ(result.accessToken, QStringLiteral("at-final"));
  EXPECT_EQ(result.refreshToken, QStringLiteral("rt-final"));

  // PKCE bound the code to this process, so the verifier must be spent too.
  const auto req = token.lastRequest("POST /token");
  EXPECT_TRUE(req.body.contains("code=granted")) << req.body.toStdString();
  EXPECT_TRUE(req.body.contains("code_verifier=")) << req.body.toStdString();
  EXPECT_TRUE(req.body.contains("redirect_uri=")) << req.body.toStdString();
}

TEST_F(OAuthTest, AForgedRedirectNeverReachesTheTokenEndpoint) {
  FakeHttpServer token;
  token.route("POST /token", {200, R"({"access_token":"should-not-happen"})", {}});

  QNetworkAccessManager nam;
  OAuthManager mgr;
  mgr.setNetworkAccessManager(&nam);

  OAuthManager::Params p;
  p.authUrl = QStringLiteral("https://provider.example/authorize");
  p.tokenUrl = token.base() + QStringLiteral("/token");
  p.clientId = QStringLiteral("cid");
  p.redirectPort = 0;

  QUrl seenAuthorizeUrl;
  mgr.setUrlOpener([&seenAuthorizeUrl](const QUrl& url) {
    seenAuthorizeUrl = url;
  });
  bool done = false;
  QObject::connect(&mgr, &OAuthManager::finished, [&done](const OAuthResult&) {
    done = true;
  });
  mgr.start(p);

  const QUrlQuery authQuery{seenAuthorizeUrl.query()};
  const quint16 port = static_cast<quint16>(QUrl(authQuery.queryItemValue(QStringLiteral("redirect_uri"))).port());
  httpGet(port, "/?code=forged&state=not-the-state");

  // Give it a moment to do the wrong thing.
  waitUntil(
      [&token]() {
        return !token.seen().isEmpty();
      },
      600);
  EXPECT_TRUE(token.seen().isEmpty()) << "a code with the wrong state must not be exchanged";
  EXPECT_FALSE(done) << "and must not end the flow either";
}

TEST_F(OAuthTest, FullFragmentFlowNeedsNoTokenEndpoint) {
  FakeHttpServer token;  // stays untouched

  OAuthManager mgr;
  OAuthManager::Params p;
  p.flow = OAuthFlow::ImplicitFragment;
  p.authUrl = QStringLiteral("https://trello.com/1/authorize");
  p.tokenUrl = token.base() + QStringLiteral("/token");
  p.clientId = QStringLiteral("appkey");
  p.clientIdParam = QStringLiteral("key");
  p.redirectParam = QStringLiteral("return_url");
  p.redirectPort = 0;

  QUrl seenAuthorizeUrl;
  mgr.setUrlOpener([&seenAuthorizeUrl](const QUrl& url) {
    seenAuthorizeUrl = url;
  });
  OAuthResult result;
  bool done = false;
  QObject::connect(&mgr, &OAuthManager::finished, [&result, &done](const OAuthResult& r) {
    result = r;
    done = true;
  });
  mgr.start(p);

  const QUrlQuery authQuery{seenAuthorizeUrl.query()};
  const QString state = authQuery.queryItemValue(QStringLiteral("state"));
  const quint16 port = static_cast<quint16>(QUrl(authQuery.queryItemValue(QStringLiteral("return_url"))).port());
  ASSERT_GT(port, 0);

  httpGet(port, "/?state=" + state.toUtf8());  // the page the script runs in
  httpPostForm(port, "/token", "token=trello-token&state=" + state.toUtf8());

  ASSERT_TRUE(waitFor(done));
  ASSERT_TRUE(result.ok) << result.error.toStdString();
  EXPECT_EQ(result.accessToken, QStringLiteral("trello-token"));
  EXPECT_TRUE(token.seen().isEmpty()) << "the fragment flow has nothing to exchange";
}
