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
  EXPECT_FALSE(nextOccurrence(QStringLiteral("every:month:0"), d).isValid());
  EXPECT_FALSE(nextOccurrence(QStringLiteral("every:month:32"), d).isValid());
  EXPECT_FALSE(nextOccurrence(QStringLiteral("nonsense"), d).isValid());
  EXPECT_FALSE(nextOccurrence(QStringLiteral("every:day"), QDate()).isValid());
}

TEST(Recur, IsRecurringMatchesEngine) {
  EXPECT_TRUE(isRecurring(QStringLiteral("every:weekday")));
  EXPECT_TRUE(isRecurring(QStringLiteral("every:fri")));
  EXPECT_FALSE(isRecurring(QString()));
  EXPECT_TRUE(isRecurring(QStringLiteral("every:month")));
  EXPECT_TRUE(isRecurring(QStringLiteral("every:month:15")));
  EXPECT_FALSE(isRecurring(QStringLiteral("every:fortnight")));
}

// "every month on the 15th": the 15th after `from`, clamped in a short month
// and back on the 15th after it.
TEST(Recur, MonthlyOnADayOfTheMonth) {
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:month:15"), QDate(2026, 7, 4)), QDate(2026, 7, 15));
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:month:15"), QDate(2026, 7, 15)), QDate(2026, 8, 15));
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:month:31"), QDate(2026, 1, 31)), QDate(2026, 2, 28));
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:month:31"), QDate(2026, 2, 28)), QDate(2026, 3, 31)) << "no drift to the 28th";
  EXPECT_EQ(nextOccurrence(QStringLiteral("every:month"), QDate(2026, 7, 4)), QDate(2026, 8, 4));
}

// Finishing late must not spawn an occurrence that is already overdue.
TEST(Recur, NextOccurrenceAfterSkipsToTheFuture) {
  using heap::recur::nextOccurrenceAfter;
  const QDate today(2026, 9, 30);  // a Wednesday
  // Weekly from three weeks ago lands on the first one after today.
  EXPECT_EQ(nextOccurrenceAfter(QStringLiteral("every:week"), QDate(2026, 9, 9), today), QDate(2026, 10, 7));
  // Not late: one step, as before.
  EXPECT_EQ(nextOccurrenceAfter(QStringLiteral("every:day"), QDate(2026, 10, 3), today), QDate(2026, 10, 4));
  // Due today, done today: tomorrow, not today again.
  EXPECT_EQ(nextOccurrenceAfter(QStringLiteral("every:day"), today, today), QDate(2026, 10, 1));
  EXPECT_FALSE(nextOccurrenceAfter(QStringLiteral("nonsense"), today, today).isValid());
}
