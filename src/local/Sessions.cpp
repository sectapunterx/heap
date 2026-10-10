#include "local/Checklist.h"
#include "local/Sessions.h"

#include <algorithm>
#include <limits>

namespace heap::local::sessions {

namespace {

// Seconds of [a, b) that fall on `day`.
qint64 overlapOn(const QDateTime& a, const QDateTime& b, const QDate& day) {
  if(!a.isValid() || !b.isValid() || b <= a) {
    return 0;
  }
  const QDateTime dayStart(day, QTime(0, 0));
  const QDateTime dayEnd(day.addDays(1), QTime(0, 0));
  const QDateTime from = std::max(a, dayStart);
  const QDateTime to = std::min(b, dayEnd);
  return to > from ? from.secsTo(to) : 0;
}

}  // namespace

int lengthOf(const TimerSession& s) {
  if(!s.start.isValid()) {
    return std::max(0, s.seconds);
  }
  if(!s.end.isValid() || s.end <= s.start) {
    return 0;
  }
  return static_cast<int>(s.start.secsTo(s.end));
}

int total(const QVector<TimerSession>& xs) {
  qint64 sum = 0;
  for(const TimerSession& s : xs) {
    sum += lengthOf(s);
  }
  return static_cast<int>(std::min<qint64>(sum, std::numeric_limits<int>::max()));
}

int secondsOn(const QVector<TimerSession>& xs, const QDate& day, const QDateTime& runningSince, const QDateTime& now) {
  qint64 sum = 0;
  for(const TimerSession& s : xs) {
    sum += overlapOn(s.start, s.end, day);
  }
  if(runningSince.isValid() && now.isValid()) {
    sum += overlapOn(runningSince, now, day);
  }
  return static_cast<int>(sum);
}

void record(QVector<TimerSession>& xs, const QDateTime& start, const QDateTime& end) {
  if(!start.isValid() || !end.isValid() || end <= start) {
    return;
  }
  xs.append(TimerSession{heap::local::checklist::newId(), start, end, 0});
}

void adoptTotal(QVector<TimerSession>& xs, int trackedSeconds) {
  const int missing = trackedSeconds - total(xs);
  if(missing <= 0) {
    return;
  }
  xs.prepend(TimerSession{heap::local::checklist::newId(), QDateTime(), QDateTime(), missing});
}

}  // namespace heap::local::sessions
