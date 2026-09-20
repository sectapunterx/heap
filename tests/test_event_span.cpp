// All-day and multi-day spans.
//
// clampHours() describes exactly one day and pins anything that runs past
// midnight to the end of it. That is right for a drag and wrong for the two
// shapes a calendar has to hold anyway: an all-day event, and a timed one that
// crosses midnight. normalizeSpan() is the one place both are given their
// invariants, so every write path lands on the same shape.

#include "cal/EventSpan.h"

#include <gtest/gtest.h>

using heap::cal::kMaxSpanDays;
using heap::cal::normalizeSpan;
using heap::cal::Span;

namespace {

constexpr double kQuarter = 0.25;
const QDate kMon(2026, 9, 21);

}  // namespace

// The common case has to be untouched by any of this: no end date, hours
// inside one day, straight through clampHours.
TEST(EventSpan, AnOrdinaryEventIsUnchanged) {
  const Span s = normalizeSpan(kMon, QDate(), 9.0, 10.0, false, kQuarter);

  EXPECT_EQ(s.date, kMon);
  EXPECT_EQ(s.endDate, kMon);
  EXPECT_DOUBLE_EQ(s.start, 9.0);
  EXPECT_DOUBLE_EQ(s.end, 10.0);
  EXPECT_FALSE(s.allDay);
  EXPECT_EQ(s.dayCount(), 1);
  EXPECT_FALSE(s.multiDay());
}

// A single-day event still gets the single-day guarantees — a zero-length one
// is grown to a slot rather than left ungrabbable.
TEST(EventSpan, ASingleDayEventKeepsItsMinimumLength) {
  const Span s = normalizeSpan(kMon, kMon, 9.0, 9.0, false, kQuarter);

  EXPECT_EQ(s.endDate, kMon);
  EXPECT_GE(s.end - s.start, kQuarter);
}

TEST(EventSpan, AnEndDateEqualToTheStartIsASingleDay) {
  const Span s = normalizeSpan(kMon, kMon, 9.0, 10.0, false, kQuarter);

  EXPECT_EQ(s.dayCount(), 1);
  EXPECT_FALSE(s.multiDay());
}

TEST(EventSpan, AnAllDayEventLosesItsHours) {
  const Span s = normalizeSpan(kMon, QDate(), 9.0, 10.0, true, kQuarter);

  EXPECT_TRUE(s.allDay);
  EXPECT_DOUBLE_EQ(s.start, 0.0);
  EXPECT_DOUBLE_EQ(s.end, 24.0);
  EXPECT_EQ(s.endDate, kMon);
}

TEST(EventSpan, AnAllDayEventKeepsItsRunOfDays) {
  const Span s = normalizeSpan(kMon, kMon.addDays(2), 0.0, 24.0, true, kQuarter);

  EXPECT_EQ(s.endDate, kMon.addDays(2));
  EXPECT_EQ(s.dayCount(), 3);
  EXPECT_TRUE(s.multiDay());
}

// The whole point: 22:00 Monday to 02:00 Tuesday survives as one event with
// two edges, instead of being pinned to Monday 23:45.
TEST(EventSpan, ATimedEventMayCrossMidnight) {
  const Span s = normalizeSpan(kMon, kMon.addDays(1), 22.0, 2.0, false, kQuarter);

  EXPECT_EQ(s.date, kMon);
  EXPECT_EQ(s.endDate, kMon.addDays(1));
  EXPECT_DOUBLE_EQ(s.start, 22.0);
  EXPECT_DOUBLE_EQ(s.end, 2.0);
  EXPECT_EQ(s.dayCount(), 2);
}

// An end earlier than the start across days is legal and must not be read as
// an empty event the way a same-day pair would be.
TEST(EventSpan, AnEndHourBeforeTheStartHourIsFineAcrossDays) {
  const Span s = normalizeSpan(kMon, kMon.addDays(1), 23.5, 0.5, false, kQuarter);

  EXPECT_DOUBLE_EQ(s.start, 23.5);
  EXPECT_DOUBLE_EQ(s.end, 0.5);
}

