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
#include <QDir>
#include <QFile>
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

TEST_F(OnboardingTest, FreshInstallShowsWelcomeAndFlagsDemo) {
  AppController app;
  EXPECT_FALSE(app.welcomeSeen());
  EXPECT_TRUE(app.demoActive());
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
    ASSERT_TRUE(a.demoActive());
    a.dismissDemo();
    a.flushSave();
  }
  AppController b;
  EXPECT_FALSE(b.demoActive());
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
