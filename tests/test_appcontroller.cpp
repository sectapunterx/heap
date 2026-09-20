// Coverage for AppController's non-selection public logic: the rebindable
// shortcut catalog (set/reset/conflict/normalize), scheduleTask + its
// read-back, localized humanDate/shortDate, and the QVariant wrappers over
// the text/chrono helpers. Boots headless exactly like test_selection /
// test_notes: offscreen QPA + QStandardPaths test mode so nothing touches
// the real state.json.

#include "AppController.h"
#include "FakeHttpServer.h"
#include "Models.h"

#include "git/BranchTaskMatcher.h"
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

// The palette searches the persisted profiles, and the live models only reach
// a profile when a save runs — which is debounced by 300 ms. So a task created
// a moment ago was simply missing from Ctrl+K. Note the deliberate absence of
// flushSave() here: that is the whole point.
TEST_F(AppControllerTest, ATaskIsFindableInThePaletteBeforeTheSaveDebounceFires) {
  QVariantMap draft;
  draft["_isNew"] = true;
  draft["id"] = QStringLiteral("LTE-9100");
  draft["title"] = QStringLiteral("unflushed quokka");
  draft["priority"] = QStringLiteral("P2");
  draft["status"] = QStringLiteral("todo");
  app_->saveTask(draft);

  bool found = false;
  for(const QVariant& v : app_->commandPaletteEntries()) {
    if(v.toMap().value(QStringLiteral("taskId")).toString() == QStringLiteral("LTE-9100")) {
      found = true;
    }
  }
  EXPECT_TRUE(found) << "a just-created task was missing from the palette";

  // …and an edit is visible just as promptly.
  QVariantMap edit = app_->taskById(QStringLiteral("LTE-9100"));
  edit["_isNew"] = false;
  edit["_originalId"] = QStringLiteral("LTE-9100");
  edit["title"] = QStringLiteral("renamed wombat");
  app_->saveTask(edit);

  bool renamed = false;
  for(const QVariant& v : app_->commandPaletteEntries()) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("taskId")).toString() == QStringLiteral("LTE-9100")) {
      renamed = m.value(QStringLiteral("label")).toString().contains(QStringLiteral("wombat"));
    }
  }
  EXPECT_TRUE(renamed) << "the palette showed a stale title";

  app_->deleteTask(QStringLiteral("LTE-9100"));
  app_->clearPendingUndo();
}

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

// ─── Task ids must never destroy a task ───
// saveTask ends in upsert(), and TaskModel::upsert on an id that is already
// taken replaces that row outright. Three ways in, all silent, none undoable.

// The proposed id was "2700 + rowCount()". The count drops when a task is
// deleted, so the generator walks back over ids that are still in use.
TEST_F(AppControllerTest, ANewTasksProposedIdIsNeverOneAlreadyInUse) {
  app_->tasks()->reset({});

  const auto create = [this](const QString& title) {
    QVariantMap draft = app_->newTaskDraft(QStringLiteral("todo"));
    draft["_isNew"] = true;
    draft["title"] = title;
    app_->saveTask(draft);
    return draft.value(QStringLiteral("id")).toString();
  };

  const QString first = create(QStringLiteral("A"));
  const QString second = create(QStringLiteral("B"));
  ASSERT_NE(first, second);
  ASSERT_EQ(app_->tasks()->rowCount(), 2);

  // Delete the older one: the row count is now 1 again.
  app_->deleteTask(first);
  ASSERT_EQ(app_->tasks()->rowCount(), 1);

  const QString third = create(QStringLiteral("C"));
  EXPECT_NE(third, second) << "the new task reused a live id";
  ASSERT_EQ(app_->tasks()->rowCount(), 2) << "a task was overwritten";
  const int survivor = app_->tasks()->indexOfId(second);
  ASSERT_GE(survivor, 0);
  EXPECT_EQ(app_->tasks()->items().at(survivor).title, QStringLiteral("B")) << "B was replaced by C";
}

// Even when something else proposes the id, the save itself has to refuse.
TEST_F(AppControllerTest, CreatingATaskOnATakenIdIsRefusedNotMerged) {
  Task existing;
  existing.id = QStringLiteral("LTE-2700");
  existing.title = QStringLiteral("do not lose me");
  app_->tasks()->reset({existing});

  QVariantMap draft = app_->newTaskDraft(QStringLiteral("todo"));
  draft["_isNew"] = true;
  draft["id"] = QStringLiteral("LTE-2700");
  draft["title"] = QStringLiteral("the impostor");
  app_->saveTask(draft);

  ASSERT_EQ(app_->tasks()->rowCount(), 1);
  EXPECT_EQ(app_->tasks()->items().at(0).title, QStringLiteral("do not lose me"));
}

