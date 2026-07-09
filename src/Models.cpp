#include "Models.h"
#include "TaskDefer.h"

#include <algorithm>

QString externalKeyOf(const Task& t) {
  if(t.externalId.isEmpty()) {
    return {};
  }
  // Jira hands us the human key already ("PROJ-123"); the issue-number trackers
  // hand us a bare number, which reads as "#123" everywhere they render it.
  bool numeric = false;
  t.externalId.toLongLong(&numeric);
  return numeric ? QStringLiteral("#") + t.externalId : t.externalId;
}

QVariantList labelsToVariant(const QVector<Label>& labels) {
  QVariantList out;
  out.reserve(labels.size());
  for(const Label& l : labels) {
    out.append(QVariantMap{{QStringLiteral("id"), l.id}, {QStringLiteral("color"), l.color}});
  }
  return out;
}

QVector<Label> labelsFromVariant(const QVariantList& list) {
  QVector<Label> out;
  out.reserve(list.size());
  for(const QVariant& v : list) {
    // A plain string is accepted so the editor can hand over comma-separated
    // text without inventing colours for it.
    if(v.typeId() == QMetaType::QString) {
      const QString id = v.toString().trimmed();
      if(!id.isEmpty()) {
        out.append(Label{id, {}});
      }
      continue;
    }
    const QVariantMap m = v.toMap();
    const QString id = m.value(QStringLiteral("id")).toString().trimmed();
    if(!id.isEmpty()) {
      out.append(Label{id, m.value(QStringLiteral("color")).toString()});
    }
  }
  return out;
}

QHash<int, QByteArray> TaskModel::roleNames() const {
  return {
      {IdRole, "id"},
      {TitleRole, "title"},
      {DescRole, "desc"},
      {PriorityRole, "priority"},
      {StatusRole, "status"},
      {DeadlineRole, "deadline"},
      {BranchRole, "branch"},
      {StatusChangedAtRole, "statusChangedAt"},
      {ArchivedRole, "archived"},
      {BlockedStuckRole, "blockedStuck"},
      {PrStateRole, "prState"},
      {PrNumberRole, "prNumber"},
      {PrUrlRole, "prUrl"},
      {GitAheadRole, "gitAhead"},
      {GitBehindRole, "gitBehind"},
      {RecentCommitsRole, "recentCommits"},
      {TrackedSecondsRole, "trackedSeconds"},
      {IsTimingRole, "isTiming"},
      {RecurrenceRole, "recurrence"},
      {ScheduledAtRole, "scheduledAt"},
      {DueAtRole, "dueAt"},
      {HasTimeRole, "hasTime"},
      {EstimateMinutesRole, "estimateMinutes"},
      {SomedayRole, "someday"},
      {DeferStateRole, "deferState"},
      {ExternalProviderRole, "externalProvider"},
      {ExternalUrlRole, "externalUrl"},
      {ExternalKeyRole, "externalKey"},
      {LabelsRole, "labels"},
      {AssigneeRole, "assignee"},
  };
}

QVariant TaskModel::data(const QModelIndex& idx, int role) const {
  if(!idx.isValid() || idx.row() < 0 || idx.row() >= m_items.size()) {
    return {};
  }
  const Task& t = m_items[idx.row()];
  switch(role) {
    case IdRole:
      return t.id;
    case TitleRole:
      return t.title;
    case DescRole:
      return t.desc;
    case PriorityRole:
      return t.priority;
    case StatusRole:
      return t.status;
    case DeadlineRole:
      // Kept a QDate: every calendar/timeline view does whole-day arithmetic on
      // it. The clock component lives on DueAtRole / ScheduledAtRole.
      return t.dueAt.isValid() ? t.dueAt.date() : QDate();
    case BranchRole:
      return t.branch;
    case StatusChangedAtRole:
      return t.statusChangedAt;
    case ArchivedRole:
      return t.archived;
    case BlockedStuckRole:
      return m_blockedStuck.contains(t.id);
    case PrStateRole:
      return m_git.value(t.id).prState;
    case PrNumberRole:
      return m_git.value(t.id).prNumber;
    case PrUrlRole:
      return m_git.value(t.id).prUrl;
    case GitAheadRole:
      return m_git.value(t.id).ahead;
    case GitBehindRole:
      return m_git.value(t.id).behind;
    case RecentCommitsRole:
      return m_git.value(t.id).recentCommits;
    case TrackedSecondsRole:
      return t.trackedSeconds;
    case IsTimingRole:
      return t.timerStartedAt.isValid();
    case RecurrenceRole:
      return t.recurrence;
    case ScheduledAtRole:
      return t.scheduledAt;
    case DueAtRole:
      return t.dueAt;
    case HasTimeRole:
      return t.hasTime;
    case EstimateMinutesRole:
      return t.estimateMinutes;
    case SomedayRole:
      return t.someday;
    case DeferStateRole:
      return heap::model::deferState(t, QDate::currentDate());
    case ExternalProviderRole:
      return t.externalProvider;
    case ExternalUrlRole:
      return t.externalUrl;
    case ExternalKeyRole:
      return externalKeyOf(t);
    case LabelsRole:
      return labelsToVariant(t.labels);
    case AssigneeRole:
      return t.assignee;
  }
  return {};
}

