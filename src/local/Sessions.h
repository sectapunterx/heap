#pragma once

#include "local/TaskLocal.h"

#include <QDate>
#include <QDateTime>
#include <QVector>

// Timer sessions (APP-251) as pure functions: the task keeps a list of
// {start, end}; the old single total is one session with no date. Nothing
// here reads the clock — `now` is always handed in.
namespace heap::local::sessions {

// A session's length in seconds (0 for a broken one that ends before it
// starts).
int lengthOf(const TimerSession& s);

// The sum of every session: what trackedSeconds holds.
int total(const QVector<TimerSession>& xs);

// Seconds that fall on `day` (local time), a session over midnight counted on
// both sides. A running timer (`runningSince` valid) counts up to `now`.
// Undated sessions belong to no day.
int secondsOn(const QVector<TimerSession>& xs, const QDate& day, const QDateTime& runningSince, const QDateTime& now);

// Adds a finished session [start, end). Ignored when it has no length.
void record(QVector<TimerSession>& xs, const QDateTime& start, const QDateTime& end);

// The total the task had before sessions (or anything over the sessions' sum)
// becomes one undated session, so nothing tracked is lost.
void adoptTotal(QVector<TimerSession>& xs, int trackedSeconds);

}  // namespace heap::local::sessions
