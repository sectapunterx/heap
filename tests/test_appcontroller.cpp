// Coverage for AppController's non-selection public logic: the rebindable
// shortcut catalog (set/reset/conflict/normalize), scheduleTask + its
// read-back, localized humanDate/shortDate, and the QVariant wrappers over
// the text/chrono helpers. Boots headless exactly like test_selection /
// test_notes: offscreen QPA + QStandardPaths test mode so nothing touches
// the real state.json.

#include "AppController.h"
#include "FakeHttpServer.h"
#include "Models.h"

#include "integrations/IntegrationTypes.h"

#include <QApplication>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QStringList>
#include <QTemporaryDir>
#include <QVariantMap>
#include <QVector>

#include <gtest/gtest.h>

namespace {

Task mkTask(const QString& id, const QString& title) {
  Task t;
  t.id = id;
  t.title = title;
  t.status = QStringLiteral("todo");
  t.priority = QStringLiteral("P2");
  return t;
}

}  // namespace

class AppControllerTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->tasks()->reset({});
    app_->events()->reset({});
    app_->setLanguage(QStringLiteral("en"));
    // AppController persists shortcut rebinds to the test-mode state.json, which
    // a prior test in this process may have written; restore the catalog to
    // defaults so every shortcut test starts from a known baseline.
    app_->resetAllShortcuts();
  }

  void TearDown() override {
    app_.reset();
  }

  // Integration config lives inside the appSettingsJson blob; these keep the
  // tests to the setting they care about.
  void writeIntegrationConfig(const QString& providerId, const QJsonObject& cfg) {
    QJsonObject settings = QJsonDocument::fromJson(app_->appSettingsJson().toUtf8()).object();
    QJsonObject integrations = settings.value(QStringLiteral("integrations")).toObject();
    integrations.insert(providerId, cfg);
    settings.insert(QStringLiteral("integrations"), integrations);
    app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(settings).toJson(QJsonDocument::Compact)));
  }

  QJsonObject readIntegrationConfig(const QString& providerId) const {
    return QJsonDocument::fromJson(app_->appSettingsJson().toUtf8())
        .object()
        .value(QStringLiteral("integrations"))
        .toObject()
        .value(providerId)
        .toObject();
  }

  std::unique_ptr<AppController> app_;
};

// ─── Shortcut catalog ─────────────────────────────────────────────────

TEST_F(AppControllerTest, SetShortcutSwapsConflictingOwner) {
  EXPECT_TRUE(app_->setShortcut(QStringLiteral("task.new"), QStringLiteral("Ctrl+K")));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.new")), QString("Ctrl+K"));
  // palette.open previously owned Ctrl+K → freed.
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("palette.open")), QString());
}

TEST_F(AppControllerTest, SetShortcutUnknownIdReturnsFalse) {
  EXPECT_FALSE(app_->setShortcut(QStringLiteral("no.such.id"), QStringLiteral("Ctrl+K")));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.new")), QString("Ctrl+N"));
}

TEST_F(AppControllerTest, SetShortcutSameSequenceIsNoopTrue) {
  EXPECT_TRUE(app_->setShortcut(QStringLiteral("task.new"), QStringLiteral("ctrl+n")));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.new")), QString("Ctrl+N"));
  // palette.open untouched.
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("palette.open")), QString("Ctrl+K"));
}

TEST_F(AppControllerTest, SetShortcutEmptyClearsWithoutSwapping) {
  EXPECT_TRUE(app_->setShortcut(QStringLiteral("task.new"), QString()));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.new")), QString());
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("palette.open")), QString("Ctrl+K"));
}

TEST_F(AppControllerTest, NormalizeTrimsAndCaseFolds) {
  EXPECT_TRUE(app_->setShortcut(QStringLiteral("task.new"), QStringLiteral("  ctrl+alt+j ")));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.new")), QString("Ctrl+Alt+J"));
}

TEST_F(AppControllerTest, ShortcutForUnknownIsEmpty) {
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("does.not.exist")), QString());
  EXPECT_EQ(app_->defaultShortcutFor(QStringLiteral("does.not.exist")), QString());
  EXPECT_EQ(app_->defaultShortcutFor(QStringLiteral("palette.open")), QString("Ctrl+K"));
}

TEST_F(AppControllerTest, FindShortcutConflict) {
  EXPECT_EQ(app_->findShortcutConflict(QStringLiteral("task.new"), QStringLiteral("Ctrl+K")), QString("palette.open"));
  // self excluded
  EXPECT_EQ(app_->findShortcutConflict(QStringLiteral("palette.open"), QStringLiteral("Ctrl+K")), QString());
  // normalized before compare
  EXPECT_EQ(app_->findShortcutConflict(QStringLiteral("task.new"), QStringLiteral("ctrl+k")), QString("palette.open"));
  // unbound combo
  EXPECT_EQ(app_->findShortcutConflict(QStringLiteral("task.new"), QStringLiteral("Ctrl+Alt+Shift+F12")), QString());
  // empty
  EXPECT_EQ(app_->findShortcutConflict(QStringLiteral("task.new"), QString()), QString());
}

TEST_F(AppControllerTest, ResetShortcutRestoresAndSwaps) {
  app_->setShortcut(QStringLiteral("task.new"), QStringLiteral("Ctrl+K"));  // frees palette.open
  app_->resetShortcut(QStringLiteral("palette.open"));                      // default Ctrl+K conflicts with task.new
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("palette.open")), QString("Ctrl+K"));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.new")), QString());  // swapped out
}

TEST_F(AppControllerTest, ResetShortcutAlreadyDefaultNoop) {
  app_->resetShortcut(QStringLiteral("view.board"));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("view.board")), QString("Ctrl+1"));
  app_->resetShortcut(QStringLiteral("unknown.id"));  // no crash
}

TEST_F(AppControllerTest, ResetAllShortcutsRestoresEveryEntry) {
  app_->setShortcut(QStringLiteral("task.new"), QStringLiteral("Ctrl+K"));
  app_->setShortcut(QStringLiteral("view.week"), QStringLiteral("Ctrl+9"));
  app_->resetAllShortcuts();
  const QVariantList cat = app_->shortcuts();
  ASSERT_FALSE(cat.isEmpty());
  for(const QVariant& v : cat) {
    const QVariantMap m = v.toMap();
    const QString id = m.value(QStringLiteral("id")).toString();
    EXPECT_EQ(app_->shortcutFor(id), app_->defaultShortcutFor(id)) << "id=" << id.toStdString();
  }
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.new")), QString("Ctrl+N"));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("palette.open")), QString("Ctrl+K"));
}

// ─── scheduleTask + read-back ─────────────────────────────────────────

TEST_F(AppControllerTest, ScheduleTaskCreatesFocusEvent) {
  app_->tasks()->reset({mkTask(QStringLiteral("T-1"), QStringLiteral("Fix login"))});
  app_->scheduleTask(QStringLiteral("T-1"), 14.5, QDate(2026, 5, 15));
  ASSERT_EQ(app_->events()->rowCount(), 1);
  const CalEvent& e = app_->events()->items().at(0);
  EXPECT_EQ(e.type, QString("focus"));
  EXPECT_EQ(e.taskId, QString("T-1"));
  EXPECT_DOUBLE_EQ(e.start, 14.5);
  EXPECT_DOUBLE_EQ(e.end, 15.5);
  EXPECT_EQ(e.profileId, app_->activeProfileId());
  EXPECT_EQ(app_->scheduledLabelFor(QStringLiteral("T-1"), QDate(2026, 5, 15)), QString("14:30"));
}

TEST_F(AppControllerTest, ScheduleTaskUnknownIdIsNoop) {
  app_->scheduleTask(QStringLiteral("ghost"), 9.0, QDate(2026, 5, 15));
  EXPECT_EQ(app_->events()->rowCount(), 0);
  EXPECT_EQ(app_->scheduledLabelFor(QStringLiteral("ghost"), QDate(2026, 5, 15)), QString());
}

TEST_F(AppControllerTest, ScheduledLabelPicksEarliest) {
  app_->tasks()->reset({mkTask(QStringLiteral("T-1"), QStringLiteral("x"))});
  app_->scheduleTask(QStringLiteral("T-1"), 14.0, QDate(2026, 5, 15));
  app_->scheduleTask(QStringLiteral("T-1"), 10.0, QDate(2026, 5, 15));
  EXPECT_EQ(app_->scheduledLabelFor(QStringLiteral("T-1"), QDate(2026, 5, 15)), QString("10:00"));
}

