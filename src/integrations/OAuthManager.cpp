#include "integrations/OAuthManager.h"
#include "integrations/OAuthRefresh.h"

#include <QAbstractOAuth>
#include <QCryptographicHash>
#include <QDesktopServices>
#include <QHostAddress>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QRandomGenerator>
#include <QTcpServer>
#include <QTcpSocket>
#include <QtGlobal>
#include <QTimer>
#include <QUrlQuery>

// The device grant still rides on Qt's own class, which only stabilised in Qt
// 6.9 (QOAuth2DeviceAuthorizationFlow, setNetworkRequestModifier,
// setRequestedScopeTokens). Distro packaging (e.g. the Ubuntu .deb) builds
// against the system Qt 6.4, so there it compiles to a stub and the card hides
// the button — see deviceFlowAvailable(). The authorization-code and fragment
// flows below are hand-rolled and work on every supported Qt.
#define HEAP_HAVE_DEVICE_OAUTH (QT_VERSION >= QT_VERSION_CHECK(6, 9, 0))

#if HEAP_HAVE_DEVICE_OAUTH
#include <QOAuth2DeviceAuthorizationFlow>

namespace {
// GitHub's OAuth endpoints (device/code, access_token) default to
// `application/x-www-form-urlencoded`; Qt's OAuth flows expect JSON and abort
// with "Authorization stage: invalid response format" otherwise.
void forceJsonAccept(QNetworkRequest& req, QAbstractOAuth::Stage) {
  req.setRawHeader("Accept", "application/json");
}
}  // namespace
#endif

namespace heap::integrations {

namespace {

constexpr int kAuthCodeTimeoutMs = 3 * 60 * 1000;
constexpr int kDeviceTimeoutMs = 14 * 60 * 1000;  // device codes live ~15 min

QByteArray base64Url(const QByteArray& raw) {
  return raw.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals);
}

// A static page. Nothing from the request is echoed into it, so there is
// nothing for a crafted callback URL to inject.
QByteArray landingPage(const QByteArray& headline, const QByteArray& detail) {
  return "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
         "<title>heap</title><style>"
         "body{background:#0f1419;color:#c8d2dc;font:15px/1.6 system-ui,sans-serif;"
         "display:flex;align-items:center;justify-content:center;height:100vh;margin:0}"
         "div{text-align:center}h1{font-size:19px;font-weight:600;margin:0 0 6px}"
         "p{margin:0;color:#7c8b99;font-size:13px}</style></head>"
         "<body><div><h1>" +
         headline + "</h1><p>" + detail + "</p></div></body></html>";
}

}  // namespace

// ───────────────────────── LoopbackReceiver ─────────────────────────

LoopbackReceiver::LoopbackReceiver(Mode mode, QByteArray expectedState, QObject* parent) :
    QObject(parent), m_mode(mode), m_state(std::move(expectedState)), m_nonce(OAuthManager::randomToken(16)) {
}

LoopbackReceiver::~LoopbackReceiver() = default;

bool LoopbackReceiver::sameToken(const QByteArray& a, const QByteArray& b) {
  // Length is not secret (it's fixed by randomToken); the contents are, so the
  // comparison always walks the whole string.
  if(a.isEmpty() || a.size() != b.size()) {
    return false;
  }
  unsigned char diff = 0;
  for(int i = 0; i < a.size(); ++i) {
    diff |= static_cast<unsigned char>(a.at(i) ^ b.at(i));
  }
  return diff == 0;
}

bool LoopbackReceiver::listen(quint16 port) {
  m_server = new QTcpServer(this);
  // Loopback only: a redirect listener must never be reachable from the network.
  if(!m_server->listen(QHostAddress::LocalHost, port)) {
    return false;
  }
  connect(m_server, &QTcpServer::newConnection, this, &LoopbackReceiver::acceptConnections);
  return true;
}

quint16 LoopbackReceiver::port() const {
  return m_server ? m_server->serverPort() : 0;
}

void LoopbackReceiver::close() {
  if(m_server) {
    m_server->close();
  }
}

