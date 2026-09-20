#pragma once

#include "EventClamp.h"

#include <QDate>

#include <utility>

// Events that are not one block on one day.
//
// A CalEvent used to be exactly that: a date, and two hours inside it. The
// invariant was enforced by clampHours(), which pins a range that runs past
// midnight to the end of the day rather than wrapping — correct for a drag, and
// wrong for the two things a calendar is expected to hold anyway:
//
//   * an all-day event (a holiday, a release day, a trip) that has no hours at
//     all and can cover a run of days;
//   * a timed event that crosses midnight (22:00 → 02:00), which is one event
//     the user entered once and two blocks the grid has to draw.
//
// Both are described by the same two extra fields — `allDay` and `endDate` —
// and normalized here, so that every write path (saveEvent, updateEvent, .ics
// import, a drag in any view) lands on the same shape and the views can assume
// it. Rendering the per-day pieces is a separate job: see qml/Segments.js.
namespace heap::cal {

// A span an event covers. `endDate` is always valid and never before `date`;
// `start` is an hour on `date` and `end` an hour on `endDate`. For an all-day
// span the hours are 0 and 24 and carry no meaning of their own.
struct Span {
  QDate date;
  QDate endDate;
  double start = 0.0;
  double end = 0.0;
  bool allDay = false;

  bool operator==(const Span&) const = default;

  // Days touched, counting both ends. 1 for an ordinary event.
  [[nodiscard]] int dayCount() const {
    return date.isValid() && endDate.isValid() ? static_cast<int>(date.daysTo(endDate)) + 1 : 1;
  }

  // True when the span needs more than one day's worth of drawing.
  [[nodiscard]] bool multiDay() const {
    return dayCount() > 1;
  }
};

// An event longer than this is a data-entry accident or a corrupt import, not
// a plan. Rendering one costs a delegate per day in every month it touches, so
// the span is truncated rather than trusted.
inline constexpr int kMaxSpanDays = 366;

// Normalizes a raw span into the invariants above.
//
// `endDate` may be null or garbage — a single-day event carries no end date at
// all, and that is the common case. An all-day span loses its hours. A timed
// span that ends on a later day keeps both edges as given (an event may legally
// end at 02:00, which clampHours would refuse on a single day); a single-day
// span goes through clampHours unchanged, so nothing about ordinary events
// moves.
inline Span normalizeSpan(QDate date, QDate endDate, double start, double end, bool allDay, double step) {
  Span out;
  out.date = date;
  out.allDay = allDay;

  // An end before the start is a swapped pair, not an empty event: a drag that
  // crosses the anchor, or an .ics DTEND the exporter wrote loosely.
  if(endDate.isValid() && date.isValid() && endDate < date) {
    std::swap(date, endDate);
    out.date = date;
  }
  out.endDate = (endDate.isValid() && date.isValid() && endDate > date) ? endDate : date;

  if(out.date.isValid() && out.endDate.isValid() && out.dayCount() > kMaxSpanDays) {
    out.endDate = out.date.addDays(kMaxSpanDays - 1);
  }

  if(allDay) {
    out.start = 0.0;
    out.end = 24.0;
    return out;
  }

  if(out.endDate == out.date) {
    const HourRange r = clampHours(start, end, step);
    out.start = r.start;
    out.end = r.end;
    return out;
  }

  // Multi-day: the event is already longer than any minimum, so each edge is
  // only snapped to the grid and kept inside its own day.
  const double s = stepHours(static_cast<int>(std::lround(step * 60.0)));
  const auto snap = [s](double h) {
    return std::round(qBound(0.0, std::isfinite(h) ? h : 0.0, 24.0) / s) * s;
  };
  out.start = qMin(snap(start), 24.0 - s);
  out.end = snap(end);

  // An end of exactly midnight belongs to the previous day — "Monday 22:00 to
  // Tuesday 00:00" is a Monday event. Giving the last day a zero-length piece
  // instead would draw an invisible block the user cannot grab.
  if(out.end <= 0.0) {
    out.endDate = out.endDate.addDays(-1);
    out.end = 24.0;
    if(out.endDate <= out.date) {
      out.endDate = out.date;
      const HourRange r = clampHours(out.start, 24.0, s);
      out.start = r.start;
      out.end = r.end;
    }
  }
  return out;
}

}  // namespace heap::cal
