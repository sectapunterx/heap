#pragma once

#include <QObject>
#include <QDate>
#include <QTimer>
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
    Q_PROPERTY(QVariantList statuses READ statuses NOTIFY statusesChanged)
    Q_PROPERTY(QDate        today    READ today    CONSTANT)

    Q_PROPERTY(QDate selectedDate READ selectedDate WRITE setSelectedDate NOTIFY selectedDateChanged)
    Q_PROPERTY(QString theme   READ theme   WRITE setTheme   NOTIFY themeChanged)
    Q_PROPERTY(QString density READ density WRITE setDensity NOTIFY densityChanged)
    Q_PROPERTY(QString currentView READ currentView WRITE setCurrentView NOTIFY currentViewChanged)

    Q_PROPERTY(int workdayStart READ workdayStart WRITE setWorkdayStart NOTIFY workdayChanged)
    Q_PROPERTY(int workdayEnd   READ workdayEnd   WRITE setWorkdayEnd   NOTIFY workdayChanged)

    Q_PROPERTY(QString crumbProject READ crumbProject WRITE setCrumbProject NOTIFY crumbProjectChanged)
    Q_PROPERTY(QString crumbUser    READ crumbUser    WRITE setCrumbUser    NOTIFY crumbUserChanged)

    Q_PROPERTY(QString docsState READ docsState WRITE setDocsState NOTIFY docsStateChanged)
    Q_PROPERTY(bool hasPendingUndo READ hasPendingUndo NOTIFY pendingUndoChanged)

    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
    Q_PROPERTY(QString activeProfileId READ activeProfileId
               WRITE setActiveProfileId NOTIFY activeProfileChanged)

public:
    explicit AppController(QObject *parent = nullptr);
    ~AppController() override;

    Q_INVOKABLE void flushSave();

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

    QString currentView() const { return m_currentView; }
    void    setCurrentView(const QString &v);

    int  workdayStart() const { return m_workdayStart; }
    void setWorkdayStart(int v);
    int  workdayEnd() const { return m_workdayEnd; }
    void setWorkdayEnd(int v);

    QString crumbProject() const { return m_crumbProject; }
    void    setCrumbProject(const QString &v);
    QString crumbUser() const { return m_crumbUser; }
    void    setCrumbUser(const QString &v);

    QString docsState() const { return m_docsState; }
    void    setDocsState(const QString &v);

    bool hasPendingUndo() const { return m_pendingUndo.kind != PendingUndo::None; }

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
    Q_INVOKABLE void setPersonState(const QString &id, const QString &state);
    Q_INVOKABLE QVariantMap newPersonDraft() const;
    Q_INVOKABLE QVariantMap personById(const QString &id) const;
    Q_INVOKABLE void savePerson(const QVariantMap &draft);
    Q_INVOKABLE void deletePerson(const QString &id);
    Q_INVOKABLE int  pendingPeopleCount() const { return m_people.todoCount(); }

    // ---- Status (kanban column) ops ----
    Q_INVOKABLE void addStatus(const QString &name, const QString &color = QString());
    Q_INVOKABLE void renameStatus(const QString &id, const QString &name);
    Q_INVOKABLE void setStatusColor(const QString &id, const QString &color);
    Q_INVOKABLE void moveStatus(const QString &id, int newIndex);
    Q_INVOKABLE void deleteStatus(const QString &id);

    // ---- Status counts ----
    Q_INVOKABLE int  countByStatus(const QString &statusId) const;

    // ---- Lookups ----
    Q_INVOKABLE QVariantMap taskById(const QString &id) const;
    Q_INVOKABLE QString eventHourLabel(double hour) const;
    Q_INVOKABLE QString sprintLabel() const;
    Q_INVOKABLE QString humanDate(const QDate &date) const;

    // ---- Timeline / week helpers ----
    Q_INVOKABLE QString deadlineBucket(const QDate &deadline) const;   // overdue/today/tomorrow/thisweek/nextweek/later/nodl
    Q_INVOKABLE QString deadlineDiffLabel(const QDate &deadline) const;
    Q_INVOKABLE QString shortDate(const QDate &d) const;               // "Пт, 15 май"
    Q_INVOKABLE int     isoWeekNumber(const QDate &d) const;

    Q_INVOKABLE void copyToClipboard(const QString &text);

    // ---- Profiles ----
    QVariantList profiles() const;
    QString      activeProfileId() const { return m_activeProfileId; }
    void         setActiveProfileId(const QString &id);
    Q_INVOKABLE QString createProfile(const QString &name, const QString &color = QString());
    Q_INVOKABLE void    renameProfile(const QString &id, const QString &newName);
    Q_INVOKABLE void    setProfileColor(const QString &id, const QString &color);
    Q_INVOKABLE void    deleteProfile(const QString &id);
    Q_INVOKABLE QString duplicateProfile(const QString &id, const QString &newName);
    Q_INVOKABLE QString exportActiveProfileToMarkdown() const;
    Q_INVOKABLE void    copyActiveProfileMarkdownToClipboard();
    Q_INVOKABLE QVariantList commandPaletteEntries() const;

    // ---- Backups ----
    Q_INVOKABLE QVariantList listBackups() const;
    Q_INVOKABLE bool         restoreFromBackup(const QString &fileName);

    // ---- Undo ----
    Q_INVOKABLE void undoLastDeletion();
    Q_INVOKABLE void clearPendingUndo();

