#pragma once

#include <QDateTime>
#include <QObject>
#include <QString>

class QOAuth2AuthorizationCodeFlow;
class QOAuth2DeviceAuthorizationFlow;
class QOAuthHttpServerReplyHandler;
class QTimer;

namespace heap::integrations {

// Result of one browser OAuth flow.
struct OAuthResult {
  bool ok = false;
  QString accessToken;
  QString refreshToken;
  QDateTime expiresAt;
  QString error;
};

// Runs one OAuth 2.0 Authorization Code flow (with PKCE for public clients)
// against a loopback redirect: spins up a 127.0.0.1 listener, opens the system
// browser for consent, exchanges the code, and emits finished() exactly once.
// One-shot — create per sign-in, delete on finished.
class OAuthManager : public QObject {
  Q_OBJECT

 public:
  explicit OAuthManager(QObject* parent = nullptr);
  ~OAuthManager() override;

  struct Params {
    QString authUrl;
    QString tokenUrl;
    QString clientId;
    QString clientSecret;  // empty for PKCE/public clients
    QString scope;         // space-separated
    bool usePkce = true;
    // Device Authorization Grant (RFC 8628): no loopback, no secret. When true,
    // `authUrl` is the device authorization endpoint and the flow surfaces a
    // short user code via the userCode() signal instead of a browser redirect.
    bool deviceFlow = false;
  };

  // Fixed loopback port for the OAuth redirect. Users must register
  // `http://127.0.0.1:<kRedirectPort>/` as the callback URL in their OAuth app —
  // an ephemeral port would never match a registered redirect URI.
  static constexpr quint16 kRedirectPort = 51789;
  static QString redirectUri();

  // Begin the flow. Emits finished() with the tokens or an error.
  void start(const Params& params);

 signals:
  void finished(const heap::integrations::OAuthResult& result);
  // Device flow only: the user must open `verificationUri` in a browser and
  // enter `code`. Emitted once, before finished().
  void userCode(const QString& code, const QString& verificationUri);

 private:
  void startAuthCode(const Params& params);
  void startDevice(const Params& params);
  void report(const OAuthResult& result);

  QOAuth2AuthorizationCodeFlow* m_flow = nullptr;
  QOAuth2DeviceAuthorizationFlow* m_deviceFlow = nullptr;
  QOAuthHttpServerReplyHandler* m_handler = nullptr;
  QTimer* m_timeout = nullptr;
  bool m_done = false;
};

}  // namespace heap::integrations
