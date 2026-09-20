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
  app_->addStatus(QStringLiteral("Review"), QString());
  app_->addStatus(QStringLiteral("Review"), QString());

  const QStringList ids = statusIds();
  EXPECT_EQ(ids.count(QStringLiteral("review")), 1);
  EXPECT_TRUE(ids.contains(QStringLiteral("review-2"))) << ids.join(QStringLiteral(",")).toStdString();
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
