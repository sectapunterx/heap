#pragma once

#include <QAbstractListModel>
#include <QColor>
#include <QDate>
#include <QString>
#include <QVector>
#include <qqmlregistration.h>

struct Task {
    QString id;
    QString title;
    QString desc;
    QString priority;   // P0..P3
    QString status;     // backlog/todo/prog/half/blocked/review/done
    QDate   deadline;   // invalid = none
    QString branch;
};

struct CalEvent {
    QString id;
    QString title;
    QString type;       // standup/oneone/sync/focus
    double  start;      // hour 0..24
    double  end;
    QString attendees;
    QDate   date;
    QString taskId;     // optional link
};

struct Person {
    QString id;
    QString name;
    QString role;
    QString question;
    QString state;      // todo/pinged/replied
    QColor  color;
};

class TaskModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Provided by AppController")
public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        TitleRole, DescRole, PriorityRole,
        StatusRole, DeadlineRole, BranchRole,
    };
    explicit TaskModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex & = {}) const override { return m_items.size(); }
    QVariant data(const QModelIndex &idx, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void reset(QVector<Task> items);
    const QVector<Task>& items() const { return m_items; }

    int indexOfId(const QString &id) const;
    void setStatus(const QString &id, const QString &status);
    void upsert(const Task &t);
    void removeById(const QString &id);

private:
    QVector<Task> m_items;
};

class EventModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Provided by AppController")
public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        TitleRole, TypeRole, StartRole, EndRole,
        AttendeesRole, DateRole, TaskIdRole,
    };
    explicit EventModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex & = {}) const override { return m_items.size(); }
    QVariant data(const QModelIndex &idx, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void reset(QVector<CalEvent> items);
    const QVector<CalEvent>& items() const { return m_items; }

    int indexOfId(const QString &id) const;
    void upsert(const CalEvent &e);
    void removeById(const QString &id);
    void detachTask(const QString &taskId);

private:
    QVector<CalEvent> m_items;
};

class PersonModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Provided by AppController")
public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        NameRole, RoleRole, QuestionRole, StateRole, ColorRole,
    };
    explicit PersonModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex & = {}) const override { return m_items.size(); }
    QVariant data(const QModelIndex &idx, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void reset(QVector<Person> items);

    int indexOfId(const QString &id) const;
    void cycleState(const QString &id);
    void setState(const QString &id, const QString &state);
    void upsert(const Person &p);
    void removeById(const QString &id);
    int todoCount() const;

private:
    QVector<Person> m_items;
};
