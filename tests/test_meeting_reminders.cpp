// Reminders for calendar events.
//
// heap had a "minutes before a meeting" setting and exactly one meeting it
// applied to: the standup, at a fixed time from settings. Every real event in
// the calendar went unannounced, which made the setting read like a promise
// the app did not keep.
//
// The window rule is pure and takes `now` as an argument (src/cal/Reminders.h).
// It has to be: a test can only place an event a few minutes out, saveEvent()
// snaps it to the calendar's grid, and whether the snapped slot lands before or
// after the current instant depends on what time the suite happens to run. The
// first version of this file did exactly that and passed locally while failing
// on CI, for no reason connected to the feature.
//
// The AppController cases below cover what is genuinely its own: the
// once-per-day sentinel, the settings switch, and the fact that quiet hours do
// not gate a meeting. They set a lead wide enough that the grid can snap the
// event wherever it likes.

#include "AppController.h"
#include "Models.h"

#include "cal/Reminders.h"

#include <QApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

using heap::cal::dueMeetingReminders;

namespace {

const QDate kDay(2026, 9, 21);
// Mid-morning, so nothing in these cases is near a day boundary.
const QDateTime kNow(kDay, QTime(10, 0));

CalEvent at(const QString& id, double startHour, const QString& type = QStringLiteral("sync")) {
  CalEvent e;
  e.id = id;
  e.title = QStringLiteral("standup with the team");
  e.type = type;
  e.date = kDay;
  e.start = startHour;
  e.end = startHour + 0.5;
  return e;
}

}  // namespace

// ── The window rule ──

TEST(MeetingWindow, AnEventInsideTheLeadWindowIsDue) {
  const auto due = dueMeetingReminders({at(QStringLiteral("a"), 10.0 + 5.0 / 60.0)}, kNow, 10);

  ASSERT_EQ(due.size(), 1);
  EXPECT_EQ(due.at(0).eventId, QStringLiteral("a"));
  EXPECT_EQ(due.at(0).minutesLeft, 5);
}

TEST(MeetingWindow, AnEventBeyondTheLeadWindowIsNotDueYet) {
  const auto due = dueMeetingReminders({at(QStringLiteral("a"), 12.0)}, kNow, 10);

  EXPECT_TRUE(due.isEmpty());
}

// An event that has already started is not something to be reminded about.
TEST(MeetingWindow, AnEventThatHasPassedIsNotDue) {
  const auto due = dueMeetingReminders({at(QStringLiteral("a"), 9.5)}, kNow, 10);

  EXPECT_TRUE(due.isEmpty());
}

// The far edge is inclusive: a lead of 10 has to announce a meeting exactly
// ten minutes out, or the setting is off by one for its own value.
TEST(MeetingWindow, TheEdgeOfTheWindowIsIncluded) {
  const auto due = dueMeetingReminders({at(QStringLiteral("a"), 10.0 + 10.0 / 60.0)}, kNow, 10);

  EXPECT_EQ(due.size(), 1);
}

// A lead of 0 means "when it starts", not "never" — the slider's minimum is 0
// and it has to mean something.
TEST(MeetingWindow, AZeroLeadStillAnnouncesAtTheStart) {
  const auto due = dueMeetingReminders({at(QStringLiteral("a"), 10.0)}, kNow, 0);

  ASSERT_EQ(due.size(), 1);
  EXPECT_EQ(due.at(0).minutesLeft, 0);
}

TEST(MeetingWindow, AZeroLeadAnnouncesNothingEarlier) {
  const auto due = dueMeetingReminders({at(QStringLiteral("a"), 10.0 + 5.0 / 60.0)}, kNow, 0);

  EXPECT_TRUE(due.isEmpty());
}

// A focus block is the user's own time — they put it there on purpose and are
// already in it. Reminding them about it is noise.
TEST(MeetingWindow, AFocusBlockIsNotAMeeting) {
  const auto due = dueMeetingReminders({at(QStringLiteral("a"), 10.0 + 5.0 / 60.0, QStringLiteral("focus"))}, kNow, 10);

  EXPECT_TRUE(due.isEmpty());
}

TEST(MeetingWindow, TwoEventsInTheWindowAreBothDue) {
  const QVector<CalEvent> events{at(QStringLiteral("a"), 10.0 + 3.0 / 60.0), at(QStringLiteral("b"), 10.0 + 6.0 / 60.0)};
  const auto due = dueMeetingReminders(events, kNow, 10);

  EXPECT_EQ(due.size(), 2);
}

// An event on another day is not in today's window however close its hour is.
TEST(MeetingWindow, AnEventOnAnotherDayIsIgnored) {
  CalEvent e = at(QStringLiteral("a"), 10.0 + 5.0 / 60.0);
  e.date = kDay.addDays(1);

  EXPECT_TRUE(dueMeetingReminders({e}, kNow, 10).isEmpty());
}

// Late in the evening the window must not spill into tomorrow's small hours:
// a 00:30 meeting is not "30 minutes away" from 23:50 as far as the rule is
// concerned, because it is not on today's date at all.
TEST(MeetingWindow, TheWindowDoesNotReachAcrossMidnight) {
  CalEvent e = at(QStringLiteral("a"), 0.5);
  e.date = kDay.addDays(1);

  EXPECT_TRUE(dueMeetingReminders({e}, QDateTime(kDay, QTime(23, 50)), 60).isEmpty());
}

// An all-day event has no start to count down to. Announcing "your holiday
// begins in 0 minutes" at midnight is noise, not a reminder.
TEST(MeetingWindow, AnAllDayEventIsNotAnnounced) {
  CalEvent e = at(QStringLiteral("a"), 10.0 + 5.0 / 60.0);
  e.allDay = true;

  EXPECT_TRUE(dueMeetingReminders({e}, kNow, 10).isEmpty());
}

