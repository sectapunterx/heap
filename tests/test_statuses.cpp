// Column (status) CRUD on AppController.
//
// The board's columns are the app's statuses, and addStatus / renameStatus /
// moveStatus / deleteStatus had no coverage at all — including the part that
// actually touches user data: deleting a column re-homes every task in it, and
// undo has to put both the column and those tasks back.
//
// Headless via offscreen QPA + AppDataLocation test mode.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QDir>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QVector>

#include <gtest/gtest.h>

namespace {

// Each case here rearranges the board's columns and lets AppController persist
// them, so without a wipe the next case would inherit them — one test deleting
// columns down to the minimum left every later test with a single-column board.
void clearAppData() {
  const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  QDir(dir).removeRecursively();
  QDir().mkpath(dir);
}

Task makeTask(const QString& id, const QString& status) {
  Task t;
  t.id = id;
  t.title = id;
  t.priority = QStringLiteral("P2");
  t.status = status;
  t.statusChangedAt = QDateTime::currentDateTime().addDays(-9);
  return t;
}

}  // namespace

class StatusTest : public ::testing::Test {
 protected:
  void SetUp() override {
    clearAppData();
    app_ = std::make_unique<AppController>();
    app_->tasks()->reset({});
  }

  void TearDown() override {
    app_.reset();
  }

  QStringList statusIds() const {
    QStringList out;
    for(const QVariant& v : app_->statuses()) {
      out << v.toMap().value(QStringLiteral("id")).toString();
    }
    return out;
  }

  QString nameOf(const QString& id) const {
    for(const QVariant& v : app_->statuses()) {
      const QVariantMap m = v.toMap();
      if(m.value(QStringLiteral("id")).toString() == id) {
        return m.value(QStringLiteral("name")).toString();
      }
    }
    return {};
  }

  int wipOf(const QString& id) const {
    for(const QVariant& v : app_->statuses()) {
      const QVariantMap m = v.toMap();
      if(m.value(QStringLiteral("id")).toString() == id) {
        return m.value(QStringLiteral("wip")).toInt();
      }
    }
    return -1;
  }

  const Task* taskById(const QString& id) const {
    for(const Task& t : app_->tasks()->items()) {
      if(t.id == id) {
        return &t;
      }
    }
    return nullptr;
  }

  std::unique_ptr<AppController> app_;
};

// ─── add ──────────────────────────────────────────────────────────────

TEST_F(StatusTest, AddStatusAppendsAndSlugsTheId) {
  const int before = app_->statuses().size();
  app_->addStatus(QStringLiteral("Needs Review"), QStringLiteral("#ff0000"));

  ASSERT_EQ(app_->statuses().size(), before + 1);
  EXPECT_EQ(statusIds().last(), QStringLiteral("needs-review"));
  EXPECT_EQ(nameOf(QStringLiteral("needs-review")), QStringLiteral("Needs Review"));
}

TEST_F(StatusTest, AddStatusRejectsAnEmptyName) {
  const int before = app_->statuses().size();
  app_->addStatus(QStringLiteral("   "), QString());
  EXPECT_EQ(app_->statuses().size(), before);
}

TEST_F(StatusTest, AddStatusGivesACollidingNameItsOwnId) {
  // A name that is free but slugs to a built-in id ("blocked").
  app_->addStatus(QStringLiteral("Blocked!"), QString());
  const QStringList ids = statusIds();
  EXPECT_EQ(ids.count(QStringLiteral("blocked")), 1);
  EXPECT_TRUE(ids.contains(QStringLiteral("blocked-2"))) << ids.join(QStringLiteral(",")).toStdString();
}

// A name that slugs away to nothing still has to produce a usable id.
TEST_F(StatusTest, AddStatusHandlesANameWithNoLettersOrDigits) {
  app_->addStatus(QStringLiteral("!!! ???"), QString());
  const QString id = statusIds().last();
  EXPECT_FALSE(id.isEmpty());
  EXPECT_FALSE(id.startsWith(QLatin1Char('-')));
  EXPECT_FALSE(id.endsWith(QLatin1Char('-')));
}

