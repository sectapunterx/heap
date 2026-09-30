#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QList>
#include <QString>

#include <functional>

// Low-level state.json I/O that AppController's load/save paths share.
//
// The distinction this file exists for: a state.json that cannot be *opened*
// is not a state.json that is *damaged*. An antivirus scan, a backup agent or
// a sync client can hold the file for a second or two while heap starts; the
// bytes on disk are fine. Treating that as corruption quarantined nothing
// (the rename failed under the same lock), seeded the demo and then saved it
// over the real file as soon as the lock went away.
namespace heap::storage {

struct ReadResult {
  enum Kind {
    Missing,     // no file: a genuine first run
    Ok,          // bytes read (they may still fail to parse — that is the caller's call)
    Unreadable,  // the file exists but could not be opened or read
  };

  Kind kind = Missing;
  QByteArray bytes;
  QString error;  // why it could not be read (Unreadable only)
  int attempts = 0;
};

// One attempt at reading `path`. The test seam below replaces it.
using Reader = std::function<ReadResult(const QString& path)>;
void setReaderForTesting(Reader reader);

// Reads `path`, retrying an open/read failure after each delay in `backoffMs`
// (a short startup lock goes away on its own). Missing is never retried.
ReadResult readWithRetry(const QString& path, const QList<int>& backoffMs);

// The retry schedule loadStateOnStart uses: ~2 s in total, so a real startup
// lock (AV scan, backup snapshot) clears and a permanent one does not hold the
// window back for long.
QList<int> startupBackoff();

// Whether a parsed document is something heap can load at all: a v2+ document
// with a `profiles` array holding at least one object, or a legacy v1 document
// (no schemaVersion, or 1) carrying at least one of the flat collections.
// `{}`, `{"schemaVersion":9}` or `profiles: "x"` are not a state file, however
// valid the JSON is. `reason` says what is wrong, for recovery.log.
bool validateShape(const QJsonObject& root, QString* reason = nullptr);

// QSaveFile write: a temp file next to `path`, then an atomic rename over it.
// Replaces an existing file (QFile::copy refuses to). `error` gets the reason.
bool writeAtomically(const QString& path, const QByteArray& bytes, QString* error = nullptr);

// Whether files can actually be created in `dir` (creating it first). Tries a
// real temporary file: QFileInfo::isWritable() is not reliable for folders on
// Windows, where ACLs decide.
bool probeWritableDir(const QString& dir, QString* error = nullptr);

}  // namespace heap::storage