TEST_F(AppControllerTest, ScheduledLabelInvalidDateEmpty) {
  app_->tasks()->reset({mkTask(QStringLiteral("T-1"), QStringLiteral("x"))});
  EXPECT_EQ(app_->scheduledLabelFor(QStringLiteral("T-1"), QDate()), QString());
}

// ─── sync task ⇄ event cascade delete (HEAP-104) ──────────────────────

namespace {
// A QuickCapture "sync": one task plus one linked meeting event.
void seedSync(AppController* app, const QString& taskId) {
  app->tasks()->reset({mkTask(taskId, QStringLiteral("синк"))});
  app->events()->reset({});
  QVariantMap ev = app->newEventDraft(13.0, QDate(2026, 7, 13));
  ev["type"] = QStringLiteral("sync");
  ev["taskId"] = taskId;
  ev["title"] = QStringLiteral("синк");
  app->saveEvent(ev);
}
}  // namespace

TEST_F(AppControllerTest, DeleteTaskRemovesLinkedSyncEvent) {
  seedSync(app_.get(), QStringLiteral("SYNC-1"));
  ASSERT_EQ(app_->events()->rowCount(), 1);

  app_->deleteTask(QStringLiteral("SYNC-1"));
  EXPECT_EQ(app_->tasks()->rowCount(), 0);
  EXPECT_EQ(app_->events()->rowCount(), 0) << "the linked meeting event must go with the task";

  // Undo brings both halves back, still linked.
  app_->undoLastDeletion();
  ASSERT_EQ(app_->tasks()->rowCount(), 1);
  ASSERT_EQ(app_->events()->rowCount(), 1);
  EXPECT_EQ(app_->events()->items().at(0).taskId, QStringLiteral("SYNC-1"));
}

TEST_F(AppControllerTest, DeleteSyncEventRemovesMirrorTask) {
  seedSync(app_.get(), QStringLiteral("SYNC-1"));
  const QString evId = app_->events()->items().at(0).id;

  app_->deleteEvent(evId);
  EXPECT_EQ(app_->events()->rowCount(), 0);
  EXPECT_EQ(app_->tasks()->rowCount(), 0) << "the mirror task must go with the sync event";

  app_->undoLastDeletion();
  ASSERT_EQ(app_->tasks()->rowCount(), 1);
  ASSERT_EQ(app_->events()->rowCount(), 1);
  EXPECT_EQ(app_->tasks()->items().at(0).id, QStringLiteral("SYNC-1"));
}

TEST_F(AppControllerTest, DeleteFocusEventKeepsItsTask) {
  // A focus block is a scheduled slice of a task, not a mirror — deleting the
  // block just unschedules; the task stays.
  app_->tasks()->reset({mkTask(QStringLiteral("T-1"), QStringLiteral("x"))});
  app_->scheduleTask(QStringLiteral("T-1"), 14.0, QDate(2026, 7, 13));
  ASSERT_EQ(app_->events()->rowCount(), 1);
  ASSERT_EQ(app_->events()->items().at(0).type, QStringLiteral("focus"));

  app_->deleteEvent(app_->events()->items().at(0).id);
  EXPECT_EQ(app_->events()->rowCount(), 0);
  EXPECT_EQ(app_->tasks()->rowCount(), 1) << "a focus block must not delete its task";
}

TEST_F(AppControllerTest, DeleteTaskRemovesItsFocusBlock) {
  app_->tasks()->reset({mkTask(QStringLiteral("T-1"), QStringLiteral("x"))});
  app_->scheduleTask(QStringLiteral("T-1"), 14.0, QDate(2026, 7, 13));
  ASSERT_EQ(app_->events()->rowCount(), 1);

  app_->deleteTask(QStringLiteral("T-1"));
  EXPECT_EQ(app_->events()->rowCount(), 0) << "the focus block must go with the deleted task";
}

// ─── eventHourLabel (24h default) ─────────────────────────────────────

TEST_F(AppControllerTest, EventHourLabel24h) {
  EXPECT_EQ(app_->eventHourLabel(9.0), QString("09:00"));
  EXPECT_EQ(app_->eventHourLabel(14.5), QString("14:30"));
  EXPECT_EQ(app_->eventHourLabel(0.25), QString("00:15"));
}

// ─── humanDate / shortDate ────────────────────────────────────────────

TEST_F(AppControllerTest, HumanDateEnRu) {
  app_->setLanguage(QStringLiteral("en"));
  EXPECT_EQ(app_->humanDate(QDate(2026, 5, 15)), QString::fromUtf8("Friday, May 15"));
  EXPECT_EQ(app_->humanDate(QDate(2026, 1, 1)), QString::fromUtf8("Thursday, January 1"));
  app_->setLanguage(QStringLiteral("ru"));
  EXPECT_EQ(app_->humanDate(QDate(2026, 5, 15)), QString::fromUtf8("пятница, 15 мая"));
  EXPECT_EQ(app_->humanDate(QDate()), QString());
}

TEST_F(AppControllerTest, ShortDateEnRu) {
  app_->setLanguage(QStringLiteral("en"));
  EXPECT_EQ(app_->shortDate(QDate(2026, 5, 15)), QString::fromUtf8("Fri, 15 May"));
  app_->setLanguage(QStringLiteral("ru"));
  EXPECT_EQ(app_->shortDate(QDate(2026, 5, 15)), QString::fromUtf8("Пт, 15 май"));
  EXPECT_EQ(app_->shortDate(QDate()), QString());
}

// ─── parseDateTime wrapper key contract ───────────────────────────────

TEST_F(AppControllerTest, ParseDateTimeMapContract) {
  const QVariantMap m = app_->parseDateTime(QStringLiteral("tomorrow 15:00"), QDateTime(QDate(2026, 7, 2), QTime(9, 0)));
  for(const char* key : {"ok", "start", "end", "hasTime", "recurrence", "consumed", "startOffset", "endOffset"}) {
    EXPECT_TRUE(m.contains(QString::fromLatin1(key))) << "missing key " << key;
  }
  // Gibberish must not parse (locale-independent).
  EXPECT_FALSE(app_->parseDateTime(QStringLiteral("zzzz qqqq wwww"), QDateTime(QDate(2026, 7, 2), QTime(9, 0)))
                   .value(QStringLiteral("ok"))
                   .toBool());
}

// ─── classifyTaskKind enum→string mapping ─────────────────────────────

TEST_F(AppControllerTest, ClassifyTaskKindMapping) {
  EXPECT_EQ(app_->classifyTaskKind(QStringLiteral("focus mode tomorrow 9am")), QString("focus"));
  EXPECT_EQ(app_->classifyTaskKind(QStringLiteral("standup at 10")), QString("sync"));
  EXPECT_EQ(app_->classifyTaskKind(QString::fromUtf8("задача: подготовить синк")), QString("ticket"));
  EXPECT_EQ(app_->classifyTaskKind(QString::fromUtf8("написать @viktor про релиз")), QString("contact"));
  EXPECT_EQ(app_->classifyTaskKind(QString::fromUtf8("купить хлеб завтра в 18:00")), QString("none"));
  EXPECT_EQ(app_->classifyTaskKind(QString()), QString("none"));
}

// ─── extractTaskMeta wrapper shape ────────────────────────────────────

TEST_F(AppControllerTest, ExtractTaskMetaShape) {
  const QVariantMap m = app_->extractTaskMeta(QString::fromUtf8("напомни @andrey про PR"));
  EXPECT_TRUE(m.contains(QStringLiteral("title")));
  EXPECT_TRUE(m.contains(QStringLiteral("desc")));
  EXPECT_TRUE(m.contains(QStringLiteral("handles")));
  EXPECT_TRUE(m.value(QStringLiteral("handles")).toStringList().contains(QStringLiteral("andrey")));
  EXPECT_FALSE(m.value(QStringLiteral("title")).toString().isEmpty());

  const QVariantMap plain = app_->extractTaskMeta(QStringLiteral("plain text no handles"));
  EXPECT_TRUE(plain.value(QStringLiteral("handles")).toStringList().isEmpty());
}

// ─── Full-text command-palette entries (HEAP-80) ──────────────────────