signals:
    void selectedDateChanged();
    void themeChanged();
    void densityChanged();
    void currentViewChanged();
    void workdayChanged();
    void crumbProjectChanged();
    void crumbUserChanged();
    void docsStateChanged();
    void statusesChanged();
    void pendingUndoChanged();
    void profilesChanged();
    void activeProfileChanged();
    void toast(const QString &message);
    void undoableToast(const QString &message, int seconds);

private:
    TaskModel    m_tasks;
    EventModel   m_events;
    PersonModel  m_people;
    QVariantList m_statuses;
    QDate        m_today;
    QDate        m_selectedDate;
    QString      m_theme       = "dark";
    QString      m_density     = "comfy";
    QString      m_currentView = "board";
    int          m_workdayStart = 9;
    int          m_workdayEnd   = 19;
    QString      m_crumbProject = "eNB-core";
    QString      m_crumbUser    = "You";
    QString      m_docsState;

    // Profiles
    QVector<Profile> m_profiles;
    QString          m_activeProfileId;
    int  profileIndexOf(const QString &id) const;
    QString makeProfileId(const QString &name) const;
    void snapshotActiveProfile();
    void applyProfileToModels(const Profile &p);
    Profile makeStartingProfile(const QString &name, const QString &color) const;

    // Persistence
    QTimer*      m_saveTimer = nullptr;
    bool         m_loading   = false;
    QDateTime    m_lastBackupAt;
    void scheduleSave();
    void saveStateNow();
    void loadStateOnStart();
    QString stateFilePath() const;
    QString backupDirPath() const;
    void rotateBackupIfDue();
    void pruneBackups(int keep);
    int statusIndexOf(const QString &id) const;

    // Undo machinery
    struct PendingUndo {
        enum Kind { None, Task, Event, Person, Status, Profile } kind = None;
        // payload — only the field matching `kind` is populated
        ::Task     task;
        ::CalEvent event;
        ::Person   person;
        QVariantMap status;
        ::Profile  profile;
        int row = -1;
        // when a task is deleted, events lose their taskId — record what to restore
        QVector<QPair<QString, QString>> detachedEventIds; // (eventId, originalTaskId)
        // when a status is deleted, tasks get re-homed — record what to restore
        QVector<QPair<QString, QString>> reHomedTasks;     // (taskId, originalStatusId)
    };
    PendingUndo  m_pendingUndo;
    QTimer*      m_undoTimer = nullptr;
    void armUndo(int seconds);
    void cancelUndo();
};
