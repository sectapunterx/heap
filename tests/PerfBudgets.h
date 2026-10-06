#pragma once

// Performance budgets (APP-161) — the one table heap_perf_tests holds the app
// to. Speed is a feature: a change that makes one of these categorically slower
// fails CI instead of being noticed by a user months later.
//
// Each budget is about 4x the local median it was set from, because hosted CI
// runners are slower and noisy (the rows of a few ms get a wider margin: at
// that size scheduler jitter alone is a multiple). A median over budget is
// re-measured twice before it fails, and ctest runs the suite alone. The budgets
// catch an accidental O(n²), a lost cache or a per-row allocation storm, not a
// 10% drift. The drift is what the printed table is for: every CI log carries
// measured-vs-budget for each row.
//
// `localMs` is the median measured when the budget was set — Windows 11,
// ucrt64 GCC Release build, 12-core desktop shared with other builds, the
// middle of three runs, 2026-10-05. On that machine at 100% CPU from other
// builds the medians reached ~2.5x these (state.parse 1325, filter.reset 63).
// Update both columns together and say why in the commit; see CONTRIBUTING.md
// ("Performance budgets"). Never raise a budget to make a red run green without
// knowing what got slower.

namespace heap::perf {

struct Budget {
  const char* name;  // stable key, printed in the table
  const char* what;  // what one run measures
  double localMs;    // local median when the budget was set
  double budgetMs;   // the gate: a median above this fails the suite
};

// Profile the suite generates: 10k tasks (BenchData.h) and 300 notes of ~6 KB.
inline constexpr int kPerfTaskCount = 10000;
inline constexpr int kPerfNoteCount = 300;
inline constexpr int kPerfNoteChars = 6 * 1024;
inline constexpr int kPerfCaptureCount = 1000;
inline constexpr int kPerfLargeNoteChars = 256 * 1024;

inline constexpr Budget kBudgets[] = {
    // state.json is ~13 MB here; JSON parsing is ~180 ms of it, the rest is
    // profileFromJson (~50 µs a task).
    {"state.parse", "state.json bytes -> JSON -> profiles", 520.0, 2000.0},
    {"state.boot", "AppController ctor on the 10k profile", 575.0, 2500.0},
    {"state.save", "flushSave(): snapshot + serialize + write", 435.0, 2000.0},
    {"search.fulltext", "searchFullText(), no match, all notes", 150.0, 600.0},
    {"filter.keystroke", "7 board columns re-filter 10k tasks", 3.6, 25.0},
    {"filter.reset", "task model reset under 7 columns", 13.5, 80.0},
    {"chrono.capture1k", "1k capture strings through ChronoParser", 33.0, 150.0},
    {"markdown.render", "256 KB note: parse + rows + outline", 43.0, 200.0},
};

}  // namespace heap::perf