TEST(MeetingWindow, AnInvalidClockAnnouncesNothing) {
  EXPECT_TRUE(dueMeetingReminders({at(QStringLiteral("a"), 10.0)}, QDateTime(), 10).isEmpty());
}

TEST(MeetingWindow, ANegativeLeadIsTreatedAsZero) {
  const auto due = dueMeetingReminders({at(QStringLiteral("a"), 10.0)}, kNow, -30);

  EXPECT_EQ(due.size(), 1);
}

// ── What AppController adds on top ──

namespace {

// Only meeting reminders on, so nothing else in the tick can speak. The lead is
// a whole day: the calendar snaps a saved event to its grid, so a test that
// wants one to be "inside the window" cannot also pin the exact minute.
constexpr int kSnapMinutes = 15;

QString settingsWithMeetingLead(int leadMinutes, bool enabled = true) {
  QJsonObject notif;
  notif["meetingReminders"] = enabled;
  notif["meetingLead"] = leadMinutes;
  notif["deadlineReminders"] = false;
  notif["standupReminder"] = false;
  notif["blockedDailyDigest"] = false;
  notif["quietHours"] = false;
  // The snap grid is pinned here too, so the fixture knows where saveEvent()
  // will put an event rather than having to ask for a private accessor.
  QJsonObject cal;
  cal["snapMinutes"] = kSnapMinutes;
  QJsonObject root;
  root["notifications"] = notif;
  root["calendar"] = cal;
  return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

constexpr int kWholeDay = 24 * 60;

}  // namespace

class MeetingReminderTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->events()->reset({});
    app_->setAppSettingsJson(settingsWithMeetingLead(kWholeDay));
  }

  void TearDown() override {
    app_.reset();
  }

  // An event on the next slot of the calendar's grid. saveEvent() snaps what it
  // is given, so handing it an already-snapped time is the only way to know
  // where the event lands; with a whole-day lead it is then inside the window
  // whatever the hour.
  //
  // Returns false in the last slot of the day, where there is no later slot to
  // use; the case then has nothing to assert and says so.
  bool addEventOnTheNextSlot(const QString& title = QStringLiteral("standup with the team"), const QString& type = QStringLiteral("sync")) {
    const QDateTime now = QDateTime::currentDateTime();
    const int step = kSnapMinutes;
    const int minutes = (now.time().hour() * 60) + now.time().minute();
    const int slot = ((minutes / step) + 1) * step;
    if(slot >= 24 * 60) {
      return false;
    }
    const double startHour = slot / 60.0;
    QVariantMap draft = app_->newEventDraft(startHour, now.date());
    draft["title"] = title;
    draft["type"] = type;
    draft["date"] = now.date();
    draft["start"] = startHour;
    draft["end"] = startHour + 0.5;
    app_->saveEvent(draft);
    return true;
  }

  void tick() {
    QMetaObject::invokeMethod(app_.get(), "runAutomation", Qt::DirectConnection);
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(MeetingReminderTest, AMeetingLaterTodayIsAnnounced) {
  if(!addEventOnTheNextSlot()) {
    GTEST_SKIP() << "no calendar slot left today";
  }
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  ASSERT_GE(spy.count(), 1);
  EXPECT_EQ(spy.at(0).at(2).toString(), QStringLiteral("meeting"));
  EXPECT_TRUE(spy.at(0).at(1).toString().contains(QStringLiteral("standup with the team")));
}

// The tick runs once a minute. Without a sentinel a meeting half an hour out
// would be announced thirty times.
TEST_F(MeetingReminderTest, AnEventIsAnnouncedOnceNotOncePerTick) {
  if(!addEventOnTheNextSlot()) {
    GTEST_SKIP() << "no calendar slot left today";
  }
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();
  tick();
  tick();

  EXPECT_EQ(spy.count(), 1);
}

TEST_F(MeetingReminderTest, TheSettingTurnsThemOff) {
  app_->setAppSettingsJson(settingsWithMeetingLead(kWholeDay, /*enabled=*/false));
  if(!addEventOnTheNextSlot()) {
    GTEST_SKIP() << "no calendar slot left today";
  }
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_EQ(spy.count(), 0);
}

// Quiet hours silence ambient noise — digests, deadline nags. A meeting is an
// appointment the user agreed to attend, and the default window (19:00–09:00)
// covers every early call, so gating on it would silently swallow exactly the
// reminders that matter most. The standup reminder already behaves this way.
TEST_F(MeetingReminderTest, QuietHoursDoNotSwallowAMeeting) {
  QJsonObject notif;
  notif["meetingReminders"] = true;
  notif["meetingLead"] = kWholeDay;
  notif["deadlineReminders"] = false;
  notif["standupReminder"] = false;
  notif["blockedDailyDigest"] = false;
  notif["quietHours"] = true;
  notif["quietFrom"] = QStringLiteral("00:00");
  notif["quietTo"] = QStringLiteral("23:59");
  QJsonObject cal;
  cal["snapMinutes"] = kSnapMinutes;
  QJsonObject root;
  root["notifications"] = notif;
  root["calendar"] = cal;
  app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact)));

  if(!addEventOnTheNextSlot()) {
    GTEST_SKIP() << "no calendar slot left today";
  }
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_GE(spy.count(), 1);
}

TEST_F(MeetingReminderTest, TwoMeetingsGetTwoReminders) {
  if(!addEventOnTheNextSlot(QStringLiteral("first")) || !addEventOnTheNextSlot(QStringLiteral("second"))) {
    GTEST_SKIP() << "no calendar slot left today";
  }
  QSignalSpy spy(app_.get(), &AppController::notification);

  tick();

  EXPECT_EQ(spy.count(), 2);
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