TEST_F(AppControllerTest, CommandPaletteEntriesCarryBodyText) {
  // Seed a task whose search term lives only in the description, and a note
  // whose term lives only in the body; flush so the active profile picks both
  // up (commandPaletteEntries reads the profile snapshot).
  QVariantMap draft;
  draft["_isNew"] = true;
  draft["id"] = QStringLiteral("LTE-9001");
  draft["title"] = QStringLiteral("Quiet title");
  draft["desc"] = QStringLiteral("zebra hidden in the body");
  draft["priority"] = QStringLiteral("P2");
  draft["status"] = QStringLiteral("todo");
  app_->saveTask(draft);
  app_->setNotesState(QStringLiteral("a note mentioning platypus somewhere"));
  app_->flushSave();

  const QVariantList entries = app_->commandPaletteEntries();
  bool taskBodyOk = false;
  bool noteOk = false;
  for(const QVariant& v : entries) {
    const QVariantMap m = v.toMap();
    if(m.value("kind").toString() == QStringLiteral("task") && m.value("taskId").toString() == QStringLiteral("LTE-9001")) {
      // The term is absent from the label but present in the searchable body.
      EXPECT_FALSE(m.value("label").toString().contains(QStringLiteral("zebra")));
      EXPECT_TRUE(m.value("body").toString().contains(QStringLiteral("zebra")));
      taskBodyOk = true;
    }
    if(m.value("kind").toString() == QStringLiteral("note") && m.value("body").toString().contains(QStringLiteral("platypus"))) {
      noteOk = true;
    }
  }
  EXPECT_TRUE(taskBodyOk);
  EXPECT_TRUE(noteOk);
}

TEST_F(AppControllerTest, SnippetTagsAndLanguageReachPaletteBody) {
  // A snippet whose match term lives only in its tags / language must be
  // findable from the palette (HEAP-79 "first-class snippet library").
  const QString docs = QStringLiteral(
      "{\"sections\":[],\"contacts\":[],\"snippets\":["
      "{\"title\":\"Interactive rebase\",\"lang\":\"sh\",\"tags\":[\"git\",\"workflow\"],\"code\":\"git rebase -i\"}]}");
  app_->setDocsState(docs);
  app_->flushSave();

  bool ok = false;
  for(const QVariant& v : app_->commandPaletteEntries()) {
    const QVariantMap m = v.toMap();
    if(m.value("kind").toString() == QStringLiteral("snippet") && m.value("label").toString() == QStringLiteral("Interactive rebase")) {
      const QString body = m.value("body").toString();
      EXPECT_TRUE(body.contains(QStringLiteral("git")));       // tag
      EXPECT_TRUE(body.contains(QStringLiteral("workflow")));  // tag
      EXPECT_TRUE(body.contains(QStringLiteral("sh")));        // language
      ok = true;
    }
  }
  EXPECT_TRUE(ok);
}

// ─── Time tracking (HEAP-78) ──────────────────────────────────────────

TEST_F(AppControllerTest, TaskTimerStartStopAndSingleActive) {
  app_->tasks()->reset({mkTask(QStringLiteral("A"), QStringLiteral("a")), mkTask(QStringLiteral("B"), QStringLiteral("b"))});
  const auto timing = [&](const QString& id) {
    const int row = app_->tasks()->indexOfId(id);
    return app_->tasks()->data(app_->tasks()->index(row, 0), TaskModel::IsTimingRole).toBool();
  };

  app_->startTaskTimer(QStringLiteral("A"));
  EXPECT_TRUE(timing(QStringLiteral("A")));
  EXPECT_GE(app_->elapsedSecondsFor(QStringLiteral("A")), 0);

  // Only one timer runs at a time — starting B stops A.
  app_->startTaskTimer(QStringLiteral("B"));
  EXPECT_TRUE(timing(QStringLiteral("B")));
  EXPECT_FALSE(timing(QStringLiteral("A")));

  // Stopping clears the running flag.
  app_->stopTaskTimer(QStringLiteral("B"));
  EXPECT_FALSE(timing(QStringLiteral("B")));
}

// ─── Recurring tasks + templates (HEAP-77) ────────────────────────────

TEST_F(AppControllerTest, CompletingRecurringTaskSpawnsNext) {
  Task t = mkTask(QStringLiteral("REC-1"), QStringLiteral("Daily standup"));
  t.status = QStringLiteral("todo");
  t.recurrence = QStringLiteral("every:day");
  t.dueAt = QDateTime(QDate(2026, 7, 4), QTime(0, 0));
  t.scheduledAt = t.dueAt;
  app_->tasks()->reset({t});
  const int before = app_->tasks()->rowCount();

  app_->moveTask(QStringLiteral("REC-1"), QStringLiteral("done"));

  ASSERT_EQ(app_->tasks()->rowCount(), before + 1);
  bool foundNext = false;
  for(const Task& x : app_->tasks()->items()) {
    if(x.id != QStringLiteral("REC-1") && x.recurrence == QStringLiteral("every:day")) {
      EXPECT_EQ(x.status, QString("todo"));
      EXPECT_EQ(x.dueAt.date(), QDate(2026, 7, 5));  // next day
      foundNext = true;
    }
  }
  EXPECT_TRUE(foundNext);
}

// Regression (HEAP-104 review): a recurring task that is scheduled but was never
// given a due date must not gain a phantom midnight dueAt on its next
// occurrence. Otherwise runAutomation() fires an end-of-day reminder for a
// deadline the user never set, and the spurious dueAt is persisted forever.
TEST_F(AppControllerTest, RecurringScheduledOnlyTaskKeepsAnInvalidDueDate) {
  Task t = mkTask(QStringLiteral("REC-2"), QStringLiteral("Focus block"));
  t.status = QStringLiteral("todo");
  t.recurrence = QStringLiteral("every:day");
  t.scheduledAt = QDateTime(QDate(2026, 7, 4), QTime(9, 0));
  t.dueAt = QDateTime();  // scheduled, never owed
  app_->tasks()->reset({t});

  app_->moveTask(QStringLiteral("REC-2"), QStringLiteral("done"));

  bool foundNext = false;
  for(const Task& x : app_->tasks()->items()) {
    if(x.id != QStringLiteral("REC-2") && x.recurrence == QStringLiteral("every:day")) {
      foundNext = true;
      EXPECT_FALSE(x.dueAt.isValid()) << "recurrence manufactured a due date the task never had";
      EXPECT_EQ(x.scheduledAt, QDateTime(QDate(2026, 7, 5), QTime(9, 0))) << "the scheduled clock time must roll onto the next occurrence";
    }
  }
  EXPECT_TRUE(foundNext);
}

TEST_F(AppControllerTest, TemplateCreatesPrefilledChecklistTask) {
  ASSERT_FALSE(app_->taskTemplates().isEmpty());
  const int before = app_->tasks()->rowCount();

  app_->createTaskFromTemplate(QStringLiteral("PR review"));

  EXPECT_EQ(app_->tasks()->rowCount(), before + 1);
  bool found = false;
  for(const Task& x : app_->tasks()->items()) {
    if(x.title.startsWith(QStringLiteral("Review PR"))) {
      EXPECT_TRUE(x.desc.contains(QStringLiteral("- [ ]")));  // checklist markdown
      found = true;
    }
  }
  EXPECT_TRUE(found);
}

// ─── Git focus: prefix change re-matches the current branch ───────────

TEST_F(AppControllerTest, GitPrefixChangeRematchesFocusedBranch) {
  // Watched repo sitting on branch "HEAP-77-x". With prefix LTE the branch
  // carries no recognizable task id (77 is too short for the lone-digit rule);
  // switching the prefix to HEAP must make the banner pick it up WITHOUT any
  // HEAD movement. Regression: setPrefixes updated the matcher but never re-ran
  // the match on the branch already checked out, so the banner stayed stale
  // until the next checkout.
  QTemporaryDir repo;
  ASSERT_TRUE(repo.isValid());
  const QString gitDir = repo.path() + QStringLiteral("/.git");
  ASSERT_TRUE(QDir().mkpath(gitDir));
  {
    QFile head(gitDir + QStringLiteral("/HEAD"));
    ASSERT_TRUE(head.open(QIODevice::WriteOnly | QIODevice::Text));
    head.write("ref: refs/heads/HEAP-77-x\n");
  }
  const QString repoPath = QDir(repo.path()).absolutePath();

  const auto settings = [&](const QString& prefix) {
    const QJsonObject root{{"tasks", QJsonObject{{"idPrefix", prefix}}}, {"git", QJsonObject{{"watchedRepos", QJsonArray{repoPath}}}}};
    return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact));
  };

  app_->setAppSettingsJson(settings(QStringLiteral("LTE")));
  EXPECT_EQ(app_->focusedBranch(), QStringLiteral("HEAP-77-x"));
  EXPECT_EQ(app_->focusedTaskId(), QString());  // no match under LTE

  app_->setAppSettingsJson(settings(QStringLiteral("HEAP")));
  EXPECT_EQ(app_->focusedTaskId(), QStringLiteral("HEAP-77"));  // linked live

  app_->setAppSettingsJson(settings(QStringLiteral("LTE")));
  EXPECT_EQ(app_->focusedTaskId(), QString());  // un-match propagates too
}

