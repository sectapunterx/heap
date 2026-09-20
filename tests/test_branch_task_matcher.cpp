#include "git/BranchTaskMatcher.h"

#include <gtest/gtest.h>

using heap::git::BranchTaskMatcher;

TEST(Matcher, PrefixedExplicit) {
  BranchTaskMatcher m({"LTE"});
  auto r = m.extract("feature/LTE-2398-retx");
  EXPECT_TRUE(r.matched);
  EXPECT_EQ(r.taskId, QString("LTE-2398"));
  EXPECT_EQ(r.matchedPrefix, QString("LTE"));
  EXPECT_EQ(r.numericPart, 2398);
}

TEST(Matcher, PrefixCaseInsensitiveCanonicalized) {
  BranchTaskMatcher m({"LTE"});
  auto r = m.extract("fix/lte-2398");
  EXPECT_TRUE(r.matched);
  EXPECT_EQ(r.taskId, QString("LTE-2398"));
}

TEST(Matcher, NumericOnlySinglePrefix) {
  BranchTaskMatcher m({"LTE"});
  auto r = m.extract("fix/harq-retx-2398");
  EXPECT_TRUE(r.matched);
  EXPECT_EQ(r.taskId, QString("LTE-2398"));
}

TEST(Matcher, NumericOnlyMultiPrefixAmbiguous) {
  BranchTaskMatcher m({"LTE", "RAN"});
  auto r = m.extract("fix/harq-retx-2398");
  EXPECT_FALSE(r.matched);
}

TEST(Matcher, MultiPrefixExplicitWins) {
  BranchTaskMatcher m({"LTE", "RAN"});
  auto r = m.extract("feat/RAN-77-cleanup");
  EXPECT_TRUE(r.matched);
  EXPECT_EQ(r.taskId, QString("RAN-77"));
}

TEST(Matcher, DetachedHeadNotMatched) {
  BranchTaskMatcher m({"LTE"});
  EXPECT_FALSE(m.extract("(detached HEAD)").matched);
}

TEST(Matcher, EmptyPrefixesDisabled) {
  BranchTaskMatcher m({});
  EXPECT_FALSE(m.extract("LTE-1234").matched);
}

TEST(Matcher, IgnoreNumericTooShortOrLong) {
  BranchTaskMatcher m({"LTE"});
  EXPECT_FALSE(m.extract("fix/12").matched);
  EXPECT_FALSE(m.extract("fix/12345678").matched);
}

TEST(Matcher, BranchAtStartWithoutSeparator) {
  BranchTaskMatcher m({"LTE"});
  auto r = m.extract("LTE-1234");
  EXPECT_TRUE(r.matched);
  EXPECT_EQ(r.taskId, QString("LTE-1234"));
}

TEST(Matcher, EmptyBranch) {
  BranchTaskMatcher m({"LTE"});
  EXPECT_FALSE(m.extract("").matched);
}

TEST(Matcher, SetPrefixesUpdatesMatching) {
  BranchTaskMatcher m({"LTE"});
  auto r1 = m.extract("fix/LTE-123");
  EXPECT_TRUE(r1.matched);
  EXPECT_EQ(r1.taskId, QString("LTE-123"));
  m.setPrefixes({"RAN"});
  // "LTE-123" no longer matches Rule 1 (RAN-only), and it must NOT fall
  // through to Rule 2 either. It used to: the digit run "123" was
  // canonicalised with the sole registered prefix, so a branch that plainly
  // said LTE came back as RAN-123 — a confident answer about the wrong task.
  // A branch naming a key this matcher does not know is a no-match.
  auto r2 = m.extract("fix/LTE-123");
  EXPECT_FALSE(r2.matched) << "a branch naming an unregistered key must not resolve to the local prefix";
  auto r3 = m.extract("fix/ran-555");
  EXPECT_TRUE(r3.matched);
  EXPECT_EQ(r3.taskId, QString("RAN-555"));
}

// The bug this suppression exists for, stated plainly: a Jira branch whose
// project is not registered here used to focus whichever local task happened
// to share its number.
TEST(Matcher, AForeignProjectKeyDoesNotResolveToTheLocalPrefix) {
  BranchTaskMatcher m({"LTE"});
  EXPECT_FALSE(m.extract("feature/PROJ-123").matched);
  EXPECT_FALSE(m.extract("bugfix/ACME-4711-crash").matched);
  // Registering the key is what makes it resolve — and to itself.
  m.setPrefixes({"LTE", "PROJ"});
  auto r = m.extract("feature/PROJ-123");
  EXPECT_TRUE(r.matched);
  EXPECT_EQ(r.taskId, QString("PROJ-123"));
}

// …while a descriptive branch that merely ends in digits still resolves, which
// is the whole point of the bare-digit fallback. The two are told apart by
// case: a tracker key is written in capitals, prose is not.
TEST(Matcher, ALowercaseWordBeforeDigitsIsStillProseNotAKey) {
  BranchTaskMatcher m({"LTE"});
  auto r = m.extract("fix/harq-retx-2398");
  EXPECT_TRUE(r.matched);
  EXPECT_EQ(r.taskId, QString("LTE-2398"));
}
