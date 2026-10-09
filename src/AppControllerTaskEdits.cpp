// Quick task edits that do not need the editor: priority and labels, on one
// card or on the whole selection (audit TASKS-32 / UX-26). Kept out of
// AppController.cpp, which is long enough; these are ordinary members.

#include "AppController.h"

#include "local/Effective.h"
#include "query/TaskQuery.h"

#include <QRegularExpression>

namespace {

bool validPriority(const QString& p) {
  static const QRegularExpression kPriority(QStringLiteral("^P[0-3]$"));
  return kPriority.match(p).hasMatch();
}

}  // namespace

bool AppController::setPriorityOf(const QString& id, const QString& priority) {
  const int row = m_tasks.indexOfId(id);
  if(row < 0) {
    return false;
  }
  Task t = m_tasks.items().at(row);
  if(heap::local::effectivePriority(t) == priority) {
    return false;
  }
  heap::local::setMyPriority(t, priority);  // a tracker card's is mine (APP-238)
  m_tasks.upsert(t);
  return true;
}

void AppController::setTaskPriority(const QString& taskId, const QString& priority) {
  if(!validPriority(priority)) {
    return;
  }
  const UndoScope scope(this, tr_("task.editUndone").arg(taskId));
  if(setPriorityOf(taskId, priority)) {
    emit undoableToast(tr_("task.moved").arg(taskId, priority), 5);
    scheduleSave();
  }
}

void AppController::setSelectedTasksPriority(const QString& priority) {
  pruneSelectionToFilter_();
  if(!validPriority(priority) || m_selectedTaskIdsList.isEmpty()) {
    return;
  }
  UndoScope scope(this, tr_("undo.bulkEdit").arg(m_selectedTaskIdsList.size()));
  int n = 0;
  for(const QString& id : m_selectedTaskIdsList) {
    n += setPriorityOf(id, priority) ? 1 : 0;
  }
  if(n > 0) {
    scope.setLabel(tr_("undo.bulkEdit").arg(n));
    emit undoableToast(tr_("task.bulkPriority").arg(n).arg(priority), 5);
    scheduleSave();
  }
}

void AppController::setSelectedTasksLabel(const QString& label, bool present) {
  pruneSelectionToFilter_();
  const QString name = label.trimmed().remove(QRegularExpression(QStringLiteral("^#+")));
  if(name.isEmpty() || m_selectedTaskIdsList.isEmpty()) {
    return;
  }
  UndoScope scope(this, tr_("undo.bulkEdit").arg(m_selectedTaskIdsList.size()));
  int n = 0;
  for(const QString& id : m_selectedTaskIdsList) {
    const int row = m_tasks.indexOfId(id);
    if(row < 0) {
      continue;
    }
    Task t = m_tasks.items().at(row);
    int at = -1;
    for(int i = 0; i < t.labels.size(); ++i) {
      if(t.labels.at(i).id.compare(name, Qt::CaseInsensitive) == 0) {
        at = i;
        break;
      }
    }
    if(present && at < 0) {
      // Reuse the colour the label already has elsewhere on the board.
      QString color;
      for(const Task& other : m_tasks.items()) {
        for(const Label& l : other.labels) {
          if(l.id.compare(name, Qt::CaseInsensitive) == 0 && !l.color.isEmpty()) {
            color = l.color;
            break;
          }
        }
        if(!color.isEmpty()) {
          break;
        }
      }
      t.labels.append(Label{name, color});
    } else if(!present && at >= 0) {
      t.labels.removeAt(at);
    } else {
      continue;
    }
    m_tasks.upsert(t);
    ++n;
  }
  if(n > 0) {
    scope.setLabel(tr_("undo.bulkEdit").arg(n));
    emit undoableToast(tr_(present ? "task.bulkLabel" : "task.bulkUnlabel").arg(n).arg(name), 5);
    scheduleSave();
  }
}

bool AppController::passesFilter_(
    int row, const heap::query::TaskQuery& q, const QStringList& priorities, bool showArchived, bool hideDone) const {
  const Task& t = m_tasks.items().at(row);
  if((t.archived && !showArchived) || (hideDone && t.status == QStringLiteral("done"))) {
    return false;
  }
  if(!priorities.isEmpty() && !priorities.contains(heap::local::effectivePriority(t))) {
    return false;
  }
  const QString free = q.freeText();
  if(!free.isEmpty() && !m_tasks.searchTextAt(row).contains(free)) {
    return false;
  }
  return !q.isQuery() || q.matches(t, m_tasks.searchTextAt(row));
}

QVariantMap AppController::filteredCounts(
    const QString& search, const QStringList& priorities, bool showArchived, bool hideDone, const QVariant&) const {
  const heap::query::TaskQuery q = heap::query::TaskQuery::compile(search, m_today, m_statuses, m_syncNewIds);
  int total = 0;
  int active = 0;
  int blocked = 0;
  int review = 0;
  for(int row = 0; row < m_tasks.rowCount(); ++row) {
    if(!passesFilter_(row, q, priorities, showArchived, hideDone)) {
      continue;
    }
    const Task& t = m_tasks.items().at(row);
    ++total;
    active += (t.status == QStringLiteral("prog") || t.status == QStringLiteral("half")) ? 1 : 0;
    blocked += t.status == QStringLiteral("blocked") ? 1 : 0;
    review += t.status == QStringLiteral("review") ? 1 : 0;
  }
  return {{QStringLiteral("total"), total},
          {QStringLiteral("active"), active},
          {QStringLiteral("blocked"), blocked},
          {QStringLiteral("review"), review}};
}

void AppController::setSelectionFilter(const QString& search, const QStringList& priorities, bool showArchived, bool hideDone) {
  m_selectionFilter = {search, priorities, showArchived, hideDone};
  pruneSelectionToFilter_();
}

void AppController::pruneSelectionToFilter_() {
  if(m_selectedTaskIds.isEmpty()) {
    return;
  }
  const SelectionFilter& f = m_selectionFilter;
  const heap::query::TaskQuery q = heap::query::TaskQuery::compile(f.search, m_today, m_statuses, m_syncNewIds);
  QSet<QString> kept;
  for(const QString& id : std::as_const(m_selectedTaskIds)) {
    const int row = m_tasks.indexOfId(id);
    if(row >= 0 && passesFilter_(row, q, f.priorities, f.showArchived, f.hideDone)) {
      kept.insert(id);
    }
  }
  if(kept.size() == m_selectedTaskIds.size()) {
    return;
  }
  m_selectedTaskIds = kept;
  rebuildSelectionList_();
  emit selectedTaskIdsChanged();
}
