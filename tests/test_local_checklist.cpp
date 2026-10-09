// The card's own checklist (APP-236) and timer sessions (APP-251): the pure
// rules under src/local, no AppController.

#include "local/Checklist.h"
#include "local/Sessions.h"

#include <gtest/gtest.h>

namespace cl = heap::local::checklist;
namespace ss = heap::local::sessions;

namespace {

QList<int> levels(const QVector<LocalCheckItem>& xs) {
  QList<int> out;
  for(const LocalCheckItem& c : xs) {
    out << c.level;
  }
  return out;
}

QStringList texts(const QVector<LocalCheckItem>& xs) {
  QStringList out;
  for(const LocalCheckItem& c : xs) {
    out << c.text;
  }
  return out;
}

int at(const QVector<LocalCheckItem>& xs, const QString& text) {
  for(int i = 0; i < xs.size(); ++i) {
    if(xs.at(i).text == text) {
      return i;
    }
  }
  return -1;
}

}  // namespace

// ── levels ──

TEST(LocalChecklistParse, DashesSpacedOrJoinedGiveTheSameLevel) {
  const auto xs = cl::parse(QStringLiteral("plain\n- one\n-- two\n- - two b\n--- three\n- - - three b\n- -- three c\n---- four"));
  EXPECT_EQ(levels(xs), (QList<int>{1, 1, 2, 2, 3, 3, 3, 4}));
  EXPECT_EQ(texts(xs).first(), QStringLiteral("plain"));
  EXPECT_EQ(xs.at(4).text, QStringLiteral("three"));
}

TEST(LocalChecklistParse, LeadingSpacesAreNotNesting) {
  const auto xs = cl::parse(QStringLiteral("top\n   -- indented\n\t- tabbed"));
  EXPECT_EQ(levels(xs), (QList<int>{1, 1, 1}));
  EXPECT_EQ(xs.at(1).text, QStringLiteral("indented"));
  EXPECT_EQ(xs.at(2).text, QStringLiteral("tabbed"));
}

TEST(LocalChecklistParse, AJumpOfTwoLevelsIsKept) {
  const auto xs = cl::parse(QStringLiteral("- a\n--- deep\n- b"));
  EXPECT_EQ(levels(xs), (QList<int>{1, 3, 1}));
  EXPECT_TRUE(cl::hasChildren(xs, 0));
  EXPECT_EQ(cl::subtreeEnd(xs, 0), 2);
}

TEST(LocalChecklistParse, MarksBlankLinesAndStraySpaces) {
  const auto xs = cl::parse(QStringLiteral("\n-- [ ] open\n\n- [x] done\n[x] bare done\n- [X]   spaced   \r\n-5 degrees\n- --x\n"));
  ASSERT_EQ(xs.size(), 6);
  EXPECT_FALSE(xs.at(0).done);
  EXPECT_EQ(xs.at(0).level, 2);
  EXPECT_TRUE(xs.at(1).done);
  EXPECT_EQ(xs.at(1).text, QStringLiteral("done"));
  EXPECT_TRUE(xs.at(2).done);
  EXPECT_EQ(xs.at(2).level, 1);
  EXPECT_EQ(xs.at(3).text, QStringLiteral("spaced"));
  EXPECT_EQ(xs.at(4).text, QStringLiteral("-5 degrees"));  // a dash on a word is text
  EXPECT_EQ(xs.at(4).level, 1);
  EXPECT_EQ(xs.at(5).text, QStringLiteral("--x"));
}

TEST(LocalChecklistParse, CyrillicXTicksToo) {
  const auto xs = cl::parse(QStringLiteral("- [х] сделано\n- [ ] нет"));
  EXPECT_TRUE(xs.at(0).done);
  EXPECT_FALSE(xs.at(1).done);
  EXPECT_EQ(xs.at(0).text, QStringLiteral("сделано"));
}

TEST(LocalChecklistParse, CanonicalTextRoundTrips) {
  const QString text = QStringLiteral("- [x] repro\n-- [x] log\n- fix\n--- deep one\n- ship");
  const auto xs = cl::parse(text);
  EXPECT_EQ(cl::serialize(xs), text);
  const auto again = cl::parse(cl::serialize(xs), xs);
  EXPECT_EQ(again, xs);
}

