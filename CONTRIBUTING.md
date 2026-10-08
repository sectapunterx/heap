# Contributing to heap.

Thanks for taking a look. This page covers building, testing, what CI checks, and where things live.

## Build and test

Toolchain setup per platform is in [docs/BUILDING.md](docs/BUILDING.md). Once Qt 6.9+ is in place:

```sh
git clone https://github.com/sectapunterx/heap && cd heap
cmake -S . -B build && cmake --build build -j        # app
cmake --build build --target heap_all_tests          # tests
ctest --test-dir build/tests --output-on-failure
```

## Workflow

Two long-lived branches:

- **`master`** — the stable line. Every release is tagged here. It only takes a PR from `feature` (a release,
  merged with a merge commit so the two branches keep one history) or from `hotfix/*` (an urgent fix to the
  released version, which is then merged back into `feature`). Any other PR into `master` fails the
  `branch flow` job and with it `ci`.
- **`feature`** — the next release in the making. New work lands here and is tested here before it ships.

Work on a branch off `feature` named `heap-<ticket>_<short-desc>` and open the PR against `feature` (squash-merged).
Keep the tree green. Both branches are protected by repository rulesets: no direct pushes, no force-pushes, no
deletion, and a green `ci` check before a merge.

To release: open a PR `feature` → `master`, merge it once `ci` is green, then bump the version on `master` and
push the `vX.Y.Z` tag (see `release.yml`).

## CI

CI (`.github/workflows/ci.yml`) checks clang-format and clang-tidy on the changed lines, builds and tests on Linux,
Windows and macOS, runs an ASan/UBSan pass, a qmllint ratchet and actionlint, and smoke-tests the app — the `ci`
check gates the merge into `master` and `feature`. A PR that only touches docs or Markdown skips the build. A nightly run
(`nightly.yml`) adds the next Qt, fuzzing, coverage and a full release build. The website in `site/` has its own
workflow (`pages.yml`); see [`site/README.md`](site/README.md).

### Running the qmllint ratchet locally

The qmllint ratchet runs CI's Qt (6.9.1), whose qmllint reports differently from newer ones. To get CI's verdict
before pushing, install that Qt's QML modules once and run the same check against your build:

```sh
pip install aqtinstall
python -m aqt install-qt windows desktop 6.9.1 win64_msvc2022_64 -O C:/Qt -m qtnetworkauth --archives qtbase qtdeclarative qtsvg
python .github/scripts/qmllint_local.py --build build --qt C:/Qt/6.9.1/msvc2022_64   # or set HEAP_QMLLINT_QT
```

Once that Qt is in `C:/Qt/6.9.1`, `~/Qt/6.9.1` or `HEAP_QMLLINT_QT`, configuring the build finds it and `ctest` runs the
same check as `heap_qmllint_qt69` (lines changed since `origin/master`), so a green `ctest` means a green ratchet.
Set `-DHEAP_QMLLINT_QT=` to another Qt 6.9 dir, or leave the Qt out to skip it.

### Performance budgets

Speed is a feature, so it is gated. `heap_perf_tests` (`tests/test_perf_budget.cpp`) generates a 10k-task profile
and times state parse, app boot, save, full-text search, the board's filter proxies, 1k capture strings through the
date parser and a 256 KB note through the markdown renderer. Each is the median of several runs, compared against
the table in `tests/PerfBudgets.h`; every run prints measured vs budget, so CI logs show the trend:

```sh
build/heap_perf_tests --gtest_filter=PerfBudget*      # [ perf-budget ] lines
```

Budgets are about 4x a local median (noted next to each one), because CI runners are slow and noisy — they catch
an accidental quadratic or a lost cache, not a 10% drift. A median over budget is measured twice more before it
counts, and ctest runs the suite alone (`RUN_SERIAL`). The gate is armed only in an optimised build without
sanitizers or coverage; elsewhere the table is printed and nothing fails. `HEAP_PERF_REPORT_ONLY=1` disarms it by hand.

When a budget fails, find what got slower first. Change a budget only on purpose (a feature that costs time, a
deliberately larger fixture): re-measure locally in a Release build, take the middle of three runs, update `localMs`
and `budgetMs` together, and say why in the commit.

For the UI, `heap --perf-log` (or `HEAP_PERF_LOG=1`) writes `perf:` lines to the log: time from `main()` to the QML
being loaded and to the main window's first frame, and from the capture hotkey (or `open()`) to the first frame
showing the capture popup. It only logs.

