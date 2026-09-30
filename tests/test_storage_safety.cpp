// Storage safety, profile scoping and platform fixes from the 2026-09-30 audit
// (PLAT-1…26, TASKS-1/31, UX-32).
//
// Every case drives a real AppController against the QStandardPaths test-mode
// profile, starting from an empty data directory, and judges what reached the
// disk — the only place "heap lost my data" is decided.

#include "AppController.h"
#include "RecoveryLog.h"
#include "StateSerializer.h"

#include "git/BranchTaskMatcher.h"
#include "git/GitWatcher.h"
#include "storage/StateIO.h"

#include <QApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <algorithm>
#include <iostream>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace {

QString appDataDir() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QString statePath() {
  return appDataDir() + QStringLiteral("/state.json");
}

QString backupDir() {
  return appDataDir() + QStringLiteral("/backups");
}

void writeRaw(const QString& path, const QByteArray& bytes) {
  QDir().mkpath(QFileInfo(path).absolutePath());
  QFile f(path);
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write(bytes);
}

QByteArray readRaw(const QString& path) {
  QFile f(path);
  return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

QJsonObject readJson(const QString& path) {
  return QJsonDocument::fromJson(readRaw(path)).object();
}

QJsonObject taskJson(const QString& id, const QString& status, const QDateTime& changed = QDateTime::currentDateTime()) {
  return QJsonObject{{"id", id},
                     {"title", id + QStringLiteral(" title")},
                     {"status", status},
                     {"priority", "P2"},
                     {"statusChangedAt", changed.toString(Qt::ISODate)}};
}

QJsonArray defaultStatuses() {
  QJsonArray a;
  for(const char* id : {"backlog", "todo", "prog", "blocked", "review", "done"}) {
    a.append(QJsonObject{{"id", id}, {"name", id}, {"color", "#888888"}});
  }
  return a;
}

QJsonObject profileJson(const QString& id, const QJsonArray& tasks) {
  return QJsonObject{{"id", id}, {"name", id.toUpper()}, {"color", "#5cc2dd"}, {"tasks", tasks}, {"statuses", defaultStatuses()}};
}

QByteArray stateDoc(const QJsonArray& profiles, const QString& active, const QJsonObject& extraRoot = {}) {
  QJsonObject root = extraRoot;
  root["schemaVersion"] = heap::state::kSchemaVersion;
  root["activeProfileId"] = active;
  root["profiles"] = profiles;
  root["events"] = QJsonArray();
  root["settings"] = QJsonObject{{"welcomeSeen", true}};
  return QJsonDocument(root).toJson();
}

bool hasTask(AppController& app, const QString& id) {
  return app.tasks()->indexOfId(id) >= 0;
}

bool logHas(AppController& app, const char* kind) {
  for(const QVariant& v : app.recoveryLog()) {
    if(v.toMap().value(QStringLiteral("kind")).toString() == QLatin1String(kind)) {
      return true;
    }
  }
  return false;
}

QStringList corruptFiles() {
  return QDir(appDataDir()).entryList({QStringLiteral("state.corrupt-*.json")}, QDir::Files);
}

class StorageSafety : public ::testing::Test {
 protected:
  void SetUp() override {
    QDir(appDataDir()).removeRecursively();
    QDir().mkpath(appDataDir());
  }

  void TearDown() override {
    heap::storage::setReaderForTesting({});
    AppController::setStateWriterForTesting({});
  }
};

// ── PLAT-1: a file that cannot be opened is not a damaged file ──

TEST_F(StorageSafety, AnUnreadableFileIsNeverQuarantinedOrSavedOver) {
  const QByteArray real = stateDoc({profileJson("work", {taskJson("REAL-1", "todo")})}, "work");
  writeRaw(statePath(), real);
  // An older backup, which the buggy path loaded and then wrote over the file.
  writeRaw(backupDir() + "/state-20260101-000000.json", stateDoc({profileJson("work", {taskJson("OLD-1", "todo")})}, "work"));

  int attempts = 0;
  heap::storage::setReaderForTesting([&attempts](const QString&) {
    ++attempts;
    heap::storage::ReadResult r;
    r.kind = heap::storage::ReadResult::Unreadable;
    r.error = QStringLiteral("sharing violation");
    return r;
  });
  {
    AppController app;
    EXPECT_GT(attempts, 1) << "an open failure must be retried before giving up";
    EXPECT_EQ(app.storageState(), QStringLiteral("unreadable"));
    EXPECT_TRUE(app.storageMessage().contains(QStringLiteral("sharing violation")));
    EXPECT_TRUE(hasTask(app, "OLD-1")) << "the newest backup is shown read-only";
    EXPECT_FALSE(app.demoActive()) << "never the demo seed";
    QVariantMap draft = app.newTaskDraft(QStringLiteral("todo"));
    draft["title"] = QStringLiteral("typed while locked");
    app.saveTask(draft);
    app.flushSave();
  }
  EXPECT_EQ(readRaw(statePath()), real) << "the locked file must be left byte-identical";
  EXPECT_TRUE(corruptFiles().isEmpty()) << "an unreadable file is not damage";

  // The lock lifts: Retry loads the real file and saving works again.
  heap::storage::setReaderForTesting({});
  AppController app;
  EXPECT_EQ(app.storageState(), QStringLiteral("ok"));
  EXPECT_TRUE(hasTask(app, "REAL-1"));
}

TEST_F(StorageSafety, RetryLoadsTheFileOnceTheLockLifts) {
  writeRaw(statePath(), stateDoc({profileJson("work", {taskJson("REAL-1", "todo")})}, "work"));
  bool locked = true;
  heap::storage::setReaderForTesting([&locked](const QString& path) {
    heap::storage::ReadResult r;
    if(locked) {
      r.kind = heap::storage::ReadResult::Unreadable;
      r.error = QStringLiteral("locked");
      return r;
    }
    QFile f(path);
    EXPECT_TRUE(f.open(QIODevice::ReadOnly));
    r.kind = heap::storage::ReadResult::Ok;
    r.bytes = f.readAll();
    return r;
  });
  AppController app;
  ASSERT_EQ(app.storageState(), QStringLiteral("unreadable"));
  EXPECT_FALSE(hasTask(app, "REAL-1"));
  locked = false;
  app.retryStorage();
  EXPECT_EQ(app.storageState(), QStringLiteral("ok"));
  EXPECT_TRUE(hasTask(app, "REAL-1"));
}

TEST_F(StorageSafety, AShortLockIsWaitedOut) {
  writeRaw(statePath(), stateDoc({profileJson("work", {taskJson("REAL-1", "todo")})}, "work"));
  int calls = 0;
  heap::storage::setReaderForTesting([&calls](const QString& path) {
    heap::storage::ReadResult r;
    if(++calls < 3) {
      r.kind = heap::storage::ReadResult::Unreadable;
      r.error = QStringLiteral("busy");
      return r;
    }
    QFile f(path);
    EXPECT_TRUE(f.open(QIODevice::ReadOnly));
    r.kind = heap::storage::ReadResult::Ok;
    r.bytes = f.readAll();
    return r;
  });
  AppController app;
  EXPECT_EQ(app.storageState(), QStringLiteral("ok"));
  EXPECT_TRUE(hasTask(app, "REAL-1"));
}

#ifdef Q_OS_WIN
// The real thing: an exclusive lock (an AV scan) for the whole start-up.
TEST_F(StorageSafety, AnExclusivelyLockedFileOpensReadOnly) {
  const QByteArray real = stateDoc({profileJson("work", {taskJson("REAL-1", "todo")})}, "work");
  writeRaw(statePath(), real);
  const std::wstring native = QDir::toNativeSeparators(statePath()).toStdWString();
  HANDLE h = CreateFileW(native.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  ASSERT_NE(h, INVALID_HANDLE_VALUE);
  {
    AppController app;
    EXPECT_EQ(app.storageState(), QStringLiteral("unreadable"));
    app.flushSave();
  }
  CloseHandle(h);
  EXPECT_EQ(readRaw(statePath()), real);
  EXPECT_TRUE(corruptFiles().isEmpty());
}

// A lock that allows reading but not renaming: the damaged file is kept as a
// byte-identical copy, and the toast names that copy.
TEST_F(StorageSafety, ADamagedFileThatCannotBeRenamedIsCopiedAside) {
  const QByteArray damaged("{ \"profiles\": [ truncated");
  writeRaw(statePath(), damaged);
  const std::wstring native = QDir::toNativeSeparators(statePath()).toStdWString();
  HANDLE h = CreateFileW(native.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  ASSERT_NE(h, INVALID_HANDLE_VALUE);
  {
    AppController app;
    const QStringList kept = corruptFiles();
    ASSERT_EQ(kept.size(), 1);
    EXPECT_EQ(readRaw(appDataDir() + "/" + kept.first()), damaged);
    // The file is still held, so the first save fails — and says so.
    QVariantMap draft = app.newTaskDraft(QStringLiteral("todo"));
    draft["title"] = QStringLiteral("x");
    app.saveTask(draft);
    app.flushSave();
    EXPECT_EQ(app.storageState(), QStringLiteral("writeFailed"));
  }
  CloseHandle(h);
}
#endif

// ── PLAT-4: a failed save is visible and retried ──

TEST_F(StorageSafety, AFailedSaveRaisesTheBannerAndRetryClearsIt) {
  bool fail = true;
  AppController::setStateWriterForTesting([&fail](const QString& path, const QByteArray& bytes) {
    if(fail) {
      return false;
    }
    return heap::storage::writeAtomically(path, bytes);
  });
  AppController app;
  QVariantMap draft = app.newTaskDraft(QStringLiteral("todo"));
  draft["title"] = QStringLiteral("unsaved");
  app.saveTask(draft);
  app.flushSave();
  EXPECT_EQ(app.storageState(), QStringLiteral("writeFailed"));
  EXPECT_FALSE(app.storageMessage().isEmpty());

  fail = false;
  app.retryStorage();
  EXPECT_EQ(app.storageState(), QStringLiteral("ok"));
  EXPECT_TRUE(QFile::exists(statePath()));
}

TEST_F(StorageSafety, AnUnwritableDirectoryIsReported) {
  QString why;
  EXPECT_TRUE(heap::storage::probeWritableDir(appDataDir(), &why));
  // A path under an existing FILE can never be a directory.
  writeRaw(appDataDir() + "/blocker", "x");
  EXPECT_FALSE(heap::storage::probeWritableDir(appDataDir() + "/blocker/sub", &why));
  EXPECT_FALSE(why.isEmpty());
}

// ── PLAT-3: restore always snapshots the current state first ──

TEST_F(StorageSafety, RestoreSnapshotsCurrentWorkEvenWithAFreshBackup) {
  const QString stamp = QDateTime::currentDateTime().addSecs(-60).toString("yyyyMMdd-HHmmss");
  const QString fresh = "state-" + stamp + ".json";
  writeRaw(backupDir() + "/" + fresh, stateDoc({profileJson("work", {taskJson("OLD-1", "todo")})}, "work"));
  writeRaw(statePath(), stateDoc({profileJson("work", {taskJson("OLD-1", "todo")})}, "work"));

  AppController app;
  QVariantMap draft = app.newTaskDraft(QStringLiteral("todo"));
  draft["id"] = QStringLiteral("NEW-9");
  draft["title"] = QStringLiteral("work since the backup");
  app.saveTask(draft);
  ASSERT_TRUE(app.restoreFromBackup(fresh));
  EXPECT_FALSE(hasTask(app, "NEW-9"));

  bool snapshotHasIt = false;
  for(const QString& name : QDir(backupDir()).entryList({"state-*prerestore*.json"}, QDir::Files)) {
    snapshotHasIt = snapshotHasIt || readRaw(backupDir() + "/" + name).contains("NEW-9");
  }
  EXPECT_TRUE(snapshotHasIt) << "the work since the backup must survive the restore";
}

// ── PLAT-15 / TASKS-1: undo is scoped to its workspace ──

TEST_F(StorageSafety, RestoreClearsTheUndoHistory) {
  writeRaw(statePath(), stateDoc({profileJson("work", {taskJson("APP-101", "todo")})}, "work"));
  AppController app;
  app.flushSave();
  const QString name = QStringLiteral("state-20260101-000000.json");
  writeRaw(backupDir() + "/" + name, readRaw(statePath()));
  app.deleteTask(QStringLiteral("APP-101"));
  ASSERT_TRUE(app.hasPendingUndo());
  ASSERT_TRUE(app.restoreFromBackup(name));
  EXPECT_FALSE(app.hasPendingUndo());
  app.undo();
  int copies = 0;
  for(const Task& t : app.tasks()->items()) {
    copies += t.id == QStringLiteral("APP-101") ? 1 : 0;
  }
  EXPECT_EQ(copies, 1);
}

TEST_F(StorageSafety, UndoAfterAProfileSwitchNeverTouchesTheOtherProfile) {
  writeRaw(statePath(), stateDoc({profileJson("a", {taskJson("TASK-1", "todo")}), profileJson("b", {taskJson("TASK-2", "todo")})}, "a"));
  AppController app;
  app.deleteTask(QStringLiteral("TASK-1"));
  app.setActiveProfileId(QStringLiteral("b"));
  EXPECT_FALSE(app.hasPendingUndo());
  app.undo();
  EXPECT_TRUE(hasTask(app, "TASK-2"));
  EXPECT_FALSE(hasTask(app, "TASK-1")) << "A's deletion must not be undone into B";
}

// ── TASKS-1/31, UX-32: task ids ──

TEST_F(StorageSafety, IdsStartAtOneAreNeverReusedAndNeverCollideAcrossProfiles) {
  writeRaw(statePath(), stateDoc({profileJson("a", {}), profileJson("b", {})}, "a"));
  {
    AppController app;
    QVariantMap d = app.newTaskDraft(QStringLiteral("todo"));
    EXPECT_EQ(d.value("id").toString(), QStringLiteral("TASK-1"));
    d["title"] = QStringLiteral("first");
    app.saveTask(d);
    app.deleteTask(QStringLiteral("TASK-1"));
    EXPECT_EQ(app.newTaskDraft(QStringLiteral("todo")).value("id").toString(), QStringLiteral("TASK-2"))
        << "a deleted id is not handed out again";
    QVariantMap d2 = app.newTaskDraft(QStringLiteral("todo"));
    d2["title"] = QStringLiteral("second");
    app.saveTask(d2);
    app.setActiveProfileId(QStringLiteral("b"));
    EXPECT_EQ(app.newTaskDraft(QStringLiteral("todo")).value("id").toString(), QStringLiteral("TASK-3"))
        << "another profile must not reuse TASK-2";
  }
  AppController reopened;
  EXPECT_EQ(reopened.newTaskDraft(QStringLiteral("todo")).value("id").toString(), QStringLiteral("TASK-3"))
      << "the counter survives a restart";
}

TEST_F(StorageSafety, ExistingIdsKeepTheirSequence) {
  writeRaw(statePath(), stateDoc({profileJson("a", {taskJson("TASK-2705", "todo")})}, "a"));
  AppController app;
  EXPECT_EQ(app.newTaskDraft(QStringLiteral("todo")).value("id").toString(), QStringLiteral("TASK-2706"));
}

// ── PLAT-14: undoing a profile deletion ──

TEST_F(StorageSafety, UndoProfileDeleteGivesItsEventsBack) {
  writeRaw(statePath(), stateDoc({profileJson("a", {}), profileJson("dup", {})}, "a"));
  AppController app;
  app.setActiveProfileId(QStringLiteral("dup"));
  QVariantMap ev = app.newEventDraft(10.0, QDate::currentDate());
  ev["title"] = QStringLiteral("standup");
  app.saveEvent(ev);
  QString eventId;
  for(const CalEvent& e : app.events()->items()) {
    if(e.title == QStringLiteral("standup")) {
      eventId = e.id;
      EXPECT_EQ(e.profileId, QStringLiteral("dup"));
    }
  }
  ASSERT_FALSE(eventId.isEmpty());

  app.deleteProfile(QStringLiteral("dup"));
  app.undo();
  for(const CalEvent& e : app.events()->items()) {
    if(e.id == eventId) {
      EXPECT_EQ(e.profileId, QStringLiteral("dup"));
    }
  }
}

TEST_F(StorageSafety, UndoProfileDeleteNeverDuplicatesAnId) {
  writeRaw(statePath(), stateDoc({profileJson("a", {})}, "a"));
  AppController app;
  const QString first = app.createProfile(QStringLiteral("DupProf"));
  app.deleteProfile(first);
  const QString second = app.createProfile(QStringLiteral("DupProf"));
  EXPECT_EQ(first, second);  // the freed id is handed out again…
  app.deleteProfile(second);
  app.undo();  // …undoes the second deletion only
  app.createProfile(QStringLiteral("DupProf"));
  QSet<QString> ids;
  QSet<QString> names;
  for(const QVariant& v : app.profiles()) {
    const QVariantMap m = v.toMap();
    EXPECT_FALSE(ids.contains(m.value("id").toString())) << qPrintable(m.value("id").toString());
    ids.insert(m.value("id").toString());
    names.insert(m.value("name").toString());
  }
  EXPECT_EQ(ids.size(), app.profiles().size());
}

// ── PLAT-5: a file from a newer heap ──

TEST_F(StorageSafety, ANewerSchemaIsAPersistentReadOnlyStateWithOneCopy) {
  const QByteArray doc = [] {
    QJsonObject r = QJsonDocument::fromJson(stateDoc({profileJson("a", {taskJson("T-1", "todo")})}, "a")).object();
    r["schemaVersion"] = heap::state::kSchemaVersion + 1;
    return QJsonDocument(r).toJson();
  }();
  writeRaw(statePath(), doc);
  for(int launch = 0; launch < 3; ++launch) {
    AppController app;
    EXPECT_EQ(app.storageState(), QStringLiteral("tooNew"));
    EXPECT_FALSE(app.storageMessage().isEmpty());
  }
  EXPECT_EQ(QDir(backupDir()).entryList({"state-premigration-*.json"}, QDir::Files).size(), 1)
      << "an unchanged newer file is copied once, not once per launch";
  EXPECT_EQ(readRaw(statePath()), doc);
}

// ── PLAT-7: valid JSON that is not a state file ──

class NotAStateFile : public StorageSafety, public ::testing::WithParamInterface<const char*> {};

TEST_P(NotAStateFile, IsQuarantinedAndNeverLoadsAColumnlessProfile) {
  writeRaw(statePath(), QByteArray(GetParam()));
  AppController app;
  EXPECT_EQ(corruptFiles().size(), 1) << GetParam();
  EXPECT_TRUE(logHas(app, heap::recovery::kQuarantined));
  EXPECT_FALSE(app.statuses().isEmpty()) << "a profile with no columns is unusable";
}

INSTANTIATE_TEST_SUITE_P(
    Shapes,
    NotAStateFile,
    ::testing::Values("{}", "{\"schemaVersion\":9}", "{\"schemaVersion\":9,\"profiles\":\"x\"}", "{\"schemaVersion\":9,\"profiles\":[]}"));

TEST_F(StorageSafety, AProfileWithoutStatusesGetsTheDefaultColumns) {
  QJsonObject p{{"id", "a"}, {"name", "A"}, {"tasks", QJsonArray{taskJson("T-1", "todo")}}};
  writeRaw(statePath(), stateDoc({p}, "a"));
  AppController app;
  EXPECT_FALSE(app.statuses().isEmpty());
  EXPECT_TRUE(hasTask(app, "T-1"));
}

// ── PLAT-26: unknown keys pass through a save ──

TEST_F(StorageSafety, UnknownKeysSurviveASave) {
  QJsonObject p = profileJson("a", {taskJson("T-1", "todo")});
  p["futureProfileField"] = QStringLiteral("keep me");
  QJsonObject root = QJsonDocument::fromJson(stateDoc({p}, "a", QJsonObject{{"futureRootField", 42}})).object();
  QJsonObject settings = root["settings"].toObject();
  settings["futureSetting"] = true;
  root["settings"] = settings;
  writeRaw(statePath(), QJsonDocument(root).toJson());
  {
    AppController app;
    QVariantMap d = app.newTaskDraft(QStringLiteral("todo"));
    d["title"] = QStringLiteral("edit");
    app.saveTask(d);
    app.flushSave();
  }
  const QJsonObject saved = readJson(statePath());
  EXPECT_EQ(saved["futureRootField"].toInt(), 42);
  EXPECT_TRUE(saved["settings"].toObject()["futureSetting"].toBool());
  EXPECT_EQ(saved["profiles"].toArray().at(0).toObject()["futureProfileField"].toString(), QStringLiteral("keep me"));
}

// ── PLAT-8: views ──

TEST_F(StorageSafety, AnUnknownViewLandsOnTheBoardAndIsNeverPersisted) {
  QJsonObject root = QJsonDocument::fromJson(stateDoc({profileJson("a", {})}, "a")).object();
  root["settings"] = QJsonObject{{"welcomeSeen", true}, {"currentView", "kanban"}};
  writeRaw(statePath(), QJsonDocument(root).toJson());
  AppController app;
  EXPECT_EQ(app.currentView(), QStringLiteral("board"));
  app.setCurrentView(QStringLiteral("week"));
  app.setCurrentView(QStringLiteral("nonsense"));
  EXPECT_EQ(app.currentView(), QStringLiteral("board"));
}

// ── PLAT-9: automation covers every profile ──

TEST_F(StorageSafety, AutoArchiveReachesInactiveProfiles) {
  const QDateTime old = QDateTime::currentDateTime().addDays(-30);
  writeRaw(statePath(), stateDoc({profileJson("a", {taskJson("A-1", "todo")}), profileJson("b", {taskJson("B-1", "done", old)})}, "a"));
  AppController app;
  QMetaObject::invokeMethod(&app, "runAutomation");
  app.setActiveProfileId(QStringLiteral("b"));
  const int row = app.tasks()->indexOfId(QStringLiteral("B-1"));
  ASSERT_GE(row, 0);
  EXPECT_TRUE(app.tasks()->items().at(row).archived);
}

// ── PLAT-20: a person keeps a name ──

TEST_F(StorageSafety, APersonCannotBeRenamedToNothing) {
  writeRaw(statePath(), stateDoc({profileJson("a", {})}, "a"));
  AppController app;
  QVariantMap p = app.newPersonDraft();
  p["name"] = QStringLiteral("Ann Lee");
  app.savePerson(p);
  ASSERT_EQ(app.people()->rowCount(), 1);
  const QString id = app.people()->items().first().id;
  QVariantMap edit = app.personById(id);
  edit["name"] = QStringLiteral("   ");
  app.savePerson(edit);
  EXPECT_EQ(app.people()->items().first().name, QStringLiteral("Ann Lee"));
}

// ── PLAT-6: the git watcher only moves work forward ──

TEST_F(StorageSafety, CheckingOutTheBranchOfFinishedWorkLeavesItAlone) {
  QTemporaryDir repos;
  const auto makeRepo = [&repos](const QString& name, const QString& branch) {
    const QString dir = repos.path() + "/" + name;
    QDir().mkpath(dir + "/.git/refs/heads");
    QFile head(dir + "/.git/HEAD");
    EXPECT_TRUE(head.open(QIODevice::WriteOnly));
    head.write(("ref: refs/heads/" + branch + "\n").toUtf8());
    return dir;
  };
  const QString doneRepo = makeRepo("done", "TASK-5-fix");
  const QString todoRepo = makeRepo("todo", "TASK-6-feature");
  writeRaw(statePath(), stateDoc({profileJson("a", {taskJson("TASK-5", "done"), taskJson("TASK-6", "todo")})}, "a"));
  AppController app;
  const QJsonObject settings{{"git", QJsonObject{{"watchedRepos", QJsonArray{doneRepo, todoRepo}}, {"watchPrState", false}}}};
  app.setAppSettingsJson(QString::fromUtf8(QJsonDocument(settings).toJson(QJsonDocument::Compact)));
  QCoreApplication::processEvents();
  const auto statusOf = [&app](const QString& id) {
    const int row = app.tasks()->indexOfId(id);
    return row >= 0 ? app.tasks()->items().at(row).status : QString();
  };
  EXPECT_EQ(statusOf("TASK-5"), QStringLiteral("done")) << "finished work must not be reopened";
  EXPECT_EQ(statusOf("TASK-6"), QStringLiteral("prog")) << "work that is starting still moves";
}

// ── PLAT-23: a save does not freeze the UI thread ──

TEST_F(StorageSafety, ADebouncedSaveOfTenThousandTasksDoesNotBlockTheEventLoop) {
  writeRaw(statePath(), stateDoc({profileJson("a", {})}, "a"));
  AppController app;
  QVector<Task> many;
  for(int i = 0; i < 10000; ++i) {
    Task t;
    t.id = QStringLiteral("BIG-%1").arg(i);
    t.title = QStringLiteral("Task number %1 with a realistic title length").arg(i);
    t.desc = QStringLiteral("Several lines of description text.\nSecond line.");
    t.status = QStringLiteral("todo");
    t.priority = QStringLiteral("P2");
    t.statusChangedAt = QDateTime::currentDateTime();
    many.append(t);
  }
  app.tasks()->reset(many);

  // The whole cost of a save, snapshot to disk.
  app.setCrumbUser(QStringLiteral("warm"));
  app.flushSave();
  app.setCrumbUser(QStringLiteral("full"));
  QElapsedTimer full;
  full.start();
  app.flushSave();
  const qint64 fullMs = full.elapsed();

  // Now let the debounce fire on its own and watch how long the event loop
  // is ever held: only the snapshot may run on it.
  app.setCrumbUser(QStringLiteral("async"));
  QElapsedTimer window;
  window.start();
  QElapsedTimer gap;
  gap.start();
  qint64 worst = 0;
  while(window.elapsed() < 1500) {
    QCoreApplication::processEvents(QEventLoop::AllEvents, 5);
    worst = std::max(worst, gap.restart());
  }
  const bool savedInTheWindow = readRaw(statePath()).contains("\"async\"");
  app.flushSave();
  std::cout << "[ save-ui-block ] full=" << fullMs << "ms worst-event-loop-gap=" << worst << "ms" << std::endl;
  if(fullMs < 40) {
    GTEST_SKIP() << "this machine saves too fast to tell the difference";
  }
  EXPECT_LT(worst, fullMs / 2) << "the save still runs on the UI thread";
  EXPECT_TRUE(savedInTheWindow) << "the debounced save did not run while the loop was watched";
}

// ── PLAT-17: git worktrees read refs from the common dir ──

TEST(GitWorktree, ShaAndUpstreamComeFromTheCommonDir) {
  QTemporaryDir tmp;
  const QString main = tmp.path() + "/main/.git";
  const QString wt = main + "/worktrees/feature";
  QDir().mkpath(main + "/refs/heads");
  QDir().mkpath(wt);
  const auto put = [](const QString& path, const QByteArray& bytes) {
    QFile f(path);
    ASSERT_TRUE(f.open(QIODevice::WriteOnly));
    f.write(bytes);
  };
  put(wt + "/commondir", "../..\n");
  put(wt + "/HEAD", "ref: refs/heads/feature\n");
  put(main + "/refs/heads/feature", "0123456789abcdef0123456789abcdef01234567\n");
  put(main + "/config", "[branch \"feature\"]\n\tremote = origin\n\tmerge = refs/heads/feature\n");

  const QString common = heap::git::BranchTaskMatcher::resolveCommonDir(wt);
  EXPECT_EQ(QDir(common).canonicalPath(), QDir(main).canonicalPath());
  EXPECT_EQ(heap::git::GitWatcher::readShaForBranch(common, "feature"), QStringLiteral("0123456789abcdef0123456789abcdef01234567"));
  EXPECT_EQ(heap::git::GitWatcher::upstreamForBranch(common, "feature"), QStringLiteral("origin/feature"));
  EXPECT_EQ(heap::git::BranchTaskMatcher::resolveCommonDir(main), main) << "a plain clone is its own common dir";
}

// ── PLAT-6 (2026-09-30-1): a damaged file is a banner, not a first run ──

TEST_F(StorageSafety, ADamagedFileWithNoBackupOpensAnEmptyWorkspaceUnderABanner) {
  const QByteArray damaged = stateDoc({profileJson("a", {taskJson("T-1", "todo")})}, "a").left(40);
  writeRaw(statePath(), damaged);
  {
    AppController app;
    const QStringList kept = corruptFiles();
    ASSERT_EQ(kept.size(), 1);
    EXPECT_EQ(readRaw(appDataDir() + "/" + kept.first()), damaged) << "the damaged bytes must be kept as they were";
    EXPECT_EQ(app.storageState(), QStringLiteral("damaged"));
    EXPECT_TRUE(app.storageMessage().contains(kept.first())) << app.storageMessage().toStdString();
    // Not a new install: no welcome tour, no demo board to work on in.
    EXPECT_TRUE(app.welcomeSeen());
    EXPECT_FALSE(app.demoActive());
    EXPECT_EQ(app.tasks()->rowCount(), 0);
    EXPECT_FALSE(app.statuses().isEmpty());
    app.dismissStorageNotice();
    EXPECT_EQ(app.storageState(), QStringLiteral("ok"));
    app.flushSave();
  }
  // The next launch opens the same empty workspace, not a first run either.
  AppController reopened;
  EXPECT_EQ(reopened.storageState(), QStringLiteral("ok"));
  EXPECT_TRUE(reopened.welcomeSeen());
  EXPECT_FALSE(reopened.demoActive());
  EXPECT_EQ(reopened.tasks()->rowCount(), 0);
  EXPECT_EQ(corruptFiles().size(), 1);
}

TEST_F(StorageSafety, ADamagedFileRestoredFromABackupSaysWhichOneAndStaysUp) {
  writeRaw(backupDir() + "/state-20260101-000000.json", stateDoc({profileJson("a", {taskJson("T-1", "todo")})}, "a"));
  writeRaw(statePath(), QByteArray("{ truncated"));
  AppController app;
  EXPECT_TRUE(hasTask(app, "T-1"));
  EXPECT_EQ(app.storageState(), QStringLiteral("recovered"));
  EXPECT_TRUE(app.storageMessage().contains(QStringLiteral("state-20260101-000000.json"))) << app.storageMessage().toStdString();
  ASSERT_EQ(corruptFiles().size(), 1);
  EXPECT_TRUE(app.storageMessage().contains(corruptFiles().first()));
  // An ordinary save does not take the notice down; only the user does.
  QVariantMap d = app.newTaskDraft(QStringLiteral("todo"));
  d["title"] = QStringLiteral("after");
  app.saveTask(d);
  app.flushSave();
  EXPECT_EQ(app.storageState(), QStringLiteral("recovered"));
}

// ── PLAT-9 (2026-09-30-1): a copied or imported profile gets its own task ids ──

TEST_F(StorageSafety, ADuplicatedProfileGetsFreshTaskIdsWithItsReferences) {
  QJsonObject blocker = taskJson("TASK-1", "todo");
  blocker["desc"] = QStringLiteral("see #TASK-2 and #TASK-20");
  blocker["links"] = QJsonArray{QJsonObject{{"type", "blocks"}, {"targetId", "TASK-2"}}};
  QJsonObject p = profileJson("a", {blocker, taskJson("TASK-2", "todo"), taskJson("TASK-20", "todo")});
  writeRaw(statePath(), stateDoc({p, profileJson("other", {taskJson("TASK-20", "todo")})}, "a"));
  AppController app;
  const QString copyId = app.duplicateProfile(QStringLiteral("a"), QStringLiteral("A copy"));
  ASSERT_FALSE(copyId.isEmpty());
  ASSERT_EQ(app.activeProfileId(), copyId);
  QSet<QString> ids;
  const Task* first = nullptr;
  for(const Task& t : app.tasks()->items()) {
    ids.insert(t.id);
    if(t.title == QStringLiteral("TASK-1 title")) {
      first = &t;
    }
  }
  ASSERT_EQ(ids.size(), 3);
  for(const char* shared : {"TASK-1", "TASK-2", "TASK-20"}) {
    EXPECT_FALSE(ids.contains(QString::fromLatin1(shared))) << shared << " is still shared with the original";
  }
  ASSERT_NE(first, nullptr);
  ASSERT_EQ(first->links.size(), 1);
  const QString newTwo = first->links.first().targetId;
  EXPECT_TRUE(ids.contains(newTwo)) << "the link must follow its target";
  EXPECT_TRUE(first->desc.contains(QStringLiteral("#") + newTwo)) << first->desc.toStdString();
  EXPECT_FALSE(first->desc.contains(QStringLiteral("#TASK-2 "))) << first->desc.toStdString();
  // A new task in the copy is not handed an id the copy just took either.
  EXPECT_FALSE(ids.contains(app.newTaskDraft(QStringLiteral("todo")).value("id").toString()));

  app.setActiveProfileId(QStringLiteral("a"));
  EXPECT_TRUE(hasTask(app, "TASK-1"));
  EXPECT_TRUE(hasTask(app, "TASK-2")) << "the original keeps its ids";
}

TEST_F(StorageSafety, AnImportedProfileNeverReusesATaskIdAndItsEventsFollow) {
  writeRaw(statePath(), stateDoc({profileJson("a", {taskJson("TASK-1", "todo")})}, "a"));
  AppController app;
  QJsonObject exported = profileJson("b", {taskJson("TASK-1", "todo"), taskJson("ZED-9", "todo")});
  exported["events"] = QJsonArray{
      QJsonObject{{"id", "ev-x"}, {"title", "pairing"}, {"date", "2026-09-30"}, {"start", 10}, {"end", 11}, {"taskId", "TASK-1"}}};
  ASSERT_TRUE(app.importProfileFromJson(QString::fromUtf8(QJsonDocument(QJsonObject{{"profile", exported}}).toJson())).isEmpty());
  EXPECT_FALSE(hasTask(app, "TASK-1")) << "the import took an id profile A holds";
  EXPECT_TRUE(hasTask(app, "ZED-9")) << "an id nobody holds is kept";
  QString renamed;
  for(const Task& t : app.tasks()->items()) {
    if(t.title == QStringLiteral("TASK-1 title")) {
      renamed = t.id;
    }
  }
  ASSERT_FALSE(renamed.isEmpty());
  bool sawEvent = false;
  for(const CalEvent& e : app.events()->items()) {
    if(e.title == QStringLiteral("pairing")) {
      sawEvent = true;
      EXPECT_EQ(e.taskId, renamed);
    }
  }
  EXPECT_TRUE(sawEvent);
}

}  // namespace

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
