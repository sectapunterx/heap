// The time machine (APP-162): the history/ snapshots the save path writes
// (storage/Snapshots.h), read back — listed, compared with now, and restored
// whole, one profile at a time, or one task, note or doc page at a time.

#include "AppController.h"
#include "StateSerializer.h"

#include "platform/Paths.h"
#include "storage/AsyncSaver.h"
#include "storage/Snapshots.h"
#include "storage/StateIO.h"

#include <QDir>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSet>
#include <QTimer>
#include <QUuid>

#include <algorithm>

namespace {

// Past this many rows, a "deleted since" list is not something anyone scrolls.
constexpr int kMaxListedItems = 500;

struct Counts {
  int added = 0;
  int removed = 0;
  int changed = 0;
};

// Whether two versions of an element say the same thing. The order key is left
// out: loading spreads tied ranks and a drag renumbers neighbours, neither of
// which is an edit anyone would want to roll back one card at a time.
template<typename T>
bool sameContent(const T& a, const T& b) {
  if constexpr(requires { a.rank; }) {
    if(a.rank != b.rank) {
      T unranked = b;
      unranked.rank = a.rank;
      return a == unranked;
    }
  }
  return a == b;
}

// Compares two collections of elements with an `id`: what `now` has that
// `then` did not (added), the reverse (removed), and what both hold but
// differently (changed). `removedOut` / `changedOut` get those elements of `then`.
template<typename T>
Counts diffById(const QVector<T>& then, const QVector<T>& now, QVector<T>* removedOut, QVector<T>* changedOut) {
  Counts c;
  QHash<QString, const T*> byId;
  for(const T& x : now) {
    byId.insert(x.id, &x);
  }
  QSet<QString> thenIds;
  for(const T& x : then) {
    thenIds.insert(x.id);
    const T* cur = byId.value(x.id, nullptr);
    if(!cur) {
      ++c.removed;
      if(removedOut) {
        removedOut->append(x);
      }
    } else if(!sameContent(*cur, x)) {
      ++c.changed;
      if(changedOut) {
        changedOut->append(x);
      }
    }
  }
  for(const T& x : now) {
    if(!thenIds.contains(x.id)) {
      ++c.added;
    }
  }
  return c;
}

QVariantMap itemRow(const QString& kind,
                    const QString& id,
                    const QString& title,
                    const QString& profileId,
                    const QString& profileName,
                    bool profileExists) {
  return QVariantMap{{QStringLiteral("kind"), kind},
                     {QStringLiteral("id"), id},
                     {QStringLiteral("title"), title},
                     {QStringLiteral("profileId"), profileId},
                     {QStringLiteral("profileName"), profileName},
                     {QStringLiteral("profileExists"), profileExists}};
}

// "Restore everything" brings back the data — profiles, events, task history —
// and not the app's settings (TM-3). Those describe the install, not a moment
// of the work: the theme, the shortcuts, the integrations, and the time
// machine's own retention, which taken back to the snapshot's (the 30-day
// default, typically) let the next hourly copy prune the months of history
// the user had asked to keep. The snapshot is brought up to this build's
// schema first, so the settings it is given are read at the version they were
// written in. Only `demoActive` comes from the snapshot: it says whether the
// restored profiles are the seeded demo.
QByteArray withCurrentSettings(const QByteArray& snapshot, const QByteArray& current) {
  const QJsonObject now = QJsonDocument::fromJson(current).object();
  if(!now.value(QStringLiteral("settings")).isObject()) {
    return snapshot;
  }
  QJsonObject root = QJsonDocument::fromJson(snapshot).object();
  heap::state::migrateState(root, root.value(QStringLiteral("schemaVersion")).toInt(1));
  const QJsonObject then = root.value(QStringLiteral("settings")).toObject();
  QJsonObject settings = now.value(QStringLiteral("settings")).toObject();
  const QString demo = QStringLiteral("demoActive");
  if(then.contains(demo)) {
    settings.insert(demo, then.value(demo));
  } else {
    settings.remove(demo);
  }
  root.insert(QStringLiteral("settings"), settings);
  return QJsonDocument(root).toJson(QJsonDocument::Compact);
}

}  // namespace

QString AppController::historyDirPath() const {
  return heap::history::dirFor(heap::paths::dataDir());
}

