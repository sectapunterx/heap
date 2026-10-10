// Regression tests for the 0.5.0 end-to-end audit (the tier list behind
// 0.5.1). Each test pins one defect the audit reproduced, named after the
// AppController method that carried it.
//
// The fixture is called AppController so the suite reads as the class under
// test; it lives in its own namespace and reaches the real class as
// ::AppController.

#include "AppController.h"
#include "Models.h"

#include "integrations/IntegrationTypes.h"
#include "integrations/SecretStore.h"

#include <QApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QVariantMap>

#include <gtest/gtest.h>

#include <memory>

namespace regression {

using heap::integrations::ExternalTask;

class AppController : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<::AppController>();
    app_->tasks()->reset({});
    app_->events()->reset({});
    app_->people()->reset({});
    app_->setLanguage(QStringLiteral("en"));
    // No tracker writes unless a test turns them on (APP-243).
    app_->setAppSettingsJson(QStringLiteral("{}"));
  }

  void TearDown() override {
    app_->setAppSettingsJson(QStringLiteral("{}"));
    app_.reset();
  }

  // One GitHub issue as a pull would hand it over.
  static ExternalTask issue(const QString& number, const QString& status, const QString& title = QStringLiteral("title")) {
    ExternalTask e;
    e.providerId = QStringLiteral("github");
    e.externalId = number;
    e.url = QStringLiteral("https://github.com/acme/app/issues/") + number;
    e.title = title;
    e.body = QStringLiteral("body");
    e.status = status;
    e.project = QStringLiteral("acme/app");
    return e;
  }

  const Task* task(const QString& id) const {
    const int row = app_->tasks()->indexOfId(id);
    return row >= 0 ? &app_->tasks()->items().at(row) : nullptr;
  }

  void merge(const QVector<ExternalTask>& issues, bool complete = false) {
    app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("gh-"), issues, complete);
  }

  static QVariantMap draftOf(const Task& t, bool isNew) {
    return {{"_isNew", isNew},
            {"_originalId", isNew ? QString() : t.id},
            {"id", t.id},
            {"title", t.title},
            {"desc", t.desc},
            {"priority", t.priority},
            {"status", t.status}};
  }

  static Task local(const QString& id, const QString& title) {
    Task t;
    t.id = id;
    t.title = title;
    t.status = QStringLiteral("todo");
    t.priority = QStringLiteral("P2");
    return t;
  }

  std::unique_ptr<::AppController> app_;
};

// ─── S1: sync must not reset working columns ───────────────────────────

TEST_F(AppController, MergeExternalTasks_RemoteStatusUnchanged_KeepsLocalColumn) {
  merge({issue(QStringLiteral("3"), QStringLiteral("open"))});
  ASSERT_NE(task(QStringLiteral("gh-3")), nullptr);
  Task t = *task(QStringLiteral("gh-3"));
  t.status = QStringLiteral("prog");  // the user dragged it
  app_->tasks()->upsert(t);

  merge({issue(QStringLiteral("3"), QStringLiteral("open"))});

  EXPECT_EQ(task(QStringLiteral("gh-3"))->status, QStringLiteral("prog"));
}

TEST_F(AppController, MergeExternalTasks_RemoteStatusChanged_TakesTrackerColumn) {
  // Only while heap writes this tracker: the move was (or would be) sent, so
  // a later move in the tracker is the newer word (APP-243).
  app_->setAppSettingsJson(QStringLiteral(R"({"integrations":{"github":{"writeStatus":true,"askBeforeWrite":false}}})"));
  merge({issue(QStringLiteral("3"), QStringLiteral("open"))});
  Task t = *task(QStringLiteral("gh-3"));
  t.status = QStringLiteral("prog");
  app_->tasks()->upsert(t);

  merge({issue(QStringLiteral("3"), QStringLiteral("closed"))});

  EXPECT_EQ(task(QStringLiteral("gh-3"))->status, QStringLiteral("done"));
}

