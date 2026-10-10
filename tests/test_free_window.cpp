// The nearest free window (APP-253) and the carry of leftovers (APP-248):
// pure functions of the busy spans and `now`.
#include "plan/Carry.h"
#include "plan/FreeWindow.h"

#include <QHash>

#include <gtest/gtest.h>

using heap::plan::findWindow;
using heap::plan::firstFit;
using heap::plan::nextWindow;
using heap::plan::Span;
using heap::plan::WindowAsk;

namespace {

const QDate kThu(2026, 10, 8);  // Thursday; Saturday is kThu + 2

struct Calendar {
  QHash<QDate, QVector<Span>> busy;

  heap::plan::BusyOn busyOn() const {
    return [this](const QDate& d) {
      return busy.value(d);
    };
  }
};

bool weekday(const QDate& d) {
  return d.dayOfWeek() <= 5;
}

WindowAsk ask(const QDateTime& now, double hours = 1) {
  WindowAsk a;
  a.date = now.date();
  a.now = now;
  a.hours = hours;
  a.workStart = 9;
  a.workEnd = 19;
  a.step = 0.25;
  return a;
}

}  // namespace

TEST(FreeWindow, FirstFitSkipsBusyAndRespectsTheEnd) {
  EXPECT_DOUBLE_EQ(firstFit({{9, 10}, {11, 12}}, 9, 19, 1, 0.25), 10);
  EXPECT_DOUBLE_EQ(firstFit({{9, 10}, {11, 12}}, 9, 19, 1.5, 0.25), 12);
  EXPECT_DOUBLE_EQ(firstFit({{9, 18.5}}, 9, 19, 1, 0.25), -1);
  // Unsorted and overlapping spans are fine.
  EXPECT_DOUBLE_EQ(firstFit({{13, 14}, {9, 12}, {11, 13.5}}, 9, 19, 0.5, 0.25), 14);
}

// A task with a time and no event of its own is busy: it is a span like any
// meeting, and the search steps past it.
TEST(FreeWindow, ATaskBlockTakesItsTime) {
  Calendar c;
  c.busy[kThu] = {{9, 10.5}};  // the task block 9:00-10:30
  const auto w = findWindow(ask(QDateTime(kThu, QTime(8, 0))), c.busyOn(), weekday);
  ASSERT_TRUE(w.found);
  EXPECT_DOUBLE_EQ(w.start, 10.5);
}

TEST(FreeWindow, StartsFromNowOnToday) {
  Calendar c;
  const auto w = findWindow(ask(QDateTime(kThu, QTime(13, 5))), c.busyOn(), weekday);
  ASSERT_TRUE(w.found);
  EXPECT_DOUBLE_EQ(w.start, 13.25);
}

// No room left in the working day: "no", with tomorrow's window and what is
// left of the evening as options, never a silent 21:00.
TEST(FreeWindow, NoRoomTodayIsSaidWithOptions) {
  Calendar c;
  c.busy[kThu] = {{9, 19}};
  c.busy[kThu.addDays(1)] = {{9, 10}};
  const auto w = findWindow(ask(QDateTime(kThu, QTime(12, 0))), c.busyOn(), weekday);
  EXPECT_FALSE(w.found);
  EXPECT_EQ(w.nextDate, kThu.addDays(1));
  EXPECT_DOUBLE_EQ(w.nextStart, 10);
  EXPECT_DOUBLE_EQ(w.lateStart, 19);
}

TEST(FreeWindow, LateInTheEveningNothingFitsBeforeMidnight) {
  Calendar c;
  const auto w = findWindow(ask(QDateTime(kThu, QTime(23, 30)), 1), c.busyOn(), weekday);
  EXPECT_FALSE(w.found);
  EXPECT_DOUBLE_EQ(w.lateStart, -1);
  EXPECT_EQ(w.nextDate, kThu.addDays(1));
}

// A day off has no working window; the next one is Monday.
TEST(FreeWindow, ADayOffOffersTheNextWorkingDay) {
  Calendar c;
  const QDate sat = kThu.addDays(2);
  const auto w = findWindow(ask(QDateTime(sat, QTime(10, 0))), c.busyOn(), weekday);
  EXPECT_FALSE(w.found);
  EXPECT_EQ(w.nextDate, sat.addDays(2));
  EXPECT_DOUBLE_EQ(w.nextStart, 9);
  EXPECT_DOUBLE_EQ(w.lateStart, 10);
}

// A meeting from the evening before that runs past midnight takes the morning.
TEST(FreeWindow, AMeetingAcrossMidnightTakesTheMorning) {
  Calendar c;
  c.busy[kThu] = {{0, 9.5}};
  const auto w = findWindow(ask(QDateTime(kThu, QTime(0, 30))), c.busyOn(), weekday);
  ASSERT_TRUE(w.found);
  EXPECT_DOUBLE_EQ(w.start, 9.5);
}

TEST(FreeWindow, ADayGoneByHasNoWindow) {
  Calendar c;
  WindowAsk a = ask(QDateTime(kThu, QTime(9, 0)));
  a.date = kThu.addDays(-1);
  const auto w = findWindow(a, c.busyOn(), weekday);
  EXPECT_FALSE(w.found);
  EXPECT_DOUBLE_EQ(w.lateStart, -1);
  EXPECT_EQ(w.nextDate, kThu);
}

TEST(FreeWindow, NextWindowGoesOnToTheNextWorkingDay) {
  Calendar c;
  c.busy[kThu] = {{9, 19}};
  c.busy[kThu.addDays(1)] = {{9, 19}};
  const auto [d, s] = nextWindow(ask(QDateTime(kThu, QTime(9, 0))), c.busyOn(), weekday);
  EXPECT_EQ(d, kThu.addDays(4));  // Monday
  EXPECT_DOUBLE_EQ(s, 9);
}

TEST(Carry, TomorrowKeepsTheTime) {
  const auto p = heap::plan::toTomorrow(QDateTime(kThu.addDays(-3), QTime(14, 30)), true, kThu);
  EXPECT_EQ(p.at, QDateTime(kThu.addDays(1), QTime(14, 30)));
  EXPECT_TRUE(p.hasTime);
}

TEST(Carry, TomorrowWithoutATimeIsADate) {
  const auto p = heap::plan::toTomorrow(QDateTime(kThu, QTime(0, 0)), false, kThu);
  EXPECT_EQ(p.at.date(), kThu.addDays(1));
  EXPECT_FALSE(p.hasTime);
  const auto none = heap::plan::toTomorrow(QDateTime(), false, kThu);
  EXPECT_EQ(none.at.date(), kThu.addDays(1));
}
