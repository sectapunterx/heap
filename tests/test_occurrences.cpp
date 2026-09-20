// Turning stored events into the ones a calendar shows.
//
// A repeating meeting is stored once: writing every standup out would mean a
// row per working day forever and a merge conflict for each. The dates come
// from the rule, the deletions from `exdates`, and "just this one, moved" from
// an override event that names the occurrence it replaces.

#include "cal/Occurrences.h"

#include <gtest/gtest.h>

using heap::cal::expandEvents;
using heap::cal::kMaxExpandDays;
using heap::cal::Occurrence;

namespace {

const QDate kMon(2026, 9, 21);  // a Monday

CalEvent master(const QString& id, const QString& rule, const QDate& start = kMon) {
  CalEvent e;
  e.id = id;
  e.title = QStringLiteral("weekly sync");
  e.type = QStringLiteral("sync");
  e.date = start;
  e.start = 10.0;
  e.end = 11.0;
  e.rrule = rule;
  return e;
}

QVector<QDate> datesOf(const QVector<Occurrence>& xs) {
  QVector<QDate> out;
  out.reserve(xs.size());
  for(const Occurrence& o : xs) {
    out.append(o.event.date);
  }
  std::sort(out.begin(), out.end());
  return out;
}

}  // namespace

// An event with no rule is itself, once.
TEST(Occurrences, AnOrdinaryEventPassesThrough) {
  CalEvent e = master(QStringLiteral("a"), QString());

  const auto out = expandEvents({e}, kMon, kMon.addDays(30));

  ASSERT_EQ(out.size(), 1);
  EXPECT_EQ(out.at(0).event.date, kMon);
  EXPECT_FALSE(out.at(0).generated);
}

TEST(Occurrences, AnOrdinaryEventOutsideTheRangeIsNotEmitted) {
  CalEvent e = master(QStringLiteral("a"), QString());

  EXPECT_TRUE(expandEvents({e}, kMon.addDays(10), kMon.addDays(20)).isEmpty());
}

// A multi-day event that began before the range still reaches into it.
TEST(Occurrences, AnEventStartingBeforeTheRangeStillReachesIntoIt) {
  CalEvent e = master(QStringLiteral("a"), QString());
  e.endDate = kMon.addDays(5);

  const auto out = expandEvents({e}, kMon.addDays(3), kMon.addDays(4));

  EXPECT_EQ(out.size(), 1);
}

TEST(Occurrences, AWeeklyRuleRepeatsAcrossTheRange) {
  const auto out = expandEvents({master(QStringLiteral("a"), QStringLiteral("FREQ=WEEKLY"))}, kMon, kMon.addDays(21));

  EXPECT_EQ(datesOf(out), (QVector<QDate>{kMon, kMon.addDays(7), kMon.addDays(14), kMon.addDays(21)}));
}

// Every generated instance is a real event the views can draw without knowing
// anything about recurrence.
TEST(Occurrences, AGeneratedInstanceKeepsTheMastersDetails) {
  const auto out = expandEvents({master(QStringLiteral("a"), QStringLiteral("FREQ=WEEKLY"))}, kMon, kMon.addDays(7));

  ASSERT_GE(out.size(), 2);
  for(const Occurrence& o : out) {
    EXPECT_EQ(o.event.title, QStringLiteral("weekly sync"));
    EXPECT_DOUBLE_EQ(o.event.start, 10.0);
    EXPECT_DOUBLE_EQ(o.event.end, 11.0);
  }
}

// An instance is not a master: it carries no rule of its own, or expanding the
// expansion would repeat it forever.
TEST(Occurrences, AGeneratedInstanceCarriesNoRuleOfItsOwn) {
  const auto out = expandEvents({master(QStringLiteral("a"), QStringLiteral("FREQ=DAILY"))}, kMon, kMon.addDays(2));

  ASSERT_FALSE(out.isEmpty());
  for(const Occurrence& o : out) {
    EXPECT_TRUE(o.event.rrule.isEmpty());
  }
}