// ─── headless boot ────────────────────────────────────────────────────

// ─── Time-aware save/edit (HEAP-115) ───

// The isNew guard used to drop the parsed clock time on every edit of an
// existing task. Editing one now keeps 09:00.
TEST_F(AppControllerTest, EditingAnExistingTaskKeepsTheParsedClockTime) {
  Task t = mkTask(QStringLiteral("EDIT-1"), QStringLiteral("standup"));
  t.scheduledAt = QDateTime(QDate(2026, 7, 10), QTime(0, 0));
  t.dueAt = t.scheduledAt;
  app_->tasks()->reset({t});

  QVariantMap draft = app_->taskById(QStringLiteral("EDIT-1"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("EDIT-1");
  draft["scheduledAt"] = QDateTime(QDate(2026, 7, 10), QTime(9, 0));
  draft["dueAt"] = QDateTime(QDate(2026, 7, 10), QTime(9, 0));
  draft["hasTime"] = true;
  app_->saveTask(draft);

  const int row = app_->tasks()->indexOfId(QStringLiteral("EDIT-1"));
  ASSERT_GE(row, 0);
  const Task& after = app_->tasks()->items().at(row);
  EXPECT_EQ(after.scheduledAt, QDateTime(QDate(2026, 7, 10), QTime(9, 0)));
  EXPECT_EQ(after.dueAt, QDateTime(QDate(2026, 7, 10), QTime(9, 0)));
  EXPECT_TRUE(after.hasTime);
}

// A caller that only knows a date (an old draft, an import) still works.
TEST_F(AppControllerTest, ALegacyDeadlineDraftKeyLandsAtMidnight) {
  QVariantMap draft = app_->newTaskDraft(QStringLiteral("todo"));
  draft["_isNew"] = true;
  draft["id"] = QStringLiteral("OLD-1");
  draft["title"] = QStringLiteral("bare date");
  draft["deadline"] = QDate(2026, 7, 8);
  app_->saveTask(draft);

  const int row = app_->tasks()->indexOfId(QStringLiteral("OLD-1"));
  ASSERT_GE(row, 0);
  const Task& t = app_->tasks()->items().at(row);
  EXPECT_EQ(t.dueAt, QDateTime(QDate(2026, 7, 8), QTime(0, 0)));
  EXPECT_FALSE(t.hasTime);
}

// snoozeDeadline shifts by whole days and keeps the clock time.
TEST_F(AppControllerTest, SnoozeShiftsBothDatetimesAndKeepsTheTime) {
  Task t = mkTask(QStringLiteral("SNZ-1"), QStringLiteral("ship"));
  t.dueAt = QDateTime(QDate(2026, 7, 10), QTime(16, 0));
  t.scheduledAt = t.dueAt;
  t.hasTime = true;
  app_->tasks()->reset({t});

  app_->snoozeDeadline(QStringLiteral("SNZ-1"), 3600);

  const Task& after = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("SNZ-1")));
  EXPECT_EQ(after.dueAt, QDateTime(QDate(2026, 7, 11), QTime(16, 0)));
  EXPECT_EQ(after.scheduledAt, QDateTime(QDate(2026, 7, 11), QTime(16, 0)));
}

// ─── Pulled labels (HEAP-124) ───

TEST_F(AppControllerTest, PulledIssueLabelsArePersistedOntoTheTask) {
  heap::integrations::ExternalTask issue;
  issue.providerId = QStringLiteral("github");
  issue.externalId = QStringLiteral("68");
  issue.url = QStringLiteral("https://github.com/sectapunterx/heap/issues/68");
  issue.title = QStringLiteral("Portable build misses a DLL");
  issue.status = QStringLiteral("open");
  issue.labels = {QStringLiteral("bug"), QStringLiteral("windows")};

  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});

  const int row = app_->tasks()->indexOfId(QStringLiteral("github-68"));
  ASSERT_GE(row, 0);
  const Task& t = app_->tasks()->items().at(row);
  ASSERT_EQ(t.labels.size(), 2);
  EXPECT_EQ(t.labels.at(0).id, QStringLiteral("bug"));
  EXPECT_EQ(t.labels.at(1).id, QStringLiteral("windows"));
  EXPECT_EQ(t.externalProvider, QStringLiteral("github"));

  // …and they survive a save/reload of the editor draft.
  QVariantMap draft = app_->taskById(QStringLiteral("github-68"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("github-68");
  app_->saveTask(draft);
  const Task& after = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-68")));
  ASSERT_EQ(after.labels.size(), 2);
  EXPECT_EQ(after.labels.at(0).id, QStringLiteral("bug"));
}

// Regression (HEAP-104 review): a label the user adds locally to a synced task
// must survive the next pull. Sync used to clear() every label and re-add only
// the tracker's, silently deleting user-authored chips on each sync.
TEST_F(AppControllerTest, SyncPreservesUserAddedLocalLabels) {
  heap::integrations::ExternalTask issue;
  issue.providerId = QStringLiteral("github");
  issue.externalId = QStringLiteral("68");
  issue.url = QStringLiteral("https://github.com/sectapunterx/heap/issues/68");
  issue.title = QStringLiteral("Portable build misses a DLL");
  issue.status = QStringLiteral("open");
  issue.labels = {QStringLiteral("bug")};

  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});

  // The user adds a local chip the tracker knows nothing about.
  QVariantMap draft = app_->taskById(QStringLiteral("github-68"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("github-68");
  draft["labels"] =
      QVariantList{QVariantMap{{QStringLiteral("id"), QStringLiteral("bug")}, {QStringLiteral("color"), QString()}},
                   QVariantMap{{QStringLiteral("id"), QStringLiteral("urgent")}, {QStringLiteral("color"), QStringLiteral("#e6624c")}}};
  app_->saveTask(draft);

  // A second sync of the same issue — the tracker still only reports "bug".
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});

  const Task& after = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-68")));
  QStringList ids;
  for(const Label& l : after.labels) {
    ids << l.id;
  }
  EXPECT_TRUE(ids.contains(QStringLiteral("urgent"))) << "sync wiped the user-added label";
  EXPECT_TRUE(ids.contains(QStringLiteral("bug")));
}

// ─── Cached hot paths ───
// Both of these are caches, so what needs pinning is not the speed but that
// they still answer correctly after the thing they cache has changed.

TEST_F(AppControllerTest, StatusCountsAreOnePassAndFollowTheModel) {
  Task a;
  a.id = QStringLiteral("A");
  a.status = QStringLiteral("todo");
  Task b;
  b.id = QStringLiteral("B");
  b.status = QStringLiteral("todo");
  Task c;
  c.id = QStringLiteral("C");
  c.status = QStringLiteral("prog");
  app_->tasks()->reset({a, b, c});

  QVariantMap counts = app_->statusCounts();
  EXPECT_EQ(counts.value(QStringLiteral("todo")).toInt(), 2);
  EXPECT_EQ(counts.value(QStringLiteral("prog")).toInt(), 1);
  // A status nobody holds is absent, and reads as zero.
  EXPECT_EQ(counts.value(QStringLiteral("done")).toInt(), 0);
  // countByStatus is now a lookup into the same map.
  EXPECT_EQ(app_->countByStatus(QStringLiteral("todo")), 2);
  EXPECT_EQ(app_->countByStatus(QStringLiteral("done")), 0);

  // Moving a task must be reflected, not served from the cache.
  app_->tasks()->setStatus(QStringLiteral("A"), QStringLiteral("prog"));
  EXPECT_EQ(app_->countByStatus(QStringLiteral("todo")), 1);
  EXPECT_EQ(app_->countByStatus(QStringLiteral("prog")), 2);

  // …as must adding, removing and replacing the whole model.
  Task d;
  d.id = QStringLiteral("D");
  d.status = QStringLiteral("todo");
  app_->tasks()->upsert(d);
  EXPECT_EQ(app_->countByStatus(QStringLiteral("todo")), 2);
  app_->tasks()->removeById(QStringLiteral("B"));
  EXPECT_EQ(app_->countByStatus(QStringLiteral("todo")), 1);
  app_->tasks()->reset({});
  EXPECT_EQ(app_->countByStatus(QStringLiteral("todo")), 0);
  EXPECT_TRUE(app_->statusCounts().isEmpty());
}

