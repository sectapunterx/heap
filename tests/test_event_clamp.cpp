// Hour-of-day clamping for calendar events (heap::cal::clampHours).
//
// Every event write path funnels through this, so the invariant it owns is
// worth pinning on its own: 0 <= start < end <= 24, both edges on the snap
// grid, at least one step long. Pure — no Qt event loop, no AppController.

#include "cal/EventClamp.h"

#include <gtest/gtest.h>

namespace {

constexpr double kQuarter = 0.25;  // the default 15-minute grid

// Floating-point equality on a grid: the values are all small multiples of a
// step, so an exact-ish tolerance is the honest assertion.
void expectRange(const heap::cal::HourRange& r, double start, double end) {
  EXPECT_NEAR(r.start, start, 1e-9);
  EXPECT_NEAR(r.end, end, 1e-9);
}

}  // namespace

TEST(EventClamp, SnapsBothEdgesToTheGrid) {
  expectRange(heap::cal::clampHours(9.1, 10.4, kQuarter), 9.0, 10.5);
  expectRange(heap::cal::clampHours(9.2, 10.3, 0.5), 9.0, 10.5);
}

TEST(EventClamp, LeavesAnAlreadyValidRangeAlone) {
  expectRange(heap::cal::clampHours(9.0, 10.0, kQuarter), 9.0, 10.0);
  expectRange(heap::cal::clampHours(0.0, 24.0, kQuarter), 0.0, 24.0);
}

// The regression this file exists for. updateEvent() used to compute
// qBound(start + minDur, end, 24.0); once start snapped to the last slot the
// lower bound passed the upper one — Q_ASSERT in a debug build, end > 24 in a
// release one.
TEST(EventClamp, AResizePastMidnightPinsToTheEndOfTheDay) {
  const heap::cal::HourRange r = heap::cal::clampHours(23.9, 25.5, kQuarter);
  expectRange(r, 23.75, 24.0);
  EXPECT_LE(r.end, 24.0);
  EXPECT_LT(r.start, r.end);
}

TEST(EventClamp, AStartOnMidnightStillLeavesRoomForTheEvent) {
  // 24.0 is a legal instant but not a legal start: there is no day left.
  expectRange(heap::cal::clampHours(24.0, 24.0, kQuarter), 23.75, 24.0);
  expectRange(heap::cal::clampHours(24.0, 24.0, 0.5), 23.5, 24.0);
}

TEST(EventClamp, EndBeforeStartBecomesOneStepLong) {
  expectRange(heap::cal::clampHours(14.0, 13.0, kQuarter), 14.0, 14.25);
  expectRange(heap::cal::clampHours(14.0, 14.0, 0.5), 14.0, 14.5);
}

TEST(EventClamp, NegativeHoursClampToMidnight) {
  expectRange(heap::cal::clampHours(-3.0, 1.0, kQuarter), 0.0, 1.0);
  expectRange(heap::cal::clampHours(-3.0, -1.0, kQuarter), 0.0, kQuarter);
}

// A degenerate step must not divide by zero or produce a range of length 0 —
// snapMinutes comes from a settings file a user can hand-edit.
TEST(EventClamp, ADegenerateStepFallsBackToTheDefaultGrid) {
  expectRange(heap::cal::clampHours(9.1, 10.4, 0.0), 9.0, 10.5);
  expectRange(heap::cal::clampHours(9.1, 10.4, -1.0), 9.0, 10.5);
  expectRange(heap::cal::clampHours(9.1, 10.4, 99.0), 9.0, 10.5);
}

TEST(EventClamp, NonFiniteInputsDoNotEscapeTheDay) {
  const double nan = std::nan("");
  const double inf = std::numeric_limits<double>::infinity();
  for(const heap::cal::HourRange r :
      {heap::cal::clampHours(nan, 10.0, kQuarter), heap::cal::clampHours(9.0, nan, kQuarter),
       heap::cal::clampHours(inf, inf, kQuarter), heap::cal::clampHours(-inf, 10.0, kQuarter),
       heap::cal::clampHours(9.0, 10.0, nan)}) {
    EXPECT_GE(r.start, 0.0);
    EXPECT_LE(r.end, 24.0);
    EXPECT_LT(r.start, r.end);
  }
}

TEST(EventClamp, StepHoursGuardsTheSettingsValue) {
  EXPECT_NEAR(heap::cal::stepHours(15), kQuarter, 1e-9);
  EXPECT_NEAR(heap::cal::stepHours(30), 0.5, 1e-9);
  // 0 is what a falsy-zero settings read hands over; it must not become a
  // zero-length grid.
  EXPECT_GT(heap::cal::stepHours(0), 0.0);
  EXPECT_GT(heap::cal::stepHours(-5), 0.0);
  EXPECT_LE(heap::cal::stepHours(99999), 24.0);
}
