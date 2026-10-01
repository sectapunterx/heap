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

Work on a branch off `master` named `heap-<ticket>_<short-desc>` and open the PR against `master`. Keep the tree
green.

## CI

CI (`.github/workflows/ci.yml`) checks clang-format and clang-tidy on the changed lines, builds and tests on Linux,
Windows and macOS, runs an ASan/UBSan pass, a qmllint ratchet and actionlint, and smoke-tests the app — the `ci`
check gates the merge into `master`. A PR that only touches docs or Markdown skips the build. A nightly run
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

## Brand

Logo, palette, tokens and mark geometry live in [`design/brand-export/`](design/brand-export/README.md) and are wired
into the runtime via the `Brand` QML singleton. Tagline: *Work, in one place.*

## License

By contributing you agree your work is released under the [MIT license](LICENSE).
