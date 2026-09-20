// Undo / redo.
//
// Undo was a single slot with a five-second timer: the next destructive
// operation overwrote the previous one, there was no redo, and bulk move and
// bulk archive recorded nothing at all. It is a stack of recorded diffs now
// (src/undo/UndoStack.h), so these cases pin both the behaviour that already
// existed and the three things that did not: depth, redo, and the operations
// that used to be unrecoverable.
//
// Headless via offscreen QPA + AppDataLocation test mode.

#include "AppController.h"
#include "Models.h"

#include "undo/UndoStack.h"

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QVector>

#include <gtest/gtest.h>

namespace {

constexpr int kStatusRole = Qt::UserRole + 5;
constexpr int kArchivedRole = Qt::UserRole + 9;

Task makeTask(const QString& id, const QString& status) {
  Task t;
  t.id = id;
  t.title = id;
  t.priority = QStringLiteral("P2");
  t.status = status;
  t.branch = QStringLiteral("feat/x");  // lets a move to "review" pass, too
  return t;
}

}  // namespace

class UndoTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->tasks()->reset({makeTask(QStringLiteral("T-1"), QStringLiteral("todo"))});
  }

  void TearDown() override {
    app_.reset();
  }

  QString statusOf(const QString& id) const {
    const int row = app_->tasks()->indexOfId(id);
    return app_->tasks()->data(app_->tasks()->index(row, 0), kStatusRole).toString();
  }

  bool archivedOf(const QString& id) const {
    const int row = app_->tasks()->indexOfId(id);
    return app_->tasks()->data(app_->tasks()->index(row, 0), kArchivedRole).toBool();
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(UndoTest, MoveTaskThenUndoRestoresStatus) {
  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("prog"));
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("prog"));
  EXPECT_TRUE(app_->hasPendingUndo());

  app_->undoLastDeletion();
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("todo"));
  EXPECT_FALSE(app_->hasPendingUndo());
}

TEST_F(UndoTest, ArchiveThenUndoRestores) {
  app_->setArchived(QStringLiteral("T-1"), true);
  EXPECT_TRUE(archivedOf(QStringLiteral("T-1")));
  EXPECT_TRUE(app_->hasPendingUndo());

  app_->undoLastDeletion();
  EXPECT_FALSE(archivedOf(QStringLiteral("T-1")));
}

TEST_F(UndoTest, NoOpMoveDoesNotArmUndo) {
  app_->clearPendingUndo();
  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("todo"));  // already todo
  EXPECT_FALSE(app_->hasPendingUndo());
}

// ─── depth: the thing a single slot could not do ──────────────────────

TEST_F(UndoTest, EachOperationIsItsOwnUndoStep) {
  app_->clearPendingUndo();
  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("prog"));
  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("review"));
  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("done"));
  EXPECT_EQ(app_->undoDepth(), 3) << "a later operation must not overwrite an earlier one";

  app_->undo();
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("review"));
  app_->undo();
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("prog"));
  app_->undo();
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("todo"));
  EXPECT_FALSE(app_->hasPendingUndo());
}

TEST_F(UndoTest, UndoPastTheBottomOfTheStackIsANoop) {
  app_->clearPendingUndo();
  app_->undo();
  app_->undo();
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("todo"));
}

// ─── redo ─────────────────────────────────────────────────────────────

TEST_F(UndoTest, RedoReappliesWhatUndoReversed) {
  app_->clearPendingUndo();
  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("prog"));

  app_->undo();
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("todo"));
  EXPECT_TRUE(app_->canRedo());

  app_->redo();
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("prog"));
  EXPECT_FALSE(app_->canRedo());
  EXPECT_TRUE(app_->hasPendingUndo()) << "a redone operation is undoable again";
}