void LoopbackReceiver::acceptConnections() {
  while(m_server->hasPendingConnections()) {
    QTcpSocket* sock = m_server->nextPendingConnection();
    connect(sock, &QTcpSocket::readyRead, sock, [this, sock]() {
      m_buffers[sock] += sock->readAll();
      const QByteArray buf = m_buffers.value(sock);
      const int headerEnd = static_cast<int>(buf.indexOf("\r\n\r\n"));
      if(headerEnd < 0) {
        if(buf.size() > 16384) {
          sock->abort();  // a header that never ends is not a browser
        }
        return;
      }
      int contentLength = 0;
      const QList<QByteArray> lines = buf.left(headerEnd).split('\n');
      for(const QByteArray& line : lines) {
        if(line.trimmed().toLower().startsWith("content-length:")) {
          contentLength = line.mid(line.indexOf(':') + 1).trimmed().toInt();
        }
      }
      if(buf.size() < headerEnd + 4 + contentLength) {
        return;  // body still arriving
      }
      m_buffers.remove(sock);
      handleRequest(sock, buf, headerEnd);
    });
    connect(sock, &QTcpSocket::disconnected, sock, [this, sock]() {
      m_buffers.remove(sock);
      sock->deleteLater();
    });
  }
}

void LoopbackReceiver::handleRequest(QTcpSocket* sock, const QByteArray& raw, int headerEnd) {
  const QList<QByteArray> headerLines = raw.left(headerEnd).split('\n');
  const QList<QByteArray> requestLine = headerLines.value(0).trimmed().split(' ');
  const QByteArray method = requestLine.value(0);
  const QByteArray target = requestLine.value(1);

  QByteArray host;
  for(int i = 1; i < headerLines.size(); ++i) {
    const QByteArray line = headerLines.at(i).trimmed();
    if(line.toLower().startsWith("host:")) {
      host = line.mid(line.indexOf(':') + 1).trimmed().toLower();
    }
  }
  // A DNS-rebinding page resolves its own name to 127.0.0.1 and then talks to
  // this port from the browser under that name; the Host header is what gives
  // it away. Only the literal loopback names are ours.
  const QByteArray expectedHost = QByteArray("127.0.0.1:") + QByteArray::number(port());
  const QByteArray expectedAlias = QByteArray("localhost:") + QByteArray::number(port());
  if(host != expectedHost && host != expectedAlias) {
    reply(sock, 400, "text/plain", "bad host");
    return;
  }

  const int q = static_cast<int>(target.indexOf('?'));
  const QByteArray path = q >= 0 ? target.left(q) : target;
  const QUrlQuery query{QString::fromUtf8(q >= 0 ? target.mid(q + 1) : QByteArray())};

  if(m_mode == Mode::Fragment && method == "POST" && path == "/token") {
    takeToken(sock, QUrlQuery{QString::fromUtf8(raw.mid(headerEnd + 4))});
    return;
  }
  if(method != "GET" || path != "/") {
    // A favicon probe, or anything else that wandered in. Answer and keep
    // listening: the real callback may still be on its way.
    reply(sock, 404, "text/plain", "not found");
    return;
  }
  serveLanding(sock, query);
}

