#pragma once

#include "EventClamp.h"
#include "Models.h"

#include <QDateTime>
#include <QTimeZone>

#include <cmath>

// Events whose wall-clock fields belong to another time zone.
//
// heap's events are floating: 10:00 is 10:00 wherever the user is, which is
// right for everything the user types in. It is wrong for a meeting imported
// from New York. Converting it to local time once, at import, fixes the first
// occurrence and breaks the rest: the series then sits at 17:00 Moscow time
// forever, while in New York it moves an hour when the clocks change there.
//
// So an event may name a zone (`CalEvent::tz`). Its date/start/end stay in
// that zone and every occurrence is converted on its own day, which is how
// DST follows the source. The helpers here are the only place that does the
// arithmetic.
namespace heap::cal {

// The zone an event's wall times are in, or an invalid zone for a floating
// event (and for a name this build does not know — then it floats too).
inline QTimeZone zoneOf(const CalEvent& e) {
  if(e.tz.isEmpty()) {
    return {};
  }
  const QTimeZone z(e.tz.toUtf8());
  return z.isValid() ? z : QTimeZone();
}

// An hour on a date as an instant in `zone`. 24.0 is midnight at the end of
// the day, which QTime cannot hold.
inline QDateTime wallInstant(const QDate& date, double hour, const QTimeZone& zone) {
  if(std::isfinite(hour) && hour >= 24.0 - 1e-9) {
    return QDateTime(date.addDays(1), QTime(0, 0), zone);
  }
  const int minutes = qBound(0, static_cast<int>(std::lround((std::isfinite(hour) ? hour : 0.0) * 60.0)), (24 * 60) - 1);
  return QDateTime(date, QTime(minutes / 60, minutes % 60), zone);
}

// The wall date and hour of `at` as seen in `zone`.
inline void wallOf(const QDateTime& at, const QTimeZone& zone, QDate* date, double* hour) {
  const QDateTime there = zone.isValid() ? at.toTimeZone(zone) : at.toLocalTime();
  *date = there.date();
  const QTime t = there.time();
  *hour = t.hour() + (t.minute() / 60.0) + (t.second() / 3600.0);
}

// The event re-expressed in `display` (the viewer's zone). A floating event
// comes back unchanged; a zoned one comes back floating, with its span
// converted — including a span that lands on a different day, or runs past
// midnight only in the viewer's zone.
inline CalEvent localized(const CalEvent& e, const QTimeZone& display) {
  const QTimeZone src = zoneOf(e);
  if(!src.isValid() || !e.date.isValid() || e.allDay) {
    CalEvent out = e;
    if(e.allDay) {
      out.tz.clear();  // a day is a day in every zone
    }
    return out;
  }
  const QDate endDay = (e.endDate.isValid() && e.endDate > e.date) ? e.endDate : e.date;
  const QDateTime startAt = wallInstant(e.date, e.start, src);
  const QDateTime endAt = wallInstant(endDay, e.end, src);

  CalEvent out = e;
  out.tz.clear();
  QDate sd;
  QDate ed;
  double sh = 0.0;
  double eh = 0.0;
  wallOf(startAt, display, &sd, &sh);
  wallOf(endAt, display, &ed, &eh);
  // Midnight belongs to the day before: 22:00 → 00:00 is one day's event.
  if(eh <= 1e-9 && ed > sd) {
    ed = ed.addDays(-1);
    eh = 24.0;
  }
  out.date = sd;
  out.start = sh;
  out.endDate = ed > sd ? ed : QDate();
  out.end = eh;
  return out;
}

// The inverse: a span given in the viewer's zone, written into `zone`'s wall
// clock. Used when an edit made on screen lands on a series that keeps its
// source zone.
inline void toZoneWall(const QDate& date, double hour, const QTimeZone& display, const QTimeZone& zone, QDate* outDate, double* outHour) {
  const QDateTime at = wallInstant(date, hour, display.isValid() ? display : QTimeZone::systemTimeZone());
  wallOf(at, zone, outDate, outHour);
}

}  // namespace heap::cal