void TaskModel::reset(QVector<Task> items) {
  beginResetModel();
  m_items = std::move(items);
  m_git.clear();
  endResetModel();
}

void TaskModel::setGitInfoForId(const QString& id, const QVariantMap& info) {
  const int row = indexOfId(id);
  if(row < 0) {
    return;
  }
  GitInfo& g = m_git[id];
  if(info.contains(QStringLiteral("prState"))) {
    g.prState = info.value(QStringLiteral("prState")).toString();
  }
  if(info.contains(QStringLiteral("prNumber"))) {
    g.prNumber = info.value(QStringLiteral("prNumber")).toInt();
  }
  if(info.contains(QStringLiteral("prUrl"))) {
    g.prUrl = info.value(QStringLiteral("prUrl")).toString();
  }
  if(info.contains(QStringLiteral("ahead"))) {
    g.ahead = info.value(QStringLiteral("ahead")).toInt();
  }
  if(info.contains(QStringLiteral("behind"))) {
    g.behind = info.value(QStringLiteral("behind")).toInt();
  }
  if(info.contains(QStringLiteral("recentCommits"))) {
    g.recentCommits = info.value(QStringLiteral("recentCommits")).toList();
  }
  const QModelIndex mi = index(row, 0);
  emit dataChanged(mi, mi, {PrStateRole, PrNumberRole, PrUrlRole, GitAheadRole, GitBehindRole, RecentCommitsRole});
}

void TaskModel::clearAllGitInfo() {
  if(m_git.isEmpty() || m_items.isEmpty()) {
    m_git.clear();
    return;
  }
  m_git.clear();
  emit dataChanged(
      index(0, 0), index(m_items.size() - 1, 0), {PrStateRole, PrNumberRole, PrUrlRole, GitAheadRole, GitBehindRole, RecentCommitsRole});
}

int TaskModel::indexOfId(const QString& id) const {
  for(int i = 0; i < m_items.size(); ++i) {
    if(m_items[i].id == id) {
      return i;
    }
  }
  return -1;
}

void TaskModel::setStatus(const QString& id, const QString& status) {
  const int row = indexOfId(id);
  if(row < 0 || m_items[row].status == status) {
    return;
  }
  m_items[row].status = status;
  m_items[row].statusChangedAt = QDateTime::currentDateTime();
  const QModelIndex mi = index(row, 0);
  emit dataChanged(mi, mi, {StatusRole, StatusChangedAtRole});
}

void TaskModel::stampStatusChange(const QString& id) {
  const int row = indexOfId(id);
  if(row < 0) {
    return;
  }
  m_items[row].statusChangedAt = QDateTime::currentDateTime();
  const QModelIndex mi = index(row, 0);
  emit dataChanged(mi, mi, {StatusChangedAtRole});
}

void TaskModel::startTiming(const QString& id) {
  const int row = indexOfId(id);
  if(row < 0 || m_items[row].timerStartedAt.isValid()) {
    return;
  }
  // Only one task tracks at a time — stop any other running timer first.
  for(int i = 0; i < m_items.size(); ++i) {
    if(i != row && m_items[i].timerStartedAt.isValid()) {
      stopTiming(m_items[i].id);
    }
  }
  m_items[row].timerStartedAt = QDateTime::currentDateTime();
  const QModelIndex mi = index(row, 0);
  emit dataChanged(mi, mi, {TrackedSecondsRole, IsTimingRole});
}