TEST_F(AppControllerTest, SettingsMapIsCachedButNeverStale) {
  app_->setAppSettingsJson(QStringLiteral(R"({"tasks":{"idPrefix":"AAA"}})"));
  EXPECT_EQ(app_->settingsMapForTest().value(QStringLiteral("tasks")).toMap().value(QStringLiteral("idPrefix")).toString(),
            QStringLiteral("AAA"));
  // Same string twice — the second read comes from the cache and must match.
  EXPECT_EQ(app_->settingsMapForTest(), app_->settingsMapForTest());

  app_->setAppSettingsJson(QStringLiteral(R"({"tasks":{"idPrefix":"BBB"}})"));
  EXPECT_EQ(app_->settingsMapForTest().value(QStringLiteral("tasks")).toMap().value(QStringLiteral("idPrefix")).toString(),
            QStringLiteral("BBB"))
      << "the cache outlived the settings it was built from";

  // Malformed and empty both answer an empty map rather than the last good one.
  app_->setAppSettingsJson(QStringLiteral("{not json"));
  EXPECT_TRUE(app_->settingsMapForTest().isEmpty());
  app_->setAppSettingsJson(QString());
  EXPECT_TRUE(app_->settingsMapForTest().isEmpty());
}

TEST_F(AppControllerTest, EstimateAndSomedayRoundTripThroughTheEditorDraft) {
  QVariantMap draft = app_->newTaskDraft(QStringLiteral("todo"));
  draft["_isNew"] = true;
  draft["id"] = QStringLiteral("EST-1");
  draft["title"] = QStringLiteral("plan the epic");
  draft["estimateMinutes"] = 480;
  draft["someday"] = true;
  draft["labels"] = QVariantList{QStringLiteral("infra")};
  app_->saveTask(draft);

  const Task& t = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("EST-1")));
  EXPECT_EQ(t.estimateMinutes, 480);
  EXPECT_TRUE(t.someday);
  ASSERT_EQ(t.labels.size(), 1);
  EXPECT_EQ(t.labels.at(0).id, QStringLiteral("infra"));
}

// A task saved as "someday" is filed under the backlog column, whatever status
// the editor sent — that is what the checkbox means (parked, not now).
TEST_F(AppControllerTest, SomedayTaskIsFiledUnderBacklog) {
  QVariantMap draft = app_->newTaskDraft(QStringLiteral("todo"));
  draft["_isNew"] = true;
  draft["id"] = QStringLiteral("SD-1");
  draft["title"] = QStringLiteral("park me");
  draft["status"] = QStringLiteral("prog");  // deliberately not backlog
  draft["someday"] = true;
  app_->saveTask(draft);

  const int row = app_->tasks()->indexOfId(QStringLiteral("SD-1"));
  ASSERT_GE(row, 0);
  const Task& t = app_->tasks()->items().at(row);
  EXPECT_EQ(t.status, QStringLiteral("backlog")) << "a someday task must land in the backlog";
  EXPECT_TRUE(t.someday);

  // Clearing someday leaves the status alone (no forced move back).
  QVariantMap edit = app_->taskById(QStringLiteral("SD-1"));
  edit["_isNew"] = false;
  edit["_originalId"] = QStringLiteral("SD-1");
  edit["status"] = QStringLiteral("todo");
  edit["someday"] = false;
  app_->saveTask(edit);
  const Task& t2 = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("SD-1")));
  EXPECT_FALSE(t2.someday);
  EXPECT_EQ(t2.status, QStringLiteral("todo")) << "un-parking must not force a column";
}

// The epic-level contract (HEAP-104): "review PR tomorrow 3pm" keeps its 3pm
// through capture, an edit of the existing task, save, reload and export.
TEST_F(AppControllerTest, ThreePmSurvivesCaptureEditSaveReloadAndExport) {
  const QDateTime reference(QDate(2026, 7, 9), QTime(10, 0));
  const QVariantMap parsed = app_->parseDateTime(QStringLiteral("review PR tomorrow 3pm"), reference);
  ASSERT_TRUE(parsed.value(QStringLiteral("ok")).toBool());
  ASSERT_TRUE(parsed.value(QStringLiteral("hasTime")).toBool());
  const QDateTime at = parsed.value(QStringLiteral("start")).toDateTime();
  ASSERT_EQ(at, QDateTime(QDate(2026, 7, 10), QTime(15, 0)));

  // Capture, exactly as QuickCapturePopup does.
  QVariantMap draft = app_->newQuickTaskDraft();
  draft["_isNew"] = true;
  draft["title"] = QStringLiteral("review PR");
  draft["scheduledAt"] = at;
  draft["dueAt"] = at;
  draft["hasTime"] = true;
  app_->saveTask(draft);
  const QString id = draft.value("id").toString();

  // Edit the existing task without touching the time (the old isNew guard's bug).
  QVariantMap edit = app_->taskById(id);
  edit["_isNew"] = false;
  edit["_originalId"] = id;
  edit["title"] = QStringLiteral("review PR (urgent)");
  app_->saveTask(edit);

  const Task& afterEdit = app_->tasks()->items().at(app_->tasks()->indexOfId(id));
  EXPECT_EQ(afterEdit.dueAt, at) << "the edit dropped the clock time";
  EXPECT_TRUE(afterEdit.hasTime);

  // Save, then reload from disk in a fresh controller.
  app_->flushSave();
  {
    AppController reloaded;
    const int row = reloaded.tasks()->indexOfId(id);
    ASSERT_GE(row, 0);
    const Task& t = reloaded.tasks()->items().at(row);
    EXPECT_EQ(t.dueAt, at) << "the clock time did not survive a reload";
    EXPECT_EQ(t.scheduledAt, at);
    EXPECT_TRUE(t.hasTime);
  }

  // Export carries it too.
  const QString exported = app_->exportActiveProfileJson();
  EXPECT_TRUE(exported.contains(QStringLiteral("2026-07-10T15:00:00"))) << exported.left(400).toStdString();
}

// ─── OAuth token refresh ──────────────────────────────────────────────
// The refresh token lives in the secret store but is not one of the card's
// secretKeys, so integrationConfig() never handed it to the refresh path: a
// browser-connected tracker went quiet at its first token expiry. Driven end to
// end against a local fake GitLab — the sync must spend the refresh token first
// and only then list issues, with the new access token.
TEST_F(AppControllerTest, ExpiredOAuthTokenIsRefreshedBeforeTheSync) {
  heap::testing::FakeHttpServer gitlab;
  gitlab.route("POST /oauth/token", {200, R"({"access_token":"at-new","refresh_token":"rt-new","expires_in":7200})", {}});
  gitlab.route("GET /api/v4/issues", {200, "[]", {}});

  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QStringLiteral("at-old"));
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken"), QStringLiteral("rt-old"));

  writeIntegrationConfig(QStringLiteral("gitlab"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("authMode"), QStringLiteral("oauth")},
                             {QStringLiteral("host"), gitlab.base()},
                             {QStringLiteral("clientId"), QStringLiteral("cid")},
                             {QStringLiteral("tokenExpiresAt"), QDateTime::currentDateTime().addSecs(-3600).toString(Qt::ISODate)},
                         });

  app_->syncProvider(QStringLiteral("gitlab"));
  ASSERT_TRUE(heap::testing::waitUntil([&gitlab]() {
    return gitlab.seen().contains("GET /api/v4/issues");
  })) << "the sync never reached the issue list";

  ASSERT_EQ(gitlab.seen().value(0), QByteArray("POST /oauth/token")) << "the expired token was used without a refresh";
  const QByteArray form = gitlab.lastRequest("POST /oauth/token").body;
  EXPECT_TRUE(form.contains("grant_type=refresh_token")) << form.toStdString();
  EXPECT_TRUE(form.contains("refresh_token=rt-old")) << form.toStdString();
  EXPECT_EQ(gitlab.lastRequest("GET /api/v4/issues").headers.value("authorization"), QByteArray("Bearer at-new"));

  // Rotated: both halves of the new grant are what the next run will load.
  EXPECT_EQ(app_->integrationSecret(QStringLiteral("gitlab"), QStringLiteral("token")), QStringLiteral("at-new"));
  EXPECT_EQ(app_->integrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken")), QStringLiteral("rt-new"));

  // Leave nothing behind for the suites sharing this test-mode profile.
  writeIntegrationConfig(QStringLiteral("gitlab"), QJsonObject{});
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QString());
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken"), QString());
}

