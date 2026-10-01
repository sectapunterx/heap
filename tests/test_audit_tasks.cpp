// Regressions from the 2026-09-30 e2e audit, tasks area.
//
// Each block names the finding it pins (TASKS-n in the audit's FINDINGS.md).
// Headless via offscreen QPA + AppDataLocation test mode, like every other
// AppController suite.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

Task makeTask(const QString& id, const QString& status, double rank = 0.0) {
  Task t;
  t.id = id;
  t.title = id;
  t.priority = QStringLiteral("P2");
  t.status = status;
  t.rank = rank;
  t.statusChangedAt = QDateTime::currentDateTime();
  return t;
}

}  // namespace

class AuditTasksTest : public ::testing::Test {
 protected:
  void SetUp() override {
    // Every test starts from the demo seed: one of them deletes a column, and
    // the profile would otherwise carry that into the next.
    QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)).removeRecursively();
    app_ = std::make_unique<AppController>();
    app_->clearPendingUndo();
    // The demo seed ships these columns; tests that need others add them.
    ASSERT_GE(statusIdx(QStringLiteral("todo")), 0);
    ASSERT_GE(statusIdx(QStringLiteral("done")), 0);
  }

  void TearDown() override {
    app_.reset();
  }

  const Task& task(const QString& id) const {
    return app_->tasks()->items().at(app_->tasks()->indexOfId(id));
  }

  bool has(const QString& id) const {
    return app_->tasks()->indexOfId(id) >= 0;
  }

  QVariantMap editDraft(const QString& id) const {
    QVariantMap d = app_->taskById(id);
    d["_isNew"] = false;
    d["_originalId"] = id;
    return d;
  }

  int statusIdx(const QString& id) const {
    const QVariantList sts = app_->statuses();
    for(int i = 0; i < sts.size(); ++i) {
      if(sts.at(i).toMap().value("id").toString() == id) {
        return i;
      }
    }
    return -1;
  }

  QStringList columnNames() const {
    QStringList out;
    for(const QVariant& v : app_->statuses()) {
      out << v.toMap().value("name").toString();
    }
    return out;
  }

  std::unique_ptr<AppController> app_;
};

// ── TASKS-2: an editor save keeps what the editor does not show ──

TEST_F(AuditTasksTest, SavingFromTheEditorKeepsRankLinksAndLabelColours) {
  Task a = makeTask(QStringLiteral("A"), QStringLiteral("todo"), 5000.0);
  a.links = {TaskLink{QStringLiteral("blocks"), QStringLiteral("B")}};
  a.labels = {Label{QStringLiteral("infra"), QStringLiteral("#ff0000")}};
  app_->tasks()->reset({a, makeTask(QStringLiteral("B"), QStringLiteral("todo"), 1000.0)});

  QVariantMap d = editDraft(QStringLiteral("A"));
  // The editor hands labels back as plain text.
  d["labels"] = QVariantList{QStringLiteral("infra"), QStringLiteral("new")};
  ASSERT_TRUE(app_->saveTask(d));

  const Task& after = task(QStringLiteral("A"));
  EXPECT_DOUBLE_EQ(after.rank, 5000.0) << "a save must not move the card";
  ASSERT_EQ(after.links.size(), 1);
  EXPECT_EQ(after.links.first().targetId, QStringLiteral("B"));
  ASSERT_EQ(after.labels.size(), 2);
  EXPECT_EQ(after.labels.at(0).color, QStringLiteral("#ff0000"));
  EXPECT_TRUE(after.labels.at(1).color.isEmpty());
}

// ── TASKS-3: manual order works with rank-0 cards ──

TEST_F(AuditTasksTest, ANewCardLandsOnTopOfARankZeroColumn) {
  app_->tasks()->reset({makeTask(QStringLiteral("X-1"), QStringLiteral("todo")), makeTask(QStringLiteral("X-2"), QStringLiteral("todo"))});
  QVariantMap d = app_->newTaskDraft(QStringLiteral("todo"));
  d["title"] = QStringLiteral("fresh");
  const QString id = d.value("id").toString();
  ASSERT_TRUE(app_->saveTask(d));
  EXPECT_LT(task(id).rank, task(QStringLiteral("X-1")).rank);
  EXPECT_LT(task(id).rank, task(QStringLiteral("X-2")).rank);
}

