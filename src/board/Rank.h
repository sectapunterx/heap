#pragma once

#include "StateSerializer.h"

#include <QtGlobal>

#include <cmath>


// Fractional ranking for manual card order.
//
// A card's position in its column is a double, and dropping it between two
// others gives it the midpoint of their ranks. That rewrites one task instead
// of renumbering the column — which is what makes the order survive a sync:
// JsonMerger resolves conflicts per element, so renumbering would turn one
// reorder into a conflict on every card in the column.
//
// Doubles run out of room eventually. Repeatedly dropping into the same gap
// halves it each time, so after ~50 inserts between the same two neighbours
// the midpoint stops being distinct. needsRebalance() says when that is close,
// and the caller renumbers that one column.
namespace heap::board {

// Rank for a card dropped between `before` and `after`. Either bound may be
// absent, which is what the ends of a column look like:
//   - both absent  → the column is empty
//   - after absent → dropped at the end
//   - before absent → dropped at the top
inline double between(double before, double after, bool hasBefore, bool hasAfter) {
  if(!hasBefore && !hasAfter) {
    return state::kRankStep;
  }
  if(!hasBefore) {
    // Above everything. Halving keeps it positive rather than marching toward
    // negative infinity as cards are dragged to the top over and over.
    return after / 2.0;
  }
  if(!hasAfter) {
    return before + state::kRankStep;
  }
  return before + ((after - before) / 2.0);
}

// True when the gap `a`..`b` is too small to take another midpoint reliably.
// The threshold is well above the point where the midpoint of two neighbours
// equals one of them, so a rebalance happens before order can be lost.
inline bool needsRebalance(double a, double b) {
  const double gap = std::abs(b - a);
  return !std::isfinite(gap) || gap < 1e-6;
}

// The rank a brand-new card gets when it goes to the top of a column whose
// current first card is `firstRank` (or to an empty column).
inline double beforeFirst(double firstRank, bool columnHasCards) {
  return between(0.0, firstRank, false, columnHasCards);
}

}  // namespace heap::board
