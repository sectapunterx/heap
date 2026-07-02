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
  EXPECT_EQ(app_->shortcutFor(QStringLiteral("task.new")), QString());       // swapped out
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
