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
  EXPECT_EQ(r.plainDays(), (QVector<int>{1, 3}));
}

TEST(RRuleParse, IntervalDefaultsToOne) {
  EXPECT_EQ(parseRRule(QStringLiteral("FREQ=DAILY")).interval, 1);
}

TEST(RRuleParse, ReadsCountAndUntil) {
  const RRule r = parseRRule(QStringLiteral("FREQ=DAILY;COUNT=5;UNTIL=20270115"));
  EXPECT_EQ(r.count, 5);
  EXPECT_EQ(r.until, QDate(2027, 1, 15));
}

// The UTC form keeps its instant; the day bound is loosened by one because in
// UTC the date can run ahead of the event's own (see untilAt).
TEST(RRuleParse, ReadsTheDateTimeFormOfUntil) {
  const RRule r = parseRRule(QStringLiteral("FREQ=DAILY;UNTIL=20270115T090000Z"));
  EXPECT_EQ(r.untilAt, QDateTime(QDate(2027, 1, 15), QTime(9, 0), QTimeZone::utc()));
  EXPECT_EQ(r.until, QDate(2027, 1, 16));
}

TEST(RRuleParse, RejectsWhatItDoesNotSupport) {
  EXPECT_FALSE(parseRRule(QString()).isValid());
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=HOURLY")).isValid()) << "not in the subset";
  EXPECT_FALSE(parseRRule(QStringLiteral("nonsense")).isValid());
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=DAILY;INTERVAL=0")).isValid());
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=DAILY;COUNT=0")).isValid());
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=DAILY;UNTIL=notadate")).isValid());
}

// An ordinal BYDAY means "the second Thursday" and is read as such where the
// RFC allows it; in a DAILY or WEEKLY rule it has nothing to count within, so
// the rule is rejected rather than misread as "every Thursday".
TEST(RRuleParse, ReadsAnOrdinalByDayWhereTheRfcAllowsIt) {
  const RRule r = parseRRule(QStringLiteral("FREQ=MONTHLY;BYDAY=2TH"));
  ASSERT_TRUE(r.isValid());
  ASSERT_EQ(r.byDay.size(), 1);
  EXPECT_EQ(r.byDay.first().ord, 2);
  EXPECT_EQ(r.byDay.first().day, 4);
  EXPECT_TRUE(parseRRule(QStringLiteral("FREQ=MONTHLY;BYDAY=-1FR")).isValid());
  QString why;
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=WEEKLY;BYDAY=2TH"), &why).isValid());
  EXPECT_FALSE(why.isEmpty());
}

TEST(RRuleParse, NamesThePartItDoesNotSupport) {
  QString why;
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=YEARLY;BYWEEKNO=20"), &why).isValid());
  EXPECT_TRUE(why.contains(QStringLiteral("BYWEEKNO")));
  EXPECT_FALSE(parseRRule(QStringLiteral("FREQ=HOURLY"), &why).isValid());
  EXPECT_TRUE(why.contains(QStringLiteral("HOURLY")));
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
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=DAILY;UNTIL=20270103"), QDate(2027, 1, 1), QDate(2027, 1, 1), QDate(2027, 1, 10));
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

// ─── Month ends (audit S9) ────────────────────────────────────────────

TEST(RRule, Expand_MonthlyOnThe31st_ReturnsToThe31stAfterShortMonths) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=MONTHLY"), QDate(2027, 1, 31), QDate(2027, 1, 1), QDate(2027, 5, 31));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2027, 1, 31), QDate(2027, 2, 28), QDate(2027, 3, 31), QDate(2027, 4, 30), QDate(2027, 5, 31)}));
}

TEST(RRule, Expand_YearlyOnLeapDay_ReturnsToLeapDay) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=YEARLY"), QDate(2028, 2, 29), QDate(2028, 1, 1), QDate(2032, 12, 31));
  ASSERT_EQ(d.size(), 5);
  EXPECT_EQ(d.last(), QDate(2032, 2, 29));
}

// ─── The rest of RFC 5545's BYxxx (audit TIME-8, TIME-27) ─────────────

// 5 Oct 2026 is a Monday.
TEST(RRuleRfc, DailyByDayIsEveryWorkingDay) {
  const QVector<QDate> d =
      datesOf(QStringLiteral("FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR"), QDate(2026, 10, 5), QDate(2026, 10, 5), QDate(2026, 10, 18));
  EXPECT_EQ(d.size(), 10);
  for(const QDate& x : d) {
    EXPECT_LE(x.dayOfWeek(), 5) << x.toString(Qt::ISODate).toStdString();
  }
}

TEST(RRuleRfc, MonthlyByMonthDayListHitsEveryDay) {
  const QVector<QDate> d =
      datesOf(QStringLiteral("FREQ=MONTHLY;BYMONTHDAY=1,15"), QDate(2026, 10, 1), QDate(2026, 10, 1), QDate(2026, 12, 31));
  EXPECT_EQ(
      d,
      (QVector<QDate>{
          QDate(2026, 10, 1), QDate(2026, 10, 15), QDate(2026, 11, 1), QDate(2026, 11, 15), QDate(2026, 12, 1), QDate(2026, 12, 15)}));
}

TEST(RRuleRfc, NegativeMonthDayIsCountedFromTheEnd) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=MONTHLY;BYMONTHDAY=-1"), QDate(2027, 1, 31), QDate(2027, 1, 1), QDate(2027, 4, 30));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2027, 1, 31), QDate(2027, 2, 28), QDate(2027, 3, 31), QDate(2027, 4, 30)}));
}

TEST(RRuleRfc, AnExplicitMonthDayTheMonthLacksIsSkipped) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=MONTHLY;BYMONTHDAY=31"), QDate(2027, 1, 31), QDate(2027, 1, 1), QDate(2027, 5, 31));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2027, 1, 31), QDate(2027, 3, 31), QDate(2027, 5, 31)}));
}

