// Drag-to-reschedule (APP-249): AppController::rescheduleTask, clearTaskDate
// and resizeTaskBlock — what a drop or a move key in Week, Month and Timeline
// writes. One field, local only, one undo step with an undo toast, and the
// focus block a schedule came from moves with it. No clock is read: every
// date here is fixed.

#include "AppController.h"
#include "Models.h"

#include "local/Effective.h"

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

const QDate kDay(2031, 3, 12);  // a Wednesday

Task makeTask(const QString& id) {
  Task t;
  t.id = id;
  t.title = id + QStringLiteral(" title");
  t.priority = QStringLiteral("P2");
  t.status = QStringLiteral("todo");
  return t;
}

}  // namespace

class RescheduleTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->tasks()->reset({});
    app_->events()->reset({});
    app_->clearPendingUndo();
  }

  void TearDown() override {
    app_.reset();
  }

  Task task(const QString& id) const {
    const int row = app_->tasks()->indexOfId(id);
    return row >= 0 ? app_->tasks()->items().at(row) : Task{};
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(RescheduleTest, SchedulesADateOnly) {
  app_->tasks()->reset({makeTask(QStringLiteral("A-1"))});
  ASSERT_TRUE(app_->rescheduleTask(QStringLiteral("A-1"), QStringLiteral("scheduled"), QDateTime(kDay, QTime(0, 0)), false));
  const Task t = task(QStringLiteral("A-1"));
  EXPECT_EQ(t.scheduledAt, QDateTime(kDay, QTime(0, 0)));
  EXPECT_FALSE(t.scheduledHasTime);
  EXPECT_FALSE(t.dueAt.isValid()) << "the deadline is a different field";
}

TEST_F(RescheduleTest, KeepsTheClockWhenTimedAndDropsSeconds) {
  app_->tasks()->reset({makeTask(QStringLiteral("A-1"))});
  ASSERT_TRUE(app_->rescheduleTask(QStringLiteral("A-1"), QStringLiteral("scheduled"), QDateTime(kDay, QTime(14, 30, 42)), true));
  const Task t = task(QStringLiteral("A-1"));
  EXPECT_EQ(t.scheduledAt, QDateTime(kDay, QTime(14, 30)));
  EXPECT_TRUE(t.scheduledHasTime);
}

TEST_F(RescheduleTest, MovesTheDeadlineOnlyWhenAskedFor) {
  Task a = makeTask(QStringLiteral("A-1"));
  a.scheduledAt = QDateTime(kDay, QTime(9, 0));
  a.scheduledHasTime = true;
  app_->tasks()->reset({a});
  ASSERT_TRUE(app_->rescheduleTask(QStringLiteral("A-1"), QStringLiteral("due"), QDateTime(kDay.addDays(2), QTime(0, 0)), false));
  const Task t = task(QStringLiteral("A-1"));
  EXPECT_EQ(t.dueAt.date(), kDay.addDays(2));
  EXPECT_FALSE(t.dueHasTime);
  EXPECT_EQ(t.scheduledAt, QDateTime(kDay, QTime(9, 0))) << "the schedule is left alone";
}

TEST_F(RescheduleTest, ClearsAField) {
  Task a = makeTask(QStringLiteral("A-1"));
  a.dueAt = QDateTime(kDay, QTime(17, 0));
  a.dueHasTime = true;
  app_->tasks()->reset({a});
  ASSERT_TRUE(app_->clearTaskDate(QStringLiteral("A-1"), QStringLiteral("due")));
  const Task t = task(QStringLiteral("A-1"));
  EXPECT_FALSE(t.dueAt.isValid());
  EXPECT_FALSE(t.dueHasTime);
}

TEST_F(RescheduleTest, RefusesAnUnknownFieldOrTaskAndNoOps) {
  Task a = makeTask(QStringLiteral("A-1"));
  a.scheduledAt = QDateTime(kDay, QTime(0, 0));
  app_->tasks()->reset({a});
  const int depth = app_->undoDepth();
  EXPECT_FALSE(app_->rescheduleTask(QStringLiteral("A-1"), QStringLiteral("deadline"), QDateTime(kDay, QTime(0, 0)), false));
  EXPECT_FALSE(app_->rescheduleTask(QStringLiteral("NOPE"), QStringLiteral("scheduled"), QDateTime(kDay, QTime(0, 0)), false));
  EXPECT_FALSE(app_->rescheduleTask(QStringLiteral("A-1"), QStringLiteral("scheduled"), QDateTime(kDay, QTime(0, 0)), false))
      << "the same date is not a change";
  EXPECT_EQ(app_->undoDepth(), depth) << "nothing recorded for nothing done";
}

TEST_F(RescheduleTest, IsOneUndoStepWithAnUndoToast) {
  app_->tasks()->reset({makeTask(QStringLiteral("A-1"))});
  QSignalSpy toasts(app_.get(), &AppController::undoableToast);
  const int depth = app_->undoDepth();
  ASSERT_TRUE(app_->rescheduleTask(QStringLiteral("A-1"), QStringLiteral("scheduled"), QDateTime(kDay, QTime(10, 0)), true));
  EXPECT_EQ(app_->undoDepth(), depth + 1);
  ASSERT_EQ(toasts.count(), 1);
  EXPECT_TRUE(toasts.at(0).at(0).toString().contains(QStringLiteral("A-1")));

  // The toast's own action takes it back.
  ASSERT_TRUE(app_->undoEntry(app_->undoSerialForToast()));
  EXPECT_FALSE(task(QStringLiteral("A-1")).scheduledAt.isValid());
}

TEST_F(RescheduleTest, ATrackerDeadlineIsChangedLocallyAndSaysSo) {
  Task a = makeTask(QStringLiteral("GH-7"));
  a.externalProvider = QStringLiteral("github");
  a.externalId = QStringLiteral("7");
  a.dueAt = QDateTime(kDay, QTime(0, 0));
  a.externalMeta.dueAt = a.dueAt;
  app_->tasks()->reset({a});
  QSignalSpy toasts(app_.get(), &AppController::undoableToast);
  ASSERT_TRUE(app_->rescheduleTask(QStringLiteral("GH-7"), QStringLiteral("due"), QDateTime(kDay.addDays(7), QTime(0, 0)), false));
  const Task t = task(QStringLiteral("GH-7"));
  // A tracker card's date is mine now (APP-238): it sits in the local layer,
  // and the tracker's own field keeps what the tracker sent.
  EXPECT_EQ(heap::local::effectiveDueAt(t).date(), kDay.addDays(7));
  EXPECT_EQ(t.local.myDueAt.date(), kDay.addDays(7));
  EXPECT_EQ(t.dueAt, QDateTime(kDay, QTime(0, 0)));
  EXPECT_EQ(t.externalMeta.dueAt, QDateTime(kDay, QTime(0, 0))) << "what the tracker last sent is kept";
  ASSERT_EQ(toasts.count(), 1);
  EXPECT_NE(toasts.at(0).at(0).toString(), QString()) << "the toast names the change";
  EXPECT_TRUE(toasts.at(0).at(0).toString().contains(QStringLiteral(" · "))) << "and says it stays local";
}

TEST_F(RescheduleTest, TheFocusBlockTheScheduleCameFromMovesWithIt) {
  Task a = makeTask(QStringLiteral("A-1"));
  a.scheduledAt = QDateTime(kDay, QTime(10, 0));
  a.scheduledHasTime = true;
  CalEvent block;
  block.id = QStringLiteral("ev-1");
  block.type = QStringLiteral("focus");
  block.taskId = QStringLiteral("A-1");
  block.date = kDay;
  block.start = 10.0;
  block.end = 11.5;
  CalEvent other = block;  // another block of the same task, at another time
  other.id = QStringLiteral("ev-2");
  other.start = 15.0;
  other.end = 16.0;
  app_->tasks()->reset({a});
  app_->events()->reset({block, other});

  ASSERT_TRUE(app_->rescheduleTask(QStringLiteral("A-1"), QStringLiteral("scheduled"), QDateTime(kDay.addDays(1), QTime(13, 0)), true));
  const CalEvent moved = app_->events()->items().at(app_->events()->indexOfId(QStringLiteral("ev-1")));
  EXPECT_EQ(moved.date, kDay.addDays(1));
  EXPECT_DOUBLE_EQ(moved.start, 13.0);
  EXPECT_DOUBLE_EQ(moved.end, 14.5) << "the block keeps its length";
  const CalEvent kept = app_->events()->items().at(app_->events()->indexOfId(QStringLiteral("ev-2")));
  EXPECT_EQ(kept.date, kDay);
  EXPECT_DOUBLE_EQ(kept.start, 15.0);

  // One step: the undo puts the block back too.
  app_->undo();
  const CalEvent back = app_->events()->items().at(app_->events()->indexOfId(QStringLiteral("ev-1")));
  EXPECT_EQ(back.date, kDay);
  EXPECT_DOUBLE_EQ(back.start, 10.0);
  EXPECT_EQ(task(QStringLiteral("A-1")).scheduledAt, QDateTime(kDay, QTime(10, 0)));
}

TEST_F(RescheduleTest, ResizingABlockSetsTheStartAndTheEstimate) {
  Task a = makeTask(QStringLiteral("A-1"));
  a.scheduledAt = QDateTime(kDay, QTime(10, 0));
  a.scheduledHasTime = true;
  a.estimateMinutes = 60;
  app_->tasks()->reset({a});
  ASSERT_TRUE(app_->resizeTaskBlock(QStringLiteral("A-1"), kDay, 9.5, 11.0));
  Task t = task(QStringLiteral("A-1"));
  EXPECT_EQ(t.scheduledAt, QDateTime(kDay, QTime(9, 30)));
  EXPECT_TRUE(t.scheduledHasTime);
  EXPECT_EQ(t.estimateMinutes, 90);

  app_->undo();
  t = task(QStringLiteral("A-1"));
  EXPECT_EQ(t.scheduledAt, QDateTime(kDay, QTime(10, 0)));
  EXPECT_EQ(t.estimateMinutes, 60);
}

TEST_F(RescheduleTest, DroppingOnTheGridIsUndoableFromItsToast) {
  app_->tasks()->reset({makeTask(QStringLiteral("A-1"))});
  QSignalSpy toasts(app_.get(), &AppController::undoableToast);
  app_->scheduleTask(QStringLiteral("A-1"), 14.0, kDay);
  ASSERT_EQ(toasts.count(), 1) << "a drop on the hour grid gets an undo toast like every other drop";
  ASSERT_TRUE(app_->undoEntry(app_->undoSerialForToast()));
  EXPECT_FALSE(task(QStringLiteral("A-1")).scheduledAt.isValid());
  EXPECT_EQ(app_->events()->rowCount(), 0);
}

TEST_F(RescheduleTest, TheMoveKeysAreInTheCatalog) {
  QStringList ids;
  for(const QVariant& v : app_->shortcuts()) {
    ids << v.toMap().value("id").toString();
  }
  for(const char* id :
      {"cal.taskEarlier", "cal.taskLater", "cal.taskEarlierWeek", "cal.taskLaterWeek", "cal.taskTimeEarlier", "cal.taskTimeLater"}) {
    EXPECT_TRUE(ids.contains(QString::fromLatin1(id))) << id;
  }
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("cal.taskLater")), QStringLiteral("Ctrl+Right"));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("cal.taskLaterWeek")), QStringLiteral("Ctrl+Shift+Right"));
}

// ─── headless boot ────────────────────────────────────────────────────

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  if(!appData.isEmpty()) {
    QFile::remove(appData + QStringLiteral("/state.json"));
    QDir(appData + QStringLiteral("/backups")).removeRecursively();
  }

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
