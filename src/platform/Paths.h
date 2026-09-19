#pragma once

#include <QString>

// Single source of truth for the directory heap keeps its data in: state.json,
// backups/, logs/ and the keychain-less secrets.json fallback. Defaults to
// QStandardPaths::AppDataLocation, and can be redirected once — early in
// main(), by --data-dir or the HEAP_DATA_DIR environment variable — so tests,
// screenshots and throwaway runs never write into a real profile.
namespace heap::paths {

// Point every data path at `dir` (absolute, or relative to the working
// directory). Call before installFileLogger() and before AppController is
// constructed: anything that resolved a path earlier keeps the old location.
// An empty `dir` is ignored. Not thread-safe by design — it runs once, in
// main(), before any other thread or the QML engine exists.
void setDataDir(const QString& dir);

// Absolute path to the data directory. Callers that write into it create it;
// this only computes the path.
QString dataDir();

// True when the location was redirected away from the platform default.
// Diagnostics surface this so a bug report says which profile it came from.
bool dataDirOverridden();

}  // namespace heap::paths
