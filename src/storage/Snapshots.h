#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVector>

// The time machine's store (APP-162): compressed hourly copies of state.json
// in <dataDir>/history, thinned out as they age.
//
// backups/ keeps the last twenty copies at one interval, which covers "the
// file broke" and not "I deleted that project on Tuesday". A snapshot here is
// taken after a successful save once the newest one is an hour old, so the
// last two days can be rewound hour by hour and the last month day by day.
//
// A file is `state-YYYYMMDD-HHMM[-tag].json.z`:
//
//   HEAPSNAP 1\n
//   {"profiles":2,"tasks":120,"notes":5,"docs":3,"schema":11}\n
//   <qCompress(state.json bytes)>
//
// The summary line is what lets the dialog list a month of snapshots without
// inflating a single one. Everything here is plain functions of their
// arguments (the clock included), so retention is tested without waiting.
namespace heap::history {

struct SnapshotFile {
  QString name;
  QDateTime at;    // from the name: when the copy was taken
  qint64 bytes{};  // on disk
  QString tag;     // "" for the hourly ones, "pre" before a restore
};

struct Policy {
  int hourlyHours = 48;                   // every hourly copy this recent is kept
  int dailyDays = 30;                     // then one a day, this far back
  qint64 maxBytes = 200LL * 1024 * 1024;  // and never more than this in all
  qint64 minIntervalSecs = 3600;          // between two automatic copies
};

inline constexpr int kDefaultDays = 30;
inline constexpr int kDefaultMaxMb = 200;

// settings.data.historyDays / historyMaxMb, clamped to something sane.
Policy policyFrom(const QVariantMap& dataSettings);

// <dataDir>/history (not created).
QString dirFor(const QString& dataDir);

// "state-20261005-1430.json.z", or "state-20261005-1430-pre.json.z".
QString fileNameFor(const QDateTime& at, const QString& tag = QString());

// Whether `name` is a snapshot, and if so when it was taken and its tag.
bool parseName(const QString& name, QDateTime* at = nullptr, QString* tag = nullptr);

// Every snapshot in `dir`, newest first.
QVector<SnapshotFile> list(const QString& dir);

// Whether an automatic copy is due: none yet, or the newest is at least
// `minIntervalSecs` old. A newest copy dated in the future (the clock went
// back) does not hold copies back for ever: it counts as due.
bool isDue(const QVector<SnapshotFile>& existing, const QDateTime& now, qint64 minIntervalSecs = 3600);

// Which files retention removes, given `files` (any order). Keeps:
//   - the newest snapshot, always;
//   - within `hourlyHours`: every snapshot (one per clock hour for the
//     automatic ones, every tagged one);
//   - within `dailyDays`: the newest of each calendar day;
// and then drops the oldest of what is left until the total fits `maxBytes`.
QStringList pickToDelete(const QVector<SnapshotFile>& files, const QDateTime& now, const Policy& policy);

// Counts the summary line carries, from a parsed state document.
QJsonObject summarize(const QJsonObject& stateRoot);

// The file bytes for `stateJson` with `summary`.
QByteArray encode(const QByteArray& stateJson, const QJsonObject& summary);

// The other way: false when `fileBytes` is not a snapshot (or is damaged).
bool decode(const QByteArray& fileBytes, QByteArray* stateJson, QJsonObject* summary = nullptr);

// The summary line alone, read without inflating the rest. Empty on failure.
QJsonObject readSummary(const QString& path);

// Reads and inflates one snapshot. Empty with `error` set on failure.
QByteArray read(const QString& path, QString* error = nullptr);

// Writes `stateJson` as a snapshot taken `at` into `dir` (created), atomically.
// A name already taken gets "-2", "-3"… after the tag. Returns the file name,
// empty on failure.
QString write(const QString& dir,
              const QByteArray& stateJson,
              const QJsonObject& summary,
              const QDateTime& at,
              const QString& tag = QString(),
              QString* error = nullptr);

// Removes what pickToDelete() picks. Returns how many went.
int prune(const QString& dir, const QDateTime& now, const Policy& policy);

// What a save calls after state.json landed: a copy if one is due, then
// retention. Returns the name written, empty when none was due or it failed.
QString maybeSnapshot(
    const QString& dir, const QByteArray& stateJson, const QJsonObject& summary, const QDateTime& now, const Policy& policy);

}  // namespace heap::history
