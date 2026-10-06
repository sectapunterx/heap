#pragma once

#include <QString>
#include <QtGlobal>

// Opt-in timing of the moments a user feels (APP-161): how long the app takes
// to show its first frame, and how long a capture takes to come up after its
// hotkey. Off unless HEAP_PERF_LOG=1 or `--perf-log`; when on, each measurement
// is one "perf: ..." line through the logger (stderr and heap.log). It only
// measures and logs — nothing in the app changes behaviour because of it.
//
// Spans are named, at most one pending per name. Thread-safe: a span may end
// from the scene graph's render thread (QQuickWindow::frameSwapped).

namespace heap::perf {

// Starts the process clock. Called first thing in main(); the "startup"
// figures are measured from here.
void markProcessStart();

// Milliseconds since markProcessStart(), or -1 when it was never called.
qint64 sinceProcessStart();

// HEAP_PERF_LOG=1 in the environment, or setEnabled(true).
bool enabled();
void setEnabled(bool on);

// Starts span `name`, replacing a pending one. No-op while disabled.
void begin(const QString& name);

// Starts span `name` unless one is already pending and younger than
// `keepYoungerMs` — so a capture opened by the global hotkey keeps the
// hotkey's start, while a stale start whose end never came is replaced.
void beginIfIdle(const QString& name, qint64 keepYoungerMs = 2000);

// Ends span `name` and logs it. Returns its length in ms, or -1 when there was
// no pending span of that name (or logging is off).
qint64 end(const QString& name);

// Logs a point measurement, e.g. ("startup first-frame", 412).
void log(const QString& what, qint64 ms);

// For tests: forgets every pending span and the enabled override.
void resetForTests();

}  // namespace heap::perf
