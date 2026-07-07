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
#include <vector>

class QJsonObject;

namespace heap::chrono {
class ChronoParser;
}

namespace heap::git {
class GitWatcher;
}

namespace heap::notify {
class NotificationCenter;
}

namespace heap::platform {
class GlobalHotkey;
}

namespace heap::update {
class Updater;
}

namespace heap::integrations {
class IntegrationProvider;
class SecretStore;
struct ExternalTask;
}  // namespace heap::integrations

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
  Q_PROPERTY(QString focusedStatus READ focusedStatus NOTIFY focusedStatusChanged)

  Q_PROPERTY(int workdayStart READ workdayStart WRITE setWorkdayStart NOTIFY workdayChanged)
  Q_PROPERTY(int workdayEnd READ workdayEnd WRITE setWorkdayEnd NOTIFY workdayChanged)

  Q_PROPERTY(QString crumbProject READ crumbProject WRITE setCrumbProject NOTIFY crumbProjectChanged)
  Q_PROPERTY(QString crumbUser READ crumbUser WRITE setCrumbUser NOTIFY crumbUserChanged)

  Q_PROPERTY(QString docsState READ docsState WRITE setDocsState NOTIFY docsStateChanged)
  Q_PROPERTY(QString notesState READ notesState WRITE setNotesState NOTIFY notesStateChanged)
  Q_PROPERTY(QString appSettingsJson READ appSettingsJson WRITE setAppSettingsJson NOTIFY appSettingsJsonChanged)
  Q_PROPERTY(bool hasPendingUndo READ hasPendingUndo NOTIFY pendingUndoChanged)

  // ---- Onboarding (first run) ----
  // welcomeSeen: the welcome dialog has been shown/dismissed at least once.
  // demoActive: the profile is still the seeded demo, so the "this is demo
  // data" banner should offer to start fresh. Both persist in the settings blob.
  Q_PROPERTY(bool welcomeSeen READ welcomeSeen NOTIFY onboardingChanged)
  Q_PROPERTY(bool demoActive READ demoActive NOTIFY onboardingChanged)

  Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
  Q_PROPERTY(QString activeProfileId READ activeProfileId WRITE setActiveProfileId NOTIFY activeProfileChanged)

  Q_PROPERTY(QVariantList shortcuts READ shortcuts NOTIFY shortcutsChanged)
  Q_PROPERTY(QStringList blockedStuckIds READ blockedStuckIds NOTIFY blockedStuckChanged)

  // ---- Multi-select ----
  Q_PROPERTY(QStringList selectedTaskIds READ selectedTaskIds NOTIFY selectedTaskIdsChanged)
  Q_PROPERTY(int selectionCount READ selectionCount NOTIFY selectedTaskIdsChanged)

  // Compile-time flag — true for Debug / RelWithDebInfo builds. QML uses
  // it to surface the developer-only "show unimplemented" toggle.
  Q_PROPERTY(bool debugBuild READ debugBuild CONSTANT)

  // Runtime facts for Settings → About (so nothing is hardcoded / stale).
  Q_PROPERTY(QString dataDir READ dataDir CONSTANT)
  Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)
  Q_PROPERTY(QString appVersion READ appVersion CONSTANT)

  // ---- Auto-update (HEAP-63) ----
  // Human-readable result of the last update check, shown in Settings → About:
  // "" (idle), a "checking" string, "up to date", or "update available: vX".
  Q_PROPERTY(QString updateStatus READ updateStatus NOTIFY updateStatusChanged)

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

  QString focusedStatus() const {
    return m_focusedStatus;
  }

  // Jump the Board to a specific status column (sidebar Blocked / Code Review).
  Q_INVOKABLE void focusStatusColumn(const QString& statusId);

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

  // QuickCapture for Notes: appends `text` to notesState separated by a
  // timestamped horizontal-rule header. First entry gets the heading only
  // (no leading HR — there is nothing to separate from yet).
  Q_INVOKABLE void appendNoteEntry(const QString& text);

  // Note wiki-links (HEAP-79). Headings feed [[…]] autocomplete; backlinks list
  // which lines reference each [[target]]; the offset lets the editor jump to a
  // heading. The caller passes the live editor text so results reflect unsaved
  // edits (the pure logic lives in heap::notes and is unit-tested there).
  Q_INVOKABLE QStringList noteHeadings(const QString& markdown) const;
  Q_INVOKABLE QVariantList noteBacklinks(const QString& markdown) const;
  Q_INVOKABLE int noteHeadingOffset(const QString& markdown, const QString& heading) const;

  QString appSettingsJson() const {
    return m_appSettingsJson;
  }

  void setAppSettingsJson(const QString& v);

  bool hasPendingUndo() const {
    return m_pendingUndo.kind != PendingUndo::None;
  }

  // ---- Onboarding ----
  bool welcomeSeen() const {
    return m_welcomeSeen;
  }

  bool demoActive() const {
    return m_demoActive;
  }

  // Mark the welcome dialog as shown (persists; never re-shown after this).
  Q_INVOKABLE void markWelcomeSeen();
  // Hide the demo banner without clearing anything ("keep exploring").
  Q_INVOKABLE void dismissDemo();
  // Clear the active profile's demo content (tasks, people, events, notes,
  // docs) to give the user a blank workspace; keeps the profile and its
  // columns. Also clears the demo banner.
  Q_INVOKABLE void startFresh();
  // Nuke everything — profiles, tasks, notes, docs, events, settings, the
  // on-disk state.json + backups — and re-seed the Example profile with the
  // first-run onboarding, so the app is exactly "as new" on this device.
  Q_INVOKABLE void resetToFirstRun();

  // ---- Task ops ----
  Q_INVOKABLE void moveTask(const QString& id, const QString& newStatus);
  Q_INVOKABLE QVariantMap newTaskDraft(const QString& statusId) const;
  // Like newTaskDraft, but the id is a placeholder ("TODO-N") instead of
  // the project prefix — used by QuickCapture so the user is reminded to
  // assign a real ticket id later.
  Q_INVOKABLE QVariantMap newQuickTaskDraft() const;
  // Reusable task/checklist templates (HEAP-77). taskTemplates lists the
  // built-ins ({name, title, desc}); createTaskFromTemplate drops a pre-filled
  // task (checklist in the description) onto the board.
  Q_INVOKABLE QVariantList taskTemplates() const;
  Q_INVOKABLE void createTaskFromTemplate(const QString& name);
  Q_INVOKABLE void saveTask(const QVariantMap& draft);
  Q_INVOKABLE void deleteTask(const QString& id);
  Q_INVOKABLE bool canTransitionStatus(const QString& taskId, const QString& newStatus);
  Q_INVOKABLE void setArchived(const QString& taskId, bool archived);

  // Time tracking (HEAP-78). start/stop the per-task timer (only one runs at a
  // time); elapsedSecondsFor returns the live total incl. the running session.
  Q_INVOKABLE void startTaskTimer(const QString& id);
  Q_INVOKABLE void stopTaskTimer(const QString& id);
  Q_INVOKABLE int elapsedSecondsFor(const QString& id) const;

  // ---- Multi-select API ----
  QStringList selectedTaskIds() const {
    return m_selectedTaskIdsList;
  }

  int selectionCount() const {
    return m_selectedTaskIdsList.size();
  }

  Q_INVOKABLE bool isTaskSelected(const QString& id) const;
  Q_INVOKABLE void toggleTaskSelection(const QString& id);
  Q_INVOKABLE void setTaskSelected(const QString& id, bool selected);
  Q_INVOKABLE void setSelectedTaskIds(const QStringList& ids);
  Q_INVOKABLE void clearSelection();

  // Bulk ops — operate on the current selection set.
  Q_INVOKABLE void deleteSelectedTasks();
  Q_INVOKABLE void moveSelectedTasksToStatus(const QString& statusId);
  Q_INVOKABLE void setSelectedTasksArchived(bool archived);

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

  // Actual writable data directory (where state.json / backups live) and the
  // Qt runtime version — resolved at runtime for the About panel.
  QString dataDir() const;
  QString qtVersion() const;
  QString appVersion() const;

  QString updateStatus() const {
    return m_updateStatus;
  }

  // ---- Diagnostics (HEAP-64) ----
  // Open the rotating-log directory in the system file manager.
  Q_INVOKABLE void openLogsFolder() const;
  // Open a pre-filled GitHub "new issue" page carrying version / OS / Qt
  // version / recent-log-tail diagnostics, so a user can file a report in one
  // click.
  Q_INVOKABLE void reportAnIssue() const;

  // ---- Auto-update (HEAP-63) ----
  // Manually trigger a GitHub-Releases check (Settings → About → "Check for
  // updates"). Result surfaces via updateStatus + the updateAvailable toast.
  Q_INVOKABLE void checkForUpdates();
  // Open the latest release's page in the browser — the "Download" action.
  Q_INVOKABLE void openLatestRelease() const;

  // ---- Tracker sync (HEAP-74/75) ----
  // Pull issues from every connected tracker and mirror them as tasks in the
  // active profile. No-op (with a toast) when no provider is configured.
  Q_INVOKABLE void syncNow();
  // Pull from a single connected provider (the per-card "Sync now" button).
  Q_INVOKABLE void syncProvider(const QString& providerId);
  // Validate the current credentials for one provider and toast the result.
  Q_INVOKABLE void testIntegration(const QString& providerId);
  // Start the browser OAuth flow for a provider; on success stores the access
  // token in the keychain and marks the provider connected (authMode=oauth).
  Q_INVOKABLE void connectOAuth(const QString& providerId);
  // The full integration catalogue (id, name, colour, fields, …) for the
  // Settings → Integrations cards. Data-driven from the provider registry.
  Q_INVOKABLE QVariantList integrationCatalog() const;
  // Secret (token/key) accessors — secrets live in the OS keychain, never in
  // state.json, so QML reads/writes them through these instead of the settings
  // blob.
  Q_INVOKABLE QString integrationSecret(const QString& providerId, const QString& field) const;
  Q_INVOKABLE bool hasIntegrationSecret(const QString& providerId, const QString& field) const;
  Q_INVOKABLE void setIntegrationSecret(const QString& providerId, const QString& field, const QString& value);

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
  // Render a Markdown summary of the active profile (tasks grouped by column,
  // people, notes) and put it on the clipboard. Bound to the profile.exportMd
  // shortcut (Ctrl+Shift+E).
  Q_INVOKABLE void copyActiveProfileMarkdownToClipboard();
  // Weekly "what I shipped" report (HEAP-78): done tasks from the last 7 days
  // with tracked time, copied to the clipboard as Markdown.
  Q_INVOKABLE void copyWeeklyReportToClipboard();
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
  // Create (and switch to) the task's branch from a task card. Honors the
  // configured integrations.github.branchTemplate; toasts the result.
  Q_INVOKABLE void createBranchForTask(const QString& taskId);

 signals:
  void selectedDateChanged();
  void themeChanged();
  void densityChanged();
  void languageChanged();
  void currentViewChanged();
  void focusedStatusChanged();
  void workdayChanged();
  void crumbProjectChanged();
  void crumbUserChanged();
  void docsStateChanged();
  void notesStateChanged();
  void appSettingsJsonChanged();
  void statusesChanged();
  void pendingUndoChanged();
  void onboardingChanged();
  // Emitted after resetToFirstRun() rebuilds a fresh install — Main.qml re-opens
  // the Welcome dialog and surfaces a confirmation toast.
  void firstRunReset();
  void profilesChanged();
  void activeProfileChanged();
  void shortcutsChanged();
  void blockedStuckChanged();
  void notification(const QString& title, const QString& body, const QString& kind);
  void toast(const QString& message);
  // Device-flow OAuth: prompts the Integrations card to show a "enter this code
  // in your browser" banner. An empty `code` clears the banner (flow finished).
  void oauthDeviceCode(const QString& providerId, const QString& code, const QString& verificationUri);
  void updateStatusChanged();
  // Emitted when a newer release is found — Main.qml shows an actionable toast.
  void updateAvailable(const QString& version, const QString& url);
  void undoableToast(const QString& message, int seconds);
  void focusedGitChanged();
  void openTaskRequested(const QString& id);
  void selectedTaskIdsChanged();
  // Raised by the OS-level global hotkeys (Quick-capture from anywhere). QML
  // brings the window forward and opens the matching capture popup.
  void quickCaptureRequested();
  void quickCaptureNotesRequested();
  // Raised when the user asks to restore the window from the tray (tray click
  // or the tray menu's "Show" entry). QML un-hides and activates the window.
  void showWindowRequested();

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
  QString m_focusedStatus;
  int m_workdayStart = 9;
  int m_workdayEnd = 19;
  QString m_crumbProject = "eNB-core";
  QString m_crumbUser = "You";
  QString m_docsState;
  QString m_notesState;
  QString m_appSettingsJson;
  bool m_welcomeSeen = false;  // onboarding: welcome dialog shown at least once
  bool m_demoActive = false;   // onboarding: profile still holds seeded demo

  // Profiles
  QVector<Profile> m_profiles;
  QString m_activeProfileId;
  int profileIndexOf(const QString& id) const;
  QString makeProfileId(const QString& name) const;
  void snapshotActiveProfile();
  void applyProfileToModels(const Profile& p);
  Profile makeStartingProfile(const QString& name, const QString& color) const;
  // Seed the first-run "Example" profile (demo tasks/people/events) + onboarding
  // flags. Shared by the constructor's fresh-install path and resetToFirstRun().
  void seedExampleProfile();

  // Shortcuts
  QVariantList m_shortcuts;  // [{id,label,description,defaultSequence,sequence}]
  int shortcutIndexOf(const QString& id) const;
  void seedShortcutCatalog();
  void applyShortcutOverrides(const QVariantMap& overrides);
  QString normalizeSequence(const QString& raw) const;

  // Global hotkeys — OS-level Quick-capture triggers (work unfocused). Re-armed
  // from the matching catalog sequences whenever they change. Each combination
  // is registered under one of these ids and routed back in onGlobalHotkey().
  enum GlobalHotkeyId { HotkeyQuickCapture = 1, HotkeyQuickCaptureNotes = 2 };

  std::unique_ptr<heap::platform::GlobalHotkey> m_globalHotkey;
  void registerGlobalHotkeys();
  void onGlobalHotkey(int id);

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
  // Crash/corruption recovery for loadStateOnStart(): find the newest backup
  // that still parses (returns its object + path), and move a damaged
  // state.json aside so a fresh seed can never silently overwrite it.
  bool recoverFromNewestBackup(QJsonObject& out, QString& fromPath);
  void quarantineCorruptState(const QString& path);
  QString m_recoveryNotice;  // deferred toast shown once the UI is up
  int statusIndexOf(const QString& id) const;

  // Undo machinery
  struct PendingUndo {
    enum Kind { None, Task, BulkTasks, Event, Person, Status, Profile, TaskMove, TaskArchive } kind = None;

    // payload — only the field matching `kind` is populated
    ::Task task;
    ::CalEvent event;
    ::Person person;
    QVariantMap status;
    ::Profile profile;
    int row = -1;
    // TaskMove / TaskArchive — the single task and the value to restore.
    QString taskId;
    QString prevStatus;
    bool prevArchived = false;
    // Bulk-task delete — every task and its original row index. Ordered
    // by ascending row so re-insertion in the same order is safe.
    QVector<::Task> tasks;
    QVector<int> rows;
    // when a task is deleted, events lose their taskId — record what to restore
    QVector<QPair<QString, QString>> detachedEventIds;  // (eventId, originalTaskId)
    // when a status is deleted, tasks get re-homed — record what to restore
    QVector<QPair<QString, QString>> reHomedTasks;  // (taskId, originalStatusId)
  };

  PendingUndo m_pendingUndo;
  QTimer* m_undoTimer = nullptr;
  void armUndo(int seconds);
  void cancelUndo();

  // Selection state
  QSet<QString> m_selectedTaskIds;
  QStringList m_selectedTaskIdsList;  // ordered cache for QML
  void rebuildSelectionList_();

  std::unique_ptr<heap::chrono::ChronoParser> m_chrono;

  // ---- Git watcher ----
  std::unique_ptr<heap::git::GitWatcher> m_gitWatcher;

  // ---- Auto-update (HEAP-63) ----
  std::unique_ptr<heap::update::Updater> m_updater;
  QString m_updateStatus;
  QString m_latestReleaseUrl;

  // ---- Tracker sync (HEAP-74 GitHub, HEAP-75 Jira + GitLab) ----
  // Every connected + configured provider runs concurrently; a task's
  // externalProvider routes status pushes to the matching one.
  std::vector<std::unique_ptr<heap::integrations::IntegrationProvider>> m_syncProviders;
  // Access tokens for the trackers, kept in the OS keychain (HEAP-74/75).
  heap::integrations::SecretStore* m_secretStore = nullptr;
  // Drives optional periodic pulls (integrations.autoSyncMinutes).
  QTimer* m_syncTimer = nullptr;
  // Reconcile the active providers with the current integrations settings.
  void applyIntegrationSettings();
  // Merge a provider's non-secret settings with its keychain secrets.
  QVariantMap integrationConfig(const QString& providerId) const;
  // Write one non-secret integration field into the settings blob and persist.
  void setIntegrationField(const QString& providerId, const QString& field, const QVariant& value);
  // One-time move of any plaintext tokens found in state.json into the keychain.
  void migrateLegacySecrets();
  // Fold a batch of pulled external tasks into the model. providerId tags the
  // task's externalProvider; idPrefix seeds ids for newly-created local tasks.
  void mergeExternalTasks(const QString& providerId, const QString& idPrefix, const QVector<heap::integrations::ExternalTask>& issues);
  QString m_focusedTaskId, m_focusedBranch, m_focusedRepo;
  QVariantMap m_focusedRepoState;
  QSet<QString> m_dismissedBranches;  // in-memory only; per branch name
  void applyGitSettingsFromMap(const QVariantMap& git);
  // Re-derive the focused branch's task id under the current id-prefix and
  // refresh the banner. Needed because a prefix change (settings/profile) does
  // not move HEAD, so no branchChanged fires to re-run the match on its own.
  void refreshFocusedTaskId();
  void onGitBranchChanged(const QString& repo, const QString& branch, const QString& taskId);
  void onGitRepoState(const QString& repo, const QVariantMap& state);
  void onGitCommits(const QString& repo, const QVariantMap& commitsByTask);
};
