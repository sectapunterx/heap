#pragma once

#include "StateSerializer.h"

#include <QHash>
#include <QString>
#include <QtGlobal>
#include <QVector>

#include <algorithm>
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
    // Above everything: one step above the first card. Halving toward zero
    // had no room at all once the first card sat at rank 0 (every demo card,
    // every synced issue), so "to the top" landed on a tie and did nothing.
    // Ranks may go negative; a double has room for 2^53 such steps.
    return after - state::kRankStep;
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

// Spread out every column that holds two cards on the same rank, keeping the
// order the board shows (rank, then id). Ties come from data written before
// every path handed out ranks — the demo seed, synced issues, editor saves —
// and a tie is a gap no drop can land in. Returns how many tasks it re-ranked;
// columns without a tie are left alone, so this is a no-op on clean data.
template<class TaskT>
int spreadTiedRanks(QVector<TaskT>& tasks) {
  QHash<QString, QVector<int>> byStatus;
  for(int i = 0; i < tasks.size(); ++i) {
    byStatus[tasks.at(i).status].append(i);
  }
  int changed = 0;
  for(auto it = byStatus.begin(); it != byStatus.end(); ++it) {
    QVector<int>& rows = it.value();
    std::sort(rows.begin(), rows.end(), [&](int a, int b) {
      const TaskT& x = tasks.at(a);
      const TaskT& y = tasks.at(b);
      return x.rank != y.rank ? x.rank < y.rank : x.id < y.id;
    });
    bool tie = false;
    for(int k = 1; k < rows.size() && !tie; ++k) {
      tie = tasks.at(rows[k - 1]).rank == tasks.at(rows[k]).rank;
    }
    if(!tie) {
      continue;
    }
    for(int k = 0; k < rows.size(); ++k) {
      const double r = (k + 1) * state::kRankStep;
      if(tasks[rows[k]].rank != r) {
        tasks[rows[k]].rank = r;
        ++changed;
      }
    }
  }
  return changed;
}

}  // namespace heap::board