TEST_F(AuditTasksTest, DroppingOnTopOfARankZeroCardMovesIt) {
  app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo")), makeTask(QStringLiteral("B"), QStringLiteral("todo"))});
  app_->moveTaskTo(QStringLiteral("B"), QStringLiteral("todo"), QStringLiteral("A"));
  EXPECT_LT(task(QStringLiteral("B")).rank, task(QStringLiteral("A")).rank);
}

TEST_F(AuditTasksTest, TiedRanksAreSpreadWhenAProfileIsLoaded) {
  QVector<Task> tasks{makeTask(QStringLiteral("B"), QStringLiteral("todo")), makeTask(QStringLiteral("A"), QStringLiteral("todo"))};
  QVector<Task> copy = tasks;
  EXPECT_EQ(heap::board::spreadTiedRanks(copy), 2);
  EXPECT_LT(copy[1].rank, copy[0].rank) << "A sorted before B by id, and keeps that place";
}

// ── TASKS-6: due and scheduled each carry their own clock flag ──

TEST_F(AuditTasksTest, SchedulingATaskLeavesADateOnlyDeadlineDateOnly) {
  Task t = makeTask(QStringLiteral("S-1"), QStringLiteral("todo"));
  t.dueAt = QDateTime(QDate(2026, 10, 20), QTime(0, 0));
  app_->tasks()->reset({t});

  app_->scheduleTask(QStringLiteral("S-1"), 14.0, QDate(2026, 10, 12));

  const Task& after = task(QStringLiteral("S-1"));
  EXPECT_TRUE(after.scheduledHasTime);
  EXPECT_FALSE(after.dueHasTime) << "the deadline must not turn into a 00:00 deadline";
  const QVariantMap m = app_->taskById(QStringLiteral("S-1"));
  EXPECT_FALSE(m.value("dueHasTime").toBool());
  EXPECT_TRUE(m.value("scheduledHasTime").toBool());
}

TEST_F(AuditTasksTest, EditorDraftFlagsArePerField) {
  QVariantMap d = app_->newTaskDraft(QStringLiteral("todo"));
  d["title"] = QStringLiteral("mixed");
  d["dueAt"] = QDateTime(QDate(2026, 10, 20), QTime(0, 0));
  d["scheduledAt"] = QDateTime(QDate(2026, 10, 12), QTime(9, 30));
  d["dueHasTime"] = false;
  d["scheduledHasTime"] = true;
  const QString id = d.value("id").toString();
  ASSERT_TRUE(app_->saveTask(d));
  EXPECT_FALSE(task(id).dueHasTime);
  EXPECT_TRUE(task(id).scheduledHasTime);
}

// ── TASKS-7 / TIME-12: every mutating action is one undo step ──

TEST_F(AuditTasksTest, ColumnEditsAreUndoable) {
  app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo"))});
  const QStringList before = columnNames();

  app_->addStatus(QStringLiteral("QA"), QStringLiteral("#123456"));
  ASSERT_EQ(columnNames().size(), before.size() + 1);
  app_->undo();
  EXPECT_EQ(columnNames(), before);

  app_->renameStatus(QStringLiteral("todo"), QStringLiteral("Later"));
  app_->undo();
  EXPECT_EQ(columnNames(), before);

  app_->setStatusWipLimit(QStringLiteral("todo"), 4);
  app_->undo();
  EXPECT_EQ(app_->statuses().at(statusIdx(QStringLiteral("todo"))).toMap().value("wip").toInt(), 0);

  app_->moveStatus(QStringLiteral("todo"), before.size() - 1);
  app_->undo();
  EXPECT_EQ(columnNames(), before);

  // And undo after a rename never reaches back into an older, unrelated task.
  EXPECT_TRUE(has(QStringLiteral("A")));
}

