// Seed content sanity (HEAP-56).
//
// Guards two properties of the demo profile: calendar events are spread across
// the week (not all stamped to today, which left the Week view looking empty),
// and the sample content is generic software-dev material rather than the old
// niche telecom/LTE workload no non-telecom user could relate to.

#include "Models.h"
#include "SampleData.h"

#include <QDate>
#include <QSet>

#include <gtest/gtest.h>

TEST(SampleData, EventsSpreadAcrossMultipleDays) {
  const QDate today(2026, 5, 19);
  const QVector<CalEvent> evs = SampleData::events(today, SampleData::Lang::En);
  ASSERT_FALSE(evs.isEmpty());

  QSet<qint64> days;
  for(const CalEvent& e : evs) {
    ASSERT_TRUE(e.date.isValid());
    days.insert(e.date.toJulianDay());
    EXPECT_GE(e.date.toJulianDay(), today.toJulianDay());
    EXPECT_LE(e.date.toJulianDay(), today.addDays(6).toJulianDay());
  }
  // At least three distinct days so Week / non-today views are populated.
  EXPECT_GE(days.size(), 3);
}

TEST(SampleData, SeedIsGenericNotTelecom) {
  for(const SampleData::Lang lang : {SampleData::Lang::En, SampleData::Lang::Ru}) {
    for(const Task& t : SampleData::tasks(lang)) {
      const QString blob = t.id + " " + t.title + " " + t.desc;
      EXPECT_FALSE(blob.contains("LTE")) << blob.toStdString();
      EXPECT_FALSE(blob.contains("PDCP"));
      EXPECT_FALSE(blob.contains("HARQ"));
      EXPECT_FALSE(blob.contains("3GPP"));
      EXPECT_FALSE(blob.contains("S1AP"));
    }
  }
}

TEST(SampleData, BoardStaysPopulatedAcrossColumns) {
  // A believable demo needs cards in several columns, not one pile.
  const QVector<Task> ts = SampleData::tasks(SampleData::Lang::En);
  QSet<QString> statuses;
  for(const Task& t : ts) {
    statuses.insert(t.status);
  }
  EXPECT_GE(ts.size(), 10);
  EXPECT_GE(statuses.size(), 4);
}

int main(int argc, char** argv) {
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
