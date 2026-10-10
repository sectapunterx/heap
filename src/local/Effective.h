#pragma once

#include "Models.h"

// The one place that decides which priority and due date a task plans by
// (ADR 0001, APP-244): mine if I set one, else the tracker's (or, for a local
// task, the only one there is). Planning, sorting, search, reminders, "today"
// and the CLI read these, never Task::priority / Task::dueAt directly.
namespace heap::local {

inline QString effectivePriority(const Task& t) {
  return t.local.myPriority.isEmpty() ? t.priority : t.local.myPriority;
}

inline QDateTime effectiveDueAt(const Task& t) {
  return t.local.myDueAt.isValid() ? t.local.myDueAt : t.dueAt;
}

inline bool effectiveDueHasTime(const Task& t) {
  return t.local.myDueAt.isValid() ? t.local.myDueHasTime : t.dueHasTime;
}

// Where a priority the person picked goes. A local task has only its own
// field. On a tracker card it is mine (APP-238): the tracker's value stays in
// the task's field, and picking the tracker's value again drops my override.
inline void setMyPriority(Task& t, const QString& priority) {
  if(t.externalId.isEmpty()) {
    t.priority = priority;
    t.local.myPriority.clear();
    t.local.myPriorityBase.clear();
  } else if(priority == t.priority) {
    t.local.myPriority.clear();
    t.local.myPriorityBase.clear();
  } else {
    t.local.myPriority = priority;
    t.local.myPriorityBase = t.priority;
  }
}

// The same for a due date. An invalid `at` on a tracker card drops my
// override, so the tracker's date shows again: "no date at all" over a
// tracker's date is not something a pull ever kept either.
inline void setMyDue(Task& t, const QDateTime& at, bool has_time) {
  const bool clock = at.isValid() && has_time;
  if(t.externalId.isEmpty()) {
    t.dueAt = at;
    t.dueHasTime = clock;
    t.local.myDueAt = QDateTime();
    t.local.myDueHasTime = false;
    t.local.myDueBase = QDateTime();
  } else if(!at.isValid() || (at == t.dueAt && clock == t.dueHasTime)) {
    t.local.myDueAt = QDateTime();
    t.local.myDueHasTime = false;
    t.local.myDueBase = QDateTime();
  } else {
    t.local.myDueAt = at;
    t.local.myDueHasTime = clock;
    t.local.myDueBase = t.dueAt;
  }
}

}  // namespace heap::local