// The mirror image, and the one that fails silently. Atlassian now forces
// rotation on every new 3LO app, but Bitbucket and ClickUp answer a refresh
// with an access token and no refresh_token at all. SecretStore::setValue
// deletes a key when handed an empty string, so writing the parsed value
// unconditionally would wipe the credential that keeps the grant alive — the
// card would work until the next expiry and then be unrecoverable without a
// fresh browser sign-in.
TEST_F(AppControllerTest, ARefreshThatReturnsNoNewRefreshTokenKeepsTheOldOne) {
  heap::testing::FakeHttpServer gitlab;
  gitlab.route("POST /oauth/token", {200, R"({"access_token":"at-new","expires_in":7200})", {}});
  gitlab.route("GET /api/v4/issues", {200, "[]", {}});

  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QStringLiteral("at-old"));
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken"), QStringLiteral("rt-keep"));

  writeIntegrationConfig(QStringLiteral("gitlab"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("authMode"), QStringLiteral("oauth")},
                             {QStringLiteral("host"), gitlab.base()},
                             {QStringLiteral("clientId"), QStringLiteral("cid")},
                             {QStringLiteral("tokenExpiresAt"), QDateTime::currentDateTime().addSecs(-3600).toString(Qt::ISODate)},
                         });

  app_->syncProvider(QStringLiteral("gitlab"));
  ASSERT_TRUE(heap::testing::waitUntil([&gitlab]() {
    return gitlab.seen().contains("GET /api/v4/issues");
  })) << "the sync never reached the issue list";

  EXPECT_EQ(gitlab.lastRequest("GET /api/v4/issues").headers.value("authorization"), QByteArray("Bearer at-new"));
  EXPECT_EQ(app_->integrationSecret(QStringLiteral("gitlab"), QStringLiteral("token")), QStringLiteral("at-new"));
  EXPECT_EQ(app_->integrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken")), QStringLiteral("rt-keep"))
      << "the silent half of the grant was cleared, leaving the next expiry nothing to spend";

  writeIntegrationConfig(QStringLiteral("gitlab"), QJsonObject{});
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QString());
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken"), QString());
}

// A rotated refresh token is single-use, and Sentry in particular rotates with
// no grace period: spending the same one twice does not merely fail the second
// call, it invalidates the grant and logs the user out for good. Two syncs
// landing together on an expired token must therefore produce exactly one
// token request.
TEST_F(AppControllerTest, TwoSyncsRacingAnExpiredTokenSpendTheRefreshTokenOnce) {
  heap::testing::FakeHttpServer gitlab;
  gitlab.route("POST /oauth/token", {200, R"({"access_token":"at-new","refresh_token":"rt-new","expires_in":7200})", {}});
  gitlab.route("GET /api/v4/issues", {200, "[]", {}});

  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QStringLiteral("at-old"));
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken"), QStringLiteral("rt-old"));
  writeIntegrationConfig(QStringLiteral("gitlab"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("authMode"), QStringLiteral("oauth")},
                             {QStringLiteral("host"), gitlab.base()},
                             {QStringLiteral("clientId"), QStringLiteral("cid")},
                             {QStringLiteral("tokenExpiresAt"), QDateTime::currentDateTime().addSecs(-3600).toString(Qt::ISODate)},
                         });

  // Back to back, before the first refresh can have answered.
  app_->syncProvider(QStringLiteral("gitlab"));
  app_->syncProvider(QStringLiteral("gitlab"));

  ASSERT_TRUE(heap::testing::waitUntil([&gitlab]() {
    return gitlab.seen().contains("GET /api/v4/issues");
  })) << "the sync never reached the issue list";

  int refreshes = 0;
  for(const QByteArray& seen : gitlab.seen()) {
    refreshes += seen == "POST /oauth/token" ? 1 : 0;
  }
  EXPECT_EQ(refreshes, 1) << "the same refresh token was spent twice, which kills the grant outright";

  writeIntegrationConfig(QStringLiteral("gitlab"), QJsonObject{});
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QString());
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken"), QString());
}

// ─── Required fields after a browser sign-in ──────────────────────────
// Signing in proves who you are, not what to sync, so the scope fields stay
// empty and the card says so. But Trello's "API key" is not a scope field at
// all: it is the app's own client ID, which makeBespokeProvider substitutes
// from the baked credential. Listing it as missing sent the user hunting for a
// value they cannot obtain, on a card that already syncs.

TEST_F(AppControllerTest, ABrowserSignInStillAsksForTheFieldsThatSayWhatToSync) {
  app_->setIntegrationSecret(QStringLiteral("sentry"), QStringLiteral("token"), QStringLiteral("at"));
  writeIntegrationConfig(QStringLiteral("sentry"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("authMode"), QStringLiteral("oauth")},
                         });

  const QStringList missing = app_->missingRequiredFields(QStringLiteral("sentry"));
  EXPECT_TRUE(missing.contains(QStringLiteral("Org slug"))) << missing.join(QStringLiteral(", ")).toStdString();
  EXPECT_TRUE(missing.contains(QStringLiteral("Project slug"))) << missing.join(QStringLiteral(", ")).toStdString();

  writeIntegrationConfig(QStringLiteral("sentry"), QJsonObject{});
  app_->setIntegrationSecret(QStringLiteral("sentry"), QStringLiteral("token"), QString());
}

TEST_F(AppControllerTest, TrelloDoesNotAskForAnApiKeyTheBrowserSignInAlreadySupplied) {
  app_->setIntegrationSecret(QStringLiteral("trello"), QStringLiteral("token"), QStringLiteral("tok"));
  writeIntegrationConfig(QStringLiteral("trello"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("authMode"), QStringLiteral("oauth")},
                         });

  EXPECT_FALSE(app_->missingRequiredFields(QStringLiteral("trello")).contains(QStringLiteral("API key")))
      << "the app key is the build's own, not something the user can type";

  // Pasting a personal token instead is the other path, and there the key is
  // genuinely the user's to provide.
  writeIntegrationConfig(QStringLiteral("trello"), QJsonObject{{QStringLiteral("connected"), true}});
  EXPECT_TRUE(app_->missingRequiredFields(QStringLiteral("trello")).contains(QStringLiteral("API key")));

  writeIntegrationConfig(QStringLiteral("trello"), QJsonObject{});
  app_->setIntegrationSecret(QStringLiteral("trello"), QStringLiteral("token"), QString());
}

// ─── Disconnect / auth mode ───────────────────────────────────────────
// authMode=oauth used to survive a disconnect, so a personal access token
// pasted afterwards was still sent as a Bearer — which GitLab (PRIVATE-TOKEN)
// and ClickUp (raw Authorization) both reject.

TEST_F(AppControllerTest, DisconnectingABrowserSessionDropsItsTokens) {
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QStringLiteral("at"));
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken"), QStringLiteral("rt"));
  writeIntegrationConfig(QStringLiteral("gitlab"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("authMode"), QStringLiteral("oauth")},
                             {QStringLiteral("tokenExpiresAt"), QStringLiteral("2026-01-01T00:00:00")},
                         });

  app_->disconnectIntegration(QStringLiteral("gitlab"));

  const QJsonObject cfg = readIntegrationConfig(QStringLiteral("gitlab"));
  EXPECT_FALSE(cfg.value(QStringLiteral("connected")).toBool());
  EXPECT_FALSE(cfg.contains(QStringLiteral("authMode"))) << "a stale authMode makes the next PAT go out as a Bearer";
  EXPECT_FALSE(cfg.contains(QStringLiteral("tokenExpiresAt")));
  EXPECT_TRUE(app_->integrationSecret(QStringLiteral("gitlab"), QStringLiteral("token")).isEmpty());
  EXPECT_TRUE(app_->integrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken")).isEmpty());

  writeIntegrationConfig(QStringLiteral("gitlab"), QJsonObject{});
}