// Renaming A onto B's id used to remove A's row and overwrite B's — two tasks
// collapsing into one, with A's calendar events re-pointed at the survivor.
TEST_F(AppControllerTest, RenamingATaskOntoAnotherTasksIdIsRefused) {
  Task a;
  a.id = QStringLiteral("LTE-2700");
  a.title = QStringLiteral("A");
  Task b;
  b.id = QStringLiteral("LTE-2701");
  b.title = QStringLiteral("B");
  app_->tasks()->reset({a, b});

  QVariantMap draft = app_->taskById(QStringLiteral("LTE-2700"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("LTE-2700");
  draft["id"] = QStringLiteral("LTE-2701");  // B's id
  app_->saveTask(draft);

  ASSERT_EQ(app_->tasks()->rowCount(), 2) << "one of the two tasks was destroyed";
  const int rowA = app_->tasks()->indexOfId(QStringLiteral("LTE-2700"));
  const int rowB = app_->tasks()->indexOfId(QStringLiteral("LTE-2701"));
  ASSERT_GE(rowA, 0) << "the renamed task vanished";
  ASSERT_GE(rowB, 0);
  EXPECT_EQ(app_->tasks()->items().at(rowA).title, QStringLiteral("A"));
  EXPECT_EQ(app_->tasks()->items().at(rowB).title, QStringLiteral("B")) << "B was overwritten by A";
}

// A rename to a free id still has to work.
TEST_F(AppControllerTest, RenamingATaskToAFreeIdStillWorks) {
  Task a;
  a.id = QStringLiteral("LTE-2700");
  a.title = QStringLiteral("A");
  app_->tasks()->reset({a});

  QVariantMap draft = app_->taskById(QStringLiteral("LTE-2700"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("LTE-2700");
  draft["id"] = QStringLiteral("LTE-9000");
  app_->saveTask(draft);

  EXPECT_LT(app_->tasks()->indexOfId(QStringLiteral("LTE-2700")), 0);
  const int row = app_->tasks()->indexOfId(QStringLiteral("LTE-9000"));
  ASSERT_GE(row, 0);
  EXPECT_EQ(app_->tasks()->items().at(row).title, QStringLiteral("A"));
}

// Saving an unchanged task is not a rename, so the guard must not fire on it.
TEST_F(AppControllerTest, SavingATaskUnderItsOwnIdIsNotTreatedAsACollision) {
  Task a;
  a.id = QStringLiteral("LTE-2700");
  a.title = QStringLiteral("A");
  app_->tasks()->reset({a});

  QVariantMap draft = app_->taskById(QStringLiteral("LTE-2700"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("LTE-2700");
  draft["title"] = QStringLiteral("A, edited");
  app_->saveTask(draft);

  const int row = app_->tasks()->indexOfId(QStringLiteral("LTE-2700"));
  ASSERT_GE(row, 0);
  EXPECT_EQ(app_->tasks()->items().at(row).title, QStringLiteral("A, edited"));
}

// ─── Ticket identity and the self-scope collision (HEAP-117) ───

namespace {

// One pulled issue, with only the fields a test cares about set.
heap::integrations::ExternalTask ghIssue(const QString& id, const QString& url, const QString& title = QStringLiteral("t")) {
  heap::integrations::ExternalTask e;
  e.providerId = QStringLiteral("github");
  e.externalId = id;
  e.url = url;
  e.title = title;
  e.status = QStringLiteral("open");
  return e;
}

}  // namespace

// The bug: an "assigned to me" pull spans repos, and GitHub's externalId is the
// bare issue number. #5 of repo A and #5 of repo B used to collapse onto one
// task that flip-flopped between them on every sync.
TEST_F(AppControllerTest, SelfScopeSameNumberInTwoReposStaysTwoTasks) {
  auto a = ghIssue(QStringLiteral("5"), QStringLiteral("https://github.com/acme/web/issues/5"), QStringLiteral("web five"));
  a.project = QStringLiteral("acme/web");
  a.crossProject = true;
  auto b = ghIssue(QStringLiteral("5"), QStringLiteral("https://github.com/acme/api/issues/5"), QStringLiteral("api five"));
  b.project = QStringLiteral("acme/api");
  b.crossProject = true;

  app_->tasks()->reset({});
  const auto first = app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {a, b});
  EXPECT_EQ(first.added, 2);
  EXPECT_EQ(app_->tasks()->rowCount(), 2);

  // Re-syncing the same two issues must not add, rename or re-clobber anything.
  const auto second = app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {a, b});
  EXPECT_EQ(second.added, 0);
  EXPECT_EQ(second.updated, 0);
  ASSERT_EQ(app_->tasks()->rowCount(), 2);

  QStringList titles;
  for(const Task& t : app_->tasks()->items()) {
    titles << t.title;
  }
  titles.sort();
  EXPECT_EQ(titles, (QStringList{QStringLiteral("api five"), QStringLiteral("web five")}));
  // The ids say which repo each came from.
  for(const Task& t : app_->tasks()->items()) {
    EXPECT_TRUE(t.id.contains(QStringLiteral("web")) || t.id.contains(QStringLiteral("api"))) << t.id.toStdString();
  }
}

// A task stored by an older build has no project recorded. It is matched by URL
// and heals in one sync; the other repo's issue gets a task of its own.
TEST_F(AppControllerTest, ACollapsedLegacyTaskHealsOnTheNextSync) {
  Task legacy;
  legacy.id = QStringLiteral("github-5");
  legacy.externalId = QStringLiteral("5");
  legacy.externalProvider = QStringLiteral("github");
  legacy.externalUrl = QStringLiteral("https://github.com/acme/api/issues/5");
  legacy.title = QStringLiteral("stale");
  app_->tasks()->reset({legacy});

  auto web = ghIssue(QStringLiteral("5"), QStringLiteral("https://github.com/acme/web/issues/5"), QStringLiteral("web five"));
  web.project = QStringLiteral("acme/web");
  web.crossProject = true;
  auto api = ghIssue(QStringLiteral("5"), QStringLiteral("https://github.com/acme/api/issues/5"), QStringLiteral("api five"));
  api.project = QStringLiteral("acme/api");
  api.crossProject = true;

  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {web, api});
  ASSERT_EQ(app_->tasks()->rowCount(), 2);
  // The legacy row kept its id and its own issue, matched by URL.
  const int legacyRow = app_->tasks()->indexOfId(QStringLiteral("github-5"));
  ASSERT_GE(legacyRow, 0);
  EXPECT_EQ(app_->tasks()->items().at(legacyRow).title, QStringLiteral("api five"));
}

// upsert() on a colliding id replaces the other row, so a new task's id has to
// be checked even when nothing about the tracker is ambiguous.
TEST_F(AppControllerTest, ANewTicketNeverOverwritesAnExistingTask) {
  Task local;
  local.id = QStringLiteral("github-7");
  local.title = QStringLiteral("hand-made, not a ticket");
  app_->tasks()->reset({local});

  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("7"), QStringLiteral("https://github.com/acme/web/issues/7"))});

  ASSERT_EQ(app_->tasks()->rowCount(), 2) << "the local task was overwritten";
  const int row = app_->tasks()->indexOfId(QStringLiteral("github-7"));
  ASSERT_GE(row, 0);
  EXPECT_EQ(app_->tasks()->items().at(row).title, QStringLiteral("hand-made, not a ticket"));
}

