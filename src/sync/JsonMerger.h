#pragma once

#include <QJsonObject>
#include <QJsonValue>
#include <QString>
#include <QVector>

namespace heap::sync {

// One unresolved field/element where local and remote both diverged from base.
struct MergeConflict {
  QString path;  // JSON pointer-ish, e.g. "/tasks/T-1/title"
  QJsonValue baseValue;
  QJsonValue localValue;
  QJsonValue remoteValue;
};

struct MergeResult {
  bool ok = false;  // true when there were no unresolved conflicts
  QJsonObject merged;
  QVector<MergeConflict> conflicts;
};

// Structural 3-way merge of two JSON documents against a known base — the
// non-git BYOS backends (WebDAV / SSH+rsync) need this because, unlike git,
// they have no built-in merge. Rules:
//   - scalars: if only one side changed vs base, take it; if both changed
//     differently → conflict (the merged doc keeps the local value).
//   - nested objects: recurse field by field.
//   - arrays of objects with an "id": merge by id. Items on one side only are
//     kept (add) or dropped (delete-vs-unchanged); items edited on both sides
//     use last-write-wins by an "updatedAt" field when present, else conflict.
//     Arrays without id-objects are treated as an opaque scalar value.
//   - "createdAt" is never a conflict — the earlier value always wins.
// The merged document is always populated (conflicts resolve to local) so a
// caller can proceed and surface `conflicts` in a resolver UI.
class JsonMerger {
 public:
  static MergeResult merge(const QJsonObject& base, const QJsonObject& local, const QJsonObject& remote);
};

}  // namespace heap::sync