void LoopbackReceiver::serveLanding(QTcpSocket* sock, const QUrlQuery& query) {
  const QByteArray state = query.queryItemValue(QStringLiteral("state")).toUtf8();
  if(!sameToken(state, m_state)) {
    // Not our callback — a stale tab, a probe, or a forged redirect. It must
    // not be able to end the flow, so the listener stays open.
    reply(sock, 400, "text/plain", "unexpected request");
    return;
  }

  const QString error = query.queryItemValue(QStringLiteral("error"));
  if(!error.isEmpty()) {
    const QString description = query.queryItemValue(QStringLiteral("error_description"));
    reply(sock, 200, "text/html", landingPage("Sign-in cancelled", "You can close this tab and try again in heap."));
    if(!m_done) {
      m_done = true;
      emit failed(error == QLatin1String("access_denied") ? QStringLiteral("you declined the authorization request")
                                                          : (description.isEmpty() ? error : description));
    }
    return;
  }

  if(m_mode == Mode::Fragment) {
    // The token is in the URL fragment, which the browser never puts on the
    // wire. Hand back a page that posts it here, then scrubs it from the
    // address bar. The script is the only one allowed to run (CSP + nonce).
    const QByteArray body =
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>heap</title>"
        "<style>body{background:#0f1419;color:#c8d2dc;font:15px/1.6 system-ui,sans-serif;"
        "display:flex;align-items:center;justify-content:center;height:100vh;margin:0}"
        "div{text-align:center}h1{font-size:19px;font-weight:600;margin:0 0 6px}"
        "p{margin:0;color:#7c8b99;font-size:13px}</style></head>"
        "<body><div><h1>Finishing sign-in…</h1><p>You can close this tab in a moment.</p></div>"
        "<script nonce=\"" +
        m_nonce +
        "\">(function(){var h=new URLSearchParams(location.hash.slice(1));"
        "var b=new URLSearchParams();b.set('token',h.get('token')||'');"
        "b.set('state',new URLSearchParams(location.search).get('state')||'');"
        "fetch('/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:b.toString()})"
        ".then(function(){history.replaceState(null,'','/');"
        "document.querySelector('h1').textContent='You can close this tab';"
        "document.querySelector('p').textContent='heap is connected.';});})();</script>"
        "</body></html>";
    reply(sock,
          200,
          "text/html",
          body,
          "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; connect-src 'self'; script-src 'nonce-" + m_nonce +
              "'\r\n");
    return;
  }

  const QString code = query.queryItemValue(QStringLiteral("code"));
  if(code.isEmpty()) {
    reply(sock, 400, "text/plain", "missing code");
    return;
  }
  reply(sock, 200, "text/html", landingPage("You can close this tab", "heap is finishing the sign-in."));
  if(!m_done) {
    m_done = true;
    emit received(QVariantMap{{QStringLiteral("code"), code}});
  }
}

void LoopbackReceiver::takeToken(QTcpSocket* sock, const QUrlQuery& form) {
  const QByteArray state = form.queryItemValue(QStringLiteral("state")).toUtf8();
  const QString token = form.queryItemValue(QStringLiteral("token"));
  if(!sameToken(state, m_state) || token.isEmpty()) {
    reply(sock, 400, "text/plain", "unexpected request");
    return;
  }
  reply(sock, 200, "text/plain", "ok");
  if(!m_done) {
    m_done = true;
    emit received(QVariantMap{{QStringLiteral("token"), token}});
  }
}

void LoopbackReceiver::reply(
    QTcpSocket* sock, int status, const QByteArray& contentType, const QByteArray& body, const QByteArray& extraHeaders) {
  QByteArray out = "HTTP/1.1 " + QByteArray::number(status) + (status == 200 ? " OK" : " Error") + "\r\n";
  out += "Content-Type: " + contentType + "; charset=utf-8\r\n";
  out += "Content-Length: " + QByteArray::number(body.size()) + "\r\n";
  // A page carrying a code or token has no business being cached, sniffed, or
  // quoted back to the provider as a referrer.
  out += "Cache-Control: no-store\r\n";
  out += "Referrer-Policy: no-referrer\r\n";
  out += "X-Content-Type-Options: nosniff\r\n";
  out += extraHeaders;
  out += "Connection: close\r\n\r\n";
  out += body;
  sock->write(out);
  sock->flush();
  sock->disconnectFromHost();
}

// ─────────────────────────── OAuthManager ───────────────────────────

OAuthManager::OAuthManager(QObject* parent) :
    QObject(parent), m_openUrl([](const QUrl& url) {
      QDesktopServices::openUrl(url);
    }) {
}

OAuthManager::~OAuthManager() = default;

QString OAuthManager::redirectUri() {
  return redirectUriFor(kRedirectPort);
}

QString OAuthManager::redirectUriFor(quint16 port) {
  return QStringLiteral("http://127.0.0.1:%1/").arg(port);
}

