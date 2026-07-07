#include "integrations/OAuthManager.h"

#include <QAbstractOAuth>
#include <QDesktopServices>
#include <QHostAddress>
#include <QNetworkRequest>
#include <QOAuth2AuthorizationCodeFlow>
#include <QOAuthHttpServerReplyHandler>
#include <QtGlobal>
#include <QTimer>

// QOAuth2DeviceAuthorizationFlow and QAbstractOAuth2::setNetworkRequestModifier
// both landed in Qt 6.9. Distro packaging (e.g. the Ubuntu .deb) still builds
// against the system Qt 6.4, so degrade gracefully there: GitHub device sign-in
// is unavailable (fall back to a token) and the GitLab loopback flow runs
// without the JSON-Accept modifier — GitLab already returns JSON, so it works.
#define HEAP_HAVE_OAUTH_DEVICE_FLOW (QT_VERSION >= QT_VERSION_CHECK(6, 9, 0))

#if HEAP_HAVE_OAUTH_DEVICE_FLOW
#include <QOAuth2DeviceAuthorizationFlow>

namespace {
// GitHub's OAuth endpoints (device/code, access_token) default to
// `application/x-www-form-urlencoded`; Qt's OAuth flows expect JSON and abort
// with "Authorization stage: invalid response format" otherwise. Force JSON on
// every OAuth request so the responses parse. Harmless for providers (GitLab,
// Gitea) that already return JSON.
void forceJsonAccept(QNetworkRequest& req, QAbstractOAuth::Stage) {
  req.setRawHeader("Accept", "application/json");
}
}  // namespace
#endif

namespace heap::integrations {

OAuthManager::OAuthManager(QObject* parent) : QObject(parent) {
}

OAuthManager::~OAuthManager() = default;

QString OAuthManager::redirectUri() {
  return QStringLiteral("http://127.0.0.1:%1/").arg(kRedirectPort);
}

void OAuthManager::start(const Params& params) {
  if(params.deviceFlow) {
    startDevice(params);
  } else {
    startAuthCode(params);
  }
}

void OAuthManager::startDevice(const Params& params) {
#if !HEAP_HAVE_OAUTH_DEVICE_FLOW
  Q_UNUSED(params);
  report({false, {}, {}, {}, QStringLiteral("browser sign-in for this provider needs Qt 6.9 or newer — use an access token")});
}
#else
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
            QDesktopServices::openUrl(open);
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
    report({false, {}, {}, {}, QStringLiteral("authorization was denied, expired, or failed")});
  });

  // Device codes typically live ~15 min; give up a little before that.
  m_timeout = new QTimer(this);
  m_timeout->setSingleShot(true);
  connect(m_timeout, &QTimer::timeout, this, [this]() {
    report({false, {}, {}, {}, QStringLiteral("timed out waiting for device authorization")});
  });
  m_timeout->start(14 * 60 * 1000);

  m_deviceFlow->grant();
}
#endif

void OAuthManager::startAuthCode(const Params& params) {
  // Loopback listener on a FIXED 127.0.0.1 port — must equal the redirect URI
  // registered in the provider's OAuth app.
  m_handler = new QOAuthHttpServerReplyHandler(QHostAddress::LocalHost, kRedirectPort, this);
  if(!m_handler->isListening()) {
    report({false, {}, {}, {}, QStringLiteral("redirect port %1 is busy — close the other app and retry").arg(kRedirectPort)});
    return;
  }

  m_flow = new QOAuth2AuthorizationCodeFlow(this);
  m_flow->setAuthorizationUrl(QUrl(params.authUrl));
  m_flow->setTokenUrl(QUrl(params.tokenUrl));
  m_flow->setClientIdentifier(params.clientId);
#if HEAP_HAVE_OAUTH_DEVICE_FLOW
  m_flow->setNetworkRequestModifier(this, forceJsonAccept);  // JSON token responses
#endif
  if(!params.clientSecret.isEmpty()) {
    m_flow->setClientIdentifierSharedKey(params.clientSecret);
  }
  if(params.usePkce) {
    m_flow->setPkceMethod(QOAuth2AuthorizationCodeFlow::PkceMethod::S256);
  }
  if(!params.scope.isEmpty()) {
    QSet<QByteArray> scopes;
    const QStringList parts = params.scope.split(QChar(' '), Qt::SkipEmptyParts);
    for(const QString& s : parts) {
      scopes.insert(s.toUtf8());
    }
    m_flow->setRequestedScopeTokens(scopes);
  }
  m_flow->setReplyHandler(m_handler);

  connect(m_flow, &QOAuth2AuthorizationCodeFlow::authorizeWithBrowser, this, [](const QUrl& url) {
    QDesktopServices::openUrl(url);
  });
  connect(m_flow, &QOAuth2AuthorizationCodeFlow::granted, this, [this]() {
    OAuthResult r;
    r.ok = true;
    r.accessToken = m_flow->token();
    r.refreshToken = m_flow->refreshToken();
    r.expiresAt = m_flow->expirationAt();
    report(r);
  });
  connect(m_flow, &QAbstractOAuth::requestFailed, this, [this](QAbstractOAuth::Error) {
    report({false, {}, {}, {}, QStringLiteral("authorization was denied or failed")});
  });

  // Give up if the user never finishes so the loopback port doesn't linger.
  m_timeout = new QTimer(this);
  m_timeout->setSingleShot(true);
  connect(m_timeout, &QTimer::timeout, this, [this]() {
    report({false, {}, {}, {}, QStringLiteral("timed out waiting for browser sign-in")});
  });
  m_timeout->start(3 * 60 * 1000);

  m_flow->grant();
}

void OAuthManager::report(const OAuthResult& result) {
  if(m_done) {
    return;
  }
  m_done = true;
  if(m_timeout) {
    m_timeout->stop();
  }
#if HEAP_HAVE_OAUTH_DEVICE_FLOW
  if(m_deviceFlow) {
    m_deviceFlow->stopTokenPolling();
  }
#endif
  if(m_handler) {
    m_handler->close();
  }
  emit finished(result);
}

}  // namespace heap::integrations
