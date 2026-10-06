#pragma once

#include <QDateTime>
#include <QString>

#include <cstdint>

// How each connected tracker has been doing (APP-164): when it last answered,
// what went wrong last, how much the last pull carried. Read-only facts for
// Settings → Integrations; nothing here retries or changes anything.
namespace heap::integrations {

// What kind of failure a pull ended in, from the HTTP status the provider
// reported (0 = no HTTP answer at all) and its error text.
enum class FailureKind : std::uint8_t {
  None,
  Auth,         // 401: the token was rejected or has expired
  Forbidden,    // 403: signed in, but not allowed (scope, permissions)
  NotFound,     // 404: the repo / project / site is not there, or hidden
  RateLimited,  // 429 (or a 403 that says so)
  Server,       // 5xx: the tracker itself failed
  Network,      // no HTTP answer: offline, DNS, TLS, timeout
  Other,        // anything else
};

FailureKind classifyFailure(int httpStatus, const QString& error);

// One plain sentence for the kind, in the UI language. Empty for None.
QString failureText(FailureKind kind, bool ru);

// "just now", "5 min ago", "3 h ago", "2 d ago" (or Russian), from `then` to
// `now`. Empty for an invalid `then`. Pure: the caller passes the clock.
QString relativeAge(const QDateTime& then, const QDateTime& now, bool ru);

// "expired", "expires in 40 min", "expires in 3 d" — or empty when the token
// has no known expiry.
QString expiryText(const QDateTime& expires, const QDateTime& now, bool ru);

struct ProviderHealth {
  QDateTime lastOk;         // the last pull that came back
  int lastItems = -1;       // issues that pull carried, -1 = none yet
  QDateTime lastFailureAt;  // the last pull that failed
  FailureKind lastFailure = FailureKind::None;
  QString lastError;  // the provider's own words, for the tooltip

  // A pull came back with `items` issues: the failure, if any, is history.
  void recordOk(const QDateTime& at, int items);
  void recordFailure(const QDateTime& at, int httpStatus, const QString& error);
  // The failure is current only if nothing has succeeded since.
  bool failing() const;
};

}  // namespace heap::integrations