TEST_F(AppControllerTest, SyncWritesAndClearsTheTrackerAssignee) {
  auto issue = ghIssue(QStringLiteral("9"), QStringLiteral("https://github.com/acme/web/issues/9"));
  issue.assignee = QStringLiteral("ada");
  issue.author = QStringLiteral("grace");
  issue.commentCount = 3;
  issue.project = QStringLiteral("acme/web");

  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});
  const int row = app_->tasks()->indexOfId(QStringLiteral("github-9"));
  ASSERT_GE(row, 0);
  EXPECT_EQ(app_->tasks()->items().at(row).assignee, QStringLiteral("ada"));
  EXPECT_EQ(app_->tasks()->items().at(row).externalMeta.author, QStringLiteral("grace"));
  EXPECT_EQ(app_->tasks()->items().at(row).externalMeta.commentCount, 3);

  // Unassigned upstream → unassigned here.
  issue.assignee.clear();
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});
  EXPECT_TRUE(app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-9"))).assignee.isEmpty());
}

TEST_F(AppControllerTest, TrackerDueDateFillsAnEmptyDeadline) {
  auto issue = ghIssue(QStringLiteral("9"), QStringLiteral("https://github.com/acme/web/issues/9"));
  issue.dueAt = QDateTime(QDate(2026, 8, 15), QTime(0, 0));
  issue.dueHasTime = false;

  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});
  const Task& t = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-9")));
  EXPECT_EQ(t.dueAt, QDateTime(QDate(2026, 8, 15), QTime(0, 0)));
  EXPECT_FALSE(t.hasTime);
}

// The whole point of storing the tracker's due date: telling "the user moved
// this" apart from "the tracker moved this".
TEST_F(AppControllerTest, ALocallyEditedDeadlineSurvivesTheNextSync) {
  auto issue = ghIssue(QStringLiteral("9"), QStringLiteral("https://github.com/acme/web/issues/9"));
  issue.dueAt = QDateTime(QDate(2026, 8, 15), QTime(0, 0));

  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});

  QVariantMap draft = app_->taskById(QStringLiteral("github-9"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("github-9");
  draft["dueAt"] = QDateTime(QDate(2026, 9, 1), QTime(18, 0));
  app_->saveTask(draft);

  // The tracker still says the 15th; the user's own date has to win.
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});
  const Task& t = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-9")));
  EXPECT_EQ(t.dueAt, QDateTime(QDate(2026, 9, 1), QTime(18, 0)));
}

TEST_F(AppControllerTest, ADeadlineRemovedUpstreamClearsOnlyWhenSyncOwned) {
  auto issue = ghIssue(QStringLiteral("9"), QStringLiteral("https://github.com/acme/web/issues/9"));
  issue.dueAt = QDateTime(QDate(2026, 8, 15), QTime(0, 0));
  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});

  issue.dueAt = QDateTime();  // the due date is dropped upstream
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});
  EXPECT_FALSE(app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-9"))).dueAt.isValid());

  // Whereas a deadline the user set on an issue that never had one stays put.
  auto other = ghIssue(QStringLiteral("10"), QStringLiteral("https://github.com/acme/web/issues/10"));
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {other});
  QVariantMap draft = app_->taskById(QStringLiteral("github-10"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("github-10");
  draft["dueAt"] = QDateTime(QDate(2026, 9, 1), QTime(18, 0));
  app_->saveTask(draft);
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {other});
  EXPECT_EQ(app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-10"))).dueAt,
            QDateTime(QDate(2026, 9, 1), QTime(18, 0)));
}

TEST_F(AppControllerTest, ASnoozedDeadlineIsNotSnappedBackBySync) {
  auto issue = ghIssue(QStringLiteral("9"), QStringLiteral("https://github.com/acme/web/issues/9"));
  issue.dueAt = QDateTime(QDate(2026, 8, 15), QTime(9, 0));
  issue.dueHasTime = true;
  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});

  app_->snoozeDeadline(QStringLiteral("github-9"), 60);
  const QDateTime snoozed = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-9"))).dueAt;
  ASSERT_NE(snoozed, issue.dueAt);

  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});
  EXPECT_EQ(app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-9"))).dueAt, snoozed);
}

