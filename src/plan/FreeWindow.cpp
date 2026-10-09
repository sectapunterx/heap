#include "plan/FreeWindow.h"

#include <algorithm>
#include <cmath>

namespace heap::plan {

namespace {

constexpr double kEps = 1e-6;

double snapUp(double h, double step) {
  return std::ceil((h / step) - kEps) * step;
}

}  // namespace

double firstFit(QVector<Span> busy, double from, double until, double hours, double step) {
  if(step <= 0) {
    step = 0.25;
  }
  hours = std::max(step, hours);
  std::sort(busy.begin(), busy.end());
  double cursor = snapUp(std::max(0.0, from), step);
  for(const Span& b : std::as_const(busy)) {
    if(b.second <= b.first) {
      continue;
    }
    if(cursor + hours <= b.first + kEps) {
      break;  // fits in the gap before this one
    }
    if(b.second > cursor) {
      cursor = snapUp(b.second, step);
    }
  }
  return cursor + hours <= until + kEps ? cursor : -1;
}

double searchFrom(const QDate& date, const QDateTime& now, double workStart, double step) {
  if(!now.isValid() || date < now.date()) {
    return -1;
  }
  if(date > now.date()) {
    return workStart;
  }
  const double nowHour = now.time().hour() + (now.time().minute() / 60.0) + (now.time().second() / 3600.0);
  return std::max(workStart, snapUp(nowHour, step > 0 ? step : 0.25));
}

Window findWindow(const WindowAsk& ask, const BusyOn& busyOn, const IsWorkDay& isWorkDay) {
  Window w;
  const double from = searchFrom(ask.date, ask.now, ask.workStart, ask.step);
  if(from >= 0) {
    const QVector<Span> busy = busyOn(ask.date);
    if(isWorkDay(ask.date)) {
      const double s = firstFit(busy, from, ask.workEnd, ask.hours, ask.step);
      if(s >= 0) {
        w.found = true;
        w.start = s;
        return w;
      }
    }
    // No room in the working day: what is left of the evening, as an
    // option the person may still take.
    w.lateStart = firstFit(busy, from, 24.0, ask.hours, ask.step);
  }
  for(int i = 1; i <= ask.maxDays; ++i) {
    const QDate d = ask.date.addDays(i);
    if(!isWorkDay(d)) {
      continue;
    }
    const double dayFrom = searchFrom(d, ask.now, ask.workStart, ask.step);
    if(dayFrom < 0) {
      continue;
    }
    const double s = firstFit(busyOn(d), dayFrom, ask.workEnd, ask.hours, ask.step);
    if(s >= 0) {
      w.nextDate = d;
      w.nextStart = s;
      break;
    }
  }
  return w;
}

std::pair<QDate, double> nextWindow(const WindowAsk& ask, const BusyOn& busyOn, const IsWorkDay& isWorkDay) {
  for(int i = 0; i <= ask.maxDays; ++i) {
    const QDate d = ask.date.addDays(i);
    if(!isWorkDay(d)) {
      continue;
    }
    const double from = searchFrom(d, ask.now, ask.workStart, ask.step);
    if(from < 0) {
      continue;
    }
    const double s = firstFit(busyOn(d), from, ask.workEnd, ask.hours, ask.step);
    if(s >= 0) {
      return {d, s};
    }
  }
  return {QDate(), -1};
}

}  // namespace heap::plan
