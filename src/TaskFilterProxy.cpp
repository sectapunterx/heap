#include "TaskFilterProxy.h"

#include <QDate>
#include <QDateTime>

TaskFilterProxy::TaskFilterProxy(QObject* parent) : QSortFilterProxyModel(parent) {
  // Board order. The task model is in insertion order, so without this a card
  // dropped between two others would show up wherever it happened to sit in
  // the underlying list. Dynamic so a rank change re-sorts on its own.
  setSortRole(TaskModel::RankRole);
  setDynamicSortFilter(true);
  sort(0, Qt::AscendingOrder);

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

void TaskFilterProxy::setSortMode(const QString& v) {
  const QString mode = v.isEmpty() ? QStringLiteral("manual") : v;
  if(m_sortMode == mode) {
    return;
  }
  m_sortMode = mode;
  invalidate();
  emit sortModeChanged();
}

namespace {

// P0 is the most urgent, so it sorts first. `?? 4` rather than `|| 4`: a
// priority that maps to 0 is P0, and the falsy-zero form would send it to the
// bottom — the same bug that once demoted every P0 in four views.
int priorityRank(const QString& p) {
  static const QHash<QString, int> kRanks = {
      {QStringLiteral("P0"), 0}, {QStringLiteral("P1"), 1}, {QStringLiteral("P2"), 2}, {QStringLiteral("P3"), 3}};
  const auto it = kRanks.constFind(p);
  return it == kRanks.constEnd() ? 4 : *it;
}

}  // namespace

bool TaskFilterProxy::lessThan(const QModelIndex& left, const QModelIndex& right) const {
  const QAbstractItemModel* src = sourceModel();

  if(m_sortMode == QStringLiteral("priority")) {
    const int lp = priorityRank(src->data(left, TaskModel::PriorityRole).toString());
    const int rp = priorityRank(src->data(right, TaskModel::PriorityRole).toString());
    if(lp != rp) {
      return lp < rp;
    }
  } else if(m_sortMode == QStringLiteral("due")) {
    const QDateTime ld = src->data(left, TaskModel::DueAtRole).toDateTime();
    const QDateTime rd = src->data(right, TaskModel::DueAtRole).toDateTime();
    // A task with no due date is not "due at the epoch" — it sorts last,
    // behind everything that actually has a date.
    if(ld.isValid() != rd.isValid()) {
      return ld.isValid();
    }
    if(ld.isValid() && ld != rd) {
      return ld < rd;
    }
  } else if(m_sortMode == QStringLiteral("updated")) {
    const QDateTime lu = src->data(left, TaskModel::StatusChangedAtRole).toDateTime();
    const QDateTime ru = src->data(right, TaskModel::StatusChangedAtRole).toDateTime();
    if(lu != ru) {
      return lu > ru;  // most recently touched first
    }
  } else if(m_sortMode == QStringLiteral("title")) {
    const QString lt = src->data(left, TaskModel::TitleRole).toString();
    const QString rt = src->data(right, TaskModel::TitleRole).toString();
    const int cmp = QString::compare(lt, rt, Qt::CaseInsensitive);
    if(cmp != 0) {
      return cmp < 0;
    }
  }

  // Manual order, and the tie-break for every other mode: two cards that
  // compare equal must not swap places between launches.
  const double lr = src->data(left, TaskModel::RankRole).toDouble();
  const double rr = src->data(right, TaskModel::RankRole).toDouble();
  if(lr != rr) {
    return lr < rr;
  }
  return src->data(left, TaskModel::IdRole).toString() < src->data(right, TaskModel::IdRole).toString();
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