void TaskModel::stopTiming(const QString& id) {
  const int row = indexOfId(id);
  if(row < 0 || !m_items[row].timerStartedAt.isValid()) {
    return;
  }
  const qint64 elapsed = m_items[row].timerStartedAt.secsTo(QDateTime::currentDateTime());
  if(elapsed > 0) {
    m_items[row].trackedSeconds += static_cast<int>(elapsed);
  }
  m_items[row].timerStartedAt = QDateTime();  // clear → stopped
  const QModelIndex mi = index(row, 0);
  emit dataChanged(mi, mi, {TrackedSecondsRole, IsTimingRole});
}

void TaskModel::setArchived(const QString& id, bool archived) {
  const int row = indexOfId(id);
  if(row < 0 || m_items[row].archived == archived) {
    return;
  }
  m_items[row].archived = archived;
  const QModelIndex mi = index(row, 0);
  emit dataChanged(mi, mi, {ArchivedRole});
}

void TaskModel::setBlockedStuckIds(const QSet<QString>& ids) {
  if(ids == m_blockedStuck) {
    return;
  }
  QSet<QString> changed = m_blockedStuck;
  changed.unite(ids);
  m_blockedStuck = ids;
  if(m_items.isEmpty()) {
    return;
  }
  int lo = m_items.size();
  int hi = -1;
  for(int i = 0; i < m_items.size(); ++i) {
    if(changed.contains(m_items[i].id)) {
      lo = std::min(i, lo);
      hi = std::max(i, hi);
    }
  }
  if(hi < 0) {
    return;
  }
  emit dataChanged(index(lo, 0), index(hi, 0), {BlockedStuckRole});
}

void TaskModel::upsert(const Task& t) {
  const int row = indexOfId(t.id);
  if(row >= 0) {
    m_items[row] = t;
    const QModelIndex mi = index(row, 0);
    emit dataChanged(mi, mi);
  } else {
    beginInsertRows({}, m_items.size(), m_items.size());
    m_items.push_back(t);
    endInsertRows();
  }
}

void TaskModel::insertAt(int row, const Task& t) {
  row = qBound(0, row, m_items.size());
  beginInsertRows({}, row, row);
  m_items.insert(row, t);
  endInsertRows();
}

void TaskModel::removeById(const QString& id) {
  const int row = indexOfId(id);
  if(row < 0) {
    return;
  }
  beginRemoveRows({}, row, row);
  m_items.removeAt(row);
  endRemoveRows();
}

// ---- EventModel ----

QHash<int, QByteArray> EventModel::roleNames() const {
  return {
      {IdRole, "id"},
      {TitleRole, "title"},
      {TypeRole, "type"},
      {StartRole, "start"},
      {EndRole, "end"},
      {AttendeesRole, "attendees"},
      {DateRole, "date"},
      {TaskIdRole, "taskId"},
      {ProfileIdRole, "profileId"},
      {ContextRole, "context"},
  };
}

QVariant EventModel::data(const QModelIndex& idx, int role) const {
  if(!idx.isValid() || idx.row() < 0 || idx.row() >= m_items.size()) {
    return {};
  }
  const CalEvent& e = m_items[idx.row()];
  switch(role) {
    case IdRole:
      return e.id;
    case TitleRole:
      return e.title;
    case TypeRole:
      return e.type;
    case StartRole:
      return e.start;
    case EndRole:
      return e.end;
    case AttendeesRole:
      return e.attendees;
    case DateRole:
      return e.date;
    case TaskIdRole:
      return e.taskId;
    case ProfileIdRole:
      return e.profileId;
    case ContextRole:
      return e.context;
  }
  return {};
}

void EventModel::reset(QVector<CalEvent> items) {
  beginResetModel();
  m_items = std::move(items);
  endResetModel();
}

int EventModel::indexOfId(const QString& id) const {
  for(int i = 0; i < m_items.size(); ++i) {
    if(m_items[i].id == id) {
      return i;
    }
  }
  return -1;
}