// APP-243: with writes off (the default) a move is the user's own and no pull
// takes it back, whatever the tracker did meanwhile.
TEST_F(AppController, MergeExternalTasks_WritesOff_RemoteStatusChanged_KeepsLocalColumn) {
  merge({issue(QStringLiteral("3"), QStringLiteral("open"))});
  Task t = *task(QStringLiteral("gh-3"));
  t.status = QStringLiteral("prog");
  app_->tasks()->upsert(t);

  merge({issue(QStringLiteral("3"), QStringLiteral("closed"))});

  EXPECT_EQ(task(QStringLiteral("gh-3"))->status, QStringLiteral("prog"));
  EXPECT_TRUE(task(QStringLiteral("gh-3"))->externalMeta.conflicts.isEmpty());
  // The tracker's side is still known, for the tooltip and the editor.
  EXPECT_EQ(task(QStringLiteral("gh-3"))->externalMeta.status, QStringLiteral("closed"));
  EXPECT_EQ(task(QStringLiteral("gh-3"))->externalMeta.column, QStringLiteral("done"));
}

TEST_F(AppController, MergeExternalTasks_LegacyCardInOpenColumn_StaysWhileIssueOpen) {
  // A card from 0.5.0 carries no last-seen status.
  Task legacy = local(QStringLiteral("gh-4"), QStringLiteral("title"));
  legacy.status = QStringLiteral("blocked");
  legacy.externalId = QStringLiteral("4");
  legacy.externalProvider = QStringLiteral("github");
  legacy.externalUrl = QStringLiteral("https://github.com/acme/app/issues/4");
  app_->tasks()->reset({legacy});

  merge({issue(QStringLiteral("4"), QStringLiteral("open"))});

  EXPECT_EQ(task(QStringLiteral("gh-4"))->status, QStringLiteral("blocked"));
}

// ─── S2: local edits of a mirrored issue ───────────────────────────────

TEST_F(AppController, MergeExternalTasks_LocalTitleEditedRemoteUnchanged_KeepsLocalTitle) {
  merge({issue(QStringLiteral("7"), QStringLiteral("open"), QStringLiteral("upstream"))});
  Task t = *task(QStringLiteral("gh-7"));
  t.title = QStringLiteral("mine");
  t.desc = QStringLiteral("my notes");
  app_->tasks()->upsert(t);

  merge({issue(QStringLiteral("7"), QStringLiteral("open"), QStringLiteral("upstream"))});

  EXPECT_EQ(task(QStringLiteral("gh-7"))->title, QStringLiteral("mine"));
  EXPECT_EQ(task(QStringLiteral("gh-7"))->desc, QStringLiteral("my notes"));
}

TEST_F(AppController, MergeExternalTasks_RemoteTitleChangedLocalUntouched_TakesRemoteTitle) {
  merge({issue(QStringLiteral("7"), QStringLiteral("open"), QStringLiteral("first"))});

  merge({issue(QStringLiteral("7"), QStringLiteral("open"), QStringLiteral("second"))});

  EXPECT_EQ(task(QStringLiteral("gh-7"))->title, QStringLiteral("second"));
}

TEST_F(AppController, MergeExternalTasks_BothSidesChangedTitle_KeepsLocalAndCountsConflict) {
  merge({issue(QStringLiteral("7"), QStringLiteral("open"), QStringLiteral("first"))});
  Task t = *task(QStringLiteral("gh-7"));
  t.title = QStringLiteral("mine");
  app_->tasks()->upsert(t);

  const auto stats = app_->mergeExternalTasks(
      QStringLiteral("github"), QStringLiteral("gh-"), {issue(QStringLiteral("7"), QStringLiteral("open"), QStringLiteral("theirs"))});

  EXPECT_EQ(task(QStringLiteral("gh-7"))->title, QStringLiteral("mine"));
  EXPECT_EQ(stats.conflicts, 1);
}

// ─── A1: a refused push keeps the card where the user put it ───────────

