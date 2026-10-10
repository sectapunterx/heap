// Unit tests for the pure GitHub-sync helpers (HEAP-74): JSON→ExternalTask
// parsing and the heap-column→issue-state push mapping. No network.

#include "integrations/GithubProvider.h"

#include <QJsonArray>

#include <gtest/gtest.h>

using heap::integrations::ExternalTask;
using heap::integrations::githubStateForColumn;
using heap::integrations::parseGithubIssues;

TEST(GithubParse, ParsesIssuesAndSkipsPullRequests) {
  const QByteArray json = R"([
    {"number": 12, "html_url": "https://github.com/o/r/issues/12", "title": "Fix crash",
     "body": "steps to repro", "state": "open", "updated_at": "2026-01-02T03:04:05Z",
     "labels": [{"name": "bug"}, {"name": "priority: high"}]},
    {"number": 13, "title": "a pull request", "state": "open", "pull_request": {"url": "x"}},
    {"number": 14, "html_url": "u", "title": "Closed one", "state": "closed",
     "updated_at": "2026-01-03T00:00:00Z", "labels": []}
  ])";
  const QVector<ExternalTask> tasks = parseGithubIssues(json);

  ASSERT_EQ(tasks.size(), 2);  // the pull request is skipped
  EXPECT_EQ(tasks[0].providerId, QStringLiteral("github"));
  EXPECT_EQ(tasks[0].externalId, QStringLiteral("12"));
  EXPECT_EQ(tasks[0].url, QStringLiteral("https://github.com/o/r/issues/12"));
  EXPECT_EQ(tasks[0].title, QStringLiteral("Fix crash"));
  EXPECT_EQ(tasks[0].body, QStringLiteral("steps to repro"));
  EXPECT_EQ(tasks[0].status, QStringLiteral("open"));
  EXPECT_EQ(tasks[0].priority, QStringLiteral("high"));  // from "priority: high" label
  ASSERT_EQ(tasks[0].labels.size(), 2);
  EXPECT_TRUE(tasks[0].updatedAt.isValid());

  EXPECT_EQ(tasks[1].externalId, QStringLiteral("14"));
  EXPECT_EQ(tasks[1].status, QStringLiteral("closed"));
  EXPECT_TRUE(tasks[1].priority.isEmpty());
}

TEST(GithubParse, HandlesEmptyAndInvalid) {
  EXPECT_TRUE(parseGithubIssues(QByteArray()).isEmpty());
  EXPECT_TRUE(parseGithubIssues("{}").isEmpty());  // object, not an array
  EXPECT_TRUE(parseGithubIssues("not json").isEmpty());
  EXPECT_TRUE(parseGithubIssues("[]").isEmpty());
}

// ── HEAP-117: the identity and context a card needs ──

TEST(GithubParse, ParsesAssigneeAuthorMilestoneCommentsAndLabelColors) {
  const QByteArray json = R"([
    {"number": 12, "html_url": "https://github.com/acme/web/issues/12", "title": "Fix crash",
     "state": "open", "updated_at": "2026-01-02T03:04:05Z", "created_at": "2025-12-01T10:00:00Z",
     "comments": 4, "type": {"name": "Bug"},
     "user": {"login": "reporter1"},
     "assignees": [{"login": "dev1"}, {"login": "dev2"}],
     "milestone": {"title": "v2.0"},
     "repository_url": "https://api.github.com/repos/acme/web",
     "labels": [{"name": "bug", "color": "d73a4a"}, {"name": "ci", "color": ""}]}
  ])";
  const QVector<ExternalTask> tasks = parseGithubIssues(json);
  ASSERT_EQ(tasks.size(), 1);
  const ExternalTask& t = tasks[0];
  EXPECT_EQ(t.assignee, QStringLiteral("dev1, dev2"));
  EXPECT_EQ(t.author, QStringLiteral("reporter1"));
  EXPECT_EQ(t.commentCount, 4);
  EXPECT_EQ(t.issueType, QStringLiteral("Bug"));
  EXPECT_EQ(t.milestone, QStringLiteral("v2.0"));
  EXPECT_EQ(t.project, QStringLiteral("acme/web"));
  EXPECT_TRUE(t.createdAt.isValid());
  // GitHub sends the chip colour without a leading '#'.
  EXPECT_EQ(t.labelColors.value(QStringLiteral("bug")), QStringLiteral("#d73a4a"));
  EXPECT_FALSE(t.labelColors.contains(QStringLiteral("ci")));
  // Nothing in the payload is a per-issue due date.
  EXPECT_FALSE(t.dueAt.isValid());
  // crossProject is stamped by the provider, not the parser.
  EXPECT_FALSE(t.crossProject);
}

TEST(GithubParse, FallsBackToSingularAssignee) {
  const QByteArray json = R"([
    {"number": 1, "title": "t", "state": "open", "assignee": {"login": "solo"}, "assignees": []}])";
  const QVector<ExternalTask> tasks = parseGithubIssues(json);
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].assignee, QStringLiteral("solo"));
}