TEST_F(AuditTasksTest, RenameThenUndoDoesNotDeleteTheTaskCreatedBefore) {
  app_->tasks()->reset({});
  QVariantMap d = app_->newTaskDraft(QStringLiteral("todo"));
  d["title"] = QStringLiteral("keep me");
  const QString id = d.value("id").toString();
  ASSERT_TRUE(app_->saveTask(d));
  app_->renameStatus(QStringLiteral("todo"), QStringLiteral("Inbox"));
  app_->undo();
  EXPECT_TRUE(has(id)) << "Ctrl+Z after a rename undid the task creation instead";
}

TEST_F(AuditTasksTest, ScheduleTemplateTimerAndSnoozeAreOneStepEach) {
  Task t = makeTask(QStringLiteral("T-1"), QStringLiteral("todo"));
  t.dueAt = QDateTime(QDate(2026, 10, 20), QTime(16, 0));
  t.dueHasTime = true;
  app_->tasks()->reset({t});
  const int events = app_->events()->rowCount();

  app_->scheduleTask(QStringLiteral("T-1"), 10.0, QDate(2026, 10, 12));
  EXPECT_EQ(app_->events()->rowCount(), events + 1);
  app_->undo();
  EXPECT_EQ(app_->events()->rowCount(), events) << "the focus block must go with the undo";
  EXPECT_FALSE(task(QStringLiteral("T-1")).scheduledAt.isValid());

  app_->startTaskTimer(QStringLiteral("T-1"));
  EXPECT_TRUE(task(QStringLiteral("T-1")).timerStartedAt.isValid());
  app_->undo();
  EXPECT_FALSE(task(QStringLiteral("T-1")).timerStartedAt.isValid());

  app_->snoozeDeadline(QStringLiteral("T-1"), 3600);
  app_->undo();
  EXPECT_EQ(task(QStringLiteral("T-1")).dueAt, t.dueAt);

  const int rows = app_->tasks()->rowCount();
  app_->createTaskFromTemplate(QStringLiteral("PR review"));
  EXPECT_EQ(app_->tasks()->rowCount(), rows + 1);
  app_->undo();
  EXPECT_EQ(app_->tasks()->rowCount(), rows);
}

TEST_F(AuditTasksTest, AnUndoGroupRecordsOneStep) {
  app_->tasks()->reset({});
  const int depth = app_->undoDepth();
  app_->beginUndoGroup(QStringLiteral("sync"));
  QVariantMap d = app_->newTaskDraft(QStringLiteral("todo"));
  d["title"] = QStringLiteral("sync with Maria");
  const QString id = d.value("id").toString();
  ASSERT_TRUE(app_->saveTask(d));
  QVariantMap ev = app_->newEventDraft(15.0, QDate(2026, 10, 12));
  ev["title"] = QStringLiteral("sync with Maria");
  ev["type"] = QStringLiteral("sync");
  ev["taskId"] = id;
  app_->saveEvent(ev);
  app_->endUndoGroup();
  EXPECT_EQ(app_->undoDepth(), depth + 1);
  app_->undo();
  EXPECT_FALSE(has(id));
}

// The toast's Undo takes back the action it names, not whatever came after.
TEST_F(AuditTasksTest, ToastUndoUndoesTheActionItNames) {
  app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo"), 1024.0),
                        makeTask(QStringLiteral("B"), QStringLiteral("todo"), 2048.0),
                        makeTask(QStringLiteral("C"), QStringLiteral("todo"), 3072.0)});
  double serial = 0;
  QObject::connect(app_.get(), &AppController::undoableToast, [&](const QString&, int) {
    serial = app_->undoSerialForToast();
  });
  app_->deleteTask(QStringLiteral("A"));
  ASSERT_GT(serial, 0.0);
  // Something else happens before the user reaches the toast.
  app_->moveTaskTo(QStringLiteral("C"), QStringLiteral("todo"), QStringLiteral("B"));
  const double cRank = task(QStringLiteral("C")).rank;

  EXPECT_TRUE(app_->undoEntry(serial));
  EXPECT_TRUE(has(QStringLiteral("A"))) << "the deletion the toast named is undone";
  EXPECT_DOUBLE_EQ(task(QStringLiteral("C")).rank, cRank) << "the later reorder stays";
}

