#pragma once

#include "Models.h"

#include <QDate>
#include <QString>
#include <QVector>

// Jira sprints as the board's cards carry them (APP-255): read-only facts the
// last pull left in ExternalMeta::details.sprint. Only shown — heap writes
// nothing to a sprint and counts no velocity. Pure functions of the tasks.
namespace heap::integrations {

struct SprintMarker {
  QString name;
  QString state;  // "active" | "future"
  QDate start;    // local dates; invalid when Jira gave none
  QDate end;
  int tasks = 0;  // unarchived cards in it
};

// The sprint a card is in, or an empty marker (no name) when none.
SprintMarker sprintOf(const Task& t);

// The distinct sprints of `tasks` (unarchived ones) whose end falls in
// [from, to], by end date then name. One sprint = one name and end date.
QVector<SprintMarker> sprintMarkers(const QVector<Task>& tasks, const QDate& from, const QDate& to);

// The active sprint of `tasks` that ends first on or after `today`, or an
// empty marker when no card is in an active one.
SprintMarker currentSprint(const QVector<Task>& tasks, const QDate& today);

}  // namespace heap::integrations
