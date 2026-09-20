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
#include "StateSerializer.h"

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
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

// ─── view shortcuts ───────────────────────────────────────────────────
// Ctrl+1..8 are counted off the side rail, so they have to be in rail order.
// They used to skip Month (which had no shortcut at all) and then run
// docs/notes/settings out of order, so the number a user counted off the rail
// opened a different view.

namespace {

QString sequenceOf(AppController* app, const QString& id) {
  for(const QVariant& v : app->shortcuts()) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("id")).toString() == id) {
      return m.value(QStringLiteral("sequence")).toString();
    }
  }
  return {};
}

}  // namespace

TEST_F(ViewFocusTest, ViewShortcutsFollowTheSideRailOrder) {
  EXPECT_EQ(sequenceOf(app_.get(), QStringLiteral("view.board")), QStringLiteral("Ctrl+1"));
  EXPECT_EQ(sequenceOf(app_.get(), QStringLiteral("view.timeline")), QStringLiteral("Ctrl+2"));
  EXPECT_EQ(sequenceOf(app_.get(), QStringLiteral("view.week")), QStringLiteral("Ctrl+3"));
  EXPECT_EQ(sequenceOf(app_.get(), QStringLiteral("view.month")), QStringLiteral("Ctrl+4"));
  EXPECT_EQ(sequenceOf(app_.get(), QStringLiteral("view.archive")), QStringLiteral("Ctrl+5"));
  EXPECT_EQ(sequenceOf(app_.get(), QStringLiteral("view.docs")), QStringLiteral("Ctrl+6"));
  EXPECT_EQ(sequenceOf(app_.get(), QStringLiteral("view.notes")), QStringLiteral("Ctrl+7"));
  EXPECT_EQ(sequenceOf(app_.get(), QStringLiteral("view.settings")), QStringLiteral("Ctrl+8"));
}

// Month is reachable from the rail, so it needs a binding like its neighbours.
TEST_F(ViewFocusTest, MonthHasAShortcutWithALabelAndDescription) {
  bool found = false;
  for(const QVariant& v : app_->shortcuts()) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("id")).toString() != QStringLiteral("view.month")) {
      continue;
    }
    found = true;
    EXPECT_FALSE(m.value(QStringLiteral("label")).toString().isEmpty());
    EXPECT_FALSE(m.value(QStringLiteral("description")).toString().isEmpty());
  }
  EXPECT_TRUE(found);
}

// Every catalog entry must be unique — two views on one chord means one of
// them is unreachable, which is the shape of the bug this renumbering fixes.
TEST_F(ViewFocusTest, NoTwoShortcutsShareASequence) {
  QHash<QString, QString> seen;
  for(const QVariant& v : app_->shortcuts()) {
    const QVariantMap m = v.toMap();
    const QString seq = m.value(QStringLiteral("sequence")).toString();
    const QString id = m.value(QStringLiteral("id")).toString();
    if(seq.isEmpty()) {
      continue;
    }
    EXPECT_FALSE(seen.contains(seq)) << "both " << seen.value(seq).toStdString() << " and " << id.toStdString() << " are bound to "
                                     << seq.toStdString();
    seen.insert(seq, id);
  }
}

// ─── shortcut override migration ──────────────────────────────────────
// Settings written before kShortcutsSchema 2 stored *every* binding, not only
// the rebound ones. Restoring all of them would pin each shortcut to whatever
// the default was on the day the file was written — the renumbering above
// would reach nobody, and Ctrl+4 would end up bound to both Month and Docs.

namespace {

QString appDataDir() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

// A state file whose settings.shortcuts carry `entries`, with no schema marker
// — i.e. what an older build wrote.
void writeLegacyStateWithShortcuts(const QJsonObject& entries) {
  QDir(appDataDir()).removeRecursively();
  QDir().mkpath(appDataDir());

  QJsonObject settings;
  settings["shortcuts"] = entries;  // deliberately no "shortcutsSchema"

  QJsonObject root;
  root["schemaVersion"] = heap::state::kSchemaVersion;
  root["settings"] = settings;

  QFile f(appDataDir() + "/state.json");
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write(QJsonDocument(root).toJson());
}

QString sequenceIn(AppController& app, const QString& id) {
  for(const QVariant& v : app.shortcuts()) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("id")).toString() == id) {
      return m.value(QStringLiteral("sequence")).toString();
    }
  }
  return {};
}

}  // namespace

TEST(ShortcutMigration, ALegacyFilesStoredDefaultsDoNotPinTheOldLayout) {
  writeLegacyStateWithShortcuts({
      {QStringLiteral("view.docs"), QStringLiteral("Ctrl+4")},   // was the default
      {QStringLiteral("view.notes"), QStringLiteral("Ctrl+5")},  // was the default
      {QStringLiteral("view.archive"), QStringLiteral("Ctrl+7")},
  });

  AppController app;
  EXPECT_EQ(sequenceIn(app, QStringLiteral("view.month")), QStringLiteral("Ctrl+4"));
  EXPECT_EQ(sequenceIn(app, QStringLiteral("view.docs")), QStringLiteral("Ctrl+6"));
  EXPECT_EQ(sequenceIn(app, QStringLiteral("view.archive")), QStringLiteral("Ctrl+5"));
}

TEST(ShortcutMigration, ALegacyFilesRealRebindSurvives) {
  writeLegacyStateWithShortcuts({
      {QStringLiteral("view.docs"), QStringLiteral("Ctrl+4")},       // default of the day → dropped
      {QStringLiteral("task.new"), QStringLiteral("Ctrl+Shift+J")},  // never a default → kept
  });

  AppController app;
  EXPECT_EQ(sequenceIn(app, QStringLiteral("task.new")), QStringLiteral("Ctrl+Shift+J"));
  EXPECT_EQ(sequenceIn(app, QStringLiteral("view.docs")), QStringLiteral("Ctrl+6"));
}

// A cleared binding is a choice too, and "" never matched a default.
TEST(ShortcutMigration, ALegacyFilesClearedBindingSurvives) {
  writeLegacyStateWithShortcuts({{QStringLiteral("task.openExternal"), QString()}});

  AppController app;
  EXPECT_TRUE(sequenceIn(app, QStringLiteral("task.openExternal")).isEmpty());
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
