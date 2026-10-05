#include "TaskFilterProxy.h"

#include <QDate>
#include <QDateTime>

#include <utility>

TaskFilterProxy::TaskFilterProxy(QObject* parent) : QSortFilterProxyModel(parent) {
  // Board order. The task model is in insertion order, so without this a card
  // dropped between two others would show up wherever it happened to sit in
  // the underlying list. Dynamic so a rank change re-sorts on its own.
  setSortRole(TaskModel::RankRole);
  setDynamicSortFilter(true);
  sort(0, Qt::AscendingOrder);

  // The header badge and the "nothing here" placeholder both read count().
  // Not while a filter change is being applied: that removes and inserts rows
  // one contiguous range at a time — hundreds of ranges when a keystroke
  // narrows 3k tasks — and every one re-ran each binding on count. The setter
  // announces the new count once when it is done.
  const auto rowsMoved = [this]() {
    if(!m_refiltering) {
      emit countChanged();
    }
  };
  connect(this, &QAbstractItemModel::rowsInserted, this, rowsMoved);
  connect(this, &QAbstractItemModel::rowsRemoved, this, rowsMoved);
  connect(this, &QAbstractItemModel::modelReset, this, rowsMoved);
}

void TaskFilterProxy::refilter() {
  m_refiltering = true;
  invalidateFilter();
  m_refiltering = false;
}

void TaskFilterProxy::setStatus(const QString& v) {
  if(m_status == v) {
    return;
  }
  m_status = v;
  refilter();
  emit filterChanged();
  emit countChanged();
}

void TaskFilterProxy::setShowArchived(bool v) {
  if(m_showArchived == v) {
    return;
  }
  m_showArchived = v;
  refilter();
  emit filterChanged();
  emit countChanged();
}

void TaskFilterProxy::setArchivedOnly(bool v) {
  if(m_archivedOnly == v) {
    return;
  }
  m_archivedOnly = v;
  refilter();
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
  m_query = heap::query::TaskQuery::compile(v, m_today.isValid() ? m_today : QDate::currentDate(), m_statuses);
  m_searchText = m_query.freeText();
  refilter();
  emit filterChanged();
  emit countChanged();
}

void TaskFilterProxy::setToday(const QDate& d) {
  if(m_today == d) {
    return;
  }
  m_today = d;
  // Relative clauses ("deadline:today") mean a different day now.
  m_query = heap::query::TaskQuery::compile(m_rawSearch, m_today.isValid() ? m_today : QDate::currentDate(), m_statuses);
  m_searchText = m_query.freeText();
  refilter();
  emit filterChanged();
  emit countChanged();
}

void TaskFilterProxy::setStatuses(const QVariantList& v) {
  if(m_statuses == v) {
    return;
  }
  m_statuses = v;
  if(m_rawSearch.isEmpty()) {
    emit filterChanged();
    return;
  }
  m_query = heap::query::TaskQuery::compile(m_rawSearch, m_today.isValid() ? m_today : QDate::currentDate(), m_statuses);
  m_searchText = m_query.freeText();
  refilter();
  emit filterChanged();
  emit countChanged();
}

