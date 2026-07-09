// Direct coverage for the three QAbstractListModel subclasses in Models.cpp:
// role→field mapping in data(), upsert insert-vs-update, the mutation guards
// (setStatus/setArchived/stampStatusChange), setBlockedStuckIds range/union
// logic, the runtime git-info merge, remove/insert clamping, and the
// PersonModel/EventModel-specific ops (cycleState, todoCount, detachTask,
// setTaskId). Pure and headless — no AppController, no QApplication needed.

#include "Models.h"
#include "TaskDefer.h"

#include <QColor>
#include <QDate>
#include <QDateTime>
#include <QList>
#include <QSignalSpy>
#include <QVariantMap>
#include <QVector>

#include <gtest/gtest.h>

namespace {

Task mkTask(const QString& id) {
  Task t;
  t.id = id;
  t.title = id + QStringLiteral(" title");
  t.status = QStringLiteral("todo");
  t.priority = QStringLiteral("P2");
  return t;
}

Person mkPerson(const QString& id, const QString& state) {
  Person p;
  p.id = id;
  p.name = id;
  p.state = state;
  p.color = QColor(QStringLiteral("#112233"));
  return p;
}

}  // namespace

// ─── TaskModel::data role mapping ─────────────────────────────────────

TEST(TaskModelData, MapsEveryRole) {
  TaskModel m;
  Task t;
  t.id = QStringLiteral("T1");
  t.title = QStringLiteral("Fix");
  t.desc = QStringLiteral("d");
  t.priority = QStringLiteral("P1");
  t.status = QStringLiteral("prog");
  t.branch = QStringLiteral("feat/x");
  t.dueAt = QDateTime(QDate(2030, 1, 2), QTime(0, 0));
  t.scheduledAt = t.dueAt;
  t.archived = true;
  t.statusChangedAt = QDateTime(QDate(2030, 1, 2), QTime(9, 0));
  m.reset({t});

  const QModelIndex i = m.index(0, 0);
  EXPECT_EQ(m.data(i, TaskModel::IdRole).toString(), QString("T1"));
  EXPECT_EQ(m.data(i, TaskModel::TitleRole).toString(), QString("Fix"));
  EXPECT_EQ(m.data(i, TaskModel::DescRole).toString(), QString("d"));
  EXPECT_EQ(m.data(i, TaskModel::PriorityRole).toString(), QString("P1"));
  EXPECT_EQ(m.data(i, TaskModel::StatusRole).toString(), QString("prog"));
  EXPECT_EQ(m.data(i, TaskModel::BranchRole).toString(), QString("feat/x"));
  EXPECT_EQ(m.data(i, TaskModel::DeadlineRole).toDate(), QDate(2030, 1, 2));
  EXPECT_TRUE(m.data(i, TaskModel::ArchivedRole).toBool());
  EXPECT_EQ(m.data(i, TaskModel::StatusChangedAtRole).toDateTime(), QDateTime(QDate(2030, 1, 2), QTime(9, 0)));
  // Default (no git info pushed) — runtime git roles are empty/zero.
  EXPECT_FALSE(m.data(i, TaskModel::BlockedStuckRole).toBool());
  EXPECT_EQ(m.data(i, TaskModel::PrStateRole).toString(), QString());
  EXPECT_EQ(m.data(i, TaskModel::PrNumberRole).toInt(), 0);
}

TEST(TaskModelData, InvalidAndOutOfRangeReturnInvalid) {
  TaskModel m;
  m.reset({mkTask(QStringLiteral("T1"))});
  EXPECT_FALSE(m.data(QModelIndex(), TaskModel::IdRole).isValid());
  EXPECT_FALSE(m.data(m.index(5, 0), TaskModel::IdRole).isValid());
  EXPECT_FALSE(m.data(m.index(0, 0), Qt::DisplayRole).isValid());
}

// ─── TaskModel::upsert ────────────────────────────────────────────────

