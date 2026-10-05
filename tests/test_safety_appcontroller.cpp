// The safety net (APP-157…) as AppController runs it: the settings switches,
// once-a-day / once-per-link bookkeeping, and that nothing changes the data.
// The rules themselves are tested pure in test_safety_net.cpp.

#include "AppController.h"
#include "Models.h"
#include "StateSerializer.h"

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
    // The profile on disk persists between runs (LinksSurviveARestart saves).
    for(const WaitingOn& w : app_->waitingOnLinks()) {
      app_->clearWaitingOn(w.taskId);
    }
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

// ── APP-158 ──

namespace {

Person person(const QString& id, const QString& state = QStringLiteral("pinged")) {
  Person p;
  p.id = id;
  p.name = QStringLiteral("Oleg");
  p.state = state;
  p.color = QColor(QStringLiteral("#7da8d9"));
  return p;
}

}  // namespace

class WaitingOnTest : public SafetyNetTest {
 protected:
  void SetUp() override {
    SafetyNetTest::SetUp();
    app_->tasks()->reset({task(QStringLiteral("T-1"), QStringLiteral("todo"))});
    app_->people()->reset({person(QStringLiteral("oleg"))});
  }
};

TEST_F(WaitingOnTest, ALinkNeedsATaskAndAPerson) {
  app_->setWaitingOn(QStringLiteral("nope"), QStringLiteral("oleg"));
  app_->setWaitingOn(QStringLiteral("T-1"), QStringLiteral("nobody"));
  EXPECT_TRUE(app_->waitingOnLinks().isEmpty());

  app_->setWaitingOn(QStringLiteral("T-1"), QStringLiteral("oleg"));
  const QVariantMap m = app_->waitingOnMap().value(QStringLiteral("T-1")).toMap();
  EXPECT_EQ(m.value(QStringLiteral("name")).toString(), QStringLiteral("Oleg"));
  EXPECT_EQ(m.value(QStringLiteral("days")).toInt(), 0);
}

TEST_F(WaitingOnTest, TheReminderIsOffByDefault) {
  app_->setAppSettingsJson(settingsJson({}));
  app_->setWaitingOn(QStringLiteral("T-1"), QStringLiteral("oleg"));
  const QSignalSpy spy(app_.get(), &AppController::safetyNotice);

  app_->runAutomationAt(QDateTime::currentDateTime().addDays(5));

  EXPECT_EQ(spy.count(), 0);
}

TEST_F(WaitingOnTest, OneGentleReminderPerLink) {
  app_->setAppSettingsJson(settingsJson({{"waitingOn", true}, {"waitingDays", 2}}));
  app_->setWaitingOn(QStringLiteral("T-1"), QStringLiteral("oleg"));
  const QDateTime since = app_->waitingOnLinks().at(0).since;
  const QSignalSpy spy(app_.get(), &AppController::safetyNotice);

  app_->runAutomationAt(since.addDays(1));
  EXPECT_EQ(spy.count(), 0);
  app_->runAutomationAt(since.addDays(2).addSecs(60));
  app_->runAutomationAt(since.addDays(3));

  ASSERT_EQ(spy.count(), 1);
  EXPECT_EQ(spy.at(0).at(0).toString(), QStringLiteral("waiting"));
  EXPECT_TRUE(spy.at(0).at(2).toString().contains(QStringLiteral("Oleg")));
  EXPECT_TRUE(spy.at(0).at(2).toString().contains(QStringLiteral("T-1 title")));
  EXPECT_EQ(spy.at(0).at(3).toStringList(), QStringList{QStringLiteral("T-1")});
  // It reminded; the link and the task are as they were.
  EXPECT_EQ(app_->waitingOnLinks().size(), 1);
  EXPECT_EQ(app_->tasks()->items().at(0).status, QStringLiteral("todo"));
}

TEST_F(WaitingOnTest, MarkingTheReplyEndsTheWait) {
  app_->setWaitingOn(QStringLiteral("T-1"), QStringLiteral("oleg"));
  app_->setPersonState(QStringLiteral("oleg"), QStringLiteral("replied"));
  EXPECT_TRUE(app_->waitingOnLinks().isEmpty());
}

TEST_F(WaitingOnTest, ClearingEndsTheWait) {
  app_->setWaitingOn(QStringLiteral("T-1"), QStringLiteral("oleg"));
  app_->clearWaitingOn(QStringLiteral("T-1"));
  EXPECT_TRUE(app_->waitingOnLinks().isEmpty());
}

TEST_F(WaitingOnTest, LinksSurviveARestart) {
  app_->setWaitingOn(QStringLiteral("T-1"), QStringLiteral("oleg"));
  const WaitingOn before = app_->waitingOnLinks().at(0);
  app_->flushSave();

  const AppController reopened;
  ASSERT_EQ(reopened.waitingOnLinks().size(), 1);
  EXPECT_EQ(reopened.waitingOnLinks().at(0).taskId, before.taskId);
  EXPECT_EQ(reopened.waitingOnLinks().at(0).personId, before.personId);
  EXPECT_EQ(reopened.waitingOnLinks().at(0).since.toSecsSinceEpoch(), before.since.toSecsSinceEpoch());
}

TEST(WaitingOnSerializer, RoundTripsThroughTheProfileObject) {
  Profile p;
  p.id = QStringLiteral("p");
  p.waitingOn.append({.taskId = QStringLiteral("T-1"),
                      .personId = QStringLiteral("oleg"),
                      .since = QDateTime(QDate(2026, 10, 1), QTime(10, 0)),
                      .remindedAt = QDateTime(QDate(2026, 10, 3), QTime(10, 0))});
  p.waitingOn.append({.taskId = QStringLiteral("T-2"),
                      .personId = QStringLiteral("anna"),
                      .since = QDateTime(QDate(2026, 10, 2), QTime(9, 0)),
                      .remindedAt = {}});
  const QJsonObject o = heap::state::profileToJson(p);
  ASSERT_TRUE(o.contains(QStringLiteral("waitingOn")));
  const Profile back = heap::state::profileFromJson(o);
  EXPECT_EQ(back.waitingOn, p.waitingOn);
  // Known, so not also carried in `extra`.
  EXPECT_FALSE(back.extra.contains(QStringLiteral("waitingOn")));
  // None → no key at all, like statusLog.
  EXPECT_FALSE(heap::state::profileToJson(Profile{}).contains(QStringLiteral("waitingOn")));
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
