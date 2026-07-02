#pragma once

#include "Models.h"

#include <QByteArray>
#include <QJsonArray>
#include <QJsonObject>
#include <QVector>

#include <optional>

namespace heap::sync {

// Serializes heap. entities to/from the human-readable, git-friendly JSON that
// the BYOS git-remote backend (HEAP-19) stores one-file-per-entity in the sync
// repository.
//
// The single non-obvious requirement is STABLE ordering: git merges and diffs
// line-by-line, so the byte output for a given logical state must not depend on
// in-memory ordering. QJsonObject already keeps its keys sorted, so the only
// remaining source of churn is entity arrays — those are sorted by "id" before
// emission. Two profiles that differ only in task/person/status vector order
// therefore serialize to identical bytes, and a round-trip is idempotent.
class SyncSerializer {
 public:
  // Profile → pretty-printed JSON (tasks/people/statuses sorted by id).
  static QByteArray serializeProfile(const Profile& p);
  // JSON → Profile. Returns nullopt when the document is not a JSON object.
  static std::optional<Profile> deserializeProfile(const QByteArray& json);

  // Global calendar events → JSON (events.json), sorted by id.
  static QByteArray serializeEvents(const QVector<CalEvent>& events);
  static QVector<CalEvent> deserializeEvents(const QByteArray& json);

  // ── Building blocks (exposed for reuse / testing) ──
  static QJsonObject taskToJson(const Task& t);
  static Task taskFromJson(const QJsonObject& o);
  static QJsonObject personToJson(const Person& p);
  static Person personFromJson(const QJsonObject& o);
  static QJsonObject eventToJson(const CalEvent& e);
  static CalEvent eventFromJson(const QJsonObject& o);

  // Sort a JSON array of objects by their "id" field (stable ordering helper).
  static QJsonArray sortedById(const QJsonArray& arr);
};

}  // namespace heap::sync