// ─── rename ───────────────────────────────────────────────────────────

TEST_F(StatusTest, RenameStatusChangesTheNameNotTheId) {
  app_->addStatus(QStringLiteral("Needs Review"), QString());
  app_->renameStatus(QStringLiteral("needs-review"), QStringLiteral("QA"));

  EXPECT_EQ(nameOf(QStringLiteral("needs-review")), QStringLiteral("QA"));
  EXPECT_TRUE(statusIds().contains(QStringLiteral("needs-review"))) << "the id is a task's status value; it must not move";
}

// The board commits a rename on blur as well as on Enter, so an empty field
// must not be able to leave a column with no name.
TEST_F(StatusTest, RenameStatusRejectsAnEmptyName) {
  app_->addStatus(QStringLiteral("Needs Review"), QString());
  app_->renameStatus(QStringLiteral("needs-review"), QStringLiteral("   "));
  EXPECT_EQ(nameOf(QStringLiteral("needs-review")), QStringLiteral("Needs Review"));
}

TEST_F(StatusTest, RenameStatusIgnoresAnUnknownId) {
  const QStringList before = statusIds();
  app_->renameStatus(QStringLiteral("ghost"), QStringLiteral("QA"));
  EXPECT_EQ(statusIds(), before);
}

// ─── move ─────────────────────────────────────────────────────────────

TEST_F(StatusTest, MoveStatusReordersTheColumns) {
  const QStringList before = statusIds();
  ASSERT_GE(before.size(), 3);

  app_->moveStatus(before.at(0), 2);

  const QStringList after = statusIds();
  EXPECT_EQ(after.at(2), before.at(0));
  EXPECT_EQ(after.size(), before.size());
}

TEST_F(StatusTest, MoveStatusClampsAnOutOfRangeIndex) {
  const QStringList before = statusIds();
  app_->moveStatus(before.at(0), 999);
  EXPECT_EQ(statusIds().last(), before.at(0));

  app_->moveStatus(before.at(0), -5);
  EXPECT_EQ(statusIds().first(), before.at(0));
}

TEST_F(StatusTest, MoveStatusToItsOwnIndexIsANoop) {
  const QStringList before = statusIds();
  app_->moveStatus(before.at(1), 1);
  EXPECT_EQ(statusIds(), before);
}

// ─── delete ───────────────────────────────────────────────────────────

TEST_F(StatusTest, DeleteStatusReHomesItsTasksToTheFirstRemainingColumn) {
  const QStringList ids = statusIds();
  ASSERT_GE(ids.size(), 2);
  const QString doomed = ids.at(1);
  const QString survivor = ids.at(0);
  app_->tasks()->reset({makeTask(QStringLiteral("T-1"), doomed), makeTask(QStringLiteral("T-2"), survivor)});

  app_->deleteStatus(doomed);

  EXPECT_FALSE(statusIds().contains(doomed));
  ASSERT_NE(taskById(QStringLiteral("T-1")), nullptr);
  EXPECT_EQ(taskById(QStringLiteral("T-1"))->status, survivor) << "a task must never be left pointing at a deleted column";
  EXPECT_EQ(taskById(QStringLiteral("T-2"))->status, survivor);
}

TEST_F(StatusTest, DeleteStatusMovesItsTasksIntoThePickedColumn) {
  // X-Dlg-Small "Перенести задачи в [К выполнению ▾]" (R2-041).
  const QStringList ids = statusIds();
  ASSERT_GE(ids.size(), 3);
  const QString doomed = ids.at(1);
  const QString target = ids.at(2);
  app_->tasks()->reset({makeTask(QStringLiteral("T-1"), doomed)});

  app_->deleteStatus(doomed, target);
  EXPECT_EQ(taskById(QStringLiteral("T-1"))->status, target);

  // The column being deleted, or one that does not exist, falls back to the first.
  app_->tasks()->reset({makeTask(QStringLiteral("T-2"), target)});
  app_->deleteStatus(target, target);
  EXPECT_EQ(taskById(QStringLiteral("T-2"))->status, ids.at(0));
}

