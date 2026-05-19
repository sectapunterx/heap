<div align="center">

# heap.

**heap.push(task)** — native desktop kanban + calendar + docs for C++ engineers.

[![Qt 6](https://img.shields.io/badge/Qt-6.4%2B-41cd52?logo=qt&logoColor=white)](https://www.qt.io/)
[![C++17](https://img.shields.io/badge/C%2B%2B-17-00599c?logo=cplusplus&logoColor=white)](https://en.cppreference.com/w/cpp/17)
[![CMake](https://img.shields.io/badge/CMake-3.21%2B-064f8c?logo=cmake&logoColor=white)](https://cmake.org/)
[![License](https://img.shields.io/badge/license-MIT-blue)](#license)

</div>

---

## What it is

`heap.` is a single-binary Qt6/QML application. One process — no Electron, no
browser, no remote services. Tasks, events, docs, snippets, and contacts live
side by side in a per-profile workspace that's persisted as a JSON blob in your
user data directory.

The app was ported one-to-one from a React/Babel prototype (`design/`) that
still ships with the repo for visual reference. The brand bundle lives under
`design/brand-export/`.

## Highlights

- **Kanban Board** — drag-and-drop columns, status color picker, per-card
  priority chips, branch decoration, scheduled-time pill.
- **Timeline** — overdue / today / tomorrow / week / later buckets with
  sub-grouping by date, show-done toggle, accent stripes.
- **Week** — 7-day grid with all-day deadline chips, hourly event grid, full
  drag/resize + cross-day move for events.
- **Day calendar** — drag-to-create events, top/bottom resize, drop a task to
  schedule a focus block, live now-line.
- **Docs** — sections (3GPP / internal / C++ / tools) with custom fields,
  snippet editor with syntax highlight, contact cards with per-channel info.
- **Notes** — per-profile markdown canvas with `@people` / `#ticket`
  autocomplete.
- **Profiles** — feature-scoped workspaces. JSON import / export.
- **Command palette** — `Ctrl+K` fuzzy across tasks, docs, snippets, contacts,
  people, profiles.
- **Hotkeys** — full rebindable catalog, inline capture.
- **Settings** — 10 sections (profile, appearance, notifications, calendar,
  tasks, shortcuts, C++, integrations, data, about). Persists as JSON.
- **Tweaks** — floating quick-access panel: theme, density, accent, reduced
  motion, high contrast.
- **Automation** — periodic 60s tick auto-archives done tasks, surfaces
  blocked-stuck warnings, fires deadline + standup reminders via system tray
  (respects quiet hours).

## Brand

`design/brand-export/` ships the **heap.** brand bundle: logos (mark, lockup,
wordmark), the 1024×1024 squircle app icon, palette tokens, and two QML helpers
(`Brand` singleton + `BrandLogo` component). See
[design/brand-export/README.md](design/brand-export/README.md).

The brand SVGs ride along in `qrc:/brand/...` resources baked into the
executable at build time, so nothing has to be installed system-wide.

> SVG rendering needs Qt 6 with the `Qt6::Svg` module (`qsvg` image-format
> plugin). On MSYS2: `pacman -S mingw-w64-ucrt-x86_64-qt6-svg`. Without it,
> `BrandLogo` falls back to a text wordmark — no crash, just less pretty.

## Build

Requires **Qt 6.4+** and a **C++17** toolchain.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/todocpp
```

### Linux (Debian / Ubuntu)

```sh
sudo apt install qt6-base-dev qt6-declarative-dev libqt6svg6-dev cmake g++
```

### macOS

```sh
brew install qt cmake
cmake -S . -B build -DCMAKE_PREFIX_PATH=$(brew --prefix qt)
cmake --build build -j
```

### Windows (MSYS2 UCRT64 + CLion)

1. Install [MSYS2](https://www.msys2.org/) into `C:\msys64`.
2. Open the **MSYS2 UCRT64** shell (not "MSYS" or "MinGW64").
3. Sync and install the toolchain:

   ```sh
   pacman -Syu          # restart the shell if prompted
   pacman -S --needed \
       mingw-w64-ucrt-x86_64-toolchain \
       mingw-w64-ucrt-x86_64-cmake \
       mingw-w64-ucrt-x86_64-ninja \
       mingw-w64-ucrt-x86_64-qt6-base \
       mingw-w64-ucrt-x86_64-qt6-declarative \
       mingw-w64-ucrt-x86_64-qt6-svg \
       mingw-w64-ucrt-x86_64-qt6-tools \
       git
   ```

4. Open the project in CLion → **Settings → Build, Execution, Deployment →
   Toolchains → + → MinGW**:
   - **Name:** `MSYS2 UCRT64`
   - **Toolset:** `C:\msys64\ucrt64`
5. In **Settings → CMake**, add to **CMake options**:

   ```
   -DCMAKE_PREFIX_PATH=C:/msys64/ucrt64
   ```
6. Pick the `todocpp` run configuration. `Shift+F10` to launch.
7. To run the `.exe` outside CLion, either add `C:\msys64\ucrt64\bin` to your
   `PATH`, or bundle the Qt DLLs once with `windeployqt6 --qmldir ../qml
   todocpp.exe` from inside your build directory.

## Project layout

```
.
├─ CMakeLists.txt          ← qt_add_executable + qt_add_qml_module + qt_add_resources
├─ src/
│  ├─ main.cpp             ← QApplication entry, window icon, signal handlers
│  ├─ AppController.{h,cpp}← QML_SINGLETON exposing models, profiles, automation, undo
│  ├─ Models.{h,cpp}       ← TaskModel / EventModel / PersonModel (QAbstractListModel)
│  ├─ SampleData.{h,cpp}   ← seed tasks / events / people for first run
│  ├─ CodeHighlighter.{h,cpp}  ← QSyntaxHighlighter for the docs snippet editor
│  └─ NotesHighlighter.{h,cpp} ← markdown highlighter for the Notes view
├─ qml/
│  ├─ Main.qml             ← top-level window: TopBar + SideRail + view stack + right column
│  ├─ Theme.qml            ← singleton: dark/light/density/highContrast tokens, accent reactive to Settings
│  ├─ Brand.qml            ← singleton: brand palette + tagline + asset paths
│  ├─ BrandLogo.qml        ← lockup/mark/wordmark component
│  ├─ TopBar.qml           ← BrandLogo, breadcrumbs, profile pill, search, +Task
│  ├─ SideRail.qml         ← view switcher rail with badge counts
│  ├─ FilterBar.qml        ← priority chips + Archived toggle + task counts
│  ├─ KanbanBoard.qml      ← drag-and-drop board with status columns
│  ├─ TaskCard.qml         ← per-task card (priority/branch/deadline/stuck/archived)
│  ├─ TimelineView.qml     ← deadline-bucketed agenda
│  ├─ WeekView.qml         ← 7-day grid with interactive events
│  ├─ DayCalendar.qml      ← hourly grid with drag-to-create + resize handles
│  ├─ MiniWeek.qml         ← week navigator with per-day dots
│  ├─ PeopleList.qml       ← "Кому написать" todo→pinged→replied
│  ├─ DocsView.qml         ← docs canvas (sections, snippets, contacts)
│  ├─ DocsEditor.qml       ← modal editor for docs/snippets/contacts
│  ├─ NotesView.qml        ← markdown notes canvas
│  ├─ SettingsView.qml     ← 10-section settings UI
│  ├─ TweaksPanel.qml      ← floating theme/accent/a11y quick controls
│  ├─ HotkeysPanel.qml     ← rebindable shortcut catalog
│  ├─ CommandPalette.qml   ← Ctrl+K fuzzy palette
│  ├─ TaskEditor.qml       ← task modal
│  ├─ EventEditor.qml      ← event modal
│  ├─ PersonEditor.qml     ← contact modal
│  ├─ ProfileEditor.qml    ← profile create / rename / duplicate modal
│  ├─ ThinScrollBar.qml    ← shared thin translucent scrollbar
│  ├─ Toast.qml            ← bottom-centered transient notifications
│  └─ PillButton.qml       ← rounded primary/secondary button
├─ design/
│  ├─ *.jsx                ← original React/Babel prototype (reference only)
│  ├─ styles.css           ← prototype stylesheet
│  └─ brand-export/        ← heap. brand bundle (logos, icon, fonts, QML, brand.qrc)
└─ README.md
```

## State, persistence, and data

- **Profile snapshot** — each profile owns its own tasks, people, statuses,
  docs blob, and notes blob.
- **Events** are global (so the calendar reflects every profile at once), with
  an optional `profileId` attribution.
- **Settings** live as `appSettingsJson` — a single JSON blob persisted via
  `QStandardPaths::AppDataLocation`. `SettingsView` is the canonical editor.
- **Backups** rotate daily under `<AppDataLocation>/backups/` (configurable
  retention in Settings → Data).

## Keyboard

Defaults — every entry is rebindable from **Settings → Shortcuts** or the
floating Hotkeys panel.

| Action            | Default      |
| ----------------- | ------------ |
| Open palette      | `Ctrl+K` / `Ctrl+P` |
| New task          | `Ctrl+N`     |
| Switch to Board   | `Ctrl+1`     |
| Switch to Timeline| `Ctrl+2`     |
| Switch to Week    | `Ctrl+3`     |
| Switch to Docs    | `Ctrl+4`     |
| Switch to Notes   | `Ctrl+5`     |
| Switch to Settings| `Ctrl+,`     |
| Next profile      | `Ctrl+Tab`   |
| Prev profile      | `Ctrl+Shift+Tab` |
| Focus search      | `/`          |
| Undo last deletion| `Ctrl+Z`     |
| Open Tweaks       | `Ctrl+T`     |
| Open Hotkeys      | `Ctrl+Shift+K` |

## Accessibility

- **Reduced motion** — Tweaks → Reduced motion mutes all transitions
  (`Theme.scaledMs(n)` collapses to 0).
- **High contrast** — Tweaks → High contrast strengthens border and text
  tokens.
- **Tab focus** — focusable inputs (search, breadcrumbs, settings fields)
  paint an accent border when focused.

## License

MIT — see [LICENSE](LICENSE) (if present) or treat this repo as MIT-licensed.

The brand assets in `design/brand-export/` are also MIT for use within this
codebase. Fonts referenced (IBM Plex Sans, JetBrains Mono) ship under the SIL
Open Font License — see their own repositories.