void TaskFilterProxy::setPriorities(const QStringList& v) {
  if(m_priorities == v) {
    return;
  }
  m_priorities = v;
  refilter();
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

int TaskFilterProxy::compareTaskIds(const QString& a, const QString& b) {
  // "APP-9" before "APP-10": the key's text first, then its trailing number
  // as a number. A plain string compare put APP-10 between APP-1 and APP-2.
  const auto split = [](const QString& id) {
    qsizetype i = id.size();
    while(i > 0 && id.at(i - 1).isDigit()) {
      --i;
    }
    return std::pair<QString, QString>(id.left(i), id.mid(i));
  };
  const auto [ap, an] = split(a);
  const auto [bp, bn] = split(b);
  if(const int c = QString::compare(ap, bp, Qt::CaseInsensitive); c != 0) {
    return c;
  }
  if(an.isEmpty() != bn.isEmpty()) {
    return an.isEmpty() ? -1 : 1;
  }
  // Compared as digit strings, leading zeros off, so a forty-digit key
  // cannot overflow.
  const auto digits = [](const QString& n) {
    qsizetype i = 0;
    while(i + 1 < n.size() && n.at(i) == QLatin1Char('0')) {
      ++i;
    }
    return n.mid(i);
  };
  const QString na = digits(an);
  const QString nb = digits(bn);
  if(na.size() != nb.size()) {
    return na.size() < nb.size() ? -1 : 1;
  }
  return QString::compare(na, nb);
}

bool TaskFilterProxy::lessThan(const QModelIndex& left, const QModelIndex& right) const {
  const QAbstractItemModel* src = sourceModel();
  // "priority-desc" is the priority sort turned round (APP-117); every mode
  // but manual can be. The direction flips the mode's own comparison only:
  // the tie-break below stays the manual order, so equal cards keep still.
  const bool desc = m_sortMode.endsWith(QStringLiteral("-desc"));
  const QString mode = desc ? m_sortMode.chopped(5) : m_sortMode;
  int cmp = 0;

  if(mode == QStringLiteral("priority")) {
    cmp = priorityRank(src->data(left, TaskModel::PriorityRole).toString()) -
          priorityRank(src->data(right, TaskModel::PriorityRole).toString());
  } else if(mode == QStringLiteral("due")) {
    const QDateTime ld = src->data(left, TaskModel::DueAtRole).toDateTime();
    const QDateTime rd = src->data(right, TaskModel::DueAtRole).toDateTime();
    // A task with no due date is not "due at the epoch" — it sorts last,
    // behind everything that actually has a date, in either direction.
    if(ld.isValid() != rd.isValid()) {
      return ld.isValid();
    }
    cmp = ld < rd ? -1 : (rd < ld ? 1 : 0);
  } else if(mode == QStringLiteral("updated")) {
    const QDateTime lu = src->data(left, TaskModel::StatusChangedAtRole).toDateTime();
    const QDateTime ru = src->data(right, TaskModel::StatusChangedAtRole).toDateTime();
    cmp = lu > ru ? -1 : (ru > lu ? 1 : 0);  // most recently touched first
  } else if(mode == QStringLiteral("title")) {
    cmp = QString::compare(
        src->data(left, TaskModel::TitleRole).toString(), src->data(right, TaskModel::TitleRole).toString(), Qt::CaseInsensitive);
  } else if(mode == QStringLiteral("id")) {
    cmp = compareTaskIds(src->data(left, TaskModel::IdRole).toString(), src->data(right, TaskModel::IdRole).toString());
  }
  if(cmp != 0) {
    return desc ? cmp > 0 : cmp < 0;
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
  // The board's source is always the TaskModel, and this predicate runs for
  // every row of it in every column on each keystroke. Reading the Task
  // directly skips five QVariant round trips per row; the generic path below
  // stays for any other source model.
  if(const auto* tasks = qobject_cast<const TaskModel*>(src); tasks != nullptr && !sourceParent.isValid()) {
    if(sourceRow < 0 || sourceRow >= tasks->items().size()) {
      return false;
    }
    const Task& t = tasks->items().at(sourceRow);
    if(!m_status.isEmpty() && t.status != m_status) {
      return false;
    }
    if(m_archivedOnly ? !t.archived : (!m_showArchived && t.archived)) {
      return false;
    }
    if(!m_priorities.isEmpty() && !m_priorities.contains(t.priority)) {
      return false;
    }
    // The model's cached haystack (see SearchTextRole), not a concatenation
    // of a few fields here, which would quietly narrow what the board finds.
    if(!m_searchText.isEmpty() && !tasks->searchTextAt(sourceRow).contains(m_searchText)) {
      return false;
    }
    return !m_query.isQuery() || m_query.matches(t);
  }

  const QModelIndex idx = src->index(sourceRow, 0, sourceParent);
  if(!idx.isValid()) {
    return false;
  }

  if(!m_status.isEmpty() && src->data(idx, TaskModel::StatusRole).toString() != m_status) {
    return false;
  }
  const bool archived = src->data(idx, TaskModel::ArchivedRole).toBool();
  if(m_archivedOnly ? !archived : (!m_showArchived && archived)) {
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
  // Structured clauses need the real Task, which only a TaskModel source has.
  return !m_query.isQuery();
}

QStringList TaskFilterProxy::ids() const {
  QStringList out;
  const int n = rowCount();
  out.reserve(n);
  for(int row = 0; row < n; ++row) {
    out.append(data(index(row, 0), TaskModel::IdRole).toString());
  }
  return out;
}
