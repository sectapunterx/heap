#pragma once

#include "EventSpan.h"
#include "Models.h"
#include "RRule.h"

#include <QDate>
#include <QHash>
#include <QVector>

// Turning stored events into the ones a calendar actually shows.
//
// A repeating meeting is stored once. The event that carries `rrule` is the
// master; the dates it lands on are computed, never written, because writing
// them would mean a row per standup per working day forever and a merge
// conflict for every one of them.
//
// Two things bend a series after the fact, and both are stored on the side
// rather than by materialising it:
//
//   * `exdates` on the master — occurrences the user deleted one at a time.
//   * an override: a whole event carrying `masterId` and `originalDate`, which
//     stands in for the occurrence on that date. "Move just this week's 1:1 to
//     Thursday" writes one of these.
//
// expandEvents() applies both and hands back plain CalEvents with real dates,
// so everything downstream — the views, the overlap layout, the reminders —
// keeps working on the shape it already understands.
namespace heap::cal {

// An expanded occurrence. It is a CalEvent so that callers need no new shape,
// plus the two facts that only make sense after expansion.
struct Occurrence {
  CalEvent event;
  // The date this instance falls on. For a master's occurrence it is the
  // computed date; for an override it is the date it replaces, which is not
  // necessarily the date it now sits on.
  QDate occurrenceDate;
  // True when this came out of a rule rather than being stored as itself.
  bool generated = false;
};

// A range wider than this is a caller's bug — a month view asks for six weeks.
// Expanding a daily rule over a decade would build 3650 delegates.
inline constexpr int kMaxExpandDays = 750;

namespace detail {

inline QString overrideKey(const QString& masterId, const QDate& date) {
  return masterId + QLatin1Char('|') + date.toString(Qt::ISODate);
}

}  // namespace detail

// Every occurrence that touches [from, to], from the stored events.
//
// Ordinary events pass through when their span overlaps the range. A master is
// expanded over it; each occurrence is dropped if the date is in `exdates`,
// replaced if an override claims it, and otherwise dated forward — keeping the
// master's length, so a two-day event repeats as a two-day event.
//
// Overrides are never emitted on their own: one whose master is gone would
// otherwise appear as a ghost the user cannot explain, and one whose occurrence
// falls outside the range has no business being drawn.
inline QVector<Occurrence> expandEvents(const QVector<CalEvent>& stored, const QDate& from, const QDate& to) {
  QVector<Occurrence> out;
  if(!from.isValid() || !to.isValid() || to < from) {
    return out;
  }
  const QDate last = from.daysTo(to) > kMaxExpandDays ? from.addDays(kMaxExpandDays) : to;

  // Overrides, by the occurrence they replace.
  QHash<QString, const CalEvent*> overrides;
  for(const CalEvent& e : stored) {
    if(!e.masterId.isEmpty() && e.originalDate.isValid()) {
      overrides.insert(detail::overrideKey(e.masterId, e.originalDate), &e);
    }
  }

  const auto overlaps = [&](const CalEvent& e, const QDate& startDate) {
    const QDate endDate = (e.endDate.isValid() && e.endDate > startDate) ? e.endDate : startDate;
    return startDate <= last && endDate >= from;
  };

  for(const CalEvent& e : stored) {
    // An override is emitted through its master, so that an occurrence the
    // master no longer has cannot resurrect it.
    if(!e.masterId.isEmpty()) {
      continue;
    }

    const RRule rule = parseRRule(e.rrule);
    if(!rule.isValid()) {
      if(e.date.isValid() && overlaps(e, e.date)) {
        out.append({e, e.date, false});
      }
      continue;
    }
    if(!e.date.isValid()) {
      continue;
    }

    // How long one occurrence runs, so a multi-day event repeats as one.
    const qint64 lengthDays = (e.endDate.isValid() && e.endDate > e.date) ? e.date.daysTo(e.endDate) : 0;

    // Widened at the front by the event's own length: an occurrence that
    // started before the range can still reach into it.
    const QDate searchFrom = from.addDays(-lengthDays);
    for(const QDate& day : expand(rule, e.date, searchFrom, last)) {
      if(e.exdates.contains(day)) {
        continue;
      }
      const auto it = overrides.constFind(detail::overrideKey(e.id, day));
      if(it != overrides.constEnd()) {
        const CalEvent& ov = *it.value();
        if(ov.date.isValid() && overlaps(ov, ov.date)) {
          out.append({ov, day, false});
        }
        continue;
      }
      CalEvent inst = e;
      inst.date = day;
      if(lengthDays > 0) {
        inst.endDate = day.addDays(lengthDays);
      }
      // The instance is not the master: it carries no rule of its own, and it
      // points back at what it came from, so an editor can ask "this one, or
      // all of them?" and a click can find the series again.
      inst.rrule.clear();
      inst.exdates.clear();
      inst.masterId = e.id;
      inst.originalDate = day;
      if(overlaps(inst, day)) {
        out.append({inst, day, true});
      }
    }
  }
  return out;
}

// The stored events an expansion is built from, as plain CalEvents. The views
// want this shape; the two extra facts ride along on the events themselves
// (`masterId` and `originalDate` are set on every generated instance).
inline QVector<CalEvent> expandedEvents(const QVector<CalEvent>& stored, const QDate& from, const QDate& to) {
  QVector<CalEvent> out;
  for(const Occurrence& o : expandEvents(stored, from, to)) {
    out.append(o.event);
  }
  return out;
}

}  // namespace heap::cal