QVariantList AppController::listSnapshots() const {
  QVariantList out;
  const QString dir = historyDirPath();
  for(const heap::history::SnapshotFile& f : heap::history::list(dir)) {
    const QJsonObject s = heap::history::readSummary(dir + QLatin1Char('/') + f.name);
    out.append(QVariantMap{{QStringLiteral("name"), f.name},
                           {QStringLiteral("at"), f.at.toString(Qt::ISODate)},
                           {QStringLiteral("day"), f.at.date().toString(Qt::ISODate)},
                           {QStringLiteral("time"), f.at.toString(QStringLiteral("HH:mm"))},
                           {QStringLiteral("sizeKb"), qMax<qint64>(1, f.bytes / 1024)},
                           {QStringLiteral("tag"), f.tag},
                           {QStringLiteral("profiles"), s.value(QStringLiteral("profiles")).toInt()},
                           {QStringLiteral("tasks"), s.value(QStringLiteral("tasks")).toInt()},
                           {QStringLiteral("notes"), s.value(QStringLiteral("notes")).toInt()},
                           {QStringLiteral("docs"), s.value(QStringLiteral("docs")).toInt()}});
  }
  return out;
}

QString AppController::takeSnapshotNow(const QString& tag) {
  // What is on disk has to be what is on screen: a pending edit goes first.
  if(!m_saveBlocked && !m_loading) {
    if(m_saveTimer) {
      m_saveTimer->stop();
    }
    saveStateNow();
  }
  if(m_saver) {
    m_saver->flush();
  }
  QFile f(stateFilePath());
  if(!f.open(QIODevice::ReadOnly)) {
    return {};
  }
  const QByteArray bytes = f.readAll();
  f.close();
  const QJsonDocument doc = QJsonDocument::fromJson(bytes);
  if(!doc.isObject()) {
    return {};
  }
  return heap::history::write(historyDirPath(), bytes, heap::history::summarize(doc.object()), QDateTime::currentDateTime(), tag);
}

bool AppController::loadSnapshot(const QString& name, QString* error) {
  if(name == m_snapName && !name.isEmpty()) {
    return true;
  }
  // Names come from listSnapshots(); anything with a path in it is not one.
  if(!heap::history::parseName(name) || name.contains(QLatin1Char('/')) || name.contains(QChar(0x5C))) {
    *error = tr_("history.notFound");
    return false;
  }
  QString readError;
  const QByteArray bytes = heap::history::read(historyDirPath() + QLatin1Char('/') + name, &readError);
  const QJsonDocument doc = QJsonDocument::fromJson(bytes);
  if(bytes.isEmpty() || !doc.isObject() || !heap::storage::validateShape(doc.object())) {
    *error = tr_("history.damaged");
    return false;
  }
  QJsonObject root = doc.object();
  const int schema = root.value(QStringLiteral("schemaVersion")).toInt(1);
  if(schema > heap::state::kSchemaVersion) {
    *error = tr_("history.newer");
    return false;
  }
  if(schema < 3) {
    // History began at v11; a v1/v2 document here was put here by hand.
    *error = tr_("history.damaged");
    return false;
  }
  heap::state::migrateState(root, schema);
  QVector<Profile> profiles;
  const QVector<CalEvent> events = heap::state::eventsFromJson(root.value(QStringLiteral("events")).toArray());
  const QJsonArray profilesArr = root.value(QStringLiteral("profiles")).toArray();
  for(const auto& v : profilesArr) {
    profiles.append(heap::state::profileFromJson(v.toObject()));
  }
  m_snapName = name;
  m_snapProfiles = profiles;
  m_snapEvents = events;
  return true;
}