TEST_F(AuditTasksTest, ToastUndoRefusesWhenTheSameThingChangedSince) {
  app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo"), 1024.0)});
  double serial = 0;
  QObject::connect(app_.get(), &AppController::undoableToast, [&](const QString&, int) {
    serial = app_->undoSerialForToast();
  });
  app_->moveTask(QStringLiteral("A"), QStringLiteral("prog"));
  const double moveSerial = serial;
  app_->setArchived(QStringLiteral("A"), true);  // touches A again
  EXPECT_FALSE(app_->undoEntry(moveSerial));
  EXPECT_EQ(task(QStringLiteral("A")).status, QStringLiteral("prog"));
  EXPECT_TRUE(task(QStringLiteral("A")).archived);
}

// ── TASKS-18: undoing a column delete keeps the column edits made after it ──

TEST_F(AuditTasksTest, UndoingAColumnDeleteKeepsLaterColumnEdits) {
  app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo"))});
  app_->addStatus(QStringLiteral("QA"), QString());
  double serial = 0;
  QObject::connect(app_.get(), &AppController::undoableToast, [&](const QString&, int) {
    serial = app_->undoSerialForToast();
  });
  app_->deleteStatus(QStringLiteral("qa"));
  const double deleteSerial = serial;
  app_->renameStatus(QStringLiteral("todo"), QStringLiteral("Inbox"));

  ASSERT_TRUE(app_->undoEntry(deleteSerial));
  EXPECT_TRUE(columnNames().contains(QStringLiteral("QA")));
  EXPECT_TRUE(columnNames().contains(QStringLiteral("Inbox"))) << "the rename made after the delete must survive";
}

// ── TASKS-15: recurring completion ──

TEST_F(AuditTasksTest, ALateRecurringTaskSpawnsItsNextOccurrenceInTheFuture) {
  const QDate today = QDate::currentDate();
  Task t = makeTask(QStringLiteral("R-1"), QStringLiteral("todo"));
  t.recurrence = QStringLiteral("every:week");
  t.dueAt = QDateTime(today.addDays(-21), QTime(0, 0));
  app_->tasks()->reset({t});
  app_->moveTask(QStringLiteral("R-1"), QStringLiteral("done"));
  ASSERT_TRUE(has(QStringLiteral("R-1-r1")));
  EXPECT_GT(task(QStringLiteral("R-1-r1")).dueAt.date(), today);
  EXPECT_LE(task(QStringLiteral("R-1-r1")).dueAt.date(), today.addDays(7));
}

TEST_F(AuditTasksTest, DoneAgainAfterReopeningDoesNotSpawnASecondCopy) {
  Task t = makeTask(QStringLiteral("R-1"), QStringLiteral("todo"));
  t.recurrence = QStringLiteral("every:day");
  t.dueAt = QDateTime(QDate::currentDate(), QTime(0, 0));
  app_->tasks()->reset({t});
  app_->moveTask(QStringLiteral("R-1"), QStringLiteral("done"));
  app_->moveTask(QStringLiteral("R-1"), QStringLiteral("prog"));
  app_->moveTask(QStringLiteral("R-1"), QStringLiteral("done"));
  EXPECT_TRUE(has(QStringLiteral("R-1-r1")));
  EXPECT_FALSE(has(QStringLiteral("R-1-r2")));
}

TEST_F(AuditTasksTest, TheNextOccurrenceResetsItsChecklistAndFindsAColumn) {
  // Drop To Do: the copy must land in a column that exists.
  app_->tasks()->reset({});
  app_->deleteStatus(QStringLiteral("todo"));
  ASSERT_LT(statusIdx(QStringLiteral("todo")), 0);
  const QString first = app_->statuses().constFirst().toMap().value("id").toString();

  Task t = makeTask(QStringLiteral("R-1"), first);
  t.recurrence = QStringLiteral("every:day");
  t.dueAt = QDateTime(QDate::currentDate(), QTime(0, 0));
  t.desc = QStringLiteral("- [x] one\n- [X] two\n- [ ] three\nnot [x] a list");
  app_->tasks()->reset({t});
  app_->moveTask(QStringLiteral("R-1"), QStringLiteral("done"));
  ASSERT_TRUE(has(QStringLiteral("R-1-r1")));
  EXPECT_EQ(task(QStringLiteral("R-1-r1")).status, first);
  EXPECT_EQ(task(QStringLiteral("R-1-r1")).desc, QStringLiteral("- [ ] one\n- [ ] two\n- [ ] three\nnot [x] a list"));
}

