#pragma once

#include <QAbstractListModel>
#include <QColor>
#include <QDate>
#include <QDateTime>
#include <QHash>
#include <qqmlregistration.h>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

// One tag on a task (HEAP-124). `id` is the label text — it is what a tracker
// calls the label and what the user types. `color` is a "#rrggbb" string, empty
// when the source gave none.
struct Label {
  QString id;
  QString color;

  bool operator==(const Label&) const = default;
};

// What a tracker says about a mirrored issue beyond the fields heap already has
// of its own (HEAP-117). Read-only: sync writes it, nothing else does, and it
// never travels back upstream. The three timestamps are the tracker's own
// values as last seen — `dueAt` in particular is what lets a pull tell "the
// user moved this deadline" from "the deadline is still the tracker's".
struct ExternalMeta {
  QString author;
  QString issueType;
  QString project;  // "owner/name", a Jira project key, a list name…
  QString milestone;
  int commentCount = -1;  // -1 = the provider did not say
  QDateTime createdAt;
  QDateTime updatedAt;
  QDateTime dueAt;
  // True when the issue arrived from an "assigned to me" pull, which spans
  // projects. Such an issue's number is unique only within its own project, and
  // it must never be pushed back through the configured-project path.
  bool crossProject = false;

  bool operator==(const ExternalMeta&) const = default;
};

struct Task {
  QString id;
  QString title;
  QString desc;
  QString priority;  // P0..P3
  QString status;    // backlog/todo/prog/half/blocked/review/done
  // Time-aware scheduling (HEAP-115). `scheduledAt` is when the work is meant
  // to happen, `dueAt` is when it is owed; either may be invalid (= none).
  // `hasTime` says whether the clock component of both is meaningful — a bare
  // date lands at 00:00 with hasTime=false, which is how a legacy QDate
  // deadline migrates in.
  QDateTime scheduledAt;
  QDateTime dueAt;
  bool hasTime = false;
  QString branch;
  QDateTime statusChangedAt;  // last time `status` was mutated
  bool archived = false;      // hidden from Board/Timeline once auto-archived
  // Time tracking (HEAP-78). trackedSeconds is the accumulated total; while a
  // timer runs, timerStartedAt marks when the current session began (invalid =
  // stopped). Live elapsed = trackedSeconds + (now - timerStartedAt).
  int trackedSeconds = 0;
  QDateTime timerStartedAt;
  // Recurrence (HEAP-77): "" = none, else a chrono token like "every:weekday".
  // Completing (moving to done) a recurring task spawns the next occurrence.
  QString recurrence;
  // Tracker-sync link (HEAP-74): set when this task mirrors an external issue.
  // Empty for locally-created tasks. Used to route status pushes and to match
  // pulled issues back to their task on the next sync.
  QString externalId;        // e.g. GitHub issue number as a string
  QString externalUrl;       // issue web URL
  QString externalProvider;  // "github" | "jira" | "gitlab"
  // Planning fields (HEAP-124).
  QVector<Label> labels;
  int estimateMinutes = 0;
  bool someday = false;  // parked: never surfaces in a "scheduled today" view
  QString assignee;      // tracker-supplied owner, empty for local tasks
  // What the tracker says about this issue (HEAP-117). Default for a local task.
  ExternalMeta externalMeta;

  bool operator==(const Task&) const = default;
};

struct CalEvent {
  QString id;
  QString title;
  QString type;    // standup/oneone/sync/focus
  double start{};  // hour 0..24
  double end{};
  QString attendees;
  QDate date;
  QString taskId;     // optional link to task in same profile
  QString profileId;  // optional attribution to a feature profile (empty = global)
  QString context;    // free-form context label rendered before the title in calendar views

  bool operator==(const CalEvent&) const = default;
};

// Tracker-native issue key for a task: Jira stores "PROJ-123" verbatim, the
// issue-number trackers store a bare number that reads as "#123". A number
// pulled across projects is ambiguous on its own, so it is qualified with the
// repo it came from ("web#42"). Empty for locally-created tasks.
QString externalKeyOf(const Task& t);

// Everything the ticket UI needs about a task's tracker link, as one map:
// provider, key, url, assignee, author, type, project, milestone, comment count
// and the tracker's created/updated timestamps. Empty for a local task, so a
// QML delegate can test it to decide whether to render the ticket strip at all.
QVariantMap ticketToVariant(const Task& t);

// Labels across the QML boundary: a list of { id, color } maps.
QVariantList labelsToVariant(const QVector<Label>& labels);
QVector<Label> labelsFromVariant(const QVariantList& list);

struct Person {
  QString id;
  QString name;
  QString role;
  QString question;
  QString state;  // todo/pinged/replied
  QColor color;
};

// One profile = one feature workspace: its own tasks, people,
// kanban-statuses and docs. Events live globally on AppController so the
// calendar can show meetings/focus blocks from every profile at once;
// CalEvent.profileId records the optional feature attribution.
struct Profile {
  QString id;     // slug, unique
  QString name;   // human-readable
  QString color;  // accent ("#5cc2dd")
  QDateTime createdAt;
  QVector<Task> tasks;
  QVector<Person> people;
  QVariantList statuses;  // [{ id, name, color }]
  QString docsState;      // JSON blob, same shape as AppController::docsState
  QString notesState;     // raw markdown text for the Notes view
};

