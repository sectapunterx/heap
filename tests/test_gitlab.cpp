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

// ── HEAP-117: the identity and context a card needs ──

TEST(GitlabParse, ParsesAssigneeAuthorDueTypeProjectMilestoneAndComments) {
  const QByteArray json = R"([
    {
      "iid": 42,
      "web_url": "https://gitlab.com/acme/app/-/issues/42",
      "title": "Fix login",
      "state": "opened",
      "labels": [],
      "updated_at": "2026-07-01T10:00:00.000Z",
      "created_at": "2026-06-20T09:00:00.000Z",
      "due_date": "2026-08-15",
      "user_notes_count": 3,
      "issue_type": "incident",
      "references": {"full": "acme/app#42"},
      "milestone": {"title": "Sprint 12"},
      "author": {"username": "reporter1"},
      "assignees": [{"username": "dev1"}, {"username": "dev2"}]
    }
  ])";
  const QVector<ExternalTask> tasks = parseGitlabIssues(json);
  ASSERT_EQ(tasks.size(), 1);
  const ExternalTask& t = tasks[0];
  EXPECT_EQ(t.assignee, QString("dev1, dev2"));
  EXPECT_EQ(t.author, QString("reporter1"));
  EXPECT_EQ(t.commentCount, 3);
  EXPECT_EQ(t.issueType, QString("incident"));
  EXPECT_EQ(t.project, QString("acme/app"));
  EXPECT_EQ(t.milestone, QString("Sprint 12"));
  EXPECT_TRUE(t.createdAt.isValid());
  // A GitLab due date is a day, not an instant.
  ASSERT_TRUE(t.dueAt.isValid());
  EXPECT_EQ(t.dueAt.date(), QDate(2026, 8, 15));
  EXPECT_EQ(t.dueAt.time(), QTime(0, 0));
  EXPECT_FALSE(t.dueHasTime);
}

TEST(GitlabParse, ProjectFallsBackToWebUrlWhenReferencesMissing) {
  const QByteArray json = R"([
    {"iid": 5, "web_url": "https://gitlab.example.com/group/sub/app/-/issues/5",
     "title": "t", "state": "opened", "labels": []}])";
  const QVector<ExternalTask> tasks = parseGitlabIssues(json);
  ASSERT_EQ(tasks.size(), 1);
  EXPECT_EQ(tasks[0].project, QString("group/sub/app"));
}

TEST(GitlabParse, LabelsAcceptStringsAndDetailObjects) {
  // with_labels_details=true turns the array into objects; an older GitLab (or
  // a list requested without the flag) still sends plain strings.
  const QByteArray detailed = R"([
    {"iid": 1, "web_url": "u", "title": "t", "state": "opened",
     "labels": [{"name": "backend", "color": "#428BCA"}, {"name": "priority::high", "color": "#FF0000"}]}])";
  const QVector<ExternalTask> tasks = parseGitlabIssues(detailed);
  ASSERT_EQ(tasks.size(), 1);
  ASSERT_EQ(tasks[0].labels.size(), 2);
  EXPECT_EQ(tasks[0].labels[0], QString("backend"));
  EXPECT_EQ(tasks[0].labelColors.value(QString("backend")), QString("#428BCA"));
  // The scoped priority label still drives the priority column.
  EXPECT_EQ(tasks[0].priority, QString("high"));

  const QByteArray plain = R"([{"iid": 1, "web_url": "u", "title": "t", "state": "opened", "labels": ["backend"]}])";
  const QVector<ExternalTask> plainTasks = parseGitlabIssues(plain);
  ASSERT_EQ(plainTasks.size(), 1);
  ASSERT_EQ(plainTasks[0].labels.size(), 1);
  EXPECT_TRUE(plainTasks[0].labelColors.isEmpty());
}

TEST(GitlabPushState, MapsColumnToStateEvent) {
  EXPECT_EQ(gitlabStateEventForColumn("done"), QString("close"));
  EXPECT_EQ(gitlabStateEventForColumn("todo"), QString("reopen"));
  EXPECT_EQ(gitlabStateEventForColumn("prog"), QString("reopen"));
  EXPECT_EQ(gitlabStateEventForColumn(""), QString("reopen"));
}