TEST_F(AuditTasksTest, TheRecurrenceIsNamedInTheMoveToast) {
  Task t = makeTask(QStringLiteral("R-1"), QStringLiteral("todo"));
  t.recurrence = QStringLiteral("every:day");
  t.dueAt = QDateTime(QDate::currentDate(), QTime(0, 0));
  app_->tasks()->reset({t});
  QSignalSpy spy(app_.get(), &AppController::undoableToast);
  app_->moveTask(QStringLiteral("R-1"), QStringLiteral("done"));
  ASSERT_EQ(spy.count(), 1);
  EXPECT_TRUE(spy.at(0).at(0).toString().contains(QStringLiteral("R-1-r1")));
}

// ── TASKS-26: a new task knows when it entered its column ──

TEST_F(AuditTasksTest, ANewTaskIsStampedWithItsStatusChange) {
  QVariantMap d = app_->newTaskDraft(QStringLiteral("done"));
  d["title"] = QStringLiteral("already done");
  const QString id = d.value("id").toString();
  ASSERT_TRUE(app_->saveTask(d));
  EXPECT_TRUE(task(id).statusChangedAt.isValid());
}

// ── TASKS-28: a refused status keeps the editor's draft ──

TEST_F(AuditTasksTest, AReviewWithoutABranchRefusesTheWholeSave) {
  if(statusIdx(QStringLiteral("review")) < 0) {
    GTEST_SKIP() << "no review column in this seed";
  }
  QVariantMap s = app_->settingsMapForTest();
  QVariantMap tasks = s.value("tasks").toMap();
  tasks["requireBranchOnReview"] = true;
  s["tasks"] = tasks;
  app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(s)).toJson()));
  app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo"))});

  QVariantMap d = editDraft(QStringLiteral("A"));
  d["status"] = QStringLiteral("review");
  d["title"] = QStringLiteral("renamed");
  EXPECT_FALSE(app_->saveTask(d));
  EXPECT_EQ(task(QStringLiteral("A")).title, QStringLiteral("A")) << "nothing of a refused save is written";

  d["branch"] = QStringLiteral("feat/a");  // typed in the same save
  EXPECT_TRUE(app_->saveTask(d));
  EXPECT_EQ(task(QStringLiteral("A")).status, QStringLiteral("review"));
}

// ── TASKS-20: counters are about the live board ──

TEST_F(AuditTasksTest, ArchivedTasksAreNotCounted) {
  Task b1 = makeTask(QStringLiteral("B1"), QStringLiteral("blocked"));
  Task b2 = makeTask(QStringLiteral("B2"), QStringLiteral("blocked"));
  b2.archived = true;
  app_->tasks()->reset({b1, b2, makeTask(QStringLiteral("T1"), QStringLiteral("todo"))});
  const QVariantMap counts = app_->statusCounts();
  EXPECT_EQ(counts.value(QStringLiteral("blocked")).toInt(), 1);
  EXPECT_EQ(counts.value(QStringLiteral("_total")).toInt(), 2);
  // A column delete re-homes archived cards too, so that count includes them.
  EXPECT_EQ(app_->countByStatus(QStringLiteral("blocked")), 2);
}

TEST_F(AuditTasksTest, TheFilterBarCountsFollowTheFilters) {
  Task a = makeTask(QStringLiteral("A"), QStringLiteral("blocked"));
  a.priority = QStringLiteral("P0");
  Task b = makeTask(QStringLiteral("B"), QStringLiteral("prog"));
  Task c = makeTask(QStringLiteral("C"), QStringLiteral("blocked"));
  c.archived = true;
  app_->tasks()->reset({a, b, c});
  QVariantMap all = app_->filteredCounts(QString(), {}, false);
  EXPECT_EQ(all.value("total").toInt(), 2);
  EXPECT_EQ(all.value("blocked").toInt(), 1);
  EXPECT_EQ(app_->filteredCounts(QString(), {}, true).value("blocked").toInt(), 2);
  EXPECT_EQ(app_->filteredCounts(QString(), {QStringLiteral("P0")}, false).value("total").toInt(), 1);
  EXPECT_EQ(app_->filteredCounts(QStringLiteral("status:prog"), {}, false).value("active").toInt(), 1);
  EXPECT_EQ(app_->filteredCounts(QStringLiteral("status:prog"), {}, false).value("total").toInt(), 1);
}

