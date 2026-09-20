#pragma once

#include <QtGlobal>

#include <cmath>

// Hour-of-day arithmetic for calendar events.
//
// A CalEvent stores start/end as hours-since-midnight (0.0 … 24.0) on one date,
// so every write path has the same three jobs: keep both edges inside the day,
// put them on the snap grid, and keep the event long enough to be grabbable.
// Doing that inline is how the two live bugs got in — saveEvent() clamped
// nothing at all, and updateEvent() called qBound(start + minDur, end, 24.0),
// whose lower bound exceeds its upper one as soon as start lands on the last
// slot (Q_ASSERT in a debug build, end > 24 in a release one).
namespace heap::cal {

struct HourRange {
  double start = 0.0;
  double end = 0.0;
};

// The snap grid in hours, from a snapMinutes setting. Guarded so a 0 (or a
// negative, or a value past a whole day) cannot produce a division by zero or
// a degenerate grid.
inline double stepHours(int snapMinutes) {
  const int m = qBound(1, snapMinutes, 24 * 60);
  return m / 60.0;
}

// Returns a range with 0 <= start < end <= 24, both edges on the `step` grid
// and at least one step apart.
//
// When the requested range runs past midnight the event is pinned to the end of
// the day rather than dropped or wrapped: dragging a block to the bottom of the
// grid should hand back the last slot. Callers that want a multi-day event have
// to split it themselves — this function only ever describes one day.
inline HourRange clampHours(double start, double end, double step) {
  constexpr double kDay = 24.0;
  if(!std::isfinite(step) || step <= 0.0 || step > kDay) {
    step = 0.25;
  }
  if(!std::isfinite(start)) {
    start = 0.0;
  }
  if(!std::isfinite(end)) {
    end = start + step;
  }

  const auto snap = [step](double h) {
    return std::round(h / step) * step;
  };

  double s = snap(qBound(0.0, start, kDay));
  double e = snap(qBound(0.0, end, kDay));

  // Minimum length first, then the day boundary — an event that would have run
  // past midnight slides back instead of collapsing onto it.
  if(e < s + step) {
    e = s + step;
  }
  if(e > kDay) {
    e = kDay;
    s = qMin(s, kDay - step);
  }
  if(s < 0.0) {
    s = 0.0;
  }
  return {s, e};
}

}  // namespace heap::cal
