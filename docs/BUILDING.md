# Building heap. from source

Prebuilt binaries for Windows, macOS and Linux are attached to every
[GitHub release](https://github.com/sectapunterx/heap/releases). Build from source if you want to hack on heap. or
run an unreleased commit.

You need **Qt 6.9+** (what CI builds and tests) and a **C++20** toolchain. On any platform:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/heap                  # ./build/heap.exe on Windows
```

## Linux

On a rolling distribution with a current Qt (Arch ships 6.11), the system packages are enough:

```sh
sudo pacman -S --needed qt6-base qt6-declarative qt6-svg qt6-networkauth qtkeychain-qt6 cmake ninja
```

Elsewhere distribution Qt is often too old: Ubuntu 24.04 ships 6.4, on which the UI does not run. Take Qt 6.9 from
[aqtinstall](https://github.com/miurahr/aqtinstall) (what CI does) or the Qt online installer:

```sh
pip install aqtinstall
aqt install-qt linux desktop 6.9.1 linux_gcc_64 -m qtnetworkauth -O ~/Qt
cmake -S . -B build -DCMAKE_PREFIX_PATH=~/Qt/6.9.1/gcc_64 && cmake --build build -j
```

Releases up to 0.5.1 also shipped a `.deb` and a tarball built against Ubuntu 24.04's Qt 6.4. The UI does not run on
Qt 6.4, so those are gone; the AppImage carries its own Qt.

## macOS

```sh
brew install qt cmake
cmake -S . -B build -DCMAKE_PREFIX_PATH=$(brew --prefix qt)
cmake --build build -j
```

## Windows (MSYS2 UCRT64 + CLion)

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
       mingw-w64-ucrt-x86_64-qt6-networkauth \
       mingw-w64-ucrt-x86_64-qtkeychain \
       git
   ```

4. Open the project in CLion. Under **Settings → Build, Execution, Deployment → Toolchains → + → MinGW**:
   - **Name:** `MSYS2 UCRT64`
   - **Toolset:** `C:\msys64\ucrt64`
5. In **Settings → CMake**, add to **CMake options**: `-DCMAKE_PREFIX_PATH=C:/msys64/ucrt64`
6. Pick the `heap` run configuration. `Shift+F10` to launch.
7. To run `heap.exe` outside CLion, add `C:\msys64\ucrt64\bin` to `PATH`, or bundle the Qt DLLs once with
   `windeployqt6 --qmldir ../qml heap.exe` from the build directory.

## Next

- [CONTRIBUTING.md](../CONTRIBUTING.md) — tests, CI, branch naming, project layout.
- [PACKAGING.md](PACKAGING.md) — how the installer / AppImage / portable bundles are built.
