// First-run onboarding state on AppController (HEAP-51).
//
// Covers the persisted welcomeSeen / demoActive flags and startFresh():
//   - a fresh install shows the welcome and flags the demo,
//   - markWelcomeSeen / dismissDemo persist across restarts,
//   - startFresh clears the active profile's demo content.
//
// Headless via offscreen QPA + AppDataLocation test mode.

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
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QVector>

#include <gtest/gtest.h>

namespace {

Task makeTask(const QString& id) {
  Task t;
  t.id = id;
  t.title = id;
  t.priority = QStringLiteral("P2");
  t.status = QStringLiteral("todo");
  return t;
}

}  // namespace

class OnboardingTest : public ::testing::Test {
 protected:
  void SetUp() override {
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir(dir).removeRecursively();
    QDir().mkpath(dir);
  }
};

// APP-271: a fresh install is one empty profile of the person's own — no
// sample tasks, people, meetings, notes, reference links or views in it —
// and Today is the first-run screen (welcomeSeen false) until a task.
TEST_F(OnboardingTest, FreshInstallIsAnEmptyProfileOfYourOwn) {
  AppController app;
  EXPECT_FALSE(app.welcomeSeen());
  EXPECT_FALSE(app.demoActive());
  ASSERT_EQ(app.profiles().size(), 1);
  EXPECT_NE(app.activeProfileId(), QString::fromLatin1(AppController::kExampleProfileId));
  EXPECT_EQ(app.tasks()->rowCount(), 0);
  EXPECT_EQ(app.people()->rowCount(), 0);
  EXPECT_EQ(app.events()->rowCount(), 0);
  EXPECT_EQ(app.notes()->rowCount(), 0);
  EXPECT_FALSE(app.hasExample());
  const QJsonObject docs = QJsonDocument::fromJson(app.docsState().toUtf8()).object();
  EXPECT_TRUE(docs["sections"].toArray().isEmpty());
  EXPECT_TRUE(docs["snippets"].toArray().isEmpty());
  EXPECT_GT(app.statuses().size(), 0) << "a profile needs its columns";
}

// Closed before the first task: the next start is the first-run screen again.
TEST_F(OnboardingTest, ClosedBeforeTheFirstTaskStartsFirstRunAgain) {
  {
    AppController a;
    a.flushSave();
  }
  AppController b;
  EXPECT_FALSE(b.welcomeSeen());
  EXPECT_EQ(b.tasks()->rowCount(), 0);
  EXPECT_EQ(b.profiles().size(), 1);
}

// The example is a profile of its own; the person's profile is not touched,
// a second "open" does not make a second one, and removing it takes its
// meetings too.
TEST_F(OnboardingTest, ExampleIsASeparateProfileMadeOnceAndRemovedWhole) {
  AppController app;
  const QString own = app.activeProfileId();
  app.tasks()->reset({makeTask(QStringLiteral("MINE-1"))});

  const QString ex = app.openExample();
  EXPECT_EQ(ex, QString::fromLatin1(AppController::kExampleProfileId));
  EXPECT_EQ(app.activeProfileId(), ex);
  EXPECT_GT(app.tasks()->rowCount(), 0);
  EXPECT_GT(app.events()->rowCount(), 0);
  EXPECT_EQ(app.profiles().size(), 2);
  EXPECT_EQ(app.exampleChanges(), 0);

  // Again: no duplicate, only a switch.
  app.setActiveProfileId(own);
  ASSERT_EQ(app.tasks()->rowCount(), 1);
  app.openExample();
  EXPECT_EQ(app.profiles().size(), 2);
  EXPECT_EQ(app.activeProfileId(), ex);

  app.removeExample();
  EXPECT_FALSE(app.hasExample());
  EXPECT_EQ(app.profiles().size(), 1);
  EXPECT_EQ(app.activeProfileId(), own);
  ASSERT_EQ(app.tasks()->rowCount(), 1);
  EXPECT_EQ(app.tasks()->items().at(0).id, QStringLiteral("MINE-1"));
  for(const CalEvent& e : app.events()->items()) {
    EXPECT_NE(e.profileId, ex) << "a sample meeting stayed behind";
  }
}