TEST(TaskModelUpsert, InsertAppendsUpdateReplacesInPlace) {
  TaskModel m;
  QSignalSpy ins(&m, &QAbstractItemModel::rowsInserted);
  QSignalSpy chg(&m, &QAbstractItemModel::dataChanged);

  m.upsert(mkTask(QStringLiteral("A")));
  m.upsert(mkTask(QStringLiteral("B")));
  m.upsert(mkTask(QStringLiteral("C")));
  EXPECT_EQ(m.rowCount(), 3);
  EXPECT_EQ(m.indexOfId(QStringLiteral("A")), 0);
  EXPECT_EQ(m.indexOfId(QStringLiteral("C")), 2);
  EXPECT_EQ(ins.count(), 3);
  EXPECT_EQ(chg.count(), 0);

  Task b = mkTask(QStringLiteral("B"));
  b.title = QStringLiteral("new");
  m.upsert(b);
  EXPECT_EQ(m.rowCount(), 3);
  EXPECT_EQ(m.indexOfId(QStringLiteral("B")), 1);  // not moved to end
  EXPECT_EQ(m.data(m.index(1, 0), TaskModel::TitleRole).toString(), QString("new"));
  EXPECT_EQ(ins.count(), 3);  // no new insert
  EXPECT_EQ(chg.count(), 1);  // one update
}

// ─── TaskModel::setStatus / setArchived / stampStatusChange ───────────

TEST(TaskModelMutate, SetStatusStampsAndGuards) {
  TaskModel m;
  m.reset({mkTask(QStringLiteral("T1"))});
  EXPECT_FALSE(m.data(m.index(0, 0), TaskModel::StatusChangedAtRole).toDateTime().isValid());

  QSignalSpy chg(&m, &QAbstractItemModel::dataChanged);
  m.setStatus(QStringLiteral("T1"), QStringLiteral("done"));
  EXPECT_EQ(m.data(m.index(0, 0), TaskModel::StatusRole).toString(), QString("done"));
  EXPECT_TRUE(m.data(m.index(0, 0), TaskModel::StatusChangedAtRole).toDateTime().isValid());
  EXPECT_EQ(chg.count(), 1);

  // Same value → no-op, no emit.
  m.setStatus(QStringLiteral("T1"), QStringLiteral("done"));
  EXPECT_EQ(chg.count(), 1);
  // Unknown id → no-op.
  m.setStatus(QStringLiteral("ghost"), QStringLiteral("todo"));
  EXPECT_EQ(chg.count(), 1);
}

TEST(TaskModelMutate, SetArchivedGuards) {
  TaskModel m;
  m.reset({mkTask(QStringLiteral("T1"))});
  QSignalSpy chg(&m, &QAbstractItemModel::dataChanged);
  m.setArchived(QStringLiteral("T1"), true);
  EXPECT_TRUE(m.data(m.index(0, 0), TaskModel::ArchivedRole).toBool());
  EXPECT_EQ(chg.count(), 1);
  m.setArchived(QStringLiteral("T1"), true);  // same value
  EXPECT_EQ(chg.count(), 1);
}

// ─── TaskModel::setBlockedStuckIds ────────────────────────────────────

TEST(TaskModelBlockedStuck, MembershipEqualSetAndUnionClear) {
  TaskModel m;
  m.reset({mkTask(QStringLiteral("T1")), mkTask(QStringLiteral("T2")), mkTask(QStringLiteral("T3"))});

  QSignalSpy chg(&m, &QAbstractItemModel::dataChanged);
  m.setBlockedStuckIds({QStringLiteral("T2")});
  EXPECT_TRUE(m.data(m.index(1, 0), TaskModel::BlockedStuckRole).toBool());
  EXPECT_FALSE(m.data(m.index(0, 0), TaskModel::BlockedStuckRole).toBool());
  EXPECT_FALSE(m.data(m.index(2, 0), TaskModel::BlockedStuckRole).toBool());
  EXPECT_EQ(chg.count(), 1);

  // Equal set → no-op.
  m.setBlockedStuckIds({QStringLiteral("T2")});
  EXPECT_EQ(chg.count(), 1);

  // Clear → T2 refreshes back to false (union of old+new covers it).
  m.setBlockedStuckIds({});
  EXPECT_FALSE(m.data(m.index(1, 0), TaskModel::BlockedStuckRole).toBool());
  EXPECT_EQ(chg.count(), 2);
}

