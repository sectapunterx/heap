#pragma once

#include <QList>

#include <algorithm>
#include <cmath>

// Interface scale steps (APP-168) driven from the keyboard: Ctrl+= / Ctrl+-
// walk Theme.scaleSteps, Ctrl+0 goes back to 100 %. Pure, so the rule is
// tested without a window.
namespace heap::ui {

// The step after `current` in `direction` (> 0 up, < 0 down); 0 resets to 1.
// A value between two steps (one stored by an older build, or typed into
// state.json) snaps to the nearest step that way. The ends stay put.
inline double nextUiScale(double current, int direction, QList<double> steps) {
  if(direction == 0 || steps.isEmpty()) {
    return 1.0;
  }
  std::sort(steps.begin(), steps.end());
  constexpr double kEps = 1e-6;
  if(!std::isfinite(current)) {
    current = 1.0;
  }
  if(direction > 0) {
    for(const double s : steps) {
      if(s > current + kEps) {
        return s;
      }
    }
    return steps.last();
  }
  for(auto it = steps.crbegin(); it != steps.crend(); ++it) {
    if(*it < current - kEps) {
      return *it;
    }
  }
  return steps.first();
}

// The interface scale a system text size asks for (APP-183), while the user
// has not picked one in heap: the step of `steps` nearest to `textScale`
// (1.0 = 100 %), a tie going up. Larger text than the top step gets the top
// step; nothing unreadable or below 100 % shrinks heap.
inline double uiScaleForTextScale(double textScale, QList<double> steps) {
  if(steps.isEmpty() || !std::isfinite(textScale) || textScale <= 1.0) {
    return 1.0;
  }
  std::sort(steps.begin(), steps.end());
  double best = steps.first();
  for(const double s : steps) {
    if(std::abs(s - textScale) <= std::abs(best - textScale) + 1e-9) {
      best = s;
    }
  }
  return std::max(best, 1.0);
}

}  // namespace heap::ui
