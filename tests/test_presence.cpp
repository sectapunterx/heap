// heap staying around: start at login (APP-154) and the buttons on a
// reminder (APP-155).
//
// Runs in Qt's test mode, where the autostart entry goes to a scratch folder
// rather than the real Run key / launch agent / autostart folder, and the
// notifications use the tray fallback rather than registering with the OS.

#include "AppController.h"
#include "Models.h"

#include "notify/NotifyPayload.h"
#include "platform/Autostart.h"
#include "platform/Paths.h"

#include <QApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
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

// ── Reminder buttons (APP-155) ──

namespace {

const QDateTime kNoon(QDate(2026, 10, 6), QTime(12, 0));

// Snoozes are kept on disk and the test profile persists: start without any.
void dropSavedSnoozes() {
  QFile::remove(heap::paths::dataDir() + QStringLiteral("/snoozes.json"));
}

// The reminder the snoozed one came back as, if it did.
int refired(const QSignalSpy& spy, const QString& routeId) {
  int n = 0;
  for(const QList<QVariant>& args : spy) {
    if(args.size() > 3 && args.at(3).toString() == routeId) {
      ++n;
    }
  }
  return n;
}

}  // namespace

TEST(ReminderButtons, SnoozeBringsTheSameReminderBackLater) {
  dropSavedSnoozes();
  AppController c;
  c.setAppSettingsJson(QStringLiteral("{}"));
  c.sendTestNotification();
  const QString id = QStringLiteral("test:heap");
  c.snoozeReminderAt(id, 10, kNoon);
  ASSERT_EQ(c.pendingSnoozes().size(), 1);
  EXPECT_EQ(c.pendingSnoozes().at(0).fireAt, kNoon.addSecs(600));

  QSignalSpy spy(&c, &AppController::notification);
  c.runAutomationAt(kNoon.addSecs(540));
  EXPECT_EQ(refired(spy, id), 0) << "not before its time";
  c.runAutomationAt(kNoon.addSecs(600));
  EXPECT_EQ(refired(spy, id), 1);
  EXPECT_TRUE(c.pendingSnoozes().isEmpty());
  c.runAutomationAt(kNoon.addSecs(660));
  EXPECT_EQ(refired(spy, id), 1) << "once";
}

// The click arrives as a heap://notify URI; the durations come from settings.
TEST(ReminderButtons, SnoozeButtonFromUriUsesTheSetting) {
  dropSavedSnoozes();
  AppController c;
  c.setAppSettingsJson(QStringLiteral("{\"notifications\":{\"snoozeShortMin\":20,\"snoozeLongMin\":90}}"));
  const QDateTime before = QDateTime::currentDateTime();
  ASSERT_TRUE(c.handleNotificationUri(heap::notify::notifyUri(QStringLiteral("test:heap"), QStringLiteral("snoozeLong"))));
  ASSERT_EQ(c.pendingSnoozes().size(), 1);
  const qint64 secs = before.secsTo(c.pendingSnoozes().at(0).fireAt);
  EXPECT_GE(secs, 90 * 60);
  EXPECT_LE(secs, 90 * 60 + 60);
  EXPECT_FALSE(c.handleNotificationUri(QStringLiteral("heap://elsewhere")));
}

// A snooze puts the reminder off; the task's deadline stays where it was.
TEST(ReminderButtons, SnoozeLeavesTheDeadlineAlone) {
  dropSavedSnoozes();
  AppController c;
  Task t;
  t.id = QStringLiteral("SNZ-155");
  t.title = QStringLiteral("ship it");
  t.status = QStringLiteral("todo");
  t.dueAt = QDateTime(QDate(2026, 10, 6), QTime(13, 0));
  t.dueHasTime = true;
  c.tasks()->upsert(t);
  c.snoozeReminderAt(QStringLiteral("deadline:SNZ-155"), 60, kNoon);
  EXPECT_EQ(c.taskById(QStringLiteral("SNZ-155")).value(QStringLiteral("dueAt")).toDateTime(), t.dueAt);
  ASSERT_EQ(c.pendingSnoozes().size(), 1);
  // Without the shown text (a restart), the task's title stands in.
  EXPECT_EQ(c.pendingSnoozes().at(0).body, QStringLiteral("ship it"));
}

// Finished in the meantime: the snoozed reminder has nothing left to say.
TEST(ReminderButtons, SnoozedReminderOfADoneTaskStaysQuiet) {
  dropSavedSnoozes();
  AppController c;
  c.setAppSettingsJson(QStringLiteral("{\"notifications\":{\"quietHours\":false}}"));
  Task t;
  t.id = QStringLiteral("SNZ-156");
  t.title = QStringLiteral("done already");
  t.status = QStringLiteral("done");
  c.tasks()->upsert(t);
  c.snoozeReminderAt(QStringLiteral("deadline:SNZ-156"), 10, kNoon);
  QSignalSpy toasts(&c, &AppController::toast);
  c.runAutomationAt(kNoon.addSecs(600));
  EXPECT_TRUE(c.pendingSnoozes().isEmpty());
  for(const QList<QVariant>& args : toasts) {
    EXPECT_FALSE(args.at(0).toString().contains(QStringLiteral("done already")));
  }
}

TEST(ReminderButtons, OpenOnAMeetingGoesToItsDay) {
  dropSavedSnoozes();
  AppController c;
  QSignalSpy spy(&c, &AppController::openEventRequested);
  ASSERT_TRUE(c.handleNotificationUri(heap::notify::notifyUri(QStringLiteral("meeting:ev-1"), QStringLiteral("open"))));
  ASSERT_EQ(spy.count(), 1);
  EXPECT_EQ(spy.at(0).at(0).toString(), QStringLiteral("ev-1"));
  EXPECT_EQ(spy.at(0).at(1).toDate(), c.today()) << "a day it was not shown for falls back to today";
}

TEST(ReminderButtons, OpenOnATaskOpensIt) {
  dropSavedSnoozes();
  AppController c;
  Task t;
  t.id = QStringLiteral("OPN-1");
  t.title = QStringLiteral("look at me");
  t.status = QStringLiteral("todo");
  c.tasks()->upsert(t);
  QSignalSpy spy(&c, &AppController::openTaskRequested);
  ASSERT_TRUE(c.handleNotificationUri(heap::notify::notifyUri(QStringLiteral("deadline:OPN-1"), QString())));
  ASSERT_EQ(spy.count(), 1);
  EXPECT_EQ(spy.at(0).at(0).toString(), QStringLiteral("OPN-1"));
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