TEST_F(AppControllerTest, DisconnectingATokenCardKeepsTheUsersOwnToken) {
  // A PAT is the user's credential, not one this app obtained — reconnecting
  // must not mean pasting it again.
  app_->setIntegrationSecret(QStringLiteral("todoist"), QStringLiteral("token"), QStringLiteral("mine"));
  writeIntegrationConfig(QStringLiteral("todoist"), QJsonObject{{QStringLiteral("connected"), true}});

  app_->disconnectIntegration(QStringLiteral("todoist"));

  EXPECT_FALSE(readIntegrationConfig(QStringLiteral("todoist")).value(QStringLiteral("connected")).toBool());
  EXPECT_EQ(app_->integrationSecret(QStringLiteral("todoist"), QStringLiteral("token")), QStringLiteral("mine"));

  app_->setIntegrationSecret(QStringLiteral("todoist"), QStringLiteral("token"), QString());
  writeIntegrationConfig(QStringLiteral("todoist"), QJsonObject{});
}

TEST_F(AppControllerTest, PastingATokenOverABrowserSessionEndsThatSession) {
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QStringLiteral("at"));
  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken"), QStringLiteral("rt"));
  writeIntegrationConfig(QStringLiteral("gitlab"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("authMode"), QStringLiteral("oauth")},
                             {QStringLiteral("tokenExpiresAt"), QStringLiteral("2026-01-01T00:00:00")},
                         });

  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QStringLiteral("glpat-mine"));

  const QJsonObject cfg = readIntegrationConfig(QStringLiteral("gitlab"));
  EXPECT_FALSE(cfg.contains(QStringLiteral("authMode")));
  EXPECT_TRUE(cfg.value(QStringLiteral("connected")).toBool()) << "the card stays connected, just on the PAT";
  EXPECT_TRUE(app_->integrationSecret(QStringLiteral("gitlab"), QStringLiteral("refreshToken")).isEmpty())
      << "the old grant's refresh token is dead weight";

  app_->setIntegrationSecret(QStringLiteral("gitlab"), QStringLiteral("token"), QString());
  writeIntegrationConfig(QStringLiteral("gitlab"), QJsonObject{});
}

TEST_F(AppControllerTest, CatalogFlagsWhichProvidersCanDoOneClick) {
  // Built without the CI credentials, so every provider that refuses a public
  // client must report itself as not one-click — otherwise the card offers a
  // button whose token exchange is guaranteed to fail.
  const QVariantList catalog = app_->integrationCatalog();
  ASSERT_FALSE(catalog.isEmpty());
  int checked = 0;
  QVariantMap sentry;
  for(const QVariant& entry : catalog) {
    const QVariantMap m = entry.toMap();
    if(m.value(QStringLiteral("id")).toString() == QStringLiteral("sentry")) {
      sentry = m;
    }
    if(!m.value(QStringLiteral("oauthNeedsSecret")).toBool()) {
      continue;
    }
    ++checked;
    EXPECT_FALSE(m.value(QStringLiteral("oauthReady")).toBool()) << m.value(QStringLiteral("id")).toString().toStdString();
    EXPECT_TRUE(m.value(QStringLiteral("oauth")).toBool()) << m.value(QStringLiteral("id")).toString().toStdString();
  }
  EXPECT_GE(checked, 4) << "todoist, asana, clickup and bitbucket all need a secret";

  // Sentry is the counterexample, and the whole point of registering it as a
  // public client: no secret exists to ship, PKCE stands in for one, and the
  // client ID is committed — so even this build, which has no CI credentials
  // at all, must still offer one-click sign-in. This fails if Sentry is moved
  // back to a confidential app, and if the committed client ID is dropped.
  ASSERT_FALSE(sentry.isEmpty());
  EXPECT_FALSE(sentry.value(QStringLiteral("oauthNeedsSecret")).toBool());
  EXPECT_TRUE(sentry.value(QStringLiteral("oauthReady")).toBool())
      << "a public client needs no secret, so a plain build must still offer the button";
}

// ─── Mattermost contact merge ─────────────────────────────────────────
// Imported people land in the Docs contact list, and the ones actually talked
// to also in the People rail. The rules that matter: never clobber an edit of
// the user's, never resurrect something they deleted, and never churn the docs
// blob when nothing changed.

namespace {

heap::integrations::ExternalContact mkContact(
    const QString& id, const QString& username, const QString& name, const QString& role, const QString& where) {
  heap::integrations::ExternalContact c;
  c.providerId = QStringLiteral("mattermost");
  c.externalId = id;
  c.username = username;
  c.displayName = name;
  c.role = role;
  c.channelLabel = where;
  return c;
}

const QString kDm = QStringLiteral("direct message");

}  // namespace

class ContactMergeTest : public AppControllerTest {
 protected:
  void SetUp() override {
    AppControllerTest::SetUp();
    app_->setDocsState(QString());
    writeIntegrationConfig(QStringLiteral("mattermost"), QJsonObject{});
  }

  QJsonArray contacts() const {
    return QJsonDocument::fromJson(app_->docsState().toUtf8()).object().value(QStringLiteral("contacts")).toArray();
  }

  QJsonObject contactNamed(const QString& name) const {
    const QJsonArray list = contacts();
    for(const auto& v : list) {
      if(v.toObject().value(QStringLiteral("name")).toString() == name) {
        return v.toObject();
      }
    }
    return {};
  }

  int merge(const QVector<heap::integrations::ExternalContact>& c) {
    return app_->mergeExternalContacts(QStringLiteral("mattermost"), c);
  }
};

