// Undo coverage for task move + archive (HEAP-59).
//
// Undo used to be delete-only; a mis-dragged card or an accidental archive was
// unrecoverable. These tests pin the extended coverage: moveTask and
// setArchived arm the single-level undo, and undoLastDeletion() restores the
// previous status / archived flag.
//
// Headless via offscreen QPA + AppDataLocation test mode.

#include "AppController.h"
#include "Models.h"

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
