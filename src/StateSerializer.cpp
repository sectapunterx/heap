#include "FieldCount.h"
#include "StateSerializer.h"

#include <QColor>
#include <QJsonDocument>
#include <QJsonValue>
#include <QTime>

namespace heap::state {

namespace {

// Every declared field of Task and CalEvent has to survive toJson→fromJson. The
// counts below are the guard: add a field and this build fails until the
// serializers here, the ones in sync/SyncSerializer.cpp, and the round-trip
// fixture in tests/test_roundtrip.cpp all learn about it.
static_assert(heap::meta::fieldCount<Task>() == 21,
              "Task gained or lost a field. Update taskToJson/taskFromJson here AND in "
              "src/sync/SyncSerializer.cpp, extend makeFullTask() in tests/test_roundtrip.cpp, "
              "then bump this count.");
static_assert(heap::meta::fieldCount<CalEvent>() == 10,
              "CalEvent gained or lost a field. Update eventToJson/eventFromJson here AND in "
              "src/sync/SyncSerializer.cpp, extend makeFullEvent() in tests/test_roundtrip.cpp, "
              "then bump this count.");

// Milliseconds are written so a QDateTime round-trips exactly; Qt::ISODate on the
// read side accepts both the fractional and the whole-second form, so files
// written before this change still parse.
QString dtToStr(const QDateTime& dt) {
  return dt.isValid() ? dt.toString(Qt::ISODateWithMs) : QString();
}

QDateTime dtFromStr(const QString& s) {
  return s.isEmpty() ? QDateTime() : QDateTime::fromString(s, Qt::ISODate);
}

QJsonArray labelsToJson(const QVector<Label>& labels) {
  QJsonArray a;
  for(const Label& l : labels) {
    QJsonObject o;
    o["id"] = l.id;
    o["color"] = l.color;
    a.append(o);
  }
  return a;
}

QVector<Label> labelsFromJson(const QJsonArray& a) {
  QVector<Label> out;
  out.reserve(a.size());
  for(const auto& it : a) {
    const QJsonObject o = it.toObject();
    out.append(Label{o["id"].toString(), o["color"].toString()});
  }
  return out;
}

}  // namespace

// ───────────────── Task ─────────────────

QJsonObject taskToJson(const Task& t) {
  QJsonObject o;
  o["id"] = t.id;
  o["title"] = t.title;
  o["desc"] = t.desc;
  o["priority"] = t.priority;
  o["status"] = t.status;
  o["branch"] = t.branch;
  o["statusChangedAt"] = dtToStr(t.statusChangedAt);
  o["archived"] = t.archived;
  // Scheduling (HEAP-115) — omitted when unset so an undated task's JSON stays
  // as small as it was when `deadline` was a bare date.
  if(t.scheduledAt.isValid()) {
    o["scheduledAt"] = dtToStr(t.scheduledAt);
  }
  if(t.dueAt.isValid()) {
    o["dueAt"] = dtToStr(t.dueAt);
  }
  if(t.hasTime) {
    o["hasTime"] = true;
  }
  // Time tracking (HEAP-78) — omitted when zero/stopped so untimed task JSON
  // stays byte-identical.
  if(t.trackedSeconds > 0) {
    o["trackedSeconds"] = t.trackedSeconds;
  }
  if(t.timerStartedAt.isValid()) {
    o["timerStartedAt"] = dtToStr(t.timerStartedAt);
  }
  // Recurrence (HEAP-77) — omitted for non-recurring tasks.
  if(!t.recurrence.isEmpty()) {
    o["recurrence"] = t.recurrence;
  }
  // Tracker-sync link — only emitted for synced tasks so locally-created
  // task JSON stays byte-identical to before HEAP-74.
  if(!t.externalId.isEmpty()) {
    o["externalId"] = t.externalId;
    o["externalUrl"] = t.externalUrl;
    o["externalProvider"] = t.externalProvider;
  }
  // Planning fields (HEAP-124).
  if(!t.labels.isEmpty()) {
    o["labels"] = labelsToJson(t.labels);
  }
  if(t.estimateMinutes > 0) {
    o["estimateMinutes"] = t.estimateMinutes;
  }
  if(t.someday) {
    o["someday"] = true;
  }
  if(!t.assignee.isEmpty()) {
    o["assignee"] = t.assignee;
  }
  return o;
}

Task taskFromJson(const QJsonObject& o) {
  Task t;
  t.id = o["id"].toString();
  t.title = o["title"].toString();
  t.desc = o["desc"].toString();
  t.priority = o["priority"].toString();
  t.status = o["status"].toString();
  t.branch = o["branch"].toString();
  t.statusChangedAt = dtFromStr(o["statusChangedAt"].toString());
  if(!t.statusChangedAt.isValid()) {
    t.statusChangedAt = QDateTime::currentDateTime();
  }
  t.archived = o["archived"].toBool(false);
  t.scheduledAt = dtFromStr(o["scheduledAt"].toString());
  t.dueAt = dtFromStr(o["dueAt"].toString());
  t.hasTime = o["hasTime"].toBool(false);
  // Legacy bare-date deadline (schema ≤ 3, and any profile exported by an older
  // build). state.json itself is migrated by migrateState() before it reaches
  // here; this covers imports, which carry no schema ladder.
  if(!t.scheduledAt.isValid() && !t.dueAt.isValid()) {
    const QDate legacy = QDate::fromString(o["deadline"].toString(), Qt::ISODate);
    if(legacy.isValid()) {
      t.scheduledAt = QDateTime(legacy, QTime(0, 0));
      t.dueAt = t.scheduledAt;
      t.hasTime = false;
    }
  }
  t.trackedSeconds = o["trackedSeconds"].toInt(0);
  t.timerStartedAt = dtFromStr(o["timerStartedAt"].toString());
  t.recurrence = o["recurrence"].toString();
  t.externalId = o["externalId"].toString();
  t.externalUrl = o["externalUrl"].toString();
  t.externalProvider = o["externalProvider"].toString();
  t.labels = labelsFromJson(o["labels"].toArray());
  t.estimateMinutes = o["estimateMinutes"].toInt(0);
  t.someday = o["someday"].toBool(false);
  t.assignee = o["assignee"].toString();
  return t;
}

QJsonArray tasksToJson(const QVector<Task>& xs) {
  QJsonArray a;
  for(const Task& t : xs) {
    a.append(taskToJson(t));
  }
  return a;
}

QVector<Task> tasksFromJson(const QJsonArray& a) {
  QVector<Task> v;
  v.reserve(a.size());
  for(const auto& it : a) {
    v.append(taskFromJson(it.toObject()));
  }
  return v;
}

// ───────────────── CalEvent ─────────────────

QJsonObject eventToJson(const CalEvent& e) {
  QJsonObject o;
  o["id"] = e.id;
  o["title"] = e.title;
  o["type"] = e.type;
  o["start"] = e.start;
  o["end"] = e.end;
  o["attendees"] = e.attendees;
  o["date"] = e.date.isValid() ? e.date.toString(Qt::ISODate) : QString();
  o["taskId"] = e.taskId;
  o["profileId"] = e.profileId;
  o["context"] = e.context;
  return o;
}

CalEvent eventFromJson(const QJsonObject& o, const QString& fallbackProfileId) {
  CalEvent e;
  e.id = o["id"].toString();
  e.title = o["title"].toString();
  e.type = o["type"].toString();
  e.start = o["start"].toDouble();
  e.end = o["end"].toDouble();
  e.attendees = o["attendees"].toString();
  e.date = QDate::fromString(o["date"].toString(), Qt::ISODate);
  e.taskId = o["taskId"].toString();
  e.profileId = o.contains("profileId") ? o["profileId"].toString() : fallbackProfileId;
  e.context = o["context"].toString();
  return e;
}

QJsonArray eventsToJson(const QVector<CalEvent>& xs) {
  QJsonArray a;
  for(const CalEvent& e : xs) {
    a.append(eventToJson(e));
  }
  return a;
}

QVector<CalEvent> eventsFromJson(const QJsonArray& a, const QString& fallbackProfileId) {
  QVector<CalEvent> v;
  v.reserve(a.size());
  for(const auto& it : a) {
    v.append(eventFromJson(it.toObject(), fallbackProfileId));
  }
  return v;
}

// ───────────────── Person / statuses ─────────────────

QJsonArray peopleToJson(const QVector<Person>& xs) {
  QJsonArray a;
  for(const Person& p : xs) {
    QJsonObject o;
    o["id"] = p.id;
    o["name"] = p.name;
    o["role"] = p.role;
    o["question"] = p.question;
    o["state"] = p.state;
    o["color"] = p.color.name();
    a.append(o);
  }
  return a;
}

QVector<Person> peopleFromJson(const QJsonArray& a) {
  QVector<Person> v;
  v.reserve(a.size());
  for(const auto& it : a) {
    const QJsonObject o = it.toObject();
    Person p;
    p.id = o["id"].toString();
    p.name = o["name"].toString();
    p.role = o["role"].toString();
    p.question = o["question"].toString();
    p.state = o["state"].toString();
    p.color = QColor(o["color"].toString());
    v.append(p);
  }
  return v;
}

QJsonArray statusesToJson(const QVariantList& xs) {
  QJsonArray a;
  for(const QVariant& v : xs) {
    const QVariantMap m = v.toMap();
    QJsonObject o;
    o["id"] = m.value("id").toString();
    o["name"] = m.value("name").toString();
    const QVariant col = m.value("color");
    o["color"] = col.canConvert<QColor>() ? col.value<QColor>().name() : col.toString();
    a.append(o);
  }
  return a;
}

QVariantList statusesFromJson(const QJsonArray& a) {
  QVariantList v;
  for(const auto& it : a) {
    const QJsonObject o = it.toObject();
    QVariantMap m;
    m["id"] = o["id"].toString();
    m["name"] = o["name"].toString();
    m["color"] = QColor(o["color"].toString());
    v.append(m);
  }
  return v;
}

// ───────────────── Profile ─────────────────

QJsonObject profileToJson(const Profile& p) {
  QJsonObject o;
  o["id"] = p.id;
  o["name"] = p.name;
  o["color"] = p.color;
  o["createdAt"] = dtToStr(p.createdAt);
  o["tasks"] = tasksToJson(p.tasks);
  o["people"] = peopleToJson(p.people);
  o["statuses"] = statusesToJson(p.statuses);
  if(!p.docsState.isEmpty()) {
    const QJsonDocument d = QJsonDocument::fromJson(p.docsState.toUtf8());
    if(!d.isNull() && d.isObject()) {
      o["docs"] = d.object();
    }
  }
  if(!p.notesState.isEmpty()) {
    o["notes"] = p.notesState;
  }
  return o;
}

Profile profileFromJson(const QJsonObject& o, QVector<CalEvent>* outLegacyEvents) {
  Profile p;
  p.id = o["id"].toString();
  p.name = o["name"].toString();
  p.color = o["color"].toString();
  p.createdAt = dtFromStr(o["createdAt"].toString());
  p.tasks = tasksFromJson(o["tasks"].toArray());
  p.people = peopleFromJson(o["people"].toArray());
  p.statuses = statusesFromJson(o["statuses"].toArray());
  if(o.contains("docs")) {
    p.docsState = QJsonDocument(o["docs"].toObject()).toJson(QJsonDocument::Compact);
  }
  if(o.contains("notes")) {
    p.notesState = o["notes"].toString();
  }
  if(outLegacyEvents && o.contains("events")) {
    outLegacyEvents->append(eventsFromJson(o["events"].toArray(), p.id));
  }
  return p;
}

// ───────────────── Migration ─────────────────

namespace {

// v3→v4: a bare `deadline` date becomes a scheduledAt/dueAt pair at midnight
// with no clock component. Both are set so the task keeps showing up wherever a
// due date used to put it while also being schedulable.
void migrateTaskV3ToV4(QJsonObject& task) {
  if(!task.contains("deadline")) {
    return;
  }
  const QDate legacy = QDate::fromString(task["deadline"].toString(), Qt::ISODate);
  task.remove("deadline");
  if(!legacy.isValid()) {
    return;  // an empty "" deadline: dropping the dead key is the whole migration
  }
  if(!task.contains("scheduledAt") && !task.contains("dueAt")) {
    const QString at = dtToStr(QDateTime(legacy, QTime(0, 0)));
    task["scheduledAt"] = at;
    task["dueAt"] = at;
    task["hasTime"] = false;
  }
}

// Rebuilds the array rather than writing back through an index: QJsonArray's
// subscript hands out a reference proxy, and in-place index mutation is exactly
// the shape a well-meaning "modernize to a range-for" rewrite would break.
QJsonArray migratedTaskArrayV3ToV4(const QJsonArray& tasks) {
  QJsonArray out;
  for(const QJsonValue& v : tasks) {
    QJsonObject t = v.toObject();
    migrateTaskV3ToV4(t);
    out.append(t);
  }
  return out;
}

}  // namespace

bool migrateState(QJsonObject& root, int fromVersion) {
  if(fromVersion >= kSchemaVersion) {
    return false;  // the version gate: a v4 document is never re-migrated
  }

  // Tasks live under profiles[].tasks from v2 on, and at the top level in v1.
  if(root.contains("profiles")) {
    QJsonArray profiles;
    for(const QJsonValue& v : root["profiles"].toArray()) {
      QJsonObject p = v.toObject();
      p["tasks"] = migratedTaskArrayV3ToV4(p["tasks"].toArray());
      profiles.append(p);
    }
    root["profiles"] = profiles;
  } else if(root.contains("tasks")) {
    root["tasks"] = migratedTaskArrayV3ToV4(root["tasks"].toArray());
  }

  root["schemaVersion"] = kSchemaVersion;
  return true;
}

}  // namespace heap::state
