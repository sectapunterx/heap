#pragma once

#include "Models.h"

#include <QDate>
#include <QMap>
#include <QObject>
#include <qqmlregistration.h>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include <memory>

namespace heap::chrono {
class ChronoParser;
}

namespace heap::git {
class GitWatcher;
}

namespace heap::notify {
class NotificationCenter;
}

class AppController : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

  Q_PROPERTY(TaskModel* tasks READ tasks CONSTANT)
  Q_PROPERTY(EventModel* events READ events CONSTANT)
  Q_PROPERTY(PersonModel* people READ people CONSTANT)
  Q_PROPERTY(QVariantList statuses READ statuses NOTIFY statusesChanged)
  Q_PROPERTY(QDate today READ today CONSTANT)

  Q_PROPERTY(QDate selectedDate READ selectedDate WRITE setSelectedDate NOTIFY selectedDateChanged)
  Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY themeChanged)
  Q_PROPERTY(QString density READ density WRITE setDensity NOTIFY densityChanged)
  Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
  Q_PROPERTY(QString currentView READ currentView WRITE setCurrentView NOTIFY currentViewChanged)

  Q_PROPERTY(int workdayStart READ workdayStart WRITE setWorkdayStart NOTIFY workdayChanged)
  Q_PROPERTY(int workdayEnd READ workdayEnd WRITE setWorkdayEnd NOTIFY workdayChanged)

  Q_PROPERTY(QString crumbProject READ crumbProject WRITE setCrumbProject NOTIFY crumbProjectChanged)
  Q_PROPERTY(QString crumbUser READ crumbUser WRITE setCrumbUser NOTIFY crumbUserChanged)

  Q_PROPERTY(QString docsState READ docsState WRITE setDocsState NOTIFY docsStateChanged)
  Q_PROPERTY(QString notesState READ notesState WRITE setNotesState NOTIFY notesStateChanged)
  Q_PROPERTY(QString appSettingsJson READ appSettingsJson WRITE setAppSettingsJson NOTIFY appSettingsJsonChanged)
  Q_PROPERTY(bool hasPendingUndo READ hasPendingUndo NOTIFY pendingUndoChanged)

  Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
  Q_PROPERTY(QString activeProfileId READ activeProfileId WRITE setActiveProfileId NOTIFY activeProfileChanged)

  Q_PROPERTY(QVariantList shortcuts READ shortcuts NOTIFY shortcutsChanged)
  Q_PROPERTY(QStringList blockedStuckIds READ blockedStuckIds NOTIFY blockedStuckChanged)

  // Compile-time flag — true for Debug / RelWithDebInfo builds. QML uses
  // it to surface the developer-only "show unimplemented" toggle.
  Q_PROPERTY(bool debugBuild READ debugBuild CONSTANT)

  // ---- Git focus banner ----
  Q_PROPERTY(QString focusedTaskId READ focusedTaskId NOTIFY focusedGitChanged)
  Q_PROPERTY(QString focusedBranch READ focusedBranch NOTIFY focusedGitChanged)
  Q_PROPERTY(QString focusedRepo READ focusedRepo NOTIFY focusedGitChanged)
  Q_PROPERTY(QVariantMap focusedRepoState READ focusedRepoState NOTIFY focusedGitChanged)
  Q_PROPERTY(bool focusedBannerDismissed READ focusedBannerDismissed NOTIFY focusedGitChanged)

 public:
  explicit AppController(QObject* parent = nullptr);
  ~AppController() override;

  Q_INVOKABLE void flushSave();

  TaskModel* tasks() {
    return &m_tasks;
  }

  EventModel* events() {
    return &m_events;
  }

  PersonModel* people() {
    return &m_people;
  }

  QVariantList statuses() const {
    return m_statuses;
  }

  QDate today() const {
    return m_today;
  }

  QDate selectedDate() const {
    return m_selectedDate;
  }

  void setSelectedDate(const QDate& d);

  QString theme() const {
    return m_theme;
  }

  void setTheme(const QString& t);

  QString density() const {
    return m_density;
  }

  void setDensity(const QString& d);

  QString language() const {
    return m_language;
  }

  void setLanguage(const QString& v);

  // Resolve a UI string for the current language. `key` is a stable
  // identifier (e.g. "task.created"); returns the EN form as a last-resort
  // fallback if the key is missing in the active table.
  Q_INVOKABLE QString tr_(const QString& key) const;

  QString currentView() const {
    return m_currentView;
  }

  void setCurrentView(const QString& v);

  int workdayStart() const {
    return m_workdayStart;
  }

  void setWorkdayStart(int v);

  int workdayEnd() const {
    return m_workdayEnd;
  }

  void setWorkdayEnd(int v);

  QString crumbProject() const {
    return m_crumbProject;
  }

  void setCrumbProject(const QString& v);

  QString crumbUser() const {
    return m_crumbUser;
  }

  void setCrumbUser(const QString& v);

  QString docsState() const {
    return m_docsState;
  }

  void setDocsState(const QString& v);

  QString notesState() const {
    return m_notesState;
  }

  void setNotesState(const QString& v);

  QString appSettingsJson() const {
    return m_appSettingsJson;
  }

  void setAppSettingsJson(const QString& v);

  bool hasPendingUndo() const {
    return m_pendingUndo.kind != PendingUndo::None;
  }

  // ---- Task ops ----
  Q_INVOKABLE void moveTask(const QString& id, const QString& newStatus);
  Q_INVOKABLE QVariantMap newTaskDraft(const QString& statusId) const;
  // Like newTaskDraft, but the id is a placeholder ("TODO-N") instead of
  // the project prefix — used by QuickCapture so the user is reminded to
  // assign a real ticket id later.
  Q_INVOKABLE QVariantMap newQuickTaskDraft() const;
  Q_INVOKABLE void saveTask(const QVariantMap& draft);
  Q_INVOKABLE void deleteTask(const QString& id);
  Q_INVOKABLE bool canTransitionStatus(const QString& taskId, const QString& newStatus);
  Q_INVOKABLE void setArchived(const QString& taskId, bool archived);

  QStringList blockedStuckIds() const {
    return m_blockedStuckIds.values();
  }

  static constexpr bool debugBuild() {
#ifdef HEAP_DEBUG_BUILD
    return true;
#else
    return false;
#endif
  }

  // ---- Notifications & automation ----
  Q_INVOKABLE void notify(const QString& title, const QString& body, const QString& kind = QString());
  // Post the given rich payload via the native notification backend.
  // `taskId` is the optional task tied to this toast — it is encoded into
  // the notification id so the action handlers can route back.
  Q_INVOKABLE void notifyTask(const QString& taskId, const QString& title, const QString& body, const QString& kind = QString());
  // Slide the deadline of \p taskId forward by \p seconds (no-op if the
  // task currently has no deadline). Invoked by the "Snooze 1h" action.
  Q_INVOKABLE void snoozeDeadline(const QString& taskId, int seconds);

  // ---- Event ops ----
  Q_INVOKABLE QVariantMap newEventDraft(double startHour, const QDate& date) const;
  Q_INVOKABLE void saveEvent(const QVariantMap& draft);
  Q_INVOKABLE void updateEvent(const QString& id, double start, double end, const QDate& date);
  Q_INVOKABLE void deleteEvent(const QString& id);
  Q_INVOKABLE void scheduleTask(const QString& taskId, double startHour, const QDate& date);
  Q_INVOKABLE QString scheduledLabelFor(const QString& taskId, const QDate& date) const;

  // ---- People ops ----
  Q_INVOKABLE void cyclePerson(const QString& id);
  Q_INVOKABLE void setPersonState(const QString& id, const QString& state);
  Q_INVOKABLE QVariantMap newPersonDraft() const;
  Q_INVOKABLE QVariantMap personById(const QString& id) const;
  Q_INVOKABLE void savePerson(const QVariantMap& draft);
  Q_INVOKABLE void deletePerson(const QString& id);

  Q_INVOKABLE int pendingPeopleCount() const {
    return m_people.todoCount();
  }

  // ---- Status (kanban column) ops ----
  Q_INVOKABLE void addStatus(const QString& name, const QString& color = QString());
  Q_INVOKABLE void renameStatus(const QString& id, const QString& name);
  Q_INVOKABLE void setStatusColor(const QString& id, const QString& color);
  Q_INVOKABLE void moveStatus(const QString& id, int newIndex);
  Q_INVOKABLE void deleteStatus(const QString& id);

  // ---- Status counts ----
  Q_INVOKABLE int countByStatus(const QString& statusId) const;

  // ---- Lookups ----
  Q_INVOKABLE QVariantMap taskById(const QString& id) const;
  Q_INVOKABLE QString eventHourLabel(double hour) const;
  Q_INVOKABLE QString sprintLabel() const;
  Q_INVOKABLE QString humanDate(const QDate& date) const;

  // ---- Timeline / week helpers ----
  Q_INVOKABLE QString deadlineBucket(const QDate& deadline) const;  // overdue/today/tomorrow/thisweek/nextweek/later/nodl
  Q_INVOKABLE QString deadlineDiffLabel(const QDate& deadline) const;
  Q_INVOKABLE QString shortDate(const QDate& d) const;  // "Пт, 15 май"
  Q_INVOKABLE int isoWeekNumber(const QDate& d) const;

  // ---- Free-form datetime parser (heap chrono) ----
  Q_INVOKABLE QVariantMap parseDateTime(const QString& input, const QDateTime& reference = QDateTime()) const;
  Q_INVOKABLE QVariantList parseAllDateTimes(const QString& input, const QDateTime& reference = QDateTime()) const;

  Q_INVOKABLE void copyToClipboard(const QString& text);

  // ---- Free-form text classification (used by QuickCapture / TaskEditor) ----
  // Returns one of "focus" | "sync" | "ticket" | "none".
  Q_INVOKABLE QString classifyTaskKind(const QString& text) const;
  // Returns { title, desc, handles: [..] } — same shape as the JS helper.
  Q_INVOKABLE QVariantMap extractTaskMeta(const QString& text) const;
  // Suggest a slug-style person id ("e.zaharov") from a free-form name.
  // Avoids collisions with already-existing ids in the active profile
  // by appending "-2", "-3", … on conflict.
  Q_INVOKABLE QString suggestPersonId(const QString& name, const QString& exceptId = QString()) const;

  // ---- Profiles ----
  QVariantList profiles() const;

  QString activeProfileId() const {
    return m_activeProfileId;
  }

  void setActiveProfileId(const QString& id);
  Q_INVOKABLE QString createProfile(const QString& name, const QString& color = QString());
  Q_INVOKABLE void renameProfile(const QString& id, const QString& newName);
  Q_INVOKABLE void setProfileColor(const QString& id, const QString& color);
  Q_INVOKABLE void deleteProfile(const QString& id);
  Q_INVOKABLE QString duplicateProfile(const QString& id, const QString& newName);
  Q_INVOKABLE QVariantMap profileById(const QString& id) const;

  // Rewrite every task id that starts with `oldPrefix-<digits>` to use
  // `newPrefix-<digits>`. CalEvent.taskId backlinks are kept in sync so
  // scheduled-task labels stay attached. Returns the number of tasks
  // renamed. Used by Settings → Tasks when toggling idPrefix.
  Q_INVOKABLE int renameTaskIdPrefix(const QString& oldPrefix, const QString& newPrefix);
  // Profile JSON import / export (replaces the older Markdown export).
  Q_INVOKABLE QString exportActiveProfileJson() const;
  Q_INVOKABLE bool exportActiveProfileToFile(const QUrl& fileUrl) const;
  Q_INVOKABLE QString importProfileFromJson(const QString& jsonText, bool activate = true);
  Q_INVOKABLE QString importProfileFromFile(const QUrl& fileUrl, bool activate = true);

  Q_INVOKABLE QVariantList commandPaletteEntries() const;

  // ---- Backups ----
  Q_INVOKABLE QVariantList listBackups() const;
  Q_INVOKABLE bool restoreFromBackup(const QString& fileName);

  // ---- Shortcuts (rebindable keyboard catalog) ----
  QVariantList shortcuts() const {
    return m_shortcuts;
  }

  Q_INVOKABLE QString shortcutFor(const QString& id) const;
  Q_INVOKABLE QString defaultShortcutFor(const QString& id) const;
  Q_INVOKABLE QString shortcutDescription(const QString& id) const;
  Q_INVOKABLE QString shortcutLabel(const QString& id) const;
  Q_INVOKABLE QString findShortcutConflict(const QString& id, const QString& sequence) const;
  Q_INVOKABLE bool setShortcut(const QString& id, const QString& sequence);
  Q_INVOKABLE void resetShortcut(const QString& id);
  Q_INVOKABLE void resetAllShortcuts();

  // ---- Undo ----
  Q_INVOKABLE void undoLastDeletion();
  Q_INVOKABLE void clearPendingUndo();

  // ---- Git focus / watcher ----
  QString focusedTaskId() const {
    return m_focusedTaskId;
  }

  QString focusedBranch() const {
    return m_focusedBranch;
  }

  QString focusedRepo() const {
    return m_focusedRepo;
  }

  QVariantMap focusedRepoState() const {
    return m_focusedRepoState;
  }

  bool focusedBannerDismissed() const {
    return m_dismissedBranches.contains(m_focusedBranch);
  }

  Q_INVOKABLE void dismissGitBanner();
  Q_INVOKABLE void openFocusedTask();
  Q_INVOKABLE QStringList collectPrefixes() const;
  Q_INVOKABLE void refreshGitForTaskBranch(const QString& taskId);

 signals:
  void selectedDateChanged();
  void themeChanged();
  void densityChanged();
  void languageChanged();
  void currentViewChanged();
  void workdayChanged();
  void crumbProjectChanged();
  void crumbUserChanged();
  void docsStateChanged();
  void notesStateChanged();
  void appSettingsJsonChanged();
  void statusesChanged();
  void pendingUndoChanged();
  void profilesChanged();
  void activeProfileChanged();
  void shortcutsChanged();
  void blockedStuckChanged();
  void notification(const QString& title, const QString& body, const QString& kind);
  void toast(const QString& message);
  void undoableToast(const QString& message, int seconds);
  void focusedGitChanged();
  void openTaskRequested(const QString& id);

 private slots:
  void runAutomation();

 private:
  TaskModel m_tasks;
  EventModel m_events;
  PersonModel m_people;
  QVariantList m_statuses;
  QDate m_today;
  QDate m_selectedDate;
  QString m_theme = "dark";
  QString m_density = "comfy";
  QString m_language = "en";
  QString m_currentView = "board";
  int m_workdayStart = 9;
  int m_workdayEnd = 19;
  QString m_crumbProject = "eNB-core";
  QString m_crumbUser = "You";
  QString m_docsState;
  QString m_notesState;
  QString m_appSettingsJson;

  // Profiles
  QVector<Profile> m_profiles;
  QString m_activeProfileId;
  int profileIndexOf(const QString& id) const;
  QString makeProfileId(const QString& name) const;
  void snapshotActiveProfile();
  void applyProfileToModels(const Profile& p);
  Profile makeStartingProfile(const QString& name, const QString& color) const;

  // Shortcuts
  QVariantList m_shortcuts;  // [{id,label,description,defaultSequence,sequence}]
  int shortcutIndexOf(const QString& id) const;
  void seedShortcutCatalog();
  void applyShortcutOverrides(const QVariantMap& overrides);
  QString normalizeSequence(const QString& raw) const;

  // Automation
  QTimer* m_automationTimer = nullptr;
  std::unique_ptr<heap::notify::NotificationCenter> m_notifier;
  void onNotifierAction(const QString& notificationId, const QString& actionId);
  void onNotifierActivated(const QString& notificationId);
  QSet<QString> m_blockedStuckIds;
  QMap<QString, QDate> m_lastReminderDay;  // task/sentinel id -> last day notified
  QVariantMap settingsMap() const;
  bool inQuietHours(const QDateTime& when) const;
  static double nextQuarterHour(const QDateTime& when);
  void scheduleFocusBlockFor(const QString& taskId);

  // Persistence
  QTimer* m_saveTimer = nullptr;
  bool m_loading = false;
  QDateTime m_lastBackupAt;
  void scheduleSave();
  void saveStateNow();
  void loadStateOnStart();
  QString stateFilePath() const;
  QString backupDirPath() const;
  void rotateBackupIfDue();
  void pruneBackups(int keep);
  int statusIndexOf(const QString& id) const;

  // Undo machinery
  struct PendingUndo {
    enum Kind { None, Task, Event, Person, Status, Profile } kind = None;

    // payload — only the field matching `kind` is populated
    ::Task task;
    ::CalEvent event;
    ::Person person;
    QVariantMap status;
    ::Profile profile;
    int row = -1;
    // when a task is deleted, events lose their taskId — record what to restore
    QVector<QPair<QString, QString>> detachedEventIds;  // (eventId, originalTaskId)
    // when a status is deleted, tasks get re-homed — record what to restore
    QVector<QPair<QString, QString>> reHomedTasks;  // (taskId, originalStatusId)
  };

  PendingUndo m_pendingUndo;
  QTimer* m_undoTimer = nullptr;
  void armUndo(int seconds);
  void cancelUndo();

  std::unique_ptr<heap::chrono::ChronoParser> m_chrono;

  // ---- Git watcher ----
  std::unique_ptr<heap::git::GitWatcher> m_gitWatcher;
  QString m_focusedTaskId, m_focusedBranch, m_focusedRepo;
  QVariantMap m_focusedRepoState;
  QSet<QString> m_dismissedBranches;  // in-memory only; per branch name
  void applyGitSettingsFromMap(const QVariantMap& git);
  void onGitBranchChanged(const QString& repo, const QString& branch, const QString& taskId);
  void onGitRepoState(const QString& repo, const QVariantMap& state);
};
