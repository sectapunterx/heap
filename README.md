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

### Windows (рекомендуется MSYS2 UCRT64 + CLion)

#### 1. Установить MSYS2

Скачать инсталлятор с [msys2.org](https://www.msys2.org/) и поставить
в `C:\msys64` (путь по умолчанию). После установки открыть терминал
**MSYS2 UCRT64** (не «MSYS» и не «MinGW64» — нам нужен именно UCRT64).

Обновить пакетную базу:

```sh
pacman -Syu          # закрыть и снова открыть терминал, если попросит
pacman -Su
```

#### 2. Установить toolchain и Qt 6

В том же UCRT64-терминале:

```sh
pacman -S --needed \
    mingw-w64-ucrt-x86_64-toolchain \
    mingw-w64-ucrt-x86_64-cmake \
    mingw-w64-ucrt-x86_64-ninja \
    mingw-w64-ucrt-x86_64-qt6-base \
    mingw-w64-ucrt-x86_64-qt6-declarative \
    mingw-w64-ucrt-x86_64-qt6-tools \
    git
```

Проверить, что всё на месте:

```sh
qmake6 --version       # должен показать Qt 6.x
cmake --version
g++ --version
```

#### 3. Склонировать репозиторий

```sh
git clone <repo-url> todolist
cd todolist
```

#### 4. Открыть проект в CLion

1. **File → Open…** → выбрать папку `todolist` (CLion подхватит
   `CMakeLists.txt`).
2. **File → Settings → Build, Execution, Deployment → Toolchains**:
   - **+ → MinGW**
   - **Name:** `MSYS2 UCRT64`
   - **Toolset:** `C:\msys64\ucrt64`
   - CLion должен сам подобрать `gcc.exe`, `g++.exe`, `mingw32-make.exe` /
     `ninja.exe`, `gdb.exe`. Если поля пустые — указать вручную из
     `C:\msys64\ucrt64\bin\`.
3. **Settings → Build, Execution, Deployment → CMake**:
   - В **CMake options** добавить:
     ```
     -DCMAKE_PREFIX_PATH=C:/msys64/ucrt64
     ```
     Это нужно, чтобы CMake нашёл `Qt6Config.cmake`.
   - **Generator:** `Ninja` (быстрее) либо «Let CMake decide».
   - **Build type:** `Release` (или `Debug` для отладки).
4. **OK** → CLion перезагрузит CMake-проект и должен написать
   `-- Configuring done`.

#### 5. Запустить

В верхнем правом углу выбрать конфигурацию **todocpp** и нажать
**Run** (`Shift+F10`).

#### 6. Если приложение не запускается вне CLion

CLion подкладывает `PATH` от toolchain автоматически, а двойной клик
по `todocpp.exe` — нет, и не находит Qt-DLL. Два варианта:

**Вариант А — добавить `C:\msys64\ucrt64\bin` в системный `PATH`:**
Settings (Windows) → System → About → Advanced system settings →
Environment Variables → Path → Edit → New.

**Вариант Б — собрать standalone-сборку через `windeployqt6`:**

```sh
cd cmake-build-release        # или build/, смотря как назвал CLion
windeployqt6 --qmldir ../qml todocpp.exe
```

Это положит рядом с `.exe` все нужные Qt-DLL и QML-плагины — папку
можно копировать на другую машину как есть.


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
