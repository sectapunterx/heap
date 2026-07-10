#pragma once

#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Durability audit trail (HEAP-156). Every time the app quarantines a damaged
// state.json, recovers from a backup, or fails to write state, one JSON line is
// appended to …/AppDataLocation/logs/recovery.log. The file is the evidence a
// solo maintainer otherwise never gets: with no telemetry, a recovery that fires
// on a user's machine is invisible.
//
// Strictly local. Nothing in this module opens a socket; the only way a record
// leaves the machine is the user pasting an exported copy into a bug report.
namespace heap::recovery {

// Record kinds, written verbatim into the "kind" field.
inline constexpr auto kQuarantined = "quarantined";    // state.json was damaged and moved aside
inline constexpr auto kRecovered = "recovered";        // a backup was promoted to live state
inline constexpr auto kUnrecovered = "unrecovered";    // damaged, and no usable backup existed
inline constexpr auto kWriteFailed = "write-failed";   // a save could not be committed
inline constexpr auto kMigrated = "migrated";          // the schema ladder upgraded the file
inline constexpr auto kPreMigration = "premigration";  // a pre-migration copy was retained

QString recoveryLogPath();

// Appends one record. `details` is merged into the line alongside a UTC
// timestamp, the app version and `kind`. Best-effort: a log that cannot be
// written must never take the app down with it.
void append(const QString& kind, const QVariantMap& details = {});

// Every record, oldest first. Unparseable lines are skipped.
QVariantList entries();

// Writes the whole log to `destPath`. Returns false if there is nothing to
// export or the copy fails.
bool exportTo(const QString& destPath);

// Last `maxBytes` of the log, trimmed to whole lines — for the bug-report body.
QString tail(int maxBytes = 2000);

}  // namespace heap::recovery