QVariantMap AppController::previewSnapshot(const QString& name) {
  QVariantMap out;
  QString error;
  if(!loadSnapshot(name, &error)) {
    out[QStringLiteral("ok")] = false;
    out[QStringLiteral("error")] = error;
    return out;
  }
  QDateTime at;
  heap::history::parseName(name, &at);

  // The state as it is now, the active profile from its live models.
  QHash<QString, Profile> current;
  QSet<QString> taskIdsNow;
  for(const Profile& p : m_profiles) {
    Profile live = p;
    if(p.id == m_activeProfileId) {
      live.tasks = m_tasks.items();
      live.notes = m_notes.items();
      live.docPages = m_docPages.items();
    }
    for(const Task& t : live.tasks) {
      taskIdsNow.insert(t.id);
    }
    current.insert(p.id, live);
  }

  Counts totalTasks;
  Counts totalNotes;
  Counts totalDocs;
  QVariantList profiles;
  QVariantList missing;
  QVariantList changed;
  for(const Profile& then : m_snapProfiles) {
    const bool exists = current.contains(then.id);
    const Profile now = current.value(then.id);
    QVector<Task> goneTasks;
    QVector<Task> editedTasks;
    QVector<Note> goneNotes;
    QVector<Note> editedNotes;
    QVector<DocPage> goneDocs;
    QVector<DocPage> editedDocs;
    const Counts t = diffById(then.tasks, now.tasks, &goneTasks, &editedTasks);
    const Counts n = diffById(then.notes, now.notes, &goneNotes, &editedNotes);
    const Counts d = diffById(then.docPages, now.docPages, &goneDocs, &editedDocs);
    const auto addTo = [](Counts& total, const Counts& c) {
      total.added += c.added;
      total.removed += c.removed;
      total.changed += c.changed;
    };
    addTo(totalTasks, t);
    addTo(totalNotes, n);
    addTo(totalDocs, d);
    profiles.append(QVariantMap{{QStringLiteral("id"), then.id},
                                {QStringLiteral("name"), then.name},
                                {QStringLiteral("color"), then.color},
                                {QStringLiteral("tasks"), static_cast<int>(then.tasks.size())},
                                {QStringLiteral("notes"), static_cast<int>(then.notes.size())},
                                {QStringLiteral("docs"), static_cast<int>(then.docPages.size())},
                                {QStringLiteral("existsNow"), exists},
                                {QStringLiteral("tasksAdded"), t.added},
                                {QStringLiteral("tasksRemoved"), t.removed},
                                {QStringLiteral("tasksChanged"), t.changed},
                                {QStringLiteral("notesAdded"), n.added + d.added},
                                {QStringLiteral("notesRemoved"), n.removed + d.removed},
                                {QStringLiteral("notesChanged"), n.changed + d.changed}});
    for(const Task& x : goneTasks) {
      // A task that moved to another profile is not gone.
      if(!taskIdsNow.contains(x.id) && missing.size() < kMaxListedItems) {
        missing.append(itemRow(QStringLiteral("task"), x.id, x.title, then.id, then.name, exists));
      }
    }
    for(const Note& x : goneNotes) {
      if(missing.size() < kMaxListedItems) {
        missing.append(itemRow(QStringLiteral("note"), x.id, x.title, then.id, then.name, exists));
      }
    }
    for(const DocPage& x : goneDocs) {
      if(missing.size() < kMaxListedItems) {
        missing.append(itemRow(QStringLiteral("doc"), x.id, x.title, then.id, then.name, exists));
      }
    }
    for(const Task& x : editedTasks) {
      if(changed.size() < kMaxListedItems) {
        changed.append(itemRow(QStringLiteral("task"), x.id, x.title, then.id, then.name, exists));
      }
    }
    for(const Note& x : editedNotes) {
      if(changed.size() < kMaxListedItems) {
        changed.append(itemRow(QStringLiteral("note"), x.id, x.title, then.id, then.name, exists));
      }
    }
    for(const DocPage& x : editedDocs) {
      if(changed.size() < kMaxListedItems) {
        changed.append(itemRow(QStringLiteral("doc"), x.id, x.title, then.id, then.name, exists));
      }
    }
  }
  out[QStringLiteral("ok")] = true;
  out[QStringLiteral("name")] = name;
  out[QStringLiteral("at")] = at.toString(Qt::ISODate);
  out[QStringLiteral("profiles")] = profiles;
  out[QStringLiteral("totals")] = QVariantMap{{QStringLiteral("tasksAdded"), totalTasks.added},
                                              {QStringLiteral("tasksRemoved"), totalTasks.removed},
                                              {QStringLiteral("tasksChanged"), totalTasks.changed},
                                              {QStringLiteral("notesAdded"), totalNotes.added + totalDocs.added},
                                              {QStringLiteral("notesRemoved"), totalNotes.removed + totalDocs.removed},
                                              {QStringLiteral("notesChanged"), totalNotes.changed + totalDocs.changed}};
  out[QStringLiteral("missing")] = missing;
  out[QStringLiteral("changed")] = changed;
  return out;
}