class TaskModel : public QAbstractListModel {
  Q_OBJECT
  QML_ELEMENT
  QML_UNCREATABLE("Provided by AppController")
 public:
  enum Roles {
    IdRole = Qt::UserRole + 1,
    TitleRole,
    DescRole,
    PriorityRole,
    StatusRole,
    DeadlineRole,
    BranchRole,
    StatusChangedAtRole,
    ArchivedRole,
    BlockedStuckRole,
    PrStateRole,
    PrNumberRole,
    PrUrlRole,
    GitAheadRole,
    GitBehindRole,
    RecentCommitsRole,
    TrackedSecondsRole,
    IsTimingRole,
    RecurrenceRole,
    // HEAP-115 / HEAP-124: the datetime pair behind DeadlineRole, plus planning
    // fields. DeadlineRole stays a QDate (dueAt's date) so existing views keep
    // their all-day arithmetic.
    ScheduledAtRole,
    DueAtRole,
    HasTimeRole,
    EstimateMinutesRole,
    SomedayRole,
    DeferStateRole,
    // HEAP-140: read-only reflections of the tracker link.
    ExternalProviderRole,
    ExternalUrlRole,
    ExternalKeyRole,
    LabelsRole,
    AssigneeRole,
    // HEAP-117. Twelve QML files read roles by their numeric offset from
    // Qt::UserRole, so a new role only ever goes on the end — inserting one
    // above silently reassigns every offset below it.
    TicketRole,
    SearchTextRole,
  };

  explicit TaskModel(QObject* parent = nullptr) : QAbstractListModel(parent) {
  }

  // ID set the controller marks as "blocked too long"; consumed by
  // BlockedStuckRole so TaskCard can paint a warning border.
  void setBlockedStuckIds(const QSet<QString>& ids);
  void setArchived(const QString& id, bool archived);
  void stampStatusChange(const QString& id);
  // Time tracking (HEAP-78). startTiming marks a task running (stopping any
  // other running task); stopTiming folds the elapsed session into
  // trackedSeconds. Both emit dataChanged for the timing roles.
  void startTiming(const QString& id);
  void stopTiming(const QString& id);

  // Push live git-derived data for a task (PR state, ahead/behind). Only
  // keys present in \p info are updated; others stay as-is. Emits
  // dataChanged for the matching row across all git roles.
  void setGitInfoForId(const QString& id, const QVariantMap& info);
  void clearAllGitInfo();

  int rowCount(const QModelIndex& = {}) const override {
    return m_items.size();
  }

  QVariant data(const QModelIndex& idx, int role) const override;
  QHash<int, QByteArray> roleNames() const override;

  void reset(QVector<Task> items);

  const QVector<Task>& items() const {
    return m_items;
  }

  int indexOfId(const QString& id) const;
  void setStatus(const QString& id, const QString& status);
  void upsert(const Task& t);
  void insertAt(int row, const Task& t);
  void removeById(const QString& id);

 private:
  struct GitInfo {
    QString prState;
    QString prUrl;
    int prNumber = 0;
    int ahead = 0;
    int behind = 0;
    QVariantList recentCommits;  // [ {sha, subject}, … ] mentioning this task
  };

  QVector<Task> m_items;
  QSet<QString> m_blockedStuck;
  QHash<QString, GitInfo> m_git;  // not persisted; runtime only
  // indexOfId's id→row map, rebuilt lazily whenever rows are added, removed or
  // replaced wholesale. Mutable so the lookup can stay const.
  mutable QHash<QString, int> m_index;
  mutable bool m_indexDirty = true;
};

class EventModel : public QAbstractListModel {
  Q_OBJECT
  QML_ELEMENT
  QML_UNCREATABLE("Provided by AppController")
 public:
  enum Roles {
    IdRole = Qt::UserRole + 1,
    TitleRole,
    TypeRole,
    StartRole,
    EndRole,
    AttendeesRole,
    DateRole,
    TaskIdRole,
    ProfileIdRole,
    ContextRole,
  };

  explicit EventModel(QObject* parent = nullptr) : QAbstractListModel(parent) {
  }

  int rowCount(const QModelIndex& = {}) const override {
    return m_items.size();
  }

  QVariant data(const QModelIndex& idx, int role) const override;
  QHash<int, QByteArray> roleNames() const override;

  void reset(QVector<CalEvent> items);

  const QVector<CalEvent>& items() const {
    return m_items;
  }

  int indexOfId(const QString& id) const;
  void upsert(const CalEvent& e);
  void insertAt(int row, const CalEvent& e);
  void removeById(const QString& id);
  void detachTask(const QString& taskId);
  void setTaskId(const QString& eventId, const QString& taskId);

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
    NameRole,
    RoleRole,
    QuestionRole,
    StateRole,
    ColorRole,
  };

  explicit PersonModel(QObject* parent = nullptr) : QAbstractListModel(parent) {
  }

  int rowCount(const QModelIndex& = {}) const override {
    return m_items.size();
  }

  QVariant data(const QModelIndex& idx, int role) const override;
  QHash<int, QByteArray> roleNames() const override;

  void reset(QVector<Person> items);

  const QVector<Person>& items() const {
    return m_items;
  }

  int indexOfId(const QString& id) const;
  void cycleState(const QString& id);
  void setState(const QString& id, const QString& state);
  void upsert(const Person& p);
  void insertAt(int row, const Person& p);
  void removeById(const QString& id);
  int todoCount() const;

 private:
  QVector<Person> m_items;
};
