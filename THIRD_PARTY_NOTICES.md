# Third-party notices

heap. bundles the third-party components listed here. Each is used under its own
license, reproduced in full alongside the code it covers.

## md4c

- Source: https://github.com/mity/md4c
- Version: 0.5.3 (`release-0.5.3`)
- License: MIT — `third_party/md4c/LICENSE.md`
- Copyright © 2016-2024 Martin Mitáš
- Vendored at `third_party/md4c/`; provenance and update steps in
  `third_party/md4c/README.heap.md`.

md4c is the CommonMark parser behind heap's notes editor. Its sources are
included verbatim and compiled into the application.

## Qt

heap links the Qt 6 libraries under the GNU Lesser General Public License v3.
Qt is not redistributed as source here; see https://www.qt.io/licensing and the
license texts shipped with your Qt installation. Binary releases of heap include
the Qt libraries they load, and the corresponding Qt sources for the exact
version used are available from https://download.qt.io.

## QtKeychain

- Source: https://github.com/frankosterfeld/qtkeychain
- License: Modified BSD (2-clause)

Used, when available at build time, to store integration tokens in the operating
system's keychain rather than on disk.
