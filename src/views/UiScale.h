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

}  // namespace heap::ui