TEST_F(AppController, MergeExternalTasks_UnsyncedLocalMove_KeepsLocalColumn) {
  merge({issue(QStringLiteral("8"), QStringLiteral("open"))});
  Task t = *task(QStringLiteral("gh-8"));
  t.status = QStringLiteral("done");
  t.externalMeta.unsyncedStatus = QStringLiteral("done");
  app_->tasks()->upsert(t);

  merge({issue(QStringLiteral("8"), QStringLiteral("open"))});

  EXPECT_EQ(task(QStringLiteral("gh-8"))->status, QStringLiteral("done"));
  EXPECT_TRUE(app_->taskById(QStringLiteral("gh-8")).value(QStringLiteral("ticket")).toMap().value(QStringLiteral("unsynced")).toBool());
}

// ─── A3: issues deleted upstream ───────────────────────────────────────

TEST_F(AppController, MergeExternalTasks_IssueMissingFromCompletePull_MarksCardGone) {
  merge({issue(QStringLiteral("2"), QStringLiteral("open")), issue(QStringLiteral("3"), QStringLiteral("open"))});

  const auto stats =
      app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("gh-"), {issue(QStringLiteral("3"), QStringLiteral("open"))}, true);

  EXPECT_EQ(stats.gone, 1);
  EXPECT_TRUE(task(QStringLiteral("gh-2"))->externalMeta.goneUpstream);
  EXPECT_FALSE(task(QStringLiteral("gh-3"))->externalMeta.goneUpstream);
}

TEST_F(AppController, MergeExternalTasks_IssueMissingFromPartialPull_LeavesCardAlone) {
  merge({issue(QStringLiteral("2"), QStringLiteral("open")), issue(QStringLiteral("3"), QStringLiteral("open"))});

  merge({issue(QStringLiteral("3"), QStringLiteral("open"))}, /*complete=*/false);

  EXPECT_FALSE(task(QStringLiteral("gh-2"))->externalMeta.goneUpstream);
}

TEST_F(AppController, MergeExternalTasks_GoneIssueReturns_ClearsTheMark) {
  merge({issue(QStringLiteral("2"), QStringLiteral("open"))});
  merge({}, /*complete=*/true);
  ASSERT_TRUE(task(QStringLiteral("gh-2"))->externalMeta.goneUpstream);

  merge({issue(QStringLiteral("2"), QStringLiteral("open"))});

  EXPECT_FALSE(task(QStringLiteral("gh-2"))->externalMeta.goneUpstream);
}

// ─── B4: focus blocks of a closed issue ────────────────────────────────

TEST_F(AppController, MergeExternalTasks_IssueClosedUpstream_DropsFutureFocusBlocks) {
  merge({issue(QStringLiteral("5"), QStringLiteral("open"))});
  CalEvent block;
  block.id = QStringLiteral("ev-focus");
  block.type = QStringLiteral("focus");
  block.taskId = QStringLiteral("gh-5");
  block.date = QDate::currentDate().addDays(1);
  block.start = 10.0;
  block.end = 11.5;
  app_->events()->upsert(block);

  merge({issue(QStringLiteral("5"), QStringLiteral("closed"))});

  EXPECT_LT(app_->events()->indexOfId(QStringLiteral("ev-focus")), 0);
}

// ─── S4: deleting a note ───────────────────────────────────────────────

TEST_F(AppController, DeleteNote_ThenUndo_RestoresTheNote) {
  const QString id = app_->newNote(QStringLiteral("Keep me"));
  app_->setNoteBody(id, QStringLiteral("# Keep me\n\nprecious text\n"));
  const int depth = app_->undoDepth();

  app_->deleteNote(id);
  ASSERT_LT(app_->notes()->indexOfId(id), 0);
  EXPECT_EQ(app_->undoDepth(), depth + 1);

  app_->undo();

  ASSERT_GE(app_->notes()->indexOfId(id), 0);
  EXPECT_EQ(app_->noteBody(id), QStringLiteral("# Keep me\n\nprecious text\n"));
}

