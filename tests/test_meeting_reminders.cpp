// Reminders for calendar events.
//
// heap had a "minutes before a meeting" setting and exactly one meeting it
// applied to: the standup, at a fixed time from settings. Every real event in
// the calendar went unannounced, which made the setting read like a promise
// the app did not keep.
//
// runAutomation() is a private slot, invoked here the way the timer invokes
// it. Headless via offscreen QPA + AppDataLocation test mode.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

// Only meeting reminders on, so nothing else in the tick can speak.
QString settingsWithMeetingLead(int leadMinutes, bool enabled = true) {
  QJsonObject notif;
  notif["meetingReminders"] = enabled;
  notif["meetingLead"] = leadMinutes;
  notif["deadlineReminders"] = false;
  notif["standupReminder"] = false;
  notif["blockedDailyDigest"] = false;
  notif["quietHours"] = false;
  QJsonObject root;
  root["notifications"] = notif;
  return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

}  // namespace

class MeetingReminderTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->events()->reset({});
    app_->setAppSettingsJson(settingsWithMeetingLead(10));
  }

  void TearDown() override {
    app_.reset();
  }

  // An event today, `minutesFromNow` away, of the given type.
  QString addEventIn(int minutesFromNow, const QString& type = QStringLiteral("sync")) {
    const QDateTime at = QDateTime::currentDateTime().addSecs(minutesFromNow * 60);
    QVariantMap draft = app_->newEventDraft(at.time().hour() + (at.time().minute() / 60.0), at.date());
    draft["title"] = QStringLiteral("standup with the team");
    draft["type"] = type;
    draft["date"] = at.date();
    draft["start"] = at.time().hour() + (at.time().minute() / 60.0);
    draft["end"] = draft["start"].toDouble() + 0.5;
    app_->saveEvent(draft);
    return draft.value(QStringLiteral("id")).toString();
  }

  void tick() {
    QMetaObject::invokeMethod(app_.get(), "runAutomation", Qt::DirectConnection);
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(MeetingReminderTest, AnEventInsideTheLeadWindowIsAnnounced) {
  addEventIn(5);
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  ASSERT_GE(spy.count(), 1);
  EXPECT_EQ(spy.at(0).at(2).toString(), QStringLiteral("meeting"));
  EXPECT_TRUE(spy.at(0).at(1).toString().contains(QStringLiteral("standup with the team")));
}

TEST_F(MeetingReminderTest, AnEventBeyondTheLeadWindowIsNotAnnouncedYet) {
  addEventIn(120);
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_EQ(spy.count(), 0);
}

// An event that has already started is not something to be reminded about.
TEST_F(MeetingReminderTest, AnEventThatHasPassedIsNotAnnounced) {
  addEventIn(-30);
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_EQ(spy.count(), 0);
}

// The tick runs once a minute. Without a sentinel a meeting ten minutes out
// would be announced ten times.
TEST_F(MeetingReminderTest, AnEventIsAnnouncedOnceNotOncePerTick) {
  addEventIn(5);
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();
  tick();
  tick();

  EXPECT_EQ(spy.count(), 1);
}

// A focus block is the user's own time — they put it there on purpose and are
// already in it. Reminding them about it is noise.
TEST_F(MeetingReminderTest, AFocusBlockIsNotAMeeting) {
  addEventIn(5, QStringLiteral("focus"));
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_EQ(spy.count(), 0);
}

TEST_F(MeetingReminderTest, TheSettingTurnsThemOff) {
  app_->setAppSettingsJson(settingsWithMeetingLead(10, /*enabled=*/false));
  addEventIn(5);
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_EQ(spy.count(), 0);
}

// A lead of 0 means "when it starts", not "never" — the slider's minimum is 0
// and it has to mean something.
TEST_F(MeetingReminderTest, AZeroLeadStillAnnouncesAtTheStart) {
  app_->setAppSettingsJson(settingsWithMeetingLead(0));
  addEventIn(0);
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_GE(spy.count(), 1);
}

TEST_F(MeetingReminderTest, TwoEventsGetTwoReminders) {
  addEventIn(3);
  addEventIn(6);
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_EQ(spy.count(), 2);
}

// Quiet hours silence ambient noise — digests, deadline nags. A meeting is an
// appointment the user agreed to attend, and the default window (19:00–09:00)
// covers every early call, so gating on it would silently swallow exactly the
// reminders that matter most. The standup reminder already behaves this way.
TEST_F(MeetingReminderTest, QuietHoursDoNotSwallowAMeeting) {
  QJsonObject notif;
  notif["meetingReminders"] = true;
  notif["meetingLead"] = 10;
  notif["deadlineReminders"] = false;
  notif["standupReminder"] = false;
  notif["blockedDailyDigest"] = false;
  notif["quietHours"] = true;
  notif["quietFrom"] = QStringLiteral("00:00");
  notif["quietTo"] = QStringLiteral("23:59");
  QJsonObject root;
  root["notifications"] = notif;
  app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact)));

  addEventIn(5);
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_GE(spy.count(), 1);
}

// An event on another day is not in today's window however close its hour is.
TEST_F(MeetingReminderTest, AnEventOnAnotherDayIsIgnored) {
  const QDateTime at = QDateTime::currentDateTime().addDays(1).addSecs(5 * 60);
  QVariantMap draft = app_->newEventDraft(at.time().hour(), at.date());
  draft["title"] = QStringLiteral("tomorrow");
  draft["date"] = at.date();
  app_->saveEvent(draft);

  QSignalSpy spy(app_.get(), &AppController::notification);
  tick();

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
