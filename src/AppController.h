#pragma once

#include <QObject>
#include <QDate>
#include <QVariantList>
#include <qqmlregistration.h>

#include "Models.h"

class AppController : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(TaskModel*   tasks    READ tasks    CONSTANT)
    Q_PROPERTY(EventModel*  events   READ events   CONSTANT)
    Q_PROPERTY(PersonModel* people   READ people   CONSTANT)
    Q_PROPERTY(QVariantList statuses READ statuses CONSTANT)
    Q_PROPERTY(QDate        today    READ today    CONSTANT)

    Q_PROPERTY(QDate selectedDate READ selectedDate WRITE setSelectedDate NOTIFY selectedDateChanged)
    Q_PROPERTY(QString theme   READ theme   WRITE setTheme   NOTIFY themeChanged)
    Q_PROPERTY(QString density READ density WRITE setDensity NOTIFY densityChanged)

public:
    explicit AppController(QObject *parent = nullptr);

    TaskModel*   tasks()    { return &m_tasks; }
    EventModel*  events()   { return &m_events; }
    PersonModel* people()   { return &m_people; }
    QVariantList statuses() const { return m_statuses; }
    QDate        today() const    { return m_today; }

    QDate selectedDate() const { return m_selectedDate; }
    void  setSelectedDate(const QDate &d);

    QString theme() const { return m_theme; }
    void    setTheme(const QString &t);

    QString density() const { return m_density; }
    void    setDensity(const QString &d);

    // ---- Task ops ----
    Q_INVOKABLE void moveTask(const QString &id, const QString &newStatus);
    Q_INVOKABLE QVariantMap newTaskDraft(const QString &statusId) const;
    Q_INVOKABLE void saveTask(const QVariantMap &draft);
    Q_INVOKABLE void deleteTask(const QString &id);

    // ---- Event ops ----
    Q_INVOKABLE QVariantMap newEventDraft(double startHour, const QDate &date) const;
    Q_INVOKABLE void saveEvent(const QVariantMap &draft);
    Q_INVOKABLE void deleteEvent(const QString &id);
    Q_INVOKABLE void scheduleTask(const QString &taskId, double startHour, const QDate &date);

    // ---- People ops ----
    Q_INVOKABLE void cyclePerson(const QString &id);
    Q_INVOKABLE int  pendingPeopleCount() const { return m_people.todoCount(); }

    // ---- Status counts ----
    Q_INVOKABLE int  countByStatus(const QString &statusId) const;

    // ---- Lookups ----
    Q_INVOKABLE QVariantMap taskById(const QString &id) const;
    Q_INVOKABLE QString eventHourLabel(double hour) const;
    Q_INVOKABLE QString sprintLabel() const;
    Q_INVOKABLE QString humanDate(const QDate &date) const;

signals:
    void selectedDateChanged();
    void themeChanged();
    void densityChanged();
    void toast(const QString &message);

private:
    TaskModel    m_tasks;
    EventModel   m_events;
    PersonModel  m_people;
    QVariantList m_statuses;
    QDate        m_today;
    QDate        m_selectedDate;
    QString      m_theme   = "dark";
    QString      m_density = "comfy";
};
