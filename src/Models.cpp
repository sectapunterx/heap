#include "Models.h"
#include "TaskDefer.h"

#include <QRegularExpression>

#include <algorithm>

QString externalKeyOf(const Task& t) {
  if(t.externalId.isEmpty()) {
    return {};
  }
  // Jira hands us the human key already ("PROJ-123"); the issue-number trackers
  // hand us a bare number, which reads as "#123" everywhere they render it.
  bool numeric = false;
  t.externalId.toLongLong(&numeric);
  if(!numeric) {
    return t.externalId;
  }
  // A number pulled from an "assigned to me" endpoint spans projects, so "#42"
  // alone does not say which issue it is. Qualify it with the repo's own name.
  if(t.externalMeta.crossProject && !t.externalMeta.project.isEmpty()) {
    const QString shortName = t.externalMeta.project.section(QChar('/'), -1);
    return shortName + QStringLiteral("#") + t.externalId;
  }
  return QStringLiteral("#") + t.externalId;
}

QVariantMap ticketToVariant(const Task& t) {
  if(t.externalProvider.isEmpty()) {
    return {};
  }
  return {
      {QStringLiteral("provider"), t.externalProvider},
      {QStringLiteral("key"), externalKeyOf(t)},
      {QStringLiteral("url"), t.externalUrl},
      {QStringLiteral("assignee"), t.assignee},
      {QStringLiteral("author"), t.externalMeta.author},
      {QStringLiteral("issueType"), t.externalMeta.issueType},
      {QStringLiteral("project"), t.externalMeta.project},
      {QStringLiteral("milestone"), t.externalMeta.milestone},
      {QStringLiteral("commentCount"), t.externalMeta.commentCount},
      {QStringLiteral("createdAt"), t.externalMeta.createdAt},
      {QStringLiteral("updatedAt"), t.externalMeta.updatedAt},
  };
}

namespace {

// Markdown task items in a description: "- [ ] thing" and "- [x] thing".
// A template ships checklists, so a card that carries one should be able to
// say how far along it is without the user opening it.
QVariantMap checklistOf(const Task& t) {
  if(!t.desc.contains(QStringLiteral("[ ]")) && !t.desc.contains(QStringLiteral("[x]")) && !t.desc.contains(QStringLiteral("[X]"))) {
    return {};  // the common case: no scan, no allocation
  }
  static const QRegularExpression rx(QStringLiteral(R"(^\s*(?:[-*+]|\d+[.)])\s+\[([ xX])\])"), QRegularExpression::MultilineOption);
  int total = 0;
  int done = 0;
  auto it = rx.globalMatch(t.desc);
  while(it.hasNext()) {
    const auto m = it.next();
    ++total;
    if(m.captured(1) != QStringLiteral(" ")) {
      ++done;
    }
  }
  if(total == 0) {
    return {};
  }
  return {{QStringLiteral("done"), done}, {QStringLiteral("total"), total}};
}

// One lowercase haystack per task, so the five views that filter on a search
// box each read one role instead of concatenating four themselves — and so a
// ticket is findable by its key, its labels and its owner, not just its title.
QString searchTextOf(const Task& t) {
  QStringList parts{t.title, t.id, t.desc, externalKeyOf(t), t.assignee, t.externalMeta.project, t.externalMeta.milestone};
  for(const Label& l : t.labels) {
    parts.append(l.id);
  }
  return parts.join(QChar(' ')).toLower();
}

}  // namespace

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
      {TicketRole, "ticket"},
      {SearchTextRole, "searchText"},
      {RankRole, "rank"},
      {BlocksRole, "blocks"},
      {ChecklistRole, "checklist"},
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
    case TicketRole:
      return ticketToVariant(t);
    case SearchTextRole:
      return searchTextOf(t);
    case RankRole:
      return t.rank;
    case ChecklistRole:
      return checklistOf(t);
    case BlocksRole: {
      QStringList ids;
      for(const TaskLink& l : t.links) {
        if(l.type == QStringLiteral("blocks")) {
          ids << l.targetId;
        }
      }
      return ids;
    }
  }
  return {};
}

void TaskModel::reset(QVector<Task> items) {
  beginResetModel();
  m_items = std::move(items);
  m_git.clear();
  m_indexDirty = true;
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
  // Called on essentially every mutation, and by AppController from ~30 more
  // places — mergeExternalTasks alone walks the model three times per pulled
  // issue. Lazily indexed: any structural change flips the dirty flag and the
  // next lookup rebuilds, which keeps the row-shifting cases (insertAt,
  // removeById) correct without each one maintaining the map by hand.
  if(m_indexDirty) {
    m_index.clear();
    m_index.reserve(m_items.size());
    for(int i = 0; i < m_items.size(); ++i) {
      m_index.insert(m_items[i].id, i);
    }
    m_indexDirty = false;
  }
  return m_index.value(id, -1);
}

void TaskModel::setStatus(const QString& id, const QString& status, const QDateTime& changedAt) {
  const int row = indexOfId(id);
  if(row < 0 || m_items[row].status == status) {
    return;
  }
  m_items[row].status = status;
  m_items[row].statusChangedAt = changedAt.isValid() ? changedAt : QDateTime::currentDateTime();
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
    m_indexDirty = true;
    endInsertRows();
  }
}

void TaskModel::insertAt(int row, const Task& t) {
  row = qBound(0, row, m_items.size());
  beginInsertRows({}, row, row);
  m_items.insert(row, t);
  m_indexDirty = true;  // every row at or after this one shifted
  endInsertRows();
}

void TaskModel::removeById(const QString& id) {
  const int row = indexOfId(id);
  if(row < 0) {
    return;
  }
  beginRemoveRows({}, row, row);
  m_items.removeAt(row);
  m_indexDirty = true;  // every row after this one shifted
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
      {AllDayRole, "allDay"},
      {EndDateRole, "endDate"},
      {RRuleRole, "rrule"},
      {MasterIdRole, "masterId"},
      {OccurrenceDateRole, "occurrenceDate"},
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
    case AllDayRole:
      return e.allDay;
    case EndDateRole:
      // Always a usable date, so a delegate can subtract without a validity
      // check: a single-day event reports its own day.
      return e.endDate.isValid() ? e.endDate : e.date;
    case RRuleRole:
      return e.rrule;
    case MasterIdRole:
      return e.masterId;
    case OccurrenceDateRole:
      // The stored model holds masters and overrides, never expanded
      // occurrences, so this is the event's own date.
      return e.date;
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