// ─── S5: "Start fresh" ─────────────────────────────────────────────────

TEST_F(AppController, StartFresh_ThenUndo_RestoresTasksAndNotes) {
  app_->tasks()->reset({local(QStringLiteral("MY-1"), QStringLiteral("real work"))});
  const QString note = app_->newNote(QStringLiteral("mine"));

  app_->startFresh();
  ASSERT_EQ(app_->tasks()->rowCount(), 0);
  ASSERT_EQ(app_->notes()->rowCount(), 0);

  app_->undo();

  EXPECT_NE(task(QStringLiteral("MY-1")), nullptr);
  EXPECT_GE(app_->notes()->indexOfId(note), 0);
}

// ─── S6 / A9 / B7: saving a task ───────────────────────────────────────

TEST_F(AppController, SaveTask_EmptyIdOnExistingTask_KeepsOriginalId) {
  app_->tasks()->reset({local(QStringLiteral("APP-101"), QStringLiteral("title"))});
  QVariantMap d = draftOf(*task(QStringLiteral("APP-101")), false);
  d.insert("id", QString());

  EXPECT_TRUE(app_->saveTask(d));

  EXPECT_NE(task(QStringLiteral("APP-101")), nullptr);
  EXPECT_EQ(task(QString()), nullptr);
}

TEST_F(AppController, SaveTask_IdTakenInAnotherCase_ReturnsFalse) {
  app_->tasks()->reset({local(QStringLiteral("APP-104"), QStringLiteral("one"))});
  const QVariantMap d = draftOf(local(QStringLiteral("app-104"), QStringLiteral("two")), true);

  EXPECT_FALSE(app_->saveTask(d));

  EXPECT_EQ(app_->tasks()->rowCount(), 1);
}

TEST_F(AppController, SaveTask_EditBlanksTitle_ReturnsFalseAndKeepsTitle) {
  app_->tasks()->reset({local(QStringLiteral("APP-1"), QStringLiteral("title"))});
  QVariantMap d = draftOf(*task(QStringLiteral("APP-1")), false);
  d.insert("title", QStringLiteral("   "));

  EXPECT_FALSE(app_->saveTask(d));

  EXPECT_EQ(task(QStringLiteral("APP-1"))->title, QStringLiteral("title"));
}

TEST_F(AppController, SaveTask_UnknownPriorityAndStatus_KeepsTaskOnTheBoard) {
  app_->tasks()->reset({local(QStringLiteral("APP-1"), QStringLiteral("title"))});
  QVariantMap d = draftOf(*task(QStringLiteral("APP-1")), false);
  d.insert("priority", QStringLiteral("P9"));
  d.insert("status", QStringLiteral("nowhere"));

  EXPECT_TRUE(app_->saveTask(d));

  EXPECT_EQ(task(QStringLiteral("APP-1"))->priority, QStringLiteral("P2"));
  EXPECT_EQ(task(QStringLiteral("APP-1"))->status, QStringLiteral("todo"));
}

// ─── A6: undo covers edits ─────────────────────────────────────────────

TEST_F(AppController, SaveTask_EditThenUndo_RestoresPreviousTitle) {
  app_->tasks()->reset({local(QStringLiteral("APP-1"), QStringLiteral("before"))});
  QVariantMap d = draftOf(*task(QStringLiteral("APP-1")), false);
  d.insert("title", QStringLiteral("after"));
  ASSERT_TRUE(app_->saveTask(d));

  app_->undo();

  EXPECT_EQ(task(QStringLiteral("APP-1"))->title, QStringLiteral("before"));
}

