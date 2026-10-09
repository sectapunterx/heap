#pragma once

#include <QDate>
#include <QDateTime>
#include <QTime>

// Carrying leftovers on by hand (APP-248): "→ tomorrow" keeps the time a task
// had, and only the plan ("when") moves — the deadline is the person's to
// change. Nothing here runs on its own; the caller is a click.
namespace heap::plan {

struct Planned {
  QDateTime at;
  bool hasTime = false;
};

// The day after `today`, at the same clock time when the plan had one.
inline Planned toTomorrow(const QDateTime& at, bool hasTime, const QDate& today) {
  const QDate d = today.addDays(1);
  if(at.isValid() && hasTime) {
    return {QDateTime(d, QTime(at.time().hour(), at.time().minute())), true};
  }
  return {QDateTime(d, QTime(0, 0)), false};
}

}  // namespace heap::plan