bool OAuthManager::deviceFlowAvailable() {
  return HEAP_HAVE_DEVICE_OAUTH != 0;
}

QByteArray OAuthManager::randomToken(int bytes) {
  QByteArray raw(bytes, Qt::Uninitialized);
  QRandomGenerator::system()->generate(raw.begin(), raw.end());
  return base64Url(raw);
}

QByteArray OAuthManager::pkceChallenge(const QByteArray& verifier) {
  return base64Url(QCryptographicHash::hash(verifier, QCryptographicHash::Sha256));
}

QUrl OAuthManager::buildAuthorizeUrl(const Params& p, const QString& redirectUri, const QByteArray& state, const QByteArray& challenge) {
  QUrl url(p.authUrl);
  QUrlQuery query(url.query());
  query.addQueryItem(p.clientIdParam, p.clientId);
  query.addQueryItem(p.redirectParam, redirectUri);
  query.addQueryItem(QStringLiteral("state"), QString::fromLatin1(state));
  if(p.flow != OAuthFlow::ImplicitFragment) {
    query.addQueryItem(QStringLiteral("response_type"), QStringLiteral("code"));
  }
  if(!p.scope.isEmpty()) {
    // Most providers take space-separated scopes; Todoist and Trello want commas.
    query.addQueryItem(QStringLiteral("scope"), QString(p.scope).replace(QLatin1Char(' '), p.scopeSeparator));
  }
  if(!challenge.isEmpty()) {
    query.addQueryItem(QStringLiteral("code_challenge"), QString::fromLatin1(challenge));
    query.addQueryItem(QStringLiteral("code_challenge_method"), QStringLiteral("S256"));
  }
  for(const auto& extra : p.extraAuthParams) {
    query.addQueryItem(extra.first, extra.second);
  }
  url.setQuery(query);
  return url;
}

void OAuthManager::setUrlOpener(std::function<void(const QUrl&)> opener) {
  if(opener) {
    m_openUrl = std::move(opener);
  }
}

void OAuthManager::setNetworkAccessManager(QNetworkAccessManager* nam) {
  m_nam = nam;
}

void OAuthManager::start(const Params& params) {
  if(params.flow == OAuthFlow::Device) {
    startDevice(params);
  } else {
    startAuthCode(params);
  }
}

void OAuthManager::armTimeout(int ms, const QString& message) {
  m_timeout = new QTimer(this);
  m_timeout->setSingleShot(true);
  connect(m_timeout, &QTimer::timeout, this, [this, message]() {
    report({false, {}, {}, {}, message});
  });
  m_timeout->start(ms);
}

void OAuthManager::startAuthCode(const Params& params) {
  const bool fragment = params.flow == OAuthFlow::ImplicitFragment;
  const QByteArray state = randomToken();
  m_receiver = new LoopbackReceiver(fragment ? LoopbackReceiver::Mode::Fragment : LoopbackReceiver::Mode::Query, state, this);
  if(!m_receiver->listen(params.redirectPort)) {
    report({false, {}, {}, {}, tr("redirect port %1 is busy — close the other app and retry").arg(params.redirectPort)});
    return;
  }
  const QString redirect = redirectUriFor(m_receiver->port());

  // PKCE (RFC 7636) binds the code to this process. Send it whenever the
  // provider tolerates it, secret or not: another local process could have
  // raced us for the port, and without a verifier it could spend our code.
  QByteArray verifier;
  QByteArray challenge;
  if(params.usePkce && !fragment) {
    verifier = randomToken(48);
    challenge = pkceChallenge(verifier);
  }

  connect(m_receiver, &LoopbackReceiver::failed, this, [this](const QString& error) {
    report({false, {}, {}, {}, error});
  });
  connect(m_receiver, &LoopbackReceiver::received, this, [this, params, redirect, verifier](const QVariantMap& got) {
    m_receiver->close();
    // Trello answers with the token itself — there is nothing left to exchange.
    if(params.flow == OAuthFlow::ImplicitFragment) {
      OAuthResult r;
      r.ok = true;
      r.accessToken = got.value(QStringLiteral("token")).toString();
      report(r);
      return;
    }
    if(m_nam == nullptr) {
      m_nam = new QNetworkAccessManager(this);
    }
    AuthCodeParams exchange;
    exchange.tokenUrl = params.tokenUrl;
    exchange.clientId = params.clientId;
    exchange.clientSecret = params.clientSecret;
    exchange.code = got.value(QStringLiteral("code")).toString();
    exchange.redirectUri = redirect;
    exchange.codeVerifier = QString::fromLatin1(verifier);
    exchange.style = params.tokenStyle;
    exchangeAuthCode(m_nam, exchange, [this](const OAuthResult& r) {
      report(r);
    });
  });

  armTimeout(kAuthCodeTimeoutMs, tr("timed out waiting for browser sign-in"));
  m_openUrl(buildAuthorizeUrl(params, redirect, state, challenge));
}

