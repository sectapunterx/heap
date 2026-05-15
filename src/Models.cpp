#include "Models.h"

QHash<int, QByteArray> TaskModel::roleNames() const {
    return {
        { IdRole,       "id" },
        { TitleRole,    "title" },
        { DescRole,     "desc" },
        { PriorityRole, "priority" },
        { StatusRole,   "status" },
        { DeadlineRole, "deadline" },
        { BranchRole,   "branch" },
    };
}

QVariant TaskModel::data(const QModelIndex &idx, int role) const {
    if (!idx.isValid() || idx.row() < 0 || idx.row() >= m_items.size()) return {};
    const Task &t = m_items[idx.row()];
    switch (role) {
        case IdRole:       return t.id;
        case TitleRole:    return t.title;
        case DescRole:     return t.desc;
        case PriorityRole: return t.priority;
        case StatusRole:   return t.status;
        case DeadlineRole: return t.deadline;
        case BranchRole:   return t.branch;
    }
    return {};
}

void TaskModel::reset(QVector<Task> items) {
    beginResetModel();
    m_items = std::move(items);
    endResetModel();
}

int TaskModel::indexOfId(const QString &id) const {
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items[i].id == id) return i;
    return -1;
}

void TaskModel::setStatus(const QString &id, const QString &status) {
    const int row = indexOfId(id);
    if (row < 0 || m_items[row].status == status) return;
    m_items[row].status = status;
    const QModelIndex mi = index(row, 0);
    emit dataChanged(mi, mi, { StatusRole });
}

void TaskModel::upsert(const Task &t) {
    const int row = indexOfId(t.id);
    if (row >= 0) {
        m_items[row] = t;
        const QModelIndex mi = index(row, 0);
        emit dataChanged(mi, mi);
    } else {
        beginInsertRows({}, m_items.size(), m_items.size());
        m_items.push_back(t);
        endInsertRows();
    }
}

void TaskModel::removeById(const QString &id) {
    const int row = indexOfId(id);
    if (row < 0) return;
    beginRemoveRows({}, row, row);
    m_items.removeAt(row);
    endRemoveRows();
}

// ---- EventModel ----

QHash<int, QByteArray> EventModel::roleNames() const {
    return {
        { IdRole,        "id" },
        { TitleRole,     "title" },
        { TypeRole,      "type" },
        { StartRole,     "start" },
        { EndRole,       "end" },
        { AttendeesRole, "attendees" },
        { DateRole,      "date" },
        { TaskIdRole,    "taskId" },
    };
}

QVariant EventModel::data(const QModelIndex &idx, int role) const {
    if (!idx.isValid() || idx.row() < 0 || idx.row() >= m_items.size()) return {};
    const CalEvent &e = m_items[idx.row()];
    switch (role) {
        case IdRole:        return e.id;
        case TitleRole:     return e.title;
        case TypeRole:      return e.type;
        case StartRole:     return e.start;
        case EndRole:       return e.end;
        case AttendeesRole: return e.attendees;
        case DateRole:      return e.date;
        case TaskIdRole:    return e.taskId;
    }
    return {};
}

void EventModel::reset(QVector<CalEvent> items) {
    beginResetModel();
    m_items = std::move(items);
    endResetModel();
}

int EventModel::indexOfId(const QString &id) const {
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items[i].id == id) return i;
    return -1;
}

void EventModel::upsert(const CalEvent &e) {
    const int row = indexOfId(e.id);
    if (row >= 0) {
        m_items[row] = e;
        const QModelIndex mi = index(row, 0);
        emit dataChanged(mi, mi);
    } else {
        beginInsertRows({}, m_items.size(), m_items.size());
        m_items.push_back(e);
        endInsertRows();
    }
}

void EventModel::removeById(const QString &id) {
    const int row = indexOfId(id);
    if (row < 0) return;
    beginRemoveRows({}, row, row);
    m_items.removeAt(row);
    endRemoveRows();
}

void EventModel::detachTask(const QString &taskId) {
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i].taskId == taskId) {
            m_items[i].taskId.clear();
            const QModelIndex mi = index(i, 0);
            emit dataChanged(mi, mi, { TaskIdRole });
        }
    }
}

// ---- PersonModel ----

QHash<int, QByteArray> PersonModel::roleNames() const {
    return {
        { IdRole,       "id" },
        { NameRole,     "name" },
        { RoleRole,     "role" },
        { QuestionRole, "question" },
        { StateRole,    "state" },
        { ColorRole,    "color" },
    };
}

QVariant PersonModel::data(const QModelIndex &idx, int role) const {
    if (!idx.isValid() || idx.row() < 0 || idx.row() >= m_items.size()) return {};
    const Person &p = m_items[idx.row()];
    switch (role) {
        case IdRole:       return p.id;
        case NameRole:     return p.name;
        case RoleRole:     return p.role;
        case QuestionRole: return p.question;
        case StateRole:    return p.state;
        case ColorRole:    return p.color;
    }
    return {};
}

void PersonModel::reset(QVector<Person> items) {
    beginResetModel();
    m_items = std::move(items);
    endResetModel();
}

int PersonModel::indexOfId(const QString &id) const {
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items[i].id == id) return i;
    return -1;
}

void PersonModel::cycleState(const QString &id) {
    const int row = indexOfId(id);
    if (row < 0) return;
    const QString cur = m_items[row].state;
    QString next = "todo";
    if (cur == "todo") next = "pinged";
    else if (cur == "pinged") next = "replied";
    else if (cur == "replied") next = "todo";
    m_items[row].state = next;
    const QModelIndex mi = index(row, 0);
    emit dataChanged(mi, mi, { StateRole });
}

void PersonModel::setState(const QString &id, const QString &state) {
    const int row = indexOfId(id);
    if (row < 0 || m_items[row].state == state) return;
    m_items[row].state = state;
    const QModelIndex mi = index(row, 0);
    emit dataChanged(mi, mi, { StateRole });
}

void PersonModel::upsert(const Person &p) {
    const int row = indexOfId(p.id);
    if (row >= 0) {
        m_items[row] = p;
        const QModelIndex mi = index(row, 0);
        emit dataChanged(mi, mi);
    } else {
        beginInsertRows({}, m_items.size(), m_items.size());
        m_items.push_back(p);
        endInsertRows();
    }
}

void PersonModel::removeById(const QString &id) {
    const int row = indexOfId(id);
    if (row < 0) return;
    beginRemoveRows({}, row, row);
    m_items.removeAt(row);
    endRemoveRows();
}

int PersonModel::todoCount() const {
    int n = 0;
    for (const auto &p : m_items) if (p.state == "todo") ++n;
    return n;
}