// The editor rewrites labels from comma text, which drops every colour. The
// next pull has to restore them without touching a colour the user chose.
TEST_F(AppControllerTest, LabelColoursFillOnlyEmptyChips) {
  auto issue = ghIssue(QStringLiteral("9"), QStringLiteral("https://github.com/acme/web/issues/9"));
  issue.labels = {QStringLiteral("bug"), QStringLiteral("ci")};
  issue.labelColors = {{QStringLiteral("bug"), QStringLiteral("#d73a4a")}, {QStringLiteral("ci"), QStringLiteral("#0000ff")}};

  Task existing;
  existing.id = QStringLiteral("github-9");
  existing.externalId = QStringLiteral("9");
  existing.externalProvider = QStringLiteral("github");
  existing.externalUrl = issue.url;
  existing.labels = {Label{QStringLiteral("ci"), QStringLiteral("#123456")}};  // the user picked this one
  app_->tasks()->reset({existing});

  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});
  const Task& t = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-9")));
  QHash<QString, QString> byName;
  for(const Label& l : t.labels) {
    byName.insert(l.id, l.color);
  }
  EXPECT_EQ(byName.value(QStringLiteral("bug")), QStringLiteral("#d73a4a"));
  EXPECT_EQ(byName.value(QStringLiteral("ci")), QStringLiteral("#123456")) << "sync overwrote a user-chosen colour";
}

TEST_F(AppControllerTest, AnEditorSavePreservesTheTrackerMetadata) {
  auto issue = ghIssue(QStringLiteral("9"), QStringLiteral("https://github.com/acme/web/issues/9"));
  issue.author = QStringLiteral("grace");
  issue.project = QStringLiteral("acme/web");
  issue.milestone = QStringLiteral("v2");
  issue.commentCount = 5;
  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});

  QVariantMap draft = app_->taskById(QStringLiteral("github-9"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("github-9");
  draft["title"] = QStringLiteral("edited locally");
  app_->saveTask(draft);

  const Task& t = app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("github-9")));
  EXPECT_EQ(t.externalMeta.author, QStringLiteral("grace"));
  EXPECT_EQ(t.externalMeta.project, QStringLiteral("acme/web"));
  EXPECT_EQ(t.externalMeta.milestone, QStringLiteral("v2"));
  EXPECT_EQ(t.externalMeta.commentCount, 5);
}

TEST_F(AppControllerTest, TheEditorDraftCarriesTheTicketMap) {
  auto issue = ghIssue(QStringLiteral("9"), QStringLiteral("https://github.com/acme/web/issues/9"));
  issue.author = QStringLiteral("grace");
  issue.issueType = QStringLiteral("Bug");
  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});

  const QVariantMap ticket = app_->taskById(QStringLiteral("github-9")).value(QStringLiteral("ticket")).toMap();
  EXPECT_EQ(ticket.value(QStringLiteral("provider")).toString(), QStringLiteral("github"));
  EXPECT_EQ(ticket.value(QStringLiteral("key")).toString(), QStringLiteral("#9"));
  EXPECT_EQ(ticket.value(QStringLiteral("author")).toString(), QStringLiteral("grace"));
  EXPECT_EQ(ticket.value(QStringLiteral("issueType")).toString(), QStringLiteral("Bug"));

  Task local;
  local.id = QStringLiteral("LOCAL-1");
  app_->tasks()->reset({local});
  EXPECT_TRUE(app_->taskById(QStringLiteral("LOCAL-1")).value(QStringLiteral("ticket")).toMap().isEmpty());
}

// A completed recurring ticket spawns a local occurrence, which must not carry
// the original issue's owner or metadata.
TEST_F(AppControllerTest, ARecurrenceCloneDropsTheTicketIdentity) {
  auto issue = ghIssue(QStringLiteral("9"), QStringLiteral("https://github.com/acme/web/issues/9"));
  issue.assignee = QStringLiteral("ada");
  issue.author = QStringLiteral("grace");
  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});

  QVariantMap draft = app_->taskById(QStringLiteral("github-9"));
  draft["_isNew"] = false;
  draft["_originalId"] = QStringLiteral("github-9");
  draft["recurrence"] = QStringLiteral("every:week");
  draft["dueAt"] = QDateTime(QDate(2026, 8, 15), QTime(9, 0));
  app_->saveTask(draft);
  app_->moveTask(QStringLiteral("github-9"), QStringLiteral("done"));

  const Task* clone = nullptr;
  for(const Task& t : app_->tasks()->items()) {
    if(t.id != QStringLiteral("github-9")) {
      clone = &t;
    }
  }
  ASSERT_NE(clone, nullptr) << "the recurrence clone was not created";
  EXPECT_TRUE(clone->externalId.isEmpty());
  EXPECT_TRUE(clone->assignee.isEmpty());
  EXPECT_EQ(clone->externalMeta, ExternalMeta{});
}

// ─── Sync must not undo what the user did ───
// The contact half of this code has guarded against both of these since it
// was written; the task half never did.

// Deleting a mirrored issue is how the user says "not mine". The next pull
// used to put it straight back, which made the deletion meaningless.
TEST_F(AppControllerTest, ADeletedTicketDoesNotComeBackOnTheNextSync) {
  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("1"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("1"))});
  ASSERT_GE(app_->tasks()->indexOfId(QStringLiteral("github-1")), 0);

  app_->deleteTask(QStringLiteral("github-1"));
  app_->clearPendingUndo();
  ASSERT_LT(app_->tasks()->indexOfId(QStringLiteral("github-1")), 0);

  // The tracker still reports it; heap must not.
  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("1"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("1"))});
  EXPECT_LT(app_->tasks()->indexOfId(QStringLiteral("github-1")), 0) << "the deleted ticket was re-created by sync";

  // Other issues are unaffected.
  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("2"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("2"))});
  EXPECT_GE(app_->tasks()->indexOfId(QStringLiteral("github-2")), 0);

  app_->restoreExternalTask(QStringLiteral("github"), QStringLiteral("1"));
}