TEST_F(ContactMergeTest, ImportsAContactAndLinksAPersonForDirectMessages) {
  const int changed =
      merge({mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga Titova"), QStringLiteral("Tech Lead"), kDm)});
  EXPECT_EQ(changed, 1);

  const QJsonObject c = contactNamed(QStringLiteral("Olga Titova"));
  EXPECT_EQ(c.value(QStringLiteral("role")).toString(), QStringLiteral("Tech Lead"));
  EXPECT_EQ(c.value(QStringLiteral("mattermost")).toString(), QStringLiteral("@olga.t"));
  EXPECT_EQ(c.value(QStringLiteral("mmId")).toString(), QStringLiteral("u1"));
  EXPECT_EQ(c.value(QStringLiteral("source")).toString(), QStringLiteral("mattermost"));
  EXPECT_FALSE(c.value(QStringLiteral("color")).toString().isEmpty());

  // The id is the handle itself, so "@olga.t" in heap matches Mattermost —
  // slugifyPersonName would have produced "olgat".
  EXPECT_EQ(c.value(QStringLiteral("personId")).toString(), QStringLiteral("olga.t"));
  const int row = app_->people()->indexOfId(QStringLiteral("olga.t"));
  ASSERT_GE(row, 0);
  const Person& p = app_->people()->items().at(row);
  EXPECT_EQ(p.name, QStringLiteral("Olga Titova"));
  EXPECT_EQ(p.role, QStringLiteral("Tech Lead"));
  EXPECT_EQ(p.state, QStringLiteral("idle")) << "an import is not a list of people you owe an answer to";
}

TEST_F(ContactMergeTest, AChannelRosterStaysOutOfTheRail) {
  const int before = app_->people()->rowCount();
  merge({mkContact(
      QStringLiteral("u2"), QStringLiteral("pavel"), QStringLiteral("Pavel K"), QStringLiteral("Member"), QStringLiteral("#backend"))});
  EXPECT_FALSE(contactNamed(QStringLiteral("Pavel K")).isEmpty()) << "still a contact";
  EXPECT_EQ(app_->people()->rowCount(), before) << "but not someone you have talked to";
  EXPECT_EQ(contactNamed(QStringLiteral("Pavel K")).value(QStringLiteral("channel")).toString(), QStringLiteral("#backend"));
}

TEST_F(ContactMergeTest, ReSyncingUnchangedDataWritesNothing) {
  const QVector<heap::integrations::ExternalContact> same = {
      mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga Titova"), QStringLiteral("Tech Lead"), kDm)};
  ASSERT_EQ(merge(same), 1);
  const QString after = app_->docsState();

  QSignalSpy spy(app_.get(), &AppController::docsStateChanged);
  EXPECT_EQ(merge(same), 0);
  EXPECT_EQ(spy.count(), 0) << "an idempotent sync must not churn the docs blob";
  EXPECT_EQ(app_->docsState(), after);
}

TEST_F(ContactMergeTest, AnEditOfYourOwnSurvivesButUpstreamChangesStillArrive) {
  merge({mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga Titova"), QStringLiteral("Tech Lead"), kDm)});

  // The user renames the role by hand.
  QJsonObject docs = QJsonDocument::fromJson(app_->docsState().toUtf8()).object();
  QJsonArray list = docs.value(QStringLiteral("contacts")).toArray();
  QJsonObject c = list.at(0).toObject();
  c.insert(QStringLiteral("role"), QStringLiteral("my tech lead"));
  list.replace(0, c);
  docs.insert(QStringLiteral("contacts"), list);
  app_->setDocsState(QString::fromUtf8(QJsonDocument(docs).toJson(QJsonDocument::Compact)));

  // Upstream, both the title and the name change.
  merge({mkContact(
      QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga Titova-Smirnova"), QStringLiteral("Engineering Manager"), kDm)});

  const QJsonObject after = contacts().at(0).toObject();
  EXPECT_EQ(after.value(QStringLiteral("role")).toString(), QStringLiteral("my tech lead")) << "the user's own words win";
  EXPECT_EQ(after.value(QStringLiteral("name")).toString(), QStringLiteral("Olga Titova-Smirnova"))
      << "a field the user never touched still follows the server";
}

TEST_F(ContactMergeTest, ADeletedContactDoesNotComeBack) {
  const QVector<heap::integrations::ExternalContact> one = {
      mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga Titova"), QStringLiteral("Tech Lead"), kDm)};
  ASSERT_EQ(merge(one), 1);

  app_->dismissExternalContact(QStringLiteral("mattermost"), QStringLiteral("u1"));
  app_->setDocsState(QStringLiteral(R"({"contacts":[]})"));

  EXPECT_EQ(merge(one), 0);
  EXPECT_TRUE(contacts().isEmpty());

  // Undoing the deletion puts it back in scope.
  app_->restoreExternalContact(QStringLiteral("mattermost"), QStringLiteral("u1"));
  EXPECT_EQ(merge(one), 1);
  EXPECT_EQ(contacts().size(), 1);
}

TEST_F(ContactMergeTest, ADeletedPersonIsNotRecreated) {
  const QVector<heap::integrations::ExternalContact> one = {
      mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga Titova"), QStringLiteral("Tech Lead"), kDm)};
  ASSERT_EQ(merge(one), 1);
  ASSERT_GE(app_->people()->indexOfId(QStringLiteral("olga.t")), 0);

  app_->deletePerson(QStringLiteral("olga.t"));
  ASSERT_LT(app_->people()->indexOfId(QStringLiteral("olga.t")), 0);

  merge(one);
  EXPECT_LT(app_->people()->indexOfId(QStringLiteral("olga.t")), 0)
      << "the contact keeps its personId, so the rail entry is not rebuilt behind the user's back";
}

TEST_F(ContactMergeTest, AContactTypedByHandIsAdoptedRatherThanDuplicated) {
  // Someone who filled in the Mattermost handle before the integration existed.
  app_->setDocsState(QStringLiteral(R"({"contacts":[{"name":"Olga","role":"","channel":"","mattermost":"@Olga.T"}]})"));

  merge({mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga Titova"), QStringLiteral("Tech Lead"), kDm)});

  ASSERT_EQ(contacts().size(), 1) << "matched on the handle, case-insensitively";
  const QJsonObject c = contacts().at(0).toObject();
  EXPECT_EQ(c.value(QStringLiteral("mmId")).toString(), QStringLiteral("u1"));
  EXPECT_EQ(c.value(QStringLiteral("name")).toString(), QStringLiteral("Olga")) << "their own name for the person is kept";
  EXPECT_EQ(c.value(QStringLiteral("role")).toString(), QStringLiteral("Tech Lead")) << "an empty field is filled in";
}

TEST_F(ContactMergeTest, AutoSyncIntoAnUnboundProfileIsANoop) {
  // The first sync binds the card to the profile it ran in.
  ASSERT_EQ(merge({mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga"), QString(), kDm)}), 1);
  EXPECT_EQ(readIntegrationConfig(QStringLiteral("mattermost")).value(QStringLiteral("profileId")).toString(), app_->activeProfileId());

  // A timer firing while another workspace is open must not pour colleagues into it.
  QJsonObject cfg = readIntegrationConfig(QStringLiteral("mattermost"));
  cfg.insert(QStringLiteral("profileId"), QStringLiteral("some-other-profile"));
  writeIntegrationConfig(QStringLiteral("mattermost"), cfg);

  EXPECT_EQ(merge({mkContact(QStringLiteral("u2"), QStringLiteral("pavel"), QStringLiteral("Pavel"), QString(), kDm)}), 0);
  EXPECT_TRUE(contactNamed(QStringLiteral("Pavel")).isEmpty());
}

TEST_F(ContactMergeTest, ImportingDoesNotInflateThePendingCount) {
  const int before = app_->pendingPeopleCount();
  merge({mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga"), QString(), kDm),
         mkContact(QStringLiteral("u2"), QStringLiteral("pavel"), QStringLiteral("Pavel"), QString(), kDm)});
  ASSERT_GE(app_->people()->indexOfId(QStringLiteral("olga.t")), 0);
  EXPECT_EQ(app_->pendingPeopleCount(), before) << "the rail badge counts people you owe an answer to";
}

TEST_F(ContactMergeTest, AnImportNeverHijacksAPersonTheUserAlreadyHas) {
  // Usernames are sanitised to [a-z0-9._-], so "ALEX", "al ex" and "alex!" all
  // derive the id "alex" — which the user may already have typed by hand for
  // somebody else entirely.
  Person mine;
  mine.id = QStringLiteral("alex");
  mine.name = QStringLiteral("Alex from accounting");
  mine.role = QStringLiteral("Finance");
  mine.state = QStringLiteral("todo");
  app_->people()->upsert(mine);

  merge({mkContact(QStringLiteral("u1"), QStringLiteral("ALEX"), QStringLiteral("Alexandra Petrova"), QStringLiteral("Backend"), kDm)});

  const int row = app_->people()->indexOfId(QStringLiteral("alex"));
  ASSERT_GE(row, 0);
  const Person& kept = app_->people()->items().at(row);
  EXPECT_EQ(kept.name, QStringLiteral("Alex from accounting")) << "a stranger was welded onto an existing person";
  EXPECT_EQ(kept.role, QStringLiteral("Finance"));

  // The contact still lands, just linked to its own Person (or none at all).
  const QJsonObject c = contactNamed(QStringLiteral("Alexandra Petrova"));
  ASSERT_FALSE(c.isEmpty());
  EXPECT_NE(c.value(QStringLiteral("personId")).toString(), QStringLiteral("alex"));
}

TEST_F(ContactMergeTest, TwoServerUsersSharingAHandleBothSurvive) {
  // The handle index is the fallback for contacts typed before the
  // integration existed. It was not updated for rows appended during the same
  // merge, so a second user with the same handle overwrote the first.
  merge({mkContact(QStringLiteral("u1"), QStringLiteral("bob"), QStringLiteral("Bob One"), QString(), kDm),
         mkContact(QStringLiteral("u2"), QStringLiteral("bob"), QStringLiteral("Bob Two"), QString(), kDm)});

  EXPECT_EQ(contacts().size(), 2) << "one of them overwrote the other";
  EXPECT_FALSE(contactNamed(QStringLiteral("Bob One")).isEmpty());
  EXPECT_FALSE(contactNamed(QStringLiteral("Bob Two")).isEmpty());
}

TEST_F(ContactMergeTest, TheSameColourComesBackAcrossRuns) {
  // qHash(QString) is seeded per process, so it gave the same person a
  // different colour in another profile or after a restart.
  merge({mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga"), QString(), kDm)});
  const QString first = contactNamed(QStringLiteral("Olga")).value(QStringLiteral("color")).toString();
  ASSERT_FALSE(first.isEmpty());

  app_->setDocsState(QString());
  merge({mkContact(QStringLiteral("u1"), QStringLiteral("olga.t"), QStringLiteral("Olga"), QString(), kDm)});
  EXPECT_EQ(contactNamed(QStringLiteral("Olga")).value(QStringLiteral("color")).toString(), first);
}

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
    // Test mode keeps integration secrets in this file instead of the OS
    // keychain; a token left by an earlier run must not leak into this one.
    QFile::remove(appData + QStringLiteral("/secrets.json"));
    QDir(appData + QStringLiteral("/backups")).removeRecursively();
  }

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