TEST_F(AppController, SaveTask_StatusChangedToDone_GoesThroughMoveTask) {
  Task t = local(QStringLiteral("REC-2"), QStringLiteral("weekly report"));
  t.recurrence = QStringLiteral("every:week");
  t.dueAt = QDateTime(QDate::currentDate(), QTime(9, 0));
  app_->tasks()->reset({t});
  QVariantMap d = draftOf(t, false);
  d.insert("status", QStringLiteral("done"));

  ASSERT_TRUE(app_->saveTask(d));

  EXPECT_EQ(task(QStringLiteral("REC-2"))->status, QStringLiteral("done"));
  EXPECT_NE(task(QStringLiteral("REC-2-r1")), nullptr) << "a finished recurring task spawns its next one";
}

// ─── A2: bulk move goes through moveTask ───────────────────────────────

TEST_F(AppController, MoveSelectedTasksToStatus_RecurringTaskDone_SpawnsNextOccurrence) {
  Task t = local(QStringLiteral("REC-1"), QStringLiteral("standup notes"));
  t.recurrence = QStringLiteral("every:day");
  t.dueAt = QDateTime(QDate::currentDate(), QTime(9, 0));
  app_->tasks()->reset({t});
  app_->toggleTaskSelection(QStringLiteral("REC-1"));
  QSignalSpy undoable(app_.get(), &::AppController::undoableToast);

  app_->moveSelectedTasksToStatus(QStringLiteral("done"));

  EXPECT_EQ(task(QStringLiteral("REC-1"))->status, QStringLiteral("done"));
  EXPECT_NE(task(QStringLiteral("REC-1-r1")), nullptr);
  EXPECT_EQ(undoable.count(), 1);
}

// ─── B13 / A6: events ──────────────────────────────────────────────────

TEST_F(AppController, SaveEvent_UnsupportedRule_DropsItAndSaysSo) {
  QSignalSpy toasts(app_.get(), &::AppController::toast);
  app_->saveEvent({{"id", QStringLiteral("ev-bogus")},
                   {"title", QStringLiteral("standup")},
                   {"type", QStringLiteral("standup")},
                   {"start", 10.0},
                   {"end", 10.5},
                   {"date", QDate(2027, 1, 4)},
                   {"rrule", QStringLiteral("FREQ=BOGUS")}});

  const int row = app_->events()->indexOfId(QStringLiteral("ev-bogus"));
  ASSERT_GE(row, 0);
  EXPECT_TRUE(app_->events()->items().at(row).rrule.isEmpty());
  EXPECT_GE(toasts.count(), 1);
}

TEST_F(AppController, UpdateEvent_DragThenUndo_RestoresTheSlot) {
  app_->saveEvent({{"id", QStringLiteral("ev-drag")},
                   {"title", QStringLiteral("1:1")},
                   {"type", QStringLiteral("oneone")},
                   {"start", 10.0},
                   {"end", 11.0},
                   {"date", QDate(2027, 1, 4)}});
  app_->updateEvent(QStringLiteral("ev-drag"), 14.0, 15.0, QDate(2027, 1, 5));

  app_->undo();

  const CalEvent& e = app_->events()->items().at(app_->events()->indexOfId(QStringLiteral("ev-drag")));
  EXPECT_EQ(e.date, QDate(2027, 1, 4));
  EXPECT_DOUBLE_EQ(e.start, 10.0);
}

// ─── C6: names, long spans, working hours ─────────────────────────────

TEST_F(AppController, AddStatus_NameAlreadyUsed_IsRefused) {
  const int before = static_cast<int>(app_->statuses().size());
  app_->addStatus(QStringLiteral("done"), QString());  // "Done" exists, in another case
  EXPECT_EQ(static_cast<int>(app_->statuses().size()), before);
}

TEST_F(AppController, CreateProfile_NameAlreadyUsed_ReturnsEmpty) {
  const QString first = app_->createProfile(QStringLiteral("Twin"), QString());
  ASSERT_FALSE(first.isEmpty());
  EXPECT_TRUE(app_->createProfile(QStringLiteral("twin"), QString()).isEmpty());
  app_->deleteProfile(first);
}

