#include "diag/FrameLog.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEvent>
#include <QFile>
#include <QMutex>
#include <QMutexLocker>
#include <QPointer>
#include <QQuickWindow>
#include <QStringList>
#include <QTimer>

#include <atomic>
#include <memory>

namespace heap::frame {

namespace {

constexpr qint64 kNsPerMs = 1000000;
// A frame this soon after the previous one is part of a running animation
// (two vsyncs at 60 Hz); the frame after it is then expected on time too.
constexpr qint64 kMovingGapNs = 25 * kNsPerMs;
constexpr qint64 kLateFrameNs = 16700000;  // one frame at 60 Hz
constexpr qint64 kIdleGapNs = 250 * kNsPerMs;
constexpr qint64 kStallNs = 20 * kNsPerMs;
constexpr qint64 kSpanLogNs = 2 * kNsPerMs;
constexpr int kWatchdogMs = 4;

struct WindowTimes {
  qint64 lastSwap = -1;
  qint64 prevGap = -1;
  qint64 lastAnim = -1;
  qint64 animGap = 0;
  qint64 syncStart = -1;
  qint64 syncMs = 0;
  qint64 renderStart = -1;
  qint64 renderMs = 0;
};

struct State {
  QMutex mutex;
  QElapsedTimer clock;
  std::unique_ptr<QFile> file;
  QStringList pendingSpans;  // since the last frame/stall line
  qint64 frames = 0;
  qint64 over16 = 0;
  qint64 over33 = 0;
  qint64 over50 = 0;
  qint64 maxGap = 0;
  qint64 stalls = 0;
  qint64 maxStall = 0;
};

std::atomic<bool> g_on{false};

State& state() {
  static State s;
  return s;
}

QString ms(qint64 ns) {
  return QString::number(static_cast<double>(ns) / kNsPerMs, 'f', 1);
}

// Callers hold the mutex.
void writeLocked(State& s, const QString& line) {
  if(s.file) {
    s.file->write(line.toUtf8());
    s.file->write("\n");
    s.file->flush();
  }
}

QString takeSpansLocked(State& s) {
  const QString out = s.pendingSpans.join(QStringLiteral(", "));
  s.pendingSpans.clear();
  return QStringLiteral("[") + out + QStringLiteral("]");
}

void attach(QQuickWindow* w) {
  if(w->property("_heapFrameLog").toBool()) {
    return;
  }
  w->setProperty("_heapFrameLog", true);
  auto times = std::make_shared<WindowTimes>();
  State& s = state();
  {
    const QMutexLocker lock(&s.mutex);
    writeLocked(s, QStringLiteral("window\t%1\t%2").arg(ms(s.clock.nsecsElapsed()), w->title()));
  }
  // Every slot runs on the thread that emits (the render thread for most):
  // the times are shared under the one mutex.
  QObject::connect(
      w,
      &QQuickWindow::afterAnimating,
      w,
      [times, &s]() {
        const QMutexLocker lock(&s.mutex);
        const qint64 now = s.clock.nsecsElapsed();
        times->animGap = times->lastAnim < 0 ? 0 : now - times->lastAnim;
        times->lastAnim = now;
      },
      Qt::DirectConnection);
  QObject::connect(
      w,
      &QQuickWindow::beforeSynchronizing,
      w,
      [times, &s]() {
        const QMutexLocker lock(&s.mutex);
        times->syncStart = s.clock.nsecsElapsed();
      },
      Qt::DirectConnection);
  QObject::connect(
      w,
      &QQuickWindow::afterSynchronizing,
      w,
      [times, &s]() {
        const QMutexLocker lock(&s.mutex);
        times->syncMs = times->syncStart < 0 ? 0 : s.clock.nsecsElapsed() - times->syncStart;
      },
      Qt::DirectConnection);
  QObject::connect(
      w,
      &QQuickWindow::beforeRendering,
      w,
      [times, &s]() {
        const QMutexLocker lock(&s.mutex);
        times->renderStart = s.clock.nsecsElapsed();
      },
      Qt::DirectConnection);
  QObject::connect(
      w,
      &QQuickWindow::afterRendering,
      w,
      [times, &s]() {
        const QMutexLocker lock(&s.mutex);
        times->renderMs = times->renderStart < 0 ? 0 : s.clock.nsecsElapsed() - times->renderStart;
      },
      Qt::DirectConnection);
  QObject::connect(
      w,
      &QQuickWindow::frameSwapped,
      w,
      [times, &s]() {
        const QMutexLocker lock(&s.mutex);
        const qint64 now = s.clock.nsecsElapsed();
        const qint64 gap = times->lastSwap < 0 ? -1 : now - times->lastSwap;
        times->lastSwap = now;
        // Only a frame that follows an on-time one is part of something
        // moving; the first frame after idle has nothing to be late for.
        const bool moving = times->prevGap >= 0 && times->prevGap <= kMovingGapNs;
        times->prevGap = gap;
        // Past this, nothing was waiting for a frame: the motion had ended.
        if(!moving || gap < 0 || gap > kIdleGapNs) {
          return;
        }
        ++s.frames;
        s.maxGap = qMax(s.maxGap, gap);
        if(gap <= kLateFrameNs) {
          return;
        }
        ++s.over16;
        if(gap > 33 * kNsPerMs) {
          ++s.over33;
        }
        if(gap > 50 * kNsPerMs) {
          ++s.over50;
        }
        writeLocked(s,
                    QStringLiteral("frame\t%1\t%2\t%3\t%4\t%5\t%6")
                        .arg(ms(now), ms(gap), ms(times->animGap), ms(times->syncMs), ms(times->renderMs), takeSpansLocked(s)));
      },
      Qt::DirectConnection);
}

// Watches for windows as they show, and keeps the GUI-thread watchdog.
class Watcher : public QObject {
 public:
  explicit Watcher(QObject* parent) : QObject(parent), m_timer(new QTimer(this)) {
    m_timer->setTimerType(Qt::PreciseTimer);
    m_timer->setInterval(kWatchdogMs);
    connect(m_timer, &QTimer::timeout, this, &Watcher::tick);
    m_timer->start();
    m_last.start();
  }

