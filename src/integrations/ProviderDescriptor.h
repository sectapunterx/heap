#pragma once

#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QList>
#include <QPair>
#include <QString>
#include <QStringList>
#include <QVector>

namespace heap::integrations {

// How the access token is presented to the remote API. Only the two styles the
// generic REST providers need are handled by RestIssueProvider; providers whose
// auth doesn't fit (Jira Basic, Trello key+token in the query) are bespoke.
enum class AuthKind {
  HeaderToken,   // <headerName>: <tokenPrefix><token>   (GitHub "token ", Bearer, raw)
  CustomHeader,  // <headerName>: <token>                (GitLab PRIVATE-TOKEN, Redmine key)
};

struct AuthRecipe {
  AuthKind kind = AuthKind::HeaderToken;
  QByteArray headerName = "Authorization";
  QByteArray tokenPrefix;                             // "token " | "Bearer " | "" (HeaderToken only)
  QList<QPair<QByteArray, QByteArray>> extraHeaders;  // Accept, X-GitHub-Api-Version, …
};

// Declarative extraction of one ExternalTask from one JSON issue object. Every
// field is a dot-path into the object ("status.name", "links.html.href"); an
// empty string means "not present". Used by parseWithFieldMap when a descriptor
// has no bespoke ParseFn.
struct FieldMap {
  QString arrayPointer;  // "" = root array, else a key holding the array ("issues","data","values")
  QString id;
  QString title;
  QString body;
  QString status;        // dot-path to a status string (skipped when boolStatusField is set)
  QString priority;      // dot-path to a provider-native priority name
  QString url;           // dot-path to a web URL (skipped when urlTemplate is set)
  QString urlTemplate;   // "{baseUrl}/issues/{id}" — built when the object carries no URL
  QString updatedAt;     // dot-path to an ISO-8601 timestamp
  QString labels;        // dot-path to a labels array
  QString labelNameKey;  // if labels are objects, the key holding the name; empty = array of strings
  // Boolean-completion providers (Asana `completed`, Todoist `is_completed`)
  // have no status string — derive one from a bool leaf instead.
  QString boolStatusField;
  QString boolTrueStatus = QStringLiteral("closed");
  QString boolFalseStatus = QStringLiteral("open");
};

// A credential/config input rendered by the Settings → Integrations card.
struct FieldSpec {
  QString key;
  QString label;
  QString placeholder;
  bool mono = false;
  bool secret = false;  // stored in the OS keychain, never in state.json
};

using ParseFn = QVector<ExternalTask> (*)(const QByteArray& body, const QString& baseUrl);
using PushMapFn = QString (*)(const QString& heapColumn);

// Browser-based OAuth 2.0 (Authorization Code, loopback redirect). When
// supported, the "Sign in with browser" button runs the flow and stores the
// resulting access token as the provider's `token` secret with authMode=oauth
// (so RestIssueProvider sends it as a Bearer token). URLs may contain {host}.
struct OAuthConfig {
  bool supported = false;
  QString authUrl;      // authorization endpoint (may be a {host} template)
  QString tokenUrl;     // token endpoint (may be a {host} template)
  QString scope;        // space-separated scopes
  bool usePkce = true;  // PKCE S256 (no client secret) vs. confidential client
  // App-registered credentials baked into the build. When clientId is non-empty
  // the card offers true one-click "Connect with browser" (no field to fill);
  // otherwise the user pastes a client ID under Advanced. See ProviderRegistry.cpp.
  QString clientId;
  QString clientSecret;  // only for confidential clients (GitHub); empty for PKCE
  // OAuth 2.0 Device Authorization Grant (RFC 8628). Used for providers whose
  // web flow needs a client secret we can't safely embed (GitHub): the user
  // authorizes a short code in the browser — client ID only, no secret, no
  // loopback. When true, authUrl is ignored and deviceAuthUrl is the device
  // authorization endpoint.
  bool deviceFlow = false;
  QString deviceAuthUrl;  // e.g. https://github.com/login/device/code
};

// The single source of truth for one tracker integration: its UI card, its
// config schema, and (for generic providers) the REST recipe RestIssueProvider
// executes. Bespoke providers (Jira, Trello) set `bespoke = true` and leave the
// network templates empty — their behaviour lives in a dedicated subclass.
struct ProviderDescriptor {
  // Identity + UI.
  QString id;
  QString displayName;
  QString color;    // card swatch, e.g. "#5a6371"
  QString icon;     // single-glyph badge
  QString descKey;  // I18n key for the one-line description
  QVector<FieldSpec> uiFields;
  QStringList requiredKeys;  // must be non-empty before the provider is built
  QStringList secretKeys;    // subset of fields kept in the keychain

  bool bespoke = false;

  // ── Generic REST recipe (ignored when bespoke) ──
  QString baseUrlTemplate;  // "https://api.github.com" | "{host}"
  AuthRecipe auth;
  QString tokenKey = QStringLiteral("token");  // cfg key holding the secret
  QString listMethod = QStringLiteral("GET");
  QString listPathTemplate;  // "/repos/{repo}/issues?state=all&per_page=100"
  // Zero-config "issues assigned to me" endpoint used when scopeKey is blank, so
  // an OAuth-connected provider needs no repo/project entry. scopeKey names the
  // scoping field (repo/projectId); when it's empty this path is used instead of
  // listPathTemplate, and push is skipped (no repo to write back to).
  QString selfListPathTemplate;
  QString scopeKey;          // "repo" | "projectId" — empty for providers without a self endpoint
  QString baseUrlFallback;   // default base URL when {host} resolves empty (e.g. gitlab.com)
  FieldMap fields;           // used when parser == nullptr
  ParseFn parser = nullptr;  // bespoke parser (reused GitHub/GitLab parsers)

  // Write-back (empty pushPathTemplate = pull-only for v1).
  QString pushMethod = QStringLiteral("PATCH");
  QString pushPathTemplate;     // "/repos/{repo}/issues/{externalId}"
  QByteArray pushBodyTemplate;  // may contain "{state}"; empty = no body
  PushMapFn pushMap = nullptr;

  // Optional browser OAuth (see OAuthConfig).
  OAuthConfig oauth;
};

}  // namespace heap::integrations
