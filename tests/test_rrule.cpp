// Recurrence rules for calendar events (src/cal/RRule.h).
//
// Events repeat and heap had no way to say so: only tasks had a recurrence, it
// was a chrono token rather than a rule, and it could only answer "what is the
// next one?". A calendar needs the other question — which occurrences fall
// inside the fortnight on screen. Pure; no Qt event loop.

#include "cal/RRule.h"

#include <gtest/gtest.h>

namespace {

using heap::cal::expand;
using heap::cal::parseRRule;
using heap::cal::RRule;

QVector<QDate> datesOf(const QString& rule, const QDate& start, const QDate& from, const QDate& to) {
  return expand(parseRRule(rule), start, from, to);
}

}  // namespace

// ─── parsing ──────────────────────────────────────────────────────────

TEST(RRuleParse, ReadsFrequencyIntervalAndDays) {
  const RRule r = parseRRule(QStringLiteral("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE"));
  ASSERT_TRUE(r.isValid());
  EXPECT_EQ(r.freq, RRule::Weekly);
  EXPECT_EQ(r.interval, 2);
  EXPECT_EQ(r.byDay, (QVector<int>{1, 3}));
}

TEST(RRuleParse, IntervalDefaultsToOne) {
  EXPECT_EQ(parseRRule(QStringLiteral("FREQ=DAILY")).interval, 1);
}

TEST(RRuleParse, ReadsCountAndUntil) {
  const RRule r = parseRRule(QStringLiteral("FREQ=DAILY;COUNT=5;UNTIL=20270115"));
  EXPECT_EQ(r.count, 5);
  EXPECT_EQ(r.until, QDate(2027, 1, 15));
}

TEST(RRuleParse, ReadsTheDateTimeFormOfUntil) {
  EXPECT_EQ(parseRRule(QStringLiteral("FREQ=DAILY;UNTIL=20270115T090000Z")).until, QDate(2027, 1, 15));
}

TEST(RRuleParse, RejectsWhatItDoesNotSupport) {
  EXPECT_FALSE(parseRRule(QString()).isValid());
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=HOURLY")).isValid()) << "not in the subset";
  EXPECT_FALSE(parseRRule(QStringLiteral("nonsense")).isValid());
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=DAILY;INTERVAL=0")).isValid());
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=DAILY;COUNT=0")).isValid());
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=DAILY;UNTIL=notadate")).isValid());
}

// An ordinal BYDAY means "the second Thursday". Dropping the ordinal would
// silently turn that into every Thursday — a meeting four times as often as it
// should be — so the whole rule is rejected instead.
TEST(RRuleParse, RejectsAnOrdinalByDayRatherThanMisreadingIt) {
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=MONTHLY;BYDAY=2TH")).isValid());
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=MONTHLY;BYDAY=-1FR")).isValid());
}

TEST(RRuleParse, RoundTripsThroughText) {
  const QString text = QStringLiteral("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=10");
  EXPECT_EQ(heap::cal::toRRuleText(parseRRule(text)), text);
}

// ─── expansion ────────────────────────────────────────────────────────

TEST(RRuleExpand, DailyFillsTheWindow) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=DAILY"), QDate(2027, 1, 1), QDate(2027, 1, 1), QDate(2027, 1, 5));
  EXPECT_EQ(d.size(), 5);
  EXPECT_EQ(d.first(), QDate(2027, 1, 1));
  EXPECT_EQ(d.last(), QDate(2027, 1, 5));
}

TEST(RRuleExpand, IntervalSkips) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=DAILY;INTERVAL=3"), QDate(2027, 1, 1), QDate(2027, 1, 1), QDate(2027, 1, 10));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2027, 1, 1), QDate(2027, 1, 4), QDate(2027, 1, 7), QDate(2027, 1, 10)}));
}

TEST(RRuleExpand, WeeklyWithNoByDayUsesTheStartsWeekday) {
  // 4 Jan 2027 is a Monday.
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=WEEKLY"), QDate(2027, 1, 4), QDate(2027, 1, 1), QDate(2027, 2, 1));
  for(const QDate& x : d) {
    EXPECT_EQ(x.dayOfWeek(), 1);
  }
  EXPECT_GE(d.size(), 4);
}

TEST(RRuleExpand, WeeklyByDayHitsEveryNamedDay) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=WEEKLY;BYDAY=MO,WE,FR"), QDate(2027, 1, 4), QDate(2027, 1, 4), QDate(2027, 1, 10));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2027, 1, 4), QDate(2027, 1, 6), QDate(2027, 1, 8)}));
}

// INTERVAL=2 means every other week *of the series*, counted from the week the
// series starts in — not every other week of the year, which would shift with
// wherever the year happened to begin.
TEST(RRuleExpand, WeeklyIntervalCountsFromTheSeriesOwnWeek) {
  const QVector<QDate> d =
      datesOf(QStringLiteral("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO"), QDate(2027, 1, 4), QDate(2027, 1, 1), QDate(2027, 2, 15));
  ASSERT_GE(d.size(), 3);
  EXPECT_EQ(d.at(0), QDate(2027, 1, 4));
  EXPECT_EQ(d.at(1), QDate(2027, 1, 18));
  EXPECT_EQ(d.at(2), QDate(2027, 2, 1));
}

