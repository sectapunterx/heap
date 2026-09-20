// Fractional ranking for manual card order (src/board/Rank.h).
//
// A card dropped between two others takes the midpoint of their ranks, so one
// task is rewritten per move instead of the whole column being renumbered —
// which is what keeps a reorder from becoming a conflict on every card when
// two devices sync. Pure arithmetic; no Qt event loop.

#include "board/Rank.h"

#include <gtest/gtest.h>

namespace {

constexpr double kStep = heap::state::kRankStep;

}  // namespace

TEST(Rank, BetweenTwoCardsIsTheirMidpoint) {
  EXPECT_DOUBLE_EQ(heap::board::between(1000.0, 2000.0, true, true), 1500.0);
  EXPECT_DOUBLE_EQ(heap::board::between(1000.0, 1001.0, true, true), 1000.5);
}

TEST(Rank, DroppedAtTheEndGoesPastTheLastCard) {
  const double r = heap::board::between(2048.0, 0.0, true, false);
  EXPECT_GT(r, 2048.0);
  EXPECT_DOUBLE_EQ(r, 2048.0 + kStep);
}

// Dragging to the top repeatedly must not walk the rank toward negative
// infinity — halving keeps it positive however many times it happens.
TEST(Rank, DroppedAtTheTopStaysPositive) {
  double first = kStep;
  for(int i = 0; i < 200; ++i) {
    const double r = heap::board::between(0.0, first, false, true);
    EXPECT_GT(r, 0.0) << "iteration " << i;
    EXPECT_LT(r, first);
    first = r;
  }
}

TEST(Rank, AnEmptyColumnGetsTheBaseStep) {
  EXPECT_DOUBLE_EQ(heap::board::between(0.0, 0.0, false, false), kStep);
}

TEST(Rank, BeforeFirstMatchesTheTopOfAColumn) {
  EXPECT_DOUBLE_EQ(heap::board::beforeFirst(1000.0, true), 500.0);
  EXPECT_DOUBLE_EQ(heap::board::beforeFirst(0.0, false), kStep);
}

// The order a sequence of midpoint inserts produces has to stay strictly
// increasing — that is the whole guarantee the board relies on.
TEST(Rank, RepeatedMidpointInsertsStayOrdered) {
  double lo = 0.0;
  double hi = kStep;
  for(int i = 0; i < 40; ++i) {
    const double mid = heap::board::between(lo, hi, true, true);
    ASSERT_GT(mid, lo) << "iteration " << i;
    ASSERT_LT(mid, hi) << "iteration " << i;
    hi = mid;  // keep dropping into the same shrinking gap
  }
}

TEST(Rank, NeedsRebalanceOnlyWhenTheGapIsExhausted) {
  EXPECT_FALSE(heap::board::needsRebalance(1000.0, 2000.0));
  EXPECT_FALSE(heap::board::needsRebalance(1000.0, 1000.001));
  EXPECT_TRUE(heap::board::needsRebalance(1000.0, 1000.0));
  EXPECT_TRUE(heap::board::needsRebalance(1000.0, 1000.0 + 1e-9));
}

// The signal has to fire before the midpoint stops being distinct, or the
// board would silently lose an ordering.
TEST(Rank, RebalanceIsSignalledBeforeMidpointsCollapse) {
  double lo = 0.0;
  double hi = kStep;
  int guard = 0;
  while(!heap::board::needsRebalance(lo, hi) && guard++ < 1000) {
    hi = heap::board::between(lo, hi, true, true);
  }
  ASSERT_LT(guard, 1000) << "the gap must eventually be reported as exhausted";
  // At the moment it is reported, a midpoint is still distinct from both ends.
  const double mid = heap::board::between(lo, hi, true, true);
  EXPECT_GT(mid, lo);
  EXPECT_LT(mid, hi);
}
