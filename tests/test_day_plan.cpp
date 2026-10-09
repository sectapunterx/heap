// One day as Today and the calendars draw it (APP-260/247): blocks by the
// hour, free windows as facts, the load counted once. A pure function of
// what it is handed and `now`.
#include "plan/DayPlan.h"

#include <gtest/gtest.h>

using heap::plan::buildDay;
using heap::plan::Day;
using heap::plan::EventIn;
using heap::plan::TaskIn;

namespace {

const QDate kDay(2026, 10, 8);  // a Thursday
const QDateTime kNoon(kDay, QTime(12, 0));

EventIn meeting(const QString& id, double start, double end) {
  EventIn e;
  e.id = id;
  e.title = id;
  e.date = kDay;
  e.start = start;
  e.end = end;
  return e;
}

TaskIn task(const QString& id, int hour, int minutes) {
  TaskIn t;
  t.id = id;
  t.title = id;
  t.status = QStringLiteral("todo");
  t.scheduledAt = QDateTime(kDay, QTime(hour, 0));
  t.minutes = minutes;
  return t;
}

}  // namespace

TEST(DayPlan, BlocksAreByTimeAndFreeWindowsAreFacts) {
  const Day d = buildDay(kDay, kNoon, {meeting("standup", 10, 10.5)}, {task("T-1", 13, 120)}, 9, 19, true);
  ASSERT_EQ(d.blocks.size(), 2);
  EXPECT_EQ(d.blocks[0].id, QStringLiteral("standup"));
  EXPECT_TRUE(d.blocks[0].past);
  EXPECT_FALSE(d.blocks[1].past);
  // 9–10, 10:30–13, 15–19.
  ASSERT_EQ(d.free.size(), 3);
  EXPECT_DOUBLE_EQ(d.free[1].start, 10.5);
  EXPECT_DOUBLE_EQ(d.free[1].end, 13);
  EXPECT_EQ(d.load.meetings, 30);
  EXPECT_EQ(d.load.tasks, 120);
  EXPECT_EQ(d.load.free, 600 - 150);
  EXPECT_EQ(d.load.overWork, 0);
}

TEST(DayPlan, OverlapsAreNamedAndCountedOnce) {
  const Day d = buildDay(kDay, kNoon, {meeting("sync", 14, 15)}, {task("T-1", 14, 120)}, 9, 19, true);
  ASSERT_EQ(d.blocks.size(), 2);
  EXPECT_EQ(d.blocks[0].overlapsWith, QStringList{QStringLiteral("T-1")});
  EXPECT_EQ(d.load.meetings, 60);
  EXPECT_EQ(d.load.tasks, 60) << "the hour under the meeting is not counted twice";
}

TEST(DayPlan, ATaskWithItsOwnBlockIsDrawnOnce) {
  EventIn focus = meeting("focus-1", 15, 16);
  focus.type = QStringLiteral("focus");
  focus.taskId = QStringLiteral("T-1");
  const Day d = buildDay(kDay, kNoon, {focus}, {task("T-1", 15, 60)}, 9, 19, true);
  EXPECT_EQ(d.blocks.size(), 1);
}

TEST(DayPlan, AMeetingAcrossMidnightIsInBothDays) {
  EventIn late = meeting("deploy", 23, 1);
  late.endDate = kDay.addDays(1);
  const Day today = buildDay(kDay, kNoon, {late}, {}, 9, 19, true);
  ASSERT_EQ(today.blocks.size(), 1);
  EXPECT_TRUE(today.blocks[0].toNextDay);
  EXPECT_DOUBLE_EQ(today.blocks[0].end, 24);
  EXPECT_DOUBLE_EQ(today.toHour, 24) << "the day widens for it";
  const Day next = buildDay(kDay.addDays(1), kNoon, {late}, {}, 9, 19, true);
  ASSERT_EQ(next.blocks.size(), 1);
  EXPECT_TRUE(next.blocks[0].fromPrevDay);
  EXPECT_DOUBLE_EQ(next.blocks[0].end, 1);
}

TEST(DayPlan, AllDayIsAboveTheHoursAndNotLoad) {
  EventIn off = meeting("offsite", 0, 24);
  off.allDay = true;
  const Day d = buildDay(kDay, kNoon, {off}, {}, 9, 19, true);
  EXPECT_EQ(d.allDay.size(), 1);
  EXPECT_TRUE(d.blocks.isEmpty());
  EXPECT_EQ(d.load.meetings, 0);
  EXPECT_EQ(d.load.free, 600);
}

TEST(DayPlan, ADayOffHasNoWorkingBandAndNoFreeWindows) {
  const Day d = buildDay(kDay, kNoon, {meeting("brunch", 11, 12)}, {}, 9, 19, false);
  EXPECT_FALSE(d.workday);
  EXPECT_TRUE(d.free.isEmpty());
  EXPECT_DOUBLE_EQ(d.fromHour, 11);
  EXPECT_DOUBLE_EQ(d.toHour, 12);
}

TEST(DayPlan, EarlyAndLateMeetingsWidenTheDay) {
  const Day d = buildDay(kDay, kNoon, {meeting("early", 7, 8), meeting("late", 21, 22)}, {}, 9, 19, true);
  EXPECT_DOUBLE_EQ(d.fromHour, 7);
  EXPECT_DOUBLE_EQ(d.toHour, 22);
}

TEST(DayPlan, MoreThanTheWorkingDayIsAPlainFact) {
  const Day d = buildDay(kDay, kNoon, {meeting("a", 8, 13), meeting("b", 13, 20)}, {}, 9, 19, true);
  EXPECT_EQ(d.load.overWork, 120);
  EXPECT_EQ(d.load.free, 0);
}

TEST(DayPlan, ADayGoneByIsAllPastAndOneToComeIsNot) {
  const Day before = buildDay(kDay, kNoon.addDays(2), {meeting("m", 10, 11)}, {}, 9, 19, true);
  EXPECT_TRUE(before.blocks[0].past);
  const Day after = buildDay(kDay, kNoon.addDays(-2), {meeting("m", 10, 11)}, {}, 9, 19, true);
  EXPECT_FALSE(after.blocks[0].past);
}
