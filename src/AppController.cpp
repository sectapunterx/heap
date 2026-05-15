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
