#pragma once

#include "Models.h"

#include "query/TaskQuery.h"
#include "views/SavedView.h"

#include <QDate>
#include <QHash>
#include <QString>
#include <QVariantList>
#include <QVector>

namespace heap::savedviews {

// A saved view's filters compiled once, ready to test tasks against — the
// same predicate the board's TaskFilterProxy and the filter bar's counter
// (AppController::filteredCounts) apply, so the sidebar badge agrees with
// what opening the view shows.
struct CompiledView {
  heap::query::TaskQuery query;
  QString freeText;
  QStringList priorities;
  bool showArchived = false;
  bool archivedOnly = false;  // the Archive view lists archived tasks only
  bool hideDone = false;      // the timeline without Show done
};

CompiledView compile(const SavedView& v, const QDate& today, const QVariantList& statuses);

// `haystack` is the model's prebuilt lowercase search text for the task
// (TaskModel::searchTextAt).
bool accepts(const CompiledView& c, const Task& t, const QString& haystack);

// How many tasks each view shows, keyed by view id. One pass over the tasks
// for all views together.
QHash<QString, int> countMatches(const QVector<SavedView>& views, const TaskModel& tasks, const QDate& today, const QVariantList& statuses);

}  // namespace heap::savedviews
