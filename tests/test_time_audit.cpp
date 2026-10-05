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

// The raw updateEvent on a series master no longer re-dates it to the day
// one occurrence was dropped on.
TEST_F(TimeAudit, UpdateEventOnAMasterKeepsTheSeriesStart) {
  const QString id = seed(QStringLiteral("FREQ=DAILY;COUNT=7"));
  app_->updateEvent(id, 10.5, 11.5, kMon.addDays(4));

  const QVector<QDate> d = dates();
  ASSERT_EQ(d.size(), 7);
  EXPECT_EQ(d.first(), kMon);
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

// ── TIME-25 (audit 2026-09-30): another heap's ev-2 is not ours ──

TEST_F(TimeAudit, AnotherHeapsEventWithOurIdIsANewEvent) {
  const QString id = seed(QString());
  const QString title = app_->eventById(id).value("title").toString();
  QTemporaryDir dir;
  const QString path = dir.filePath(QStringLiteral("colleague.ics"));
  QFile f(path);
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write(QStringLiteral("BEGIN:VCALENDAR\r\nPRODID:-//heap//EN\r\nBEGIN:VEVENT\r\nUID:%1@0123456789ab.heap\r\n"
                         "DTSTART:20261105T100000\r\nSUMMARY:Colleague's design review\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
              .arg(id)
              .toUtf8());
  f.close();

  const QVariantMap r = app_->importIcs(QUrl::fromLocalFile(path));

  EXPECT_EQ(r.value("imported").toInt(), 1);
  EXPECT_EQ(r.value("updated").toInt(), 0);
  EXPECT_EQ(app_->events()->rowCount(), 2);
  EXPECT_EQ(app_->eventById(id).value("title").toString(), title) << "our own event is left alone";
}

TEST_F(TimeAudit, OurOwnExportComesBackAsAnUpdate) {
  const QString id = seed(QString());
  QTemporaryDir dir;
  const QString path = dir.filePath(QStringLiteral("mine.ics"));
  ASSERT_TRUE(app_->exportIcsToFile(QUrl::fromLocalFile(path)));
  QFile f(path);
  ASSERT_TRUE(f.open(QIODevice::ReadOnly));
  const QString text = QString::fromUtf8(f.readAll());
  f.close();
  EXPECT_TRUE(text.contains(QStringLiteral("UID:") + id + QLatin1Char('@') + app_->icsUidDomain())) << text.toStdString();

  const QVariantMap r = app_->importIcs(QUrl::fromLocalFile(path));

  EXPECT_EQ(r.value("imported").toInt(), 0);
  EXPECT_EQ(r.value("updated").toInt(), 1);
  EXPECT_EQ(app_->events()->rowCount(), 1);
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
  t.dueHasTime = true;
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
  t.dueHasTime = false;
  app_->tasks()->reset({t});
  app_->scheduleTask(QStringLiteral("T-1"), 10.0, kMon);

  EXPECT_FALSE(app_->tasks()->items().first().dueHasTime) << "the deadline must not become 00:00";
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
  a.scheduledHasTime = true;
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

// ── B·A tier of the 2026-09-30 audit: series edits and .ics round trips ──

namespace {

QVector<QDate> datesOf(const QVariantList& occurrences) {
  QVector<QDate> out;
  for(const QVariant& v : occurrences) {
    out.append(v.toMap().value("date").toDate());
  }
  std::sort(out.begin(), out.end());
  return out;
}

QVariantMap occurrenceOn(AppController& app, const QDate& day) {
  return app.eventOccurrences(day, day).value(0).toMap();
}

bool writeFile(const QString& path, const QString& text) {
  QFile f(path);
  if(!f.open(QIODevice::WriteOnly)) {
    return false;
  }
  f.write(text.toUtf8());
  return true;
}

}  // namespace

// TIME-3: the editor hands an imported "BYDAY=TU" weekly rule back without
// the BYDAY; the split still knows it is the same rule and the same COUNT.
TEST_F(TimeAudit, SplittingAnImportedCountedSeriesKeepsTheTotal) {
  const QDate tue(2031, 4, 1);
  seed(QStringLiteral("FREQ=WEEKLY;BYDAY=TU;COUNT=6"), 10.0, 11.0, tue);
  QVariantMap fourth = occurrenceOn(*app_, QDate(2031, 4, 22));
  ASSERT_FALSE(fourth.isEmpty());
  fourth["title"] = QStringLiteral("renamed");
  fourth["rrule"] = QStringLiteral("FREQ=WEEKLY;COUNT=6");

  app_->saveOccurrence(fourth, QStringLiteral("following"));

  const QVariantList all = app_->eventOccurrences(tue, tue.addDays(120));
  EXPECT_EQ(all.size(), 6) << "3 before the split and 3 after, not 3 + 6";
  int renamed = 0;
  for(const QVariant& v : all) {
    renamed += v.toMap().value("title").toString() == QStringLiteral("renamed") ? 1 : 0;
  }
  EXPECT_EQ(renamed, 3);
}

// TIME-5: a Tue/Thu meeting created on a Monday starts on Tuesday.
TEST_F(TimeAudit, ASeriesCreatedOffItsDaysStartsOnTheFirstOfThem) {
  const QDate mon(2031, 6, 2);
  seed(QStringLiteral("FREQ=WEEKLY;BYDAY=TU,TH;COUNT=4"), 10.0, 11.0, mon);

  EXPECT_EQ(datesOf(app_->eventOccurrences(mon, mon.addDays(30))),
            (QVector<QDate>{QDate(2031, 6, 3), QDate(2031, 6, 5), QDate(2031, 6, 10), QDate(2031, 6, 12)}))
      << "no Monday occurrence, and it does not eat one of the four";
}

// TIME-5: renaming a series that legally starts off its days (as an import
// may) leaves its start alone.
TEST_F(TimeAudit, RenamingAnOffDaySeriesKeepsItsStart) {
  const QDate mon(2031, 6, 2);
  const QString id = seed(QStringLiteral("FREQ=WEEKLY;BYDAY=TU"), 10.0, 11.0, mon.addDays(1));
  CalEvent stored = app_->events()->items().at(app_->events()->indexOfId(id));
  stored.date = mon;  // as an RFC import would store it
  app_->events()->upsert(stored);
  QVariantMap e = app_->eventById(id);
  e["title"] = QStringLiteral("renamed");

  app_->saveEvent(e);

  EXPECT_EQ(app_->eventById(id).value("date").toDate(), mon);
}

// TIME-7: moving "all" of a series on the 15th to the 16th moves every one.
TEST_F(TimeAudit, MovingAMonthDaySeriesForAllMovesEveryOccurrence) {
  const QDate first(2031, 8, 15);
  const QString id = seed(QStringLiteral("FREQ=MONTHLY;BYMONTHDAY=15"), 10.0, 11.0, first);
  app_->deleteOccurrence(id, QDate(2031, 10, 15), QStringLiteral("this"));

  app_->moveOccurrence(occurrenceOn(*app_, QDate(2031, 9, 15)), 24.0, QStringLiteral("all"));

  EXPECT_EQ(datesOf(app_->eventOccurrences(first, QDate(2031, 11, 30))),
            (QVector<QDate>{QDate(2031, 8, 16), QDate(2031, 9, 16), QDate(2031, 11, 16)}))
      << "the deleted October one stays deleted";
}

// TIME-7: the second Tuesday dropped on the following Wednesday (the 3rd
// Wednesday that month) is "the third Wednesday" from then on.
TEST_F(TimeAudit, MovingAnOrdinalWeekdaySeriesForAllRereadsTheDay) {
  const QDate first(2031, 9, 9);  // the second Tuesday of September
  seed(QStringLiteral("FREQ=MONTHLY;BYDAY=2TU"), 10.0, 11.0, first);

  app_->moveOccurrence(occurrenceOn(*app_, QDate(2031, 10, 14)), 24.0, QStringLiteral("all"));

  EXPECT_EQ(datesOf(app_->eventOccurrences(QDate(2031, 9, 1), QDate(2031, 11, 30))),
            (QVector<QDate>{QDate(2031, 9, 17), QDate(2031, 10, 15), QDate(2031, 11, 19)}));
}

// TIME-7: a rule the new day cannot be said in is left whole and says why.
TEST_F(TimeAudit, AnUnmovableRuleIsNotMovedInPart) {
  const QDate first(2031, 9, 1);  // the first Monday
  const QString id = seed(QStringLiteral("FREQ=MONTHLY;BYDAY=1MO,3MO"), 10.0, 11.0, first);
  QSignalSpy spy(app_.get(), &AppController::toast);

  app_->moveOccurrence(occurrenceOn(*app_, QDate(2031, 9, 15)), 24.0, QStringLiteral("all"));

  EXPECT_EQ(app_->eventById(id).value("date").toDate(), first);
  EXPECT_EQ(app_->eventById(id).value("rrule").toString(), QStringLiteral("FREQ=MONTHLY;BYDAY=1MO,3MO"));
  EXPECT_EQ(spy.count(), 1);
}

// TIME-9: a file that only cancels one occurrence of a stored series
// deletes it there.
TEST_F(TimeAudit, AnImportedCancellationDeletesTheStoredOccurrence) {
  const QDate mon(2031, 6, 2);
  const QString id = seed(QStringLiteral("FREQ=WEEKLY"), 10.0, 11.0, mon);
  QTemporaryDir dir;
  const QString path = dir.filePath(QStringLiteral("cancel.ics"));
  ASSERT_TRUE(writeFile(path,
                        QStringLiteral("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:%1@%2\r\n"
                                       "RECURRENCE-ID:20310609T100000\r\nSTATUS:CANCELLED\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
                            .arg(id, app_->icsUidDomain())));

  const QVariantMap r = app_->importIcs(QUrl::fromLocalFile(path));

  EXPECT_EQ(r.value("skipped").toInt(), 0);
  EXPECT_EQ(datesOf(app_->eventOccurrences(mon, mon.addDays(14))), (QVector<QDate>{mon, mon.addDays(14)}));
}

// TIME-10: our own export with a moved occurrence comes back as an update,
// however many times, and an earlier import's double is folded away.
TEST_F(TimeAudit, ReimportingOurExportDoesNotDoubleMovedOccurrences) {
  const QDate mon(2031, 3, 3);
  seed(QStringLiteral("FREQ=WEEKLY;COUNT=4"), 10.0, 11.0, mon);
  app_->moveOccurrence(occurrenceOn(*app_, mon.addDays(14)), 2.0, QStringLiteral("this"));
  ASSERT_EQ(app_->events()->rowCount(), 2);
  QTemporaryDir dir;
  const QString path = dir.filePath(QStringLiteral("mine.ics"));
  ASSERT_TRUE(app_->exportIcsToFile(QUrl::fromLocalFile(path)));

  for(int round = 0; round < 2; ++round) {
    const QVariantMap r = app_->importIcs(QUrl::fromLocalFile(path));
    EXPECT_EQ(r.value("imported").toInt(), 0) << "round " << round;
    EXPECT_EQ(r.value("updated").toInt(), 2) << "round " << round;
    EXPECT_EQ(app_->events()->rowCount(), 2) << "round " << round;
  }

  // The state an older build's import left: a second override of that date.
  CalEvent dup = app_->events()->items().at(1).masterId.isEmpty() ? app_->events()->items().at(0) : app_->events()->items().at(1);
  dup.id = dup.masterId + QStringLiteral("-20310317");
  app_->events()->upsert(dup);
  ASSERT_EQ(app_->events()->rowCount(), 3);
  app_->importIcs(QUrl::fromLocalFile(path));
  EXPECT_EQ(app_->events()->rowCount(), 2) << "the double is folded into one override";
  EXPECT_NEAR(occurrenceOn(*app_, mon.addDays(14)).value("start").toDouble(), 12.0, 1e-6);
}

// ── APP-122: auto-archive for any column ──

TEST_F(TimeAudit, AnyColumnArchivesAfterItsOwnDays) {
  app_->addStatus(QStringLiteral("Obsolete"));
  const QString obsolete = app_->statuses().constLast().toMap().value("id").toString();
  ASSERT_FALSE(obsolete.isEmpty());
  EXPECT_EQ(app_->statusArchiveDays(obsolete), 0) << "a new column never archives by default";
  app_->setStatusArchiveDays(obsolete, 3);
  EXPECT_EQ(app_->statusArchiveDays(obsolete), 3);

  const QDateTime moved(kMon, QTime(10, 0));
  Task old;
  old.id = QStringLiteral("OB-1");
  old.status = obsolete;
  old.statusChangedAt = moved;
  Task fresh = old;
  fresh.id = QStringLiteral("OB-2");
  fresh.statusChangedAt = moved.addDays(2);
  Task todo = old;
  todo.id = QStringLiteral("TD-1");
  todo.status = QStringLiteral("todo");
  app_->tasks()->reset({old, fresh, todo});

  app_->runAutomationAt(moved.addDays(3));
  EXPECT_TRUE(app_->tasks()->items().at(0).archived) << "three days in Obsolete";
  EXPECT_FALSE(app_->tasks()->items().at(1).archived) << "one day in Obsolete";
  EXPECT_FALSE(app_->tasks()->items().at(2).archived) << "To Do has no limit";
}

// Done keeps one number, the Settings → Tasks slider; the column menu writes
// the same one.
TEST_F(TimeAudit, DoneArchiveDaysAreTheSettingsSlider) {
  EXPECT_EQ(app_->statusArchiveDays(QStringLiteral("done")), 7) << "the slider's default";
  app_->setStatusArchiveDays(QStringLiteral("done"), 2);
  EXPECT_EQ(app_->settingsMapForTest().value("tasks").toMap().value("archiveDoneAfterDays").toInt(), 2);
  EXPECT_EQ(app_->statusArchiveDays(QStringLiteral("done")), 2);
  app_->setStatusArchiveDays(QStringLiteral("done"), 0);
  Task done;
  done.id = QStringLiteral("DN-1");
  done.status = QStringLiteral("done");
  done.statusChangedAt = QDateTime(kMon, QTime(10, 0));
  app_->tasks()->reset({done});
  app_->runAutomationAt(QDateTime(kMon.addDays(60), QTime(10, 0)));
  EXPECT_FALSE(app_->tasks()->items().at(0).archived) << "0 = never";
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
