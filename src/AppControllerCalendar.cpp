// The calendar lens (APP-264): what the day / week / month zoom reads that
// the views cannot cheaply work out in QML — the load of each day on screen
// (APP-247) and the tray of tasks without a date.
#include "AppController.h"

#include "board/ColumnCategory.h"
#include "cal/Occurrences.h"
#include "local/Effective.h"
#include "plan/DayPlan.h"
#include "query/TaskQuery.h"

#include <algorithm>

QVariantList AppController::dayLoads(const QDate& from, int days) const {
  QVariantList out;
  if(!from.isValid() || days <= 0) {
    return out;
  }
  days = std::min(days, 62);
  const QDate to = from.addDays(days - 1);
  const QDateTime now = QDateTime::currentDateTime();

  // Everything the range touches, read once: the day before too, for a
  // meeting that runs past midnight into the first day.
  QVector<heap::plan::EventIn> events;
  for(const heap::cal::Occurrence& o : heap::cal::expandEvents(m_events.items(), from.addDays(-1), to)) {
    heap::plan::EventIn e;
    e.id = o.event.id;
    e.title = o.event.title;
    e.type = o.event.type;
    e.taskId = o.event.taskId;
    e.date = o.event.date;
    e.endDate = o.event.endDate;
    e.start = o.event.start;
    e.end = o.event.end;
    e.allDay = o.event.allDay;
    events.append(e);
  }
  QVector<heap::plan::TaskIn> timed;
  for(const Task& t : m_tasks.items()) {
    if(t.archived || !t.scheduledHasTime || !t.scheduledAt.isValid()) {
      continue;
    }
    if(t.scheduledAt.date() < from || t.scheduledAt.date() > to) {
      continue;
    }
    heap::plan::TaskIn in;
    in.id = t.id;
    in.title = t.title;
    in.scheduledAt = t.scheduledAt;
    in.minutes = taskBlockMinutes(t.id);
    timed.append(in);
  }
  for(int i = 0; i < days; ++i) {
    const QDate d = from.addDays(i);
    const bool work = isWorkDay(d);
    const heap::plan::Day day = heap::plan::buildDay(d, now, events, timed, m_workdayStart, m_workdayEnd, work);
    out.append(QVariantMap{{QStringLiteral("date"), d},
                           {QStringLiteral("workday"), work},
                           {QStringLiteral("meetings"), day.load.meetings},
                           {QStringLiteral("tasks"), day.load.tasks},
                           {QStringLiteral("free"), day.load.free},
                           {QStringLiteral("overWork"), day.load.overWork},
                           {QStringLiteral("work"), work ? static_cast<int>((m_workdayEnd - m_workdayStart) * 60) : 0}});
  }
  return out;
}

QVariantList AppController::undatedTasks(const QString& search) const {
  // The same rule as the query "is:undated" (no plan, no deadline, not parked
  // for someday), narrowed by the section's query, so the tray, the list and
  // Today count the same tasks.
  const QString text = QStringLiteral("is:undated ") + search;
  const heap::query::TaskQuery q = heap::query::TaskQuery::compile(text, m_today, m_statuses, m_syncNewIds, isStrictQuery_(search));
  QVariantList out;
  for(int row = 0; row < m_tasks.rowCount(); ++row) {
    if(!passesFilter_(row, q, {}, false, true)) {
      continue;
    }
    const Task& t = m_tasks.items().at(row);
    out.append(QVariantMap{{QStringLiteral("id"), t.id},
                           {QStringLiteral("title"), t.title},
                           {QStringLiteral("status"), t.status},
                           {QStringLiteral("category"), statusCategory(t.status)},
                           {QStringLiteral("priority"), heap::local::effectivePriority(t)},
                           {QStringLiteral("blockMinutes"), taskBlockMinutes(t.id)}});
  }
  return out;
}
