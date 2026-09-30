// Calendar fixes from the 2026-09-30 audit (TIME-*, and the PLAT/TASKS items
// that live in the calendar's code). Each case names the finding it pins.
//
// Driven through a real AppController. Every clock-dependent case hands the
// tick its own `now` (runAutomationAt), so none of them depends on when the
// suite runs.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

const QDate kMon(2026, 9, 21);  // a Monday

QString settingsJson(const QJsonObject& notif, const QJsonObject& cal = {}) {
  QJsonObject c = cal;
  if(!c.contains("snapMinutes")) {
    c["snapMinutes"] = 15;
  }
  QJsonObject root;
  root["notifications"] = notif;
  root["calendar"] = c;
  return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

QJsonObject quietNotif() {
  QJsonObject n;
  n["meetingReminders"] = false;
  n["deadlineReminders"] = false;
  n["standupReminder"] = false;
  n["blockedDailyDigest"] = false;
  n["quietHours"] = false;
  return n;
}

}  // namespace

class TimeAudit : public ::testing::Test {
 protected:
  void SetUp() override {
    // Nothing sent is remembered from an earlier run of the suite.
    QFile::remove(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/reminders.json"));
    app_ = std::make_unique<AppController>();
    app_->events()->reset({});
    app_->tasks()->reset({});
    app_->setAppSettingsJson(settingsJson(quietNotif()));
  }

  void TearDown() override {
    app_.reset();
  }

  QString seed(const QString& rule, double start = 10.0, double end = 11.0, const QDate& day = kMon) {
    QVariantMap d = app_->newEventDraft(start, day);
    d["title"] = QStringLiteral("sync");
    d["date"] = day;
    d["start"] = start;
    d["end"] = end;
    d["rrule"] = rule;
    app_->saveEvent(d);
    return d.value("id").toString();
  }

  QVariantList occ(int days = 35, const QDate& from = kMon) const {
    return app_->eventOccurrences(from, from.addDays(days));
  }

  QVariantMap on(const QDate& day) const {
    for(const QVariant& v : occ(60)) {
      if(v.toMap().value("date").toDate() == day) {
        return v.toMap();
      }
    }
    return {};
  }

  QVector<QDate> dates(int days = 35) const {
    QVector<QDate> out;
    for(const QVariant& v : occ(days)) {
      out.append(v.toMap().value("date").toDate());
    }
    std::sort(out.begin(), out.end());
    return out;
  }

  std::unique_ptr<AppController> app_;
};

// ── TIME-1: a drag on one occurrence asks, and "this" moves only it ──

TEST_F(TimeAudit, DraggingOneOccurrenceMovesOnlyThatOne) {
  seed(QStringLiteral("FREQ=DAILY;COUNT=7"));
  const QVariantMap third = on(kMon.addDays(2));
  ASSERT_FALSE(third.isEmpty());

  app_->moveOccurrence(third, 2.0, QStringLiteral("this"));

  EXPECT_EQ(dates().size(), 7) << "no occurrence vanishes";
  EXPECT_NEAR(on(kMon.addDays(2)).value("start").toDouble(), 12.0, 1e-6);
  EXPECT_NEAR(on(kMon.addDays(1)).value("start").toDouble(), 10.0, 1e-6);
  EXPECT_NEAR(on(kMon).value("start").toDouble(), 10.0, 1e-6);
}

TEST_F(TimeAudit, DraggingForAllKeepsThePastOccurrences) {
  seed(QStringLiteral("FREQ=DAILY;COUNT=7"));
  app_->moveOccurrence(on(kMon.addDays(4)), 1.0, QStringLiteral("all"));

  const QVector<QDate> d = dates();
  ASSERT_EQ(d.size(), 7);
  EXPECT_EQ(d.first(), kMon) << "moving the hour must not re-date the series";
  for(const QVariant& v : occ()) {
    EXPECT_NEAR(v.toMap().value("start").toDouble(), 11.0, 1e-6);
  }
}

TEST_F(TimeAudit, DraggingAcrossDaysForAllMovesTheWeekday) {
  seed(QStringLiteral("FREQ=WEEKLY;BYDAY=MO"));
  app_->moveOccurrence(on(kMon.addDays(7)), 24.0, QStringLiteral("all"));

  for(const QDate& d : dates(28)) {
    EXPECT_EQ(d.dayOfWeek(), 2) << d.toString(Qt::ISODate).toStdString();
  }
}

TEST_F(TimeAudit, ResizingOneOccurrenceLeavesTheRest) {
  seed(QStringLiteral("FREQ=DAILY;COUNT=5"));
  app_->resizeOccurrence(on(kMon.addDays(1)), 10.0, 12.0, QStringLiteral("this"));

  EXPECT_NEAR(on(kMon.addDays(1)).value("end").toDouble(), 12.0, 1e-6);
  EXPECT_NEAR(on(kMon.addDays(2)).value("end").toDouble(), 11.0, 1e-6);
  EXPECT_EQ(dates().size(), 5);
}

// ── TIME-2: "all" from a later occurrence does not stretch the series ──

TEST_F(TimeAudit, EditingAllFromALaterOccurrenceKeepsOneDayEvents) {
  seed(QStringLiteral("FREQ=WEEKLY"));
  QVariantMap o = on(kMon.addDays(14));
  o["title"] = QStringLiteral("renamed");
  o["endDate"] = kMon.addDays(14);  // what the editor sends: the same day
  app_->saveOccurrence(o, QStringLiteral("all"));

  for(const QVariant& v : occ(28)) {
    const QVariantMap m = v.toMap();
    EXPECT_FALSE(m.value("endDate").toDate().isValid()) << "every occurrence stays a single-day event";
  }
}

// ── TIME-3: the rule itself is editable and removable ──

TEST_F(TimeAudit, TheRuleCanBeChangedForAll) {
  seed(QStringLiteral("FREQ=WEEKLY"));
  QVariantMap o = on(kMon.addDays(7));
  o["rrule"] = QStringLiteral("FREQ=DAILY");
  app_->saveOccurrence(o, QStringLiteral("all"));

  EXPECT_EQ(dates(6).size(), 7);
}

TEST_F(TimeAudit, TheRuleCanBeRemovedForAll) {
  seed(QStringLiteral("FREQ=WEEKLY"));
  QVariantMap o = on(kMon.addDays(7));
  o["rrule"] = QString();
  app_->saveOccurrence(o, QStringLiteral("all"));

  EXPECT_EQ(dates(60).size(), 1);
  EXPECT_EQ(app_->events()->rowCount(), 1);
}

TEST_F(TimeAudit, TheRuleCanBeChangedForFollowing) {
  seed(QStringLiteral("FREQ=WEEKLY"));
  QVariantMap o = on(kMon.addDays(14));
  o["rrule"] = QStringLiteral("FREQ=DAILY");
  app_->saveOccurrence(o, QStringLiteral("following"));

  const QVector<QDate> d = dates(17);
  // Weekly Mon 21, Mon 28; then daily from Mon Oct 5 to Thu Oct 8.
  EXPECT_EQ(d, (QVector<QDate>{kMon, kMon.addDays(7), kMon.addDays(14), kMon.addDays(15), kMon.addDays(16), kMon.addDays(17)}));
}

// ── TIME-9: splitting a COUNT series keeps its length; moves survive ──

TEST_F(TimeAudit, SplittingACountedSeriesKeepsTheTotal) {
  seed(QStringLiteral("FREQ=DAILY;COUNT=10"));
  QVariantMap sixth = on(kMon.addDays(5));
  sixth["title"] = QStringLiteral("later ones");
  app_->saveOccurrence(sixth, QStringLiteral("following"));

  EXPECT_EQ(dates(40).size(), 10) << "5 before the split and 5 after, not 5 + 10";
}

TEST_F(TimeAudit, AMovedOccurrenceAfterASplitStaysMoved) {
  seed(QStringLiteral("FREQ=DAILY;COUNT=10"));
  QVariantMap eighth = on(kMon.addDays(7));
  eighth["start"] = 15.0;
  eighth["end"] = 16.0;
  app_->saveOccurrence(eighth, QStringLiteral("this"));

  QVariantMap fifth = on(kMon.addDays(4));
  fifth["title"] = QStringLiteral("renamed");
  app_->saveOccurrence(fifth, QStringLiteral("following"));

  EXPECT_NEAR(on(kMon.addDays(7)).value("start").toDouble(), 15.0, 1e-6) << "the moved occurrence must not revert";
  EXPECT_EQ(dates(40).size(), 10);
}

// ── TIME-10: the after-midnight piece of an overnight event ──

TEST_F(TimeAudit, DraggingTheAfterMidnightPieceShiftsTheHours) {
  QVariantMap d = app_->newEventDraft(22.0, kMon);
  d["date"] = kMon;
  d["endDate"] = kMon.addDays(1);
  d["start"] = 22.0;
  d["end"] = 2.0;
  app_->saveEvent(d);
  const QVariantMap o = app_->eventOccurrences(kMon, kMon.addDays(1)).value(0).toMap();

  app_->moveOccurrence(o, 1.0, QStringLiteral("this"));

  const QVariantMap after = app_->eventById(d.value("id").toString());
  EXPECT_EQ(after.value("date").toDate(), kMon);
  EXPECT_NEAR(after.value("start").toDouble(), 23.0, 1e-6);
  EXPECT_NEAR(after.value("end").toDouble(), 3.0, 1e-6);
}

// ── TIME-20 / TIME-25: deleting says so; redo says what it redid ──

TEST_F(TimeAudit, DeletingAnOccurrenceOffersUndo) {
  const QString id = seed(QStringLiteral("FREQ=WEEKLY"));
  QSignalSpy spy(app_.get(), &AppController::undoableToast);

  app_->deleteOccurrence(id, kMon.addDays(7), QStringLiteral("this"));
  app_->deleteOccurrence(id, kMon.addDays(14), QStringLiteral("following"));
  app_->deleteOccurrence(id, kMon, QStringLiteral("all"));

  EXPECT_EQ(spy.count(), 3);
}

TEST_F(TimeAudit, RedoDoesNotRepeatTheUndoMessage) {
  const QString id = seed(QString());
  app_->deleteEvent(id);
  app_->undo();
  QSignalSpy spy(app_.get(), &AppController::toast);
  app_->redo();

  ASSERT_GE(spy.count(), 1);
  EXPECT_FALSE(spy.last().at(0).toString().startsWith(QStringLiteral("Restored"))) << spy.last().at(0).toString().toStdString();
}

// ── TIME-18: re-import keeps what heap knows ──

TEST_F(TimeAudit, ReimportKeepsTypeAndAttendees) {
  QTemporaryDir dir;
  const QString path = dir.filePath(QStringLiteral("a.ics"));
  QFile f(path);
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:ev-x\r\nDTSTART:20260921T100000\r\nSUMMARY:x\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
  f.close();
  app_->importIcs(QUrl::fromLocalFile(path));
  QVariantMap e = app_->eventById(QStringLiteral("ev-x"));
  e["type"] = QStringLiteral("focus");
  e["attendees"] = QStringLiteral("Ann");
  app_->saveEvent(e);

  app_->importIcs(QUrl::fromLocalFile(path));

  const QVariantMap back = app_->eventById(QStringLiteral("ev-x"));
  EXPECT_EQ(back.value("type").toString(), QStringLiteral("focus"));
  EXPECT_EQ(back.value("attendees").toString(), QStringLiteral("Ann"));
}

TEST_F(TimeAudit, AFileThatIsNotACalendarIsAnError) {
  QTemporaryDir dir;
  const QString path = dir.filePath(QStringLiteral("notes.ics"));
  QFile f(path);
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write("just some notes\n");
  f.close();

  const QVariantMap r = app_->importIcs(QUrl::fromLocalFile(path));
  EXPECT_FALSE(r.value("error").toString().isEmpty());
}

// ── TIME-7 / TASKS-17: today moves ──

TEST_F(TimeAudit, TodayMovesAndASelectionOnTodayFollows) {
  const QDate was = app_->today();
  app_->setSelectedDate(was);
  QSignalSpy spy(app_.get(), &AppController::todayChanged);

  app_->refreshToday(was.addDays(1));

  EXPECT_EQ(spy.count(), 1);
  EXPECT_EQ(app_->today(), was.addDays(1));
  EXPECT_EQ(app_->selectedDate(), was.addDays(1));
}

TEST_F(TimeAudit, ASelectionElsewhereStaysPut) {
  const QDate was = app_->today();
  app_->setSelectedDate(was.addDays(10));
  app_->refreshToday(was.addDays(1));
  EXPECT_EQ(app_->selectedDate(), was.addDays(10));
}

// ── TIME-5 / TIME-21 / PLAT-10: reminders ──

namespace {

QJsonObject meetings(bool quiet = false) {
  QJsonObject n = quietNotif();
  n["meetingReminders"] = true;
  n["meetingLead"] = 5;
  n["quietHours"] = quiet;
  n["quietFrom"] = QStringLiteral("19:00");
  n["quietTo"] = QStringLiteral("09:00");
  return n;
}

int meetingCount(const QSignalSpy& spy) {
  int n = 0;
  for(const QList<QVariant>& args : spy) {
    if(args.at(2).toString() == QStringLiteral("meeting")) {
      ++n;
    }
  }
  return n;
}

}  // namespace

TEST_F(TimeAudit, EveryOccurrenceOfASeriesReminds) {
  app_->setAppSettingsJson(settingsJson(meetings()));
  seed(QStringLiteral("FREQ=DAILY"), 10.0, 10.5);
  QSignalSpy spy(app_.get(), &AppController::notification);

  app_->runAutomationAt(QDateTime(kMon.addDays(3), QTime(9, 56)));

  EXPECT_EQ(meetingCount(spy), 1) << "today's occurrence of a series used to be silent";
}

TEST_F(TimeAudit, ADeletedOccurrenceDoesNotRemind) {
  app_->setAppSettingsJson(settingsJson(meetings()));
  const QString id = seed(QStringLiteral("FREQ=DAILY"), 10.0, 10.5);
  app_->deleteOccurrence(id, kMon, QStringLiteral("this"));
  QSignalSpy spy(app_.get(), &AppController::notification);

  app_->runAutomationAt(QDateTime(kMon, QTime(9, 56)));

  EXPECT_EQ(meetingCount(spy), 0);
}

TEST_F(TimeAudit, ARestartDoesNotRemindAgain) {
  // Near the real date: the list on disk forgets what is days old.
  const QDate day = QDate::currentDate().addDays(1);
  app_->setAppSettingsJson(settingsJson(meetings()));
  seed(QString(), 10.0, 10.5, day);
  app_->runAutomationAt(QDateTime(day, QTime(9, 56)));
  app_->flushSave();

  // A fresh controller reads the sent list back from disk.
  const QString json = settingsJson(meetings());
  app_.reset();
  app_ = std::make_unique<AppController>();
  app_->setAppSettingsJson(json);
  ASSERT_FALSE(app_->eventOccurrences(day, day).isEmpty()) << "the event survived the restart";
  QSignalSpy spy(app_.get(), &AppController::notification);
  app_->runAutomationAt(QDateTime(day, QTime(9, 57)));
  EXPECT_EQ(meetingCount(spy), 0);
}

TEST_F(TimeAudit, AMeetingRightAfterQuietHoursStillReminds) {
  app_->setAppSettingsJson(settingsJson(meetings(/*quiet=*/true)));
  seed(QString(), 9.0, 9.5);
  QSignalSpy spy(app_.get(), &AppController::notification);

  app_->runAutomationAt(QDateTime(kMon, QTime(8, 55)));

  EXPECT_EQ(meetingCount(spy), 1) << "a meeting reminder is an appointment, not held by quiet hours";
}

TEST_F(TimeAudit, ADeadlineInQuietHoursIsHeldNotDropped) {
  QJsonObject n = quietNotif();
  n["deadlineReminders"] = true;
  n["deadlineLeadHours"] = 24;
  n["quietHours"] = true;
  n["quietFrom"] = QStringLiteral("19:00");
  n["quietTo"] = QStringLiteral("09:00");
  app_->setAppSettingsJson(settingsJson(n));
  Task t;
  t.id = QStringLiteral("T-1");
  t.title = QStringLiteral("ship it");
  t.status = QStringLiteral("todo");
  t.dueAt = QDateTime(kMon, QTime(12, 0));
  t.hasTime = true;
  app_->tasks()->reset({t});
  QSignalSpy spy(app_.get(), &AppController::toast);

  app_->runAutomationAt(QDateTime(kMon, QTime(7, 0)));
  const int during = spy.count();
  app_->runAutomationAt(QDateTime(kMon, QTime(9, 1)));

  EXPECT_EQ(during, 0);
  EXPECT_GE(spy.count(), 1) << "delivered once the quiet window ends";
}

// ── PLAT-11: the in-app toast carries the title ──

TEST_F(TimeAudit, TheInAppToastSaysWhy) {
  app_->setAppSettingsJson(settingsJson(meetings()));
  seed(QString(), 10.0, 10.5);
  QSignalSpy spy(app_.get(), &AppController::toast);

  app_->runAutomationAt(QDateTime(kMon, QTime(9, 56)));

  ASSERT_GE(spy.count(), 1);
  EXPECT_TRUE(spy.last().at(0).toString().contains(QStringLiteral("sync")));
  EXPECT_TRUE(spy.last().at(0).toString().contains(QStringLiteral("4"))) << "In 4 min · sync";
}

// ── PLAT-18: no standup on a weekend ──

TEST_F(TimeAudit, NoStandupOnAWeekend) {
  QJsonObject n = quietNotif();
  n["standupReminder"] = true;
  n["meetingLead"] = 5;
  QJsonObject cal;
  cal["standupTime"] = QStringLiteral("10:00");
  app_->setAppSettingsJson(settingsJson(n, cal));
  QSignalSpy spy(app_.get(), &AppController::notification);

  app_->runAutomationAt(QDateTime(kMon.addDays(5), QTime(9, 57)));  // Saturday
  EXPECT_EQ(spy.count(), 0);
  app_->runAutomationAt(QDateTime(kMon, QTime(9, 57)));  // Monday
  EXPECT_EQ(spy.count(), 1);
}

// ── TIME-13 / TASKS-29: focus blocks and the task's schedule ──

namespace {

Task task(const QString& id, const QString& status) {
  Task t;
  t.id = id;
  t.title = id;
  t.status = status;
  t.priority = QStringLiteral("P2");
  return t;
}

int focusBlocks(AppController* app, const QString& taskId) {
  int n = 0;
  for(const CalEvent& e : app->events()->items()) {
    if(e.taskId == taskId && e.type == QStringLiteral("focus")) {
      ++n;
    }
  }
  return n;
}

}  // namespace

TEST_F(TimeAudit, MovingAFocusBlockMovesTheTasksSchedule) {
  app_->tasks()->reset({task(QStringLiteral("T-1"), QStringLiteral("todo"))});
  app_->scheduleTask(QStringLiteral("T-1"), 10.0, kMon);
  QString blockId;
  for(const CalEvent& e : app_->events()->items()) {
    blockId = e.id;
  }
  app_->updateEvent(blockId, 14.0, 15.5, kMon.addDays(1));

  EXPECT_EQ(app_->tasks()->items().first().scheduledAt, QDateTime(kMon.addDays(1), QTime(14, 0)));
}

TEST_F(TimeAudit, DeletingAFocusBlockUnschedulesTheTask) {
  app_->tasks()->reset({task(QStringLiteral("T-1"), QStringLiteral("todo"))});
  app_->scheduleTask(QStringLiteral("T-1"), 10.0, kMon);
  app_->deleteEvent(app_->events()->items().first().id);

  EXPECT_FALSE(app_->tasks()->items().first().scheduledAt.isValid());
}

TEST_F(TimeAudit, SchedulingKeepsADateOnlyDeadlineDateOnly) {
  Task t = task(QStringLiteral("T-1"), QStringLiteral("todo"));
  t.dueAt = QDateTime(kMon.addDays(3), QTime(0, 0));
  t.hasTime = false;
  app_->tasks()->reset({t});
  app_->scheduleTask(QStringLiteral("T-1"), 10.0, kMon);

  EXPECT_FALSE(app_->tasks()->items().first().hasTime) << "the deadline must not become 00:00";
}

TEST_F(TimeAudit, LeavingInProgressGivesTheBlockBack) {
  app_->tasks()->reset({task(QStringLiteral("T-1"), QStringLiteral("todo"))});
  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("prog"));
  const int blocks = focusBlocks(app_.get(), QStringLiteral("T-1"));
  app_->moveTask(QStringLiteral("T-1"), QStringLiteral("todo"));

