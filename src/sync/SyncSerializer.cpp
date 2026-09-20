#include "FieldCount.h"

#include "sync/SyncSerializer.h"

#include <QJsonDocument>
#include <QJsonValue>
#include <QTime>

#include <algorithm>

namespace heap::sync {

namespace {

// Kept in lockstep with src/StateSerializer.cpp: a field that only one of the
// two serializers knows about is a field the sync transport will drop (HEAP-131).
static_assert(heap::meta::fieldCount<TaskLink>() == 2,
              "TaskLink gained or lost a field. Update linksToJson/linksFromJson here AND in "
              "src/StateSerializer.cpp, extend makeFullTask() in tests/test_roundtrip.cpp, "
              "then bump this count.");
static_assert(heap::meta::fieldCount<Task>() == 24,
              "Task gained or lost a field. Update taskToJson/taskFromJson here AND in "
              "src/StateSerializer.cpp, extend makeFullTask() in tests/test_roundtrip.cpp, "
              "then bump this count.");
static_assert(heap::meta::fieldCount<ExternalMeta>() == 9,
              "ExternalMeta gained or lost a field. Update externalMetaToJson/FromJson here AND "
              "in src/StateSerializer.cpp, extend makeFullTask() in tests/test_roundtrip.cpp, "
              "then bump this count.");
static_assert(heap::meta::fieldCount<CalEvent>() == 10,
              "CalEvent gained or lost a field. Update eventToJson/eventFromJson here AND in "
              "src/StateSerializer.cpp, extend makeFullEvent() in tests/test_roundtrip.cpp, "
              "then bump this count.");

// QDate/QDateTime ↔ ISO string, with invalid mapping to "" (round-trip safe).
// Datetimes carry milliseconds out; Qt::ISODate parses them back and still
// accepts the whole-second form written by older builds.
QString dateToStr(const QDate& d) {
  return d.isValid() ? d.toString(Qt::ISODate) : QString();
}

QDate dateFromStr(const QString& s) {
  return s.isEmpty() ? QDate() : QDate::fromString(s, Qt::ISODate);
}

QString dateTimeToStr(const QDateTime& dt) {
  return dt.isValid() ? dt.toString(Qt::ISODateWithMs) : QString();
}

QDateTime dateTimeFromStr(const QString& s) {
  return s.isEmpty() ? QDateTime() : QDateTime::fromString(s, Qt::ISODate);
}

QJsonArray labelsToJson(const QVector<Label>& labels) {
  QJsonArray a;
  for(const Label& l : labels) {
    QJsonObject o;
    o[QStringLiteral("id")] = l.id;
    o[QStringLiteral("color")] = l.color;
    a.append(o);
  }
  return a;
}

QVector<Label> labelsFromJson(const QJsonArray& a) {
  QVector<Label> out;
  out.reserve(a.size());
  for(const QJsonValue& v : a) {
    const QJsonObject o = v.toObject();
    out.append(Label{o.value(QStringLiteral("id")).toString(), o.value(QStringLiteral("color")).toString()});
  }
  return out;
}

QJsonArray linksToJson(const QVector<TaskLink>& links) {
  QJsonArray a;
  for(const TaskLink& l : links) {
    QJsonObject o;
    o[QStringLiteral("type")] = l.type;
    o[QStringLiteral("targetId")] = l.targetId;
    a.append(o);
  }
  return a;
}

QVector<TaskLink> linksFromJson(const QJsonArray& a) {
  QVector<TaskLink> out;
  out.reserve(a.size());
  for(const QJsonValue& v : a) {
    const QJsonObject o = v.toObject();
    out.append(TaskLink{o.value(QStringLiteral("type")).toString(), o.value(QStringLiteral("targetId")).toString()});
  }
  return out;
}

}  // namespace

QJsonArray SyncSerializer::sortedById(const QJsonArray& arr) {
  QVector<QJsonObject> items;
  items.reserve(arr.size());
  for(const QJsonValue& v : arr) {
    items.append(v.toObject());
  }
  std::stable_sort(items.begin(), items.end(), [](const QJsonObject& a, const QJsonObject& b) {
    return a.value(QStringLiteral("id")).toString() < b.value(QStringLiteral("id")).toString();
  });
  QJsonArray out;
  for(const QJsonObject& o : items) {
    out.append(o);
  }
  return out;
}

// ── Task ──
// Every field is emitted unconditionally: this file feeds a 3-way merge, and a
// key that disappears when its value is default is a key the merger reads as
// "deleted on the other side".
QJsonObject SyncSerializer::taskToJson(const Task& t) {
  QJsonObject o;
  o[QStringLiteral("id")] = t.id;
  o[QStringLiteral("title")] = t.title;
  o[QStringLiteral("desc")] = t.desc;
  o[QStringLiteral("priority")] = t.priority;
  o[QStringLiteral("status")] = t.status;
  o[QStringLiteral("scheduledAt")] = dateTimeToStr(t.scheduledAt);
  o[QStringLiteral("dueAt")] = dateTimeToStr(t.dueAt);
  o[QStringLiteral("hasTime")] = t.hasTime;
  o[QStringLiteral("branch")] = t.branch;
  o[QStringLiteral("statusChangedAt")] = dateTimeToStr(t.statusChangedAt);
  o[QStringLiteral("archived")] = t.archived;
  o[QStringLiteral("trackedSeconds")] = t.trackedSeconds;
  o[QStringLiteral("timerStartedAt")] = dateTimeToStr(t.timerStartedAt);
  o[QStringLiteral("recurrence")] = t.recurrence;
  o[QStringLiteral("externalId")] = t.externalId;
  o[QStringLiteral("externalUrl")] = t.externalUrl;
  o[QStringLiteral("externalProvider")] = t.externalProvider;
  o[QStringLiteral("labels")] = labelsToJson(t.labels);
  o[QStringLiteral("estimateMinutes")] = t.estimateMinutes;
  o[QStringLiteral("someday")] = t.someday;
  o[QStringLiteral("assignee")] = t.assignee;
  o[QStringLiteral("rank")] = t.rank;
  o[QStringLiteral("links")] = linksToJson(t.links);
  // Tracker metadata (HEAP-117). Nested, and its timestamps are deliberately
  // not named `updatedAt`/`createdAt`: JsonMerger reads those names at a task's
  // top level as heap's own last-write clock, and it applies "earlier wins" to
  // a `createdAt` at any depth.
  QJsonObject meta;
  meta[QStringLiteral("author")] = t.externalMeta.author;
  meta[QStringLiteral("issueType")] = t.externalMeta.issueType;
  meta[QStringLiteral("project")] = t.externalMeta.project;
  meta[QStringLiteral("milestone")] = t.externalMeta.milestone;
  meta[QStringLiteral("commentCount")] = t.externalMeta.commentCount;
  meta[QStringLiteral("remoteCreatedAt")] = dateTimeToStr(t.externalMeta.createdAt);
  meta[QStringLiteral("remoteUpdatedAt")] = dateTimeToStr(t.externalMeta.updatedAt);
  meta[QStringLiteral("remoteDueAt")] = dateTimeToStr(t.externalMeta.dueAt);
  meta[QStringLiteral("crossProject")] = t.externalMeta.crossProject;
  o[QStringLiteral("externalMeta")] = meta;
  return o;
}

Task SyncSerializer::taskFromJson(const QJsonObject& o) {
  Task t;
  t.id = o.value(QStringLiteral("id")).toString();
  t.title = o.value(QStringLiteral("title")).toString();
  t.desc = o.value(QStringLiteral("desc")).toString();
  t.priority = o.value(QStringLiteral("priority")).toString();
  t.status = o.value(QStringLiteral("status")).toString();
  t.scheduledAt = dateTimeFromStr(o.value(QStringLiteral("scheduledAt")).toString());
  t.dueAt = dateTimeFromStr(o.value(QStringLiteral("dueAt")).toString());
  t.hasTime = o.value(QStringLiteral("hasTime")).toBool();
  // A document written before HEAP-115 carries a bare date instead.
  if(!t.scheduledAt.isValid() && !t.dueAt.isValid()) {
    const QDate legacy = dateFromStr(o.value(QStringLiteral("deadline")).toString());
    if(legacy.isValid()) {
      t.scheduledAt = QDateTime(legacy, QTime(0, 0));
      t.dueAt = t.scheduledAt;
    }
  }
  t.branch = o.value(QStringLiteral("branch")).toString();
  t.statusChangedAt = dateTimeFromStr(o.value(QStringLiteral("statusChangedAt")).toString());
  t.archived = o.value(QStringLiteral("archived")).toBool();
  t.trackedSeconds = o.value(QStringLiteral("trackedSeconds")).toInt();
  t.timerStartedAt = dateTimeFromStr(o.value(QStringLiteral("timerStartedAt")).toString());
  t.recurrence = o.value(QStringLiteral("recurrence")).toString();
  t.externalId = o.value(QStringLiteral("externalId")).toString();
  t.externalUrl = o.value(QStringLiteral("externalUrl")).toString();
  t.externalProvider = o.value(QStringLiteral("externalProvider")).toString();
  t.labels = labelsFromJson(o.value(QStringLiteral("labels")).toArray());
  t.estimateMinutes = o.value(QStringLiteral("estimateMinutes")).toInt();
  t.someday = o.value(QStringLiteral("someday")).toBool();
  t.assignee = o.value(QStringLiteral("assignee")).toString();
  const QJsonObject meta = o.value(QStringLiteral("externalMeta")).toObject();
  t.externalMeta.author = meta.value(QStringLiteral("author")).toString();
  t.externalMeta.issueType = meta.value(QStringLiteral("issueType")).toString();
  t.externalMeta.project = meta.value(QStringLiteral("project")).toString();
  t.externalMeta.milestone = meta.value(QStringLiteral("milestone")).toString();
  t.externalMeta.commentCount = meta.value(QStringLiteral("commentCount")).toInt(-1);
  t.externalMeta.createdAt = dateTimeFromStr(meta.value(QStringLiteral("remoteCreatedAt")).toString());
  t.externalMeta.updatedAt = dateTimeFromStr(meta.value(QStringLiteral("remoteUpdatedAt")).toString());
  t.externalMeta.dueAt = dateTimeFromStr(meta.value(QStringLiteral("remoteDueAt")).toString());
  t.externalMeta.crossProject = meta.value(QStringLiteral("crossProject")).toBool();
  t.rank = o.value(QStringLiteral("rank")).toDouble();
  t.links = linksFromJson(o.value(QStringLiteral("links")).toArray());
  return t;
}

// ── Person ──
QJsonObject SyncSerializer::personToJson(const Person& p) {
  QJsonObject o;
  o[QStringLiteral("id")] = p.id;
  o[QStringLiteral("name")] = p.name;
  o[QStringLiteral("role")] = p.role;
  o[QStringLiteral("question")] = p.question;
  o[QStringLiteral("state")] = p.state;
  o[QStringLiteral("color")] = p.color.isValid() ? p.color.name(QColor::HexRgb) : QString();
  return o;
}

Person SyncSerializer::personFromJson(const QJsonObject& o) {
  Person p;
  p.id = o.value(QStringLiteral("id")).toString();
  p.name = o.value(QStringLiteral("name")).toString();
  p.role = o.value(QStringLiteral("role")).toString();
  p.question = o.value(QStringLiteral("question")).toString();
  p.state = o.value(QStringLiteral("state")).toString();
  const QString c = o.value(QStringLiteral("color")).toString();
  p.color = c.isEmpty() ? QColor() : QColor(c);
  return p;
}

// ── CalEvent ──
QJsonObject SyncSerializer::eventToJson(const CalEvent& e) {
  QJsonObject o;
  o[QStringLiteral("id")] = e.id;
  o[QStringLiteral("title")] = e.title;
  o[QStringLiteral("type")] = e.type;
  o[QStringLiteral("start")] = e.start;
  o[QStringLiteral("end")] = e.end;
  o[QStringLiteral("attendees")] = e.attendees;
  o[QStringLiteral("date")] = dateToStr(e.date);
  o[QStringLiteral("taskId")] = e.taskId;
  o[QStringLiteral("profileId")] = e.profileId;
  o[QStringLiteral("context")] = e.context;
  return o;
}

CalEvent SyncSerializer::eventFromJson(const QJsonObject& o) {
  CalEvent e;
  e.id = o.value(QStringLiteral("id")).toString();
  e.title = o.value(QStringLiteral("title")).toString();
  e.type = o.value(QStringLiteral("type")).toString();
  e.start = o.value(QStringLiteral("start")).toDouble();
  e.end = o.value(QStringLiteral("end")).toDouble();
  e.attendees = o.value(QStringLiteral("attendees")).toString();
  e.date = dateFromStr(o.value(QStringLiteral("date")).toString());
  e.taskId = o.value(QStringLiteral("taskId")).toString();
  e.profileId = o.value(QStringLiteral("profileId")).toString();
  e.context = o.value(QStringLiteral("context")).toString();
  return e;
}

// ── Profile ──
QByteArray SyncSerializer::serializeProfile(const Profile& p) {
  QJsonObject root;
  root[QStringLiteral("id")] = p.id;
  root[QStringLiteral("name")] = p.name;
  root[QStringLiteral("color")] = p.color;
  root[QStringLiteral("createdAt")] = dateTimeToStr(p.createdAt);

  QJsonArray tasks;
  for(const Task& t : p.tasks) {
    tasks.append(taskToJson(t));
  }
  root[QStringLiteral("tasks")] = sortedById(tasks);

  QJsonArray people;
  for(const Person& person : p.people) {
    people.append(personToJson(person));
  }
  root[QStringLiteral("people")] = sortedById(people);

  QJsonArray statuses;
  for(const QVariant& v : p.statuses) {
    statuses.append(QJsonObject::fromVariantMap(v.toMap()));
  }
  root[QStringLiteral("statuses")] = sortedById(statuses);

  // Free-form blobs kept verbatim: lossless and idempotent across round-trips.
  root[QStringLiteral("docsState")] = p.docsState;
  root[QStringLiteral("notesState")] = p.notesState;

  return QJsonDocument(root).toJson(QJsonDocument::Indented);
}

std::optional<Profile> SyncSerializer::deserializeProfile(const QByteArray& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if(!doc.isObject()) {
    return std::nullopt;
  }
  const QJsonObject root = doc.object();
  Profile p;
  p.id = root.value(QStringLiteral("id")).toString();
  p.name = root.value(QStringLiteral("name")).toString();
  p.color = root.value(QStringLiteral("color")).toString();
  p.createdAt = dateTimeFromStr(root.value(QStringLiteral("createdAt")).toString());

  for(const QJsonValue& v : root.value(QStringLiteral("tasks")).toArray()) {
    p.tasks.append(taskFromJson(v.toObject()));
  }
  for(const QJsonValue& v : root.value(QStringLiteral("people")).toArray()) {
    p.people.append(personFromJson(v.toObject()));
  }
  for(const QJsonValue& v : root.value(QStringLiteral("statuses")).toArray()) {
    p.statuses.append(v.toObject().toVariantMap());
  }
  p.docsState = root.value(QStringLiteral("docsState")).toString();
  p.notesState = root.value(QStringLiteral("notesState")).toString();
  return p;
}

// ── Events file ──
QByteArray SyncSerializer::serializeEvents(const QVector<CalEvent>& events) {
  QJsonArray arr;
  for(const CalEvent& e : events) {
    arr.append(eventToJson(e));
  }
  QJsonObject root;
  root[QStringLiteral("events")] = sortedById(arr);
  return QJsonDocument(root).toJson(QJsonDocument::Indented);
}

QVector<CalEvent> SyncSerializer::deserializeEvents(const QByteArray& json) {
  QVector<CalEvent> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if(!doc.isObject()) {
    return out;
  }
  for(const QJsonValue& v : doc.object().value(QStringLiteral("events")).toArray()) {
    out.append(eventFromJson(v.toObject()));
  }
  return out;
}

}  // namespace heap::sync
