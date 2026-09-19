#pragma once

#include "integrations/OAuthManager.h"
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

// Renewing an OAuth access token.
//
// A browser sign-in hands out a short-lived access token — GitLab's lives two
// hours — and heap stored the refresh token without ever using it, so syncing
// went quiet shortly after connecting and every pull looked like an empty
// backlog. A refresh is a plain form POST, so this deliberately avoids
// QOAuth2AuthorizationCodeFlow: those classes only exist from Qt 6.9, while the
// distro builds still compile against 6.4 (see OAuthManager.cpp). Header-only
// for the same reason ReplyError.h is.

namespace heap::integrations {

struct RefreshParams {
  QString tokenUrl;
  QString clientId;
  QString clientSecret;  // empty for PKCE / public clients
  QString refreshToken;
  QString redirectUri;  // GitLab requires it to match the original grant
};

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
  QUrlQuery form;
  form.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("refresh_token"));
  form.addQueryItem(QStringLiteral("refresh_token"), params.refreshToken);
  form.addQueryItem(QStringLiteral("client_id"), params.clientId);
  if(!params.clientSecret.isEmpty()) {
    form.addQueryItem(QStringLiteral("client_secret"), params.clientSecret);
  }
  if(!params.redirectUri.isEmpty()) {
    form.addQueryItem(QStringLiteral("redirect_uri"), params.redirectUri);
  }

  QNetworkRequest req{QUrl(params.tokenUrl)};
  req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
  req.setRawHeader("Accept", "application/json");  // GitHub answers form-encoded otherwise
  req.setRawHeader("User-Agent", "heap-sync");

  QNetworkReply* reply = nam->post(req, form.query(QUrl::FullyEncoded).toUtf8());
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

}  // namespace heap::integrations
