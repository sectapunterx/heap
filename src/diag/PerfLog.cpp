#include "diag/PerfLog.h"

#include <QElapsedTimer>
#include <QHash>
#include <QMutex>
#include <QMutexLocker>

#include <optional>

namespace heap::perf {

namespace {

struct State {
  QMutex mutex;
  QElapsedTimer process;
  std::optional<bool> override;
  QHash<QString, qint64> pending;  // span name -> start, in ns of `clock`
  QElapsedTimer clock;
};

State& state() {
  static State s;
  return s;
}

bool envEnabled() {
  static const bool on = qEnvironmentVariable("HEAP_PERF_LOG") == QLatin1String("1");
  return on;
}

// Callers hold the mutex.
bool enabledLocked(const State& s) {
  return s.override.has_value() ? *s.override : envEnabled();
}

qint64 nowNs(State& s) {
  if(!s.clock.isValid()) {
    s.clock.start();
  }
  return s.clock.nsecsElapsed();
}

}  // namespace

void markProcessStart() {
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  s.process.start();
}

qint64 sinceProcessStart() {
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  return s.process.isValid() ? s.process.elapsed() : -1;
}

bool enabled() {
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  return enabledLocked(s);
}

void setEnabled(bool on) {
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  s.override = on;
}

void begin(const QString& name) {
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  if(!enabledLocked(s)) {
    return;
  }
  s.pending.insert(name, nowNs(s));
}

void beginIfIdle(const QString& name, qint64 keepYoungerMs) {
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  if(!enabledLocked(s)) {
    return;
  }
  const qint64 now = nowNs(s);
  const auto it = s.pending.constFind(name);
  if(it != s.pending.constEnd() && (now - it.value()) / 1000000 < keepYoungerMs) {
    return;
  }
  s.pending.insert(name, now);
}

qint64 end(const QString& name) {
  qint64 ms = -1;
  {
    State& s = state();
    const QMutexLocker lock(&s.mutex);
    if(!enabledLocked(s)) {
      return -1;
    }
    const auto it = s.pending.find(name);
    if(it == s.pending.end()) {
      return -1;
    }
    ms = (nowNs(s) - it.value()) / 1000000;
    s.pending.erase(it);
  }
  log(name, ms);
  return ms;
}

void log(const QString& what, qint64 ms) {
  if(!enabled()) {
    return;
  }
  qInfo("perf: %s %lld ms", qUtf8Printable(what), static_cast<long long>(ms));
}

void resetForTests() {
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  s.pending.clear();
  s.override.reset();
}

}  // namespace heap::perf
