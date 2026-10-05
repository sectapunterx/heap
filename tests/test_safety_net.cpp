// The safety net's rules (APP-157…), pure: every one takes `now` as an
// argument, so nothing here depends on when the suite runs.

#include "safety/EndOfDay.h"
#include "safety/SafetyText.h"
#include "safety/WaitingOn.h"

#include <gtest/gtest.h>

using namespace heap::safety;

namespace {

const QDate kDay(2026, 10, 6);
const QDateTime kEvening(kDay, QTime(18, 5));

}  // namespace

// ── APP-157: when the end-of-day check runs ──

TEST(EndOfDayFire, NotBeforeTheSetTime) {
  EXPECT_FALSE(shouldFireToday({}, QDateTime(kDay, QTime(17, 59)), QTime(18, 0)));
}

TEST(EndOfDayFire, AtTheSetTimeAndAfterIt) {
  EXPECT_TRUE(shouldFireToday({}, QDateTime(kDay, QTime(18, 0)), QTime(18, 0)));
  EXPECT_TRUE(shouldFireToday({}, QDateTime(kDay, QTime(21, 30)), QTime(18, 0)));
}

TEST(EndOfDayFire, OnceADay) {
  EXPECT_FALSE(shouldFireToday(kDay, kEvening, QTime(18, 0)));
  // Yesterday's run does not count for today.
  EXPECT_TRUE(shouldFireToday(kDay.addDays(-1), kEvening, QTime(18, 0)));
}

// A day missed while the app was closed is not made up the next morning.
TEST(EndOfDayFire, AMissedDayIsNotMadeUpNextMorning) {
  EXPECT_FALSE(shouldFireToday(kDay.addDays(-2), QDateTime(kDay, QTime(9, 0)), QTime(18, 0)));
}

TEST(EndOfDayFire, AnInvalidTimeNeverFires) {
  EXPECT_FALSE(shouldFireToday({}, kEvening, QTime()));
}

// ── APP-157: what it says ──

TEST(EndOfDayFindings, NothingToSayWhenAllIsWell) {
  EndOfDayFacts facts;
  facts.inProgress.append({.taskId = QStringLiteral("A-1"), .lastActivity = kEvening.addDays(-1)});
  const EndOfDayFindings f = endOfDayFindings(facts, kEvening, {});
  EXPECT_FALSE(f.any());
}

TEST(EndOfDayFindings, ARunningTimerIsSaid) {
  EndOfDayFacts facts;
  facts.runningTimerTaskIds << QStringLiteral("A-1");
  const EndOfDayFindings f = endOfDayFindings(facts, kEvening, {});
  EXPECT_TRUE(f.any());
  EXPECT_EQ(f.timerTaskIds, QStringList{QStringLiteral("A-1")});
  EXPECT_EQ(f.taskIds(), QStringList{QStringLiteral("A-1")});
}

TEST(EndOfDayFindings, StaleIsOlderThanTheSetDays) {
  EndOfDayFacts facts;
  facts.inProgress.append({.taskId = QStringLiteral("old"), .lastActivity = kEvening.addDays(-3)});
  facts.inProgress.append({.taskId = QStringLiteral("fresh"), .lastActivity = kEvening.addDays(-2)});
  EndOfDaySettings s;
  s.staleDays = 3;
  const EndOfDayFindings f = endOfDayFindings(facts, kEvening, s);
  EXPECT_EQ(f.staleTaskIds, QStringList{QStringLiteral("old")});
}

// heap cannot tell "untouched for a week" from "no history at all".
TEST(EndOfDayFindings, UnknownActivityIsNeverStale) {
  EndOfDayFacts facts;
  facts.inProgress.append({.taskId = QStringLiteral("A-1"), .lastActivity = {}});
  EXPECT_FALSE(endOfDayFindings(facts, kEvening, {}).any());
}

// A task with its timer running is being worked on, and is said once.
TEST(EndOfDayFindings, ATimedTaskIsNotAlsoStale) {
  EndOfDayFacts facts;
  facts.runningTimerTaskIds << QStringLiteral("A-1");
  facts.inProgress.append({.taskId = QStringLiteral("A-1"), .lastActivity = kEvening.addDays(-10)});
  const EndOfDayFindings f = endOfDayFindings(facts, kEvening, {});
  EXPECT_TRUE(f.staleTaskIds.isEmpty());
  EXPECT_EQ(f.taskIds().size(), 1);
}

TEST(EndOfDayFindings, DirtNamesTheRepo) {
  EndOfDayFacts facts;
  facts.dirt = {.repo = QStringLiteral("heap"), .changedFiles = 3, .stashes = 1};
  const EndOfDayFindings f = endOfDayFindings(facts, kEvening, {});
  EXPECT_TRUE(f.any());
  EXPECT_EQ(f.changedFiles, 3);
  EXPECT_EQ(f.stashes, 1);
  EXPECT_EQ(f.repo, QStringLiteral("heap"));
}