// …and undoing the delete withdraws that, so it syncs normally again.
TEST_F(AppControllerTest, UndoingTheDeleteLetsTheTicketSyncAgain) {
  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("1"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("1"))});
  app_->deleteTask(QStringLiteral("github-1"));
  app_->undoLastDeletion();
  ASSERT_GE(app_->tasks()->indexOfId(QStringLiteral("github-1")), 0);

  app_->tasks()->reset({});  // as if the profile were reloaded
  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("1"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("1"))});
  EXPECT_GE(app_->tasks()->indexOfId(QStringLiteral("github-1")), 0) << "undo did not withdraw the dismissal";
}

TEST_F(AppControllerTest, DeletingASelectionOfTicketsDismissesAllOfThem) {
  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("1"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("1")),
                            ghIssue(QStringLiteral("2"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("2"))});
  app_->setSelectedTaskIds({QStringLiteral("github-1"), QStringLiteral("github-2")});
  app_->deleteSelectedTasks();
  app_->clearPendingUndo();
  ASSERT_EQ(app_->tasks()->rowCount(), 0);

  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("1"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("1")),
                            ghIssue(QStringLiteral("2"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("2"))});
  EXPECT_EQ(app_->tasks()->rowCount(), 0) << "a bulk delete of tickets was undone by sync";

  app_->restoreExternalTask(QStringLiteral("github"), QStringLiteral("1"));
  app_->restoreExternalTask(QStringLiteral("github"), QStringLiteral("2"));
}

// The integration config is global and the sync timer keeps running across a
// profile switch, so a background pull could pour one profile's tickets into
// whichever profile happened to be open.
TEST_F(AppControllerTest, AutoSyncIntoAnUnboundProfileIsANoopForTasks) {
  app_->tasks()->reset({});
  // The first merge binds the card to the profile it ran in.
  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("1"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("1"))});
  EXPECT_EQ(readIntegrationConfig(QStringLiteral("github")).value(QStringLiteral("profileId")).toString(), app_->activeProfileId());
  ASSERT_EQ(app_->tasks()->rowCount(), 1);

  // A timer tick while another profile is open must not write into it.
  QJsonObject cfg = readIntegrationConfig(QStringLiteral("github"));
  cfg.insert(QStringLiteral("profileId"), QStringLiteral("some-other-profile"));
  writeIntegrationConfig(QStringLiteral("github"), cfg);

  app_->mergeExternalTasks(QStringLiteral("github"),
                           QStringLiteral("github-"),
                           {ghIssue(QStringLiteral("2"), QStringLiteral("https://github.com/acme/web/issues/") + QStringLiteral("2"))});
  EXPECT_EQ(app_->tasks()->rowCount(), 1) << "a background sync imported into the wrong profile";
  EXPECT_LT(app_->tasks()->indexOfId(QStringLiteral("github-2")), 0);

  writeIntegrationConfig(QStringLiteral("github"), QJsonObject{});
}

// "Sync now" means "sync this, here" — a deliberate click rebinds the card.
TEST_F(AppControllerTest, AManualSyncRebindsTheProviderToTheOpenProfile) {
  writeIntegrationConfig(QStringLiteral("gitea"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("host"), QStringLiteral("http://127.0.0.1:1")},  // never contacted
                             {QStringLiteral("repo"), QStringLiteral("acme/web")},
                             {QStringLiteral("profileId"), QStringLiteral("some-other-profile")},
                         });
  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QStringLiteral("tok"));

  app_->syncProvider(QStringLiteral("gitea"));
  EXPECT_EQ(readIntegrationConfig(QStringLiteral("gitea")).value(QStringLiteral("profileId")).toString(), app_->activeProfileId());

  writeIntegrationConfig(QStringLiteral("gitea"), QJsonObject{});
  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QString());
}

// ─── A branch finds its own ticket ───
// A mirrored issue's heap id carries the provider ("jira-PROJ-123"), while the
// branch anyone writes for it names the tracker key ("PROJ-123").

TEST_F(AppControllerTest, ProjectKeysOfMirroredIssuesAreRegisteredAsPrefixes) {
  Task jira;
  jira.id = QStringLiteral("jira-PROJ-123");
  jira.externalId = QStringLiteral("PROJ-123");
  jira.externalProvider = QStringLiteral("jira");
  Task local;
  local.id = QStringLiteral("LTE-2700");
  Task numbered;  // a bare issue number has no key to register
  numbered.id = QStringLiteral("github-42");
  numbered.externalId = QStringLiteral("42");
  numbered.externalProvider = QStringLiteral("github");
  app_->tasks()->reset({jira, local, numbered});

  const QStringList prefixes = app_->collectPrefixes();
  EXPECT_TRUE(prefixes.contains(QStringLiteral("PROJ"))) << prefixes.join(QStringLiteral(",")).toStdString();
  EXPECT_FALSE(prefixes.contains(QStringLiteral("GITHUB")));
  EXPECT_GE(prefixes.size(), 2) << "the configured local prefix must still be there";
}

