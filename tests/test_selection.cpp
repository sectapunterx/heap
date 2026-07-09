// Multi-select coverage for AppController. Verifies the selection state
// machine (toggle/set/clear/selectAll), bulk delete + undo restoration,
// bulk move + archive, and the cross-cutting clears triggered by view /
// profile switches.
//
// Runs headless: AppController owns timers, a NotificationCenter (tray
// fallback on Windows), a GitWatcher and persistence to AppDataLocation.
// We swap AppDataLocation to a per-process temp dir via QStandardPaths
// test mode, and force the offscreen QPA platform so QSystemTrayIcon /
// QClipboard construction stays headless.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QVector>

#include <gtest/gtest.h>

namespace {

Task makeTask(const QString& id, const QString& status = QStringLiteral("todo"), const QString& priority = QStringLiteral("P2")) {
  Task t;
  t.id = id;
  t.title = id + QStringLiteral(" title");
  t.priority = priority;
  t.status = status;
  return t;
}

// Replace whatever the freshly-constructed Example profile seeded with a
// known three-task set, all in the "todo" column. Returns the ids in row
// order so tests can assert against deterministic indices.
QStringList seedTasks(AppController& app, int n) {
  QVector<Task> items;
  QStringList ids;
  for(int i = 0; i < n; ++i) {
    const QString id = QStringLiteral("T-%1").arg(i + 1);
    items.append(makeTask(id));
    ids.append(id);
  }
  app.tasks()->reset(items);
  return ids;
}

}  // namespace

class SelectionTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    // Start every test with a clean slate — replaces the "Example"
    // profile's seeded tasks with whatever the test sets up.
    app_->tasks()->reset({});
  }

  void TearDown() override {
    app_.reset();
  }

  std::unique_ptr<AppController> app_;
};

// ─── selection mutators ───────────────────────────────────────────────

TEST_F(SelectionTest, StartsEmpty) {
  EXPECT_EQ(app_->selectionCount(), 0);
  EXPECT_TRUE(app_->selectedTaskIds().isEmpty());
  EXPECT_FALSE(app_->isTaskSelected("T-1"));
}

TEST_F(SelectionTest, ToggleAddsAndRemoves) {
  seedTasks(*app_, 3);
  QSignalSpy spy(app_.get(), &AppController::selectedTaskIdsChanged);

  app_->toggleTaskSelection("T-2");
  EXPECT_TRUE(app_->isTaskSelected("T-2"));
  EXPECT_EQ(app_->selectionCount(), 1);
  EXPECT_EQ(spy.count(), 1);

  app_->toggleTaskSelection("T-2");
  EXPECT_FALSE(app_->isTaskSelected("T-2"));
  EXPECT_EQ(app_->selectionCount(), 0);
  EXPECT_EQ(spy.count(), 2);
}

TEST_F(SelectionTest, SetTaskSelectedIsIdempotent) {
  seedTasks(*app_, 2);
  QSignalSpy spy(app_.get(), &AppController::selectedTaskIdsChanged);

  app_->setTaskSelected("T-1", true);
  app_->setTaskSelected("T-1", true);  // no-op — already in set
  EXPECT_EQ(spy.count(), 1);
  EXPECT_EQ(app_->selectionCount(), 1);

  app_->setTaskSelected("T-1", false);
  app_->setTaskSelected("T-1", false);  // no-op
  EXPECT_EQ(spy.count(), 2);
  EXPECT_EQ(app_->selectionCount(), 0);
}

TEST_F(SelectionTest, SetSelectedTaskIdsReplacesAndOrdersByRow) {
  seedTasks(*app_, 4);
  // Pass ids in reverse — controller stores them ordered by current row.
  app_->setSelectedTaskIds({"T-3", "T-1", "T-4"});
  EXPECT_EQ(app_->selectionCount(), 3);
  const QStringList expected = {"T-1", "T-3", "T-4"};
  EXPECT_EQ(app_->selectedTaskIds(), expected);
}

TEST_F(SelectionTest, SetSelectedTaskIdsDropsUnknownIds) {
  seedTasks(*app_, 2);
  app_->setSelectedTaskIds({"T-1", "ghost", "T-2"});
  // "ghost" doesn't exist in the model; rebuildSelectionList_() prunes it.
  EXPECT_EQ(app_->selectionCount(), 2);
  EXPECT_FALSE(app_->isTaskSelected("ghost"));
}

TEST_F(SelectionTest, ClearSelectionEmptiesAndSignalsOnce) {
  seedTasks(*app_, 2);
  app_->setSelectedTaskIds({"T-1", "T-2"});

  QSignalSpy spy(app_.get(), &AppController::selectedTaskIdsChanged);
  app_->clearSelection();
  EXPECT_EQ(spy.count(), 1);
  EXPECT_EQ(app_->selectionCount(), 0);

  // Idempotent — second clear emits nothing.
  app_->clearSelection();
  EXPECT_EQ(spy.count(), 1);
}

