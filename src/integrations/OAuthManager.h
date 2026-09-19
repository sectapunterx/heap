#pragma once

#include "integrations/OAuthTypes.h"

#include <QByteArray>
#include <QHash>
#include <QList>
#include <QObject>
#include <QPair>
#include <QString>
#include <QUrl>
#include <QUrlQuery>
#include <QVariantMap>

#include <cstdint>
#include <functional>

class QNetworkAccessManager;
class QOAuth2DeviceAuthorizationFlow;
class QTcpServer;
class QTcpSocket;
class QTimer;

namespace heap::integrations {

// The loopback half of a browser sign-in (RFC 8252 §7.3): a 127.0.0.1 listener
// the provider redirects the browser back to. It completes on exactly one valid
// callback — one whose `state` matches — and serves a static "you can close
// this tab" page. Everything else (a wrong state, a favicon probe, another
// process poking the port) gets a 4xx and is ignored, so a stray request can
// neither finish nor abort the flow.
class LoopbackReceiver : public QObject {
  Q_OBJECT

 public:
  enum class Mode : std::uint8_t {
    Query,     // GET /?code=…&state=…
    Fragment,  // GET /?state=… serves a page whose script POSTs /token back with
               // the `#token=…` fragment the server itself never sees (Trello)
  };

  LoopbackReceiver(Mode mode, QByteArray expectedState, QObject* parent = nullptr);
  ~LoopbackReceiver() override;

  // Bind 127.0.0.1:<port>; 0 picks a free port (tests). False when it's busy.
  bool listen(quint16 port);
  quint16 port() const;
  void close();

  // Constant-time equality, so a caller can't walk the state byte by byte.
  static bool sameToken(const QByteArray& a, const QByteArray& b);

 signals:
  // The callback arrived and its state matched. Carries "code" or "token".
  void received(const QVariantMap& params);
  // The provider reported a failure for this state (error=access_denied, …).
  void failed(const QString& error);

 private:
  void acceptConnections();
  void handleRequest(QTcpSocket* sock, const QByteArray& raw, int headerEnd);
  void serveLanding(QTcpSocket* sock, const QUrlQuery& query);
  void takeToken(QTcpSocket* sock, const QUrlQuery& form);
  void reply(QTcpSocket* sock, int status, const QByteArray& contentType, const QByteArray& body, const QByteArray& extraHeaders = {});

  Mode m_mode;
  QByteArray m_state;
  QByteArray m_nonce;  // CSP nonce for the Fragment page's inline script
  QTcpServer* m_server = nullptr;
  QHash<QTcpSocket*, QByteArray> m_buffers;
  bool m_done = false;
};

// Runs one browser OAuth flow and emits finished() exactly once.
// One-shot — create per sign-in, delete on finished.
//
// AuthCode and ImplicitFragment are hand-rolled on QTcpServer plus a plain POST
// (exchangeAuthCode in OAuthRefresh.h). Qt's QOAuth2AuthorizationCodeFlow can't
// send Atlassian's JSON token body or Bitbucket's HTTP Basic client auth, can't
// read Trello's fragment response, and only became usable in Qt 6.9 — while the
// distro builds still compile against 6.4. The device grant (GitHub) stays on
// QOAuth2DeviceAuthorizationFlow and therefore still needs 6.9; ask
// deviceFlowAvailable() before offering it.
class OAuthManager : public QObject {
  Q_OBJECT

 public:
  explicit OAuthManager(QObject* parent = nullptr);
  ~OAuthManager() override;

  struct Params {
    OAuthFlow flow = OAuthFlow::AuthCode;
    QString authUrl;   // authorization endpoint — the device endpoint for Device
    QString tokenUrl;  // unused by ImplicitFragment
    QString clientId;
    QString clientSecret;  // empty for PKCE / public clients
    QString scope;
    QString scopeSeparator = QStringLiteral(" ");
    bool usePkce = true;  // AuthCode only
    TokenStyle tokenStyle = TokenStyle::FormBody;
    QList<QPair<QString, QString>> extraAuthParams;  // Atlassian audience/prompt, Trello expiration/name…
    // The query keys this provider expects the client id and the redirect
    // under — Trello calls them `key` and `return_url`.
    QString clientIdParam = QStringLiteral("client_id");
    QString redirectParam = QStringLiteral("redirect_uri");
    // Loopback port. 0 = any free port, for tests only: a real provider only
    // redirects to the URI its OAuth app registered, i.e. kRedirectPort.
    quint16 redirectPort = kRedirectPort;
  };

  // Fixed loopback port for the OAuth redirect. Users must register
  // `http://127.0.0.1:<kRedirectPort>/` as the callback URL in their OAuth app —
  // an ephemeral port would never match a registered redirect URI.
  static constexpr quint16 kRedirectPort = 51789;
  static QString redirectUri();
  static QString redirectUriFor(quint16 port);

  // True when this build can run the device grant (needs Qt ≥ 6.9).
  static bool deviceFlowAvailable();

  // ── Pure helpers, unit-tested ──
  // RFC 7636 §4.2: BASE64URL(SHA256(verifier)), unpadded.
  static QByteArray pkceChallenge(const QByteArray& verifier);
  // `bytes` random bytes as unpadded base64url — state, PKCE verifier, nonce.
  static QByteArray randomToken(int bytes = 32);
  // The URL the browser is sent to. An empty `challenge` means no PKCE.
  static QUrl buildAuthorizeUrl(const Params& p, const QString& redirectUri, const QByteArray& state, const QByteArray& challenge);

  // Where the consent URL goes. Defaults to the system browser.
  void setUrlOpener(std::function<void(const QUrl&)> opener);
  // Network used for the token exchange. Defaults to a private QNAM.
  void setNetworkAccessManager(QNetworkAccessManager* nam);

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
  void armTimeout(int ms, const QString& message);
  void report(const OAuthResult& result);

  std::function<void(const QUrl&)> m_openUrl;
  QNetworkAccessManager* m_nam = nullptr;
  LoopbackReceiver* m_receiver = nullptr;
  QOAuth2DeviceAuthorizationFlow* m_deviceFlow = nullptr;
  QTimer* m_timeout = nullptr;
  bool m_done = false;
};

}  // namespace heap::integrations
