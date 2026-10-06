// Integrations health (APP-164): what a failed pull means in plain words, and
// the relative times the page shows. The clock is always passed in.

#include "integrations/SyncHealth.h"

#include <gtest/gtest.h>

using heap::integrations::classifyFailure;
using heap::integrations::expiryText;
using heap::integrations::FailureKind;
using heap::integrations::failureText;
using heap::integrations::ProviderHealth;
using heap::integrations::relativeAge;

namespace {
QDateTime fixedNow() {
  return {QDate(2026, 10, 6), QTime(12, 0)};
}
}  // namespace

TEST(SyncHealth, HttpStatusToKind) {
  EXPECT_EQ(classifyFailure(401, "HTTP 401"), FailureKind::Auth);
  EXPECT_EQ(classifyFailure(403, "forbidden"), FailureKind::Forbidden);
  EXPECT_EQ(classifyFailure(403, "API rate limit exceeded"), FailureKind::RateLimited);
  EXPECT_EQ(classifyFailure(404, ""), FailureKind::NotFound);
  EXPECT_EQ(classifyFailure(429, ""), FailureKind::RateLimited);
  EXPECT_EQ(classifyFailure(500, ""), FailureKind::Server);
  EXPECT_EQ(classifyFailure(503, ""), FailureKind::Server);
  EXPECT_EQ(classifyFailure(0, "Host not found"), FailureKind::Network);
  EXPECT_EQ(classifyFailure(0, ""), FailureKind::None);
  EXPECT_EQ(classifyFailure(400, "bad request"), FailureKind::Other);
}

TEST(SyncHealth, EveryKindHasTextInBothLanguages) {
  for(const FailureKind k : {FailureKind::Auth,
                             FailureKind::Forbidden,
                             FailureKind::NotFound,
                             FailureKind::RateLimited,
                             FailureKind::Server,
                             FailureKind::Network,
                             FailureKind::Other}) {
    EXPECT_FALSE(failureText(k, false).isEmpty());
    EXPECT_FALSE(failureText(k, true).isEmpty());
    EXPECT_NE(failureText(k, false), failureText(k, true));
  }
  EXPECT_TRUE(failureText(FailureKind::None, false).isEmpty());
}

TEST(SyncHealth, RelativeAge) {
  EXPECT_TRUE(relativeAge(QDateTime(), fixedNow(), false).isEmpty());
  EXPECT_EQ(relativeAge(fixedNow().addSecs(-10), fixedNow(), false), QStringLiteral("just now"));
  EXPECT_EQ(relativeAge(fixedNow().addSecs(-5LL * 60), fixedNow(), false), QStringLiteral("5 min ago"));
  EXPECT_EQ(relativeAge(fixedNow().addSecs(-3LL * 3600), fixedNow(), true), QStringLiteral("3 ч назад"));
  EXPECT_EQ(relativeAge(fixedNow().addDays(-2), fixedNow(), false), QStringLiteral("2 d ago"));
  // A clock that went backwards reads as "just now", not a negative age.
  EXPECT_EQ(relativeAge(fixedNow().addSecs(600), fixedNow(), false), QStringLiteral("just now"));
}

TEST(SyncHealth, Expiry) {
  EXPECT_TRUE(expiryText(QDateTime(), fixedNow(), false).isEmpty());
  EXPECT_EQ(expiryText(fixedNow().addSecs(-1), fixedNow(), false), QStringLiteral("the token has expired"));
  EXPECT_EQ(expiryText(fixedNow().addSecs(40LL * 60), fixedNow(), false), QStringLiteral("token expires in 40 min"));
  EXPECT_EQ(expiryText(fixedNow().addSecs(5LL * 3600), fixedNow(), true), QStringLiteral("токен истекает через 5 ч"));
  EXPECT_EQ(expiryText(fixedNow().addDays(30), fixedNow(), false), QStringLiteral("token expires in 30 d"));
}

TEST(SyncHealth, FailureIsCurrentUntilASuccess) {
  ProviderHealth h;
  EXPECT_FALSE(h.failing());
  h.recordFailure(fixedNow(), 401, QStringLiteral("HTTP 401"));
  EXPECT_TRUE(h.failing());
  EXPECT_EQ(h.lastFailure, FailureKind::Auth);
  h.recordOk(fixedNow().addSecs(60), 12);
  EXPECT_FALSE(h.failing());
  EXPECT_EQ(h.lastItems, 12);
  // A failure with no status and no text still counts as a failure.
  h.recordFailure(fixedNow().addSecs(120), 0, QString());
  EXPECT_TRUE(h.failing());
  EXPECT_EQ(h.lastFailure, FailureKind::Other);
}
