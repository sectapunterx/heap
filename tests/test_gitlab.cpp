#include "integrations/GitlabProvider.h"

#include <QJsonArray>

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

// Audit C8: a confidential issue is marked on the card.
TEST(GitlabProvider, ParseGitlabIssues_ConfidentialIssue_CarriesAMarkLabel) {
  const QByteArray json = R"json([{"iid":3,"title":"secret","state":"opened","confidential":true,"labels":["bug"]}])json";
  const auto issues = heap::integrations::parseGitlabIssues(json);
  ASSERT_EQ(issues.size(), 1);
  EXPECT_EQ(issues.at(0).labels.first(), QStringLiteral("confidential"));
  EXPECT_TRUE(issues.at(0).labels.contains(QStringLiteral("bug")));
  EXPECT_EQ(issues.at(0).labelColors.value(QStringLiteral("confidential")), QStringLiteral("#e6624c"));
}

// ── Merge requests (APP-242) ──────────────────────────────────────────────

TEST(GitlabMergeRequests, EveryStageAndItsFacts) {
  const QByteArray json = R"([
    {"iid": 17, "web_url": "https://gitlab.com/acme/app/-/merge_requests/17", "title": "Login fix",
     "description": "Closes #12 and fixes acme/web#3", "state": "opened", "draft": false,
     "source_branch": "fix/login", "target_branch": "main", "detailed_merge_status": "not_approved",
     "has_conflicts": true, "references": {"full": "acme/app!17"},
     "author": {"username": "ann"}, "assignees": [{"username": "me"}], "reviewers": [{"username": "bob"}, {"username": "me"}],
     "user_notes_count": 4, "updated_at": "2026-10-08T10:00:00Z", "labels": ["backend"]},
    {"iid": 18, "web_url": "https://gitlab.com/acme/app/-/merge_requests/18", "title": "WIP", "state": "opened", "draft": true},
    {"iid": 19, "web_url": "https://gitlab.com/acme/app/-/merge_requests/19", "title": "Old WIP", "state": "opened", "work_in_progress": true},
    {"iid": 20, "web_url": "https://gitlab.com/acme/app/-/merge_requests/20", "title": "Shipped", "state": "merged",
     "head_pipeline": {"status": "success"}},
    {"iid": 21, "web_url": "https://gitlab.com/acme/app/-/merge_requests/21", "title": "Dropped", "state": "closed"},
    {"iid": 22, "web_url": "https://gitlab.com/acme/app/-/merge_requests/22", "title": "Locked", "state": "locked"},
    {"title": "no iid"}
  ])";
  const QVector<ExternalTask> mrs = heap::integrations::parseGitlabMergeRequests(json);
  ASSERT_EQ(mrs.size(), 6);
  const ExternalTask& a = mrs.at(0);
  EXPECT_EQ(a.externalId, QStringLiteral("!17"));
  EXPECT_EQ(a.status, QStringLiteral("MR open"));
  EXPECT_EQ(a.issueType, QStringLiteral("MR"));
  EXPECT_EQ(a.project, QStringLiteral("acme/app"));
  EXPECT_EQ(a.author, QStringLiteral("ann"));
  EXPECT_EQ(a.assignee, QStringLiteral("me"));
  EXPECT_EQ(a.commentCount, 4);
  EXPECT_EQ(a.labels, QStringList{QStringLiteral("backend")});
  EXPECT_EQ(a.details.value(QStringLiteral("kind")).toString(), QStringLiteral("mr"));
  EXPECT_EQ(a.details.value(QStringLiteral("state")).toString(), QStringLiteral("opened"));
  EXPECT_EQ(a.details.value(QStringLiteral("sourceBranch")).toString(), QStringLiteral("fix/login"));
  EXPECT_EQ(a.details.value(QStringLiteral("targetBranch")).toString(), QStringLiteral("main"));
  EXPECT_EQ(a.details.value(QStringLiteral("mergeStatus")).toString(), QStringLiteral("not_approved"));
  EXPECT_TRUE(a.details.value(QStringLiteral("conflicts")).toBool());
  EXPECT_EQ(a.details.value(QStringLiteral("reviewers")).toArray().size(), 2);
  EXPECT_EQ(a.details.value(QStringLiteral("closes")).toArray(), (QJsonArray{QStringLiteral("#12"), QStringLiteral("acme/web#3")}));

  EXPECT_EQ(mrs.at(1).status, QStringLiteral("MR draft"));
  EXPECT_TRUE(mrs.at(1).details.value(QStringLiteral("draft")).toBool());
  EXPECT_EQ(mrs.at(2).status, QStringLiteral("MR draft"));
  EXPECT_EQ(mrs.at(3).status, QStringLiteral("MR merged"));
  EXPECT_EQ(mrs.at(3).details.value(QStringLiteral("pipeline")).toString(), QStringLiteral("success"));
  EXPECT_EQ(mrs.at(4).status, QStringLiteral("MR closed"));
  EXPECT_EQ(mrs.at(5).status, QStringLiteral("MR closed"));
  EXPECT_EQ(mrs.at(5).details.value(QStringLiteral("state")).toString(), QStringLiteral("closed"));
  // The project comes from the web URL when references are missing.
  EXPECT_EQ(mrs.at(1).project, QStringLiteral("acme/app"));
}

TEST(GitlabMergeRequests, AnIssueAndAMergeRequestWithTheSameNumberStayApart) {
  const QVector<ExternalTask> issues =
      parseGitlabIssues(R"([{"iid": 17, "web_url": "https://gitlab.com/acme/app/-/issues/17", "title": "i", "state": "opened"}])");
  const QVector<ExternalTask> mrs = heap::integrations::parseGitlabMergeRequests(
      R"([{"iid": 17, "web_url": "https://gitlab.com/acme/app/-/merge_requests/17", "title": "m", "state": "opened"}])");
  ASSERT_EQ(issues.size(), 1);
  ASSERT_EQ(mrs.size(), 1);
  EXPECT_NE(issues.at(0).externalId, mrs.at(0).externalId);
  EXPECT_NE(issues.at(0).url, mrs.at(0).url);
  EXPECT_TRUE(issues.at(0).details.isEmpty());
}

TEST(GitlabMergeRequests, HandlesEmptyAndInvalid) {
  EXPECT_TRUE(heap::integrations::parseGitlabMergeRequests("[]").isEmpty());
  EXPECT_TRUE(heap::integrations::parseGitlabMergeRequests("{}").isEmpty());
  EXPECT_TRUE(heap::integrations::parseGitlabMergeRequests("nope").isEmpty());
}
