#pragma once

#include "Models.h"

#include <QDate>
#include <QDateTime>
#include <QHash>
#include <QStringList>
#include <QVector>

// The Monday recap (WEAK PECAP): which tasks changed column last week, as
// "backlog -> in progress: these three". Pure, so the rules are tested
// without a clock or a window.
namespace heap::recap {

// Where a task started a period and where it ended it.
struct Move {
  QString taskId;
  QString from;
  QString to;

  bool operator==(const Move&) const = default;
};

// The Monday of the week `d` falls in.
inline QDate weekStart(const QDate& d) {
  return d.addDays(1 - d.dayOfWeek());
}

// Each task's net move over [start, end): the column it left first and the
// one it was in after its last move. A task that went somewhere and came back
// (or a move that was undone) ended where it began and is left out. In the
// order the tasks first moved.
inline QVector<Move> netMoves(const QVector<StatusChange>& log, const QDateTime& start, const QDateTime& end) {
  QVector<Move> out;
  QHash<QString, qsizetype> at;
  for(const StatusChange& c : log) {
    if(c.at < start || c.at >= end || c.from == c.to) {
      continue;
    }
    const auto it = at.constFind(c.taskId);
    if(it == at.constEnd()) {
      at.insert(c.taskId, out.size());
      out.append({.taskId = c.taskId, .from = c.from, .to = c.to});
    } else {
      out[*it].to = c.to;
    }
  }
  QVector<Move> moved;
  for(const Move& m : out) {
    if(m.from != m.to) {
      moved.append(m);
    }
  }
  return moved;
}

// `log` without the entries older than `horizon`, so it does not grow for
// ever.
inline QVector<StatusChange> pruned(const QVector<StatusChange>& log, const QDateTime& horizon) {
  QVector<StatusChange> out;
  out.reserve(log.size());
  for(const StatusChange& c : log) {
    if(c.at >= horizon) {
      out.append(c);
    }
  }
  return out;
}

}  // namespace heap::recap
