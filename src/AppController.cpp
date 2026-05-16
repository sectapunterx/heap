#include "AppController.h"
#include "SampleData.h"

#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QStandardPaths>
#include <QUuid>

AppController::AppController(QObject *parent)
    : QObject(parent)
{
    m_today = QDate::currentDate();
    m_selectedDate = m_today;

    m_statuses.reserve(7);
    for (const auto &m : SampleData::statuses()) m_statuses.push_back(m);

    m_tasks.reset(SampleData::tasks());
    m_events.reset(SampleData::events(m_today));
    m_people.reset(SampleData::people());

    m_saveTimer = new QTimer(this);
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(300);
    connect(m_saveTimer, &QTimer::timeout, this, &AppController::saveStateNow);

    m_undoTimer = new QTimer(this);
    m_undoTimer->setSingleShot(true);
    connect(m_undoTimer, &QTimer::timeout, this, &AppController::clearPendingUndo);

    loadStateOnStart();
}

AppController::~AppController() {
    flushSave();
}

void AppController::flushSave() {
    if (m_saveTimer && m_saveTimer->isActive()) {
        m_saveTimer->stop();
        saveStateNow();
    }
}

void AppController::setSelectedDate(const QDate &d) {
    if (d == m_selectedDate) return;
    m_selectedDate = d;
    emit selectedDateChanged();
}

void AppController::setTheme(const QString &t) {
    if (t == m_theme) return;
    m_theme = t;
    emit themeChanged();
    scheduleSave();
}

void AppController::setDensity(const QString &d) {
    if (d == m_density) return;
    m_density = d;
    emit densityChanged();
    scheduleSave();
}

void AppController::setCurrentView(const QString &v) {
    if (v == m_currentView) return;
    m_currentView = v;
    emit currentViewChanged();
    scheduleSave();
}

void AppController::setWorkdayStart(int v) {
    v = qBound(0, v, 23);
    if (v >= m_workdayEnd) v = m_workdayEnd - 1;
    if (v == m_workdayStart) return;
    m_workdayStart = v;
    emit workdayChanged();
    scheduleSave();
}

void AppController::setWorkdayEnd(int v) {
    v = qBound(1, v, 24);
    if (v <= m_workdayStart) v = m_workdayStart + 1;
    if (v == m_workdayEnd) return;
    m_workdayEnd = v;
    emit workdayChanged();
    scheduleSave();
}

void AppController::setCrumbProject(const QString &v) {
    if (v == m_crumbProject) return;
    m_crumbProject = v;
    emit crumbProjectChanged();
    scheduleSave();
}

void AppController::setCrumbUser(const QString &v) {
    if (v == m_crumbUser) return;
    m_crumbUser = v;
    emit crumbUserChanged();
    scheduleSave();
}

void AppController::setDocsState(const QString &v) {
    if (v == m_docsState) return;
    m_docsState = v;
    emit docsStateChanged();
    scheduleSave();
}

void AppController::moveTask(const QString &id, const QString &newStatus) {
    const int row = m_tasks.indexOfId(id);
    if (row < 0) return;
    const Task &t = m_tasks.items().at(row);
    if (t.status == newStatus) return;
    QString statusName = newStatus;
    for (const auto &v : m_statuses) {
        const QVariantMap m = v.toMap();
        if (m.value("id").toString() == newStatus) {
            statusName = m.value("name").toString();
            break;
        }
    }
    const QString taskId = t.id;
    m_tasks.setStatus(id, newStatus);
    emit toast(QString("%1 → %2").arg(taskId, statusName));
    scheduleSave();
}

QVariantMap AppController::newTaskDraft(const QString &statusId) const {
    const int nextNum = 2700 + m_tasks.rowCount();
    QVariantMap m;
    m["_isNew"] = true;
    m["id"] = QString("LTE-%1").arg(nextNum);
    m["title"] = QString();
    m["desc"] = QString();
    m["priority"] = "P2";
    m["status"] = statusId.isEmpty() ? QString("todo") : statusId;
    m["deadline"] = QDate();
    m["branch"] = QString();
    return m;
}

