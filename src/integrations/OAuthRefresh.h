#pragma once

#include "integrations/OAuthTypes.h"
#include "integrations/ReplyError.h"

#include <QByteArray>
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QString>
#include <QUrl>
#include <QUrlQuery>

#include <functional>
#include <utility>

// Talking to an OAuth token endpoint: exchanging an authorization code, and
// renewing an access token.
//
// Both are a single POST, deliberately hand-rolled rather than done through
// QOAuth2AuthorizationCodeFlow. That class only became usable in Qt 6.9 while
// the distro builds still compile against 6.4 (see OAuthManager.cpp), and it
// can send neither Atlassian's JSON body nor Bitbucket's HTTP Basic client
// auth. Header-only for the same reason ReplyError.h is: tests/CMakeLists.txt
// would otherwise have to list one more .cpp.

namespace heap::integrations {

// Parse a token endpoint response: access_token / refresh_token / expires_in,
// or an error + error_description pair.
inline OAuthResult parseTokenResponse(const QByteArray& body, const QDateTime& now = QDateTime::currentDateTime()) {
  OAuthResult r;
  const QJsonObject obj = QJsonDocument::fromJson(body).object();
  r.accessToken = obj.value(QStringLiteral("access_token")).toString();
  r.refreshToken = obj.value(QStringLiteral("refresh_token")).toString();
  if(r.accessToken.isEmpty()) {
    // An error response, or not a token response at all.
    r.error = describeHttpError(0, body, QStringLiteral("no access token in the response"));
    return r;
  }
  const int expiresIn = obj.value(QStringLiteral("expires_in")).toInt();
  if(expiresIn > 0) {
    r.expiresAt = now.addSecs(expiresIn);
  }
  r.ok = true;
  return r;
}

namespace detail {

// Dress one token request per the provider's dialect. Shared by the code
// exchange and the refresh so the two can never drift apart.
inline QNetworkReply* postTokenRequest(QNetworkAccessManager* nam,
                                       const QString& tokenUrl,
                                       const QString& clientId,
                                       const QString& clientSecret,
                                       TokenStyle style,
                                       QList<QPair<QString, QString>> params) {
  QNetworkRequest req{QUrl(tokenUrl)};
  req.setRawHeader("Accept", "application/json");  // GitHub answers form-encoded otherwise
  req.setRawHeader("User-Agent", "heap-sync");

  if(style == TokenStyle::BasicAuthForm) {
    // Bitbucket takes the client credentials in an Authorization header and
    // rejects them in the body.
    const QByteArray basic = (clientId + QLatin1Char(':') + clientSecret).toUtf8().toBase64();
    req.setRawHeader("Authorization", QByteArrayLiteral("Basic ") + basic);
  } else {
    params.append({QStringLiteral("client_id"), clientId});
    if(!clientSecret.isEmpty()) {
      params.append({QStringLiteral("client_secret"), clientSecret});
    }
  }

  if(style == TokenStyle::JsonBody) {
    QJsonObject body;
    for(const auto& kv : params) {
      body.insert(kv.first, kv.second);
    }
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    return nam->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
  }

  QUrlQuery form;
  for(const auto& kv : params) {
    form.addQueryItem(kv.first, kv.second);
  }
  req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
  return nam->post(req, form.query(QUrl::FullyEncoded).toUtf8());
}

// Turn a finished token reply into an OAuthResult. `done` runs exactly once.
inline void finishTokenRequest(QNetworkReply* reply, std::function<void(const OAuthResult&)> done) {
  QObject::connect(reply, &QNetworkReply::finished, reply, [reply, done = std::move(done)]() {
    reply->deleteLater();
    const QByteArray body = reply->readAll();
    OAuthResult r = parseTokenResponse(body);
    if(!r.ok && reply->error() != QNetworkReply::NoError) {
      // Prefer the provider's own words ("invalid_grant") over Qt's.
      r.error = describeHttpError(replyHttpStatus(reply), body, reply->errorString());
    }
    done(r);
  });
}

}  // namespace detail

struct RefreshParams {
  QString tokenUrl;
  QString clientId;
  QString clientSecret;  // empty for PKCE / public clients
  QString refreshToken;
  QString redirectUri;  // GitLab requires it to match the original grant
  TokenStyle style = TokenStyle::FormBody;
};

// One authorization-code exchange (RFC 6749 §4.1.3).
struct AuthCodeParams {
  QString tokenUrl;
  QString clientId;
  QString clientSecret;  // empty for PKCE / public clients
  QString code;
  QString redirectUri;   // must repeat the one the code was granted for
  QString codeVerifier;  // PKCE (RFC 7636); empty when unused
  TokenStyle style = TokenStyle::FormBody;
};

// True when the expiry is known and close. An invalid expiry means the provider
// issues non-expiring tokens (GitHub OAuth apps by default), so there is
// nothing to refresh — and burning the grant anyway would be worse than doing
// nothing.
inline bool tokenNeedsRefresh(const QDateTime& expiresAt, const QDateTime& now = QDateTime::currentDateTime()) {
  if(!expiresAt.isValid()) {
    return false;
  }
  // A minute of slack: a token that expires mid-request is no use either.
  return expiresAt <= now.addSecs(60);
}

// POST grant_type=refresh_token. `done` runs exactly once. Providers rotate the
// refresh token, so the caller has to store whatever comes back.
inline void refreshAccessToken(QNetworkAccessManager* nam, const RefreshParams& params, std::function<void(const OAuthResult&)> done) {
  if(nam == nullptr || params.tokenUrl.isEmpty() || params.refreshToken.isEmpty() || params.clientId.isEmpty()) {
    OAuthResult r;
    r.error = QStringLiteral("nothing to refresh with");
    done(r);
    return;
  }
  QList<QPair<QString, QString>> body{
      {QStringLiteral("grant_type"), QStringLiteral("refresh_token")},
      {QStringLiteral("refresh_token"), params.refreshToken},
  };
  if(!params.redirectUri.isEmpty()) {
    body.append({QStringLiteral("redirect_uri"), params.redirectUri});
  }
  detail::finishTokenRequest(detail::postTokenRequest(nam, params.tokenUrl, params.clientId, params.clientSecret, params.style, body),
                             std::move(done));
}

// POST grant_type=authorization_code. `done` runs exactly once.
inline void exchangeAuthCode(QNetworkAccessManager* nam, const AuthCodeParams& params, std::function<void(const OAuthResult&)> done) {
  if(nam == nullptr || params.tokenUrl.isEmpty() || params.code.isEmpty() || params.clientId.isEmpty()) {
    OAuthResult r;
    r.error = QStringLiteral("nothing to exchange");
    done(r);
    return;
  }
  QList<QPair<QString, QString>> body{
      {QStringLiteral("grant_type"), QStringLiteral("authorization_code")},
      {QStringLiteral("code"), params.code},
      {QStringLiteral("redirect_uri"), params.redirectUri},
  };
  if(!params.codeVerifier.isEmpty()) {
    body.append({QStringLiteral("code_verifier"), params.codeVerifier});
  }
  detail::finishTokenRequest(detail::postTokenRequest(nam, params.tokenUrl, params.clientId, params.clientSecret, params.style, body),
                             std::move(done));
}

}  // namespace heap::integrations
