#pragma once

#include "EventClamp.h"
#include "Models.h"

#include <QDateTime>
#include <QVector>

// Which meetings are due to be announced, and when.
//
// This was a block inside runAutomation(), which reads the wall clock. That
// made the rule untestable: a test can only put an event a few minutes out,
// saveEvent() snaps it to the calendar's grid, and whether the snapped slot
// lands before or after "now" depends on what time the test happens to run.
// The window logic is the part worth pinning, so it is pulled out here where
// `now` is an argument.
//
// The once-per-day bookkeeping stays with AppController, which owns the
// sentinel map that survives across ticks.
namespace heap::cal {

struct DueReminder {
  QString eventId;
  QString title;
  // Whole minutes until the event starts. 0 means it is starting now; never
  // negative, because a meeting that already began is not something to be
  // reminded about.
  int minutesLeft = 0;
};

// Events on `now`'s date that start within `leadMinutes` of it.
//
// A focus block is excluded: it is the user's own time, put there on purpose,
// and they are already in it.
inline QVector<DueReminder> dueMeetingReminders(const QVector<CalEvent>& events, const QDateTime& now, int leadMinutes) {
  QVector<DueReminder> out;
  if(!now.isValid()) {
    return out;
  }
  const int lead = qMax(0, leadMinutes);
  const QDate today = now.date();
  for(const CalEvent& e : events) {
    if(e.date != today) {
      continue;
    }
    if(e.type == QStringLiteral("focus")) {
      continue;
    }
    const QDateTime startsAt(e.date, hourToTime(e.start));
    const qint64 minsLeft = now.secsTo(startsAt) / 60;
    if(minsLeft < 0 || minsLeft > lead) {
      continue;
    }
    out.append({e.id, e.title, static_cast<int>(minsLeft)});
  }
  return out;
}

}  // namespace heap::cal