// ── TASKS-32: priority and labels without the editor ──

TEST_F(AuditTasksTest, BulkPriorityAndLabelsAreOneUndoStepEach) {
  Task a = makeTask(QStringLiteral("A"), QStringLiteral("todo"));
  a.labels = {Label{QStringLiteral("infra"), QStringLiteral("#00ff00")}};
  app_->tasks()->reset({a, makeTask(QStringLiteral("B"), QStringLiteral("todo")), makeTask(QStringLiteral("C"), QStringLiteral("todo"))});
  app_->setSelectedTaskIds({QStringLiteral("A"), QStringLiteral("B")});

  app_->setSelectedTasksPriority(QStringLiteral("P0"));
  EXPECT_EQ(task(QStringLiteral("A")).priority, QStringLiteral("P0"));
  EXPECT_EQ(task(QStringLiteral("B")).priority, QStringLiteral("P0"));
  EXPECT_EQ(task(QStringLiteral("C")).priority, QStringLiteral("P2"));

  app_->setSelectedTasksLabel(QStringLiteral("#infra"), true);
  ASSERT_EQ(task(QStringLiteral("B")).labels.size(), 1);
  EXPECT_EQ(task(QStringLiteral("B")).labels.first().color, QStringLiteral("#00ff00")) << "the label keeps its colour";
  EXPECT_EQ(task(QStringLiteral("A")).labels.size(), 1) << "already labelled";

  app_->undo();
  EXPECT_TRUE(task(QStringLiteral("B")).labels.isEmpty());
  app_->undo();
  EXPECT_EQ(task(QStringLiteral("B")).priority, QStringLiteral("P2"));

  app_->setSelectedTasksLabel(QStringLiteral("infra"), false);
  EXPECT_TRUE(task(QStringLiteral("A")).labels.isEmpty());
}

TEST_F(AuditTasksTest, OneCardsPriorityFromItsMenu) {
  app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo"))});
  app_->setTaskPriority(QStringLiteral("A"), QStringLiteral("P1"));
  EXPECT_EQ(task(QStringLiteral("A")).priority, QStringLiteral("P1"));
  app_->setTaskPriority(QStringLiteral("A"), QStringLiteral("P7"));
  EXPECT_EQ(task(QStringLiteral("A")).priority, QStringLiteral("P1")) << "not a priority";
  app_->undo();
  EXPECT_EQ(task(QStringLiteral("A")).priority, QStringLiteral("P2"));
}

// ── TASKS-33: an id is a key ──

TEST_F(AuditTasksTest, AnIdWithASpaceOrSlashIsRefused) {
  for(const QString& bad : {QStringLiteral("FOO 1"), QStringLiteral("feat/1"), QStringLiteral("a\\b")}) {
    QVariantMap d = app_->newTaskDraft(QStringLiteral("todo"));
    d["id"] = bad;
    d["title"] = QStringLiteral("x");
    EXPECT_FALSE(app_->saveTask(d)) << bad.toStdString();
    EXPECT_FALSE(has(bad));
  }
}

// ── TASKS-30: "this week" is the calendar week ──

TEST_F(AuditTasksTest, ThisWeekEndsOnSunday) {
  const QDate today = app_->today();
  const QDate sunday = today.addDays(7 - today.dayOfWeek());
  const QDate nextMonday = sunday.addDays(1);
  if(today.daysTo(sunday) >= 2) {
    EXPECT_EQ(app_->deadlineBucket(sunday), QStringLiteral("thisweek"));
  }
  if(today.daysTo(nextMonday) >= 2) {
    EXPECT_EQ(app_->deadlineBucket(nextMonday), QStringLiteral("nextweek")) << "next Monday is not this week";
  }
  EXPECT_EQ(app_->deadlineBucket(sunday.addDays(7)), QStringLiteral("nextweek"));
  EXPECT_EQ(app_->deadlineBucket(sunday.addDays(8)), QStringLiteral("later"));
}