TEST(EndOfDayFindings, NewestIgnoresInvalidTimes) {
  const QDateTime a = kEvening.addDays(-5);
  const QDateTime b = kEvening.addDays(-1);
  EXPECT_EQ(newest({a, QDateTime(), b}), b);
  EXPECT_FALSE(newest({QDateTime(), QDateTime()}).isValid());
}

TEST(EndOfDayGit, PorcelainCountsOnePerPath) {
  EXPECT_EQ(countPorcelainEntries(" M src/a.cpp\n?? notes.txt\nR  old -> new\n"), 3);
  EXPECT_EQ(countPorcelainEntries(""), 0);
}

TEST(EndOfDayGit, StashListCountsEntries) {
  EXPECT_EQ(countStashEntries("stash@{0}: WIP on main: abc\nstash@{1}: On x: y\n"), 2);
  EXPECT_EQ(countStashEntries("\n"), 0);
}

TEST(EndOfDayText, TheSummaryReadsLikeTheSpec) {
  EndOfDayFindings f;
  f.timerTaskIds << QStringLiteral("A-1");
  f.changedFiles = 3;
  f.repo = QStringLiteral("heap");
  f.staleTaskIds << QStringLiteral("A-2") << QStringLiteral("A-3");
  EXPECT_EQ(endOfDaySummary(f, 3, true),
            QStringLiteral("Таймер всё ещё идёт · 3 незакоммиченных файла в heap · 2 задачи в работе без движения 3+ дня"));
  EXPECT_EQ(endOfDaySummary(f, 3, false),
            QStringLiteral("Timer still running · 3 uncommitted files in heap · 2 tasks in progress without a move for 3+ days"));
}

// ── APP-158: waiting on a reply ──

TEST(Waiting, TheReminderIsDueAfterTheSetDays) {
  const WaitingOn w{.taskId = QStringLiteral("T-1"), .personId = QStringLiteral("oleg"), .since = kEvening, .remindedAt = {}};
  EXPECT_FALSE(waitingReminderDue(w, kEvening.addDays(2).addSecs(-60), 2));
  EXPECT_TRUE(waitingReminderDue(w, kEvening.addDays(2), 2));
  EXPECT_TRUE(waitingReminderDue(w, kEvening.addDays(9), 2));
}

TEST(Waiting, OncePerLink) {
  WaitingOn w{.taskId = QStringLiteral("T-1"), .personId = QStringLiteral("oleg"), .since = kEvening, .remindedAt = {}};
  w.remindedAt = kEvening.addDays(2);
  EXPECT_FALSE(waitingReminderDue(w, kEvening.addDays(5), 2));
}

// Asking again starts the wait over: a new `since`, the reminder cleared.
TEST(Waiting, ReArmingStartsOver) {
  WaitingOn w{.taskId = QStringLiteral("T-1"), .personId = QStringLiteral("oleg"), .since = kEvening, .remindedAt = kEvening.addDays(2)};
  w.since = kEvening.addDays(3);
  w.remindedAt = {};
  EXPECT_FALSE(waitingReminderDue(w, kEvening.addDays(4), 2));
  EXPECT_TRUE(waitingReminderDue(w, kEvening.addDays(5), 2));
}

TEST(Waiting, ZeroDaysMeansOne) {
  const WaitingOn w{.taskId = QStringLiteral("T-1"), .personId = QStringLiteral("oleg"), .since = kEvening, .remindedAt = {}};
  EXPECT_FALSE(waitingReminderDue(w, kEvening.addSecs(3600), 0));
}

TEST(Waiting, DaysAreCalendarDays) {
  EXPECT_EQ(waitingDays(QDateTime(kDay, QTime(23, 0)), kDay.addDays(1)), 1);
  EXPECT_EQ(waitingDays(QDateTime(kDay, QTime(9, 0)), kDay), 0);
  EXPECT_EQ(waitingDays({}, kDay), 0);
}

TEST(Waiting, OnlyAMoveToRepliedEndsIt) {
  EXPECT_TRUE(replyEndsWaiting(QStringLiteral("pinged"), QStringLiteral("replied")));
  EXPECT_TRUE(replyEndsWaiting(QStringLiteral("todo"), QStringLiteral("replied")));
  EXPECT_FALSE(replyEndsWaiting(QStringLiteral("replied"), QStringLiteral("replied")));
  EXPECT_FALSE(replyEndsWaiting(QStringLiteral("todo"), QStringLiteral("pinged")));
}

TEST(EndOfDayText, RussianPluralForms) {
  const QString forms = QStringLiteral("файл|файла|файлов");
  EXPECT_EQ(plural(1, forms), QStringLiteral("файл"));
  EXPECT_EQ(plural(3, forms), QStringLiteral("файла"));
  EXPECT_EQ(plural(5, forms), QStringLiteral("файлов"));
  EXPECT_EQ(plural(11, forms), QStringLiteral("файлов"));
  EXPECT_EQ(plural(21, forms), QStringLiteral("файл"));
  EXPECT_EQ(plural(22, forms), QStringLiteral("файла"));
  EXPECT_EQ(plural(14, forms), QStringLiteral("файлов"));
}
