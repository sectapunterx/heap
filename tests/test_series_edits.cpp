// Editing and deleting a repeating event.
//
// Every calendar asks the same question when you touch one instance of a
// series — this one, this and everything after, or all of them — and every
// wrong answer is a quiet data loss: the series silently moves, or an occurrence
// the user deleted comes back, or an override outlives the master and becomes a
// ghost nothing explains.
//
// The expansion itself is covered in test_occurrences.cpp. These cases are
// about what the three scopes write.

#include "AppController.h"
#include "Models.h"

#include "cal/Occurrences.h"

#include <QApplication>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

const QDate kMon(2026, 9, 21);  // a Monday

}  // namespace

class SeriesEditTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->events()->reset({});
  }

  void TearDown() override {
    app_.reset();
  }

  // A weekly master starting on kMon.
  QString seedWeekly(const QString& rule = QStringLiteral("FREQ=WEEKLY")) {
    QVariantMap draft = app_->newEventDraft(10.0, kMon);
    draft["title"] = QStringLiteral("weekly sync");
    draft["date"] = kMon;
    draft["start"] = 10.0;
    draft["end"] = 11.0;
    draft["rrule"] = rule;
    app_->saveEvent(draft);
    return draft.value(QStringLiteral("id")).toString();
  }

  QVariantList occurrences(int days = 28) const {
    return app_->eventOccurrences(kMon, kMon.addDays(days));
  }

  QVector<QDate> dates(int days = 28) const {
    QVector<QDate> out;
    for(const QVariant& v : occurrences(days)) {
      out.append(v.toMap().value(QStringLiteral("date")).toDate());
    }
    std::sort(out.begin(), out.end());
    return out;
  }

  // The occurrence on `day`, as the views would hand it back to an editor.
  QVariantMap occurrenceOn(const QDate& day) const {
    for(const QVariant& v : occurrences(60)) {
      const QVariantMap m = v.toMap();
      if(m.value(QStringLiteral("date")).toDate() == day) {
        return m;
      }
    }
    return {};
  }

  int storedCount() const {
    return app_->events()->rowCount();
  }

  std::unique_ptr<AppController> app_;
};

// A series is one row however long it runs. Writing the dates out would mean a
// row per standup forever, and a merge conflict for every one.
TEST_F(SeriesEditTest, ASeriesIsStoredOnce) {
  seedWeekly();

  EXPECT_EQ(storedCount(), 1);
  EXPECT_EQ(dates().size(), 5);
}

// ── "this" ──

TEST_F(SeriesEditTest, EditingOneOccurrenceLeavesTheRestAlone) {
  const QString id = seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(7));
  ASSERT_FALSE(occ.isEmpty());
  occ["title"] = QStringLiteral("moved");
  occ["date"] = kMon.addDays(10);

  app_->saveOccurrence(occ, QStringLiteral("this"));

  EXPECT_EQ(dates(), (QVector<QDate>{kMon, kMon.addDays(10), kMon.addDays(14), kMon.addDays(21), kMon.addDays(28)}));
  EXPECT_EQ(storedCount(), 2) << "the master plus one override";
}

// An override must not be mistaken for a new master, or it would repeat too.
TEST_F(SeriesEditTest, AnOverrideDoesNotRepeat) {
  seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(7));
  occ["title"] = QStringLiteral("moved");

  app_->saveOccurrence(occ, QStringLiteral("this"));

  for(const QVariant& v : occurrences(60)) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("title")).toString() == QStringLiteral("moved")) {
      EXPECT_TRUE(m.value(QStringLiteral("rrule")).toString().isEmpty());
    }
  }
  EXPECT_EQ(storedCount(), 2);
}

// Editing the same occurrence twice updates the override rather than stacking
// a second one on top of it.
TEST_F(SeriesEditTest, EditingTheSameOccurrenceTwiceDoesNotPileUpOverrides) {
  seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(7));
  occ["title"] = QStringLiteral("first");
  app_->saveOccurrence(occ, QStringLiteral("this"));

  QVariantMap again = occurrenceOn(kMon.addDays(7));
  ASSERT_FALSE(again.isEmpty());
  again["title"] = QStringLiteral("second");
  app_->saveOccurrence(again, QStringLiteral("this"));

  EXPECT_EQ(storedCount(), 2);
  EXPECT_EQ(occurrenceOn(kMon.addDays(7)).value(QStringLiteral("title")).toString(), QStringLiteral("second"));
}

TEST_F(SeriesEditTest, DeletingOneOccurrenceLeavesTheRest) {
  seedWeekly();

  app_->deleteOccurrence(
      occurrenceOn(kMon.addDays(7)).value(QStringLiteral("masterId")).toString(), kMon.addDays(7), QStringLiteral("this"));

  EXPECT_EQ(dates(), (QVector<QDate>{kMon, kMon.addDays(14), kMon.addDays(21), kMon.addDays(28)}));
  EXPECT_EQ(storedCount(), 1) << "a hole is remembered on the master, not stored as a row";
}

