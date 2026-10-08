#pragma once

#include <QString>
#include <QtGlobal>

// Opt-in frame-time log (APP-203). Off unless HEAP_FRAME_LOG=<path> is set;
// then every Qt Quick window shown is watched and lines are appended to <path>:
//
// - a late frame: one presented more than 16.7 ms after the previous one
//   while something was moving (the frame before it was on time), with how
//   long the scene graph spent syncing and rendering it;
// - a stall: a 4 ms watchdog timer on the GUI thread fired 20 ms or more
//   late, i.e. the event loop was blocked. This one needs no vsync, so it is
//   the trustworthy number under QT_QPA_PLATFORM=offscreen or on a machine
//   whose display does not present;
// - a span: a named stretch of GUI-thread work (save, sync merge, the minute
//   tick ...) of 2 ms or more. Frame and stall lines list the spans that ran
//   since the previous line, so a block names its cause.
//
// At exit a summary line counts frames and those over 16.7 / 33 / 50 ms. It
// only measures and logs; nothing in the app behaves differently.
//
// Line format (tab separated, times in ms, `t` since the log was opened):
//   frame  t  gap  anim  sync  render  [span ms, ...]
//   stall  t  gap  [span ms, ...]
//   span   t  name  ms
//   note   t  text         (a log message starting "frame-note: ")
//   window t  title        (a window starts being watched)
//   expose t  0|1
//   summary frames  over16  over33  over50  maxGap  stalls  maxStall

namespace heap::frame {

// True while a log is open (HEAP_FRAME_LOG, or installForTests).
bool enabled();

// Reads HEAP_FRAME_LOG; when set, opens the file and starts watching windows.
// Call once after the QGuiApplication exists. A no-op otherwise.
void installFromEnvironment();

// For tests: logs to `path` as if HEAP_FRAME_LOG pointed there.
void installForTests(const QString& path);

// Closes the log and writes the summary. Runs at application exit too.
void shutdown();

// Times a stretch of GUI-thread work. Costs one branch while disabled.
class Span {
 public:
  explicit Span(const char* name);
  ~Span();
  Span(const Span&) = delete;
  Span& operator=(const Span&) = delete;
  Span(Span&&) = delete;
  Span& operator=(Span&&) = delete;

 private:
  const char* m_name;
  qint64 m_startNs = -1;
};

}  // namespace heap::frame