TEST_F(AppControllerTest, ATrackerKeyResolvesToTheTaskThatMirrorsIt) {
  Task jira;
  jira.id = QStringLiteral("jira-PROJ-123");
  jira.externalId = QStringLiteral("PROJ-123");
  jira.externalProvider = QStringLiteral("jira");
  Task local;
  local.id = QStringLiteral("LTE-2700");
  app_->tasks()->reset({jira, local});

  EXPECT_EQ(app_->taskIdForBranchMatch(QStringLiteral("PROJ-123")), QStringLiteral("jira-PROJ-123"));
  // Case-insensitively, because a branch name is usually lowercased.
  EXPECT_EQ(app_->taskIdForBranchMatch(QStringLiteral("proj-123")), QStringLiteral("jira-PROJ-123"));
  // A local task's key IS its id.
  EXPECT_EQ(app_->taskIdForBranchMatch(QStringLiteral("LTE-2700")), QStringLiteral("LTE-2700"));
  // Nothing to resolve to: hand the key back rather than inventing a task.
  EXPECT_EQ(app_->taskIdForBranchMatch(QStringLiteral("NOPE-1")), QStringLiteral("NOPE-1"));
  EXPECT_TRUE(app_->taskIdForBranchMatch(QString()).isEmpty());
}

// The loop has to close: a branch heap creates for a ticket must match back to
// that same ticket. It used to be named after the heap id, which never did.
TEST_F(AppControllerTest, ABranchCreatedForATicketIsNamedAfterItsTrackerKey) {
  Task jira;
  jira.id = QStringLiteral("jira-PROJ-123");
  jira.title = QStringLiteral("Handover fails");
  jira.externalId = QStringLiteral("PROJ-123");
  jira.externalProvider = QStringLiteral("jira");
  app_->tasks()->reset({jira});

  const QString branch =
      heap::git::BranchTaskMatcher::branchNameForTask(QStringLiteral("PROJ-123"), jira.title, QStringLiteral("feature/{id}-{slug}"));
  const heap::git::BranchTaskMatcher m(app_->collectPrefixes());
  const auto mr = m.extract(branch);
  ASSERT_TRUE(mr.matched) << branch.toStdString();
  EXPECT_EQ(app_->taskIdForBranchMatch(mr.taskId), QStringLiteral("jira-PROJ-123"));
}

// ─── Cached hot paths ───
// Both are caches, so what needs pinning is that they answer correctly after
// the thing they cache has changed.

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
// ─── Open in tracker (HEAP-117) ───
// The URL is tracker-supplied, and a Jira session that never learned its site
// yields a bare "/browse/KEY". Only a web address may reach the browser.
// openTaskExternal itself is never called from a test — it would open one.
TEST_F(AppControllerTest, ExternalUrlForAcceptsOnlyHttpUrls) {
  Task https;
  https.id = QStringLiteral("gh-1");
  https.externalUrl = QStringLiteral("https://github.com/acme/web/issues/1");

  Task relative;  // Jira with no site configured
  relative.id = QStringLiteral("jira-1");
  relative.externalUrl = QStringLiteral("/browse/PROJ-1");

  Task scripted;
  scripted.id = QStringLiteral("evil-1");
  scripted.externalUrl = QStringLiteral("javascript:alert(1)");

  Task file;
  file.id = QStringLiteral("evil-2");
  file.externalUrl = QStringLiteral("file:///c:/windows/system32/calc.exe");

  Task local;
  local.id = QStringLiteral("LTE-1");

  app_->tasks()->reset({https, relative, scripted, file, local});
  EXPECT_EQ(app_->externalUrlFor(QStringLiteral("gh-1")).toString(), https.externalUrl);
  EXPECT_TRUE(app_->externalUrlFor(QStringLiteral("jira-1")).isEmpty());
  EXPECT_TRUE(app_->externalUrlFor(QStringLiteral("evil-1")).isEmpty());
  EXPECT_TRUE(app_->externalUrlFor(QStringLiteral("evil-2")).isEmpty());
  EXPECT_TRUE(app_->externalUrlFor(QStringLiteral("LTE-1")).isEmpty());
  EXPECT_TRUE(app_->externalUrlFor(QStringLiteral("no-such-task")).isEmpty());
}

TEST_F(AppControllerTest, TheOpenTicketShortcutIsInTheCatalogAndRebindable) {
  bool found = false;
  for(const QVariant& v : app_->shortcuts()) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("id")).toString() != QStringLiteral("task.openExternal")) {
      continue;
    }
    found = true;
    EXPECT_EQ(m.value(QStringLiteral("defaultSequence")).toString(), QStringLiteral("O"));
    EXPECT_FALSE(m.value(QStringLiteral("label")).toString().isEmpty()) << "the shortcut has no translated label";
    EXPECT_FALSE(m.value(QStringLiteral("description")).toString().isEmpty());
  }
  EXPECT_TRUE(found) << "task.openExternal is missing from the shortcut catalog";

  EXPECT_TRUE(app_->setShortcut(QStringLiteral("task.openExternal"), QStringLiteral("Ctrl+Shift+O")));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.openExternal")), QStringLiteral("Ctrl+Shift+O"));
  app_->resetShortcut(QStringLiteral("task.openExternal"));
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.openExternal")), QStringLiteral("O"));
}

TEST_F(AppControllerTest, ProviderBadgesCoverEveryProviderInTheCatalog) {
  const QVariantMap badges = app_->providerBadges();
  for(const QVariant& v : app_->integrationCatalog()) {
    const QString id = v.toMap().value(QStringLiteral("id")).toString();
    ASSERT_TRUE(badges.contains(id)) << "no badge for " << id.toStdString();
    const QVariantMap badge = badges.value(id).toMap();
    EXPECT_FALSE(badge.value(QStringLiteral("name")).toString().isEmpty());
    EXPECT_FALSE(badge.value(QStringLiteral("icon")).toString().isEmpty());
    EXPECT_FALSE(badge.value(QStringLiteral("color")).toString().isEmpty());
  }
}

