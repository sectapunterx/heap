#include "AppController.h"
#include "SampleData.h"

#include <QDateTime>
#include <QLocale>
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
}

void AppController::setDensity(const QString &d) {
    if (d == m_density) return;
    m_density = d;
    emit densityChanged();
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
}

void AppController::deleteTask(const QString &id) {
    m_events.detachTask(id);
    m_tasks.removeById(id);
    emit toast(QString("Удалена: %1").arg(id));
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
}

void AppController::deleteEvent(const QString &id) {
    m_events.removeById(id);
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
}

void AppController::cyclePerson(const QString &id) {
    m_people.cycleState(id);
}

void AppController::setPersonState(const QString &id, const QString &state) {
    m_people.setState(id, state);
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
}

void AppController::deletePerson(const QString &id) {
    const int row = m_people.indexOfId(id);
    if (row < 0) return;
    const QString name = m_people.data(m_people.index(row,0), PersonModel::NameRole).toString();
    m_people.removeById(id);
    emit toast(QString("Удалён: %1").arg(name));
}

int AppController::countByStatus(const QString &statusId) const {
    int n = 0;
    for (const auto &t : m_tasks.items()) if (t.status == statusId) ++n;
    return n;
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