For animation jank, `HEAP_FRAME_LOG=<file>` (off by default, `src/diag/FrameLog.h`) appends one line per late frame
(more than 16.7 ms after an on-time one, i.e. mid-motion) and per GUI-thread stall (a 4 ms watchdog timer firing
20 ms or more late), each naming the instrumented work that ran in it (`saveStateNow`, `mergeExternalTasks`,
`runAutomation`, ...; add a `heap::frame::Span` around anything you suspect). A log message starting
`frame-note: ` is copied in, so a scripted scenario can mark where it is. Stalls need no vsync and are the number to
trust under `QT_QPA_PLATFORM=offscreen`; frame gaps are only meaningful on a display that presents. Combine with
`qmlprofiler` for the QML side of a stall.

## Project layout

```
.
├─ CMakeLists.txt          ← heap_core (qt_add_library + qt_add_qml_module) + thin heap exe
├─ src/
│  ├─ main.cpp             ← QApplication entry, window icon, signal handlers
│  ├─ AppController.{h,cpp}← QML_SINGLETON exposing models, profiles, automation, undo
│  ├─ Logger.{h,cpp}       ← rotating file logger, installed from main
│  ├─ Models.{h,cpp}       ← TaskModel / EventModel / PersonModel (QAbstractListModel)
│  ├─ SampleData.{h,cpp}   ← seed tasks / events / people for first run
│  ├─ CodeHighlighter.{h,cpp}  ← QSyntaxHighlighter for the docs snippet editor
│  ├─ board/               ← card ranks for the manual board order
│  ├─ cal/                 ← calendar: recurrence rules, occurrences, reminders, .ics, event clamping
│  ├─ undo/                ← the undo / redo stack
│  ├─ markdown/            ← parser, block model and editor ops for Notes
│  ├─ chrono/              ← natural-language date parser (Quick-capture)
│  ├─ git/                 ← GitWatcher + branch↔task matcher (git-aware board)
│  ├─ text/                ← task-text classification / parsing helpers
│  ├─ notes/               ← note backlinks + @people / #ticket link parsing
│  ├─ recur/               ← recurring-task engine
│  ├─ query/               ← Notes query-language parser
│  ├─ notify/              ← cross-platform notifications (tray / D-Bus)
│  ├─ platform/            ← global hotkey backend (Win32 RegisterHotKey)
│  ├─ integrations/        ← tracker sync: 12 trackers + Mattermost contacts, OAuth, keychain
│  ├─ sync/                ← BYOS serializer + 3-way JSON merge (internal)
│  └─ update/              ← GitHub-releases update check
├─ qml/                    ← all views + singletons (Theme, Brand, I18n) — see below
├─ tests/                  ← GoogleTest (C++) + Qt Quick Test (QML) suites
├─ docs/                   ← guides (also published on the website) + screenshots
├─ site/                   ← the website: Astro + React islands, deployed to GitHub Pages
├─ design/                 ← original React prototype (reference) + brand-export bundle
└─ README.md
```

The `qml/` tree holds one file per surface (`KanbanBoard`, `WeekView`, `DayCalendar`, `DocsView`, `NotesView`,
`PeopleList`, …), the modal editors, and the `Theme` / `Brand` / `I18n` singletons. `BrandLogo.qml` paints the mark
with native primitives so the brand renders without `Qt6::Svg`.

## Data model

Profiles own their tasks, people, statuses, docs, and notes. Events are global (the calendar spans every profile) and
carry an optional `profileId`. Everything persists as JSON under `QStandardPaths::AppDataLocation`; settings live in a
single `appSettingsJson` blob edited by `SettingsView`. See [docs/DATA.md](docs/DATA.md) for backups and recovery.

## Writing to other systems

heap reads from trackers and writes to them only where the user switched that write on. Any new write to an external
system (a status, a comment, a label, a PR/MR action…) gets its own per-tracker switch, **off by default** for new and
updated installs alike, and a row in the table in [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md#the-rule-every-external-write-is-opt-in).
Comments are never sent. Local data is never overwritten by a sync.

## Brand

Logo, palette, tokens and mark geometry live in [`design/brand-export/`](design/brand-export/README.md) and are wired
into the runtime via the `Brand` QML singleton. Tagline: *Work, in one place.*

## License

By contributing you agree your work is released under the [MIT license](LICENSE).