TEST_F(AppControllerTest, ThePaletteFindsAMirroredIssueByItsTrackerKey) {
  auto issue = ghIssue(QStringLiteral("1234"), QStringLiteral("https://github.com/acme/web/issues/1234"));
  app_->tasks()->reset({});
  app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("github-"), {issue});
  // The palette searches the persisted profiles, not the live model.
  app_->flushSave();

  bool found = false;
  for(const QVariant& v : app_->commandPaletteEntries()) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("taskId")).toString() != QStringLiteral("github-1234")) {
      continue;
    }
    found = true;
    const QString haystack = m.value(QStringLiteral("label")).toString() + m.value(QStringLiteral("sub")).toString();
    EXPECT_TRUE(haystack.contains(QStringLiteral("#1234"))) << haystack.toStdString();
    EXPECT_TRUE(haystack.contains(QStringLiteral("GitHub"))) << haystack.toStdString();
  }
  EXPECT_TRUE(found) << "the pulled issue never reached the palette";
}

// Moving a card writes the new state back to the tracker. An issue pulled from
// an "assigned to me" endpoint belongs to some other repo, but the push URL is
// built from the configured one — the PATCH would close a different issue that
// happens to share the number. Driven against a local fake Gitea, because its
// base URL is configurable; github's is hard-coded and a mistake here would
// reach the real API.
TEST_F(AppControllerTest, MovingACrossProjectTicketNeverPushesToTheConfiguredRepo) {
  heap::testing::FakeHttpServer gitea;
  gitea.route("GET /api/v1/repos/acme/web/issues", {200, "[]", {}});
  gitea.route("PATCH /api/v1/repos/acme/web/issues/5", {200, "{}", {}});

  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QStringLiteral("tok"));
  writeIntegrationConfig(QStringLiteral("gitea"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("host"), gitea.base()},
                             {QStringLiteral("repo"), QStringLiteral("acme/web")},
                         });

  // A ticket that came from another repo entirely.
  Task foreign;
  foreign.id = QStringLiteral("gitea-api-5");
  foreign.externalId = QStringLiteral("5");
  foreign.externalProvider = QStringLiteral("gitea");
  foreign.externalUrl = QStringLiteral("https://gitea.example.com/acme/api/issues/5");
  foreign.status = QStringLiteral("todo");
  foreign.externalMeta.project = QStringLiteral("acme/api");
  foreign.externalMeta.crossProject = true;
  app_->tasks()->reset({foreign});

  app_->moveTask(QStringLiteral("gitea-api-5"), QStringLiteral("done"));
  // Give any push that was going to happen a chance to reach the server.
  heap::testing::waitUntil(
      [&gitea]() {
        return !gitea.seen().isEmpty();
      },
      500);
  EXPECT_FALSE(gitea.seen().contains("PATCH /api/v1/repos/acme/web/issues/5")) << "closed an issue in the wrong repo";

  writeIntegrationConfig(QStringLiteral("gitea"), QJsonObject{});
  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QString());
}

// "Synced 12 issue(s)" every quarter of an hour said nothing about whether
// anything changed, and the merge rewrote state.json either way.
TEST_F(AppControllerTest, AQuietResyncReportsNoChangeAndWritesNothing) {
  const QByteArray issues = R"([{"number":5,"title":"t","state":"open","html_url":"https://gitea.example.com/acme/web/issues/5"}])";
  heap::testing::FakeHttpServer gitea;
  gitea.route("GET /api/v1/repos/acme/web/issues", {200, issues, {}});

  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QStringLiteral("tok"));
  writeIntegrationConfig(QStringLiteral("gitea"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("host"), gitea.base()},
                             {QStringLiteral("repo"), QStringLiteral("acme/web")},
                         });
  app_->tasks()->reset({});

  // syncProvider announces itself before it starts, so collect only the
  // toast that reports the outcome.
  QStringList outcomes;
  QObject::connect(app_.get(), &AppController::toast, app_.get(), [&outcomes](const QString& text) {
    if(text.contains(QStringLiteral("new")) || text.contains(QStringLiteral("up to date"))) {
      outcomes << text;
    }
  });

  app_->syncProvider(QStringLiteral("gitea"));
  ASSERT_TRUE(heap::testing::waitUntil([&outcomes]() {
    return !outcomes.isEmpty();
  }));
  EXPECT_TRUE(outcomes.last().contains(QStringLiteral("1 new"))) << outcomes.last().toStdString();
  EXPECT_EQ(app_->tasks()->rowCount(), 1);

  outcomes.clear();
  app_->syncProvider(QStringLiteral("gitea"));
  ASSERT_TRUE(heap::testing::waitUntil([&outcomes]() {
    return !outcomes.isEmpty();
  }));
  EXPECT_TRUE(outcomes.last().contains(QStringLiteral("up to date"))) << outcomes.last().toStdString();
  EXPECT_EQ(app_->tasks()->rowCount(), 1);

  writeIntegrationConfig(QStringLiteral("gitea"), QJsonObject{});
  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QString());
}