// Deleting an occurrence that had been moved removes the override too, or the
// moved copy would survive the deletion.
TEST_F(SeriesEditTest, DeletingAMovedOccurrenceRemovesTheOverride) {
  seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(7));
  const QString masterId = occ.value(QStringLiteral("masterId")).toString();
  occ["date"] = kMon.addDays(10);
  app_->saveOccurrence(occ, QStringLiteral("this"));
  ASSERT_EQ(storedCount(), 2);

  app_->deleteOccurrence(masterId, kMon.addDays(7), QStringLiteral("this"));

  EXPECT_EQ(dates(), (QVector<QDate>{kMon, kMon.addDays(14), kMon.addDays(21), kMon.addDays(28)}));
  EXPECT_EQ(storedCount(), 1);
}

// ── "following" ──

TEST_F(SeriesEditTest, EditingFollowingSplitsTheSeries) {
  seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(14));
  ASSERT_FALSE(occ.isEmpty());
  occ["title"] = QStringLiteral("renamed");

  app_->saveOccurrence(occ, QStringLiteral("following"));

  EXPECT_EQ(storedCount(), 2) << "the truncated original and a new master";
  // Same dates as before: a split changes who owns them, not when they are.
  EXPECT_EQ(dates(), (QVector<QDate>{kMon, kMon.addDays(7), kMon.addDays(14), kMon.addDays(21), kMon.addDays(28)}));
  EXPECT_EQ(occurrenceOn(kMon).value(QStringLiteral("title")).toString(), QStringLiteral("weekly sync"));
  EXPECT_EQ(occurrenceOn(kMon.addDays(14)).value(QStringLiteral("title")).toString(), QStringLiteral("renamed"));
  EXPECT_EQ(occurrenceOn(kMon.addDays(21)).value(QStringLiteral("title")).toString(), QStringLiteral("renamed"));
}

// Splitting at the very first occurrence leaves nothing of the original, which
// must go rather than linger as an empty series.
TEST_F(SeriesEditTest, SplittingAtTheFirstOccurrenceReplacesTheSeries) {
  seedWeekly();
  QVariantMap occ = occurrenceOn(kMon);
  occ["title"] = QStringLiteral("renamed");

  app_->saveOccurrence(occ, QStringLiteral("following"));

  EXPECT_EQ(storedCount(), 1);
  EXPECT_EQ(occurrenceOn(kMon).value(QStringLiteral("title")).toString(), QStringLiteral("renamed"));
  EXPECT_EQ(dates().size(), 5);
}

TEST_F(SeriesEditTest, DeletingFollowingEndsTheSeriesThere) {
  const QString id = seedWeekly();

  app_->deleteOccurrence(id, kMon.addDays(14), QStringLiteral("following"));

  EXPECT_EQ(dates(), (QVector<QDate>{kMon, kMon.addDays(7)}));
  EXPECT_EQ(storedCount(), 1);
}

// Everything after the cut goes, including occurrences that had been moved.
TEST_F(SeriesEditTest, DeletingFollowingTakesLaterOverridesWithIt) {
  const QString id = seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(21));
  occ["date"] = kMon.addDays(23);
  app_->saveOccurrence(occ, QStringLiteral("this"));
  ASSERT_EQ(storedCount(), 2);

  app_->deleteOccurrence(id, kMon.addDays(14), QStringLiteral("following"));

  EXPECT_EQ(dates(), (QVector<QDate>{kMon, kMon.addDays(7)}));
  EXPECT_EQ(storedCount(), 1);
}

// An earlier override is before the cut and survives it.
TEST_F(SeriesEditTest, DeletingFollowingKeepsEarlierOverrides) {
  const QString id = seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(7));
  occ["title"] = QStringLiteral("moved");
  app_->saveOccurrence(occ, QStringLiteral("this"));

  app_->deleteOccurrence(id, kMon.addDays(14), QStringLiteral("following"));

  EXPECT_EQ(occurrenceOn(kMon.addDays(7)).value(QStringLiteral("title")).toString(), QStringLiteral("moved"));
}

TEST_F(SeriesEditTest, DeletingFollowingFromTheFirstOccurrenceRemovesEverything) {
  const QString id = seedWeekly();

  app_->deleteOccurrence(id, kMon, QStringLiteral("following"));

  EXPECT_TRUE(dates().isEmpty());
  EXPECT_EQ(storedCount(), 0);
}