TEST_F(StatusTest, DeleteStatusRefusesToEmptyTheBoard) {
  while(app_->statuses().size() > 1) {
    app_->deleteStatus(statusIds().last());
  }
  ASSERT_EQ(app_->statuses().size(), 1);

  app_->deleteStatus(statusIds().first());
  EXPECT_EQ(app_->statuses().size(), 1) << "the board must always have a column to drop cards into";
}

TEST_F(StatusTest, DeleteStatusIgnoresAnUnknownId) {
  const QStringList before = statusIds();
  app_->deleteStatus(QStringLiteral("ghost"));
  EXPECT_EQ(statusIds(), before);
}

TEST_F(StatusTest, UndoRestoresTheColumnAtItsOldIndexAndItsTasks) {
  const QStringList before = statusIds();
  ASSERT_GE(before.size(), 3);
  const QString doomed = before.at(1);
  app_->tasks()->reset({makeTask(QStringLiteral("T-1"), doomed)});

  app_->deleteStatus(doomed);
  ASSERT_TRUE(app_->hasPendingUndo());
  app_->undoLastDeletion();

  EXPECT_EQ(statusIds(), before) << "the column must come back where it was, not at the end";
  ASSERT_NE(taskById(QStringLiteral("T-1")), nullptr);
  EXPECT_EQ(taskById(QStringLiteral("T-1"))->status, doomed);
}

// statusChangedAt drives the "stuck in this column" badge. Re-homing stamps it
// with the current time, so undo has to put the original back — otherwise
// deleting a column and immediately undoing quietly resets how long every task
// in it had been sitting there.
TEST_F(StatusTest, UndoRestoresTheOriginalStatusChangedAt) {
  const QStringList ids = statusIds();
  ASSERT_GE(ids.size(), 2);
  const QString doomed = ids.at(1);
  Task t = makeTask(QStringLiteral("T-1"), doomed);
  const QDateTime original = t.statusChangedAt;
  app_->tasks()->reset({t});

  app_->deleteStatus(doomed);
  ASSERT_NE(taskById(QStringLiteral("T-1")), nullptr);
  ASSERT_NE(taskById(QStringLiteral("T-1"))->statusChangedAt, original) << "re-homing is a real status change";

  app_->undoLastDeletion();
  EXPECT_EQ(taskById(QStringLiteral("T-1"))->statusChangedAt, original);
}

// ─── WIP limit ────────────────────────────────────────────────────────
// Advisory on purpose: the column reports that it is over, and nothing is
// blocked. A hard cap would make a drag silently do nothing, which reads as a
// bug rather than as a rule.

TEST_F(StatusTest, WipLimitIsStoredOnTheColumn) {
  const QString id = statusIds().at(0);
  app_->setStatusWipLimit(id, 5);
  EXPECT_EQ(wipOf(id), 5);
}

TEST_F(StatusTest, WipLimitZeroMeansNoLimit) {
  const QString id = statusIds().at(0);
  app_->setStatusWipLimit(id, 5);
  app_->setStatusWipLimit(id, 0);
  EXPECT_EQ(wipOf(id), 0);
}

TEST_F(StatusTest, WipLimitIsClamped) {
  const QString id = statusIds().at(0);
  app_->setStatusWipLimit(id, -3);
  EXPECT_EQ(wipOf(id), 0);
  app_->setStatusWipLimit(id, 100000);
  EXPECT_LE(wipOf(id), 999);
}

TEST_F(StatusTest, WipLimitIgnoresAnUnknownColumn) {
  QSignalSpy spy(app_.get(), &AppController::statusesChanged);
  app_->setStatusWipLimit(QStringLiteral("ghost"), 5);
  EXPECT_EQ(spy.count(), 0);
}

// Exceeding the limit must not stop a card arriving — the badge is the whole
// feature.
TEST_F(StatusTest, BeingOverTheWipLimitDoesNotBlockAMove) {
  const QStringList ids = statusIds();
  ASSERT_GE(ids.size(), 2);
  app_->setStatusWipLimit(ids.at(1), 1);
  app_->tasks()->reset({makeTask(QStringLiteral("T-1"), ids.at(0)), makeTask(QStringLiteral("T-2"), ids.at(0))});

  app_->moveTask(QStringLiteral("T-1"), ids.at(1));
  app_->moveTask(QStringLiteral("T-2"), ids.at(1));

  EXPECT_EQ(taskById(QStringLiteral("T-2"))->status, ids.at(1)) << "a WIP limit is advisory, not a gate";
}