TEST(LocalChecklistParse, LooseInputSerializesCanonically) {
  const auto xs = cl::parse(QStringLiteral("a\n - - b\n- - [X] c"));
  // b's only child is done, so b is closed too (automatically).
  EXPECT_EQ(cl::serialize(xs), QStringLiteral("- a\n- [x] b\n-- [x] c"));
  EXPECT_TRUE(xs.at(1).autoDone);
}

TEST(LocalChecklistParse, EditingTheTextKeepsIds) {
  const auto xs = cl::parse(QStringLiteral("- a\n- b\n- c"));
  const auto edited = cl::parse(QStringLiteral("- c\n- a\n- new"), xs);
  EXPECT_EQ(edited.at(0).id, xs.at(2).id);
  EXPECT_EQ(edited.at(1).id, xs.at(0).id);
  EXPECT_NE(edited.at(2).id, xs.at(1).id);
}

// ── ticks ──

TEST(LocalChecklistTicks, TickingAParentTicksEveryDescendant) {
  auto xs = cl::parse(QStringLiteral("- p\n-- c1\n--- g\n-- c2\n- other"));
  cl::setDone(xs, 0, true);
  for(int i = 0; i < 4; ++i) {
    EXPECT_TRUE(xs.at(i).done) << i;
    EXPECT_FALSE(xs.at(i).autoDone) << i;
  }
  EXPECT_FALSE(xs.at(4).done);
  EXPECT_EQ(cl::serialize(xs), QStringLiteral("- [x] p\n-- [x] c1\n--- [x] g\n-- [x] c2\n- other"));
  cl::setDone(xs, 0, false);
  for(int i = 0; i < 4; ++i) {
    EXPECT_FALSE(xs.at(i).done) << i;
  }
}

TEST(LocalChecklistTicks, AllChildrenDoneClosesTheParentAutomaticallyUpTheTree) {
  auto xs = cl::parse(QStringLiteral("- grand\n-- parent\n--- a\n--- b\n-- sibling"));
  cl::setDone(xs, at(xs, QStringLiteral("a")), true);
  EXPECT_FALSE(xs.at(at(xs, QStringLiteral("parent"))).done);
  cl::setDone(xs, at(xs, QStringLiteral("b")), true);
  EXPECT_TRUE(xs.at(at(xs, QStringLiteral("parent"))).done);
  EXPECT_TRUE(xs.at(at(xs, QStringLiteral("parent"))).autoDone);
  EXPECT_FALSE(xs.at(at(xs, QStringLiteral("grand"))).done);
  cl::setDone(xs, at(xs, QStringLiteral("sibling")), true);
  EXPECT_TRUE(xs.at(0).done);
  EXPECT_TRUE(xs.at(0).autoDone);
  // In text the auto tick is the same [x].
  EXPECT_TRUE(cl::serialize(xs).startsWith(QStringLiteral("- [x] grand")));
}

TEST(LocalChecklistTicks, UntickingAChildUnticksTheParentChain) {
  auto xs = cl::parse(QStringLiteral("- grand\n-- parent\n--- a"));
  cl::setDone(xs, 0, true);
  cl::setDone(xs, 2, false);
  EXPECT_FALSE(xs.at(0).done);
  EXPECT_FALSE(xs.at(1).done);
}

TEST(LocalChecklistTicks, ProgressCountsEveryLevel) {
  auto xs = cl::parse(QStringLiteral("- a\n-- [x] b\n--- [x] c\n- d"));
  // b's only child is done, a's only child (b) is done → a auto-done.
  const cl::Progress p = cl::progress(xs);
  EXPECT_EQ(p.total, 4);
  EXPECT_EQ(p.done, 3);
}

TEST(LocalChecklistTicks, AnEmptyListHasNoProgressAndNoNextStep) {
  const QVector<LocalCheckItem> none;
  EXPECT_EQ(cl::progress(none).total, 0);
  EXPECT_EQ(cl::nextStep(none), -1);
}

// ── next step ──

TEST(LocalChecklistNext, TheDeepestFirstOpenItemOfTheFirstOpenBranch) {
  auto xs = cl::parse(QStringLiteral("- [x] done\n- build\n-- [x] parse\n-- emit\n--- write header\n--- body\n- ship"));
  EXPECT_EQ(xs.at(cl::nextStep(xs)).text, QStringLiteral("write header"));
  cl::setDone(xs, at(xs, QStringLiteral("write header")), true);
  EXPECT_EQ(xs.at(cl::nextStep(xs)).text, QStringLiteral("body"));
  cl::setDone(xs, at(xs, QStringLiteral("body")), true);
  EXPECT_EQ(xs.at(cl::nextStep(xs)).text, QStringLiteral("ship"));
  cl::setDone(xs, at(xs, QStringLiteral("ship")), true);
  EXPECT_EQ(cl::nextStep(xs), -1);
}

