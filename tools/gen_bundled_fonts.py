#!/usr/bin/env python3
"""Generates the static fonts under resources/fonts/ that heap ships inside the app.

Golos Text (UI) and JetBrains Mono (code, ids, times) are published by
google/fonts as variable fonts. Qt's handling of a variable font's named
instances differs by font backend and Qt version (DirectWrite, CoreText,
fontconfig; CI builds on 6.9, Windows on 6.11), so the app gets plain static
faces instead: Golos Text 400/500/600 and JetBrains Mono 400/500, cut with
fontTools.varLib.instancer from the upstream files, every glyph kept (full
Latin + Cyrillic).

Each face is named the legacy way: family "heap Golos Text" / "heap JetBrains
Mono" in name ID 1, the weight ("Medium") in name ID 2, no typographic family
(16/17). GDI reads ID 1 and DirectWrite / fontconfig prefer ID 16, so with 16
absent every backend sees one family with three (two) weights rather than
"Golos Text Medium" as a family of its own.

The "heap " prefix (in the family, full and PostScript names) keeps these cuts
apart from a copy of the same font installed on the machine. Under the
upstream name, Windows with JetBrains Mono installed mixed the two: text was
shaped against one file's glyph order and drawn from the other's, so every
time, count and key hint came out as random Cyrillic (0.6.0). Neither OFL.txt
declares a Reserved Font Name; the rename is for the collision, not the
licence.

    pip install fonttools
    python tools/gen_bundled_fonts.py            # downloads upstream, writes resources/fonts/
    python tools/gen_bundled_fonts.py <dir>      # uses <dir>/GolosText[wght].ttf etc. instead
"""

import sys
import urllib.request
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

# google/fonts main at the time the fonts were cut (2026-10-06).
UPSTREAM = "https://raw.githubusercontent.com/google/fonts/7085eb89a950e85db5b166b7a58d414544b4140c/ofl"

FONTS = [
    # (upstream dir, variable file, output stem, [(weight, style)])
    ("golostext", "GolosText[wght].ttf", "GolosText", [(400, "Regular"), (500, "Medium"), (600, "SemiBold")]),
    ("jetbrainsmono", "JetBrainsMono[wght].ttf", "JetBrainsMono", [(400, "Regular"), (500, "Medium")]),
]

OUT = Path(__file__).resolve().parent.parent / "resources" / "fonts"
FS_SELECTION_REGULAR = 0x40


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url) as r:  # noqa: S310 - fixed https URL
        return r.read()


def main() -> None:
    src_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    OUT.mkdir(parents=True, exist_ok=True)
    for updir, varfile, stem, weights in FONTS:
        if src_dir:
            var_path = src_dir / varfile
        else:
            var_path = OUT / ("_" + varfile)
            var_path.write_bytes(fetch(f"{UPSTREAM}/{updir}/{varfile.replace('[', '%5B').replace(']', '%5D')}"))
            (OUT / f"{stem}-OFL.txt").write_bytes(fetch(f"{UPSTREAM}/{updir}/OFL.txt"))
        family = "heap " + TTFont(var_path)["name"].getDebugName(1)
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
                    names.setName(f"{version};heap;{ps_family}-{style}", 3, rec.platformID, rec.platEncID, rec.langID)
                elif rec.nameID == 4:
                    names.setName(f"{family} {style}", 4, rec.platformID, rec.platEncID, rec.langID)
                elif rec.nameID == 6:
                    names.setName(f"{ps_family}-{style}", 6, rec.platformID, rec.platEncID, rec.langID)
            names.removeNames(nameID=16)
            names.removeNames(nameID=17)
            names.removeNames(nameID=25)  # variations PostScript prefix: upstream name, no axes left
            if weight != 400:
                font["OS/2"].fsSelection &= ~FS_SELECTION_REGULAR
            font.recalcTimestamp = False  # keep upstream head.modified: same bytes on every run
            out = OUT / f"{stem}-{style}.ttf"
            font.save(out)
            print(f"{out.name}: {family} {style} ({font['OS/2'].usWeightClass}), {out.stat().st_size} bytes")
        if not src_dir:
            var_path.unlink()


if __name__ == "__main__":
    main()