TEST_F(StatusTest, WipLimitSurvivesASaveAndReload) {
  const QString id = statusIds().at(0);
  app_->setStatusWipLimit(id, 7);
  app_->flushSave();

  AppController reopened;
  int found = -1;
  for(const QVariant& v : reopened.statuses()) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("id")).toString() == id) {
      found = m.value(QStringLiteral("wip")).toInt();
    }
  }
  EXPECT_EQ(found, 7);
}

TEST_F(StatusTest, DeleteStatusEmitsStatusesChanged) {
  QSignalSpy spy(app_.get(), &AppController::statusesChanged);
  app_->deleteStatus(statusIds().last());
  EXPECT_GE(spy.count(), 1);
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

// ── "Done" in one action (APP-268) ──

namespace {
QString statusOf(AppController& app, const QString& id) {
  return app.taskById(id).value(QStringLiteral("status")).toString();
}
}  // namespace

TEST_F(StatusTest, DoneMovesToTheDoneStageAndBackToWhereItWas) {
  app_->tasks()->upsert(makeTask(QStringLiteral("D-1"), QStringLiteral("prog")));
  const QVariantMap r = app_->toggleDone({QStringLiteral("D-1")});
  EXPECT_EQ(r.value("count").toInt(), 1);
  EXPECT_EQ(statusOf(*app_, QStringLiteral("D-1")), app_->doneColumn());
  // Again: back to "in progress", not to the first column.
  const QVariantMap back = app_->toggleDone({QStringLiteral("D-1")});
  EXPECT_TRUE(back.value("reopened").toBool());
  EXPECT_EQ(statusOf(*app_, QStringLiteral("D-1")), QStringLiteral("prog"));
}

TEST_F(StatusTest, DoneOnManyIsOneUndo) {
  app_->tasks()->upsert(makeTask(QStringLiteral("D-1"), QStringLiteral("todo")));
  app_->tasks()->upsert(makeTask(QStringLiteral("D-2"), QStringLiteral("review")));
  app_->toggleDone({QStringLiteral("D-1"), QStringLiteral("D-2")});
  EXPECT_EQ(statusOf(*app_, QStringLiteral("D-1")), app_->doneColumn());
  EXPECT_EQ(statusOf(*app_, QStringLiteral("D-2")), app_->doneColumn());
  app_->undo();
  EXPECT_EQ(statusOf(*app_, QStringLiteral("D-1")), QStringLiteral("todo"));
  EXPECT_EQ(statusOf(*app_, QStringLiteral("D-2")), QStringLiteral("review")) << "one undo for all";
}

TEST_F(StatusTest, DoneWithNothingIsNothing) {
  EXPECT_EQ(app_->toggleDone({}).value("count").toInt(), 0);
  EXPECT_EQ(app_->toggleDone({QStringLiteral("NOPE-1")}).value("count").toInt(), 0);
}

TEST_F(StatusTest, DoneWithNoDoneStageSaysSoAndMovesNothing) {
  for(const QString& id : statusIds()) {
    if(app_->statusCategory(id) == QStringLiteral("done")) {
      app_->setStatusCategory(id, QStringLiteral("review"));
    }
  }
  ASSERT_TRUE(app_->doneColumn().isEmpty());
  app_->tasks()->upsert(makeTask(QStringLiteral("D-1"), QStringLiteral("todo")));
  QSignalSpy spy(app_.get(), &AppController::doneColumnMissing);
  const QVariantMap r = app_->toggleDone({QStringLiteral("D-1")});
  EXPECT_EQ(r.value("error").toString(), QStringLiteral("noDoneColumn"));
  EXPECT_EQ(spy.count(), 1);
  EXPECT_EQ(statusOf(*app_, QStringLiteral("D-1")), QStringLiteral("todo"));
}

TEST_F(StatusTest, DoneCountsTheUntickedItemsWithoutAsking) {
  Task t = makeTask(QStringLiteral("D-1"), QStringLiteral("todo"));
  t.desc = QStringLiteral("- [x] one\n- [ ] two\n- [ ] three");
  app_->tasks()->upsert(t);
  const QVariantMap r = app_->toggleDone({QStringLiteral("D-1")});
  EXPECT_EQ(r.value("count").toInt(), 1);
  EXPECT_EQ(r.value("unchecked").toInt(), 2);
}

// ── A column of the Done kind finishes a task as "Done" does ──

namespace {
QString addShipped(AppController& app) {
  app.addStatus(QStringLiteral("Shipped"), QStringLiteral("#00aa00"));
  app.setStatusCategory(QStringLiteral("shipped"), QStringLiteral("done"));
  return QStringLiteral("shipped");
}
}  // namespace

TEST_F(StatusTest, ARecurringTaskFinishedInAUserDoneColumnSpawnsTheNextCopy) {
  // IDIOT-CAL-4: only the column with the id "done" used to spawn it.
  const QString shipped = addShipped(*app_);
  ASSERT_EQ(app_->statusCategory(shipped), QStringLiteral("done"));
  Task t = makeTask(QStringLiteral("R-1"), QStringLiteral("todo"));
  t.recurrence = QStringLiteral("every:week");
  t.dueAt = QDateTime(QDate::currentDate().addDays(3), QTime(10, 0));
  app_->tasks()->upsert(t);
  app_->moveTask(QStringLiteral("R-1"), shipped);
  const QVariantMap copy = app_->taskById(QStringLiteral("R-1-r1"));
  ASSERT_FALSE(copy.isEmpty());
  EXPECT_EQ(app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("R-1-r1"))).dueAt.date(),
            QDate::currentDate().addDays(10));
  // Shipped → Done is the same completion: no second copy.
  app_->moveTask(QStringLiteral("R-1"), QStringLiteral("done"));
  EXPECT_LT(app_->tasks()->indexOfId(QStringLiteral("R-1-r2")), 0);
}

