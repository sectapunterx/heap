#pragma once

#include "EventClamp.h"
#include "Models.h"

#include <QDateTime>
#include <QSet>
#include <QTime>
#include <QVector>

#include <cmath>

// Which meetings, deadlines and standups are due to be announced, and when.
//
// This was a block inside runAutomation(), which reads the wall clock. That
// made the rule untestable: a test can only put an event a few minutes out,
// saveEvent() snaps it to the calendar's grid, and whether the snapped slot
// lands before or after "now" depends on what time the test happens to run.
// The rules are pulled out here where `now` is an argument.
//
// A reminder is due from the moment it should fire until a little after the
// thing it is about starts, not only inside a one-minute window. That is what
// lets quiet hours delay a reminder instead of swallowing it — the 08:55 call
// for a 09:00 meeting arrives at 09:00 when the quiet window ends then — and
// lets a reminder whose minute fell while the app was busy or asleep still
// arrive. Each one has a key; AppController remembers the keys it has sent
// (on disk, so a restart does not repeat them) and skips those.
namespace heap::cal {

// How long after an occurrence starts its reminder may still be delivered.
inline constexpr int kReminderGraceMinutes = 5;

struct DueReminder {
  // Identifies this reminder for this occurrence at this time: moving the
  // meeting or the next day's occurrence gets a new one.
  QString key;
  QString eventId;
  QString title;
  // Whole minutes until the event starts, rounded up: 0 only once it has
  // started, so "starting now" is never said a minute early.
  int minutesLeft = 0;
};

// The key of a meeting reminder: the event and the instant it starts.
inline QString meetingReminderKey(const QString& eventId, const QDateTime& startsAt) {
  return QStringLiteral("ev:%1@%2").arg(eventId, startsAt.toString(Qt::ISODate));
}

// Occurrences (already expanded, in the viewer's clock) whose reminder is
// due at `now` and not yet in `sent`.
//
// A focus block is excluded: it is the user's own time, put there on purpose,
// and they are already in it. An all-day event is excluded too — it has no
// start to count down to. An event's own lead (CalEvent::reminderMinutes)
// beats `defaultLead`; kReminderOff silences it.
inline QVector<DueReminder> dueMeetingReminders(const QVector<CalEvent>& occurrences,
                                                const QDateTime& now,
                                                int defaultLead,
                                                const QSet<QString>& sent = {}) {
  QVector<DueReminder> out;
  if(!now.isValid()) {
    return out;
  }
  for(const CalEvent& e : occurrences) {
    if(e.allDay || !e.date.isValid() || e.type == QStringLiteral("focus")) {
      continue;
    }
    if(e.reminderMinutes == CalEvent::kReminderOff) {
      continue;
    }
    const int lead = qMax(0, e.reminderMinutes >= 0 ? e.reminderMinutes : defaultLead);
    const QDateTime startsAt(e.date, hourToTime(e.start));
    const QDateTime fireAt = startsAt.addSecs(-60LL * lead);
    if(now < fireAt || now > startsAt.addSecs(60LL * kReminderGraceMinutes)) {
      continue;
    }
    const QString key = meetingReminderKey(e.id, startsAt);
    if(sent.contains(key)) {
      continue;
    }
    const qint64 secs = now.secsTo(startsAt);
    const int minutes = secs <= 0 ? 0 : static_cast<int>((secs + 59) / 60);
    out.append({key, e.id, e.title, minutes});
  }
  return out;
}

// The start of a planned task block (APP-256), opt-in: a task with a time
// ("when") is due to be announced from `lead` minutes before it to a little
// after it starts. The key carries the planned instant, so moving the task
// re-arms it, and a restart or a wake from sleep does not repeat it (the
// sent keys are kept on disk).
struct BlockCall {
  bool due = false;
  int minutesLeft = 0;  // rounded up; 0 once it has started
  QString key;
};

inline QString taskBlockReminderKey(const QString& taskId, const QDateTime& startsAt) {
  return QStringLiteral("blk:%1@%2").arg(taskId, startsAt.toString(Qt::ISODate));
}

inline BlockCall taskBlockReminder(const QString& taskId, const QDateTime& startsAt, const QDateTime& now, int lead) {
  BlockCall out;
  if(!startsAt.isValid() || !now.isValid()) {
    return out;
  }
  const qint64 secs = now.secsTo(startsAt);
  if(secs > 60LL * qMax(0, lead) || -secs > 60LL * kReminderGraceMinutes) {
    return out;
  }
  out.due = true;
  out.minutesLeft = secs <= 0 ? 0 : static_cast<int>((secs + 59) / 60);
  out.key = taskBlockReminderKey(taskId, startsAt);
  return out;
}

// A deadline reminder: whether it is due, and what to say.
struct DeadlineCall {
  bool due = false;
  bool overdue = false;
  // Whole hours left, rounded up (1 = "within the hour"); for an overdue
  // task, whole hours past it, rounded down.
  int hours = 0;
  QString key;
};

// Once when the deadline comes inside `leadHours`, and once more when it has
// passed — the old integer division said "due within the hour" 30 minutes
// after the deadline and nothing at all three hours after it. Keys carry the
// deadline itself, so moving it re-arms both.
inline DeadlineCall deadlineReminder(const QString& taskId, const QDateTime& deadlineAt, const QDateTime& now, int leadHours) {
  DeadlineCall out;
  if(!deadlineAt.isValid() || !now.isValid()) {
    return out;
  }
  const qint64 secs = now.secsTo(deadlineAt);
  // Every task is asked every minute; most are nowhere near due, so the key
  // is only formatted for the ones that are (APP-203).
  if(secs < 0) {
    // Only a deadline that passed recently: a profile full of month-old
    // overdue work must not answer an update with a flood of reminders.
    if(-secs > 24LL * 3600) {
      return out;
    }
    out.due = true;
    out.overdue = true;
    out.hours = static_cast<int>(-secs / 3600);
    out.key = QStringLiteral("dl-over:%1@%2").arg(taskId, deadlineAt.toString(Qt::ISODate));
    return out;
  }
  if(secs > 3600LL * qMax(1, leadHours)) {
    return out;
  }
  out.due = true;
  out.hours = qMax(1, static_cast<int>((secs + 3599) / 3600));
  out.key = QStringLiteral("dl:%1@%2").arg(taskId, deadlineAt.toString(Qt::ISODate));
  return out;
}

// The quiet window [from, to) as it applies to `when`: true inside it. A
// window that wraps midnight (19:00–09:00) is the usual case.
inline bool inQuietWindow(const QTime& from, const QTime& to, const QTime& when) {
  if(!from.isValid() || !to.isValid() || from == to) {
    return false;
  }
  if(from < to) {
    return when >= from && when < to;
  }
  return when >= from || when < to;
}

// A settings time of day: "HH:mm" or "H:mm", surrounding blanks ignored.
// Anything else (25:00, abc, empty) is invalid. A strict "HH:mm" parse made a
// standup stored as "9:30" invalid, and the reminder stopped without a word
// (SHELL-9, audit 2026-09-30).
inline QTime clockTime(const QString& text) {
  const QString t = text.trimmed();
  QTime out = QTime::fromString(t, QStringLiteral("HH:mm"));
  if(!out.isValid()) {
    out = QTime::fromString(t, QStringLiteral("H:mm"));
  }
  return out;
}

}  // namespace heap::cal