// ─── bulk delete + undo ───────────────────────────────────────────────

TEST_F(SelectionTest, DeleteSelectedRemovesAndArmsUndo) {
  seedTasks(*app_, 4);
  app_->setSelectedTaskIds({"T-1", "T-3"});
  ASSERT_EQ(app_->selectionCount(), 2);

  app_->deleteSelectedTasks();

  EXPECT_EQ(app_->tasks()->rowCount(), 2);
  EXPECT_EQ(app_->tasks()->indexOfId("T-1"), -1);
  EXPECT_EQ(app_->tasks()->indexOfId("T-3"), -1);
  EXPECT_GE(app_->tasks()->indexOfId("T-2"), 0);
  EXPECT_GE(app_->tasks()->indexOfId("T-4"), 0);
  EXPECT_EQ(app_->selectionCount(), 0);
  EXPECT_TRUE(app_->hasPendingUndo());
}

TEST_F(SelectionTest, UndoRestoresBulkDeleteToOriginalRows) {
  seedTasks(*app_, 4);
  app_->setSelectedTaskIds({"T-1", "T-3"});
  app_->deleteSelectedTasks();
  ASSERT_EQ(app_->tasks()->rowCount(), 2);

  app_->undoLastDeletion();

  // All four are back and in their original rows.
  ASSERT_EQ(app_->tasks()->rowCount(), 4);
  EXPECT_EQ(app_->tasks()->indexOfId("T-1"), 0);
  EXPECT_EQ(app_->tasks()->indexOfId("T-2"), 1);
  EXPECT_EQ(app_->tasks()->indexOfId("T-3"), 2);
  EXPECT_EQ(app_->tasks()->indexOfId("T-4"), 3);
  EXPECT_FALSE(app_->hasPendingUndo());
}

TEST_F(SelectionTest, DeleteSelectedOnEmptyIsNoOp) {
  seedTasks(*app_, 2);
  ASSERT_FALSE(app_->hasPendingUndo());

  app_->deleteSelectedTasks();

  EXPECT_EQ(app_->tasks()->rowCount(), 2);
  EXPECT_FALSE(app_->hasPendingUndo());
}

// ─── bulk move ────────────────────────────────────────────────────────

TEST_F(SelectionTest, MoveSelectedToStatusRewritesStatus) {
  seedTasks(*app_, 3);
  // "prog" is a column id from the default seeded statuses.
  app_->setSelectedTaskIds({"T-1", "T-3"});

  app_->moveSelectedTasksToStatus("prog");

  EXPECT_EQ(app_->taskById("T-1").value("status").toString(), QStringLiteral("prog"));
  EXPECT_EQ(app_->taskById("T-2").value("status").toString(), QStringLiteral("todo"));
  EXPECT_EQ(app_->taskById("T-3").value("status").toString(), QStringLiteral("prog"));
}

TEST_F(SelectionTest, MoveSelectedToUnknownStatusIsNoOp) {
  seedTasks(*app_, 2);
  app_->setSelectedTaskIds({"T-1", "T-2"});

  app_->moveSelectedTasksToStatus("not-a-column");

  EXPECT_EQ(app_->taskById("T-1").value("status").toString(), QStringLiteral("todo"));
  EXPECT_EQ(app_->taskById("T-2").value("status").toString(), QStringLiteral("todo"));
}

// ─── bulk archive ─────────────────────────────────────────────────────

TEST_F(SelectionTest, ArchiveSelectedTogglesFlag) {
  seedTasks(*app_, 3);
  app_->setSelectedTaskIds({"T-1", "T-2"});

  auto archivedAt = [this](const QString& id) {
    const int row = app_->tasks()->indexOfId(id);
    return app_->tasks()->items().at(row).archived;
  };

  app_->setSelectedTasksArchived(true);

  EXPECT_TRUE(archivedAt("T-1"));
  EXPECT_TRUE(archivedAt("T-2"));
  EXPECT_FALSE(archivedAt("T-3"));
  // Bulk archive empties the selection (rows just left the active view).
  EXPECT_EQ(app_->selectionCount(), 0);

  // Re-select to test the inverse — bulk unarchive also clears.
  app_->setSelectedTaskIds({"T-1", "T-2"});
  app_->setSelectedTasksArchived(false);
  EXPECT_FALSE(archivedAt("T-1"));
  EXPECT_FALSE(archivedAt("T-2"));
  EXPECT_EQ(app_->selectionCount(), 0);
}

