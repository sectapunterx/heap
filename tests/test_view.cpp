// View navigation + status-column focus (HEAP-69).
//
// The sidebar Blocked / Code Review buttons call focusStatusColumn(id): it must
// switch the active view to "board" and record the focused status so the board
// can scroll to + highlight that column. Also covers countByStatus, which feeds
// the sidebar count badges.
//
// Headless via offscreen QPA + AppDataLocation test mode.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

Task mk(const QString& id, const QString& status) {
  Task t;
  t.id = id;
  t.title = id;
  t.priority = QStringLiteral("P2");
  t.status = status;
  return t;
}

}  // namespace

class ViewFocusTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->tasks()->reset({
        mk(QStringLiteral("A"), QStringLiteral("todo")),
        mk(QStringLiteral("B"), QStringLiteral("blocked")),
        mk(QStringLiteral("C"), QStringLiteral("blocked")),
        mk(QStringLiteral("D"), QStringLiteral("review")),
    });
  }

  void TearDown() override {
    app_.reset();
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(ViewFocusTest, FocusStatusColumnSwitchesToBoardAndRecordsStatus) {
  app_->setCurrentView(QStringLiteral("notes"));
  ASSERT_EQ(app_->currentView(), QStringLiteral("notes"));

  QSignalSpy viewSpy(app_.get(), &AppController::currentViewChanged);
  QSignalSpy focusSpy(app_.get(), &AppController::focusedStatusChanged);

  app_->focusStatusColumn(QStringLiteral("blocked"));

  EXPECT_EQ(app_->currentView(), QStringLiteral("board"));
  EXPECT_EQ(app_->focusedStatus(), QStringLiteral("blocked"));
  EXPECT_EQ(viewSpy.count(), 1);  // notes -> board
  EXPECT_GE(focusSpy.count(), 1);
}

TEST_F(ViewFocusTest, RepeatFocusOnSameStatusReEmits) {
  app_->focusStatusColumn(QStringLiteral("review"));  // from default "board"
  EXPECT_EQ(app_->currentView(), QStringLiteral("board"));
  EXPECT_EQ(app_->focusedStatus(), QStringLiteral("review"));

  // A repeat click on the already-focused status must re-emit so the board
  // re-runs its scroll/pulse.
  QSignalSpy focusSpy(app_.get(), &AppController::focusedStatusChanged);
  app_->focusStatusColumn(QStringLiteral("review"));
  EXPECT_EQ(focusSpy.count(), 1);
  EXPECT_EQ(app_->focusedStatus(), QStringLiteral("review"));
}

TEST_F(ViewFocusTest, CountByStatusFeedsBadges) {
  EXPECT_EQ(app_->countByStatus(QStringLiteral("blocked")), 2);
  EXPECT_EQ(app_->countByStatus(QStringLiteral("review")), 1);
  EXPECT_EQ(app_->countByStatus(QStringLiteral("todo")), 1);
  EXPECT_EQ(app_->countByStatus(QStringLiteral("nonexistent")), 0);
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