TEST_F(AppController, ImportProfileFromJson_SameNameAsExisting_GetsASuffix) {
  const QString json = app_->exportActiveProfileJson();
  const QString activeName = app_->profiles().value(0).toMap().value(QStringLiteral("name")).toString();
  ASSERT_TRUE(app_->importProfileFromJson(json, false).isEmpty());
  const QString imported = app_->profiles().last().toMap().value(QStringLiteral("name")).toString();
  EXPECT_NE(imported.compare(activeName, Qt::CaseInsensitive), 0);
  EXPECT_TRUE(imported.endsWith(QStringLiteral(")"))) << imported.toStdString();
}

TEST_F(AppController, DeadlineDiffLabel_YearsOverdue_SpeaksInYears) {
  const QDate today = app_->today();
  EXPECT_EQ(app_->deadlineDiffLabel(today.addDays(-800)), QStringLiteral("2 yr overdue"));
  EXPECT_EQ(app_->deadlineDiffLabel(today.addDays(90)), QStringLiteral("in 3 mo"));
  EXPECT_EQ(app_->deadlineDiffLabel(today.addDays(-3)), QStringLiteral("3d overdue"));
}

TEST_F(AppController, SetWorkdayEnd_BeforeStart_AdjustsAndSaysSo) {
  app_->setWorkdayStart(9);
  QSignalSpy toasts(app_.get(), &::AppController::toast);
  app_->setWorkdayEnd(8);
  EXPECT_EQ(app_->workdayEnd(), 10);
  EXPECT_EQ(toasts.count(), 1);
}

// ─── S7: one backup per interval, across restarts ──────────────────────

TEST_F(AppController, FlushSave_RecentBackupFromEarlierRun_DoesNotCopyAgain) {
  app_->tasks()->reset({local(QStringLiteral("B-1"), QStringLiteral("x"))});
  app_->setAppSettingsJson(QStringLiteral("{\"data\":{\"backupInterval\":\"daily\"}}"));
  app_->flushSave();  // state.json exists from here on
  QDir backups(app_->dataDir() + QStringLiteral("/backups"));
  ASSERT_TRUE(backups.removeRecursively());
  ASSERT_TRUE(QDir().mkpath(backups.path()));
  const QString stamp = QDateTime::currentDateTime().addSecs(-3600).toString(QStringLiteral("yyyyMMdd-HHmmss"));
  QFile earlier(backups.filePath(QStringLiteral("state-") + stamp + QStringLiteral(".json")));
  ASSERT_TRUE(earlier.open(QFile::WriteOnly));
  earlier.write("{}");
  earlier.close();

  // A new process: nothing in memory says when the last copy was taken.
  app_.reset();
  app_ = std::make_unique<::AppController>();
  app_->setAppSettingsJson(QStringLiteral("{\"data\":{\"backupInterval\":\"daily\"}}"));
  app_->flushSave();

  EXPECT_EQ(backups.entryList({QStringLiteral("state-*.json")}, QDir::Files).size(), 1);
}

// ─── B8: the secrets.json fallback ─────────────────────────────────────

TEST(SecretStore, UnprotectFromFile_PlainValueFromOlderBuild_ReadsAsIs) {
  EXPECT_EQ(heap::integrations::SecretStore::unprotectFromFile(QStringLiteral("ghp_token")), QStringLiteral("ghp_token"));
}

TEST(SecretStore, ProtectForFile_RoundTrip_ReturnsTheValue) {
  const QString token = QStringLiteral("glpat-ÄÖ-токен-123");
  const QString stored = heap::integrations::SecretStore::protectForFile(token);
#ifdef Q_OS_WIN
  EXPECT_TRUE(stored.startsWith(QStringLiteral("dpapi:")));
  EXPECT_FALSE(stored.contains(token));
#endif
  EXPECT_EQ(heap::integrations::SecretStore::unprotectFromFile(stored), token);
}

}  // namespace regression

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
    QFile::remove(appData + QStringLiteral("/secrets.json"));
  }

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
