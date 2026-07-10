#pragma once

#include "Models.h"

#include <QDate>
#include <QString>

// Defer state (HEAP-124). Derived, never stored: the only persisted bit is
// Task::someday, everything else follows from scheduledAt. A parked task is
// someday regardless of the date it once carried.
namespace heap::model {

inline bool isSomeday(const Task& t) {
  return t.someday;
}

inline bool isScheduledForToday(const Task& t, const QDate& today) {
  return !t.someday && t.scheduledAt.isValid() && t.scheduledAt.date() <= today;
}

// "today" | "scheduled" | "anytime" | "someday"
inline QString deferState(const Task& t, const QDate& today) {
  if(t.someday) {
    return QStringLiteral("someday");
  }
  if(!t.scheduledAt.isValid()) {
    return QStringLiteral("anytime");
  }
  return t.scheduledAt.date() <= today ? QStringLiteral("today") : QStringLiteral("scheduled");
}

}  // namespace heap::model