// It does point back at the series, so a click can find it again.
TEST(Occurrences, AGeneratedInstancePointsAtItsMaster) {
  const auto out = expandEvents({master(QStringLiteral("a"), QStringLiteral("FREQ=DAILY"))}, kMon, kMon.addDays(1));

  ASSERT_FALSE(out.isEmpty());
  EXPECT_EQ(out.at(0).event.masterId, QStringLiteral("a"));
  EXPECT_EQ(out.at(0).event.originalDate, out.at(0).event.date);
  EXPECT_TRUE(out.at(0).generated);
}

// A two-day event repeats as a two-day event.
TEST(Occurrences, AMultiDayMasterRepeatsWithItsLength) {
  CalEvent e = master(QStringLiteral("a"), QStringLiteral("FREQ=WEEKLY"));
  e.endDate = kMon.addDays(2);

  const auto out = expandEvents({e}, kMon, kMon.addDays(14));

  ASSERT_GE(out.size(), 2);
  for(const Occurrence& o : out) {
    EXPECT_EQ(o.event.date.daysTo(o.event.endDate), 2);
  }
}

// Deleting one standup must not delete the series.
TEST(Occurrences, AnExdateRemovesExactlyOneOccurrence) {
  CalEvent e = master(QStringLiteral("a"), QStringLiteral("FREQ=WEEKLY"));
  e.exdates = {kMon.addDays(7)};

  const auto out = expandEvents({e}, kMon, kMon.addDays(21));

  EXPECT_EQ(datesOf(out), (QVector<QDate>{kMon, kMon.addDays(14), kMon.addDays(21)}));
}

TEST(Occurrences, AnExdateThatMatchesNoOccurrenceChangesNothing) {
  CalEvent e = master(QStringLiteral("a"), QStringLiteral("FREQ=WEEKLY"));
  e.exdates = {kMon.addDays(3)};  // a Thursday; the series is on Mondays

  EXPECT_EQ(expandEvents({e}, kMon, kMon.addDays(21)).size(), 4);
}

// Moving one week's meeting leaves the rest of the series where it was.
TEST(Occurrences, AnOverrideReplacesItsOccurrence) {
  CalEvent m = master(QStringLiteral("a"), QStringLiteral("FREQ=WEEKLY"));
  CalEvent ov = master(QStringLiteral("a-2"), QString(), kMon.addDays(10));
  ov.title = QStringLiteral("moved");
  ov.masterId = QStringLiteral("a");
  ov.originalDate = kMon.addDays(7);

  const auto out = expandEvents({m, ov}, kMon, kMon.addDays(21));

  EXPECT_EQ(datesOf(out), (QVector<QDate>{kMon, kMon.addDays(10), kMon.addDays(14), kMon.addDays(21)}));
  bool sawMoved = false;
  for(const Occurrence& o : out) {
    if(o.event.title == QStringLiteral("moved")) {
      sawMoved = true;
      EXPECT_EQ(o.occurrenceDate, kMon.addDays(7)) << "it still knows which occurrence it replaces";
      EXPECT_FALSE(o.generated);
    }
  }
  EXPECT_TRUE(sawMoved);
}

// An override whose master is gone would be a ghost the user cannot explain.
TEST(Occurrences, AnOrphanedOverrideIsNotEmitted) {
  CalEvent ov = master(QStringLiteral("a-2"), QString());
  ov.masterId = QStringLiteral("nobody");
  ov.originalDate = kMon;

  EXPECT_TRUE(expandEvents({ov}, kMon, kMon.addDays(21)).isEmpty());
}