TEST(GithubParse, MissingOptionalFieldsStayDefault) {
  const QByteArray json = R"([{"number": 9, "title": "bare", "state": "open"}])";
  const QVector<ExternalTask> tasks = parseGithubIssues(json);
  ASSERT_EQ(tasks.size(), 1);
  const ExternalTask& t = tasks[0];
  EXPECT_TRUE(t.assignee.isEmpty());
  EXPECT_TRUE(t.author.isEmpty());
  EXPECT_TRUE(t.project.isEmpty());
  EXPECT_TRUE(t.milestone.isEmpty());
  EXPECT_TRUE(t.issueType.isEmpty());
  EXPECT_TRUE(t.labelColors.isEmpty());
  EXPECT_FALSE(t.createdAt.isValid());
  // "the provider did not say", which is not the same as "no comments".
  EXPECT_EQ(t.commentCount, -1);
}

TEST(GithubParse, RejectsAProjectThatIsNotAPlainPath) {
  // repository_url is interpolated into task ids and comment URLs later on.
  const QByteArray json = R"([
    {"number": 1, "title": "t", "state": "open",
     "repository_url": "https://api.github.com/repos/acme/web/../../evil"}])";
  const QVector<ExternalTask> tasks = parseGithubIssues(json);
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_TRUE(tasks[0].project.isEmpty());
}

TEST(GithubPushState, MapsColumnToIssueState) {
  EXPECT_EQ(githubStateForColumn(QStringLiteral("done")), QStringLiteral("closed"));
  EXPECT_EQ(githubStateForColumn(QStringLiteral("todo")), QStringLiteral("open"));
  EXPECT_EQ(githubStateForColumn(QStringLiteral("prog")), QStringLiteral("open"));
  EXPECT_EQ(githubStateForColumn(QStringLiteral("review")), QStringLiteral("open"));
  EXPECT_EQ(githubStateForColumn(QString()), QStringLiteral("open"));
}

// ── Pull requests (APP-242) ───────────────────────────────────────────────

TEST(GithubPulls, SearchItemsInEveryStage) {
  const QByteArray json = R"({"total_count": 5, "items": [
    {"number": 7, "html_url": "https://github.com/o/r/pull/7", "title": "Feature", "body": "Fixes #3",
     "state": "open", "draft": false, "repository_url": "https://api.github.com/repos/o/r",
     "pull_request": {"merged_at": null}, "user": {"login": "ann"}, "comments": 2},
    {"number": 8, "html_url": "https://github.com/o/r/pull/8", "title": "Draft", "state": "open", "draft": true,
     "pull_request": {}},
    {"number": 9, "html_url": "https://github.com/o/r/pull/9", "title": "Merged", "state": "closed",
     "pull_request": {"merged_at": "2026-10-08T09:00:00Z"}},
    {"number": 10, "html_url": "https://github.com/o/r/pull/10", "title": "Closed", "state": "closed",
     "pull_request": {"merged_at": null}},
    {"number": 11, "html_url": "https://github.com/o/r/issues/11", "title": "An issue", "state": "open"}
  ]})";
  const QVector<ExternalTask> prs = heap::integrations::parseGithubPulls(json);
  ASSERT_EQ(prs.size(), 4);  // the issue is not one
  EXPECT_EQ(prs.at(0).externalId, QStringLiteral("7"));
  EXPECT_EQ(prs.at(0).status, QStringLiteral("PR open"));
  EXPECT_EQ(prs.at(0).issueType, QStringLiteral("PR"));
  EXPECT_EQ(prs.at(0).project, QStringLiteral("o/r"));
  EXPECT_EQ(prs.at(0).author, QStringLiteral("ann"));
  EXPECT_EQ(prs.at(0).details.value(QStringLiteral("kind")).toString(), QStringLiteral("pr"));
  EXPECT_EQ(prs.at(0).details.value(QStringLiteral("closes")).toArray(), QJsonArray{QStringLiteral("#3")});
  EXPECT_EQ(prs.at(1).status, QStringLiteral("PR draft"));
  EXPECT_EQ(prs.at(2).status, QStringLiteral("PR merged"));
  EXPECT_EQ(prs.at(2).details.value(QStringLiteral("state")).toString(), QStringLiteral("merged"));
  EXPECT_EQ(prs.at(3).status, QStringLiteral("PR closed"));
}

TEST(GithubPulls, APullsListCarriesTheBranches) {
  const QByteArray json = R"([{"number": 5, "html_url": "https://github.com/o/r/pull/5", "title": "x", "state": "open",
    "merged_at": null, "head": {"ref": "feature/x"}, "base": {"ref": "main", "repo": {"full_name": "o/r"}},
    "requested_reviewers": [{"login": "me"}], "mergeable_state": "dirty"}])";
  const QVector<ExternalTask> prs = heap::integrations::parseGithubPulls(json);
  ASSERT_EQ(prs.size(), 1);
  EXPECT_EQ(prs.at(0).project, QStringLiteral("o/r"));
  EXPECT_EQ(prs.at(0).details.value(QStringLiteral("sourceBranch")).toString(), QStringLiteral("feature/x"));
  EXPECT_EQ(prs.at(0).details.value(QStringLiteral("targetBranch")).toString(), QStringLiteral("main"));
  EXPECT_EQ(prs.at(0).details.value(QStringLiteral("reviewers")).toArray(), QJsonArray{QStringLiteral("me")});
  EXPECT_EQ(prs.at(0).details.value(QStringLiteral("mergeStatus")).toString(), QStringLiteral("dirty"));
  EXPECT_TRUE(heap::integrations::parseGithubPulls("garbage").isEmpty());
}