// "Monday 22:00 to Tuesday 00:00" is a Monday event. Handing Tuesday a
// zero-length piece would draw a block nothing can grab.
TEST(EventSpan, AnEndAtExactlyMidnightBelongsToThePreviousDay) {
  const Span s = normalizeSpan(kMon, kMon.addDays(1), 22.0, 0.0, false, kQuarter);

  EXPECT_EQ(s.endDate, kMon);
  EXPECT_DOUBLE_EQ(s.start, 22.0);
  EXPECT_DOUBLE_EQ(s.end, 24.0);
  EXPECT_EQ(s.dayCount(), 1);
}

// The same pull-back over a three-day span lands on day two, not on day one.
TEST(EventSpan, MidnightPullBackOnlyLosesTheLastDay) {
  const Span s = normalizeSpan(kMon, kMon.addDays(2), 22.0, 0.0, false, kQuarter);

  EXPECT_EQ(s.endDate, kMon.addDays(1));
  EXPECT_DOUBLE_EQ(s.end, 24.0);
  EXPECT_EQ(s.dayCount(), 2);
}

TEST(EventSpan, SwappedDatesAreOrdered) {
  const Span s = normalizeSpan(kMon.addDays(2), kMon, 9.0, 10.0, false, kQuarter);

  EXPECT_EQ(s.date, kMon);
  EXPECT_EQ(s.endDate, kMon.addDays(2));
}

// An end date before the start with no swap possible (same day) degrades to a
// single day rather than a negative count.
TEST(EventSpan, AnEndDateBeforeTheStartNeverYieldsANegativeCount) {
  const Span s = normalizeSpan(kMon, kMon.addDays(-5), 9.0, 10.0, false, kQuarter);

  EXPECT_GE(s.dayCount(), 1);
  EXPECT_LE(s.date, s.endDate);
}

// A corrupt import must not cost a delegate per day for a decade.
TEST(EventSpan, AnAbsurdlyLongSpanIsTruncated) {
  const Span s = normalizeSpan(kMon, kMon.addYears(30), 0.0, 24.0, true, kQuarter);

  EXPECT_EQ(s.dayCount(), kMaxSpanDays);
}

TEST(EventSpan, MultiDayEdgesAreSnappedToTheGrid) {
  const Span s = normalizeSpan(kMon, kMon.addDays(1), 22.1, 2.1, false, 0.5);

  EXPECT_DOUBLE_EQ(s.start, 22.0);
  EXPECT_DOUBLE_EQ(s.end, 2.0);
}

// A start of exactly midnight on the far edge would leave no room on its own
// day; it slides back by one slot the way clampHours does.
TEST(EventSpan, AMultiDayStartCannotSitOnMidnightAtTheEndOfItsDay) {
  const Span s = normalizeSpan(kMon, kMon.addDays(1), 24.0, 2.0, false, kQuarter);

  EXPECT_LT(s.start, 24.0);
}

TEST(EventSpan, NonFiniteHoursDoNotEscape) {
  const Span s = normalizeSpan(kMon, kMon.addDays(1), std::nan(""), std::nan(""), false, kQuarter);

  EXPECT_TRUE(std::isfinite(s.start));
  EXPECT_TRUE(std::isfinite(s.end));
  EXPECT_GE(s.start, 0.0);
  EXPECT_LE(s.end, 24.0);
}

// An invalid date is a caller's problem, but it must not produce a span that
// claims a negative number of days.
TEST(EventSpan, AnInvalidDateStillYieldsOneDay) {
  const Span s = normalizeSpan(QDate(), QDate(), 9.0, 10.0, false, kQuarter);

  EXPECT_EQ(s.dayCount(), 1);
}