// ─── cross-cutting clears ─────────────────────────────────────────────

TEST_F(SelectionTest, SwitchingViewClearsSelection) {
  seedTasks(*app_, 2);
  app_->setSelectedTaskIds({"T-1"});
  ASSERT_EQ(app_->selectionCount(), 1);

  app_->setCurrentView("timeline");

  EXPECT_EQ(app_->selectionCount(), 0);
  EXPECT_EQ(app_->currentView(), QStringLiteral("timeline"));
}

TEST_F(SelectionTest, SwitchingToSameViewDoesNotClear) {
  seedTasks(*app_, 1);
  // Normalize: loadStateOnStart() may have restored currentView from a
  // stale state file written by a prior test run. Pin it to "board"
  // BEFORE selecting so the assertion below tests the same-value path.
  app_->setCurrentView("board");
  app_->setSelectedTaskIds({"T-1"});
  ASSERT_EQ(app_->selectionCount(), 1);

  app_->setCurrentView("board");  // no-op — selection must survive
  EXPECT_EQ(app_->selectionCount(), 1);
}

TEST_F(SelectionTest, SaveTaskPreservesArchivedFlag) {
  // Reproduces the regression where opening an archived ticket in the
  // editor and hitting Save silently unarchived it (struct default
  // archived=false leaked into upsert).
  QVector<Task> items;
  Task t = makeTask("T-1");
  t.title = "kept";
  t.dueAt = QDateTime(QDate(2030, 5, 22), QTime(0, 0));
  t.scheduledAt = t.dueAt;
  t.archived = true;
  items.append(t);
  app_->tasks()->reset(items);

  // Round-trip through editor: read via taskById, save unchanged.
  QVariantMap draft = app_->taskById("T-1");
  ASSERT_TRUE(draft.value("archived").toBool());
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("T-1");
  app_->saveTask(draft);

  const int row = app_->tasks()->indexOfId("T-1");
  ASSERT_GE(row, 0);
  const Task& after = app_->tasks()->items().at(row);
  EXPECT_TRUE(after.archived);
  EXPECT_EQ(after.dueAt, QDateTime(QDate(2030, 5, 22), QTime(0, 0)));
  EXPECT_EQ(after.title, QStringLiteral("kept"));
}

TEST_F(SelectionTest, SaveTaskOmittingArchivedKeepsPriorState) {
  // Older drafts (pre-taskById-archived) won't carry the field at all.
  // saveTask must still preserve whatever was on the existing row.
  Task t = makeTask("T-1");
  t.archived = true;
  app_->tasks()->reset({t});

  QVariantMap draft;
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("T-1");
  draft["id"] = QStringLiteral("T-1");
  draft["title"] = QStringLiteral("edited");
  draft["priority"] = QStringLiteral("P2");
  draft["status"] = QStringLiteral("todo");
  // intentionally no "archived" key
  app_->saveTask(draft);

  const int row = app_->tasks()->indexOfId("T-1");
  ASSERT_GE(row, 0);
  EXPECT_TRUE(app_->tasks()->items().at(row).archived);
}

TEST_F(SelectionTest, ShortcutCatalogIncludesSelectionEntries) {
  QStringList ids;
  for(const QVariant& v : app_->shortcuts()) {
    ids.append(v.toMap().value("id").toString());
  }
  EXPECT_TRUE(ids.contains(QStringLiteral("selection.selectAll")));
  EXPECT_TRUE(ids.contains(QStringLiteral("selection.clearSel")));
  EXPECT_TRUE(ids.contains(QStringLiteral("selection.deleteSel")));
}

// ─── headless boot ────────────────────────────────────────────────────

int main(int argc, char** argv) {
  // Headless QPA — keeps QSystemTrayIcon / QClipboard from touching the
  // host display. Must run before QApplication is constructed.
  qputenv("QT_QPA_PLATFORM", "offscreen");

  // Isolate state.json / backups under the QStandardPaths test-mode dir
  // so the tests never read or overwrite the user's real AppDataLocation.
  // On Windows setTestModeEnabled() is honoured natively; on Linux the
  // XDG vars below pin the location to a per-process temp dir.
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  // Test-mode AppDataLocation can still hold leftovers from a previous
  // run on the same machine (Windows: %APPDATA%/QtProjectTest/...). Wipe
  // the state.json / backups dir so AppController boots from a clean
  // slate every test process — otherwise loadStateOnStart() can revive
  // a stale currentView / activeProfileId from another suite.
  const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  if(!appData.isEmpty()) {
    QFile::remove(appData + QStringLiteral("/state.json"));
    QDir(appData + QStringLiteral("/backups")).removeRecursively();
  }

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