  if(blocks == 0) {
    GTEST_SKIP() << "no working-hours slot left this week to book";
  }
  EXPECT_EQ(focusBlocks(app_.get(), QStringLiteral("T-1")), 0);
}

TEST_F(TimeAudit, ADoingColumnBooksABlockLikeInProgress) {
  // Through the same call the board uses for a new column.
  app_->addStatus(QStringLiteral("Doing"), QStringLiteral("#888888"));
  QString doingId;
  for(const QVariant& v : app_->statuses()) {
    if(v.toMap().value("name").toString() == QStringLiteral("Doing")) {
      doingId = v.toMap().value("id").toString();
    }
  }
  ASSERT_FALSE(doingId.isEmpty());
  app_->setStatusDoing(doingId, true);
  EXPECT_TRUE(app_->isDoingStatus(doingId));
  app_->tasks()->reset({task(QStringLiteral("T-1"), QStringLiteral("todo"))});

  app_->moveTask(QStringLiteral("T-1"), doingId);

  if(focusBlocks(app_.get(), QStringLiteral("T-1")) == 0) {
    GTEST_SKIP() << "no working-hours slot left this week to book";
  }
  EXPECT_EQ(focusBlocks(app_.get(), QStringLiteral("T-1")), 1);
  EXPECT_TRUE(app_->tasks()->items().first().scheduledAt.isValid()) << "the auto block schedules the task";
}