// ── TASKS-2 (B tier): a template task marks its id used ──

TEST_F(AuditTasksTest, ATemplateTasksIdIsNeverHandedOutAgain) {
  app_->tasks()->reset({});
  QSignalSpy opened(app_.get(), &AppController::openTaskRequested);
  app_->createTaskFromTemplate(QStringLiteral("PR review"));
  ASSERT_EQ(opened.count(), 1);
  const QString templateId = opened.first().first().toString();
  ASSERT_TRUE(has(templateId));
  app_->deleteTask(templateId);
  ASSERT_FALSE(has(templateId));
  const QString next = app_->newTaskDraft(QStringLiteral("todo")).value("id").toString();
  EXPECT_NE(next, templateId) << "the deleted template task's id was proposed again";
}

// ── TASKS-13 (B tier): bulk actions reach only the cards the filters show ──

TEST_F(AuditTasksTest, ASelectedCardTheSearchHidesLeavesTheSelection) {
  Task a = makeTask(QStringLiteral("SEL-1"), QStringLiteral("todo"));
  a.title = QStringLiteral("qzsel keep alpha");
  Task b = makeTask(QStringLiteral("SEL-2"), QStringLiteral("todo"));
  b.title = QStringLiteral("qzsel keep beta");
  Task c = makeTask(QStringLiteral("SEL-3"), QStringLiteral("todo"));
  c.title = QStringLiteral("qzsel gamma");
  app_->tasks()->reset({a, b, c});
  app_->setSelectionFilter(QString(), {}, false);
  app_->setSelectedTaskIds({QStringLiteral("SEL-1"), QStringLiteral("SEL-2"), QStringLiteral("SEL-3")});
  ASSERT_EQ(app_->selectionCount(), 3);

  app_->setSelectionFilter(QStringLiteral("gamma"), {}, false);
  EXPECT_EQ(app_->selectedTaskIds(), QStringList{QStringLiteral("SEL-3")});
  app_->deleteSelectedTasks();
  EXPECT_TRUE(has(QStringLiteral("SEL-1")));
  EXPECT_TRUE(has(QStringLiteral("SEL-2")));
  EXPECT_FALSE(has(QStringLiteral("SEL-3")));
}

TEST_F(AuditTasksTest, ABulkActionDropsCardsTheFiltersHideSinceSelecting) {
  Task a = makeTask(QStringLiteral("SEL-1"), QStringLiteral("todo"));
  a.priority = QStringLiteral("P0");
  Task b = makeTask(QStringLiteral("SEL-2"), QStringLiteral("todo"));
  b.priority = QStringLiteral("P0");
  app_->tasks()->reset({a, b});
  app_->setSelectionFilter(QString(), {QStringLiteral("P0")}, false);
  app_->setSelectedTaskIds({QStringLiteral("SEL-1"), QStringLiteral("SEL-2")});
  // SEL-2 leaves the P0 chip's view by an edit, not a filter change.
  QVariantMap d = editDraft(QStringLiteral("SEL-2"));
  d["priority"] = QStringLiteral("P3");
  ASSERT_TRUE(app_->saveTask(d));
  app_->setSelectedTasksArchived(true);
  EXPECT_TRUE(task(QStringLiteral("SEL-1")).archived);
  EXPECT_FALSE(task(QStringLiteral("SEL-2")).archived) << "a card no longer on screen was archived";
}

TEST_F(AuditTasksTest, TheArchiveViewKeepsArchivedCardsSelected) {
  Task a = makeTask(QStringLiteral("SEL-1"), QStringLiteral("todo"));
  a.archived = true;
  app_->tasks()->reset({a});
  app_->setSelectionFilter(QString(), {}, /*showArchived=*/true);
  app_->setSelectedTaskIds({QStringLiteral("SEL-1")});
  app_->setSelectedTasksArchived(false);
  EXPECT_FALSE(task(QStringLiteral("SEL-1")).archived);
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