// A deletion must never come back. An occurrence deleted after the split point
// belongs to the new half of the series, and the old half must not keep
// claiming it either.
TEST_F(SeriesEditTest, ASplitCarriesDeletionsToTheRightHalf) {
  const QString id = seedWeekly();
  app_->deleteOccurrence(id, kMon.addDays(21), QStringLiteral("this"));
  app_->deleteOccurrence(id, kMon.addDays(7), QStringLiteral("this"));
  ASSERT_EQ(dates(), (QVector<QDate>{kMon, kMon.addDays(14), kMon.addDays(28)}));

  QVariantMap occ = occurrenceOn(kMon.addDays(14));
  ASSERT_FALSE(occ.isEmpty());
  occ["title"] = QStringLiteral("renamed");
  app_->saveOccurrence(occ, QStringLiteral("following"));

  EXPECT_EQ(dates(), (QVector<QDate>{kMon, kMon.addDays(14), kMon.addDays(28)})) << "neither deleted occurrence may reappear";
}

// ── "all" ──

TEST_F(SeriesEditTest, EditingAllRewritesTheMaster) {
  seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(14));
  occ["title"] = QStringLiteral("renamed");

  app_->saveOccurrence(occ, QStringLiteral("all"));

  EXPECT_EQ(storedCount(), 1);
  for(const QVariant& v : occurrences()) {
    EXPECT_EQ(v.toMap().value(QStringLiteral("title")).toString(), QStringLiteral("renamed"));
  }
  EXPECT_EQ(dates().size(), 5) << "the series keeps its shape";
}

// Moving the whole series moves every occurrence by the same amount, rather
// than collapsing the series onto the day the user happened to be looking at.
TEST_F(SeriesEditTest, MovingAllShiftsTheWholeSeries) {
  seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(14));
  occ["date"] = kMon.addDays(16);  // two days later

  app_->saveOccurrence(occ, QStringLiteral("all"));

  EXPECT_EQ(dates(), (QVector<QDate>{kMon.addDays(2), kMon.addDays(9), kMon.addDays(16), kMon.addDays(23)}));
}

TEST_F(SeriesEditTest, DeletingAllRemovesTheSeries) {
  const QString id = seedWeekly();

  app_->deleteOccurrence(id, kMon.addDays(7), QStringLiteral("all"));

  EXPECT_TRUE(dates().isEmpty());
  EXPECT_EQ(storedCount(), 0);
}

// An override without its master is a ghost: it would draw on a date nothing
// explains, and no edit would reach it.
TEST_F(SeriesEditTest, DeletingAllTakesItsOverridesWithIt) {
  const QString id = seedWeekly();
  QVariantMap occ = occurrenceOn(kMon.addDays(7));
  occ["date"] = kMon.addDays(9);
  app_->saveOccurrence(occ, QStringLiteral("this"));
  ASSERT_EQ(storedCount(), 2);

  app_->deleteOccurrence(id, kMon.addDays(7), QStringLiteral("all"));

  EXPECT_EQ(storedCount(), 0);
  EXPECT_TRUE(dates().isEmpty());
}

// ── Edges ──

// An ordinary event saved through this path is just an ordinary save.
TEST_F(SeriesEditTest, AnEventWithNoSeriesIsSavedNormally) {
  QVariantMap draft = app_->newEventDraft(10.0, kMon);
  draft["title"] = QStringLiteral("one off");
  draft["date"] = kMon;
  app_->saveOccurrence(draft, QStringLiteral("this"));

  EXPECT_EQ(storedCount(), 1);
  EXPECT_EQ(dates().size(), 1);
}

TEST_F(SeriesEditTest, DeletingAnOccurrenceOfAMissingMasterDoesNothing) {
  seedWeekly();

  app_->deleteOccurrence(QStringLiteral("nobody"), kMon, QStringLiteral("all"));

  EXPECT_EQ(storedCount(), 1);
}

// The undo stack has to see a split as one action, not as a truncation the
// user is left stranded in the middle of.
TEST_F(SeriesEditTest, ASplitIsOneUndoStep) {
  seedWeekly();
  const int before = app_->undoDepth();
  QVariantMap occ = occurrenceOn(kMon.addDays(14));
  occ["title"] = QStringLiteral("renamed");

  app_->saveOccurrence(occ, QStringLiteral("following"));

  EXPECT_EQ(app_->undoDepth(), before + 1);
}

TEST_F(SeriesEditTest, UndoRestoresADeletedSeries) {
  const QString id = seedWeekly();
  app_->deleteOccurrence(id, kMon, QStringLiteral("all"));
  ASSERT_EQ(storedCount(), 0);

  app_->undo();

  EXPECT_EQ(storedCount(), 1);
  EXPECT_EQ(dates().size(), 5);
}

TEST_F(SeriesEditTest, UndoRestoresADeletedOccurrence) {
  const QString id = seedWeekly();
  app_->deleteOccurrence(id, kMon.addDays(7), QStringLiteral("this"));
  ASSERT_EQ(dates().size(), 4);

  app_->undo();

  EXPECT_EQ(dates().size(), 5);
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
