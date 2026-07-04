#include "integrations/GitlabProvider.h"

#include <gtest/gtest.h>

using heap::integrations::ExternalTask;
using heap::integrations::gitlabStateEventForColumn;
using heap::integrations::parseGitlabIssues;

TEST(GitlabParse, ParsesIssuesAndLabels) {
  const QByteArray json = R"([
    {
      "iid": 42,
      "web_url": "https://gitlab.com/acme/app/-/issues/42",
      "title": "Fix login",
      "description": "steps to repro",
      "state": "opened",
      "labels": ["backend", "priority::high"],
      "updated_at": "2026-07-01T10:00:00.000Z"
    },
    {
      "iid": 7,
      "web_url": "https://gitlab.com/acme/app/-/issues/7",
      "title": "Old bug",
      "description": "",
      "state": "closed",
      "labels": [],
      "updated_at": "2026-06-01T08:00:00.000Z"
    }
  ])";

  const QVector<ExternalTask> tasks = parseGitlabIssues(json);
  ASSERT_EQ(tasks.size(), 2);

  EXPECT_EQ(tasks[0].providerId, QString("gitlab"));
  EXPECT_EQ(tasks[0].externalId, QString("42"));  // iid, not internal id
  EXPECT_EQ(tasks[0].url, QString("https://gitlab.com/acme/app/-/issues/42"));
  EXPECT_EQ(tasks[0].title, QString("Fix login"));
  EXPECT_EQ(tasks[0].body, QString("steps to repro"));
  EXPECT_EQ(tasks[0].status, QString("opened"));
  ASSERT_EQ(tasks[0].labels.size(), 2);
  EXPECT_EQ(tasks[0].priority, QString("high"));  // from "priority::high" scoped label

  EXPECT_EQ(tasks[1].externalId, QString("7"));
  EXPECT_EQ(tasks[1].status, QString("closed"));
  EXPECT_TRUE(tasks[1].priority.isEmpty());
}

TEST(GitlabParse, HandlesEmptyAndInvalid) {
  EXPECT_TRUE(parseGitlabIssues(QByteArray()).isEmpty());
  EXPECT_TRUE(parseGitlabIssues("{}").isEmpty());  // object, not array
  EXPECT_TRUE(parseGitlabIssues("garbage").isEmpty());
  EXPECT_TRUE(parseGitlabIssues("[]").isEmpty());
}

TEST(GitlabPushState, MapsColumnToStateEvent) {
  EXPECT_EQ(gitlabStateEventForColumn("done"), QString("close"));
  EXPECT_EQ(gitlabStateEventForColumn("todo"), QString("reopen"));
  EXPECT_EQ(gitlabStateEventForColumn("prog"), QString("reopen"));
  EXPECT_EQ(gitlabStateEventForColumn(""), QString("reopen"));
}
