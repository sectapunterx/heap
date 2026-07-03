// Unit tests for the pure GitHub-sync helpers (HEAP-74): JSON→ExternalTask
// parsing and the heap-column→issue-state push mapping. No network.

#include "integrations/GithubProvider.h"

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

TEST(GithubPushState, MapsColumnToIssueState) {
  EXPECT_EQ(githubStateForColumn(QStringLiteral("done")), QStringLiteral("closed"));
  EXPECT_EQ(githubStateForColumn(QStringLiteral("todo")), QStringLiteral("open"));
  EXPECT_EQ(githubStateForColumn(QStringLiteral("prog")), QStringLiteral("open"));
  EXPECT_EQ(githubStateForColumn(QStringLiteral("review")), QStringLiteral("open"));
  EXPECT_EQ(githubStateForColumn(QString()), QStringLiteral("open"));
}