TEST(RRuleRfc, LastFridayViaBySetPos) {
  const QVector<QDate> d = datesOf(
      QStringLiteral("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1"), QDate(2026, 10, 30), QDate(2026, 10, 1), QDate(2026, 12, 31));
  // The last working day of Oct, Nov and Dec 2026.
  EXPECT_EQ(d, (QVector<QDate>{QDate(2026, 10, 30), QDate(2026, 11, 30), QDate(2026, 12, 31)}));
  const QVector<QDate> f =
      datesOf(QStringLiteral("FREQ=MONTHLY;BYDAY=FR;BYSETPOS=-1"), QDate(2026, 10, 30), QDate(2026, 10, 1), QDate(2026, 12, 31));
  EXPECT_EQ(f, (QVector<QDate>{QDate(2026, 10, 30), QDate(2026, 11, 27), QDate(2026, 12, 25)}));
}

TEST(RRuleRfc, OrdinalWeekdayInAMonth) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=MONTHLY;BYDAY=2TH"), QDate(2026, 10, 8), QDate(2026, 10, 1), QDate(2026, 12, 31));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2026, 10, 8), QDate(2026, 11, 12), QDate(2026, 12, 10)}));
}

TEST(RRuleRfc, YearlyByMonthListHitsEveryMonth) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=YEARLY;BYMONTH=3,9"), QDate(2026, 3, 10), QDate(2026, 1, 1), QDate(2027, 12, 31));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2026, 3, 10), QDate(2026, 9, 10), QDate(2027, 3, 10), QDate(2027, 9, 10)}));
}

TEST(RRuleRfc, YearlyOrdinalWeekdayOfAMonth) {
  // US Thanksgiving: the fourth Thursday of November.
  const QVector<QDate> d =
      datesOf(QStringLiteral("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH"), QDate(2026, 11, 26), QDate(2026, 1, 1), QDate(2028, 12, 31));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2026, 11, 26), QDate(2027, 11, 25), QDate(2028, 11, 23)}));
}

// WKST decides which days share a week for INTERVAL>1. The RFC's own example:
// every other week on TU,SU from Tue 5 Aug 1997 gives Aug 5, 10, 19, 24 with
// WKST=MO and Aug 5, 17, 19, 31 with WKST=SU.
TEST(RRuleRfc, WeekStartChangesTheBiweeklyPairing) {
  const QVector<QDate> mo = datesOf(
      QStringLiteral("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=MO"), QDate(1997, 8, 5), QDate(1997, 8, 1), QDate(1997, 9, 30));
  EXPECT_EQ(mo, (QVector<QDate>{QDate(1997, 8, 5), QDate(1997, 8, 10), QDate(1997, 8, 19), QDate(1997, 8, 24)}));
  const QVector<QDate> su = datesOf(
      QStringLiteral("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=SU"), QDate(1997, 8, 5), QDate(1997, 8, 1), QDate(1997, 9, 30));
  EXPECT_EQ(su, (QVector<QDate>{QDate(1997, 8, 5), QDate(1997, 8, 17), QDate(1997, 8, 19), QDate(1997, 8, 31)}));
}

// DTSTART is the first occurrence even when it is not one of the rule's days.
TEST(RRuleRfc, AStartOffTheRuleIsStillTheFirstOccurrence) {
  // Wed 7 Oct 2026, rule on Mondays.
  const QVector<QDate> d =
      datesOf(QStringLiteral("FREQ=WEEKLY;BYDAY=MO;COUNT=3"), QDate(2026, 10, 7), QDate(2026, 10, 1), QDate(2026, 12, 31));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2026, 10, 7), QDate(2026, 10, 12), QDate(2026, 10, 19)}));
}

// A daily series did not stop after ~11 years when the window is far ahead.
TEST(RRuleRfc, AFarWindowOfAnUnboundedSeriesIsReached) {
  const QVector<QDate> d = datesOf(QStringLiteral("FREQ=DAILY"), QDate(2010, 1, 1), QDate(2040, 6, 1), QDate(2040, 6, 3));
  EXPECT_EQ(d, (QVector<QDate>{QDate(2040, 6, 1), QDate(2040, 6, 2), QDate(2040, 6, 3)}));
  const QVector<QDate> w = datesOf(QStringLiteral("FREQ=WEEKLY;INTERVAL=2"), QDate(2010, 1, 4), QDate(2040, 6, 1), QDate(2040, 6, 30));
  ASSERT_FALSE(w.isEmpty());
  EXPECT_EQ(QDate(2010, 1, 4).daysTo(w.first()) % 14, 0);
}

TEST(RRuleRfc, AnUtcUntilKeepsTheInstantAndLoosensTheDay) {
  const RRule r = parseRRule(QStringLiteral("FREQ=DAILY;UNTIL=20261216T045959Z"));
  ASSERT_TRUE(r.isValid());
  EXPECT_EQ(r.untilAt, QDateTime(QDate(2026, 12, 16), QTime(4, 59, 59), QTimeZone::utc()));
  EXPECT_EQ(r.until, QDate(2026, 12, 17));
  EXPECT_EQ(heap::cal::toRRuleText(r), QStringLiteral("FREQ=DAILY;UNTIL=20261216T045959Z"));
}

TEST(RRuleRfc, EveryPartRoundTrips) {
  const QString text = QStringLiteral("FREQ=YEARLY;INTERVAL=2;BYMONTH=3,9;BYMONTHDAY=-1,1;BYDAY=-1FR,MO;BYSETPOS=-1,1;WKST=SU;COUNT=6");
  EXPECT_EQ(heap::cal::toRRuleText(parseRRule(text)), text);
}
