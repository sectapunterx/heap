#include "local/Effective.h"
#include "views/SavedViewMatch.h"

#include <optional>

namespace heap::savedviews {

CompiledView compile(const SavedView& v, const QDate& today, const QVariantList& statuses) {
  CompiledView c;
  // A stored query is strict: a view on a deleted column counts nothing, as
  // opening it shows (IDIOT-TASKS-11).
  c.query = heap::query::TaskQuery::compile(v.query, today.isValid() ? today : QDate::currentDate(), statuses, {}, true);
  c.freeText = c.query.freeText();
  c.priorities = v.priorities;
  c.archivedOnly = v.view == QLatin1String("archive");
  c.showArchived = v.archived || c.archivedOnly || c.query.asksArchived();
  c.hideDone = v.view == QLatin1String("timeline") && !v.showDone;
  return c;
}

bool accepts(const CompiledView& c, const Task& t, const QString& haystack) {
  if(c.archivedOnly ? !t.archived : (!c.showArchived && t.archived)) {
    return false;
  }
  if(c.hideDone && c.query.isDone(t)) {
    return false;
  }
  if(!c.priorities.isEmpty() && !c.priorities.contains(heap::local::effectivePriority(t))) {
    return false;
  }
  if(!c.freeText.isEmpty() && !haystack.contains(c.freeText)) {
    return false;
  }
  return !c.query.isQuery() || c.query.matches(t, haystack);
}

QHash<QString, int> countMatches(const QVector<SavedView>& views,
                                 const TaskModel& tasks,
                                 const QDate& today,
                                 const QVariantList& statuses) {
  QHash<QString, int> out;
  if(views.isEmpty()) {
    return out;
  }
  QVector<CompiledView> compiled;
  compiled.reserve(views.size());
  std::optional<QSet<QString>> blocked;  // built once, if any view asks
  for(const SavedView& v : views) {
    compiled.append(compile(v, today, statuses));
    if(compiled.last().query.usesBlocked()) {
      if(!blocked) {
        const heap::query::TaskQuery& q = compiled.last().query;
        blocked = heap::query::openlyBlockedIds(tasks.items(), [&q](const Task& t) {
          return q.isDone(t);
        });
      }
      compiled.last().query.setBlockedIds(*blocked);
    }
    out.insert(v.id, 0);
  }
  QVector<int> counts(views.size(), 0);
  const QVector<Task>& items = tasks.items();
  for(int row = 0; row < items.size(); ++row) {
    const Task& t = items.at(row);
    const QString& hay = tasks.searchTextAt(row);
    for(int i = 0; i < compiled.size(); ++i) {
      counts[i] += accepts(compiled.at(i), t, hay) ? 1 : 0;
    }
  }
  for(int i = 0; i < views.size(); ++i) {
    out[views.at(i).id] = counts.at(i);
  }
  return out;
}

}  // namespace heap::savedviews
