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

// IDIOT-CAL-12: a moved occurrence goes with its slot when the whole series
// moves, not a day before it next to a regular one.
TEST_F(SeriesEditTest, MovingAllTakesAMovedOccurrenceAlongWithItsSlot) {
  seedWeekly();
  QVariantMap one = occurrenceOn(kMon.addDays(7));
  one["start"] = 13.0;
  one["end"] = 14.0;
  app_->saveOccurrence(one, QStringLiteral("this"));
  QVariantMap occ = occurrenceOn(kMon.addDays(14));
  occ["date"] = kMon.addDays(15);  // a day later
  app_->saveOccurrence(occ, QStringLiteral("all"));

  EXPECT_EQ(dates(), (QVector<QDate>{kMon.addDays(1), kMon.addDays(8), kMon.addDays(15), kMon.addDays(22)}));
  const QVariantMap moved = occurrenceOn(kMon.addDays(8));
  EXPECT_DOUBLE_EQ(moved.value(QStringLiteral("start")).toDouble(), 13.0) << "at its own time";
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

// ── "all" on a series with exceptions (TIME-2, TIME-4) ──

namespace {

QVariantMap seriesDraft(AppController& app, const QDate& start, const QString& rule, const QString& title) {
  QVariantMap draft = app.newEventDraft(10.0, start);
  draft["title"] = title;
  draft["date"] = start;
  draft["start"] = 10.0;
  draft["end"] = 11.0;
  draft["rrule"] = rule;
  app.saveEvent(draft);
  return draft;
}

QVariantMap occurrenceAt(const AppController& app, const QDate& day) {
  for(const QVariant& v : app.eventOccurrences(day, day)) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("date")).toDate() == day) {
      return m;
    }
  }
  return {};
}

}  // namespace

class SeriesExceptionsTest : public SeriesEditTest {
 protected:
  const QDate kStart{2031, 3, 3};  // a Monday

  // FREQ=WEEKLY;BYDAY=MO — how Google, Outlook and .ics store a weekly
  // meeting — with 03-10 deleted and 03-17 moved to 12:00.
  QString seedImportedWeekly() {
    const QString id =
        seriesDraft(*app_, kStart, QStringLiteral("FREQ=WEEKLY;BYDAY=MO"), QStringLiteral("imported")).value("id").toString();
    app_->deleteOccurrence(id, kStart.addDays(7), QStringLiteral("this"));
    QVariantMap moved = occurrenceAt(*app_, kStart.addDays(14));
    moved["start"] = 12.0;
    moved["end"] = 13.0;
    app_->saveOccurrence(moved, QStringLiteral("this"));
    return id;
  }

  CalEvent stored(const QString& id) const {
    return app_->events()->items().at(app_->events()->indexOfId(id));
  }

  // The occurrence on `day` as the editor would save it with scope "all":
  // renamed, and with the rule the way the repeat controls rebuild it.
  void renameAll(const QDate& day, const QString& rule) {
    QVariantMap occ = occurrenceAt(*app_, day);
    ASSERT_FALSE(occ.isEmpty());
    occ["title"] = QStringLiteral("renamed");
    occ["rrule"] = rule;
    app_->saveOccurrence(occ, QStringLiteral("all"));
  }
};

// The editor spells a Monday series as "FREQ=WEEKLY"; that is the same rule,
// and renaming must not bring back what was deleted or undo what was moved.
TEST_F(SeriesExceptionsTest, RenamingAByDaySeriesKeepsItsExceptions) {
  const QString id = seedImportedWeekly();

  renameAll(kStart.addDays(21), QStringLiteral("FREQ=WEEKLY"));

  EXPECT_EQ(stored(id).rrule, QStringLiteral("FREQ=WEEKLY;BYDAY=MO")) << "the series keeps its own rule";
  EXPECT_TRUE(occurrenceAt(*app_, kStart.addDays(7)).isEmpty()) << "03-10 stays deleted";
  const QVariantMap moved = occurrenceAt(*app_, kStart.addDays(14));
  ASSERT_FALSE(moved.isEmpty());
  EXPECT_DOUBLE_EQ(moved.value("start").toDouble(), 12.0) << "03-17 stays at 12:00";
  EXPECT_EQ(moved.value("title").toString(), QStringLiteral("renamed")) << "the whole series is renamed";
  EXPECT_EQ(occurrenceAt(*app_, kStart.addDays(28)).value("title").toString(), QStringLiteral("renamed"));
  EXPECT_EQ(occurrenceAt(*app_, kStart.addDays(28)).value("start").toDouble(), 10.0);
}

// A moved occurrence that was given a title of its own keeps it.
TEST_F(SeriesExceptionsTest, RenamingAllKeepsAMovedOccurrencesOwnTitle) {
  seedImportedWeekly();
  QVariantMap own = occurrenceAt(*app_, kStart.addDays(14));
  own["title"] = QStringLiteral("special");
  app_->saveOccurrence(own, QStringLiteral("this"));

  renameAll(kStart.addDays(21), QStringLiteral("FREQ=WEEKLY"));

  EXPECT_EQ(occurrenceAt(*app_, kStart.addDays(14)).value("title").toString(), QStringLiteral("special"));
}