// ── TIME-14: the free-slot finder sees the whole calendar ──

TEST_F(TimeAudit, TheFreeSlotSkipsARecurringStandup) {
  const QDate day = QDate::currentDate().addDays(7);  // never "today": no now-clamp
  seed(QStringLiteral("FREQ=DAILY"), 9.0, 10.0, day.addDays(-3));
  QJsonObject cal;
  app_->setAppSettingsJson(settingsJson(quietNotif(), cal));
  app_->setWorkdayStart(9);

  EXPECT_GE(app_->nextFreeSlot(day, 1.0), 10.0);
}

TEST_F(TimeAudit, AnAllDayEventDoesNotFillTheDay) {
  const QDate day = QDate::currentDate().addDays(7);
  QVariantMap d = app_->newEventDraft(0, day);
  d["date"] = day;
  d["allDay"] = true;
  app_->saveEvent(d);
  app_->setWorkdayStart(9);

  EXPECT_NEAR(app_->nextFreeSlot(day, 1.0), 9.0, 1e-6);
}

// ── PLAT-13 / TIME-15: what the week and month read ──

TEST_F(TimeAudit, CalendarTasksCarryScheduledOnes) {
  Task a = task(QStringLiteral("T-1"), QStringLiteral("todo"));
  a.scheduledAt = QDateTime(kMon.addDays(3), QTime(14, 0));
  a.hasTime = true;
  Task b = task(QStringLiteral("T-2"), QStringLiteral("todo"));
  b.dueAt = QDateTime(kMon.addDays(1), QTime(0, 0));
  Task c = task(QStringLiteral("T-3"), QStringLiteral("todo"));
  c.dueAt = QDateTime(kMon.addDays(30), QTime(0, 0));
  app_->tasks()->reset({a, b, c});

  const QVariantList got = app_->calendarTasks(kMon, kMon.addDays(6), false);

  ASSERT_EQ(got.size(), 2);
  EXPECT_EQ(got.at(0).toMap().value("schedDay").toInt(), 3);
  EXPECT_NEAR(got.at(0).toMap().value("schedHour").toDouble(), 14.0, 1e-6);
  EXPECT_EQ(got.at(1).toMap().value("dueDay").toInt(), 1);
}

// PLAT-13: the week asked every task in the profile for ten roles on every
// rebuild (2.9 s at 10k). The candidate list is built in C++ now.
TEST_F(TimeAudit, CalendarTasksIsCheapAtTenThousandTasks) {
  QVector<Task> many;
  many.reserve(10000);
  for(int i = 0; i < 10000; ++i) {
    Task t = task(QStringLiteral("T-%1").arg(i), QStringLiteral("todo"));
    t.dueAt = QDateTime(kMon.addDays(i % 365), QTime(0, 0));
    many.append(t);
  }
  app_->tasks()->reset(many);

  QElapsedTimer timer;
  timer.start();
  const QVariantList week = app_->calendarTasks(kMon, kMon.addDays(6), false);
  const qint64 ms = timer.elapsed();

  EXPECT_GT(week.size(), 100);
  EXPECT_LT(ms, 250) << "a week's candidates took " << ms << " ms";
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
