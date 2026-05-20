#include <gtest/gtest.h>

#include "git/BranchTaskMatcher.h"

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
    // Explicit "LTE-123" no longer matches Rule 1 (RAN-only).
    // Rule 2 (single-prefix fallback) kicks in: digit run "123" preceded by
    // '-' is canonicalized with the sole registered prefix.
    auto r2 = m.extract("fix/LTE-123");
    EXPECT_TRUE(r2.matched);
    EXPECT_EQ(r2.taskId, QString("RAN-123"));
    auto r3 = m.extract("fix/ran-555");
    EXPECT_TRUE(r3.matched);
    EXPECT_EQ(r3.taskId, QString("RAN-555"));
}