// A new end is not a new pattern: the exceptions stay, the end is taken.
TEST_F(SeriesExceptionsTest, ChangingOnlyTheEndOfAByDaySeriesKeepsItsExceptions) {
  const QString id = seedImportedWeekly();

  renameAll(kStart.addDays(21), QStringLiteral("FREQ=WEEKLY;COUNT=8"));

  const heap::cal::RRule rule = heap::cal::parseRRule(stored(id).rrule);
  EXPECT_EQ(rule.count, 8);
  ASSERT_EQ(rule.byDay.size(), 1);
  EXPECT_EQ(rule.byDay.first().day, 1);
  EXPECT_TRUE(occurrenceAt(*app_, kStart.addDays(7)).isEmpty());
  EXPECT_DOUBLE_EQ(occurrenceAt(*app_, kStart.addDays(14)).value("start").toDouble(), 12.0);
}

// Other days are a new pattern, and the old exceptions were about other dates.
TEST_F(SeriesExceptionsTest, ARealPatternChangeStillDropsTheExceptions) {
  const QString id = seedImportedWeekly();

  renameAll(kStart.addDays(21), QStringLiteral("FREQ=WEEKLY;BYDAY=MO,WE"));

  const CalEvent m = stored(id);
  EXPECT_EQ(m.rrule, QStringLiteral("FREQ=WEEKLY;BYDAY=MO,WE"));
  EXPECT_TRUE(m.exdates.isEmpty());
  EXPECT_EQ(storedCount(), 1) << "the override went with the old pattern";
  EXPECT_FALSE(occurrenceAt(*app_, kStart.addDays(7)).isEmpty());
}

// Renaming Monday's meeting that was moved to Wednesday, for all events,
// renames the series. It stays a Monday series, and the moved one — the one
// the user was looking at — takes the new title too.
TEST_F(SeriesExceptionsTest, RenamingAMovedOccurrenceForAllDoesNotShiftTheSeries) {
  const QDate start(2033, 5, 2);  // a Monday
  const QString id = seriesDraft(*app_, start, QStringLiteral("FREQ=WEEKLY"), QStringLiteral("weekly")).value("id").toString();
  QVariantMap occ = occurrenceAt(*app_, start.addDays(7));
  occ["date"] = start.addDays(9);  // Wednesday 05-11
  app_->saveOccurrence(occ, QStringLiteral("this"));

  renameAll(start.addDays(9), QStringLiteral("FREQ=WEEKLY"));

  const CalEvent m = stored(id);
  EXPECT_EQ(m.date, start) << "still on Mondays";
  EXPECT_DOUBLE_EQ(m.start, 10.0);
  EXPECT_EQ(occurrenceAt(*app_, start.addDays(14)).value("title").toString(), QStringLiteral("renamed"));
  const QVariantMap moved = occurrenceAt(*app_, start.addDays(9));
  ASSERT_FALSE(moved.isEmpty()) << "the moved one stays on its Wednesday";
  EXPECT_EQ(moved.value("title").toString(), QStringLiteral("renamed"));
  EXPECT_EQ(moved.value("occurrenceDate").toDate(), start.addDays(7));
  EXPECT_TRUE(occurrenceAt(*app_, start.addDays(7)).isEmpty());
}

// A real change on a moved occurrence, for all events: a new time is the
// series' new time; a new day moves the series by as many days as the moved
// one was moved from where it sat.
TEST_F(SeriesExceptionsTest, ChangingAMovedOccurrenceForAllMovesTheSeriesByTheEdit) {
  const QDate start(2033, 5, 2);
  const QString id = seriesDraft(*app_, start, QStringLiteral("FREQ=WEEKLY"), QStringLiteral("weekly")).value("id").toString();
  QVariantMap occ = occurrenceAt(*app_, start.addDays(7));
  occ["date"] = start.addDays(9);
  app_->saveOccurrence(occ, QStringLiteral("this"));

  QVariantMap retimed = occurrenceAt(*app_, start.addDays(9));
  retimed["start"] = 14.0;
  retimed["end"] = 15.0;
  app_->saveOccurrence(retimed, QStringLiteral("all"));
  EXPECT_EQ(stored(id).date, start);
  EXPECT_DOUBLE_EQ(stored(id).start, 14.0);
  EXPECT_DOUBLE_EQ(occurrenceAt(*app_, start.addDays(14)).value("start").toDouble(), 14.0);
  EXPECT_DOUBLE_EQ(occurrenceAt(*app_, start.addDays(9)).value("start").toDouble(), 14.0);

  QVariantMap redated = occurrenceAt(*app_, start.addDays(9));
  redated["date"] = start.addDays(10);  // Wednesday -> Thursday
  app_->saveOccurrence(redated, QStringLiteral("all"));
  EXPECT_EQ(stored(id).date, start.addDays(1)) << "one day later: Tuesdays";
  const QVariantMap moved = occurrenceAt(*app_, start.addDays(10));
  ASSERT_FALSE(moved.isEmpty());
  EXPECT_EQ(moved.value("occurrenceDate").toDate(), start.addDays(8)) << "it still replaces its own (now Tuesday) occurrence";
  EXPECT_TRUE(occurrenceAt(*app_, start.addDays(8)).isEmpty());
  EXPECT_FALSE(occurrenceAt(*app_, start.addDays(15)).isEmpty());
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