TEST(RRuleExpand, MonthlyKeepsTheDayOfMonth) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=MONTHLY"), QDate(2027, 1, 15), QDate(2027, 1, 1), QDate(2027, 4, 30));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2027, 1, 15), QDate(2027, 2, 15), QDate(2027, 3, 15), QDate(2027, 4, 15)}));
}

// The 31st in a 30-day month clamps, which is what every calendar does with a
// monthly meeting rather than skipping the month entirely.
TEST(RRuleExpand, MonthlyClampsAShortMonth) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=MONTHLY"), QDate(2027, 1, 31), QDate(2027, 1, 1), QDate(2027, 3, 31));
  ASSERT_EQ(d.size(), 3);
  EXPECT_EQ(d.at(1), QDate(2027, 2, 28));
}

TEST(RRuleExpand, YearlyRepeats) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=YEARLY"), QDate(2027, 3, 1), QDate(2027, 1, 1), QDate(2030, 1, 1));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2027, 3, 1), QDate(2028, 3, 1), QDate(2029, 3, 1)}));
}

// ─── bounds ───────────────────────────────────────────────────────────

TEST(RRuleExpand, UntilEndsTheSeries) {
  const QVector<QDate> d =
      datesOf(QStringLiteral("FREQ=DAILY;UNTIL=20270103"), QDate(2027, 1, 1), QDate(2027, 1, 1), QDate(2027, 1, 10));
  EXPECT_EQ(d.size(), 3);
  EXPECT_EQ(d.last(), QDate(2027, 1, 3));
}

// COUNT is counted from the start of the series, not from the window — the
// tenth occurrence is the tenth whatever the calendar is showing, otherwise
// scrolling would change how many there are.
TEST(RRuleExpand, CountIsMeasuredFromTheSeriesStartNotTheWindow) {
  const QString rule = QStringLiteral("FREQ=DAILY;COUNT=3");
  const QDate start(2027, 1, 1);

  EXPECT_EQ(datesOf(rule, start, QDate(2027, 1, 1), QDate(2027, 1, 31)).size(), 3);
  // A window that opens after the series has already used up its count sees
  // nothing, rather than three more.
  EXPECT_TRUE(datesOf(rule, start, QDate(2027, 1, 10), QDate(2027, 1, 31)).isEmpty());
  // A window in the middle sees only the occurrences that fall in it.
  EXPECT_EQ(datesOf(rule, start, QDate(2027, 1, 2), QDate(2027, 1, 31)).size(), 2);
}

TEST(RRuleExpand, NothingBeforeTheSeriesStarts) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=DAILY"), QDate(2027, 6, 1), QDate(2027, 1, 1), QDate(2027, 1, 31));
  EXPECT_TRUE(d.isEmpty());
}

TEST(RRuleExpand, AWindowThatOpensMidSeriesStartsWhereItOpens) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=DAILY"), QDate(2027, 1, 1), QDate(2027, 1, 20), QDate(2027, 1, 22));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2027, 1, 20), QDate(2027, 1, 21), QDate(2027, 1, 22)}));
}

TEST(RRuleExpand, AnInvalidRuleOrWindowYieldsNothing) {
  EXPECT_TRUE(datesOf(QStringLiteral("FREQ=HOURLY"), QDate(2027, 1, 1), QDate(2027, 1, 1), QDate(2027, 1, 5)).isEmpty());
  EXPECT_TRUE(datesOf(QStringLiteral("FREQ=DAILY"), QDate(), QDate(2027, 1, 1), QDate(2027, 1, 5)).isEmpty());
  // A backwards window is not an error to diagnose, just an empty answer.
  EXPECT_TRUE(datesOf(QStringLiteral("FREQ=DAILY"), QDate(2027, 1, 1), QDate(2027, 1, 5), QDate(2027, 1, 1)).isEmpty());
}

// A long window must not take forever, and must not run away.
TEST(RRuleExpand, ALongWindowIsBounded) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=DAILY"), QDate(2027, 1, 1), QDate(2027, 1, 1), QDate(2037, 1, 1));
  EXPECT_GT(d.size(), 300);
  EXPECT_LE(d.size(), 4000);
}

// ─── nextAfter ────────────────────────────────────────────────────────

TEST(RRuleNext, FindsTheFollowingOccurrence) {
  const RRule r = parseRRule(QStringLiteral("FREQ=WEEKLY;BYDAY=MO"));
  EXPECT_EQ(heap::cal::nextAfter(r, QDate(2027, 1, 4), QDate(2027, 1, 4)), QDate(2027, 1, 11));
}

TEST(RRuleNext, ReturnsNothingOnceTheSeriesHasEnded) {
  const RRule r = parseRRule(QStringLiteral("FREQ=DAILY;COUNT=2"));
  EXPECT_FALSE(heap::cal::nextAfter(r, QDate(2027, 1, 1), QDate(2027, 1, 5)).isValid());
}

TEST(RRuleNext, ReachesPastAWideYearlyInterval) {
  const RRule r = parseRRule(QStringLiteral("FREQ=YEARLY;INTERVAL=5"));
  EXPECT_EQ(heap::cal::nextAfter(r, QDate(2027, 3, 1), QDate(2027, 3, 1)), QDate(2032, 3, 1));
}
