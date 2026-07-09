#pragma once

#include "Models.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QVariantList>
#include <QVector>

// The live state.json (de)serializer: what AppController::saveStateNow writes,
// what loadStateOnStart reads, and what profile export/import uses. Extracted
// from AppController's anonymous namespace so the round-trip and field-count
// guards can exercise the real save path rather than a look-alike (HEAP-131).
namespace heap::state {

// Bumped whenever the on-disk shape changes; migrateState() knows how to walk a
// document from any older version up to this one.
//   v2  profiles array, events nested per profile
//   v3  events hoisted to the top level
//   v4  Task.deadline (QDate) split into scheduledAt/dueAt (QDateTime) + hasTime
inline constexpr int kSchemaVersion = 4;

QJsonObject taskToJson(const Task& t);
Task taskFromJson(const QJsonObject& o);
QJsonArray tasksToJson(const QVector<Task>& xs);
QVector<Task> tasksFromJson(const QJsonArray& a);

QJsonObject eventToJson(const CalEvent& e);
CalEvent eventFromJson(const QJsonObject& o, const QString& fallbackProfileId = QString());
QJsonArray eventsToJson(const QVector<CalEvent>& xs);
QVector<CalEvent> eventsFromJson(const QJsonArray& a, const QString& fallbackProfileId = QString());

QJsonArray peopleToJson(const QVector<Person>& xs);
QVector<Person> peopleFromJson(const QJsonArray& a);

QJsonArray statusesToJson(const QVariantList& xs);
QVariantList statusesFromJson(const QJsonArray& a);

QJsonObject profileToJson(const Profile& p);

// Returns the parsed Profile and pulls out any nested "events" array (legacy
// schema v2) so the caller can hoist them into the global event pool with
// fallback profileId = p.id.
Profile profileFromJson(const QJsonObject& o, QVector<CalEvent>* outLegacyEvents = nullptr);

// Upgrades a whole state document in place from `fromVersion` to kSchemaVersion.
// Idempotent: a document already at kSchemaVersion is left untouched and false
// is returned. Only the field-level rewrites live here — the structural v1→v2→v3
// moves (wrapping flat fields into a profile, hoisting events) stay in
// AppController::loadStateOnStart, which is the only caller that has the models.
bool migrateState(QJsonObject& root, int fromVersion);

}  // namespace heap::state