// Comments are read on demand and stored nowhere. Against a local fake Gitea,
// because its base URL is configurable — github's is hard-coded.
TEST_F(AppControllerTest, TicketCommentsAreFetchedForTheIssuesOwnRepoAndNotStored) {
  heap::testing::FakeHttpServer gitea;
  gitea.route("GET /api/v1/repos/acme/api/issues/5/comments",
              {200, R"([{"user":{"login":"ada"},"body":"first","created_at":"2026-01-02T03:04:05Z"}])", {}});

  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QStringLiteral("tok"));
  writeIntegrationConfig(QStringLiteral("gitea"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("host"), gitea.base()},
                             // The configured repo is NOT the issue's own.
                             {QStringLiteral("repo"), QStringLiteral("acme/web")},
                         });

  Task t;
  t.id = QStringLiteral("gitea-api-5");
  t.externalId = QStringLiteral("5");
  t.externalProvider = QStringLiteral("gitea");
  t.externalUrl = QStringLiteral("https://gitea.example.com/acme/api/issues/5");
  t.externalMeta.project = QStringLiteral("acme/api");
  t.externalMeta.crossProject = true;
  app_->tasks()->reset({t});
  const Task before = app_->tasks()->items().at(0);

  QVariantList got;
  QString error;
  bool done = false;
  QObject::connect(app_.get(),
                   &AppController::ticketCommentsLoaded,
                   app_.get(),
                   [&](const QString& taskId, const QVariantList& comments, const QString& err) {
                     EXPECT_EQ(taskId, QStringLiteral("gitea-api-5"));
                     got = comments;
                     error = err;
                     done = true;
                   });

  app_->fetchTicketComments(QStringLiteral("gitea-api-5"));
  ASSERT_TRUE(heap::testing::waitUntil([&done]() {
    return done;
  }));
  EXPECT_TRUE(error.isEmpty()) << error.toStdString();
  ASSERT_EQ(got.size(), 1);
  EXPECT_EQ(got.at(0).toMap().value(QStringLiteral("author")).toString(), QStringLiteral("ada"));
  EXPECT_EQ(got.at(0).toMap().value(QStringLiteral("body")).toString(), QStringLiteral("first"));
  // The request went to the issue's repo, not the configured one.
  EXPECT_TRUE(gitea.seen().contains("GET /api/v1/repos/acme/api/issues/5/comments")) << "asked the wrong repo for comments";
  // Read-only in every sense: the task is untouched and nothing is pending.
  EXPECT_EQ(app_->tasks()->items().at(0), before);

  writeIntegrationConfig(QStringLiteral("gitea"), QJsonObject{});
  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QString());
}

TEST_F(AppControllerTest, FetchingCommentsForALocalTaskAnswersWithoutARequest) {
  Task local;
  local.id = QStringLiteral("LTE-1");
  app_->tasks()->reset({local});

  QString error;
  bool done = false;
  QObject::connect(
      app_.get(), &AppController::ticketCommentsLoaded, app_.get(), [&](const QString&, const QVariantList& c, const QString& err) {
        EXPECT_TRUE(c.isEmpty());
        error = err;
        done = true;
      });
  app_->fetchTicketComments(QStringLiteral("LTE-1"));
  ASSERT_TRUE(done) << "a local task should be answered synchronously";
  EXPECT_FALSE(error.isEmpty());

  done = false;
  app_->fetchTicketComments(QStringLiteral("no-such-task"));
  EXPECT_TRUE(done);
}

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

// ─── Search box → query ───────────────────────────────────────────────
// The board filters in C++ (TaskFilterProxy); the archive, timeline, week and
// month views build JS snapshots and ask compileSearch instead. Both halves
// have to agree on what a clause is, or one search box means two things.

TEST_F(AppControllerTest, CompileSearchSplitsClausesFromSearchWords) {
  Task blocked = mkTask(QStringLiteral("T-1"), QStringLiteral("login flow"));
  blocked.status = QStringLiteral("blocked");
  Task todo = mkTask(QStringLiteral("T-2"), QStringLiteral("login page"));
  Task other = mkTask(QStringLiteral("T-3"), QStringLiteral("export csv"));
  other.status = QStringLiteral("blocked");
  app_->tasks()->reset({blocked, todo, other});

  const QVariantMap r = app_->compileSearch(QStringLiteral("status:blocked login"));
  EXPECT_TRUE(r.value(QStringLiteral("isQuery")).toBool());
  // The clause is consumed, so only the loose word is left to substring-match.
  EXPECT_EQ(r.value(QStringLiteral("freeText")).toString(), QStringLiteral("login"));
  // The ids are the clause half only — "export csv" is blocked too, and the
  // caller is the one that drops it on the free text.
  const QStringList ids = r.value(QStringLiteral("ids")).toStringList();
  EXPECT_EQ(ids, QStringList({QStringLiteral("T-1"), QStringLiteral("T-3")}));
}

TEST_F(AppControllerTest, CompileSearchBuildsNoIdListForPlainText) {
  app_->tasks()->reset({mkTask(QStringLiteral("T-1"), QStringLiteral("login"))});

  const QVariantMap r = app_->compileSearch(QStringLiteral("login"));
  EXPECT_FALSE(r.value(QStringLiteral("isQuery")).toBool());
  EXPECT_EQ(r.value(QStringLiteral("freeText")).toString(), QStringLiteral("login"));
  // With no clauses every task would be in the list, which is both useless and
  // the largest thing this call could hand back.
  EXPECT_TRUE(r.value(QStringLiteral("ids")).toStringList().isEmpty());
}

TEST_F(AppControllerTest, SearchIsQueryOnlyParsesAndAdvertisesItsFields) {
  EXPECT_TRUE(app_->searchIsQuery(QStringLiteral("priority:P0")));
  EXPECT_FALSE(app_->searchIsQuery(QStringLiteral("https://example.test/x"))) << "a colon is not a clause unless the field is one we know";
  EXPECT_FALSE(app_->searchIsQuery(QString()));

  const QStringList fields = app_->searchFields();
  for(const char* f : {"status", "priority", "deadline", "tag", "mention"}) {
    EXPECT_TRUE(fields.contains(QLatin1String(f))) << f << " must be offered as a hint";
  }
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