// A sample task edited or added later is the person's work: counted, so the
// question before removing can say so.
TEST_F(OnboardingTest, ExampleChangesCountEditedAndAddedTasks) {
  AppController app;
  app.openExample();
  ASSERT_GT(app.tasks()->rowCount(), 1);
  Task edited = app.tasks()->items().at(0);
  edited.title += QStringLiteral(" (mine)");
  app.tasks()->upsert(edited);
  app.tasks()->upsert(makeTask(QStringLiteral("NEW-1")));
  EXPECT_EQ(app.exampleChanges(), 2);
}

// A new user starts on lowkey / lowkey light with normal contrast (heap 2), written into the
// settings so the built-in fallback (heap. dark) still holds for everyone who
// has never opened Appearance.
TEST_F(OnboardingTest, FreshInstallStartsOnLowkeyWithNormalContrast) {
  AppController app;
  const QJsonObject appearance = QJsonDocument::fromJson(app.appSettingsJson().toUtf8()).object()["appearance"].toObject();
  EXPECT_EQ(appearance["darkPreset"].toString(), QStringLiteral("heap-ink"));
  EXPECT_EQ(appearance["lightPreset"].toString(), QStringLiteral("heap-light"));
  EXPECT_EQ(appearance["contrast"].toString(), QStringLiteral("normal"));
}

// ...and an install that already has settings keeps its own.
TEST_F(OnboardingTest, ExistingSettingsKeepTheirTheme) {
  {
    AppController a;
    a.setAppSettingsJson(QStringLiteral(R"({"appearance":{"darkPreset":"slate"}})"));
    a.markWelcomeSeen();
    a.flushSave();
  }
  AppController b;
  const QJsonObject appearance = QJsonDocument::fromJson(b.appSettingsJson().toUtf8()).object()["appearance"].toObject();
  EXPECT_EQ(appearance["darkPreset"].toString(), QStringLiteral("slate"));
  EXPECT_FALSE(appearance.contains(QStringLiteral("contrast")));
}

TEST_F(OnboardingTest, MarkWelcomeSeenPersists) {
  {
    AppController a;
    ASSERT_FALSE(a.welcomeSeen());
    a.markWelcomeSeen();
    a.flushSave();
  }
  AppController b;
  EXPECT_TRUE(b.welcomeSeen());
}

TEST_F(OnboardingTest, DismissDemoPersists) {
  {
    AppController a;
    a.dismissDemo();
    a.flushSave();
  }
  AppController b;
  EXPECT_FALSE(b.demoActive());
}

TEST_F(OnboardingTest, ReplayWelcomeEmitsSignalAndKeepsState) {
  AppController app;
  app.markWelcomeSeen();
  app.dismissDemo();
  ASSERT_TRUE(app.welcomeSeen());
  ASSERT_FALSE(app.demoActive());

  QSignalSpy spy(&app, &AppController::welcomeReplayRequested);
  app.replayWelcome();

  // Replay is a pure UI request: it fires the signal but leaves the persisted
  // onboarding flags exactly as they were (no demo banner resurrection).
  EXPECT_EQ(spy.count(), 1);
  EXPECT_TRUE(app.welcomeSeen());
  EXPECT_FALSE(app.demoActive());
}

TEST_F(OnboardingTest, StartFreshClearsActiveProfileContent) {
  AppController app;
  const QString active = app.activeProfileId();

  app.tasks()->reset({makeTask(QStringLiteral("T-1")), makeTask(QStringLiteral("T-2"))});
  app.people()->reset({[] {
    Person p;
    p.id = QStringLiteral("alice");
    p.name = QStringLiteral("Alice");
    return p;
  }()});
  CalEvent e;
  e.id = QStringLiteral("ev-1");
  e.title = QStringLiteral("Demo event");
  e.date = QDate(2026, 5, 19);
  e.profileId = active;
  app.events()->reset({e});
  app.setNotesState(QStringLiteral("demo notes"));

  app.startFresh();

  EXPECT_EQ(app.tasks()->rowCount(), 0);
  EXPECT_EQ(app.people()->rowCount(), 0);
  EXPECT_EQ(app.events()->rowCount(), 0);
  EXPECT_TRUE(app.notesState().isEmpty());
  EXPECT_FALSE(app.demoActive());
}

