#pragma once

#include "Models.h"

#include "board/Rank.h"
#include "history/TaskHistory.h"
#include "integrations/SyncHealth.h"
#include "notify/EventLog.h"
#include "notify/NotifyPayload.h"
#include "safety/EndOfDay.h"
#include "undo/UndoStack.h"

#include <QDate>
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QMap>
#include <QObject>
#include <qqmlregistration.h>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include <functional>
#include <memory>
#include <vector>

class QNetworkAccessManager;
class QThread;

namespace heap::chrono {
class ChronoParser;
}

namespace heap::query {
class TaskQuery;
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

namespace heap::notes {
struct VaultPlanItem;
}

namespace heap::update {
class Updater;
}

namespace heap::storage {
class AsyncSaver;
struct SaveOutcome;
}  // namespace heap::storage

namespace heap::integrations {
class IntegrationProvider;
class MattermostClient;
class SecretStore;
struct ExternalContact;
struct ExternalTask;
}  // namespace heap::integrations

class AppController : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

  Q_PROPERTY(TaskModel* tasks READ tasks CONSTANT)
  Q_PROPERTY(EventModel* events READ events CONSTANT)
  Q_PROPERTY(PersonModel* people READ people CONSTANT)
  // The People rail's model: `people` minus everyone in the "idle" state. See
  // ActivePeopleModel.
  Q_PROPERTY(ActivePeopleModel* activePeople READ activePeople CONSTANT)
  Q_PROPERTY(QVariantList statuses READ statuses NOTIFY statusesChanged)
  // status id → task count, in one pass. The rail and the top bar read this
  // instead of calling countByStatus once per badge.
  Q_PROPERTY(QVariantMap statusCounts READ statusCounts NOTIFY statusCountsChanged)
  // task id → title for every task in the profile, archived included. The
  // rendered markdown shows a "#APP-12" mention as its title (APP-121).
  Q_PROPERTY(QVariantMap taskTitles READ taskTitles NOTIFY taskTitlesChanged)
  // The active profile's saved views, in sidebar order: [{id, name, query,
  // priorities, sort, archived, showDone, view, problems}] — `problems` is what
  // the search box would flag in the query (a deleted column, a typo).
  Q_PROPERTY(QVariantList savedViews READ savedViews NOTIFY savedViewsChanged)
  // view id → how many tasks opening it shows. One pass for all views, cached
  // until a task, a column, the day or the views change.
  Q_PROPERTY(QVariantMap savedViewCounts READ savedViewCounts NOTIFY savedViewCountsChanged)
  // Moves at local midnight, on resume and on a clock or zone change: every
  // "today" in the UI binds to this, so after midnight T goes to the new day.
  Q_PROPERTY(QDate today READ today NOTIFY todayChanged)
  // provider id → { name, icon, color } for the badge on a mirrored ticket
  // (HEAP-117). Constant and cheap: a board delegate reads this per card, and
  // integrationCatalog() rebuilds every provider's field list on each call.
  Q_PROPERTY(QVariantMap providerBadges READ providerBadges CONSTANT)

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
  // The notes of the active profile, without their bodies. `notesState` is the
  // body of whichever one is open, so everything that reads it keeps working.
  Q_PROPERTY(NoteModel* notes READ notes CONSTANT)
  Q_PROPERTY(QString activeNoteId READ activeNoteId WRITE setActiveNoteId NOTIFY activeNoteChanged)
  Q_PROPERTY(QString appSettingsJson READ appSettingsJson WRITE setAppSettingsJson NOTIFY appSettingsJsonChanged)
  Q_PROPERTY(bool hasPendingUndo READ hasPendingUndo NOTIFY pendingUndoChanged)
  Q_PROPERTY(bool canRedo READ canRedo NOTIFY pendingUndoChanged)

  // ---- Onboarding (first run) ----
  // welcomeSeen: the welcome dialog has been shown/dismissed at least once.
  // demoActive: the profile is still the seeded demo, so the "this is demo
  // data" banner should offer to start fresh. Both persist in the settings blob.
  Q_PROPERTY(bool welcomeSeen READ welcomeSeen NOTIFY onboardingChanged)
  Q_PROPERTY(bool demoActive READ demoActive NOTIFY onboardingChanged)

  Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
  // Calendars read from a link (APP-118), with how their last fetch went.
  Q_PROPERTY(QVariantList calendarSubscriptions READ calendarSubscriptions NOTIFY calendarSubscriptionsChanged)
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
  // In-app update (APP-125). canInstall: this copy is one heap can update
  // itself (installer, portable zip, heap.app, AppImage) and the release has
  // its package; otherwise "Download" opens the release page as before.
  // phase: "" | "downloading" | "verifying" | "ready" | "installing" | "error".
  // sha256: the checksum the package was verified against, once "ready".
  Q_PROPERTY(bool updateCanInstall READ updateCanInstall NOTIFY updateStatusChanged)
  Q_PROPERTY(QString updatePhase READ updatePhase NOTIFY updateStatusChanged)
  Q_PROPERTY(double updateProgress READ updateProgress NOTIFY updateProgressChanged)
  Q_PROPERTY(QString updateSha256 READ updateSha256 NOTIFY updateStatusChanged)

  // Per tracker: { offline: bool, outOfScope: int }. `offline` is set while
  // the token endpoint or the tracker cannot be reached and heap is retrying
  // — the card stays connected. `outOfScope` counts cards left behind by a
  // filter change (repo, JQL…), which the card offers to archive.
  Q_PROPERTY(QVariantMap integrationStates READ integrationStates NOTIFY integrationStatesChanged)
  // A tracker or directory pull is out and has not answered yet (APP-186).
  // The header shows it only once it has taken long enough to notice.
  Q_PROPERTY(bool syncing READ syncing NOTIFY syncingChanged)
  // Cards a sync brought in that the user has not looked at yet (APP-180):
  // read isTaskUnseen(id) with this in the binding, so a card follows.
  Q_PROPERTY(int unseenRevision READ unseenRevision NOTIFY unseenTasksChanged)
  // The cards the latest sync brought in, which `is:new` filters to.
  Q_PROPERTY(QStringList syncNewTaskIds READ syncNewTaskIds NOTIFY syncNewTaskIdsChanged)
  // The event log (APP-187), newest first: { id, at, kind, message, taskIds,
  // route, count }. This session only, at most 100 entries.
  Q_PROPERTY(QVariantList eventLog READ eventLog NOTIFY eventLogChanged)

  // ---- Git focus banner ----
  Q_PROPERTY(QString focusedTaskId READ focusedTaskId NOTIFY focusedGitChanged)
  Q_PROPERTY(QString focusedBranch READ focusedBranch NOTIFY focusedGitChanged)
  Q_PROPERTY(QString focusedRepo READ focusedRepo NOTIFY focusedGitChanged)
  Q_PROPERTY(QVariantMap focusedRepoState READ focusedRepoState NOTIFY focusedGitChanged)
  Q_PROPERTY(bool focusedBannerDismissed READ focusedBannerDismissed NOTIFY focusedGitChanged)
  // Settings → Git → "Show whose move" (APP-156). On by default: it is a fact
  // read off the PR, not a nudge.
  Q_PROPERTY(bool showWhoseMove READ showWhoseMove NOTIFY showWhoseMoveChanged)

  // ---- Storage health (PLAT-1/4/5) ----
  // "ok", "unreadable" (state.json exists but could not be opened: read-only
  // session, never saved over), "tooNew" (written by a newer heap: read-only),
  // or "writeFailed" (the last save did not reach disk; retried with backoff).
  // storageMessage is the localized banner text, reason included.
  Q_PROPERTY(QString storageState READ storageState NOTIFY storageStateChanged)
  Q_PROPERTY(QString storageMessage READ storageMessage NOTIFY storageStateChanged)

 public:
  explicit AppController(QObject* parent = nullptr);
  ~AppController() override;

  // A command-line run (`heap add`, `heap done` with no window open, see
  // src/cli): the same models and save path, but no tray icon, global
  // hotkeys, git watcher, tracker sync, calendar fetches or update checks.
  // Set before the controller is constructed.
  static void setHeadless(bool headless) {
    s_headless = headless;
  }

  static bool isHeadless() {
    return s_headless;
  }

  // `heap done` sent to the open window goes through moveTask() like a drag
  // does. The CLI executor mutes the sound palette (APP-177) around it: only
  // the user's own action in this window makes a sound.
  void setSoundMuted(bool muted) {
    m_soundMuted = muted;
  }

  // Settings → Sound: the "done" sound once at `volume` (0–100), so the user
  // hears what the slider set. Asked for, so quiet hours do not hold it.
  Q_INVOKABLE void previewSound(int volume);

  Q_INVOKABLE void flushSave();

  QString storageState() const {
    return m_storageState;
  }

  QString storageMessage() const {
    return m_storageMessage;
  }

  // The banner's Retry: re-reads an unreadable state.json (and loads it), or
  // writes a failed save again now.
  Q_INVOKABLE void retryStorage();
  // The banner's Dismiss, for the two states that only report what happened
  // at startup ("recovered" from a backup, "damaged" with none): nothing is
  // wrong any more, so the user may put the message away (PLAT-6).
  Q_INVOKABLE void dismissStorageNotice();

  TaskModel* tasks() {
    return &m_tasks;
  }

  EventModel* events() {
    return &m_events;
  }

  PersonModel* people() {
    return &m_people;
  }