TEST(TaskModelBlockedStuck, UnknownOnlyIdEmitsNothing) {
  TaskModel m;
  m.reset({mkTask(QStringLiteral("T1"))});
  QSignalSpy chg(&m, &QAbstractItemModel::dataChanged);
  m.setBlockedStuckIds({QStringLiteral("ghost")});
  EXPECT_FALSE(m.data(m.index(0, 0), TaskModel::BlockedStuckRole).toBool());
  EXPECT_EQ(chg.count(), 0);  // no in-model row affected → no dataChanged
}

// ─── TaskModel git info ───────────────────────────────────────────────

TEST(TaskModelGit, PartialMergeUnknownNoopAndClear) {
  TaskModel m;
  m.reset({mkTask(QStringLiteral("T1"))});

  QVariantMap info;
  info["prState"] = QStringLiteral("open");
  info["prNumber"] = 42;
  info["prUrl"] = QStringLiteral("http://x");
  info["ahead"] = 3;
  info["behind"] = 1;
  m.setGitInfoForId(QStringLiteral("T1"), info);
  const QModelIndex i = m.index(0, 0);
  EXPECT_EQ(m.data(i, TaskModel::PrStateRole).toString(), QString("open"));
  EXPECT_EQ(m.data(i, TaskModel::PrNumberRole).toInt(), 42);
  EXPECT_EQ(m.data(i, TaskModel::GitAheadRole).toInt(), 3);
  EXPECT_EQ(m.data(i, TaskModel::GitBehindRole).toInt(), 1);

  // Partial merge: only "ahead" supplied — others persist.
  QVariantMap partial;
  partial["ahead"] = 9;
  m.setGitInfoForId(QStringLiteral("T1"), partial);
  EXPECT_EQ(m.data(i, TaskModel::GitAheadRole).toInt(), 9);
  EXPECT_EQ(m.data(i, TaskModel::PrStateRole).toString(), QString("open"));
  EXPECT_EQ(m.data(i, TaskModel::PrNumberRole).toInt(), 42);

  // Unknown id → no-op, no emit.
  QSignalSpy chg(&m, &QAbstractItemModel::dataChanged);
  m.setGitInfoForId(QStringLiteral("ghost"), info);
  EXPECT_EQ(chg.count(), 0);

  // clearAllGitInfo wipes runtime git state.
  m.clearAllGitInfo();
  EXPECT_EQ(m.data(i, TaskModel::PrStateRole).toString(), QString());
  EXPECT_EQ(m.data(i, TaskModel::GitAheadRole).toInt(), 0);
}

TEST(TaskModelGit, ResetClearsGitInfo) {
  TaskModel m;
  m.reset({mkTask(QStringLiteral("T1"))});
  QVariantMap info;
  info["prState"] = QStringLiteral("open");
  m.setGitInfoForId(QStringLiteral("T1"), info);
  m.reset({mkTask(QStringLiteral("T1"))});
  EXPECT_EQ(m.data(m.index(0, 0), TaskModel::PrStateRole).toString(), QString());
}

// ─── TaskModel remove / insert clamp ──────────────────────────────────

TEST(TaskModelRemoveInsert, ReindexAndClamp) {
  TaskModel m;
  m.reset({mkTask(QStringLiteral("T1")), mkTask(QStringLiteral("T2")), mkTask(QStringLiteral("T3"))});

  m.removeById(QStringLiteral("T2"));
  EXPECT_EQ(m.rowCount(), 2);
  EXPECT_EQ(m.indexOfId(QStringLiteral("T2")), -1);
  EXPECT_EQ(m.indexOfId(QStringLiteral("T3")), 1);

  QSignalSpy rem(&m, &QAbstractItemModel::rowsRemoved);
  m.removeById(QStringLiteral("ghost"));  // no-op
  EXPECT_EQ(rem.count(), 0);

  m.insertAt(1, mkTask(QStringLiteral("X")));
  EXPECT_EQ(m.indexOfId(QStringLiteral("X")), 1);
  m.insertAt(-5, mkTask(QStringLiteral("H")));  // clamp to front
  EXPECT_EQ(m.indexOfId(QStringLiteral("H")), 0);
  m.insertAt(999, mkTask(QStringLiteral("E")));  // clamp to end
  EXPECT_EQ(m.indexOfId(QStringLiteral("E")), m.rowCount() - 1);
}

// ─── EventModel ───────────────────────────────────────────────────────