bool AppController::restoreSnapshot(const QString& name) {
  QString error;
  if(!loadSnapshot(name, &error)) {
    emit toast(error, QStringLiteral("warning"));
    return false;
  }
  const QByteArray bytes = heap::history::read(historyDirPath() + QLatin1Char('/') + name);
  if(bytes.isEmpty()) {
    emit toast(tr_("history.damaged"), QStringLiteral("warning"));
    return false;
  }
  // The state being replaced goes into history first, so this restore can be
  // taken back from the same list. If that copy cannot be made, nothing moves.
  if(QFile::exists(stateFilePath()) && takeSnapshotNow(QStringLiteral("pre")).isEmpty()) {
    emit toast(tr_("backup.snapshotFailed"), QStringLiteral("warning"));
    return false;
  }
  // Every task id handed out so far, in any profile, before the state that
  // holds them goes (TM-2).
  const QHash<QString, int> seqBefore = m_taskSeq;
  QStringList idsBefore;
  for(const Profile& p : m_profiles) {
    for(const Task& t : p.id == m_activeProfileId ? m_tasks.items() : p.tasks) {
      idsBefore.append(t.id);
    }
  }
  QByteArray current;
  if(QFile f(stateFilePath()); f.open(QIODevice::ReadOnly)) {
    current = f.readAll();
  }
  if(!replaceStateFile(withCurrentSettings(bytes, current))) {
    return false;
  }
  // The id counter never goes back. Restored to the snapshot's, it handed the
  // next new task the id of one the restore had just removed — and that one
  // is still in the "before restore" snapshot, where it then read as an edit
  // of the new task, and "Use this version" overwrote the new task with it.
  const QHash<QString, int> restored = m_taskSeq;
  for(auto it = seqBefore.constBegin(); it != seqBefore.constEnd(); ++it) {
    m_taskSeq.insert(it.key(), qMax(it.value(), m_taskSeq.value(it.key(), 1)));
  }
  for(const QString& id : std::as_const(idsBefore)) {
    noteTaskIdUsed(id);
  }
  if(m_taskSeq != restored) {
    scheduleSave();
  }
  QDateTime at;
  heap::history::parseName(name, &at);
  emit toast(tr_("history.restored").arg(at.toString(QStringLiteral("dd.MM HH:mm"))));
  return true;
}

QString AppController::restoreSnapshotProfile(const QString& name, const QString& profileId) {
  QString error;
  if(!loadSnapshot(name, &error)) {
    emit toast(error, QStringLiteral("warning"));
    return {};
  }
  const auto it = std::find_if(m_snapProfiles.cbegin(), m_snapProfiles.cend(), [&profileId](const Profile& p) {
    return p.id == profileId;
  });
  if(it == m_snapProfiles.cend()) {
    emit toast(tr_("history.notFound"), QStringLiteral("warning"));
    return {};
  }
  QDateTime at;
  heap::history::parseName(name, &at);
  Profile copy = *it;
  copy.name = uniqueProfileName(tr_("history.restoredName").arg(copy.name).arg(at.toString(QStringLiteral("HH:mm"))));
  copy.id = makeProfileId(copy.name);
  copy.createdAt = QDateTime::currentDateTime();
  QVector<CalEvent> events;
  for(const CalEvent& e : m_snapEvents) {
    if(e.profileId == profileId) {
      events.append(e);
    }
  }
  snapshotActiveProfile();
  // The copy's tasks are new tasks: an id the live profile still holds gets a
  // fresh one, and the copied events follow it (PLAT-9).
  reissueSharedTaskIds(copy, &events);
  m_profiles.push_back(copy);
  // The copied overrides follow the copied series, as duplicateProfile's do (TM-1).
  addEventsAsCopies(events, copy.id);
  emit profilesChanged();
  emit toast(tr_("history.profileRestored").arg(copy.name));
  scheduleSave();
  return copy.id;
}

