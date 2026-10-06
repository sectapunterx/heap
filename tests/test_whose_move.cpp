// Whose move it is on a PR (APP-156): parsing what gh / glab print, and the
// pure rule that reads the facts.

#include "git/PrFacts.h"

#include <QJsonArray>
#include <QJsonObject>

#include <gtest/gtest.h>

using heap::git::Move;
using heap::git::parseLogin;
using heap::git::parsePrJson;
using heap::git::PrInfo;
using heap::git::whoseMove;

namespace {

PrInfo openPr(const QString& author) {
  PrInfo pr;
  pr.state = QStringLiteral("open");
  pr.number = 7;
  pr.author = author;
  return pr;
}

QString me() {
  return QStringLiteral("ada");
}

}  // namespace

TEST(PrParse, GhFullAnswer) {
  const QByteArray raw = R"({
    "state": "OPEN", "number": 42, "url": "https://github.com/o/r/pull/42", "title": "Fix it",
    "isDraft": false,
    "statusCheckRollup": [{"status": "COMPLETED", "conclusion": "SUCCESS"}],
    "author": {"login": "ada"},
    "reviewDecision": "REVIEW_REQUIRED",
    "reviewRequests": [{"__typename": "User", "login": "bob"}, {"__typename": "Team", "slug": "core", "name": "Core"}],
    "mergeable": "MERGEABLE"
  })";
  const PrInfo pr = parsePrJson(raw, /*glab=*/false);
  EXPECT_EQ(pr.state, QStringLiteral("open"));
  EXPECT_EQ(pr.number, 42);
  EXPECT_EQ(pr.title, QStringLiteral("Fix it"));
  EXPECT_EQ(pr.checks, QStringLiteral("passing"));
  EXPECT_EQ(pr.author, QStringLiteral("ada"));
  EXPECT_EQ(pr.reviewDecision, QStringLiteral("REVIEW_REQUIRED"));
  EXPECT_EQ(pr.reviewRequests, (QStringList{QStringLiteral("bob"), QStringLiteral("core")}));
  EXPECT_EQ(pr.mergeable, QStringLiteral("MERGEABLE"));
  // Parsing never decides whose move it is.
  EXPECT_TRUE(pr.move.isEmpty());
}

TEST(PrParse, GhOlderAnswerWithoutReviewFieldsStillParses) {
  const PrInfo pr = parsePrJson(R"({"state":"MERGED","number":3,"url":"u","title":"t","isDraft":false,"statusCheckRollup":[]})", false);
  EXPECT_EQ(pr.state, QStringLiteral("merged"));
  EXPECT_EQ(pr.number, 3);
  EXPECT_TRUE(pr.checks.isEmpty());
  EXPECT_TRUE(pr.author.isEmpty());
  EXPECT_TRUE(pr.reviewRequests.isEmpty());
}

TEST(PrParse, GarbageIsNoPr) {
  EXPECT_TRUE(parsePrJson("no pull requests found for branch \"x\"", false).state.isEmpty());
  EXPECT_TRUE(parsePrJson("[]", true).state.isEmpty());
}

TEST(PrParse, GlabMapsOntoGithubVocabulary) {
  const QByteArray raw = R"({
    "iid": 12, "state": "opened", "web_url": "https://gitlab.com/o/r/-/merge_requests/12", "title": "MR",
    "draft": false, "author": {"username": "ada"}, "reviewers": [{"username": "bob"}],
    "head_pipeline": {"status": "running"}, "detailed_merge_status": "not_approved", "has_conflicts": false
  })";
  const PrInfo pr = parsePrJson(raw, /*glab=*/true);
  EXPECT_EQ(pr.state, QStringLiteral("open"));
  EXPECT_EQ(pr.number, 12);
  EXPECT_EQ(pr.url, QStringLiteral("https://gitlab.com/o/r/-/merge_requests/12"));
  EXPECT_EQ(pr.author, QStringLiteral("ada"));
  EXPECT_EQ(pr.reviewRequests, QStringList{QStringLiteral("bob")});
  EXPECT_EQ(pr.checks, QStringLiteral("pending"));
  EXPECT_EQ(pr.reviewDecision, QStringLiteral("REVIEW_REQUIRED"));
  EXPECT_EQ(pr.mergeable, QStringLiteral("UNKNOWN"));
}

TEST(PrParse, GlabConflictsAndFailedPipeline) {
  const PrInfo pr = parsePrJson(
      R"({"iid":1,"state":"opened","has_conflicts":true,"pipeline":{"status":"failed"},"detailed_merge_status":"conflict"})", true);
  EXPECT_EQ(pr.mergeable, QStringLiteral("CONFLICTING"));
  EXPECT_EQ(pr.checks, QStringLiteral("failing"));
}

TEST(PrParse, Login) {
  EXPECT_EQ(parseLogin("ada\n", false), QStringLiteral("ada"));
  EXPECT_TRUE(parseLogin("", false).isEmpty());
  EXPECT_TRUE(parseLogin("gh: To get started with GitHub CLI, please run:  gh auth login", false).isEmpty());
  EXPECT_EQ(parseLogin(R"({"id":1,"username":"ada"})", true), QStringLiteral("ada"));
  EXPECT_TRUE(parseLogin("not json", true).isEmpty());
}