TEST_F(OnboardingTest, ResetToFirstRunRebuildsFreshInstall) {
  const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  {
    AppController a;
    // Make it look like a used install: onboarding done, custom content, a
    // stale backup and a quarantined corrupt snapshot on disk.
    a.markWelcomeSeen();
    a.dismissDemo();
    a.tasks()->reset({makeTask(QStringLiteral("T-1"))});
    a.setNotesState(QStringLiteral("my notes"));
    a.flushSave();
    QDir().mkpath(base + QStringLiteral("/backups"));
    {
      QFile bk(base + QStringLiteral("/backups/state-old.json"));
      ASSERT_TRUE(bk.open(QIODevice::WriteOnly));
      bk.write("{}");
    }
    {
      QFile cr(base + QStringLiteral("/state.corrupt-1.json"));
      ASSERT_TRUE(cr.open(QIODevice::WriteOnly));
      cr.write("{}");
    }

    a.resetToFirstRun();

    // In memory: exactly a fresh install — one empty profile (APP-271).
    EXPECT_FALSE(a.welcomeSeen());
    EXPECT_FALSE(a.demoActive());
    EXPECT_EQ(a.profiles().size(), 1);
    EXPECT_EQ(a.tasks()->rowCount(), 0);
    EXPECT_FALSE(a.notesState().contains(QStringLiteral("my notes")));
    EXPECT_EQ(a.notes()->rowCount(), 0);
    // On disk: stale backup + corrupt snapshot erased, fresh state.json written.
    EXPECT_FALSE(QFile::exists(base + QStringLiteral("/backups/state-old.json")));
    EXPECT_FALSE(QFile::exists(base + QStringLiteral("/state.corrupt-1.json")));
    EXPECT_TRUE(QFile::exists(base + QStringLiteral("/state.json")));
  }
  // Persisted: a relaunch still lands on the first-run screen.
  AppController b;
  EXPECT_FALSE(b.welcomeSeen());
  EXPECT_EQ(b.tasks()->rowCount(), 0);
}

// "There is a key for that" (APP-166): the third mouse use of an action names
// its key once, and the "once" survives a restart.
TEST_F(OnboardingTest, ThirdMouseUseSuggestsTheKeyOnceEver) {
  {
    AppController a;
    const QSignalSpy spy(&a, &AppController::shortcutHintRequested);
    a.noteMouseAction(QStringLiteral("palette.open"));
    a.noteMouseAction(QStringLiteral("palette.open"));
    EXPECT_EQ(spy.count(), 0);
    a.noteMouseAction(QStringLiteral("palette.open"));
    ASSERT_EQ(spy.count(), 1);
    EXPECT_EQ(spy.at(0).at(0).toString(), QStringLiteral("palette.open"));
    EXPECT_EQ(spy.at(0).at(1).toString(), a.shortcutFor(QStringLiteral("palette.open")));
    a.noteMouseAction(QStringLiteral("palette.open"));
    EXPECT_EQ(spy.count(), 1);
    // Two uses of another action, carried over the restart.
    a.noteMouseAction(QStringLiteral("section.today"));
    a.noteMouseAction(QStringLiteral("section.today"));
    a.flushSave();
  }
  AppController b;
  const QSignalSpy spy(&b, &AppController::shortcutHintRequested);
  for(int i = 0; i < 5; ++i) {
    b.noteMouseAction(QStringLiteral("palette.open"));
  }
  EXPECT_EQ(spy.count(), 0) << "already suggested before the restart";
  b.noteMouseAction(QStringLiteral("section.today"));
  EXPECT_EQ(spy.count(), 1) << "the third use, counting the two before the restart";
}

TEST_F(OnboardingTest, NoKeySuggestionsWhenSwitchedOff) {
  AppController app;
  app.setAppSettingsJson(QStringLiteral(R"({"shortcuts":{"mouseHints":false}})"));
  const QSignalSpy spy(&app, &AppController::shortcutHintRequested);
  for(int i = 0; i < 5; ++i) {
    app.noteMouseAction(QStringLiteral("task.new"));
  }
  EXPECT_EQ(spy.count(), 0);
  // An action with nothing bound has no key to suggest.
  app.setAppSettingsJson(QStringLiteral("{}"));
  app.setShortcut(QStringLiteral("task.new"), QString());
  for(int i = 0; i < 5; ++i) {
    app.noteMouseAction(QStringLiteral("task.new"));
  }
  EXPECT_EQ(spy.count(), 0);
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
