#pragma once

#include <QDate>
#include <QDateTime>
#include <QString>

// "Waiting on a reply" (APP-158): the user asked someone something a task
// depends on. The link says who and since when, and whether its one gentle
// reminder has gone out. It ends when the person is marked as having replied
// or the user clears it; heap never decides on its own that the wait is over.
//
// Stored per profile under the key `waitingOn` (absent = none), next to
// `statusLog` and for the same reason: it is optional, profile-level data a
// build that does not know it carries through a save in Profile::extra, so no
// schema bump and no field on Task (whose shape is pinned by FieldCount).
struct WaitingOn {
  QString taskId;
  QString personId;
  QDateTime since;
  QDateTime remindedAt;  // invalid = the reminder has not gone out

  bool operator==(const WaitingOn&) const = default;
};

namespace heap::safety {

// Whether the one reminder for `w` is due at `now`: `days` full days have
// passed since the question and it has not been sent. Re-arming a link (asking
// again) gives it a new `since` and clears `remindedAt`.
inline bool waitingReminderDue(const WaitingOn& w, const QDateTime& now, int days) {
  if(!w.since.isValid() || w.remindedAt.isValid() || !now.isValid()) {
    return false;
  }
  return w.since.addDays(qMax(1, days)) <= now;
}

// Calendar days from the question to `today`: asked yesterday evening is "1".
inline int waitingDays(const QDateTime& since, const QDate& today) {
  return since.isValid() ? static_cast<int>(qMax<qint64>(0, since.date().daysTo(today))) : 0;
}

// A person's state moving to "replied" ends every wait on them. Staying there
// (an edit that changes their name) does not count as a new reply.
inline bool replyEndsWaiting(const QString& before, const QString& after) {
  return after == QLatin1String("replied") && before != QLatin1String("replied");
}

}  // namespace heap::safety
