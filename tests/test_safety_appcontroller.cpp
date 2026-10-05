// The safety net (APP-157…) as AppController runs it: the settings switches,
// once-a-day / once-per-link bookkeeping, and that nothing changes the data.
// The rules themselves are tested pure in test_safety_net.cpp.

#include "AppController.h"
#include "Models.h"

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

// Today at a fixed hour: the tick is given its clock, so nothing here depends
// on when the suite runs. Today, not a fixed date, because the bookkeeping of
// sent notices drops entries older than three days on load.
QDateTime todayAt(int hour, int minute = 0) {
  return {QDate::currentDate(), QTime(hour, minute)};
}

QString settingsJson(const QJsonObject& safety) {
  QJsonObject notif;
  // Only the safety net may speak.
  notif["meetingReminders"] = false;
  notif["deadlineReminders"] = false;
  notif["standupReminder"] = false;
  notif["blockedDailyDigest"] = false;
  notif["quietHours"] = false;
  QJsonObject root;
  root["notifications"] = notif;
  root["safety"] = safety;
  return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

Task task(const QString& id, const QString& status) {
  Task t;
  t.id = id;
  t.title = id + QStringLiteral(" title");
  t.status = status;
  t.priority = QStringLiteral("P2");
  return t;
}

}  // namespace

class SafetyNetTest : public ::testing::Test {
 protected:
  void SetUp() override {
    QFile::remove(heap::paths::dataDir() + QStringLiteral("/reminders.json"));
    app_ = std::make_unique<AppController>();
    app_->events()->reset({});
    app_->tasks()->reset({});
  }

  void TearDown() override {
    app_.reset();
  }

  std::unique_ptr<AppController> app_;
};

// ── APP-157 ──

TEST_F(SafetyNetTest, EndOfDayIsOffByDefault) {
  app_->setAppSettingsJson(settingsJson({}));
  Task t = task(QStringLiteral("T-1"), QStringLiteral("prog"));
  t.timerStartedAt = todayAt(9);
  app_->tasks()->reset({t});
  const QSignalSpy spy(app_.get(), &AppController::safetyNotice);

  app_->runAutomationAt(todayAt(18, 5));

  EXPECT_EQ(spy.count(), 0);
}

TEST_F(SafetyNetTest, EndOfDaySaysOnceThatATimerIsRunning) {
  app_->setAppSettingsJson(settingsJson({{"endOfDay", true}, {"endOfDayTime", "18:00"}}));
  Task t = task(QStringLiteral("T-1"), QStringLiteral("prog"));
  t.timerStartedAt = todayAt(9);
  app_->tasks()->reset({t});
  const QSignalSpy spy(app_.get(), &AppController::safetyNotice);

  app_->runAutomationAt(todayAt(17, 59));
  EXPECT_EQ(spy.count(), 0);
  app_->runAutomationAt(todayAt(18, 1));
  app_->runAutomationAt(todayAt(18, 2));

  ASSERT_EQ(spy.count(), 1);
  EXPECT_EQ(spy.at(0).at(0).toString(), QStringLiteral("endOfDay"));
  EXPECT_EQ(spy.at(0).at(3).toStringList(), QStringList{QStringLiteral("T-1")});
  // It said so; it did not stop the timer.
  EXPECT_TRUE(app_->tasks()->items().at(0).timerStartedAt.isValid());
}

TEST_F(SafetyNetTest, EndOfDayNamesTasksInProgressWithoutAMove) {
  app_->setAppSettingsJson(settingsJson({{"endOfDay", true}, {"staleDays", 3}}));
  Task stale = task(QStringLiteral("T-1"), QStringLiteral("prog"));
  stale.statusChangedAt = todayAt(10).addDays(-4);
  Task fresh = task(QStringLiteral("T-2"), QStringLiteral("prog"));
  fresh.statusChangedAt = todayAt(10).addDays(-1);
  Task done = task(QStringLiteral("T-3"), QStringLiteral("done"));
  done.statusChangedAt = todayAt(10).addDays(-30);
  app_->tasks()->reset({stale, fresh, done});
  const QSignalSpy spy(app_.get(), &AppController::safetyNotice);

  app_->runAutomationAt(todayAt(18, 30));

  ASSERT_EQ(spy.count(), 1);
  EXPECT_EQ(spy.at(0).at(3).toStringList(), QStringList{QStringLiteral("T-1")});
  EXPECT_EQ(app_->tasks()->items().at(0).status, QStringLiteral("prog"));
}

TEST_F(SafetyNetTest, EndOfDayStaysQuietWhenThereIsNothingToSay) {
  app_->setAppSettingsJson(settingsJson({{"endOfDay", true}}));
  app_->tasks()->reset({task(QStringLiteral("T-1"), QStringLiteral("todo"))});
  const QSignalSpy spy(app_.get(), &AppController::safetyNotice);

  app_->runAutomationAt(todayAt(18, 30));

  EXPECT_EQ(spy.count(), 0);
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  const QApplication qapp(argc, argv);

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