TEST_F(StatusTest, FinishingATaskStopsItsTimer) {
  // IDIOT-CAL-6.
  app_->tasks()->upsert(makeTask(QStringLiteral("T-1"), QStringLiteral("prog")));
  app_->startTaskTimer(QStringLiteral("T-1"));
  ASSERT_TRUE(app_->tasks()->items().at(0).timerStartedAt.isValid());
  app_->moveTask(QStringLiteral("T-1"), addShipped(*app_));
  EXPECT_FALSE(app_->tasks()->items().at(0).timerStartedAt.isValid());
}

TEST_F(StatusTest, EndOfDayCountsAUserDoneColumnAsClosed) {
  // IDIOT-CAL-13: a Shipped card dated today was offered as carry-over.
  const QString shipped = addShipped(*app_);
  Task t = makeTask(QStringLiteral("E-1"), QStringLiteral("todo"));
  t.scheduledAt = QDateTime(QDate::currentDate(), QTime(9, 0));
  app_->tasks()->upsert(t);
  app_->moveTask(QStringLiteral("E-1"), shipped);
  const QVariantMap s = app_->endOfDaySummaryAt(QDateTime::currentDateTime());
  const QVariantList closed = s.value(QStringLiteral("closed")).toList();
  const QVariantList carry = s.value(QStringLiteral("carryOver")).toList();
  ASSERT_EQ(closed.size(), 1);
  EXPECT_EQ(closed.first().toMap().value(QStringLiteral("id")).toString(), QStringLiteral("E-1"));
  EXPECT_TRUE(carry.isEmpty());
}

