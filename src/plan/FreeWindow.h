#pragma once

#include <QDate>
#include <QDateTime>
#include <QVector>

#include <functional>
#include <utility>

// The nearest free window (APP-253): one search for "put it in the next free
// slot", the carry of leftovers (APP-248) and the automatic focus block. What
// is busy is what the day shows — meetings and task blocks, a task with a
// time but no event of its own included — and the window has to fit inside
// the working hours of a working day. When today has no room, the search
// says so instead of quietly booking 21:00: the caller offers tomorrow, or
// today after hours, and the person picks. Pure: `now` and the busy spans
// come in as arguments.
namespace heap::plan {

// Hours on one day, [first, second).
using Span = std::pair<double, double>;

// The first start at or after `from`, on the `step` grid, where a block of
// `hours` fits before `until` without touching anything in `busy`. -1 when
// there is none.
double firstFit(QVector<Span> busy, double from, double until, double hours, double step);

struct WindowAsk {
  QDate date;  // the day asked about
  QDateTime now;
  double hours = 1;  // the block's length
  double workStart = 9;
  double workEnd = 19;
  double step = 0.25;  // the calendar's snap, in hours
  int maxDays = 14;    // how far ahead the next working day may be
};

struct Window {
  // A window inside the working hours of `date`.
  bool found = false;
  double start = -1;
  // When there is none: the first window of the next working day after
  // `date`, and the first gap left on `date` past its working hours (-1 when
  // even that does not fit before midnight).
  QDate nextDate;
  double nextStart = -1;
  double lateStart = -1;
};

using BusyOn = std::function<QVector<Span>(const QDate&)>;
using IsWorkDay = std::function<bool(const QDate&)>;

// Where the search starts on `date`: the top of the working day, or the next
// grid step from `now` when that is later. A day already gone has no start
// (-1).
double searchFrom(const QDate& date, const QDateTime& now, double workStart, double step);

Window findWindow(const WindowAsk& ask, const BusyOn& busyOn, const IsWorkDay& isWorkDay);

// The first window from `ask.date` on, that day or a later working day:
// what "the nearest window" means when the person has already chosen to
// carry something on (APP-248). Invalid date when none in `maxDays`.
std::pair<QDate, double> nextWindow(const WindowAsk& ask, const BusyOn& busyOn, const IsWorkDay& isWorkDay);

}  // namespace heap::plan