  bool eventFilter(QObject* watched, QEvent* event) override {
    if(event->type() == QEvent::Show || event->type() == QEvent::Expose) {
      if(auto* w = qobject_cast<QQuickWindow*>(watched)) {
        attach(w);
        if(event->type() == QEvent::Expose) {
          State& s = state();
          const QMutexLocker lock(&s.mutex);
          writeLocked(s, QStringLiteral("expose\t%1\t%2").arg(ms(s.clock.nsecsElapsed())).arg(w->isExposed() ? 1 : 0));
        }
      }
    }
    return QObject::eventFilter(watched, event);
  }

 private:
  void tick() {
    const qint64 gap = m_last.nsecsElapsed();
    m_last.restart();
    if(gap < kStallNs) {
      return;
    }
    State& s = state();
    const QMutexLocker lock(&s.mutex);
    ++s.stalls;
    s.maxStall = qMax(s.maxStall, gap);
    writeLocked(s, QStringLiteral("stall\t%1\t%2\t%3").arg(ms(s.clock.nsecsElapsed()), ms(gap), takeSpansLocked(s)));
  }

  QTimer* m_timer;
  QElapsedTimer m_last;
};

QPointer<Watcher> g_watcher;
QtMessageHandler g_previousHandler = nullptr;

// A scripted scenario (console.log("frame-note: open editor")) marks where it
// is in the log, so the late frames can be read against what was moving.
void copyNotes(QtMsgType type, const QMessageLogContext& context, const QString& message) {
  // tryLock: a message raised while the log itself holds the lock is passed
  // on, not waited for.
  State& s = state();
  if(message.startsWith(QLatin1String("frame-note: ")) && enabled() && s.mutex.tryLock()) {
    writeLocked(s, QStringLiteral("note\t%1\t%2").arg(ms(s.clock.nsecsElapsed()), message.mid(12)));
    s.mutex.unlock();
  }
  if(g_previousHandler != nullptr) {
    g_previousHandler(type, context, message);
  }
}

bool open(const QString& path) {
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  auto f = std::make_unique<QFile>(path);
  if(!f->open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
    qWarning("heap: cannot open HEAP_FRAME_LOG %s", qUtf8Printable(path));
    return false;
  }
  s.file = std::move(f);
  s.clock.start();
  s.pendingSpans.clear();
  s.frames = s.over16 = s.over33 = s.over50 = s.maxGap = s.stalls = s.maxStall = 0;
  writeLocked(s, QStringLiteral("# heap frame log: kind\tt\tgap\tanim\tsync\trender\tspans"));
  g_on.store(true);
  return true;
}

void start(const QString& path) {
  if(enabled() || !open(path)) {
    return;
  }
  QCoreApplication* app = QCoreApplication::instance();
  if(app == nullptr) {
    return;
  }
  g_watcher = new Watcher(app);
  app->installEventFilter(g_watcher);
  // shutdown() runs once however often this is connected.
  QObject::connect(app, &QCoreApplication::aboutToQuit, app, &shutdown);
  // A second start must not chain the handler to itself.
  static bool handlerInstalled = false;
  if(!handlerInstalled) {
    handlerInstalled = true;
    g_previousHandler = qInstallMessageHandler(copyNotes);
  }
}

}  // namespace

bool enabled() {
  return g_on.load(std::memory_order_relaxed);
}

void installFromEnvironment() {
  const QString path = qEnvironmentVariable("HEAP_FRAME_LOG");
  if(!path.isEmpty()) {
    start(path);
  }
}

void installForTests(const QString& path) {
  start(path);
}

void shutdown() {
  if(!g_on.exchange(false)) {
    return;
  }
  delete g_watcher.data();
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  writeLocked(s,
              QStringLiteral("summary\tframes=%1\tover16=%2\tover33=%3\tover50=%4\tmaxGap=%5\tstalls=%6\tmaxStall=%7")
                  .arg(s.frames)
                  .arg(s.over16)
                  .arg(s.over33)
                  .arg(s.over50)
                  .arg(ms(s.maxGap))
                  .arg(s.stalls)
                  .arg(ms(s.maxStall)));
  s.file.reset();
}

Span::Span(const char* name) : m_name(name) {
  if(enabled()) {
    State& s = state();
    const QMutexLocker lock(&s.mutex);
    m_startNs = s.clock.nsecsElapsed();
  }
}

Span::~Span() {
  if(m_startNs < 0 || !enabled()) {
    return;
  }
  State& s = state();
  const QMutexLocker lock(&s.mutex);
  const qint64 took = s.clock.nsecsElapsed() - m_startNs;
  if(took < kSpanLogNs) {
    return;
  }
  const QString name = QString::fromLatin1(m_name);
  s.pendingSpans.append(name + QChar(' ') + ms(took));
  writeLocked(s, QStringLiteral("span\t%1\t%2\t%3").arg(ms(s.clock.nsecsElapsed()), name, ms(took)));
}

}  // namespace heap::frame