TEST_F(StatusTest, TheListLensSeesBlockedAndDoneByTheColumnsKind) {
  // IDIOT-TASKS-13 / IDIOT-TASKS-10.
  const QString shipped = addShipped(*app_);
  app_->tasks()->upsert(makeTask(QStringLiteral("B-1"), QStringLiteral("todo")));
  app_->tasks()->upsert(makeTask(QStringLiteral("B-2"), QStringLiteral("todo")));
  app_->tasks()->upsert(makeTask(QStringLiteral("B-3"), shipped));
  ASSERT_TRUE(app_->addBlockLink(QStringLiteral("B-1"), QStringLiteral("B-2"), true));
  const auto ids = [this](const QString& query) {
    QStringList out;
    for(const QVariant& r : app_->taskListRows(query, {}, false, QString())) {
      const QString id = r.toMap().value(QStringLiteral("id")).toString();
      if(!id.isEmpty() && r.toMap().value(QStringLiteral("kind")).toString() != QStringLiteral("group")) {
        out << id;
      }
    }
    return out;
  };
  EXPECT_TRUE(ids(QStringLiteral("is:blocked")).contains(QStringLiteral("B-2")));
  EXPECT_FALSE(ids(QStringLiteral("is:open")).contains(QStringLiteral("B-3")));
  EXPECT_TRUE(ids(QStringLiteral("is:done")).contains(QStringLiteral("B-3")));
}

// ── Renaming the id prefix (IDIOT-TASKS-1, TASKS-2) ──

TEST_F(StatusTest, ThePrefixRenameRefusesAnIdAnotherTaskHolds) {
  app_->tasks()->upsert(makeTask(QStringLiteral("APP-1"), QStringLiteral("todo")));
  app_->tasks()->upsert(makeTask(QStringLiteral("APP-2"), QStringLiteral("todo")));
  app_->tasks()->upsert(makeTask(QStringLiteral("WEB-2"), QStringLiteral("todo")));
  EXPECT_EQ(app_->renameTaskIdPrefix(QStringLiteral("APP"), QStringLiteral("WEB")), 0);
  EXPECT_GE(app_->tasks()->indexOfId(QStringLiteral("APP-2")), 0);
  int web2 = 0;
  for(const Task& t : app_->tasks()->items()) {
    web2 += t.id == QStringLiteral("WEB-2") ? 1 : 0;
  }
  EXPECT_EQ(web2, 1) << "never two rows with one id";
}

TEST_F(StatusTest, ThePrefixRenameCarriesTheLinksAndIsOneUndo) {
  Task a = makeTask(QStringLiteral("APP-1"), QStringLiteral("todo"));
  a.links.append({QStringLiteral("blocks"), QStringLiteral("APP-2")});
  LocalCheckItem item;
  item.id = QStringLiteral("c1");
  item.text = QStringLiteral("part");
  item.cardId = QStringLiteral("APP-3");
  a.local.checklist.append(item);
  app_->tasks()->upsert(a);
  app_->tasks()->upsert(makeTask(QStringLiteral("APP-2"), QStringLiteral("todo")));
  app_->tasks()->upsert(makeTask(QStringLiteral("APP-3"), QStringLiteral("todo")));
  Task ext = makeTask(QStringLiteral("APP-9"), QStringLiteral("todo"));
  ext.externalProvider = QStringLiteral("jira");
  app_->tasks()->upsert(ext);

  EXPECT_EQ(app_->renameTaskIdPrefix(QStringLiteral("APP"), QStringLiteral("WEB")), 3);
  const int row = app_->tasks()->indexOfId(QStringLiteral("WEB-1"));
  ASSERT_GE(row, 0);
  const Task& w = app_->tasks()->items().at(row);
  ASSERT_EQ(w.links.size(), 1);
  EXPECT_EQ(w.links.first().targetId, QStringLiteral("WEB-2"));
  EXPECT_EQ(w.local.checklist.first().cardId, QStringLiteral("WEB-3"));
  EXPECT_GE(app_->tasks()->indexOfId(QStringLiteral("APP-9")), 0) << "a tracker ticket keeps its key";

  app_->undo();
  EXPECT_GE(app_->tasks()->indexOfId(QStringLiteral("APP-1")), 0);
  EXPECT_GE(app_->tasks()->indexOfId(QStringLiteral("APP-3")), 0);
  EXPECT_LT(app_->tasks()->indexOfId(QStringLiteral("WEB-1")), 0);
}