void EventModel::upsert(const CalEvent& e) {
  const int row = indexOfId(e.id);
  if(row >= 0) {
    m_items[row] = e;
    const QModelIndex mi = index(row, 0);
    emit dataChanged(mi, mi);
  } else {
    beginInsertRows({}, m_items.size(), m_items.size());
    m_items.push_back(e);
    endInsertRows();
  }
}

void EventModel::removeById(const QString& id) {
  const int row = indexOfId(id);
  if(row < 0) {
    return;
  }
  beginRemoveRows({}, row, row);
  m_items.removeAt(row);
  endRemoveRows();
}

void EventModel::detachTask(const QString& taskId) {
  for(int i = 0; i < m_items.size(); ++i) {
    if(m_items[i].taskId == taskId) {
      m_items[i].taskId.clear();
      const QModelIndex mi = index(i, 0);
      emit dataChanged(mi, mi, {TaskIdRole});
    }
  }
}

void EventModel::insertAt(int row, const CalEvent& e) {
  row = qBound(0, row, m_items.size());
  beginInsertRows({}, row, row);
  m_items.insert(row, e);
  endInsertRows();
}

void EventModel::setTaskId(const QString& eventId, const QString& taskId) {
  const int row = indexOfId(eventId);
  if(row < 0) {
    return;
  }
  m_items[row].taskId = taskId;
  const QModelIndex mi = index(row, 0);
  emit dataChanged(mi, mi, {TaskIdRole});
}

// ---- PersonModel ----

QHash<int, QByteArray> PersonModel::roleNames() const {
  return {
      {IdRole, "id"},
      {NameRole, "name"},
      {RoleRole, "role"},
      {QuestionRole, "question"},
      {StateRole, "state"},
      {ColorRole, "color"},
  };
}

QVariant PersonModel::data(const QModelIndex& idx, int role) const {
  if(!idx.isValid() || idx.row() < 0 || idx.row() >= m_items.size()) {
    return {};
  }
  const Person& p = m_items[idx.row()];
  switch(role) {
    case IdRole:
      return p.id;
    case NameRole:
      return p.name;
    case RoleRole:
      return p.role;
    case QuestionRole:
      return p.question;
    case StateRole:
      return p.state;
    case ColorRole:
      return p.color;
  }
  return {};
}

void PersonModel::reset(QVector<Person> items) {
  beginResetModel();
  m_items = std::move(items);
  endResetModel();
}

int PersonModel::indexOfId(const QString& id) const {
  for(int i = 0; i < m_items.size(); ++i) {
    if(m_items[i].id == id) {
      return i;
    }
  }
  return -1;
}

void PersonModel::cycleState(const QString& id) {
  const int row = indexOfId(id);
  if(row < 0) {
    return;
  }
  const QString cur = m_items[row].state;
  QString next = "todo";
  if(cur == "todo") {
    next = "pinged";
  } else if(cur == "pinged") {
    next = "replied";
  } else if(cur == "replied") {
    next = "todo";
  }
  m_items[row].state = next;
  const QModelIndex mi = index(row, 0);
  emit dataChanged(mi, mi, {StateRole});
}

void PersonModel::setState(const QString& id, const QString& state) {
  const int row = indexOfId(id);
  if(row < 0 || m_items[row].state == state) {
    return;
  }
  m_items[row].state = state;
  const QModelIndex mi = index(row, 0);
  emit dataChanged(mi, mi, {StateRole});
}

void PersonModel::upsert(const Person& p) {
  const int row = indexOfId(p.id);
  if(row >= 0) {
    m_items[row] = p;
    const QModelIndex mi = index(row, 0);
    emit dataChanged(mi, mi);
  } else {
    beginInsertRows({}, m_items.size(), m_items.size());
    m_items.push_back(p);
    endInsertRows();
  }
}

void PersonModel::insertAt(int row, const Person& p) {
  row = qBound(0, row, m_items.size());
  beginInsertRows({}, row, row);
  m_items.insert(row, p);
  endInsertRows();
}

void PersonModel::removeById(const QString& id) {
  const int row = indexOfId(id);
  if(row < 0) {
    return;
  }
  beginRemoveRows({}, row, row);
  m_items.removeAt(row);
  endRemoveRows();
}

int PersonModel::todoCount() const {
  int n = 0;
  for(const auto& p : m_items) {
    if(p.state == "todo") {
      ++n;
    }
  }
  return n;
}
