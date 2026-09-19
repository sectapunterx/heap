#pragma once

#include <QDateTime>
#include <QString>

// Value types shared by the OAuth pieces: the descriptor's OAuthConfig, the
// browser flow (OAuthManager) and the token endpoint calls (OAuthRefresh.h).
// Kept in their own header so ProviderDescriptor.h can name them without
// pulling in a QObject header.

namespace heap::integrations {

// Result of one browser OAuth flow, or of one token-endpoint round trip.
struct OAuthResult {
  bool ok = false;
  QString accessToken;
  QString refreshToken;
  QDateTime expiresAt;
  QString error;
};

// How the user's consent turns into a token.
enum class OAuthFlow {
  AuthCode,          // authorization code + loopback redirect (RFC 6749 §4.1, RFC 8252)
  Device,            // device authorization grant (RFC 8628) — GitHub
  ImplicitFragment,  // token handed back in the redirect's URL fragment — Trello
};

// How a provider wants its token request dressed. One grant, four dialects.
enum class TokenStyle {
  FormBody,       // form-encoded body carrying client_id (+ client_secret) — GitLab, Todoist, Asana, Sentry
  BasicAuthForm,  // form-encoded body, client credentials in an HTTP Basic header — Bitbucket
  JsonBody,       // JSON object body carrying everything — Atlassian, ClickUp
};

}  // namespace heap::integrations
