# todo·cpp

Native desktop kanban + calendar for C++ engineers. Qt 6 + QML + C++.

## Build

Requires Qt 6.4+ and a C++17 toolchain.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/todocpp
```

### Linux package install (Debian/Ubuntu)

```sh
sudo apt install qt6-base-dev qt6-declarative-dev cmake g++
```

### macOS

```sh
brew install qt cmake
cmake -S . -B build -DCMAKE_PREFIX_PATH=$(brew --prefix qt)
cmake --build build -j
```

### Windows

Install Qt 6 via the Qt Online Installer (with MSVC or MinGW), open the
project in Qt Creator, or invoke CMake with `-DCMAKE_PREFIX_PATH=<Qt path>`.

## Layout

- `CMakeLists.txt` — CMake project with `qt_add_qml_module`.
- `src/`
  - `main.cpp` — `QGuiApplication` + `QQmlApplicationEngine` entry.
  - `AppController.{h,cpp}` — exposes models, statuses, ops, today/selectedDate, theme & density to QML as a `QML_SINGLETON`.
  - `Models.{h,cpp}` — `TaskModel`, `EventModel`, `PersonModel` (`QAbstractListModel`).
  - `SampleData.{h,cpp}` — sample tasks, events, people.
- `qml/`
  - `Main.qml` — top-level window; grid layout for top bar / side rail / main / right column.
  - `Theme.qml` — singleton with dark/light + compact/comfy tokens and helpers.
  - `TopBar.qml` — brand, breadcrumbs, search, +Task.
  - `SideRail.qml` — icon rail with status counts.
  - `FilterBar.qml` — priority filter chips + task counts.
  - `KanbanBoard.qml` + `TaskCard.qml` — board with drag-to-move and filter.
  - `MiniWeek.qml`, `DayCalendar.qml` — week navigator and day grid.
  - `PeopleList.qml` — "Кому написать" with `todo → pinged → replied` cycle.
  - `TaskEditor.qml`, `EventEditor.qml` — modal editors.
  - `TweaksPanel.qml` — floating theme/density panel.
  - `Toast.qml` — transient confirmations.
- `design/` — the original React/Babel prototype (reference only).