TEST(EventModelData, MapsRoles) {
  EventModel m;
  CalEvent e;
  e.id = QStringLiteral("E1");
  e.title = QStringLiteral("Standup");
  e.type = QStringLiteral("standup");
  e.start = 9.5;
  e.end = 10.0;
  e.attendees = QStringLiteral("a,b");
  e.date = QDate(2030, 3, 4);
  e.taskId = QStringLiteral("T7");
  e.profileId = QStringLiteral("P");
  e.context = QStringLiteral("ctx");
  m.reset({e});
  const QModelIndex i = m.index(0, 0);
  EXPECT_DOUBLE_EQ(m.data(i, EventModel::StartRole).toDouble(), 9.5);
  EXPECT_DOUBLE_EQ(m.data(i, EventModel::EndRole).toDouble(), 10.0);
  EXPECT_EQ(m.data(i, EventModel::TypeRole).toString(), QString("standup"));
  EXPECT_EQ(m.data(i, EventModel::TaskIdRole).toString(), QString("T7"));
  EXPECT_EQ(m.data(i, EventModel::ProfileIdRole).toString(), QString("P"));
  EXPECT_EQ(m.data(i, EventModel::ContextRole).toString(), QString("ctx"));
  EXPECT_EQ(m.data(i, EventModel::DateRole).toDate(), QDate(2030, 3, 4));
  EXPECT_FALSE(m.data(QModelIndex(), EventModel::IdRole).isValid());
}

TEST(EventModelLink, DetachTaskAndSetTaskId) {
  EventModel m;
  CalEvent e1;
  e1.id = QStringLiteral("E1");
  e1.taskId = QStringLiteral("T7");
  CalEvent e2;
  e2.id = QStringLiteral("E2");
  e2.taskId = QStringLiteral("T7");
  CalEvent e3;
  e3.id = QStringLiteral("E3");
  e3.taskId = QStringLiteral("T9");
  m.reset({e1, e2, e3});

  QSignalSpy chg(&m, &QAbstractItemModel::dataChanged);
  m.detachTask(QStringLiteral("T7"));
  EXPECT_EQ(m.data(m.index(0, 0), EventModel::TaskIdRole).toString(), QString());
  EXPECT_EQ(m.data(m.index(1, 0), EventModel::TaskIdRole).toString(), QString());
  EXPECT_EQ(m.data(m.index(2, 0), EventModel::TaskIdRole).toString(), QString("T9"));
  EXPECT_EQ(chg.count(), 2);  // one per matching row

  m.detachTask(QStringLiteral("nomatch"));
  EXPECT_EQ(chg.count(), 2);

  m.setTaskId(QStringLiteral("E3"), QStringLiteral("T1"));
  EXPECT_EQ(m.data(m.index(2, 0), EventModel::TaskIdRole).toString(), QString("T1"));
  m.setTaskId(QStringLiteral("ghost"), QStringLiteral("T1"));  // no-op
  EXPECT_EQ(chg.count(), 3);
}

// ─── PersonModel ──────────────────────────────────────────────────────

TEST(PersonModelData, MapsRolesIncludingColor) {
  PersonModel m;
  Person p;
  p.id = QStringLiteral("p1");
  p.name = QStringLiteral("Ann");
  p.role = QStringLiteral("QA");
  p.question = QStringLiteral("?");
  p.state = QStringLiteral("pinged");
  p.color = QColor(QStringLiteral("#ff0000"));
  m.reset({p});
  const QModelIndex i = m.index(0, 0);
  EXPECT_EQ(m.data(i, PersonModel::NameRole).toString(), QString("Ann"));
  EXPECT_EQ(m.data(i, PersonModel::RoleRole).toString(), QString("QA"));
  EXPECT_EQ(m.data(i, PersonModel::QuestionRole).toString(), QString("?"));
  EXPECT_EQ(m.data(i, PersonModel::StateRole).toString(), QString("pinged"));
  EXPECT_EQ(m.data(i, PersonModel::ColorRole).value<QColor>(), QColor(QStringLiteral("#ff0000")));
  EXPECT_FALSE(m.data(m.index(2, 0), PersonModel::IdRole).isValid());
}

