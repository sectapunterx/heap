#pragma once

#include "Models.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QTime>
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
//   v5  Task.rank — manual order within a status column
//   v10 Task.hasTime split into dueHasTime / scheduledHasTime; every task
//       gets a distinct rank (rank-0 ties are spread out in board order)
//   v11 Task.attachments and Profile.savedViews (no rung: absent = none). The
//       bump is what sends a v10 build into its read-only mode instead of
//       saving every task without its files (PLAT-15)
//   v12 Task.local — what the developer keeps on top of a tracker issue (ADR
//       0001, APP-244). The rung moves a tracker card's local divergence
//       (priority, due date, extra labels, edited description/title) there
inline constexpr int kSchemaVersion = 12;

// The key of a column's map (Profile::statuses) that holds the column keys
// this build does not read, as a QVariantMap, so they survive a save.
inline constexpr const char* kStatusExtraKey = "_extra";

// Gap between consecutive ranks handed out by the v4→v5 migration and by
// "add to the end". Large enough that a long run of midpoint inserts between
// the same two neighbours never needs a rebalance in practice.
inline constexpr double kRankStep = 1024.0;

// The one `hasTime` of schema ≤ 9 said "the clock of these datetimes is real"
// for both fields at once. Each field keeps it unless it sits at exactly
// midnight while the other field carries a real clock time: that is the
// date-only deadline next to a timed schedule (or the reverse) the shared flag
// could not express, and midnight was never typed there.
// Inline so the sync serializer, which is built without this file in some
// test targets, reads old documents by the same rule.
inline void applyLegacyHasTime(Task& t, bool hasTime) {
  const auto atMidnight = [](const QDateTime& dt) {
    return dt.time() == QTime(0, 0);
  };
  const bool dueClock = t.dueAt.isValid() && !atMidnight(t.dueAt);
  const bool schedClock = t.scheduledAt.isValid() && !atMidnight(t.scheduledAt);
  t.dueHasTime = hasTime && t.dueAt.isValid() && (dueClock || !schedClock);
  t.scheduledHasTime = hasTime && t.scheduledAt.isValid() && (schedClock || !dueClock);
}

QJsonObject taskToJson(const Task& t);
Task taskFromJson(const QJsonObject& o);
QJsonArray tasksToJson(const QVector<Task>& xs);
QVector<Task> tasksFromJson(const QJsonArray& a);

QJsonObject eventToJson(const CalEvent& e);
CalEvent eventFromJson(const QJsonObject& o, const QString& fallbackProfileId = QString());
QJsonArray eventsToJson(const QVector<CalEvent>& xs);
QVector<CalEvent> eventsFromJson(const QJsonArray& a, const QString& fallbackProfileId = QString());

QJsonObject noteToJson(const Note& n);
Note noteFromJson(const QJsonObject& o);
QJsonArray notesToJson(const QVector<Note>& xs);
QVector<Note> notesFromJson(const QJsonArray& a);

QJsonObject docPageToJson(const DocPage& p);
DocPage docPageFromJson(const QJsonObject& o);
QJsonArray docPagesToJson(const QVector<DocPage>& xs);
QVector<DocPage> docPagesFromJson(const QJsonArray& a);

QJsonArray peopleToJson(const QVector<Person>& xs);
QVector<Person> peopleFromJson(const QJsonArray& a);

QJsonArray statusesToJson(const QVariantList& xs);
QVariantList statusesFromJson(const QJsonArray& a);

QJsonObject profileToJson(const Profile& p);

// Returns the parsed Profile and pulls out any nested "events" array (legacy
// schema v2) so the caller can hoist them into the global event pool with
// fallback profileId = p.id.
Profile profileFromJson(const QJsonObject& o, QVector<CalEvent>* outLegacyEvents = nullptr);

// Forgets the unknown keys the readers above kept, on the profile and on every
// task, person and column in it, or on every event. Pass-through is for the
// schema this build writes: in an older document an unknown key is one a later
// version retired, not one a sibling build added.
// The oldest schema whose unknown keys are still kept: a v11 document's keys
// survive the move to v12 (APP-244), since the upgrade promises to lose nothing.
inline constexpr int kPassThroughSince = 11;
void dropPassThrough(Profile& p);
void dropPassThrough(QVector<CalEvent>& events);

// Upgrades a whole state document in place from `fromVersion` to kSchemaVersion.
// Idempotent: a document already at kSchemaVersion is left untouched and false
// is returned. Only the field-level rewrites live here — the structural v1→v2→v3
// moves (wrapping flat fields into a profile, hoisting events) stay in
// AppController::loadStateOnStart, which is the only caller that has the models.
bool migrateState(QJsonObject& root, int fromVersion);

}  // namespace heap::state