#if !HEAP_HAVE_DEVICE_OAUTH
void OAuthManager::startDevice(const Params& params) {
  Q_UNUSED(params);
  report({false, {}, {}, {}, tr("browser sign-in for this provider needs Qt 6.9 or newer — use an access token")});
}
#else
void OAuthManager::startDevice(const Params& params) {
  // OAuth 2.0 Device Authorization Grant (RFC 8628): request a short user code,
  // ask the user to enter it in the browser, then poll for the token. No secret,
  // no loopback — the right fit for GitHub in an open-source client.
  m_deviceFlow = new QOAuth2DeviceAuthorizationFlow(this);
  m_deviceFlow->setAuthorizationUrl(QUrl(params.authUrl));  // device authorization endpoint
  m_deviceFlow->setTokenUrl(QUrl(params.tokenUrl));
  m_deviceFlow->setClientIdentifier(params.clientId);
  m_deviceFlow->setNetworkRequestModifier(this, forceJsonAccept);  // GitHub → JSON
  if(!params.scope.isEmpty()) {
    QSet<QByteArray> scopes;
    const QStringList parts = params.scope.split(QChar(' '), Qt::SkipEmptyParts);
    for(const QString& s : parts) {
      scopes.insert(s.toUtf8());
    }
    m_deviceFlow->setRequestedScopeTokens(scopes);
  }

  connect(m_deviceFlow,
          &QOAuth2DeviceAuthorizationFlow::authorizeWithUserCode,
          this,
          [this](const QUrl& verificationUrl, const QString& code, const QUrl& complete) {
            // `complete` (verification_uri_complete) pre-fills the code; GitHub
            // doesn't provide it, so fall back to the plain verification URL.
            const QUrl open = complete.isEmpty() ? verificationUrl : complete;
            emit userCode(code, verificationUrl.toString());
            m_openUrl(open);
            m_deviceFlow->startTokenPolling();
          });
  connect(m_deviceFlow, &QAbstractOAuth::granted, this, [this]() {
    OAuthResult r;
    r.ok = true;
    r.accessToken = m_deviceFlow->token();
    r.refreshToken = m_deviceFlow->refreshToken();
    r.expiresAt = m_deviceFlow->expirationAt();
    report(r);
  });
  connect(m_deviceFlow, &QAbstractOAuth::requestFailed, this, [this](QAbstractOAuth::Error) {
    report({false, {}, {}, {}, tr("authorization was denied, expired, or failed")});
  });

  armTimeout(kDeviceTimeoutMs, tr("timed out waiting for device authorization"));
  m_deviceFlow->grant();
}
#endif

void OAuthManager::report(const OAuthResult& result) {
  if(m_done) {
    return;
  }
  m_done = true;
  if(m_timeout) {
    m_timeout->stop();
  }
#if HEAP_HAVE_DEVICE_OAUTH
  if(m_deviceFlow) {
    m_deviceFlow->stopTokenPolling();
  }
#endif
  if(m_receiver) {
    m_receiver->close();
  }
  emit finished(result);
}

}  // namespace heap::integrations