TEST(PersonModelCycle, StateMachineAndDefault) {
  PersonModel m;
  m.reset({mkPerson(QStringLiteral("p1"), QStringLiteral("todo"))});
  m.cycleState(QStringLiteral("p1"));
  EXPECT_EQ(m.data(m.index(0, 0), PersonModel::StateRole).toString(), QString("pinged"));
  m.cycleState(QStringLiteral("p1"));
  EXPECT_EQ(m.data(m.index(0, 0), PersonModel::StateRole).toString(), QString("replied"));
  m.cycleState(QStringLiteral("p1"));
  EXPECT_EQ(m.data(m.index(0, 0), PersonModel::StateRole).toString(), QString("todo"));

  // Garbage current state → resets to todo (default branch).
  m.reset({mkPerson(QStringLiteral("p2"), QStringLiteral("banana"))});
  m.cycleState(QStringLiteral("p2"));
  EXPECT_EQ(m.data(m.index(0, 0), PersonModel::StateRole).toString(), QString("todo"));

  // Unknown id → no-op, no crash.
  QSignalSpy chg(&m, &QAbstractItemModel::dataChanged);
  m.cycleState(QStringLiteral("ghost"));
  EXPECT_EQ(chg.count(), 0);
}

TEST(PersonModelState, SetStateGuardAndTodoCount) {
  PersonModel m;
  m.reset({mkPerson(QStringLiteral("p1"), QStringLiteral("todo")),
           mkPerson(QStringLiteral("p2"), QStringLiteral("pinged")),
           mkPerson(QStringLiteral("p3"), QStringLiteral("todo")),
           mkPerson(QStringLiteral("p4"), QStringLiteral("replied"))});
  EXPECT_EQ(m.todoCount(), 2);

  QSignalSpy chg(&m, &QAbstractItemModel::dataChanged);
  m.setState(QStringLiteral("p2"), QStringLiteral("todo"));
  EXPECT_EQ(m.todoCount(), 3);
  EXPECT_EQ(chg.count(), 1);
  m.setState(QStringLiteral("p2"), QStringLiteral("todo"));  // same → no-op
  EXPECT_EQ(chg.count(), 1);
  m.setState(QStringLiteral("ghost"), QStringLiteral("todo"));  // unknown → no-op
  EXPECT_EQ(chg.count(), 1);

  PersonModel empty;
  EXPECT_EQ(empty.todoCount(), 0);
}

// ─── External-identity + label roles (HEAP-140) ───

TEST(TaskModelExternalRoles, RoleNamesExposeTheTrackerLink) {
  const TaskModel m;
  const QHash<int, QByteArray> names = m.roleNames();
  const QList<QByteArray> values = names.values();
  for(const char* expected : {"externalProvider", "externalUrl", "externalKey", "labels", "assignee"}) {
    EXPECT_TRUE(values.contains(QByteArray(expected))) << "missing role: " << expected;
  }
}

TEST(TaskModelExternalRoles, PulledJiraIssueExposesItsKeyAndLabels) {
  Task t;
  t.id = QStringLiteral("jira-PROJ-7");
  t.externalId = QStringLiteral("PROJ-7");
  t.externalUrl = QStringLiteral("https://x.atlassian.net/browse/PROJ-7");
  t.externalProvider = QStringLiteral("jira");
  t.labels = {Label{QStringLiteral("backend"), QStringLiteral("#ff0000")}, Label{QStringLiteral("p1"), QString()}};
  t.assignee = QStringLiteral("ann");

  TaskModel m;
  m.reset({t});
  const QModelIndex i = m.index(0, 0);

  EXPECT_EQ(m.data(i, TaskModel::ExternalProviderRole).toString(), QStringLiteral("jira"));
  EXPECT_EQ(m.data(i, TaskModel::ExternalKeyRole).toString(), QStringLiteral("PROJ-7"));
  EXPECT_EQ(m.data(i, TaskModel::ExternalUrlRole).toString(), t.externalUrl);
  EXPECT_EQ(m.data(i, TaskModel::AssigneeRole).toString(), QStringLiteral("ann"));

  const QVariantList labels = m.data(i, TaskModel::LabelsRole).toList();
  ASSERT_EQ(labels.size(), 2);
  EXPECT_EQ(labels.at(0).toMap().value(QStringLiteral("id")).toString(), QStringLiteral("backend"));
  EXPECT_EQ(labels.at(0).toMap().value(QStringLiteral("color")).toString(), QStringLiteral("#ff0000"));
  EXPECT_TRUE(labels.at(1).toMap().value(QStringLiteral("color")).toString().isEmpty());
}

