#!/usr/bin/env python3
"""Outline the text in a brand surface SVG so it renders the same everywhere.

The surface SVGs name IBM Plex Sans / Serif and JetBrains Mono but cannot load
them: GitHub, social cards and most viewers render an <img> SVG without web
fonts and fall back to Arial / Georgia. This replaces every <text> with the
glyph outlines from the fonts the site already ships, so the file needs no
font at all.

    python design/brand-export/outline_svg.py \
        design/brand-export/surfaces/heap-og-card.svg \
        design/brand-export/surfaces/heap-og-card-outlined.svg

Needs fontTools and brotli (`pip install fonttools brotli`). Kerning is not
applied; letter-spacing, font-size, weight and text-anchor are.
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

SVG_NS = "http://www.w3.org/2000/svg"
FONTS_DIR = Path(__file__).resolve().parents[2] / "site" / "public" / "brand" / "assets" / "fonts"
FAMILIES = {
    "ibm plex sans": "ibm-plex-sans",
    "ibm plex serif": "ibm-plex-serif",
    "jetbrains mono": "jetbrains-mono",
}
INHERITED = ("font-family", "font-weight", "font-size", "letter-spacing", "fill", "text-anchor")

_fonts = {}


def load_font(family, weight):
    stem = FAMILIES.get(family.lower())
    if stem is None:
        raise SystemExit(f"no outline font for family {family!r}")
    available = sorted(int(p.stem.split("-")[-2]) for p in FONTS_DIR.glob(f"{stem}-latin-*-normal.woff2"))
    best = min(available, key=lambda w: abs(w - weight))
    key = (stem, best)
    if key not in _fonts:
        _fonts[key] = TTFont(FONTS_DIR / f"{stem}-latin-{best}-normal.woff2")
    return _fonts[key]


def first_family(value):
    for name in value.split(","):
        name = name.strip().strip("'\"")
        if name.lower() in FAMILIES:
            return name
    raise SystemExit(f"no known family in {value!r}")


def svg_text(el):
    # SVG's default white-space handling: newlines dropped, runs of spaces
    # collapsed, leading and trailing space stripped.
    raw = "".join(el.itertext()).replace("\n", "").replace("\t", " ")
    return re.sub(r" +", " ", raw).strip()


def outline(text, font, size, spacing, x, y, anchor):
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    hmtx = font["hmtx"]
    scale = size / font["head"].unitsPerEm
    names = [cmap.get(ord(ch), ".notdef") for ch in text]
    advances = [hmtx[n][0] * scale + spacing for n in names]
    width = sum(advances) - (spacing if names else 0)
    if anchor == "end":
        x -= width
    elif anchor == "middle":
        x -= width / 2
    pen = SVGPathPen(glyphs)
    cursor = x
    for name, adv in zip(names, advances):
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, cursor, y)))
        cursor += adv
    return pen.getCommands()


def walk(el, inherited):
    attrs = dict(inherited)
    for key in INHERITED:
        if key in el.attrib:
            attrs[key] = el.attrib[key]
    for i, child in enumerate(list(el)):
        if child.tag == f"{{{SVG_NS}}}text":
            a = dict(attrs)
            for key in INHERITED:
                if key in child.attrib:
                    a[key] = child.attrib[key]
            font = load_font(first_family(a["font-family"]), int(a.get("font-weight", 400)))
            d = outline(svg_text(child), font, float(a["font-size"]), float(a.get("letter-spacing", 0)),
                        float(child.attrib.get("x", 0)), float(child.attrib.get("y", 0)),
                        a.get("text-anchor", "start"))
            path = ET.Element(f"{{{SVG_NS}}}path", {"d": d, "fill": a.get("fill", "#000")})
            el.remove(child)
            el.insert(i, path)
        else:
            walk(child, attrs)


def main(src, dst):
    ET.register_namespace("", SVG_NS)
    tree = ET.parse(src)
    walk(tree.getroot(), {})
    tree.write(dst, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
