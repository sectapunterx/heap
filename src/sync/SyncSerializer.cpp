#include "sync/SyncSerializer.h"

#include <QJsonDocument>
#include <QJsonValue>

#include <algorithm>

namespace heap::sync {

namespace {

// QDate/QDateTime ↔ ISO string, with invalid mapping to "" (round-trip safe).
QString dateToStr(const QDate& d) {
  return d.isValid() ? d.toString(Qt::ISODate) : QString();
}
QDate dateFromStr(const QString& s) {
  return s.isEmpty() ? QDate() : QDate::fromString(s, Qt::ISODate);
}
QString dateTimeToStr(const QDateTime& dt) {
  return dt.isValid() ? dt.toString(Qt::ISODate) : QString();
}
QDateTime dateTimeFromStr(const QString& s) {
  return s.isEmpty() ? QDateTime() : QDateTime::fromString(s, Qt::ISODate);
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
QJsonObject SyncSerializer::taskToJson(const Task& t) {
  QJsonObject o;
  o[QStringLiteral("id")] = t.id;
  o[QStringLiteral("title")] = t.title;
  o[QStringLiteral("desc")] = t.desc;
  o[QStringLiteral("priority")] = t.priority;
  o[QStringLiteral("status")] = t.status;
  o[QStringLiteral("deadline")] = dateToStr(t.deadline);
  o[QStringLiteral("branch")] = t.branch;
  o[QStringLiteral("statusChangedAt")] = dateTimeToStr(t.statusChangedAt);
  o[QStringLiteral("archived")] = t.archived;
  return o;
}

Task SyncSerializer::taskFromJson(const QJsonObject& o) {
  Task t;
  t.id = o.value(QStringLiteral("id")).toString();
  t.title = o.value(QStringLiteral("title")).toString();
  t.desc = o.value(QStringLiteral("desc")).toString();
  t.priority = o.value(QStringLiteral("priority")).toString();
  t.status = o.value(QStringLiteral("status")).toString();
  t.deadline = dateFromStr(o.value(QStringLiteral("deadline")).toString());
  t.branch = o.value(QStringLiteral("branch")).toString();
  t.statusChangedAt = dateTimeFromStr(o.value(QStringLiteral("statusChangedAt")).toString());
  t.archived = o.value(QStringLiteral("archived")).toBool();
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
