#pragma once

#include <QString>

// Rotating file logger. Installs a qInstallMessageHandler that mirrors every
// qDebug/qInfo/qWarning/qCritical/qFatal line to a size-capped log file under
// QStandardPaths::AppDataLocation/logs, while still forwarding to the previous
// handler (so console output is preserved). Used by HEAP-64 diagnostics: the
// "Report an issue" and "Open logs folder" actions read back from here.
namespace heap::logging {

// Install the file message handler. Safe to call once, early in main() — after
// the application/organization names are set so AppDataLocation resolves to the
// heap folder, and before the QML engine loads. No-op if already installed.
void installFileLogger();

// Absolute path to the log directory (…/AppDataLocation/logs), created on demand.
QString logDirPath();

// Absolute path to the current log file (…/logs/heap.log).
QString logFilePath();

// Last \p maxBytes of the current log, trimmed to whole lines. Empty if no log
// exists yet. Used to pre-fill the bug-report body.
QString logTail(int maxBytes = 3000);

}  // namespace heap::logging
