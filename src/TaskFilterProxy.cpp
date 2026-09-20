#include "TaskFilterProxy.h"

#include <QDate>

TaskFilterProxy::TaskFilterProxy(QObject* parent) : QSortFilterProxyModel(parent) {
  // The header badge and the "nothing here" placeholder both read count().
  connect(this, &QAbstractItemModel::rowsInserted, this, &TaskFilterProxy::countChanged);
  connect(this, &QAbstractItemModel::rowsRemoved, this, &TaskFilterProxy::countChanged);
  connect(this, &QAbstractItemModel::modelReset, this, &TaskFilterProxy::countChanged);
}

void TaskFilterProxy::setStatus(const QString& v) {
  if(m_status == v) {
    return;
  }
  m_status = v;
  invalidateFilter();
  emit filterChanged();
  emit countChanged();
}

void TaskFilterProxy::setShowArchived(bool v) {
  if(m_showArchived == v) {
    return;
  }
  m_showArchived = v;
  invalidateFilter();
  emit filterChanged();
  emit countChanged();
}

void TaskFilterProxy::setSearchText(const QString& v) {
  if(m_rawSearch == v) {
    return;
  }
  m_rawSearch = v;
  // Compiled once per keystroke, not once per row: resolving `deadline:<friday`
  // runs the date parser, which has no business being in a per-row predicate.
  m_query = heap::query::TaskQuery::compile(v, QDate::currentDate());
  m_searchText = m_query.freeText();
  invalidateFilter();
  emit filterChanged();
  emit countChanged();
}

void TaskFilterProxy::setPriorities(const QStringList& v) {
  if(m_priorities == v) {
    return;
  }
  m_priorities = v;
  invalidateFilter();
  emit filterChanged();
  emit countChanged();
}

bool TaskFilterProxy::filterAcceptsRow(int sourceRow, const QModelIndex& sourceParent) const {
  const QAbstractItemModel* src = sourceModel();
  if(src == nullptr) {
    return false;
  }
  const QModelIndex idx = src->index(sourceRow, 0, sourceParent);
  if(!idx.isValid()) {
    return false;
  }

  if(!m_status.isEmpty() && src->data(idx, TaskModel::StatusRole).toString() != m_status) {
    return false;
  }
  if(!m_showArchived && src->data(idx, TaskModel::ArchivedRole).toBool()) {
    return false;
  }
  // An empty priority set means "no filter", not "nothing passes" — the filter
  // bar starts with every chip off.
  if(!m_priorities.isEmpty() && !m_priorities.contains(src->data(idx, TaskModel::PriorityRole).toString())) {
    return false;
  }
  // SearchTextRole is the model's own prebuilt haystack: already lowercased,
  // and covering the ticket key, labels, assignee, project and milestone as
  // well as title/id/description. Concatenating a few fields here instead
  // would quietly narrow what the board can find.
  if(!m_searchText.isEmpty() && !src->data(idx, TaskModel::SearchTextRole).toString().contains(m_searchText)) {
    return false;
  }
  // Structured clauses, if the box held any. The evaluator works on the real
  // Task rather than a role-by-role reconstruction of it, so a clause can ask
  // about fields the model exposes no role for.
  if(m_query.isQuery()) {
    const auto* tasks = qobject_cast<const TaskModel*>(src);
    if(tasks == nullptr || sourceRow >= tasks->items().size() || !m_query.matches(tasks->items().at(sourceRow))) {
      return false;
    }
  }
  return true;
}