// An issue-number tracker's key reads as "#123"; a purely local card has none.
TEST(TaskModelExternalRoles, IssueNumberBecomesAHashKeyAndLocalCardsAreEmpty) {
  Task gh;
  gh.id = QStringLiteral("github-68");
  gh.externalId = QStringLiteral("68");
  gh.externalProvider = QStringLiteral("github");

  Task local;
  local.id = QStringLiteral("LTE-1");

  TaskModel m;
  m.reset({gh, local});
  EXPECT_EQ(m.data(m.index(0, 0), TaskModel::ExternalKeyRole).toString(), QStringLiteral("#68"));

  const QModelIndex li = m.index(1, 0);
  EXPECT_TRUE(m.data(li, TaskModel::ExternalKeyRole).toString().isEmpty());
  EXPECT_TRUE(m.data(li, TaskModel::ExternalProviderRole).toString().isEmpty());
  EXPECT_TRUE(m.data(li, TaskModel::ExternalUrlRole).toString().isEmpty());
  EXPECT_TRUE(m.data(li, TaskModel::LabelsRole).toList().isEmpty());
  EXPECT_TRUE(m.data(li, TaskModel::AssigneeRole).toString().isEmpty());
}

// ─── Defer state (HEAP-124) ───

TEST(DeferState, SomedayIsExcludedFromScheduledForTodayAndOnlyItsOwnPredicate) {
  const QDate today(2026, 7, 9);

  Task parked;
  parked.scheduledAt = QDateTime(today, QTime(9, 0));  // scheduled, but parked
  parked.someday = true;

  EXPECT_FALSE(heap::model::isScheduledForToday(parked, today));
  EXPECT_TRUE(heap::model::isSomeday(parked));
  EXPECT_EQ(heap::model::deferState(parked, today), QStringLiteral("someday"));
}

TEST(DeferState, DerivesTodayScheduledAndAnytime) {
  const QDate today(2026, 7, 9);

  Task dueToday;
  dueToday.scheduledAt = QDateTime(today, QTime(16, 0));
  EXPECT_TRUE(heap::model::isScheduledForToday(dueToday, today));
  EXPECT_EQ(heap::model::deferState(dueToday, today), QStringLiteral("today"));

  Task overdue;
  overdue.scheduledAt = QDateTime(today.addDays(-3), QTime(9, 0));
  EXPECT_TRUE(heap::model::isScheduledForToday(overdue, today)) << "an overdue task is still on today's plate";

  Task later;
  later.scheduledAt = QDateTime(today.addDays(2), QTime(9, 0));
  EXPECT_FALSE(heap::model::isScheduledForToday(later, today));
  EXPECT_EQ(heap::model::deferState(later, today), QStringLiteral("scheduled"));

  Task unscheduled;
  EXPECT_FALSE(heap::model::isScheduledForToday(unscheduled, today));
  EXPECT_EQ(heap::model::deferState(unscheduled, today), QStringLiteral("anytime"));
}

// The deadline role stays a QDate so every calendar view keeps its day math.
TEST(TaskModelScheduling, DeadlineRoleIsTheDueDateWithoutItsClockTime) {
  Task t;
  t.dueAt = QDateTime(QDate(2026, 7, 11), QTime(16, 0));
  t.scheduledAt = QDateTime(QDate(2026, 7, 10), QTime(9, 30));
  t.hasTime = true;

  TaskModel m;
  m.reset({t});
  const QModelIndex i = m.index(0, 0);

  EXPECT_EQ(m.data(i, TaskModel::DeadlineRole).toDate(), QDate(2026, 7, 11));
  EXPECT_EQ(m.data(i, TaskModel::DueAtRole).toDateTime(), t.dueAt);
  EXPECT_EQ(m.data(i, TaskModel::ScheduledAtRole).toDateTime(), t.scheduledAt);
  EXPECT_TRUE(m.data(i, TaskModel::HasTimeRole).toBool());

  Task undated;
  m.reset({undated});
  EXPECT_FALSE(m.data(m.index(0, 0), TaskModel::DeadlineRole).toDate().isValid());
}