TEST_F(UndoTest, ANewOperationDropsTheRedoBranch) {
  app_->clearPendingUndo();
  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("prog"));
  app_->undo();
  ASSERT_TRUE(app_->canRedo());

  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("review"));
  EXPECT_FALSE(app_->canRedo()) << "editing after an undo abandons the redone future";
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("review"));
}

TEST_F(UndoTest, DeleteThenUndoThenRedo) {
  app_->clearPendingUndo();
  app_->deleteTask(QStringLiteral("T-1"));
  EXPECT_EQ(app_->tasks()->rowCount(), 0);

  app_->undo();
  ASSERT_EQ(app_->tasks()->rowCount(), 1);
  EXPECT_EQ(app_->tasks()->items().at(0).id, QStringLiteral("T-1"));

  app_->redo();
  EXPECT_EQ(app_->tasks()->rowCount(), 0);
}

// ─── the operations that recorded nothing before ──────────────────────

TEST_F(UndoTest, BulkMoveIsUndoable) {
  app_->tasks()->reset({makeTask(QStringLiteral("T-1"), QStringLiteral("todo")),
                        makeTask(QStringLiteral("T-2"), QStringLiteral("todo")),
                        makeTask(QStringLiteral("T-3"), QStringLiteral("backlog"))});
  app_->clearPendingUndo();
  app_->setSelectedTaskIds({QStringLiteral("T-1"), QStringLiteral("T-2"), QStringLiteral("T-3")});

  app_->moveSelectedTasksToStatus(QStringLiteral("prog"));
  ASSERT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("prog"));
  ASSERT_EQ(statusOf(QStringLiteral("T-3")), QStringLiteral("prog"));

  app_->undo();
  EXPECT_EQ(statusOf(QStringLiteral("T-1")), QStringLiteral("todo"));
  EXPECT_EQ(statusOf(QStringLiteral("T-2")), QStringLiteral("todo"));
  EXPECT_EQ(statusOf(QStringLiteral("T-3")), QStringLiteral("backlog")) << "each task goes back to its own column, not to a shared one";
}

TEST_F(UndoTest, BulkArchiveIsUndoable) {
  app_->tasks()->reset({makeTask(QStringLiteral("T-1"), QStringLiteral("todo")), makeTask(QStringLiteral("T-2"), QStringLiteral("todo"))});
  app_->clearPendingUndo();
  app_->setSelectedTaskIds({QStringLiteral("T-1"), QStringLiteral("T-2")});

  app_->setSelectedTasksArchived(true);
  ASSERT_TRUE(archivedOf(QStringLiteral("T-1")));

  app_->undo();
  EXPECT_FALSE(archivedOf(QStringLiteral("T-1")));
  EXPECT_FALSE(archivedOf(QStringLiteral("T-2")));
}

// A restored task keeps its row, so undoing a delete does not silently
// reorder the column it came from.
TEST_F(UndoTest, UndoRestoresATaskToItsOriginalRow) {
  app_->tasks()->reset({makeTask(QStringLiteral("T-1"), QStringLiteral("todo")),
                        makeTask(QStringLiteral("T-2"), QStringLiteral("todo")),
                        makeTask(QStringLiteral("T-3"), QStringLiteral("todo"))});
  app_->clearPendingUndo();

  app_->deleteTask(QStringLiteral("T-2"));
  app_->undo();

  ASSERT_EQ(app_->tasks()->rowCount(), 3);
  EXPECT_EQ(app_->tasks()->items().at(1).id, QStringLiteral("T-2"));
}

// The stack is bounded, and it is the oldest entry that falls off.
TEST_F(UndoTest, TheStackIsCappedAtItsMaximumDepth) {
  app_->clearPendingUndo();
  const int cap = heap::undo::UndoStack::kMaxDepth;
  for(int i = 0; i < cap + 20; ++i) {
    app_->moveTask(QStringLiteral("T-1"), (i % 2 == 0) ? QStringLiteral("prog") : QStringLiteral("todo"));
  }
  EXPECT_EQ(app_->undoDepth(), cap);
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