void AppController::saveTask(const QVariantMap &draft) {
    Task t;
    t.id       = draft.value("id").toString();
    t.title    = draft.value("title").toString();
    t.desc     = draft.value("desc").toString();
    t.priority = draft.value("priority").toString();
    t.status   = draft.value("status").toString();
    t.deadline = draft.value("deadline").toDate();
    t.branch   = draft.value("branch").toString();
    const bool isNew = draft.value("_isNew").toBool();
    if (isNew && t.title.trimmed().isEmpty()) return;
    m_tasks.upsert(t);
    if (isNew) emit toast(QString("Создано: %1").arg(t.id));
    scheduleSave();
}

void AppController::deleteTask(const QString &id) {
    const int row = m_tasks.indexOfId(id);
    if (row < 0) return;
    cancelUndo();
    m_pendingUndo = {};
    m_pendingUndo.kind = PendingUndo::Task;
    m_pendingUndo.task = m_tasks.items().at(row);
    m_pendingUndo.row  = row;
    for (const auto &e : m_events.items()) {
        if (e.taskId == id) m_pendingUndo.detachedEventIds.append({ e.id, e.taskId });
    }
    m_events.detachTask(id);
    m_tasks.removeById(id);
    armUndo(5);
    emit undoableToast(QString("Удалена: %1").arg(id), 5);
    scheduleSave();
}