// Deleting an occurrence that had been moved removes it once, not twice.
TEST(Occurrences, AnExdateBeatsAnOverrideForTheSameDate) {
  CalEvent m = master(QStringLiteral("a"), QStringLiteral("FREQ=WEEKLY"));
  m.exdates = {kMon.addDays(7)};
  CalEvent ov = master(QStringLiteral("a-2"), QString(), kMon.addDays(10));
  ov.masterId = QStringLiteral("a");
  ov.originalDate = kMon.addDays(7);

  const auto out = expandEvents({m, ov}, kMon, kMon.addDays(21));

  EXPECT_EQ(datesOf(out), (QVector<QDate>{kMon, kMon.addDays(14), kMon.addDays(21)}));
}

TEST(Occurrences, ACountLimitsTheSeries) {
  const auto out = expandEvents({master(QStringLiteral("a"), QStringLiteral("FREQ=WEEKLY;COUNT=2"))}, kMon, kMon.addDays(60));

  EXPECT_EQ(out.size(), 2);
}

TEST(Occurrences, AnUntilLimitsTheSeries) {
  const QString rule = QStringLiteral("FREQ=WEEKLY;UNTIL=") + kMon.addDays(7).toString(QStringLiteral("yyyyMMdd"));

  const auto out = expandEvents({master(QStringLiteral("a"), rule)}, kMon, kMon.addDays(60));

  EXPECT_EQ(datesOf(out), (QVector<QDate>{kMon, kMon.addDays(7)}));
}

// A rule heap does not understand is a single event, not nothing: dropping it
// would hide something the user put in the calendar.
TEST(Occurrences, AnUnparseableRuleFallsBackToOneEvent) {
  const auto out = expandEvents({master(QStringLiteral("a"), QStringLiteral("FREQ=FORTNIGHTLY;NONSENSE"))}, kMon, kMon.addDays(60));

  ASSERT_EQ(out.size(), 1);
  EXPECT_EQ(out.at(0).event.date, kMon);
}

TEST(Occurrences, AnInvalidRangeExpandsToNothing) {
  const auto e = master(QStringLiteral("a"), QStringLiteral("FREQ=DAILY"));

  EXPECT_TRUE(expandEvents({e}, QDate(), kMon).isEmpty());
  EXPECT_TRUE(expandEvents({e}, kMon, QDate()).isEmpty());
  EXPECT_TRUE(expandEvents({e}, kMon.addDays(5), kMon).isEmpty());
}

// A view asking for a decade of a daily rule is a bug in the view; it must not
// become thousands of delegates.
TEST(Occurrences, AnAbsurdRangeIsCapped) {
  const auto out = expandEvents({master(QStringLiteral("a"), QStringLiteral("FREQ=DAILY"))}, kMon, kMon.addYears(10));

  EXPECT_LE(out.size(), kMaxExpandDays + 1);
}

TEST(Occurrences, ARecurringEventWithNoDateIsSkipped) {
  CalEvent e = master(QStringLiteral("a"), QStringLiteral("FREQ=DAILY"));
  e.date = QDate();

  EXPECT_TRUE(expandEvents({e}, kMon, kMon.addDays(10)).isEmpty());
}

// Two series must not be confused with each other, however similar.
TEST(Occurrences, OverridesOnlyApplyToTheirOwnMaster) {
  CalEvent a = master(QStringLiteral("a"), QStringLiteral("FREQ=WEEKLY"));
  CalEvent b = master(QStringLiteral("b"), QStringLiteral("FREQ=WEEKLY"));
  CalEvent ov = master(QStringLiteral("a-2"), QString(), kMon.addDays(10));
  ov.masterId = QStringLiteral("a");
  ov.originalDate = kMon.addDays(7);

  const auto out = expandEvents({a, b, ov}, kMon, kMon.addDays(7));

  // b keeps both of its own occurrences; a lost one to the override, which
  // moved outside this range.
  int fromB = 0;
  for(const Occurrence& o : out) {
    if(o.event.masterId == QStringLiteral("b")) {
      fromB++;
    }
  }
  EXPECT_EQ(fromB, 2);
}
