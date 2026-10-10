# Third-party notices

lowkey bundles the third-party components listed here. Each is used under its own
license, reproduced in full alongside the code it covers.

## md4c

- Source: https://github.com/mity/md4c
- Version: 0.5.3 (`release-0.5.3`)
- License: MIT — `third_party/md4c/LICENSE.md`
- Copyright © 2016-2024 Martin Mitáš
- Vendored at `third_party/md4c/`; provenance and update steps in
  `third_party/md4c/README.heap.md`.

md4c is the CommonMark parser behind lowkey's notes editor. Its sources are
included verbatim and compiled into the application.

## Golos Text

- Source: https://github.com/googlefonts/golos-text (as published in
  https://github.com/google/fonts, `ofl/golostext`), version 2.004
- License: SIL Open Font License 1.1 — `resources/fonts/GolosText-OFL.txt`
- Copyright 2019 The Golos Text Project Authors
- No Reserved Font Name is declared.

The interface font. lowkey ships static Regular, Medium and SemiBold faces cut
from the upstream variable font by `tools/gen_bundled_fonts.py` (weight
instancing and name-table changes only, every glyph kept); they are compiled
into the application.

## JetBrains Mono

- Source: https://github.com/JetBrains/JetBrainsMono (as published in
  https://github.com/google/fonts, `ofl/jetbrainsmono`), version 2.211
- License: SIL Open Font License 1.1 — `resources/fonts/JetBrainsMono-OFL.txt`
- Copyright 2020 The JetBrains Mono Project Authors
- No Reserved Font Name is declared.

The monospace font for code, ids and times. Static Regular and Medium faces,
cut and shipped the same way as Golos Text.

## Qt

lowkey links the Qt 6 libraries under the GNU Lesser General Public License v3.
Qt is not redistributed as source here; see https://www.qt.io/licensing and the
license texts shipped with your Qt installation. Binary releases of lowkey include
the Qt libraries they load, and the corresponding Qt sources for the exact
version used are available from https://download.qt.io.

## QtKeychain

- Source: https://github.com/frankosterfeld/qtkeychain
- License: Modified BSD (2-clause)

Used, when available at build time, to store integration tokens in the operating
system's keychain rather than on disk.