QVariantMap AppController::newEventDraft(double startHour, const QDate &date) const {
    QVariantMap m;
    m["id"] = QString("ev-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    m["title"] = QString("Новое событие");
    m["type"] = "sync";
    m["start"] = startHour;
    m["end"] = startHour + 1.0;
    m["attendees"] = QString();
    m["date"] = date.isValid() ? date : m_selectedDate;
    m["taskId"] = QString();
    m["_isNew"] = true;
    return m;
}

void AppController::saveEvent(const QVariantMap &draft) {
    CalEvent e;
    e.id        = draft.value("id").toString();
    e.title     = draft.value("title").toString();
    e.type      = draft.value("type").toString();
    e.start     = draft.value("start").toDouble();
    e.end       = draft.value("end").toDouble();
    e.attendees = draft.value("attendees").toString();
    e.date      = draft.value("date").toDate();
    e.taskId    = draft.value("taskId").toString();
    if (e.end <= e.start) e.end = e.start + 0.25;
    m_events.upsert(e);
    scheduleSave();
}

void AppController::deleteEvent(const QString &id) {
    const int row = m_events.indexOfId(id);
    if (row < 0) return;
    cancelUndo();
    m_pendingUndo = {};
    m_pendingUndo.kind  = PendingUndo::Event;
    m_pendingUndo.event = m_events.items().at(row);
    m_pendingUndo.row   = row;
    m_events.removeById(id);
    armUndo(5);
    emit undoableToast(QString("Удалено событие: %1").arg(m_pendingUndo.event.title), 5);
    scheduleSave();
}

void AppController::scheduleTask(const QString &taskId, double startHour, const QDate &date) {
    const int row = m_tasks.indexOfId(taskId);
    if (row < 0) return;
    const Task &t = m_tasks.items().at(row);
    CalEvent e;
    e.id = QString("ev-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    e.title = QString("Focus · %1").arg(t.title.left(36));
    e.type = "focus";
    e.start = startHour;
    e.end = startHour + 1.0;
    e.attendees = "🔒 deep work";
    e.date = date;
    e.taskId = t.id;
    m_events.upsert(e);
    emit toast(QString("%1 запланировано на %2").arg(t.id, eventHourLabel(startHour)));
    scheduleSave();
}

void AppController::cyclePerson(const QString &id) {
    m_people.cycleState(id);
    scheduleSave();
}

void AppController::setPersonState(const QString &id, const QString &state) {
    m_people.setState(id, state);
    scheduleSave();
}

QVariantMap AppController::newPersonDraft() const {
    static const QColor palette[] = {
        QColor("#d97a6c"), QColor("#c87fc7"), QColor("#6cc4b8"),
        QColor("#7da8d9"), QColor("#dcc06a"), QColor("#7cc492"),
        QColor("#e69854"), QColor("#a4a4d6"),
    };
    const int n = static_cast<int>(sizeof(palette) / sizeof(palette[0]));
    const QColor c = palette[m_people.rowCount() % n];
    QVariantMap m;
    m["_isNew"] = true;
    m["id"]       = QString("p-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    m["name"]     = QString();
    m["role"]     = QString();
    m["question"] = QString();
    m["state"]    = "todo";
    m["color"]    = c;
    return m;
}

QVariantMap AppController::personById(const QString &id) const {
    const int row = m_people.indexOfId(id);
    if (row < 0) return {};
    const QModelIndex mi = m_people.index(row, 0);
    QVariantMap m;
    m["_isNew"]   = false;
    m["id"]       = m_people.data(mi, PersonModel::IdRole);
    m["name"]     = m_people.data(mi, PersonModel::NameRole);
    m["role"]     = m_people.data(mi, PersonModel::RoleRole);
    m["question"] = m_people.data(mi, PersonModel::QuestionRole);
    m["state"]    = m_people.data(mi, PersonModel::StateRole);
    m["color"]    = m_people.data(mi, PersonModel::ColorRole);
    return m;
}

void AppController::savePerson(const QVariantMap &draft) {
    Person p;
    p.id       = draft.value("id").toString();
    p.name     = draft.value("name").toString();
    p.role     = draft.value("role").toString();
    p.question = draft.value("question").toString();
    p.state    = draft.value("state").toString();
    p.color    = draft.value("color").value<QColor>();
    if (!p.color.isValid()) p.color = QColor("#7da8d9");
    if (p.state.isEmpty()) p.state = "todo";
    if (p.id.isEmpty()) p.id = QString("p-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    const bool isNew = draft.value("_isNew").toBool();
    if (isNew && p.name.trimmed().isEmpty()) return;
    m_people.upsert(p);
    if (isNew) emit toast(QString("Добавлен: %1").arg(p.name));
    scheduleSave();
}

void AppController::deletePerson(const QString &id) {
    const int row = m_people.indexOfId(id);
    if (row < 0) return;
    cancelUndo();
    m_pendingUndo = {};
    m_pendingUndo.kind   = PendingUndo::Person;
    m_pendingUndo.person = m_people.items().at(row);
    m_pendingUndo.row    = row;
    m_people.removeById(id);
    armUndo(5);
    emit undoableToast(QString("Удалён: %1").arg(m_pendingUndo.person.name), 5);
    scheduleSave();
}

int AppController::countByStatus(const QString &statusId) const {
    int n = 0;
    for (const auto &t : m_tasks.items()) if (t.status == statusId) ++n;
    return n;
}

int AppController::statusIndexOf(const QString &id) const {
    for (int i = 0; i < m_statuses.size(); ++i)
        if (m_statuses[i].toMap().value("id").toString() == id) return i;
    return -1;
}

void AppController::addStatus(const QString &name, const QString &color) {
    if (name.trimmed().isEmpty()) return;
    QString base = name.toLower();
    QString slug;
    for (QChar c : base) slug.append(c.isLetterOrNumber() ? c : QChar('-'));
    while (slug.contains("--")) slug.replace("--", "-");
    if (slug.startsWith('-')) slug = slug.mid(1);
    while (slug.endsWith('-')) slug.chop(1);
    if (slug.isEmpty()) slug = "status";
    QString id = slug;
    int n = 2;
    while (statusIndexOf(id) >= 0) { id = slug + "-" + QString::number(n++); }
    QVariantMap m;
    m["id"]    = id;
    m["name"]  = name;
    m["color"] = QColor(color.isEmpty() ? QStringLiteral("#5cc2dd") : color);
    m_statuses.append(m);
    emit statusesChanged();
    emit toast(QString("Колонка добавлена: %1").arg(name));
    scheduleSave();
}

void AppController::renameStatus(const QString &id, const QString &name) {
    const int i = statusIndexOf(id);
    if (i < 0 || name.trimmed().isEmpty()) return;
    QVariantMap m = m_statuses[i].toMap();
    if (m.value("name").toString() == name) return;
    m["name"] = name;
    m_statuses[i] = m;
    emit statusesChanged();
    scheduleSave();
}

void AppController::setStatusColor(const QString &id, const QString &color) {
    const int i = statusIndexOf(id);
    if (i < 0) return;
    const QColor c(color);
    if (!c.isValid()) return;
    QVariantMap m = m_statuses[i].toMap();
    m["color"] = c;
    m_statuses[i] = m;
    emit statusesChanged();
    scheduleSave();
}

void AppController::moveStatus(const QString &id, int newIndex) {
    const int from = statusIndexOf(id);
    if (from < 0) return;
    newIndex = qBound(0, newIndex, m_statuses.size() - 1);
    if (from == newIndex) return;
    QVariant v = m_statuses.takeAt(from);
    m_statuses.insert(newIndex, v);
    emit statusesChanged();
    scheduleSave();
}

void AppController::deleteStatus(const QString &id) {
    const int i = statusIndexOf(id);
    if (i < 0 || m_statuses.size() <= 1) return; // never let the board run out of columns
    cancelUndo();
    m_pendingUndo = {};
    m_pendingUndo.kind   = PendingUndo::Status;
    m_pendingUndo.status = m_statuses[i].toMap();
    m_pendingUndo.row    = i;

    // re-home any tasks with this status to the first remaining one
    QString fallback;
    for (int k = 0; k < m_statuses.size(); ++k) {
        if (k == i) continue;
        fallback = m_statuses[k].toMap().value("id").toString();
        break;
    }
    for (const auto &t : m_tasks.items()) {
        if (t.status == id) {
            m_pendingUndo.reHomedTasks.append({ t.id, id });
        }
    }
    for (const auto &pair : m_pendingUndo.reHomedTasks) {
        m_tasks.setStatus(pair.first, fallback);
    }

    const QString name = m_pendingUndo.status.value("name").toString();
    m_statuses.removeAt(i);
    emit statusesChanged();
    armUndo(5);
    emit undoableToast(QString("Удалена колонка: %1").arg(name), 5);
    scheduleSave();
}

QVariantMap AppController::taskById(const QString &id) const {
    const int row = m_tasks.indexOfId(id);
    if (row < 0) return {};
    const Task &t = m_tasks.items().at(row);
    QVariantMap m;
    m["id"] = t.id; m["title"] = t.title; m["desc"] = t.desc;
    m["priority"] = t.priority; m["status"] = t.status;
    m["deadline"] = t.deadline; m["branch"] = t.branch;
    return m;
}

QString AppController::eventHourLabel(double hour) const {
    const int hh = int(hour);
    const int mm = int((hour - hh) * 60 + 0.5);
    return QString("%1:%2")
        .arg(hh, 2, 10, QLatin1Char('0'))
        .arg(mm, 2, 10, QLatin1Char('0'));
}

QString AppController::sprintLabel() const {
    const int n = int((m_today.month()) * 2.1);
    return QString("sprint-%1").arg(n);
}

QString AppController::humanDate(const QDate &date) const {
    if (!date.isValid()) return {};
    QLocale ru(QLocale::Russian, QLocale::Russia);
    return ru.toString(date, "dddd, d MMMM");
}

QString AppController::deadlineBucket(const QDate &deadline) const {
    if (!deadline.isValid()) return "nodl";
    const int d = m_today.daysTo(deadline);
    if (d < 0)  return "overdue";
    if (d == 0) return "today";
    if (d == 1) return "tomorrow";
    if (d <= 6)  return "thisweek";
    if (d <= 13) return "nextweek";
    return "later";
}

QString AppController::deadlineDiffLabel(const QDate &deadline) const {
    if (!deadline.isValid()) return QStringLiteral("—");
    const int d = m_today.daysTo(deadline);
    if (d < 0)  return QString("%1d overdue").arg(-d);
    if (d == 0) return QStringLiteral("today");
    if (d == 1) return QStringLiteral("+1 day");
    if (d < 7)  return QString("+%1 days").arg(d);
    return QString("+%1d").arg(d);
}

QString AppController::shortDate(const QDate &d) const {
    if (!d.isValid()) return {};
    QLocale ru(QLocale::Russian, QLocale::Russia);
    return ru.toString(d, "ddd, d MMM");
}

int AppController::isoWeekNumber(const QDate &d) const {
    if (!d.isValid()) return 0;
    return d.weekNumber();
}

void AppController::copyToClipboard(const QString &text) {
    if (auto *cb = QGuiApplication::clipboard()) cb->setText(text);
}

// ───────────────────────────────────────────────────────── Undo ──

void AppController::armUndo(int seconds) {
    m_undoTimer->start(seconds * 1000);
    emit pendingUndoChanged();
}

void AppController::cancelUndo() {
    if (m_undoTimer) m_undoTimer->stop();
    if (m_pendingUndo.kind != PendingUndo::None) {
        m_pendingUndo = {};
        emit pendingUndoChanged();
    }
}

void AppController::clearPendingUndo() {
    cancelUndo();
}

void AppController::undoLastDeletion() {
    if (m_pendingUndo.kind == PendingUndo::None) return;
    switch (m_pendingUndo.kind) {
        case PendingUndo::Task: {
            m_tasks.insertAt(m_pendingUndo.row, m_pendingUndo.task);
            for (const auto &pair : m_pendingUndo.detachedEventIds)
                m_events.setTaskId(pair.first, pair.second);
            emit toast(QString("Восстановлена: %1").arg(m_pendingUndo.task.id));
            break;
        }
        case PendingUndo::Event: {
            m_events.insertAt(m_pendingUndo.row, m_pendingUndo.event);
            emit toast(QString("Восстановлено: %1").arg(m_pendingUndo.event.title));
            break;
        }
        case PendingUndo::Person: {
            m_people.insertAt(m_pendingUndo.row, m_pendingUndo.person);
            emit toast(QString("Восстановлён: %1").arg(m_pendingUndo.person.name));
            break;
        }
        case PendingUndo::Status: {
            const int idx = qBound(0, m_pendingUndo.row, m_statuses.size());
            m_statuses.insert(idx, m_pendingUndo.status);
            for (const auto &pair : m_pendingUndo.reHomedTasks)
                m_tasks.setStatus(pair.first, pair.second);
            emit statusesChanged();
            emit toast(QString("Восстановлена колонка: %1")
                       .arg(m_pendingUndo.status.value("name").toString()));
            break;
        }
        default: break;
    }
    m_pendingUndo = {};
    if (m_undoTimer) m_undoTimer->stop();
    emit pendingUndoChanged();
    scheduleSave();
}

// ─────────────────────────────────────────────────── Persistence ──

QString AppController::stateFilePath() const {
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return dir + "/state.json";
}

void AppController::scheduleSave() {
    if (m_loading || !m_saveTimer) return;
    m_saveTimer->start();
}

void AppController::saveStateNow() {
    QJsonObject root;

    QJsonArray tasksArr;
    for (const Task &t : m_tasks.items()) {
        QJsonObject o;
        o["id"]       = t.id;
        o["title"]    = t.title;
        o["desc"]     = t.desc;
        o["priority"] = t.priority;
        o["status"]   = t.status;
        o["deadline"] = t.deadline.isValid() ? t.deadline.toString(Qt::ISODate) : QString();
        o["branch"]   = t.branch;
        tasksArr.append(o);
    }
    root["tasks"] = tasksArr;

    QJsonArray eventsArr;
    for (const CalEvent &e : m_events.items()) {
        QJsonObject o;
        o["id"]        = e.id;
        o["title"]     = e.title;
        o["type"]      = e.type;
        o["start"]     = e.start;
        o["end"]       = e.end;
        o["attendees"] = e.attendees;
        o["date"]      = e.date.isValid() ? e.date.toString(Qt::ISODate) : QString();
        o["taskId"]    = e.taskId;
        eventsArr.append(o);
    }
    root["events"] = eventsArr;

    QJsonArray peopleArr;
    for (const Person &p : m_people.items()) {
        QJsonObject o;
        o["id"]       = p.id;
        o["name"]     = p.name;
        o["role"]     = p.role;
        o["question"] = p.question;
        o["state"]    = p.state;
        o["color"]    = p.color.name();
        peopleArr.append(o);
    }
    root["people"] = peopleArr;

    QJsonArray statusesArr;
    for (const QVariant &v : m_statuses) {
        const QVariantMap m = v.toMap();
        QJsonObject o;
        o["id"]    = m.value("id").toString();
        o["name"]  = m.value("name").toString();
        const QVariant col = m.value("color");
        o["color"] = col.canConvert<QColor>() ? col.value<QColor>().name()
                                              : col.toString();
        statusesArr.append(o);
    }
    root["statuses"] = statusesArr;

    QJsonObject s;
    s["theme"]        = m_theme;
    s["density"]      = m_density;
    s["currentView"]  = m_currentView;
    s["workdayStart"] = m_workdayStart;
    s["workdayEnd"]   = m_workdayEnd;
    s["crumbProject"] = m_crumbProject;
    s["crumbUser"]    = m_crumbUser;
    root["settings"] = s;

    if (!m_docsState.isEmpty()) {
        const QJsonDocument d = QJsonDocument::fromJson(m_docsState.toUtf8());
        if (!d.isNull() && d.isObject()) root["docs"] = d.object();
    }

    QFile f(stateFilePath());
    if (f.open(QFile::WriteOnly | QFile::Truncate)) {
        f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    }
}

void AppController::loadStateOnStart() {
    QFile f(stateFilePath());
    if (!f.exists() || !f.open(QFile::ReadOnly)) return;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (doc.isNull() || !doc.isObject()) return;
    const QJsonObject root = doc.object();

    m_loading = true;

    if (root.contains("tasks")) {
        QVector<Task> v;
        for (const auto &it : root["tasks"].toArray()) {
            const QJsonObject o = it.toObject();
            Task t;
            t.id       = o["id"].toString();
            t.title    = o["title"].toString();
            t.desc     = o["desc"].toString();
            t.priority = o["priority"].toString();
            t.status   = o["status"].toString();
            t.deadline = QDate::fromString(o["deadline"].toString(), Qt::ISODate);
            t.branch   = o["branch"].toString();
            v.append(t);
        }
        m_tasks.reset(v);
    }

    if (root.contains("events")) {
        QVector<CalEvent> v;
        for (const auto &it : root["events"].toArray()) {
            const QJsonObject o = it.toObject();
            CalEvent e;
            e.id        = o["id"].toString();
            e.title     = o["title"].toString();
            e.type      = o["type"].toString();
            e.start     = o["start"].toDouble();
            e.end       = o["end"].toDouble();
            e.attendees = o["attendees"].toString();
            e.date      = QDate::fromString(o["date"].toString(), Qt::ISODate);
            e.taskId    = o["taskId"].toString();
            v.append(e);
        }
        m_events.reset(v);
    }

    if (root.contains("people")) {
        QVector<Person> v;
        for (const auto &it : root["people"].toArray()) {
            const QJsonObject o = it.toObject();
            Person p;
            p.id       = o["id"].toString();
            p.name     = o["name"].toString();
            p.role     = o["role"].toString();
            p.question = o["question"].toString();
            p.state    = o["state"].toString();
            p.color    = QColor(o["color"].toString());
            v.append(p);
        }
        m_people.reset(v);
    }

    if (root.contains("statuses")) {
        QVariantList v;
        for (const auto &it : root["statuses"].toArray()) {
            const QJsonObject o = it.toObject();
            QVariantMap m;
            m["id"]    = o["id"].toString();
            m["name"]  = o["name"].toString();
            m["color"] = QColor(o["color"].toString());
            v.append(m);
        }
        if (!v.isEmpty()) {
            m_statuses = v;
            emit statusesChanged();
        }
    }

    if (root.contains("settings")) {
        const QJsonObject s = root["settings"].toObject();
        if (s.contains("theme"))        { m_theme = s["theme"].toString(); emit themeChanged(); }
        if (s.contains("density"))      { m_density = s["density"].toString(); emit densityChanged(); }
        if (s.contains("currentView"))  { m_currentView = s["currentView"].toString(); emit currentViewChanged(); }
        if (s.contains("workdayStart") || s.contains("workdayEnd")) {
            if (s.contains("workdayStart")) m_workdayStart = s["workdayStart"].toInt(m_workdayStart);
            if (s.contains("workdayEnd"))   m_workdayEnd   = s["workdayEnd"].toInt(m_workdayEnd);
            emit workdayChanged();
        }
        if (s.contains("crumbProject")) { m_crumbProject = s["crumbProject"].toString(); emit crumbProjectChanged(); }
        if (s.contains("crumbUser"))    { m_crumbUser    = s["crumbUser"].toString();    emit crumbUserChanged(); }
    }

    if (root.contains("docs")) {
        m_docsState = QJsonDocument(root["docs"].toObject()).toJson(QJsonDocument::Compact);
        emit docsStateChanged();
    }

    m_loading = false;
}