  ActivePeopleModel* activePeople() {
    return &m_activePeople;
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
  // The same write as one entry on the undo stack, labelled with what an undo
  // says it restored. The docs catalogue's deletions go through here so they
  // share Ctrl+Z and the stack with everything else.
  Q_INVOKABLE void setDocsStateUndoable(const QString& v, const QString& label);

  NoteModel* notes() {
    return &m_notes;
  }

  QString activeNoteId() const {
    return m_activeNoteId;
  }

  void setActiveNoteId(const QString& id);

  // One note's body. The list model deliberately does not carry bodies: fifty
  // notes would mean fifty documents crossing the QML boundary on a repaint.
  Q_INVOKABLE QString noteBody(const QString& id) const;

  // Creating one returns its id so a caller can open it straight away.
  Q_INVOKABLE QString newNote(const QString& title = QString(), const QString& folder = QString());
  Q_INVOKABLE void renameNote(const QString& id, const QString& title);
  Q_INVOKABLE void deleteNote(const QString& id);
  // APP-116: appends note `sourceId`'s text below note `targetId`'s and
  // removes the source; links to the source now point at the target. One
  // undo step. False when either is missing or they are the same note.
  Q_INVOKABLE bool mergeNotes(const QString& sourceId, const QString& targetId);
  Q_INVOKABLE void setNoteBody(const QString& id, const QString& body);
  Q_INVOKABLE void setNotePinned(const QString& id, bool pinned);
  Q_INVOKABLE void moveNoteToFolder(const QString& id, const QString& folder);
  // Every folder in use, sorted, for a tree or a picker.
  Q_INVOKABLE QStringList noteFolders() const;
  // Re-file every note in `folder` (and its subfolders) under `newName`; an
  // empty name files them at the root. One undo step; returns how many moved.
  Q_INVOKABLE int renameNoteFolder(const QString& folder, const QString& newName);
  // Remove the folder, keeping its notes: they move one level up.
  Q_INVOKABLE int removeNoteFolder(const QString& folder);

  // ── Notes as a folder of .md files ──
  //
  // Import returns a summary rather than a bool, for the same reason .ics does:
  // a vault that brought in forty notes and skipped two is neither a success
  // nor a failure. Keys: imported, updated, unchanged, kept (edited here, not
  // on disk), conflicts (edited in both: the file arrives as a copy), skipped,
  // files, folder, warnings. The whole import is one undo step.
  Q_INVOKABLE QVariantMap importNotesFolder(const QUrl& folderUrl);
  // The same summary without changing anything, for a confirm step.
  Q_INVOKABLE QVariantMap previewNotesFolder(const QUrl& folderUrl);
  // Writes into a new folder inside `folderUrl` — named `subfolder`, or dated
  // when that is empty, with a suffix when the name is taken — so an export
  // never overwrites a file. Keys: written, skipped, folder.
  Q_INVOKABLE QVariantMap exportNotesFolder(const QUrl& folderUrl, const QString& subfolder = QString());

  // ── Links between notes ──
  //
  // What `[[target]]` points at, from the note it was written in. Returns
  // { kind: "note"|"heading"|"missing", noteId, heading, title }. The caller
  // opens the note or scrolls to the heading; "missing" is an offer to create
  // it, because a broken link is usually a note somebody meant to write.
  Q_INVOKABLE QVariantMap resolveNoteLink(const QString& target) const;
  // Which notes link to this one: [{ noteId, title, line, text }, …].
  Q_INVOKABLE QVariantList backlinksToNote(const QString& noteId) const;
  // Targets in the open note that nothing answers to.
  Q_INVOKABLE QStringList unresolvedNoteLinks() const;
  // Create the note a broken link was asking for, named after it, and open it.
  Q_INVOKABLE QString createNoteForLink(const QString& target);

  // Today's note, created on first use. A daily note that has to be made by
  // hand is one people stop making.
  Q_INVOKABLE QString openDailyNote();

  // ── Doc pages ──
  //
  // Docs was a catalog of one-line things. A page is where the paragraph
  // explaining why the link matters goes. Same shape as notes: the model
  // carries no bodies, and `docPageBody(id)` fetches one.
  Q_PROPERTY(DocPageModel* docPages READ docPages CONSTANT)
  Q_PROPERTY(QString activeDocPageId READ activeDocPageId WRITE setActiveDocPageId NOTIFY activeDocPageChanged)

  DocPageModel* docPages() {
    return &m_docPages;
  }

  QString activeDocPageId() const {
    return m_activeDocPageId;
  }

  void setActiveDocPageId(const QString& id);

  Q_INVOKABLE QString docPageBody(const QString& id) const;
  Q_INVOKABLE QString newDocPage(const QString& title = QString(), const QString& parentId = QString());
  Q_INVOKABLE void renameDocPage(const QString& id, const QString& title);
  Q_INVOKABLE void setDocPageBody(const QString& id, const QString& body);
  // Deleting a page takes its subtree: a page whose parent is gone would be
  // unreachable in the tree and invisible everywhere else.
  Q_INVOKABLE void deleteDocPage(const QString& id);
  // Re-parent and re-order in one call, because dragging a page in a tree does
  // both at once. `beforeId` is the sibling to land above, empty for last.
  Q_INVOKABLE void moveDocPage(const QString& id, const QString& newParentId, const QString& beforeId);
  // The pages under `parentId`, in order — what a tree row expands into.
  Q_INVOKABLE QVariantList docPageChildren(const QString& parentId) const;

  QString notesState() const {
    return m_notesState;
  }

  void setNotesState(const QString& v);

  // QuickCapture for Notes: appends `text` to notesState separated by a
  // timestamped horizontal-rule header. First entry gets the heading only
  // (no leading HR — there is nothing to separate from yet).
  Q_INVOKABLE void appendNoteEntry(const QString& text);
  // The title of the note appendNoteEntry() writes into, so the quick-note
  // popup can say where the text will land before it does.
  Q_INVOKABLE QString quickNoteTarget() const;

  // Note wiki-links (HEAP-79). Headings feed [[…]] autocomplete; backlinks list
  // which lines reference each [[target]]; the offset lets the editor jump to a
  // heading. The caller passes the live editor text so results reflect unsaved
  // edits (the pure logic lives in heap::notes and is unit-tested there).
  Q_INVOKABLE QStringList noteHeadings(const QString& markdown) const;
  Q_INVOKABLE QVariantList noteBacklinks(const QString& markdown) const;
  Q_INVOKABLE int noteHeadingOffset(const QString& markdown, const QString& heading) const;
  // The open note's own [[links]], grouped by target like noteBacklinks(), each
  // resolved against every note: { target, kind: note|heading|missing, noteId,
  // heading, resolved, refs: [{ line, text }] }.
  Q_INVOKABLE QVariantList outgoingNoteLinks(const QString& markdown) const;
  // { lines, mentions, tickets } for the editor's header.
  Q_INVOKABLE QVariantMap noteStats(const QString& markdown) const;

  // ---- Attachments (AppControllerAttachments.cpp, storage/Attachments.h) ----
  // Files go into <dataDir>/attachments under a content hash; a task lists
  // them, a note or description links them as "attachments/<id>".
  QString attachmentsDir() const;
  // Stores files (file:// URLs or paths) without attaching them to anything —
  // a new task's draft, a note that is about to link them. Returns one
  // { id, name, size, mime, isImage, ref } per stored file; a refused file is
  // left out and named in a toast. `intoText`: the caller links them from an
  // editor's text, whose own undo can bring the link back after it is deleted,
  // so the cleanup keeps them for the rest of the session (KNOW-3).
  Q_INVOKABLE QVariantList importAttachments(const QVariantList& urls, bool intoText = false);
  // Stores the files and appends them to the task, as one undo step. Returns
  // how many were attached (a file the task already has counts once).
  Q_INVOKABLE int attachFilesToTask(const QString& taskId, const QVariantList& urls);
  // Detaches one file: one undo step. The bytes stay until the cleanup.
  Q_INVOKABLE bool removeTaskAttachment(const QString& taskId, const QString& attachmentId);
  // The task's files for the editor's chips: the stored metadata plus
  // { exists, sizeText, isImage, ref }.
  Q_INVOKABLE QVariantList taskAttachments(const QString& taskId) const;
  // Chip data for a draft's list or for the files a piece of markdown links.
  Q_INVOKABLE QVariantList describeAttachments(const QVariantList& attachments) const;
  Q_INVOKABLE QVariantList markdownAttachments(const QString& markdown) const;
  // Opens a stored file in its default application. Returns "opened",
  // "confirm" (a type that runs something: ask, then call again with
  // confirmed), "missing" or "invalid".
  Q_INVOKABLE QString openAttachment(const QString& id, bool confirmed = false);
  // Shows the file in the system file manager.
  Q_INVOKABLE bool revealAttachment(const QString& id);
  // The file:// URL of a stored file, for a preview; empty when missing.
  Q_INVOKABLE QUrl attachmentUrl(const QString& id) const;
  // Paste: an image on the clipboard is saved as a PNG, copied files are
  // stored as they are. Empty when the clipboard holds neither, so the caller
  // falls back to pasting text. What it stores is linked from text, as with
  // importAttachments(urls, true).
  Q_INVOKABLE bool clipboardHasAttachment() const;
  Q_INVOKABLE QVariantList importClipboardAttachments();
  // Settings → Data: files no task, note, page or undo step refers to, and
  // that no text has linked since the app started (m_attachmentsLinkedThisSession).
  // { count, bytes, sizeText }.
  Q_INVOKABLE QVariantMap unusedAttachments() const;
  // Deletes them. Returns what unusedAttachments() said, as it was removed.
  Q_INVOKABLE QVariantMap cleanUpUnusedAttachments();
  Q_INVOKABLE QString formatBytes(double bytes) const;

  QString appSettingsJson() const {
    return m_appSettingsJson;
  }

  void setAppSettingsJson(const QString& v);

  // Kept under the old name because QML and the toast bind to it; it now means
  // "the undo stack is not empty" rather than "a five-second slot is armed".
  bool hasPendingUndo() const {
    return m_undo.canUndo();
  }

  bool canRedo() const {
    return m_undo.canRedo();
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
  // Settings -> Data -> "Reset all settings" (UX-5): preferences go back to a
  // new install's (heap. ink + soft contrast included). Kept: the profile
  // card, tracker connections, watched repositories, your own themes, window
  // and panel layout, and anything the Settings page does not own. Undoable
  // through undoSettingsReset() for as long as the toast offers it.
  Q_INVOKABLE void resetSettingsToDefaults();
  Q_INVOKABLE void undoSettingsReset();
  // Re-open the welcome guide on demand (Settings → Help "Replay"). Purely a UI
  // request — it does NOT touch welcomeSeen/demoActive or any persisted state.
  Q_INVOKABLE void replayWelcome();

  // ---- Task ops ----
  Q_INVOKABLE void moveTask(const QString& id, const QString& newStatus);
  // Manual order: place `id` in `statusId` immediately above `beforeTaskId`,
  // or at the end of the column when that is empty. This is what a drop
  // between two cards calls; moveTask() is the "somewhere in that column"
  // form and leaves the position alone.
  Q_INVOKABLE void moveTaskTo(const QString& id, const QString& statusId, const QString& beforeTaskId);
  // Same, for every selected task, preserving their order relative to one
  // another.
  Q_INVOKABLE void moveSelectedTasksTo(const QString& statusId, const QString& beforeTaskId);
  Q_INVOKABLE QVariantMap newTaskDraft(const QString& statusId) const;
  // The draft QuickCapture saves: newTaskDraft in the To Do column, with the
  // profile's id prefix like any other task. \p ticketKey, when the text named
  // a tracker ticket ("LTE-2398 fix login") and no task has that id yet, is
  // the id instead.
  Q_INVOKABLE QVariantMap newQuickTaskDraft(const QString& ticketKey = QString()) const;
  // The whole task QuickCapture makes of `raw`: newQuickTaskDraft with the
  // title, "// description", priority, #labels and the date the text names
  // (cut out of the title, read against `reference`, now when invalid). The
  // popup and `heap add` both save this, so they cannot read text apart.
  Q_INVOKABLE QVariantMap quickTaskDraft(const QString& raw, const QDateTime& reference = QDateTime()) const;
  // Reusable task/checklist templates (HEAP-77). taskTemplates lists the
  // built-ins ({name, title, desc}); createTaskFromTemplate drops a pre-filled
  // task (checklist in the description) onto the board.
  Q_INVOKABLE QVariantList taskTemplates() const;
  Q_INVOKABLE void createTaskFromTemplate(const QString& name);
  // False when the draft was refused (taken or empty id, empty title) — the
  // editor then stays open on it.
  Q_INVOKABLE bool saveTask(const QVariantMap& draft);
  // Send a card's current status to its tracker again, after a failed push.
  Q_INVOKABLE void retryTrackerPush(const QString& taskId);
  // A title/description/priority both sides changed: take the tracker's
  // version of every conflicting field (true), or keep the local one and stop
  // flagging it (false). Undoable.
  Q_INVOKABLE void resolveTrackerConflict(const QString& taskId, bool useTracker);
  // One field of it ("title" | "body" | "priority" | "status"). Keeping my
  // status sends it to the tracker; taking the tracker's drops the unsent move.
  Q_INVOKABLE void resolveTrackerConflictField(const QString& taskId, const QString& field, bool useTracker);
  // Archive every card of this tracker the current filter no longer covers.
  Q_INVOKABLE void archiveOutOfScope(const QString& providerId);
  // Settings → Integrations → Health (APP-164): one row per connected
  // tracker — { id, name, lastOk, items, failing, error, errorDetail,
  // errorAge, expiry, offline }, times relative to now, text in the UI
  // language. Read-only.
  Q_INVOKABLE QVariantList integrationHealth() const;
  QVariantList integrationHealthAt(const QDateTime& now) const;

  // ---- Sync visibility (APP-180/186/187) ----
  bool syncing() const {
    return !m_syncInFlight.isEmpty();
  }

  int unseenRevision() const {
    return m_unseenRevision;
  }

  QStringList syncNewTaskIds() const {
    return m_syncNewIds;
  }

  // A card a sync brought in, not yet opened or reached by the cursor.
  Q_INVOKABLE bool isTaskUnseen(const QString& taskId) const {
    return m_unseenTaskIds.contains(taskId);
  }

  // Opened, or the keyboard cursor landed on it: the dot goes.
  Q_INVOKABLE void markTaskSeen(const QString& taskId);
  // What a pull does for the cards it adds; public so the QML tests can set
  // the state up the way a sync does.
  Q_INVOKABLE void markTasksUnseen(const QStringList& taskIds);

  QVariantList eventLog() const {
    return m_eventLog.toVariantList();
  }

  // Adds an entry to the event log. QML uses it for the failures it reports
  // itself (an import that did not read); everything C++ reports is logged
  // where it is said.
  Q_INVOKABLE void logEvent(const QString& kind, const QString& message, const QStringList& taskIds = {}, const QString& route = QString());
  // What happened to a task, newest first: [{ at, kind, from, to, sync }]
  // (APP-165). kind: created | status | title | priority | due | scheduled
  // | pushed. Capped per task; see history/TaskHistory.h.
  Q_INVOKABLE QVariantList taskHistory(const QString& taskId) const;
  // Whether a link from user or tracker content may open without asking. See
  // heap::md::isSafeLink.
  Q_INVOKABLE bool isSafeLink(const QString& url) const;
  // False when tokens live in secrets.json in the data folder rather than the
  // OS keychain (portable --data-dir run, or a build without QtKeychain).
  Q_INVOKABLE bool secretsInKeychain() const;
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
  // The filters the views show tasks under (search or query, priority chips,
  // archived, the timeline's done toggle). Selected tasks they hide leave the
  // selection, now and before every bulk action, so Delete never reaches a
  // card the user cannot see (TASKS-13, audit 2026-09-30).
  Q_INVOKABLE void setSelectionFilter(const QString& search, const QStringList& priorities, bool showArchived, bool hideDone = false);

  // Bulk ops — operate on the current selection set.
  Q_INVOKABLE void deleteSelectedTasks();
  Q_INVOKABLE void moveSelectedTasksToStatus(const QString& statusId);
  Q_INVOKABLE void setSelectedTasksArchived(bool archived);
  // Priority and labels without the editor (src/AppControllerTaskEdits.cpp):
  // one card from its menu, or every selected card at once. Each is one undo
  // step. A label is added or removed by name ("#infra" works too).
  Q_INVOKABLE void setTaskPriority(const QString& taskId, const QString& priority);
  Q_INVOKABLE void setSelectedTasksPriority(const QString& priority);
  Q_INVOKABLE void setSelectedTasksLabel(const QString& label, bool present);
  // The filter bar's counters under the filters the user set: search text or
  // query, priority chips, the archived toggle. { total, active, blocked,
  // review }. `hideDone` is the timeline's "Show done" off. `rev` is unused;
  // binding it to statusCounts re-evaluates the counts whenever tasks change.
  Q_INVOKABLE QVariantMap filteredCounts(
      const QString& search, const QStringList& priorities, bool showArchived, bool hideDone = false, const QVariant& rev = {}) const;

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

  // Built from a key at read time, so a language switch repaints it (it
  // used to be the English sentence stored when the check finished).
  QString updateStatus() const {
    if(m_updateStatus.isEmpty()) {
      return {};
    }
    const QString text = tr_(m_updateStatus);
    if(m_updateStatusArg.isEmpty()) {
      return text;
    }
    if(m_updateStatus == QLatin1String("update.verified")) {
      return text.arg(m_updateStatusArg, m_updateSha256);  // version, checksum
    }
    // The argument is itself a key when it names a reason ("update.offline").
    return text.arg(m_updateStatusArg.startsWith(QLatin1String("update.")) ? tr_(m_updateStatusArg) : m_updateStatusArg);
  }

  bool updateCanInstall() const;

  QString updatePhase() const {
    return m_updatePhase;
  }

  double updateProgress() const {
    return m_updateProgress;
  }

  QString updateSha256() const {
    return m_updateSha256;
  }

  // ---- Diagnostics (HEAP-64) ----
  // Open the rotating-log directory in the system file manager.
  Q_INVOKABLE void openLogsFolder() const;
  // Open a pre-filled GitHub "new issue" page carrying version / OS / Qt
  // version / recent-log-tail diagnostics, so a user can file a report in one
  // click.
  // The full diagnostics go to the clipboard, not into the URL.
  Q_INVOKABLE void reportAnIssue();
  // The body reportAnIssue() pre-fills, built from purely local sources: app
  // version, OS, Qt version, the log tail and the recovery log. Split out so the
  // no-network-egress guarantee can be exercised without opening a browser.
  // It travels in a URL, so the tails are short and scrubbed of the home
  // folder and user name (audit PLAT-28).
  Q_INVOKABLE QString issueReportBody() const;
  // The longer log and recovery tails, scrubbed the same way, for the
  // clipboard.
  Q_INVOKABLE QString issueDiagnostics() const;

  // How much one pull actually changed. An issue that came back identical
  // counts as neither, so a quiet auto-sync writes nothing and says so.
  struct MergeStats {
    int added = 0;
    int updated = 0;
    // Cards whose title or description was edited here while the tracker
    // changed the same field: the local text is kept and the user is told.
    int conflicts = 0;
    // Cards whose issue was missing from a complete pull under the same filter.
    int gone = 0;
    // Cards newly left outside a changed filter: kept, not "gone".
    int outOfScope = 0;
    // The keys of the cards behind `conflicts`, so the toast can name them.
    QStringList conflictKeys;
    // The heap ids of the cards behind `added`, in pull order, so the toast
    // can name them and "Show" can filter to them (APP-180).
    QStringList addedIds;
  };

  // Fold a batch of pulled external tasks into the model. providerId tags the
  // task's externalProvider; idPrefix seeds ids for newly-created local tasks.
  // Public so the sync merge can be exercised without a live tracker.
  // `complete` says the batch holds every issue the provider's filter
  // matches; only then is a missing issue marked as gone upstream.
  // `goneCandidates`, when given, collects the external ids that would be
  // marked gone instead of marking them: the provider can look them up first
  // (INT-6, audit 2026-09-30).
  MergeStats mergeExternalTasks(const QString& providerId,
                                const QString& idPrefix,
                                const QVector<heap::integrations::ExternalTask>& issues,
                                bool complete = false,
                                QStringList* goneCandidates = nullptr);
  // What a lookup of those candidates found. An issue that still exists only
  // left the filter — closed under "statusCategory != Done", say: it is merged
  // like any pulled issue (so a closed one moves to Done) and marked outside
  // the filter. One the tracker says does not exist is gone. An id in neither
  // list (the lookup failed) is left for the next sync.
  MergeStats settleMissingIssues(const QString& providerId,
                                 const QString& idPrefix,
                                 const QVector<heap::integrations::ExternalTask>& found,
                                 const QStringList& missing);

  // Fold fetched contacts into the active profile's Docs contact list and, for
  // the people actually talked to, the People rail. Returns how many contacts
  // were added or changed — zero means nothing is written, so an idempotent
  // re-sync does not churn docsState. Public for the same reason as
  // mergeExternalTasks: the rules are worth testing without a live server.
  int mergeExternalContacts(const QString& providerId, const QVector<heap::integrations::ExternalContact>& contacts);

  // The one message for one pull's stats: a toast, an event-log entry and,
  // when it brought cards, syncNews naming them (APP-180). Quiet when a
  // follow-up pull found nothing. Public so the wording can be tested
  // without a live tracker.
  void reportSync(const QString& label, const MergeStats& stats, bool settlePull);

  // ---- Durability audit (HEAP-156) ----
  // Every quarantine / backup recovery / failed write, oldest first. Local file,
  // never uploaded.
  Q_INVOKABLE QVariantList recoveryLog() const;
  // Copy the recovery log to `fileUrl` so it can be attached to a bug report.
  Q_INVOKABLE bool exportRecoveryLog(const QUrl& fileUrl);

  // Test seam: replaces the atomic QSaveFile write behind saveStateNow() so the
  // fault-injection harness can truncate, corrupt, or drop the rename. Pass an
  // empty std::function to restore the default writer.
  using StateWriter = std::function<bool(const QString& path, const QByteArray& bytes)>;
  static void setStateWriterForTesting(StateWriter writer);

  // ---- Auto-update (HEAP-63) ----
  // Manually trigger a GitHub-Releases check (Settings → About → "Check for
  // updates"). Result surfaces via updateStatus + the updateAvailable toast.
  Q_INVOKABLE void checkForUpdates();
  // Open the latest release's page in the browser — the "Download" action.
  Q_INVOKABLE void openLatestRelease() const;
  // APP-125: download this copy's package from the latest release and check it
  // against the release's SHA256SUMS; then installUpdate() puts it in place
  // and quits (heap starts again on the new version).
  Q_INVOKABLE void downloadUpdate();
  Q_INVOKABLE void cancelUpdateDownload();
  Q_INVOKABLE void installUpdate();

  // ---- Tracker sync (HEAP-74/75) ----
  QVariantMap providerBadges() const;
  // "GitHub" for "github". The id itself when nothing in the catalog matches.
  QString providerDisplayName(const QString& providerId) const;
  // The issue URL for a task, or an empty URL when it has none or the tracker
  // handed over something that is not a web address. Split out from
  // openTaskExternal so the scheme check is testable without a browser: the
  // value is tracker-supplied, and a Jira session with no site yields a bare
  // "/browse/KEY".
  QUrl externalUrlFor(const QString& taskId) const;
  // Open a mirrored task's issue in the default browser. False (with a toast)
  // when the task has no usable issue URL.
  Q_INVOKABLE bool openTaskExternal(const QString& taskId);
  // Read a mirrored task's most recent comments (HEAP-117). On demand, never
  // stored: the answer arrives on ticketCommentsLoaded and lives only as long
  // as whatever is showing it. A GET, so it cannot change the issue.
  Q_INVOKABLE void fetchTicketComments(const QString& taskId);

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
  // Mark a provider connected from the credentials typed into its card. The
  // counterpart to connectOAuth for every card that is filled in by hand: an
  // OAuth-capable provider used with a personal access token, a self-hosted
  // Jira the Atlassian gateway knows nothing about, a tracker with no browser
  // flow at all. Refuses (with a toast) while a required field is empty, and
  // drops any leftover browser session so the typed credentials are the ones
  // actually sent.
  Q_INVOKABLE void connectIntegrationManually(const QString& providerId);
  // Drop a provider back to disconnected. For a browser/session sign-in this
  // also discards the tokens and clears authMode — otherwise a token pasted
  // afterwards would still be sent as a Bearer, which GitLab (PRIVATE-TOKEN)
  // and ClickUp (raw header) reject.
  Q_INVOKABLE void disconnectIntegration(const QString& providerId);
  // Sign in to a directory provider with a username and password (Mattermost,
  // where most corporate servers have personal access tokens switched off).
  // `credentials` holds the descriptor's loginFields; the password is used for
  // the one request and never persisted — only the session token it returns is.
  Q_INVOKABLE void connectWithCredentials(const QString& providerId, const QVariantMap& credentials);
  // Remember that the user deleted an imported contact, so the next sync does
  // not re-add it. Called by DocsView when a contact carrying an external id is
  // deleted, and undone by restoreExternalContact.
  Q_INVOKABLE void dismissExternalContact(const QString& providerId, const QString& externalId);
  Q_INVOKABLE void restoreExternalContact(const QString& providerId, const QString& externalId);
  // The same for a mirrored issue: deleting the task is how the user says "not
  // mine", and without this the next pull simply puts it back. Recorded by
  // deleteTask, undone by the delete's undo and by restoreExternalTask.
  Q_INVOKABLE void dismissExternalTask(const QString& providerId, const QString& externalId);
  Q_INVOKABLE void restoreExternalTask(const QString& providerId, const QString& externalId);
  // The full integration catalogue (id, name, colour, fields, …) for the
  // Settings → Integrations cards. Data-driven from the provider registry.
  Q_INVOKABLE QVariantList integrationCatalog() const;
  // Secret (token/key) accessors — secrets live in the OS keychain, never in
  // state.json, so QML reads/writes them through these instead of the settings
  // blob.
  Q_INVOKABLE QString integrationSecret(const QString& providerId, const QString& field) const;
  Q_INVOKABLE bool hasIntegrationSecret(const QString& providerId, const QString& field) const;
  Q_INVOKABLE void setIntegrationSecret(const QString& providerId, const QString& field, const QString& value);

  // ---- Status mapping ----
  // StatusMap has always taken per-user overrides and has never been given
  // any: every sync called it with an empty map, so a tracker status heap's
  // built-in table does not recognise — "QA", "Needs triage", anything from a
  // custom Jira workflow — landed in "todo" with no way to say otherwise.
  //
  // The rows to offer: every distinct status this provider has actually sent,
  // recorded as issues are merged, each with the column it currently resolves
  // to and whether that is the user's choice or the built-in guess.
  // [{ status, column, overridden }], sorted by status.
  Q_INVOKABLE QVariantList statusMappingFor(const QString& providerId) const;
  // Map one of this provider's statuses onto a heap column. An empty or
  // unknown \p column clears the override and restores the built-in guess.
  // Remapping does not rewrite tasks already mirrored; the next sync does.
  Q_INVOKABLE void setStatusMapping(const QString& providerId, const QString& status, const QString& column);

  // ---- Notifications & automation ----
  Q_INVOKABLE void notify(const QString& title, const QString& body, const QString& kind = QString());
  // Post the given rich payload via the native notification backend.
  // `taskId` is the optional task tied to this toast — it is encoded into
  // the notification id so the action handlers can route back.
  Q_INVOKABLE void notifyTask(const QString& taskId, const QString& title, const QString& body, const QString& kind = QString());
  // notifyTask() judged at `now` rather than the wall clock: runAutomationAt()
  // decides quiet hours for its own moment, and so must what it posts.
  void notifyTaskAt(const QString& taskId, const QString& title, const QString& body, const QString& kind, const QDateTime& now);
  // The confirmation for something quick-captured from outside the app (the
  // global hotkeys' capture window). Unlike notify(), it is shown while a heap
  // window has focus — the capture window has it — and in quiet hours, since
  // the user just asked for it. Clicking it opens `taskId` when there is one.
  Q_INVOKABLE void notifyCapture(const QString& taskId, const QString& title, const QString& body);

  // An in-app toast from QML, for a view that refuses a key and says why.
  Q_INVOKABLE void showToast(const QString& message) {
    emit toast(message, QStringLiteral("info"));
  }
  // Slide the deadline of \p taskId forward by \p seconds (no-op if the
  // task currently has no deadline). Invoked by the "Snooze 1h" action.
  Q_INVOKABLE void snoozeDeadline(const QString& taskId, int seconds);

  // ---- Start at login (APP-154) ----
  // { supported, enabled, minimized }, read from the OS entry on every call so
  // Settings shows what the next login will really do. While the entry is off,
  // `minimized` is the remembered choice (settings.system.startMinimized).
  Q_INVOKABLE QVariantMap autostartState() const;
  // Writes or removes the OS entry and remembers the choice under
  // settings.system. Starting at login implies staying in the tray: an
  // unanswered close-to-tray question is answered "hide to tray". False (and
  // an error toast) when the OS refused the change.
  Q_INVOKABLE bool setAutostart(bool enabled, bool minimized);

  // ---- Reminder buttons (APP-155) ----
  // A heap://notify URI from a toast click, forwarded by the launch the shell
  // started (main.cpp). Routes to the same handlers as a native button.
  Q_INVOKABLE bool handleNotificationUri(const QString& uri);
  // A sample reminder with the real buttons, from Settings → Notifications,
  // shown even while heap has focus: it is how the user checks that the OS
  // lets heap's notifications through.
  Q_INVOKABLE void sendTestNotification();
  // Puts a shown reminder off: it comes back `minutes` after `now`, with the
  // same text, through the usual quiet-hours rules. Kept in snoozes.json.
  void snoozeReminderAt(const QString& notificationId, int minutes, const QDateTime& now);

  // Snoozed reminders waiting (tests).
  QVector<heap::notify::SnoozedReminder> pendingSnoozes() const {
    return m_snoozed;
  }

  // ---- Event ops ----
  // A fresh event id. Shared by the draft and the series edits, which both
  // need one and must not invent different shapes.
  static QString mintEventId();
  Q_INVOKABLE QVariantMap newEventDraft(double startHour, const QDate& date) const;
  Q_INVOKABLE void saveEvent(const QVariantMap& draft);
  Q_INVOKABLE void updateEvent(const QString& id, double start, double end, const QDate& date);
  Q_INVOKABLE void deleteEvent(const QString& id);

  // ── Recurrence ──
  //
  // A repeating event is stored once, as a master carrying an RRULE. The dates
  // it lands on are computed here rather than written out: a daily standup
  // would otherwise be a row per working day forever, and a merge conflict for
  // every one of them.
  //
  // `eventOccurrences` is what the views read — plain event maps with real
  // dates, plus `masterId` and `originalDate` on anything generated, so a click
  // can find the series again.
  Q_INVOKABLE QVariantList eventOccurrences(const QDate& from, const QDate& to) const;
  // The stored event behind an occurrence: the master, or the override that
  // stands in for it. Empty when there is none.
  Q_INVOKABLE QVariantMap eventSeriesMaster(const QString& masterId) const;

  // Scope is "this", "following" or "all" — the three answers every calendar
  // asks for when a repeating event is edited or deleted.
  Q_INVOKABLE void saveOccurrence(const QVariantMap& draft, const QString& scope);
  Q_INVOKABLE void deleteOccurrence(const QString& masterId, const QDate& occurrenceDate, const QString& scope);
  // A drag or a resize on the grid, answered with the same scope the editor
  // asks for. `occurrence` is the map eventOccurrences handed the view.
  // `deltaHours` moves the whole event (a day is 24), so the piece of an
  // overnight event after midnight moves the event it belongs to, by as much
  // as it was dragged. A resize sets a single-day occurrence's own edges.
  Q_INVOKABLE void moveOccurrence(const QVariantMap& occurrence, double deltaHours, const QString& scope);
  Q_INVOKABLE void resizeOccurrence(const QVariantMap& occurrence, double start, double end, const QString& scope);
  // The stored event as the editor reads it: every field, zone included.
  Q_INVOKABLE QVariantMap eventById(const QString& id) const;
  // Whether heap can expand this RRULE body — what the editor's custom field
  // checks before it saves.
  Q_INVOKABLE bool isValidRRule(const QString& rule) const;

  // ── .ics ──
  //
  // Import returns a summary rather than a bool: a file that brought in nine
  // events and skipped one is neither a success nor a failure, and the user
  // has to be told which. Keys: imported, updated, skipped, warnings.
  Q_INVOKABLE QVariantMap importIcs(const QUrl& fileUrl);
  Q_INVOKABLE bool exportIcsToFile(const QUrl& fileUrl) const;
  // "<install id>.heap": what qualifies this install's event ids as .ics UIDs,
  // so another heap's ev-2 is not taken for ours (TIME-25).
  QString icsUidDomain() const;

  // ── Calendar subscriptions (APP-118) ──
  // A calendar heap reads from a link — Outlook's published ICS address, or
  // Google's / iCloud's — and refreshes on its own. Read-only: its events are
  // "sub:<id>:…" and every event write refuses them. The link is a secret
  // (anyone holding it reads the calendar) and lives in the keychain; the
  // list itself is settings.calendars.subscriptions [{ id, name, minutes }].
  //
  // Each entry: { id, name, minutes, events, lastSync (ISO, "" = never),
  // error ("" = fine), busy }.
  QVariantList calendarSubscriptions() const;
  // { ok, id } or { ok: false, error }. Fetches straight away.
  Q_INVOKABLE QVariantMap addCalendarSubscription(const QString& name, const QString& link, int minutes);
  // The Outlook installed on this computer, read over COM (Windows): the way
  // in when an Exchange server will not publish a calendar as a link. Same
  // read-only subscription, kind "outlook", no link.
  Q_INVOKABLE bool outlookDesktopAvailable() const;
  Q_INVOKABLE QVariantMap addOutlookDesktopCalendar(int minutes);
  // Drops the subscription, its link and the events it brought.
  Q_INVOKABLE void removeCalendarSubscription(const QString& id);
  Q_INVOKABLE void refreshCalendarSubscription(const QString& id);
  Q_INVOKABLE bool isSubscriptionEvent(const QString& id) const;
  // The name of the calendar an event came from, "" for the user's own.
  Q_INVOKABLE QString subscriptionNameOf(const QString& eventId) const;
  // What a fetch does with the body it got, without the network: parse, then
  // replace the subscription's events. Returns how many events it now holds,
  // or -1 with `error` set when the text is not a calendar.
  int applyCalendarSubscriptionFeed(const QString& id, const QByteArray& body, QString* error = nullptr);
  // Replaces subscription `id`'s events with `incoming` (already prefixed).
  // Returns how many single events and series it now holds.
  int replaceSubscriptionEvents(const QString& id, const QVector<CalEvent>& incoming);
  Q_INVOKABLE void scheduleTask(const QString& taskId, double startHour, const QDate& date);
  // First hour on `date` where a block of `durationHours` does not land on top
  // of an existing event, starting from the workday (or from now, for today).
  // The "schedule this" menu item used to hardcode 14:00 and stack blocks.
  Q_INVOKABLE double nextFreeSlot(const QDate& date, double durationHours) const;
  // Books the task into the first gap on `date` that fits the block it will
  // actually get (its estimate, else the focus-block length).
  Q_INVOKABLE void scheduleTaskAtNextFreeSlot(const QString& taskId, const QDate& date);
  // How long a block for this task is, in minutes.
  Q_INVOKABLE int taskBlockMinutes(const QString& taskId) const;
  // A "doing" column gets a focus block for a card that enters it and gives
  // the future ones back when the card leaves. In Progress always is.
  Q_INVOKABLE bool isDoingStatus(const QString& statusId) const;
  Q_INVOKABLE void setStatusDoing(const QString& statusId, bool doing);
  Q_INVOKABLE QString scheduledLabelFor(const QString& taskId, const QDate& date) const;
  // The tasks a calendar range shows, pre-sorted by day, for the week and
  // month views: those due in [from, to] and those scheduled in it. Each map
  // carries the fields the views filter and draw with, plus `dueDay` and
  // `schedDay` — the day's offset from `from`, or -1. Only candidates have
  // their fields read, which is what keeps a 10k-task profile's week cheap.
  Q_INVOKABLE QVariantList calendarTasks(const QDate& from, const QDate& to, bool includeArchived) const;

  // ---- People ops ----
  Q_INVOKABLE void cyclePerson(const QString& id);
  Q_INVOKABLE void setPersonState(const QString& id, const QString& state);
  Q_INVOKABLE QVariantMap newPersonDraft() const;
  Q_INVOKABLE QVariantMap personById(const QString& id) const;
  // The person an "@handle" in a note names, or empty.
  Q_INVOKABLE QString personIdForHandle(const QString& handle) const;
  // Finding someone by what was typed (heap::text::personMatchRank): the id,
  // a login derived from the name ("r.losev", "roman.losev"), or the name's
  // words in either script ("roman lo", "роман"). personMatchRank is the
  // rank for one candidate (0 = no match); matchPeople is the active
  // profile's people, best first, at most `limit` of them, as
  // {id, name, role, color, rank}.
  Q_INVOKABLE int personMatchRank(const QString& query, const QString& name, const QString& id) const;
  Q_INVOKABLE QVariantList matchPeople(const QString& query, int limit) const;
  Q_INVOKABLE bool savePerson(const QVariantMap& draft);
  Q_INVOKABLE void deletePerson(const QString& id);

  // ---- People picker ----
  // Everyone the rail's "+" can put on the list: the profile's Docs contacts
  // and its People, folded into one row per human. A contact that already has
  // a Person behind it (`personId`, written by the Mattermost import) is that
  // Person's row, so a colleague imported from a DM is offered once, not twice.
  // Each entry carries { key, contactKey, personId, name, role, handle,
  // channel, color, state, source, active }.
  Q_INVOKABLE QVariantList pingCandidates() const;
  // The PersonEditor draft for a picked candidate. An existing Person opens as
  // itself, moved to "todo" when it was idle; a contact with no Person yet
  // opens as a new one carrying the contact's name, role and colour.
  Q_INVOKABLE QVariantMap pingDraftFor(const QVariantMap& candidate) const;
  // The draft behind "create contact «name»": a new Person plus, on save, a
  // Docs contact to find it by next time.
  Q_INVOKABLE QVariantMap newContactDraft(const QString& name) const;

  Q_INVOKABLE int pendingPeopleCount() const {
    return m_people.todoCount();
  }

  // ---- Status (kanban column) ops ----
  Q_INVOKABLE void addStatus(const QString& name, const QString& color = QString());
  Q_INVOKABLE void renameStatus(const QString& id, const QString& name);
  Q_INVOKABLE void setStatusColor(const QString& id, const QString& color);
  // Advisory limit on how many cards a column should hold. 0 = none.
  Q_INVOKABLE void setStatusWipLimit(const QString& id, int limit);
  // Auto-archive per column (APP-122): a card that has sat in the column for
  // `days` days goes to the archive; 0 = never. Done keeps its Settings →
  // Tasks slider as the one place its number lives; any other column stores
  // it on the column.
  Q_INVOKABLE int statusArchiveDays(const QString& id) const;
  Q_INVOKABLE void setStatusArchiveDays(const QString& id, int days);
  Q_INVOKABLE void moveStatus(const QString& id, int newIndex);
  Q_INVOKABLE void deleteStatus(const QString& id);

  // ---- Status counts ----
  // Every status' task count, built in one pass and cached until the model
  // changes. Prefer this over repeated countByStatus calls: the rail and the
  // top bar used to ask for six separate counts per task edit, each a full
  // scan. Archived tasks are not counted; "_total" is the live task count.
  QVariantMap statusCounts() const;

  QVariantMap taskTitles() const {
    return m_taskTitles;
  }

  // ---- Saved views (src/AppControllerSavedViews.cpp) ----
  // `state` is the filter state as Main.qml holds it: {query, priorities
  // (list or {P0: true} map), sort, archived, showDone, view}. Every mutation
  // is one undo step with a toast. Names are made unique ("Name (2)").
  QVariantList savedViews() const;
  QVariantMap savedViewCounts() const;
  // Returns the new view's id; "" when there is no profile.
  Q_INVOKABLE QString saveView(const QString& name, const QVariantMap& state);
  Q_INVOKABLE bool renameSavedView(const QString& id, const QString& name);
  // Overwrites the view's filters with `state`, keeping its name and place.
  Q_INVOKABLE bool updateSavedView(const QString& id, const QVariantMap& state);
  Q_INVOKABLE QString duplicateSavedView(const QString& id);
  Q_INVOKABLE bool deleteSavedView(const QString& id);
  // -1 = up, +1 = down; false at either end.
  Q_INVOKABLE bool moveSavedView(const QString& id, int delta);
  // {} when there is no such view.
  Q_INVOKABLE QVariantMap savedView(const QString& id) const;
  // True when `state` no longer matches the view — what shows it as modified.
  Q_INVOKABLE bool savedViewDiffers(const QString& id, const QVariantMap& state) const;

  // settingsMap() is private and also cached; this exists so a test can prove
  // the cache does not outlive the settings it was built from.
  QVariantMap settingsMapForTest() const {
    return settingsMap();
  }

  // Every task holding the status, archived ones included (what a column
  // delete re-homes).
  Q_INVOKABLE int countByStatus(const QString& statusId) const;

  // ---- Lookups ----
  Q_INVOKABLE QVariantMap taskById(const QString& id) const;

  // Compile what the user typed in the search box into something a view can
  // filter with. The board hands the raw text to TaskFilterProxy, which does
  // this in C++; the views that build their own JS arrays (archive, timeline,
  // week, month) call this instead, so one search box means the same thing
  // everywhere.
  //
  // Returns { isQuery, freeText, ids }: `freeText` is the loose words with the
  // clauses removed, already lowercased for SearchTextRole; `ids` lists the
  // tasks of the active profile that satisfy the clauses, and is meaningful
  // only when `isQuery` is true (with no clauses every task would be in it).
  Q_INVOKABLE QVariantMap compileSearch(const QString& text) const;

  // Does this text hold at least one clause? Parsing only — it never walks the
  // task list, so the search field can ask on every keystroke to show whether
  // it is filtering structurally.
  Q_INVOKABLE bool searchIsQuery(const QString& text) const;
  // The tokens of `text` that look like clauses but mean nothing (an unknown
  // field, column, priority or date), for the search box to point out.
  Q_INVOKABLE QStringList searchProblems(const QString& text) const;

  // The clause fields the search box understands ("deadline", "status", …),
  // sorted. For the hint under the field.
  Q_INVOKABLE QStringList searchFields() const;
  Q_INVOKABLE QString eventHourLabel(double hour) const;
  Q_INVOKABLE QString sprintLabel() const;
  Q_INVOKABLE QString humanDate(const QDate& date) const;
  // Displayed dates in the UI language (APP-188): the pattern of a named
  // style ("dayMonth", "weekdayDay", "longWeekday"… see text/LocaleFormat.h)
  // for `lang` (empty = the current one). QML formats through I18n.date(),
  // which passes its own lang so the binding repaints on a language switch.
  Q_INVOKABLE QString datePattern(const QString& style, const QString& lang = QString()) const;
  // "Oct 6" / "6 окт." and "Oct 6, 15:15" — the clock follows the 12h/24h
  // setting.
  Q_INVOKABLE QString dateLabel(const QDate& d, const QString& style) const;
  Q_INVOKABLE QString dateTimeLabel(const QDateTime& dt, const QString& style) const;

  // ---- Timeline / week helpers ----
  Q_INVOKABLE QString deadlineBucket(const QDate& deadline) const;  // overdue/today/tomorrow/thisweek/nextweek/later/nodl
  Q_INVOKABLE QString deadlineDiffLabel(const QDate& deadline) const;
  Q_INVOKABLE QString shortDate(const QDate& d) const;  // "Fri, May 15" / "пт, 15 мая"
  Q_INVOKABLE int isoWeekNumber(const QDate& d) const;

  // ---- Free-form datetime parser (heap chrono) ----
  Q_INVOKABLE QVariantMap parseDateTime(const QString& input, const QDateTime& reference = QDateTime()) const;
  Q_INVOKABLE QVariantList parseAllDateTimes(const QString& input, const QDateTime& reference = QDateTime()) const;

  // ---- Opt-in timing (APP-161, diag/PerfLog.h) ----
  // A popup calls this as it starts to show: span `name` (begun earlier by the
  // global hotkey, or now) ends on the next frame `item`'s window presents, and
  // is logged. A no-op unless HEAP_PERF_LOG=1 or --perf-log.
  Q_INVOKABLE void perfMarkShown(const QString& name, QObject* item) const;

  Q_INVOKABLE void copyToClipboard(const QString& text);

  // ---- Free-form text classification (used by QuickCapture / TaskEditor) ----
  // Returns one of "focus" | "sync" | "ticket" | "contact" | "none".
  Q_INVOKABLE QString classifyTaskKind(const QString& text) const;
  // For a "sync": the event type it books — "standup" | "oneone" | "sync" |
  // "none" (a one-off call or meeting).
  Q_INVOKABLE QString meetingType(const QString& text) const;
  // Returns { title, desc, handles: [..], ticketKey, priority }. With
  // keepTicketKey the key stays in the title (see heap::text::extractMeta).
  Q_INVOKABLE QVariantMap extractTaskMeta(const QString& text, bool keepTicketKey = false) const;
  // Suggest a slug-style person id ("e.zaharov") from a free-form name.
  // Avoids collisions with already-existing ids in the active profile
  // by appending "-2", "-3", … on conflict.
  Q_INVOKABLE QString suggestPersonId(const QString& name, const QString& exceptId = QString()) const;
  // The collision walk behind suggestPersonId(), over a base that is already
  // an id rather than a display name — a Mattermost handle, say, whose dots
  // the name slugifier would eat. Returns `base`, or `base-2`, `base-3`… when
  // somebody else already holds it.
  QString uniquePersonId(const QString& base, const QString& exceptId = QString()) const;

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
  // The Monday recap (WEAK PECAP): last week's column moves, grouped by
  // from -> to. { weekStart, weekEnd ("yyyy-MM-dd", end exclusive),
  // groups: [{ from, fromName, fromColor, to, toName, toColor,
  // tasks: [{ id, title, priority }] }] }, groups in board column order.
  Q_INVOKABLE QVariantMap weeklyRecap() const;
  // The same for the week before the one `today` falls in.
  Q_INVOKABLE QVariantMap weeklyRecapFor(const QDate& today) const;

  // Every recorded move of the active profile, oldest first.
  QVector<StatusChange> statusLog() const {
    return m_statusLog;
  }
  Q_INVOKABLE QString importProfileFromJson(const QString& jsonText, bool activate = true);
  Q_INVOKABLE QString importProfileFromFile(const QUrl& fileUrl, bool activate = true);

  Q_INVOKABLE QVariantList commandPaletteEntries() const;
  // Full text over every note and every doc page of every profile, one row per
  // section, in the palette's row shape: { kind: "note"|"docPage", label, sub,
  // body, profileId, noteId|pageId, line, color }. Every word of `query` must
  // appear; `limit` <= 0 means no limit.
  Q_INVOKABLE QVariantList searchFullText(const QString& query, int limit = 50) const;
  // Ids of the active profile's notes / doc pages whose title, folder or body
  // contain every word of `query` — what the list filters show.
  Q_INVOKABLE QStringList notesMatching(const QString& query) const;
  Q_INVOKABLE QStringList docPagesMatching(const QString& query) const;

  // ---- Backups ----
  Q_INVOKABLE QVariantList listBackups() const;
  Q_INVOKABLE bool restoreFromBackup(const QString& fileName);

  // ---- Time machine (APP-162, src/storage/Snapshots.h) ----
  // Hourly snapshots in <dataDir>/history, newest first: { name, at (ISO),
  // day ("yyyy-MM-dd"), time ("HH:mm"), sizeKb, tag, profiles, tasks, notes,
  // docs }. The counts come from each file's summary line, nothing is inflated.
  Q_INVOKABLE QVariantList listSnapshots() const;
  // One snapshot, read-only, next to the state as it is now: { ok, error,
  // name, at, profiles: [{ id, name, color, tasks, notes, docs, existsNow,
  // tasksAdded, tasksRemoved, tasksChanged, notesAdded, notesRemoved,
  // notesChanged }], totals: { the same six }, missing: [{ kind ("task" |
  // "note" | "doc"), id, title, profileId, profileName, profileExists }],
  // changed: [same shape] }. "Removed" = in the snapshot, gone now.
  Q_INVOKABLE QVariantMap previewSnapshot(const QString& name);
  // The whole state goes back to the snapshot. The state it replaces is
  // snapshotted first (tag "pre"), so a restore is itself restorable.
  Q_INVOKABLE bool restoreSnapshot(const QString& name);
  // The snapshot's profile `profileId` comes back as a new profile, "<name>
  // (restored HH:MM)", beside the current one. Returns the new id, "" on failure.
  Q_INVOKABLE QString restoreSnapshotProfile(const QString& name, const QString& profileId);
  // One task, note or doc page (`kind` "task" | "note" | "doc") from the
  // snapshot's profile `profileId` goes back into that profile: re-inserted
  // when it is gone, overwritten when it is there. Switches to the profile
  // first; undoable.
  Q_INVOKABLE bool restoreSnapshotItem(const QString& name, const QString& kind, const QString& profileId, const QString& itemId);
  // Writes the current state into history right now under `tag`. Returns the
  // file name, "" on failure.
  QString takeSnapshotNow(const QString& tag);
  QString historyDirPath() const;

  // ---- Shortcuts (rebindable keyboard catalog) ----
  QVariantList shortcuts() const {
    return m_shortcuts;
  }

  Q_INVOKABLE QString shortcutFor(const QString& id) const;
  Q_INVOKABLE QString defaultShortcutFor(const QString& id) const;
  Q_INVOKABLE QString shortcutDescription(const QString& id) const;
  Q_INVOKABLE QString shortcutLabel(const QString& id) const;
  // The catalog action holding `sequence` (or the built-in key that does, as a
  // catalog id or a builtin.* id shortcutLabel() names); empty when free.
  Q_INVOKABLE QString findShortcutConflict(const QString& id, const QString& sequence) const;

  // Only the built-in half of that: a key no rebinding can free.
  Q_INVOKABLE QString builtinShortcutConflict(const QString& id, const QString& sequence) const {
    return builtinShortcutOwner(id, normalizeSequence(sequence));
  }
  Q_INVOKABLE bool setShortcut(const QString& id, const QString& sequence);
  Q_INVOKABLE void resetShortcut(const QString& id);
  Q_INVOKABLE void resetAllShortcuts();
  // A control that has a catalogue shortcut was used with the mouse (APP-166).
  // The third time for an action, shortcutHintRequested fires — once, never
  // again for that action. Off with Settings → Shortcuts "Suggest shortcuts".
  Q_INVOKABLE void noteMouseAction(const QString& shortcutId);
  // Interface scale one step up (> 0), down (< 0) or back to 100 % (0) along
  // `steps` (Theme.scaleSteps), written to settings.appearance.uiScale like
  // Settings → Appearance → Scale does. Returns the new scale.
  Q_INVOKABLE double stepUiScale(int direction, const QVariantList& steps);
  // How the capture hotkey reaches heap from other apps (APP-171): "native"
  // (Windows, macOS), "x11", "portal" (Wayland), or "none" — then Settings
  // says to bind `heap --capture` in the desktop's own keyboard settings.
  Q_INVOKABLE QString globalHotkeyBackend() const;

  // ---- Undo ----
  // Undo/redo the last recorded operation. undoLastDeletion() is the old name,
  // kept because QML and several tests call it.
  Q_INVOKABLE void undo();
  Q_INVOKABLE void redo();

  Q_INVOKABLE void undoLastDeletion() {
    undo();
  }

  // The operation a toast is about to name: the one being recorded right now
  // (an undoable toast is emitted from inside its operation) or, failing that,
  // the newest undoable one. The toast keeps this and hands it to undoEntry().
  Q_INVOKABLE double undoSerialForToast() const;
  // Undo the operation recorded under `serial` — the toast's own action, not
  // whatever happens to be on top of the stack. Newer operations stay; when
  // one of them has changed the same thing since, nothing is reverted and the
  // user is told. Returns whether it was undone.
  Q_INVOKABLE bool undoEntry(double serial);

  // Group several calls from QML into one undo step (a quick-captured "sync"
  // is a task and its meeting). Nests; every begin needs its end.
  Q_INVOKABLE void beginUndoGroup(const QString& label);
  Q_INVOKABLE void endUndoGroup();

  Q_INVOKABLE void clearPendingUndo();

  // How many operations are currently undoable. Exposed for tests.
  Q_INVOKABLE int undoDepth() const {
    return m_undo.depth();
  }

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

  bool showWhoseMove() const {
    return m_showWhoseMove;
  }

  bool focusedBannerDismissed() const {
    return m_dismissedBranches.contains(m_focusedBranch);
  }

  Q_INVOKABLE void dismissGitBanner();
  Q_INVOKABLE void openFocusedTask();
  // Task-id prefixes the branch matcher should recognise: the configured local
  // one, plus the project key of every mirrored issue in the profile.
  Q_INVOKABLE QStringList collectPrefixes() const;
  // The configured local task-id prefix, upper-cased; "TASK" when unset or
  // not a usable ticket stem (a letter, then letters and digits).
  QString taskIdPrefix() const;
  // Every profile as it stands now: the stored copies, with the active one's
  // tasks and columns taken from the live models (the stored copy lags them).
  QVector<Profile> profilesSnapshot() const;
  // Turn what the matcher found in a branch name into a task id. For a local
  // task the key IS the id; a mirrored issue's id carries the provider, so it
  // is resolved through the tracker key instead.
  Q_INVOKABLE QString taskIdForBranchMatch(const QString& matchedId) const;
  Q_INVOKABLE void refreshGitForTaskBranch(const QString& taskId);
  // Create (and switch to) the task's branch from a task card. Honors the
  // configured integrations.github.branchTemplate; toasts the result.
  Q_INVOKABLE void createBranchForTask(const QString& taskId);

 signals:
  void storageStateChanged();
  void selectedDateChanged();
  void todayChanged();
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
  void activeNoteChanged();
  // Emitted just before the active note changes, while the old one is still
  // active. The notes editor debounces its writes, so its last keystrokes are
  // only in the text field at this point; it flushes on this signal, and they
  // land in the note they were typed into instead of the one being opened.
  void aboutToChangeActiveNote();
  // Asks every editor with a debounced write pending (notes, doc pages, the
  // docs catalogue) to write it now. Emitted before anything that reads the
  // whole profile — an export, a search — so it sees what is on screen.
  void flushEditorsRequested();
  void activeDocPageChanged();
  void appSettingsJsonChanged();
  void calendarSubscriptionsChanged();
  void statusesChanged();
  void pendingUndoChanged();
  void onboardingChanged();
  // Emitted after resetToFirstRun() rebuilds a fresh install — Main.qml re-opens
  // the Welcome dialog and surfaces a confirmation toast.
  void firstRunReset();
  // "Reset all settings" went through; `message` is the toast text.
  void settingsReset(const QString& message);
  // Emitted by replayWelcome() — Main.qml re-opens the Welcome guide from step 0
  // without changing any persisted onboarding flags.
  void welcomeReplayRequested();
  // noteMouseAction() decided it is time to mention `sequence` for `label`.
  void shortcutHintRequested(const QString& shortcutId, const QString& sequence, const QString& label);
  void profilesChanged();
  void activeProfileChanged();
  void shortcutsChanged();
  void blockedStuckChanged();
  void statusCountsChanged();
  void taskTitlesChanged();
  void savedViewsChanged();
  void savedViewCountsChanged();
  // `routeId` ("meeting:<event id>") makes it a reminder with buttons
  // (APP-155); empty for a plain heads-up.
  void notification(const QString& title, const QString& body, const QString& kind, const QString& routeId = QString());
  // `kind` tints the toast: "info" (default when empty), "success", "warning"
  // or "error". Every C++ toast used to arrive as info, failures included.
  void toast(const QString& message, const QString& kind = QString());
  // Device-flow OAuth: prompts the Integrations card to show a "enter this code
  // in your browser" banner. An empty `code` clears the banner (flow finished).
  void oauthDeviceCode(const QString& providerId, const QString& code, const QString& verificationUri);
  // A browser sign-in succeeded but the provider still needs a scope field
  // (Asana workspace, ClickUp list, Sentry org/project, Bitbucket repo) before
  // it can sync. The card opens Advanced so the user can see what is missing.
  void integrationNeedsFields(const QString& providerId, const QStringList& labels);
  // A credential sign-in finished. The card clears its password field on both
  // outcomes, so a failed attempt never leaves one sitting in the UI.
  void integrationLoginFinished(const QString& providerId, bool ok);
  // A card action came back: `action` is "sync", "test", "oauth" or "signin".
  // `message` is what the toast said on failure (empty on success). The card
  // shows its buttons as busy until this arrives and keeps the last error on
  // screen, since the toast is gone in a few seconds (design audit DES-5).
  void integrationActionFinished(const QString& providerId, const QString& action, bool ok, const QString& message);
  // A sync brought new cards (APP-180): the toast names them and offers to
  // show them. One per pull, instead of the plain toast.
  void syncNews(const QString& message, const QStringList& taskIds);
  void syncingChanged();
  void unseenTasksChanged();
  void syncNewTaskIdsChanged();
  void eventLogChanged();
  // Raised whenever the keychain contents change — on the async load at startup
  // and after every write. integrationSecret() is a plain Q_INVOKABLE (secrets
  // are not properties), so QML re-reads it by binding to this signal.
  void integrationSecretsChanged();
  // The answer to one fetchTicketComments (HEAP-117). Carries the task id so a
  // reply for a ticket the user has since navigated away from can be dropped.
  // `error` is empty on success; an empty list with no error means no comments.
  void ticketCommentsLoaded(const QString& taskId, const QVariantList& comments, const QString& error);
  void updateStatusChanged();
  void integrationStatesChanged();
  void integrationHealthChanged();
  // A task's history gained an event (APP-165).
  void taskHistoryChanged(const QString& taskId);
  // Emitted when a newer release is found — Main.qml shows an actionable toast.
  void updateAvailable(const QString& version, const QString& url);
  void updateProgressChanged();
  // The package arrived and matches the release's SHA-256 — Main.qml offers
  // the restart.
  void updateReadyToInstall(const QString& version, const QString& sha256);
  void undoableToast(const QString& message, int seconds);
  // A status change did not reach the tracker. The UI offers a retry.
  void trackerPushFailed(const QString& taskId, const QString& message);
  // A conflict on this task was settled, one field or all (APP-163).
  void trackerConflictResolved(const QString& taskId);
  void focusedGitChanged();
  void showWhoseMoveChanged();
  // `profileId` is the profile the task lives in; the window switches there
  // only once the editor's unsaved edits are settled (PRES-1).
  void openTaskRequested(const QString& id, const QString& profileId);
  // "Open" on a meeting / standup reminder: the calendar at `date`, and the
  // event's editor when `eventId` names a stored event (APP-155).
  void openEventRequested(const QString& eventId, const QDate& date);
  void selectedTaskIdsChanged();
  // Raised by the OS-level global hotkeys (Quick-capture from anywhere). QML
  // brings the window forward and opens the matching capture popup.
  void quickCaptureRequested();
  void quickCaptureNotesRequested();
  // Raised when the user asks to restore the window from the tray (tray click
  // or the tray menu's "Show" entry). QML un-hides and activates the window.
  void showWindowRequested();

 public:
  // One automation tick at `now`. The timer calls it with the wall clock;
  // tests call it with the clock they need.
  void runAutomationAt(const QDateTime& now);
  // Re-reads the date. When it moved, `today` changes, and a selection that
  // was on the old today follows it — the calendar is where the user left it,
  // "today". Called by the midnight timer, the minute tick and on resume.
  void refreshToday(const QDate& current = QDate::currentDate());

 private slots:
  void runAutomation();

 private:
  // settings.calendar.timeFormat == "12h".
  bool twelveHourClock() const;
  // `base` if no task holds it, else "base-2", "base-3", … Two pulled issues
  // can want the same id (the same number from two repos), and upsert on a
  // colliding id replaces the other task rather than adding one.
  QString uniqueTaskId(const QString& base) const;

  TaskModel m_tasks;
  EventModel m_events;
  PersonModel m_people;
  ActivePeopleModel m_activePeople;
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
  QString m_crumbProject;
  QString m_crumbUser = "You";
  QString m_docsState;
  QString m_notesState;
  NoteModel m_notes;
  QString m_activeNoteId;
  DocPageModel m_docPages;
  QString m_activeDocPageId;

  // Keeps `notesState` and the active note's body the same thing. Called on
  // every edit and every switch; silent when there is no active note.
  void syncActiveNoteBody();
  // After undo/redo touched the notes: the open note may be gone, or be back
  // with a different body. Keeps `notesState` pointing at a note that exists.
  void reconcileActiveNote();

  // Tell a mirrored card's tracker about its status. No-op for local tasks.
  void pushStatusToTracker(const QString& taskId, const QString& status);
  // Drop the not-yet-started focus blocks planned for a task that is finished.
  void dropFutureFocusBlocks(const QString& taskId);
  void onTaskPushed(const QString& providerId,
                    const QString& externalId,
                    const QString& project,
                    bool ok,
                    const QString& error,
                    const QString& remoteStatus = QString());
  // Key of m_pendingPushes. `project` is the issue's own repo/project (empty
  // when it is not known): in a cross-project pull the number alone is ambiguous.
  static QString pushKey(const QString& providerId, const QString& project, const QString& externalId);
  // pushKey → task id, for pushes still in flight.
  QHash<QString, QString> m_pendingPushes;
  // Non-zero while a bulk move runs moveTask per card: one toast for the lot.
  int m_bulkMoveDepth = 0;
  // Sound palette (APP-177): muted for CLI requests; a bulk move plays one
  // sound when the loop ends, not one per card — "done" if anything closed,
  // else "refuse" if a card was refused. -1: nothing pending.
  bool m_soundMuted = false;
  int m_soundPending = -1;
  void completionSoundOnMove_(const QString& fromStatus, const QString& toStatus);
  // Plays `cue` (a heap::platform::SoundCue) if the Sound settings, quiet
  // hours (judged at `at`, the wall clock when invalid), focus mode and the
  // system allow it.
  void playSound_(int cue, const QDateTime& at = QDateTime());
  // The meeting chimes due at `now` (APP-178): one melody per tick at most.
  void meetingChimesAt(const QDateTime& now);
  // Providers already asked for their full status list this session.
  QSet<QString> m_statusesAsked;
  // Providers whose next tasksFetched answers a quiet follow-up pull.
  QSet<QString> m_settlePulls;

  // A pull whose missing issues are being looked up: its stats and whether it
  // was a quiet follow-up, held so one toast reports both (INT-6).
  struct PendingSyncReport {
    MergeStats stats;
    bool settlePull = false;
  };

  QHash<QString, PendingSyncReport> m_pendingLookups;

  // `notesState` must always belong to a note. Text that arrives with no note
  // open — typed into an empty editor, or captured with Ctrl+Shift+N — becomes
  // a note of its own here. Without this it lived only in `notesState`, which
  // is no longer written to disk since notes became a list, and the next "+"
  // overwrote it.
  void adoptOrphanNotesState();
  // A note with no body, made active without announcing a new notesState:
  // callers write the body next and that is the one change the editor sees.
  QString createActiveNote(const QString& title);
  // ---- Attachments (AppControllerAttachments.cpp) ----
  // Every attachment id something still points at: any profile's tasks,
  // descriptions, notes and doc pages, the open editor text, and the undo
  // history — so a file detached a minute ago survives a cleanup and Ctrl+Z
  // still finds it.
  QSet<QString> referencedAttachmentIds() const;
  // Every attachment a note, doc page, description or the Docs catalogue has
  // linked to since the app started. A text editor's own undo history is out
  // of reach from here, and Ctrl+Z in it can bring back a link the text no
  // longer holds, so the cleanup leaves these alone until the next start
  // (KNOW-3). Fed from the models' signals by trackAttachmentRefsInText().
  QSet<QString> m_attachmentsLinkedThisSession;
  void trackAttachmentRefsInText();
  // The ids one profile uses, for its export.
  QStringList profileAttachmentIds(const Profile& p) const;
  // The export's "attachments" array, or an empty one (and *omittedBytes set)
  // when the files would push the export past the cap.
  QJsonArray attachmentsForExport(const Profile& p, qint64* omittedBytes, int* omittedCount) const;
  // Writes an import's files into the store. Returns old id → new id for every
  // file whose content did not match its id (it is stored under the right one
  // and the references are rewritten).
  QHash<QString, QString> importAttachmentBlobs(const QJsonArray& blobs, QStringList* problems);
  // A string of the attachments feature, in the UI language.
  QString attText(const char* key) const;
  void toastAddFailure(const QString& name, int error);

  // Reads a vault folder and decides what importing it would do (see
  // heap::notes::planImport); the summary is what import and preview return.
  QVariantMap planNotesImport(const QUrl& folderUrl, QVector<heap::notes::VaultPlanItem>* plan) const;
  // Tells the contact importer about imported contacts that a docs change
  // removed (dismiss) or brought back (restore).
  void syncDismissedContacts(const QString& beforeJson, const QString& afterJson);
  // The palette rows for one profile's notes and doc pages (see searchFullText).
  QVariantList fullTextEntries(const Profile& p) const;
  QString m_appSettingsJson;
  // settingsMap()'s parse cache, keyed on the string above so that no writer
  // of it has to remember to invalidate anything.
  mutable QString m_settingsCacheSource;
  mutable QVariantMap m_settingsCache;
  // statusCounts()' cache; invalidated from the task model's own signals so
  // every mutation path is covered without each one remembering to.
  mutable QVariantMap m_statusCounts;
  mutable bool m_statusCountsDirty = true;
  // taskTitles: rebuilt once per event-loop turn after the task model
  // changes, and announced only when a title or id really changed, so a
  // status drag does not re-render every open note.
  QVariantMap m_taskTitles;
  bool m_taskTitlesQueued = false;
  void refreshTaskTitles();
  // The active profile's saved views and savedViewCounts()' cache. The count
  // signal is coalesced: a bulk edit fires the model's signals per row.
  QVector<heap::savedviews::SavedView> m_savedViews;
  // Column moves of the active profile (WEAK PECAP), and the status each task
  // was last seen in, which is how a move is noticed whatever path made it.
  QVector<StatusChange> m_statusLog;
  QHash<QString, QString> m_knownStatus;
  void rememberStatuses();
  void noteStatusMoves(int first, int last);
  mutable QVariantMap m_savedViewCounts;
  mutable bool m_savedViewCountsDirty = true;
  QTimer m_savedViewCountsTimer;
  void wireSavedViews();
  void dropSavedViewCounts();
  void setSavedViews(const QVector<heap::savedviews::SavedView>& views);
  bool m_welcomeSeen = false;  // onboarding: welcome dialog shown at least once
  bool m_demoActive = false;   // onboarding: profile still holds seeded demo
  mutable QString m_installId;  // settings.installId, minted on first use

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

  // The task a reminder is about, and the profile it lives in. Reminders cover
  // every profile; the ref names the profile (PRES-2), an older one does not.
  struct ReminderTask {
    QString profileId;  // empty: no such task any more
    Task task;
  };

  ReminderTask reminderTask(const QString& ref) const;
  QSet<QString> m_blockedStuckIds;
  // Reminders already delivered, by key (see src/cal/Reminders.h), with when.
  // Persisted to reminders.json so a restart does not announce them again.
  QHash<QString, QDateTime> m_sentReminders;

  // Notifications that arrived during quiet hours, delivered when they end.
  struct HeldNotification {
    QString title;
    QString body;
    QString kind;
    QString taskId;
  };

  QVector<HeldNotification> m_heldNotifications;
  QString remindersFilePath() const;
  void loadSentReminders();
  // Reminder buttons (APP-155): what each kind offers, what was last shown
  // under an id (so a snooze can bring the same text back), and the snoozes.
  QVector<heap::notify::NotificationAction> reminderActions(const QString& kind) const;

  struct ShownReminder {
    QString title;
    QString body;
    QString kind;
    QDate date;  // meetings: the occurrence's day, for "Open"
  };

  QHash<QString, ShownReminder> m_shownReminders;
  QVector<heap::notify::SnoozedReminder> m_snoozed;
  QString snoozesFilePath() const;
  void loadSnoozes();
  void saveSnoozes() const;
  void fireDueSnoozes(const QDateTime& now);
  void openReminder(const QString& notificationId);
  void saveSentReminders() const;
  bool reminderSent(const QString& key) const;
  QSet<QString> sentReminderKeys() const;
  void markReminderSent(const QString& key, const QDateTime& at);
  void holdNotification(const HeldNotification& n);
  void flushHeldNotifications(const QDateTime& now);
  // settings.calendar.workDays, Monday to Friday by default.
  bool isWorkDay(const QDate& day) const;
  // Fires at the next local midnight; see refreshToday().
  QTimer* m_midnightTimer = nullptr;
  void armMidnightTimer();
  QVariantMap settingsMap() const;
  // The calendar snap grid in hours, from settings.calendar.snapMinutes. Every
  // event write path clamps against the same grid (heap::cal::clampHours).
  double snapStepHours() const;
  // saveEvent's second half: normalizes the span, checks the rule and stores.
  // Series edits build a CalEvent themselves and come in here.
  void storeEvent(CalEvent e);
  bool inQuietHours(const QDateTime& when) const;
  static double nextQuarterHour(const QDateTime& when);
  void scheduleFocusBlockFor(const QString& taskId);
  void focusBlockOnStatusChange(const QString& taskId, const QString& from, const QString& to);
  // Keeps a task's scheduledAt on the focus block it came from: moved with
  // it, cleared when it is deleted (after == nullptr).
  void followFocusBlock(const CalEvent& before, const CalEvent* after);

  // Persistence
  QTimer* m_saveTimer = nullptr;
  bool m_loading = false;
  QDateTime m_lastBackupAt;
  void scheduleSave();
  void saveStateNow();
  void loadStateOnStart();
  // Everything after the bytes are known to be a state document: the schema
  // ladder, settings, profiles, events. `viewOnly` loads a backup for display
  // in a read-only session (no pre-migration copy, no recovery records).
  void loadStateDocument(QJsonObject root, bool viewOnly);
  QString stateFilePath() const;
  QString backupDirPath() const;
  // Writes `bytes` over state.json and reloads from it (a restore's last step).
  bool replaceStateFile(const QByteArray& bytes);
  // The time machine's parsed snapshot: one at a time, kept while the dialog
  // looks at it so a restore does not inflate it again.
  bool loadSnapshot(const QString& name, QString* error);
  QString m_snapName;
  QVector<Profile> m_snapProfiles;
  QVector<CalEvent> m_snapEvents;
  // When the newest rotational backup on disk was taken; invalid when none.
  QDateTime newestBackupTime() const;
  // Crash/corruption recovery for loadStateOnStart(): find the newest backup
  // that still parses (returns its object + path), and move a damaged
  // state.json aside so a fresh seed can never silently overwrite it.
  bool recoverFromNewestBackup(QJsonObject& out, QString& fromPath);
  // Moves (or, when a lock forbids the rename, copies `bytes` to) a damaged
  // state.json aside. Returns the quarantine file name, empty on failure — in
  // which case nothing may be written over the original.
  QString quarantineCorruptState(const QString& path, const QByteArray& bytes);
  // Copies the pre-migration state.json into the backup dir before the schema
  // ladder rewrites it. Exempt from retention pruning: it is the only pre-v4
  // image of the user's data.
  void retainPreMigrationBackup(const QString& path, int fromVersion);
  // Set when state.json was written by a newer build than this one. Every save
  // path is a no-op while it is true: this build cannot represent the fields it
  // did not parse, so writing would drop them.
  bool m_saveBlocked = false;

  // ---- Storage health + background save (PLAT-1/4/5/23) ----
  QString m_storageState = QStringLiteral("ok");
  QString m_storageMessage;
  void setStorageState(const QString& state, const QString& message);
  // state.json exists but could not be read: show the newest backup (or an
  // empty workspace) read-only and never write over the file.
  void enterUnreadableMode(const QString& error);
  // Drops every profile and re-reads state.json (restore, retry after a lock).
  void reloadStateFromDisk();
  // Whether an edit was made while saving was blocked (it will not persist).
  bool m_editsWhileBlocked = false;
  // When the last "this edit is not saved" toast was shown, ms since epoch.
  qint64 m_lastBlockedEditToastMs = 0;
  std::unique_ptr<heap::storage::AsyncSaver> m_saver;
  quint64 m_saveGeneration = 0;
  QTimer* m_saveRetryTimer = nullptr;
  QTimer* m_storageRetryTimer = nullptr;
  int m_saveRetryStep = 0;
  void onSaveFinished(const heap::storage::SaveOutcome& outcome);
  bool backupDueNow(const QDateTime& now);
  // Copies state.json into backups/ now (regardless of the rotation interval).
  // Returns the copy's file name, empty on failure.
  QString snapshotStateToBackups(const QString& tag = QString());
  // Unknown keys read from disk at the same schema version, written back
  // untouched (PLAT-26): the document root and settings.
  QJsonObject m_rootExtra;
  QJsonObject m_settingsExtra;
  // Next number to mint per task id prefix, across every profile (TASKS-1/31).
  QHash<QString, int> m_taskSeq;
  static inline bool s_headless = false;
  // What resetSettingsToDefaults() replaced, for its Undo.
  QString m_settingsBeforeReset;
  // The id newTaskDraft & co. hand out for `stem`: past the persisted counter
  // and past every id any profile holds under it.
  QString mintTaskId(const QString& stem) const;
  // Records that `id` was taken, so it is never handed out again.
  void noteTaskIdUsed(const QString& id);
  // Gives every task of `p` (a profile about to be added) whose id another
  // profile already holds a fresh one, and points the references inside `p`
  // — links, #KEY-1 mentions — and `events`' task links at it. Returns
  // old id -> new id (PLAT-9).
  QHash<QString, QString> reissueSharedTaskIds(Profile& p, QVector<CalEvent>* events);
  // Adds `events` (another profile's, or a snapshot's) to the pool as
  // `profileId`'s own: each gets a fresh id, and an override follows its
  // series to the copy's (PLAT-10, TM-1).
  void addEventsAsCopies(const QVector<CalEvent>& events, const QString& profileId);
  int statusIndexOf(const QString& id) const;
  // Whether another column (not `exceptId`) already carries `name`, ignoring case.
  bool statusNameTaken(const QString& name, const QString& exceptId) const;
  bool profileNameTaken(const QString& name, const QString& exceptId) const;
  // `base`, or "base (N)" with the first N no profile uses.
  QString uniqueProfileName(const QString& base) const;
  // One column's tasks in board order (rank, then id so the order is total).
  QVector<::Task> columnTasks(const QString& statusId, const QString& excludeId) const;
  // Spread a column's ranks back out when a gap has shrunk too far to take
  // another midpoint. See src/board/Rank.h.
  void rebalanceColumn(const QString& statusId);

  // ---- Undo/redo ----
  // The stack records what an operation changed (see src/undo/UndoStack.h)
  // rather than each mutator describing itself, which is why bulk move and
  // bulk archive are undoable now without either of them knowing about undo.
  heap::undo::UndoStack m_undo;
  int m_undoScopeDepth = 0;
  quint64 m_undoSerialCounter = 0;
  quint64 m_openUndoSerial = 0;  // serial of the outermost scope being recorded

  // Snapshots the collections on construction and pushes the diff on
  // destruction. Declaring one at the top of a mutator is the whole contract:
  //
  //   UndoScope scope(this, tr_("task.deleted").arg(id));
  //
  // An operation that changes nothing pushes nothing, so a no-op move or a
  // guard that returns early leaves the stack alone.
  class UndoScope {
   public:
    UndoScope(AppController* owner, QString label);
    ~UndoScope();
    UndoScope(const UndoScope&) = delete;
    UndoScope& operator=(const UndoScope&) = delete;
    UndoScope(UndoScope&&) = delete;
    UndoScope& operator=(UndoScope&&) = delete;

    // Abandon the recording — used where the operation replaces the whole
    // workspace and a per-element diff would be meaningless.
    void abandon() {
      m_armed = false;
    }

    // Several mutators only know what to call the operation part-way through
    // (the column a card landed in, how many tasks a bulk action touched).
    void setLabel(QString label) {
      m_label = std::move(label);
    }

    void setRedoLabel(QString label) {
      m_redoLabel = std::move(label);
    }

   private:
    AppController* m_owner;
    QString m_label;
    QString m_redoLabel;
    bool m_armed = true;
    // Scopes nest: an operation built out of other operations records one
    // entry, not one per part. Only the outermost scope snapshots and pushes.
    bool m_outermost = true;
    quint64 m_serial = 0;
    QVector<::Task> m_tasks;
    QVector<::CalEvent> m_events;
    QVector<::Person> m_people;
    QVector<::DocPage> m_docPages;
    QVector<::Note> m_notes;
    QVariantList m_statuses;
    QString m_docsState;
    QVector<heap::savedviews::SavedView> m_savedViews;
  };

  // One task's priority, unrecorded; false when nothing changed.
  bool setPriorityOf(const QString& id, const QString& priority);

  // Scopes opened by beginUndoGroup() and closed by endUndoGroup().
  std::vector<std::unique_ptr<UndoScope>> m_undoGroups;

  // Applies one recorded entry in either direction and refreshes what the UI
  // derives from the models.
  void applyUndoEntry(const heap::undo::Entry& entry, bool backward);
  // Hands the open note's unsaved keystrokes to it before an undo or redo.
  void flushNotesForUndo();

  // Selection state
  QSet<QString> m_selectedTaskIds;
  QStringList m_selectedTaskIdsList;  // ordered cache for QML
  void rebuildSelectionList_();

  struct SelectionFilter {
    QString search;
    QStringList priorities;
    bool showArchived = true;
    bool hideDone = false;
  } m_selectionFilter;

  // Drops selected ids m_selectionFilter hides; emits when it dropped any.
  void pruneSelectionToFilter_();
  // The one predicate the filter bar counts and the selection prune share.
  bool passesFilter_(int row, const heap::query::TaskQuery& q, const QStringList& priorities, bool showArchived, bool hideDone) const;

  std::unique_ptr<heap::chrono::ChronoParser> m_chrono;

  // ---- Git watcher ----
  std::unique_ptr<heap::git::GitWatcher> m_gitWatcher;

  // ---- Auto-update (HEAP-63) ----
  std::unique_ptr<heap::update::Updater> m_updater;
  QString m_updateStatus;  // a tr_() key, "" before the first check
  QString m_updateStatusArg;
  QString m_latestReleaseUrl;
  int m_packageKind = 0;  // a heap::update::PackageKind, read once at startup
  QString m_updatePhase;
  double m_updateProgress = 0.0;
  QString m_updateSha256;
  QString m_updatePackage;  // the verified file, once "ready"
  void setUpdatePhase(const QString& phase, const QString& statusKey, const QString& arg = QString());

  // ---- Tracker sync (HEAP-74 GitHub, HEAP-75 Jira + GitLab) ----
  // Every connected + configured provider runs concurrently; a task's
  // externalProvider routes status pushes to the matching one.
  std::vector<std::unique_ptr<heap::integrations::IntegrationProvider>> m_syncProviders;
  // Directory providers live apart from m_syncProviders: they have none of the
  // IntegrationProvider verbs. Keyed by provider id; only Mattermost for now.
  QHash<QString, heap::integrations::MattermostClient*> m_directoryClients;
  QHash<QString, QString> m_directoryConfigHash;
  // Access tokens for the trackers, kept in the OS keychain (HEAP-74/75).
  heap::integrations::SecretStore* m_secretStore = nullptr;
  // Looks for a due periodic pull (integrations.autoSyncMinutes, up to a
  // month; APP-123). The last sync's time lives in autosync.json so a
  // restart does not start the wait over.
  QTimer* m_syncTimer = nullptr;
  QDateTime m_lastTrackerSync;
  QString autoSyncFilePath() const;
  void loadLastTrackerSync();
  void saveLastTrackerSync() const;

 public:
  // The periodic-sync check at `now` (the timer passes the clock). Public
  // for the tests, like runAutomationAt.
  void autoSyncTickAt(const QDateTime& now);

  QDateTime lastTrackerSync() const {
    return m_lastTrackerSync;
  }

 private:
  // Reconcile the active providers with the current integrations settings.
  void applyIntegrationSettings();
  // Merge a provider's non-secret settings with its keychain secrets.
  QVariantMap integrationConfig(const QString& providerId) const;
  // Write one non-secret integration field into the settings blob and persist.
  void setIntegrationField(const QString& providerId, const QString& field, const QVariant& value);
  // The user's status → column choices for this provider, as StatusMap wants
  // them. Keys are the tracker's own status strings.
  QHash<QString, QString> statusOverridesFor(const QString& providerId) const;
  // Record the statuses a pull actually carried, so the mapping UI can offer
  // the real vocabulary instead of asking the user to type it. Returns true
  // when something new was learned and the settings blob needs writing.
  bool rememberSeenStatuses(const QString& providerId, const QStringList& statuses);
  // Same, for several fields at once. Every write rebuilds the providers, so a
  // sign-in that set three fields one by one tore down and rebuilt the sync
  // layer three times — enough to kill a request already in flight.
  void setIntegrationFields(const QString& providerId, const QVariantMap& fields);
  // Card labels of the requiredKeys this provider still has empty. A browser
  // sign-in proves who you are but not what to sync, so the scope fields
  // (Asana workspace, ClickUp list, Sentry org/project, Bitbucket repo) can
  // still be missing afterwards.
  // Public so the card can recompute the notice as fields are edited, rather
  // than only seeing it once in the toast that follows a sign-in.
 public:
  Q_INVOKABLE QStringList missingRequiredFields(const QString& providerId) const;

 private:
  // The same list, told explicitly whether to treat the browser sign-in as
  // having answered the client-ID field. A manual connect is about to clear
  // authMode, so it must be validated as the token card it is becoming — not
  // as the OAuth card the config still says it is.
  QStringList missingRequiredFields(const QString& providerId, bool signedInViaBrowser) const;
  // Finish a Jira browser sign-in: ask accessible-resources which Atlassian
  // site the new token was granted and cache its cloudId. A 3LO token is not
  // bound to a site, and the gateway path needs that id.
  void resolveJiraSite(const QString& accessToken, const QString& label);
  // Build (or rebuild) the directory client from the current config. Returns
  // null when the provider is not connected or not configured. Rebuilds only
  // when the effective config actually changed: applyIntegrationSettings runs
  // on every settings write, and dropping the client mid-fetch would silently
  // abandon a request already in flight.
  heap::integrations::MattermostClient* directoryClient(const QString& providerId);
  void fetchDirectory(const QString& providerId, bool rebindProfile = false);
  // Drop a directory client safely. Never `delete`: this can run from inside
  // the client's own reply handler.
  void retireDirectoryClient(const QString& providerId);
  // Contacts the user deleted, per profile, so a later sync does not bring
  // them back. They cannot live in the docs blob: DocsView rewrites it whole
  // and would drop any key it does not know.
  QStringList dismissedContacts(const QString& providerId) const;
  QStringList dismissedTasks(const QString& providerId) const;
  // Create the Person behind an imported contact, or return the id of the one
  // already there. Never edits an existing Person: those are the user's notes
  // about someone, not a mirror of the directory.
  // `linkedPersonId` is the Person this contact already points at, if any: it
  // is the only id that may be reused when the derived one is already taken.
  QString upsertImportedPerson(const heap::integrations::ExternalContact& ext, const QString& linkedPersonId);

  // A Docs contact's stable identity across a docsState rewrite: its external
  // id when it has one, else its Mattermost handle, else its name. The picker
  // hands this back on save so the Person that was just created can be linked
  // to the contact it came from without holding on to an array index.
  static QString docsContactKey(const QJsonObject& contact);
  // Point the Docs contact `contactKey` at `personId`. No-op when the contact
  // is gone or already links there.
  void linkDocsContact(const QString& contactKey, const QString& personId);
  // Point every Docs contact linked to `fromPersonId` at `toPersonId`: the
  // person was renamed.
  void relinkDocsContacts(const QString& fromPersonId, const QString& toPersonId);
  // Append a Docs contact for a Person created through the rail's picker, so
  // the next search finds them among the contacts.
  void appendDocsContact(const Person& p);
  // One-time move of any plaintext tokens found in state.json into the keychain.
  void migrateLegacySecrets();
  // Renew an expiring OAuth access token, then run `then`. Providers that use a
  // PAT, or whose token does not expire, fall straight through. A browser
  // sign-in hands out a token that lives ~2h (GitLab), so without this every
  // sync after the first couple of hours came back empty.
  // `onFail` runs instead when the token could not be renewed.
  void ensureFreshToken(const QString& providerId, std::function<void()> then, std::function<void()> onFail = {});
  // Refresh if needed, then pull. Looks the provider up again afterwards,
  // because a refresh rebuilds m_syncProviders.
  void syncProviderNow(const QString& providerId);
  // Exchange the stored refresh token for a new access token. `done` gets true
  // when the provider is usable again. A refusal from the provider disconnects
  // the card so the user is prompted to sign in again.
  void refreshOAuthToken(const QString& providerId, std::function<void(bool)> done);
  // Used by refreshOAuthToken; providers are rebuilt whenever a secret changes,
  // so it cannot borrow a provider's own manager.
  QNetworkAccessManager* m_oauthNam = nullptr;

  // Calendar subscriptions: the fetcher, the minute tick that decides who is
  // due, and per-subscription state that is not worth saving.
  struct CalSubState {
    QDateTime lastAttempt;
    QDateTime lastSync;
    QString error;
    bool busy = false;
  };

  QNetworkAccessManager* m_calNam = nullptr;
  QTimer* m_calTimer = nullptr;
  // The worker reading the desktop Outlook; waited for on exit.
  QThread* m_outlookThread = nullptr;
  QHash<QString, CalSubState> m_calSubState;
  QSet<QString> m_calSubSecretsLoaded;
  QVariantList calendarSubscriptionSettings() const;
  void writeCalendarSubscriptionSettings(const QVariantList& list);
  void applyCalendarSubscriptions();
  void fetchCalendarSubscription(const QString& id);
  // True (and says so) when `id` or `masterId` is a subscription's event.
  bool refuseSubscriptionEdit(const QString& id, const QString& masterId = QString());
  // Providers whose refresh is already in flight — a sync and a push firing
  // together must not both spend the (single-use, rotated) refresh token.
  QSet<QString> m_refreshing;
  // Providers whose 401 already bought one refresh-and-retry, so a tracker that
  // answers 401 no matter what cannot loop. Cleared by a successful pull.
  QSet<QString> m_retriedAfter401;
  // ---- Offline tolerance (audit INT-5/INT-6/INT-8) ----
  QVariantMap integrationStates() const;
  // A provider's own English reason, in the UI language when heap knows it.
  QString providerReason(const QString& reason) const;
  // A refresh that failed for want of a network: keep the session, retry
  // later with a doubling delay, say "offline" meanwhile.
  void scheduleRefreshRetry(const QString& providerId);
  void setProviderOffline(const QString& providerId, bool offline);
  QSet<QString> m_offlineProviders;
  // When each tracker last answered and how its last failure read (APP-164).
  // This session only: a restart starts the page over.
  QHash<QString, heap::integrations::ProviderHealth> m_syncHealth;
  // ---- Sync visibility (APP-180/186/187) ----
  // Pulls out right now, by provider id, each with the serial of its start:
  // a pull that never answers is let go after kSyncWatchdogMs.
  QHash<QString, int> m_syncInFlight;
  int m_syncStartSerial = 0;
  void setSyncInFlight(const QString& providerId, bool inFlight);
  QSet<QString> m_unseenTaskIds;
  int m_unseenRevision = 0;
  // `is:new`: the cards of the latest sync that brought any. A sync run
  // (Sync now, one card's sync, an auto-sync tick) starts a new set; the
  // pulls inside it, a Jira follow-up included, add to it.
  QStringList m_syncNewIds;
  int m_syncRunSerial = 0;
  int m_syncNewSerial = -1;
  void noteSyncAdded(const QStringList& ids, bool markUnseen);
  heap::notify::EventLog m_eventLog;
  // Set while a toast that was already logged with more to it (the tasks or
  // the place it is about) goes out, so the plain toast hook skips it.
  bool m_eventLogMuted = false;
  void toastAndLog(const QString& message, const QString& kind, const QStringList& taskIds = {}, const QString& route = QString());
  // Task history (APP-165). Saved as the root key "taskHistory" of state.json.
  heap::history::TaskHistory m_history;
  // True while a tracker pull is the one changing tasks.
  bool m_historySync = false;
  void recordTaskChange(const Task* before, const Task& after);
  void recordSyncHealth(const QString& providerId, bool ok, int items, int httpStatus, const QString& error);
  QHash<QString, int> m_refreshRetryMs;
  // A move that could not be sent (tracker disconnected or unreachable):
  // flagged on the card and sent after the next successful pull.
  void queueTrackerPush(const QString& taskId, const QString& status);
  void resolveTrackerConflictFields(const QString& taskId, const QStringList& fields, bool useTracker);
  void flushQueuedPushes(const QString& providerId);
  // What a pull under the card's current settings is scoped to. See
  // heap::integrations::scopeFingerprint.
  QString scopeFingerprintFor(const QString& providerId) const;
  // provider + newline + issue key → the statuses the issue's workflow can move
  // to, as of the last pull. Only trackers that report transitions (Jira)
  // fill it; an issue without an entry is not second-guessed.
  QHash<QString, QStringList> m_trackerTransitions;
  // The same answers keyed by where in the workflow they were seen (provider,
  // project, issue type, status): after a push moves an issue, the moves out of
  // its new status are known from any other issue the last pull saw there,
  // instead of the guard dropping until the next pull (INT-4).
  QHash<QString, QStringList> m_workflowTransitions;
  static QString workflowTransitionsKey(const QString& providerId, const QString& project, const QString& issueType, const QString& status);
  // The built-in key `normalized` would collide with if action `id` took it;
  // empty when none. See kBuiltinKeys.
  static QString builtinShortcutOwner(const QString& id, const QString& normalized);
  QString m_focusedTaskId, m_focusedBranch, m_focusedRepo;
  QVariantMap m_focusedRepoState;
  QSet<QString> m_dismissedBranches;  // in-memory only; per branch name
  bool m_showWhoseMove = true;        // settings.git.showWhoseMove, cached for the cards
  void applyGitSettingsFromMap(const QVariantMap& git);
  // Re-derive the focused branch's task id under the current id-prefix and
  // refresh the banner. Needed because a prefix change (settings/profile) does
  // not move HEAD, so no branchChanged fires to re-run the match on its own.
  void refreshFocusedTaskId();
  void onGitBranchChanged(const QString& repo, const QString& branch, const QString& matchedId);
  void onGitRepoState(const QString& repo, const QVariantMap& state);
  void onGitCommits(const QString& repo, const QVariantMap& commitsByTask);

  // ── Safety net (APP-157…) ──────────────────────────────────────────
  // Quiet, opt-in heads-ups, each off until switched on under
  // settings.safety. They say what they noticed, once; none of them changes
  // a task, a timer or a status. See AppControllerSafety.cpp.
 public:
  // The end-of-day check (APP-157) at `now`. runAutomationAt() calls it on
  // every tick; it fires at most once a day, at settings.safety.endOfDayTime.
  void checkEndOfDayAt(const QDateTime& now);
  // The "waiting on a reply" reminder (APP-158) at `now`, from the same tick.
  void checkWaitingAt(const QDateTime& now);

  // settings.safety, for QML: which heads-ups are on.
  Q_PROPERTY(QVariantMap safety READ safetySettings NOTIFY appSettingsJsonChanged)
  // Writes settings.safety.<key>; Settings → Safety net's rows use it.
  Q_INVOKABLE void setSafetySetting(const QString& key, const QVariant& value);
  // Waiting on a reply (APP-158), active profile: task id →
  // { personId, name, color, since, days }.
  Q_PROPERTY(QVariantMap waitingOn READ waitingOnMap NOTIFY waitingOnChanged)
  QVariantMap waitingOnMap() const;

  QVector<WaitingOn> waitingOnLinks() const {
    return m_waitingOn;
  }

  // Link a task to the person whose answer it waits on, from now. Picking
  // someone again (or the same person) starts the wait over and re-arms its
  // one reminder.
  Q_INVOKABLE void setWaitingOn(const QString& taskId, const QString& personId);
  Q_INVOKABLE void clearWaitingOn(const QString& taskId);

  // "You've seen this before" (APP-159): when `text` looks like an error or a
  // stack trace, the note, doc page or task (any profile) that already
  // mentions its gist — { kind, id, title, profileId, date } — or an empty
  // map. Empty too while settings.safety.seenBefore is off. `excludeTaskId`
  // is the task being edited, which would otherwise find itself.
  Q_INVOKABLE QVariantMap seenBefore(const QString& text, const QString& excludeTaskId = QString());

  // Focus mode (APP-160). On: notifications are held back (meetings pass
  // unless settings.safety.immersionPassMeetings is false) and the timer runs
  // on the current task — `preferredTaskId` if it names one, else the single
  // selected task, else the current branch's. Off: the timer it started stops
  // and immersionEnded() says how many notifications wait; nothing is
  // delivered until releaseImmersionHeld(). Not persisted: a restart ends it.
  Q_PROPERTY(bool immersion READ immersion NOTIFY immersionChanged)
  Q_PROPERTY(QDateTime immersionStartedAt READ immersionStartedAt NOTIFY immersionChanged)
  Q_PROPERTY(QString immersionTaskId READ immersionTaskId NOTIFY immersionChanged)

  bool immersion() const {
    return m_immersionStartedAt.isValid();
  }

  QDateTime immersionStartedAt() const {
    return m_immersionStartedAt;
  }

  QString immersionTaskId() const {
    return m_immersionTaskId;
  }

  qsizetype immersionHeldCount() const {
    return m_immersionHeld.size();
  }

  Q_INVOKABLE void startImmersion(const QString& preferredTaskId = QString());
  Q_INVOKABLE void stopImmersion();
  Q_INVOKABLE void toggleImmersion(const QString& preferredTaskId = QString());
  // Hands over what focus mode held back, through the usual paths. Returns
  // how many there were.
  Q_INVOKABLE int releaseImmersionHeld();

  // The standup draft (APP-170): "Yesterday / Today / Blockers" from the last
  // working day's column moves, commits and timer, today's work and meetings,
  // and the blocked cards. Text for the user to edit; nothing is sent.
  Q_INVOKABLE QString standupDraft();
  QString standupDraftFor(const QDate& today);
  // The day's summary (APP-190) for the end-of-day dialog: { date,
  // closed: [{id, title}], carryOver: [{id, title}], timers: [{id, title,
  // since}] }. Closed today and still-open work dated today or earlier come
  // from the active workspace; running timers from every workspace. It only
  // reads. The *At form takes `now`, for tests.
  Q_INVOKABLE QVariantMap endOfDaySummary() const;
  Q_INVOKABLE QVariantMap endOfDaySummaryAt(const QDateTime& now) const;
  // What the end-of-day check reads from the workspace at `now`; the
  // repository part is filled in by git, asynchronously.
  heap::safety::EndOfDayFacts endOfDayFacts() const;
  // The tasks the day's summary reads (APP-190).
  QVector<heap::safety::DayTask> dayTasks() const;

 signals:
  // A safety-net notice for the in-app toast. `taskIds` are the tasks its
  // "Show" opens the board on (may be empty).
  void safetyNotice(const QString& kind, const QString& title, const QString& body, const QStringList& taskIds);
  // Bring the board up narrowed to these tasks (a notice was clicked).
  void safetyOpenTasksRequested(const QStringList& taskIds);
  void waitingOnChanged();
  void immersionChanged();
  // Focus mode ended after `minutes`, holding back `held` notifications.
  void immersionEnded(int held, int minutes);

 private:
  QVariantMap safetySettings() const;
  // Delivers a safety-net notice: held during quiet hours like any other,
  // an OS notification when the window is in the background, the in-app
  // toast (safetyNotice) always.
  void safetyNotify(const QString& kind, const QString& title, const QString& body, const QStringList& taskIds, const QDateTime& now);
  void finishEndOfDay(const QDateTime& now, const heap::safety::RepoDirt& dirt);
  void onWorkingTreeChecked(const QString& repo, int changedFiles, int stashes, bool ok);
  // An end-of-day check waiting for git's answer about m_eodPendingRepo.
  QDateTime m_eodPendingAt;
  QString m_eodPendingRepo;
  // Task id → the newest commit naming it, from the watcher's log.
  QHash<QString, QDateTime> m_lastCommitAt;
  // The active profile's waiting-on links (the others' are in m_profiles).
  QVector<WaitingOn> m_waitingOn;
  // A person's state went from `before` to their current one: a reply ends
  // every wait on them; a deleted person's waits go with them.
  void personStateMoved(const QString& personId, const QString& before);
  // Focus mode (APP-160).
  QDateTime m_immersionStartedAt;
  QString m_immersionTaskId;
  bool m_immersionStartedTimer = false;
  QVector<HeldNotification> m_immersionHeld;
  // Task id → its recent commits ({sha, subject, at}) from the watcher.
  QHash<QString, QVariantList> m_taskCommits;
  // Holds `n` when focus mode says so; true when it did.
  bool holdForImmersion(const HeldNotification& n);
};
