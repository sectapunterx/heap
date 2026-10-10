#!/usr/bin/env python3
"""Generates the static fonts under resources/fonts/ that heap ships inside the app.

Golos Text (UI) and JetBrains Mono (code, ids, times) are published by
google/fonts as variable fonts. Qt's handling of a variable font's named
instances differs by font backend and Qt version (DirectWrite, CoreText,
fontconfig; CI builds on 6.9, Windows on 6.11), so the app gets plain static
faces instead: Golos Text 400/500/600 and JetBrains Mono 400/500, cut with
fontTools.varLib.instancer from the upstream files, every glyph kept (full
Latin + Cyrillic).

Each face is named the legacy way: family "lowkey Golos Text" / "lowkey JetBrains
Mono" in name ID 1, the weight ("Medium") in name ID 2, no typographic family
(16/17). GDI reads ID 1 and DirectWrite / fontconfig prefer ID 16, so with 16
absent every backend sees one family with three (two) weights rather than
"Golos Text Medium" as a family of its own.

The "lowkey " prefix (in the family, full and PostScript names; "heap " before
0.8.0) keeps these cuts
apart from a copy of the same font installed on the machine. Under the
upstream name, Windows with JetBrains Mono installed mixed the two: text was
shaped against one file's glyph order and drawn from the other's, so every
time, count and key hint came out as random Cyrillic (0.6.0). Neither OFL.txt
declares a Reserved Font Name; the rename is for the collision, not the
licence.

Both fonts are also cut smaller than upstream. The size scale (Theme.fs*) was
set for Segoe UI and Consolas, and at the same pixel size Golos Text has a 6%
taller x-height and 10% wider letters than Segoe UI, JetBrains Mono a 12%
taller x-height and 9% wider cells than Consolas, so the interface came out
oversized. Each face gets a larger head.unitsPerEm (1000 / scale) and nothing
else: outlines, advances, kerning and the vertical metrics (hhea, OS/2 typo and
win) stay in font units, so everything, line height and widths included, is
drawn `scale` times the size it was at the same pixelSize. The scale lives in
the font rather than in Theme so that every font.pixelSize in QML, present and
future, gets it without knowing, and a font the user picks in Appearance keeps
its own size. The upstream fonts carry no hinting beyond a dropout-control
prep (no fpgm, cvt or glyph programs), so nothing depends on the old em.

    pip install fonttools
    python tools/gen_bundled_fonts.py            # downloads upstream, writes resources/fonts/
    python tools/gen_bundled_fonts.py <dir>      # uses <dir>/GolosText[wght].ttf etc. instead
    python tools/fonts/add_return_glyph.py       # then: the ↵ glyph the upstream fonts lack (R4-056)

A download also rewrites each *-OFL.txt from upstream: put back the
"Modified Version (lowkey)" note under its header.
"""

import sys
import urllib.request
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

# google/fonts main at the time the fonts were cut (2026-10-06).
# Size against upstream at the same pixelSize; tests/test_bundled_fonts.cpp
# checks the resulting unitsPerEm.
SCALE_UI = 0.93
SCALE_MONO = 0.88

UPSTREAM = "https://raw.githubusercontent.com/google/fonts/7085eb89a950e85db5b166b7a58d414544b4140c/ofl"

FONTS = [
    # (upstream dir, variable file, output stem, [(weight, style)], scale)
    ("golostext", "GolosText[wght].ttf", "GolosText", [(400, "Regular"), (500, "Medium"), (600, "SemiBold")], SCALE_UI),
    ("jetbrainsmono", "JetBrainsMono[wght].ttf", "JetBrainsMono", [(400, "Regular"), (500, "Medium")], SCALE_MONO),
]

OUT = Path(__file__).resolve().parent.parent / "resources" / "fonts"
FS_SELECTION_REGULAR = 0x40


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url) as r:  # noqa: S310 - fixed https URL
        return r.read()


def main() -> None:
    src_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    OUT.mkdir(parents=True, exist_ok=True)
    for updir, varfile, stem, weights, scale in FONTS:
        if src_dir:
            var_path = src_dir / varfile
        else:
            var_path = OUT / ("_" + varfile)
            var_path.write_bytes(fetch(f"{UPSTREAM}/{updir}/{varfile.replace('[', '%5B').replace(']', '%5D')}"))
            (OUT / f"{stem}-OFL.txt").write_bytes(fetch(f"{UPSTREAM}/{updir}/OFL.txt"))
        family = "lowkey " + TTFont(var_path)["name"].getDebugName(1)
        ps_family = family.replace(" ", "")
        for weight, style in weights:
            font = instancer.instantiateVariableFont(TTFont(var_path), {"wght": weight}, updateFontNames=True)
            names = font["name"]
            for rec in list(names.names):
                if rec.nameID == 1:
                    names.setName(family, 1, rec.platformID, rec.platEncID, rec.langID)
                elif rec.nameID == 2:
                    names.setName(style, 2, rec.platformID, rec.platEncID, rec.langID)
                elif rec.nameID == 3:
                    version = rec.toUnicode().split(";")[0]
                    names.setName(f"{version};lowkey;{ps_family}-{style}", 3, rec.platformID, rec.platEncID, rec.langID)
                elif rec.nameID == 4:
                    names.setName(f"{family} {style}", 4, rec.platformID, rec.platEncID, rec.langID)
                elif rec.nameID == 6:
                    names.setName(f"{ps_family}-{style}", 6, rec.platformID, rec.platEncID, rec.langID)
            names.removeNames(nameID=16)
            names.removeNames(nameID=17)
            names.removeNames(nameID=25)  # variations PostScript prefix: upstream name, no axes left
            if weight != 400:
                font["OS/2"].fsSelection &= ~FS_SELECTION_REGULAR
            upm = round(font["head"].unitsPerEm / scale)
            assert 16 <= upm <= 16384, upm
            font["head"].unitsPerEm = upm
            font.recalcTimestamp = False  # keep upstream head.modified: same bytes on every run
            out = OUT / f"{stem}-{style}.ttf"
            font.save(out)
            print(f"{out.name}: {family} {style} ({font['OS/2'].usWeightClass}), UPM {upm}, {out.stat().st_size} bytes")
        if not src_dir:
            var_path.unlink()


if __name__ == "__main__":
    main()