// ── shape edits ──

TEST(LocalChecklistEdit, IndentMovesTheSubtree) {
  auto xs = cl::parse(QStringLiteral("- a\n- b\n-- c"));
  cl::indent(xs, 1, +1);
  EXPECT_EQ(levels(xs), (QList<int>{1, 2, 3}));
  cl::indent(xs, 1, -1);
  EXPECT_EQ(levels(xs), (QList<int>{1, 1, 2}));
  cl::indent(xs, 0, -1);  // level 1 stays
  EXPECT_EQ(levels(xs), (QList<int>{1, 1, 2}));
}

TEST(LocalChecklistEdit, MoveSwapsSiblingSubtrees) {
  auto xs = cl::parse(QStringLiteral("- a\n-- a1\n- b\n-- b1\n--- b2\n- c"));
  const int now = cl::move(xs, at(xs, QStringLiteral("b")), -1);
  EXPECT_EQ(texts(xs), (QStringList{"b", "b1", "b2", "a", "a1", "c"}));
  EXPECT_EQ(now, 0);
  EXPECT_EQ(cl::move(xs, 0, -1), -1);  // already first
  const int down = cl::move(xs, at(xs, QStringLiteral("a")), +1);
  EXPECT_EQ(texts(xs), (QStringList{"b", "b1", "b2", "c", "a", "a1"}));
  EXPECT_EQ(down, 4);
  // A child moves only among its siblings.
  EXPECT_EQ(cl::move(xs, at(xs, QStringLiteral("a1")), -1), -1);
}

TEST(LocalChecklistEdit, RemoveTakesTheSubtreeAndResettlesParents) {
  auto xs = cl::parse(QStringLiteral("- p\n-- [x] a\n-- b\n--- b1"));
  cl::remove(xs, at(xs, QStringLiteral("b")));
  EXPECT_EQ(texts(xs), (QStringList{"p", "a"}));
  EXPECT_TRUE(xs.at(0).done);
  EXPECT_TRUE(xs.at(0).autoDone);
}

// ── sessions (APP-251) ──

TEST(LocalSessions, ASessionOverMidnightCountsOnBothDays) {
  QVector<TimerSession> xs;
  ss::record(xs, QDateTime(QDate(2026, 10, 8), QTime(23, 30)), QDateTime(QDate(2026, 10, 9), QTime(0, 45)));
  EXPECT_EQ(ss::total(xs), 75 * 60);
  EXPECT_EQ(ss::secondsOn(xs, QDate(2026, 10, 8), {}, {}), 30 * 60);
  EXPECT_EQ(ss::secondsOn(xs, QDate(2026, 10, 9), {}, {}), 45 * 60);
  EXPECT_EQ(ss::secondsOn(xs, QDate(2026, 10, 10), {}, {}), 0);
}

TEST(LocalSessions, TheOldTotalBecomesOneUndatedSession) {
  QVector<TimerSession> xs;
  ss::adoptTotal(xs, 5400);
  ASSERT_EQ(xs.size(), 1);
  EXPECT_FALSE(xs.at(0).start.isValid());
  EXPECT_EQ(ss::total(xs), 5400);
  // Only what is missing is adopted; nothing twice.
  ss::adoptTotal(xs, 5400);
  EXPECT_EQ(xs.size(), 1);
  // Undated time belongs to no day.
  EXPECT_EQ(ss::secondsOn(xs, QDate(2026, 10, 9), {}, {}), 0);
}

TEST(LocalSessions, ARunningTimerCountsUpToNow) {
  const QVector<TimerSession> none;
  const QDateTime since(QDate(2026, 10, 9), QTime(9, 0));
  const QDateTime now(QDate(2026, 10, 9), QTime(9, 20));
  EXPECT_EQ(ss::secondsOn(none, QDate(2026, 10, 9), since, now), 20 * 60);
}

TEST(LocalSessions, EmptyOrBackwardSessionsAreNotRecorded) {
  QVector<TimerSession> xs;
  const QDateTime t(QDate(2026, 10, 9), QTime(9, 0));
  ss::record(xs, t, t);
  ss::record(xs, t, t.addSecs(-10));
  EXPECT_TRUE(xs.isEmpty());
}
