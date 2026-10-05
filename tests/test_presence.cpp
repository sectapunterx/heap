// heap staying around: start at login (APP-154).
//
// Runs in Qt's test mode, where the autostart entry goes to a scratch folder
// rather than the real Run key / launch agent / autostart folder.

#include "AppController.h"

#include "platform/Autostart.h"

#include <QApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

QJsonObject systemSettings(const AppController& c) {
  return QJsonDocument::fromJson(c.appSettingsJson().toUtf8()).object().value(QStringLiteral("system")).toObject();
}

// A scratch root per case, so cases do not see each other's entry.
struct AutostartRoot {
  QTemporaryDir dir;

  AutostartRoot() {
    heap::platform::autostart::setRootForTesting(dir.path());
  }

  ~AutostartRoot() {
    heap::platform::autostart::setRootForTesting(QString());
  }

  AutostartRoot(const AutostartRoot&) = delete;
  AutostartRoot& operator=(const AutostartRoot&) = delete;
};

}  // namespace

TEST(Autostart, TestModeNeverPointsAtTheSystem) {
  heap::platform::autostart::setRootForTesting(QString());
  EXPECT_FALSE(heap::platform::autostart::testRoot().isEmpty());
}

TEST(Autostart, OffByDefault) {
  const AutostartRoot root;
  AppController c;
  // The test profile persists between runs; start from no settings at all.
  c.setAppSettingsJson(QStringLiteral("{}"));
  const QVariantMap s = c.autostartState();
  EXPECT_TRUE(s.value(QStringLiteral("supported")).toBool());
  EXPECT_FALSE(s.value(QStringLiteral("enabled")).toBool());
  EXPECT_FALSE(s.value(QStringLiteral("minimized")).toBool());
}

TEST(Autostart, EnablingWritesTheEntryAndRemembersTheChoice) {
  const AutostartRoot root;
  AppController c;
  ASSERT_TRUE(c.setAutostart(true, true));
  const QVariantMap s = c.autostartState();
  EXPECT_TRUE(s.value(QStringLiteral("enabled")).toBool());
  EXPECT_TRUE(s.value(QStringLiteral("minimized")).toBool());
  EXPECT_TRUE(systemSettings(c).value(QStringLiteral("startAtLogin")).toBool());
  EXPECT_TRUE(heap::platform::autostart::read().minimized);

  // Off: the entry goes, the "minimized" choice stays for next time.
  ASSERT_TRUE(c.setAutostart(false, true));
  EXPECT_FALSE(heap::platform::autostart::read().enabled);
  EXPECT_FALSE(c.autostartState().value(QStringLiteral("enabled")).toBool());
  EXPECT_TRUE(c.autostartState().value(QStringLiteral("minimized")).toBool());
}

// The state comes from the OS, not from settings: an entry removed by hand
// reads as off even though settings still say on.
TEST(Autostart, StateFollowsTheSystemEntry) {
  const AutostartRoot root;
  AppController c;
  ASSERT_TRUE(c.setAutostart(true, false));
  ASSERT_TRUE(heap::platform::autostart::write(false, false));
  EXPECT_FALSE(c.autostartState().value(QStringLiteral("enabled")).toBool());
}

// Starting at login answers an open close-to-tray question with the tray...
TEST(Autostart, EnablingAnswersAnUnsetCloseToTray) {
  const AutostartRoot root;
  AppController c;
  c.setAppSettingsJson(QStringLiteral("{\"system\":{}}"));
  ASSERT_TRUE(c.setAutostart(true, true));
  EXPECT_TRUE(systemSettings(c).value(QStringLiteral("closeToTray")).toBool());
}

// ...but never overrides an explicit "quit".
TEST(Autostart, EnablingKeepsAnExplicitQuit) {
  const AutostartRoot root;
  AppController c;
  c.setAppSettingsJson(QStringLiteral("{\"system\":{\"closeToTray\":false}}"));
  ASSERT_TRUE(c.setAutostart(true, true));
  EXPECT_FALSE(systemSettings(c).value(QStringLiteral("closeToTray")).toBool(true));
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
