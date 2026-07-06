// Coverage for AppController's non-selection public logic: the rebindable
// shortcut catalog (set/reset/conflict/normalize), scheduleTask + its
// read-back, localized humanDate/shortDate, and the QVariant wrappers over
// the text/chrono helpers. Boots headless exactly like test_selection /
// test_notes: offscreen QPA + QStandardPaths test mode so nothing touches
// the real state.json.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
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
  t.deadline = QDate(2026, 7, 4);
  app_->tasks()->reset({t});
  const int before = app_->tasks()->rowCount();

  app_->moveTask(QStringLiteral("REC-1"), QStringLiteral("done"));

  ASSERT_EQ(app_->tasks()->rowCount(), before + 1);
  bool foundNext = false;
  for(const Task& x : app_->tasks()->items()) {
    if(x.id != QStringLiteral("REC-1") && x.recurrence == QStringLiteral("every:day")) {
      EXPECT_EQ(x.status, QString("todo"));
      EXPECT_EQ(x.deadline, QDate(2026, 7, 5));  // next day
      foundNext = true;
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
    QDir(appData + QStringLiteral("/backups")).removeRecursively();
  }

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
