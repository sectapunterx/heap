#pragma once

#include <QDate>
#include <QString>
#include <QVector>

// The groups of the Tasks → List lens (APP-263). A pure function of the tasks
// the query let through and of `today`, so the rules can be tested without a
// clock or a window.
//
// By date (the default) a task goes by its "when" (scheduledAt), else by its
// deadline:
//   overdue   — a date before today on an open task; only when there is one
//   today, tomorrow
//   week      — the rest of this week, up to Sunday
//   nextWeek  — Monday … Sunday of the next one
//   later     — after that
//   past      — a date before today on a finished task (never "overdue")
//   none      — no date at all
// By status the groups follow the board's column order; by priority P0 … P3
// and then "no priority"; by profile the active profile first, then the rest
// in their order. Empty groups are never returned.
namespace heap::tasklist {

struct Item {
  QString id;
  QDate when;  // invalid = none
  QDate due;   // invalid = none
  bool done = false;
  int statusIndex = 0;  // the column's place on the board
  QString status;
  QString priority;      // "P0" … "P3" or empty
  int profileIndex = 0;  // 0 = the active profile
  QString profile;
};

struct Group {
  QString key;    // see above; "status" / "priority" / "profile" for the others
  QString value;  // the status id, the priority ("" = none), the profile name
  QDate from;     // the dates a date group spans (invalid when it has none)
  QDate to;
  QVector<int> members;  // indices into the items, in display order
};

// The date a task is grouped and sorted by: when, else the deadline.
QDate groupDate(const Item& t);

// The date group of one task.
QString dateGroupOf(const Item& t, const QDate& today);

// by: "date" | "status" | "priority" | "profile"; anything else is "date".
QVector<Group> group(const QVector<Item>& items, const QString& by, const QDate& today);

}  // namespace heap::tasklist
