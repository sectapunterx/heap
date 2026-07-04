// Pure recurrence engine (HEAP-77): nextOccurrence() over the chrono parser's
// "every:*" tokens. No Qt app needed — QDate is self-contained.

#include "recur/RecurrenceEngine.h"

#include <QDate>

#include <gtest/gtest.h>

using heap::recur::isRecurring;
using heap::recur::nextOccurrence;

TEST(Recur, EveryDayAndWeek) {
  const QDate d(2026, 7, 4);
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:day"), d), d.addDays(1));
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:week"), d), d.addDays(7));
}

TEST(Recur, EveryWeekdaySkipsWeekend) {
  QDate fri(2026, 7, 4);
  while(fri.dayOfWeek() != 5) {  // first Friday on/after the base
    fri = fri.addDays(1);
  }
  const QDate next = nextOccurrence(QStringLiteral("every:weekday"), fri);
  EXPECT_EQ(next.dayOfWeek(), 1);   // Monday
  EXPECT_EQ(next, fri.addDays(3));  // Fri + 3 = Mon

  QDate wed(2026, 7, 4);
  while(wed.dayOfWeek() != 3) {
    wed = wed.addDays(1);
  }
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:weekday"), wed), wed.addDays(1));  // Wed → Thu
}

TEST(Recur, EveryDowLandsStrictlyAfter) {
  QDate mon(2026, 7, 4);
  while(mon.dayOfWeek() != 1) {
    mon = mon.addDays(1);
  }
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:mon"), mon), mon.addDays(7));  // same weekday → next week
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:wed"), mon), mon.addDays(2));  // Mon → Wed
}

TEST(Recur, UnknownEmptyAndInvalidYieldInvalid) {
  const QDate d(2026, 7, 4);
  EXPECT_FALSE(nextOccurrence(QString(), d).isValid());
  EXPECT_FALSE(nextOccurrence(QStringLiteral("every:month"), d).isValid());  // parser emits no monthly token
  EXPECT_FALSE(nextOccurrence(QStringLiteral("nonsense"), d).isValid());
  EXPECT_FALSE(nextOccurrence(QStringLiteral("every:day"), QDate()).isValid());
}

TEST(Recur, IsRecurringMatchesEngine) {
  EXPECT_TRUE(isRecurring(QStringLiteral("every:weekday")));
  EXPECT_TRUE(isRecurring(QStringLiteral("every:fri")));
  EXPECT_FALSE(isRecurring(QString()));
  EXPECT_FALSE(isRecurring(QStringLiteral("every:month")));
}