TEST(PrParse, RollupChecks) {
  using heap::git::rollupChecks;
  EXPECT_TRUE(rollupChecks({}).isEmpty());
  const QJsonArray pending{QJsonObject{{"status", "IN_PROGRESS"}}, QJsonObject{{"status", "COMPLETED"}, {"conclusion", "SUCCESS"}}};
  EXPECT_EQ(rollupChecks(pending), QStringLiteral("pending"));
  const QJsonArray failing{QJsonObject{{"status", "IN_PROGRESS"}}, QJsonObject{{"state", "FAILURE"}}};
  EXPECT_EQ(rollupChecks(failing), QStringLiteral("failing"));
}

TEST(WhoseMove, ReviewRequestedFromMeIsMine) {
  PrInfo pr = openPr(QStringLiteral("bob"));
  pr.reviewRequests = {QStringLiteral("Ada")};  // logins compare case-insensitively
  const auto v = whoseMove(pr, me());
  EXPECT_EQ(v.move, Move::Mine);
  EXPECT_EQ(v.reason, QStringLiteral("reviewRequested"));
}

TEST(WhoseMove, SomeoneElsesPrIsNotMyBusiness) {
  PrInfo pr = openPr(QStringLiteral("bob"));
  pr.checks = QStringLiteral("failing");
  EXPECT_EQ(whoseMove(pr, me()).move, Move::None);
}

TEST(WhoseMove, UnknownLoginSaysNothing) {
  PrInfo pr = openPr(me());
  pr.checks = QStringLiteral("failing");
  EXPECT_EQ(whoseMove(pr, QString()).move, Move::None);
}

TEST(WhoseMove, MergedClosedAndDraftSayNothing) {
  PrInfo pr = openPr(me());
  pr.checks = QStringLiteral("failing");
  pr.state = QStringLiteral("merged");
  EXPECT_EQ(whoseMove(pr, me()).move, Move::None);
  pr.state = QStringLiteral("closed");
  EXPECT_EQ(whoseMove(pr, me()).move, Move::None);
  pr.state = QStringLiteral("open");
  pr.draft = true;
  EXPECT_EQ(whoseMove(pr, me()).move, Move::None);
}

TEST(WhoseMove, RedCiOnMyPrIsMine) {
  PrInfo pr = openPr(me());
  pr.checks = QStringLiteral("failing");
  pr.reviewDecision = QStringLiteral("APPROVED");
  const auto v = whoseMove(pr, me());
  EXPECT_EQ(v.move, Move::Mine);
  EXPECT_EQ(v.reason, QStringLiteral("ciFailing"));
}

TEST(WhoseMove, ChangesRequestedIsMine) {
  PrInfo pr = openPr(me());
  pr.reviewDecision = QStringLiteral("CHANGES_REQUESTED");
  pr.checks = QStringLiteral("pending");
  const auto v = whoseMove(pr, me());
  EXPECT_EQ(v.move, Move::Mine);
  EXPECT_EQ(v.reason, QStringLiteral("changesRequested"));
}

TEST(WhoseMove, ConflictIsMine) {
  PrInfo pr = openPr(me());
  pr.mergeable = QStringLiteral("CONFLICTING");
  const auto v = whoseMove(pr, me());
  EXPECT_EQ(v.move, Move::Mine);
  EXPECT_EQ(v.reason, QStringLiteral("conflicts"));
}

TEST(WhoseMove, RunningCiIsTheirs) {
  PrInfo pr = openPr(me());
  pr.checks = QStringLiteral("pending");
  pr.reviewDecision = QStringLiteral("APPROVED");
  pr.mergeable = QStringLiteral("MERGEABLE");
  const auto v = whoseMove(pr, me());
  EXPECT_EQ(v.move, Move::Theirs);
  EXPECT_EQ(v.reason, QStringLiteral("ciRunning"));
}

TEST(WhoseMove, AwaitingReviewIsTheirs) {
  PrInfo pr = openPr(me());
  pr.checks = QStringLiteral("passing");
  pr.reviewDecision = QStringLiteral("REVIEW_REQUIRED");
  pr.mergeable = QStringLiteral("MERGEABLE");
  auto v = whoseMove(pr, me());
  EXPECT_EQ(v.move, Move::Theirs);
  EXPECT_EQ(v.reason, QStringLiteral("awaitingReview"));
  // No branch protection, but a reviewer was asked: still waiting on them.
  pr.reviewDecision.clear();
  pr.reviewRequests = {QStringLiteral("bob")};
  v = whoseMove(pr, me());
  EXPECT_EQ(v.move, Move::Theirs);
}

TEST(WhoseMove, ApprovedAndMergeableIsMine) {
  PrInfo pr = openPr(me());
  pr.checks = QStringLiteral("passing");
  pr.reviewDecision = QStringLiteral("APPROVED");
  pr.mergeable = QStringLiteral("MERGEABLE");
  auto v = whoseMove(pr, me());
  EXPECT_EQ(v.move, Move::Mine);
  EXPECT_EQ(v.reason, QStringLiteral("readyToMerge"));
  // Mergeability not computed yet: nothing to say.
  pr.mergeable = QStringLiteral("UNKNOWN");
  EXPECT_EQ(whoseMove(pr, me()).move, Move::None);
}

TEST(WhoseMove, MoveNames) {
  EXPECT_EQ(heap::git::moveName(Move::Mine), QStringLiteral("mine"));
  EXPECT_EQ(heap::git::moveName(Move::Theirs), QStringLiteral("theirs"));
  EXPECT_TRUE(heap::git::moveName(Move::None).isEmpty());
}