bool AppController::restoreSnapshotItem(const QString& name, const QString& kind, const QString& profileId, const QString& itemId) {
  QString error;
  if(!loadSnapshot(name, &error)) {
    emit toast(error, QStringLiteral("warning"));
    return false;
  }
  const auto pit = std::find_if(m_snapProfiles.cbegin(), m_snapProfiles.cend(), [&profileId](const Profile& p) {
    return p.id == profileId;
  });
  if(pit == m_snapProfiles.cend()) {
    emit toast(tr_("history.notFound"), QStringLiteral("warning"));
    return false;
  }
  if(profileIndexOf(profileId) < 0) {
    // Nowhere to put it back: the profile itself is gone.
    emit toast(tr_("history.profileGone").arg(pit->name), QStringLiteral("warning"));
    return false;
  }
  const Profile& then = *pit;

  if(kind == QLatin1String("task")) {
    const auto t = std::find_if(then.tasks.cbegin(), then.tasks.cend(), [&itemId](const Task& x) {
      return x.id == itemId;
    });
    if(t == then.tasks.cend()) {
      emit toast(tr_("history.notFound"), QStringLiteral("warning"));
      return false;
    }
    // A task id is a key across the app (TASKS-1): one that lives in another
    // profile now was moved, not lost, and two copies of it would collide.
    for(const Profile& p : m_profiles) {
      const QVector<Task>& tasks = p.id == m_activeProfileId ? m_tasks.items() : p.tasks;
      const bool holds = std::any_of(tasks.cbegin(), tasks.cend(), [&itemId](const Task& x) {
        return x.id == itemId;
      });
      if(holds && p.id != profileId) {
        emit toast(tr_("history.taskElsewhere").arg(itemId).arg(p.name), QStringLiteral("warning"));
        return false;
      }
    }
    setActiveProfileId(profileId);
    const bool wasGone = m_tasks.indexOfId(itemId) < 0;
    {
      const UndoScope scope(this, tr_("history.undo.item").arg(t->title));
      m_tasks.upsert(*t);
      // Its calendar blocks went with it (deleteTask); they come back with it.
      if(wasGone) {
        for(const CalEvent& e : m_snapEvents) {
          if(e.taskId == itemId && m_events.indexOfId(e.id) < 0) {
            m_events.upsert(e);
          }
        }
      }
    }
    noteTaskIdUsed(itemId);
    if(wasGone) {
      // Deleting a mirrored issue told its tracker "not mine"; bringing it
      // back withdraws that, as undoing the delete would.
      restoreExternalTask(t->externalProvider, t->externalId);
    }
    scheduleSave();
    emit undoableToast(tr_("history.itemRestored").arg(t->title), 8);
    return true;
  }

  if(kind == QLatin1String("note")) {
    const auto n = std::find_if(then.notes.cbegin(), then.notes.cend(), [&itemId](const Note& x) {
      return x.id == itemId;
    });
    if(n == then.notes.cend()) {
      emit toast(tr_("history.notFound"), QStringLiteral("warning"));
      return false;
    }
    setActiveProfileId(profileId);
    emit aboutToChangeActiveNote();
    syncActiveNoteBody();
    {
      const UndoScope scope(this, tr_("history.undo.item").arg(n->title));
      m_notes.upsert(*n);
    }
    reconcileActiveNote();
    scheduleSave();
    emit undoableToast(tr_("history.itemRestored").arg(n->title), 8);
    return true;
  }

  if(kind == QLatin1String("doc")) {
    const auto d = std::find_if(then.docPages.cbegin(), then.docPages.cend(), [&itemId](const DocPage& x) {
      return x.id == itemId;
    });
    if(d == then.docPages.cend()) {
      emit toast(tr_("history.notFound"), QStringLiteral("warning"));
      return false;
    }
    setActiveProfileId(profileId);
    emit flushEditorsRequested();
    DocPage page = *d;
    // Its parent may be gone too; a page under nothing is unreachable, so it
    // comes back at the top of the tree.
    if(!page.parentId.isEmpty() && m_docPages.indexOfId(page.parentId) < 0) {
      page.parentId.clear();
    }
    {
      const UndoScope scope(this, tr_("history.undo.item").arg(page.title));
      m_docPages.upsert(page);
    }
    if(page.id == m_activeDocPageId) {
      emit activeDocPageChanged();
    }
    scheduleSave();
    emit undoableToast(tr_("history.itemRestored").arg(page.title), 8);
    return true;
  }
  return false;
}
