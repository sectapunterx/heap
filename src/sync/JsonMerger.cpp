#include "sync/JsonMerger.h"

#include <QHash>
#include <QJsonArray>
#include <QSet>
#include <QStringList>

#include <algorithm>

namespace heap::sync {

namespace {

const QLatin1String kId("id");
const QLatin1String kUpdatedAt("updatedAt");
const QLatin1String kCreatedAt("createdAt");

QString joinPath(const QString& prefix, const QString& key) {
  return prefix + QLatin1Char('/') + key;
}

QString idOf(const QJsonValue& v) {
  return v.isObject() ? v.toObject().value(kId).toString() : QString();
}

bool isIdObject(const QJsonValue& v) {
  return v.isObject() && !v.toObject().value(kId).toString().isEmpty();
}

// Forward decls for the mutual recursion.
QJsonObject mergeObject(const QJsonObject& base, const QJsonObject& local, const QJsonObject& remote, const QString& path,
                        QVector<MergeConflict>& conflicts);
QJsonArray mergeArray(const QJsonArray& base, const QJsonArray& local, const QJsonArray& remote, const QString& path,
                      QVector<MergeConflict>& conflicts);

void recordConflict(QVector<MergeConflict>& conflicts, const QString& path, const QJsonValue& b, const QJsonValue& l,
                    const QJsonValue& r) {
  conflicts.append(MergeConflict{path, b, l, r});
}

// Resolve one value slot. Returns the chosen value; if the slot should be
// absent from the parent (both sides deleted, or delete-vs-unchanged), returns
// Undefined. `key` is the leaf name (for the createdAt special-case).
QJsonValue mergeValue(const QString& key, const QString& path, const QJsonValue& b, const QJsonValue& l,
                      const QJsonValue& r, QVector<MergeConflict>& conflicts) {
  if(l == r) {
    return l;  // both agree (Undefined == Undefined → key dropped)
  }
  if(l == b) {
    return r;  // only remote changed (incl. remote deletion → Undefined)
  }
  if(r == b) {
    return l;  // only local changed
  }

  // Both diverged from base and from each other.
  if(key == kCreatedAt && l.isString() && r.isString()) {
    return l.toString() <= r.toString() ? l : r;  // earlier timestamp wins
  }
  if(l.isObject() && r.isObject()) {
    return mergeObject(b.isObject() ? b.toObject() : QJsonObject(), l.toObject(), r.toObject(), path, conflicts);
  }
  if(l.isArray() && r.isArray()) {
    return mergeArray(b.isArray() ? b.toArray() : QJsonArray(), l.toArray(), r.toArray(), path, conflicts);
  }
  recordConflict(conflicts, path, b, l, r);
  return l;  // keep local; conflict recorded
}

QJsonObject mergeObject(const QJsonObject& base, const QJsonObject& local, const QJsonObject& remote, const QString& path,
                        QVector<MergeConflict>& conflicts) {
  QStringList keys;
  for(const QString& k : base.keys()) {
    keys << k;
  }
  for(const QString& k : local.keys()) {
    if(!keys.contains(k)) {
      keys << k;
    }
  }
  for(const QString& k : remote.keys()) {
    if(!keys.contains(k)) {
      keys << k;
    }
  }

  QJsonObject out;
  for(const QString& k : keys) {
    const QJsonValue merged =
        mergeValue(k, joinPath(path, k), base.value(k), local.value(k), remote.value(k), conflicts);
    if(!merged.isUndefined()) {
      out.insert(k, merged);
    }
  }
  return out;
}

// Element-level LWW for a task/person/event that both sides edited differently.
QJsonValue lwwOrConflict(const QString& path, const QJsonValue& b, const QJsonValue& l, const QJsonValue& r,
                         QVector<MergeConflict>& conflicts) {
  const QString lu = l.toObject().value(kUpdatedAt).toString();
  const QString ru = r.toObject().value(kUpdatedAt).toString();
  if(!lu.isEmpty() && !ru.isEmpty()) {
    return lu >= ru ? l : r;  // later write wins (tie → local)
  }
  recordConflict(conflicts, path, b, l, r);
  return l;
}

QJsonArray mergeArray(const QJsonArray& base, const QJsonArray& local, const QJsonArray& remote, const QString& path,
                      QVector<MergeConflict>& conflicts) {
  // If any element isn't an id-carrying object, treat the whole array as opaque.
  auto allIdObjects = [](const QJsonArray& a) {
    for(const QJsonValue& v : a) {
      if(!isIdObject(v)) {
        return false;
      }
    }
    return true;
  };
  if(!allIdObjects(local) || !allIdObjects(remote)) {
    // Fall back to scalar-style resolution on the array as a whole.
    if(local == remote) {
      return local;
    }
    if(local == base) {
      return remote;
    }
    if(remote == base) {
      return local;
    }
    recordConflict(conflicts, path, base, local, remote);
    return local;
  }

  auto byId = [](const QJsonArray& a) {
    QHash<QString, QJsonValue> m;
    for(const QJsonValue& v : a) {
      m.insert(idOf(v), v);
    }
    return m;
  };
  const QHash<QString, QJsonValue> bm = byId(base);
  const QHash<QString, QJsonValue> lm = byId(local);
  const QHash<QString, QJsonValue> rm = byId(remote);

  QSet<QString> ids;
  for(const QString& id : lm.keys()) {
    ids.insert(id);
  }
  for(const QString& id : rm.keys()) {
    ids.insert(id);
  }

  QVector<QJsonValue> kept;
  for(const QString& id : ids) {
    const bool hb = bm.contains(id);
    const bool hl = lm.contains(id);
    const bool hr = rm.contains(id);
    const QJsonValue b = hb ? bm.value(id) : QJsonValue(QJsonValue::Undefined);
    const QJsonValue l = hl ? lm.value(id) : QJsonValue(QJsonValue::Undefined);
    const QJsonValue r = hr ? rm.value(id) : QJsonValue(QJsonValue::Undefined);
    const QString elemPath = joinPath(path, id);

    if(hl && hr) {
      if(l == r) {
        kept.append(l);
      } else if(hb && l == b) {
        kept.append(r);  // only remote edited
      } else if(hb && r == b) {
        kept.append(l);  // only local edited
      } else {
        kept.append(lwwOrConflict(elemPath, b, l, r, conflicts));  // both edited / both added
      }
    } else if(hl && !hr) {
      if(!hb) {
        kept.append(l);  // local add
      } else if(l == b) {
        // remote deleted, local unchanged → drop
      } else {
        recordConflict(conflicts, elemPath, b, l, r);  // edit vs delete
        kept.append(l);
      }
    } else if(!hl && hr) {
      if(!hb) {
        kept.append(r);  // remote add
      } else if(r == b) {
        // local deleted, remote unchanged → drop
      } else {
        recordConflict(conflicts, elemPath, b, l, r);
        kept.append(r);
      }
    }
  }

  // Deterministic output — sort by id (matches SyncSerializer's stable order).
  std::sort(kept.begin(), kept.end(),
            [](const QJsonValue& a, const QJsonValue& b) { return idOf(a) < idOf(b); });
  QJsonArray out;
  for(const QJsonValue& v : kept) {
    out.append(v);
  }
  return out;
}

}  // namespace

MergeResult JsonMerger::merge(const QJsonObject& base, const QJsonObject& local, const QJsonObject& remote) {
  MergeResult res;
  res.merged = mergeObject(base, local, remote, QString(), res.conflicts);
  res.ok = res.conflicts.isEmpty();
  return res;
}

}  // namespace heap::sync
