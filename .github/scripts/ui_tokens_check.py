#!/usr/bin/env python3
"""Keep the QML on the design tokens in qml/Theme.qml.

Fails when a QML file paints with a literal instead of a token:

  - a font size (`pixelSize: 12`) instead of Theme.fsXs .. Theme.fs2xl;
  - a spacing, margin or padding between 2 and 24px instead of
    Theme.sp2xs .. Theme.sp3xl / Theme.inset. 0 and 1px hairlines, negative
    offsets and large layout constants stay literal;
  - a colour ("#5cc2dd") instead of a Theme token or Theme.swatches;
  - a number in an animation's `duration:` (`duration: 120`,
    `Theme.scaledMs(220)`) instead of Theme.durTap / durPop / durMove (or
    their *Out halves), or an `Easing.*` curve instead of Theme.easeEnter /
    Theme.easeExit. Only Theme.qml names a duration or a curve, so the
    whole app moves on one rule and "Reduce motion" zeroes every animation;
  - a font weight (`font.weight: Font.DemiBold`, `font.weight: 600`)
    instead of Theme.fwBody / fwTitle / fwHeading. Three weights, one job
    each: a free choice is what put DemiBold on 117 labels;
  - a label in capitals: `font.capitalization: Font.AllUppercase`,
    `I18n.t(...).toUpperCase()` or a positive `font.letterSpacing`.
    Labels are sentence case and untracked: Cyrillic in caps with
    tracking was the loudest thing on every screen.

A literal is what made the app grow 15 font sizes and 22 margins, and what
kept Tweaks -> Density from moving anything but the hour height.

Usage: ui_tokens_check.py [qml-dir]   (default: qml)
"""
import pathlib
import re
import sys

# The brand mark and the splash screen draw with the Brand singleton on
# purpose: they are shown before, and regardless of, the user's theme.
EXEMPT_ALL = {"Brand.qml", "BrandLogo.qml", "SplashScreen.qml"}
# Files whose job is to hold colours: the palettes, the free colour picker,
# the high-contrast pure black/white, and the docs starter's sample content.
EXEMPT_HEX = EXEMPT_ALL | {"ThemePresets.js", "Theme.qml", "ColorPickerPopup.qml", "DocsStarter.js"}

END = r"\s*(?:;|\}|$|//)"
FONT = re.compile(r"\bpixelSize:\s*(\d+)" + END)
SPACE_PROPS = ("spacing|rowSpacing|columnSpacing|margins|leftMargin|rightMargin|topMargin|bottomMargin|"
               "padding|leftPadding|rightPadding|topPadding|bottomPadding|horizontalPadding|verticalPadding")
SPACE = re.compile(r"(?<![\w.])(?:\w+\.)*(?:" + SPACE_PROPS + r"):\s*(\d+)" + END)
DURATION = re.compile(r"\bduration:\s*([^;}]*)")
NUMBER = re.compile(r"(?<![\w.])\d")
EASING = re.compile(r"\bEasing\.\w+")
WEIGHT = re.compile(r"\bFont\.(?:Thin|ExtraLight|Light|Normal|Medium|DemiBold|Bold|ExtraBold|Black)\b"
                    r"|\b(?:font\.)?weight:\s*\d")
CAPS = re.compile(r"\bfont\.capitalization:\s*Font\.AllUppercase\s*(?:;|\}|$|//)"
                  r"|\bI18n\.\w+\((?:[^()]|\([^()]*\))*\)\.toUpperCase\(\)"
                  r"|\bfont\.letterSpacing:\s*(?:0?\.0*[1-9]|[1-9])")
HEX = re.compile(r"[\"']#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})[\"']")


def check(root: pathlib.Path):
    problems = []
    files = sorted(list(root.glob("*.qml")) + list(root.glob("*.js")))
    for f in files:
        if f.name in EXEMPT_ALL:
            continue
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("//", 1)[0] if line.lstrip().startswith("//") else line
            if not code.strip():
                continue
            if f.suffix == ".qml":
                m = FONT.search(code)
                if m:
                    problems.append(f"{f}:{n}: font size {m.group(1)}px - use a Theme.fs* token")
                for m in SPACE.finditer(code):
                    v = int(m.group(1))
                    if 2 <= v <= 24:
                        problems.append(f"{f}:{n}: spacing {v}px - use a Theme.sp* token or Theme.inset")
                if f.name != "Theme.qml":
                    m = DURATION.search(code)
                    if m and code[:m.start()].count('"') % 2 == 0 and NUMBER.search(m.group(1).split("//", 1)[0]):
                        problems.append(f"{f}:{n}: duration literal - use Theme.durTap / durPop / durMove")
                    m = EASING.search(code)
                    if m:
                        problems.append(f"{f}:{n}: easing {m.group(0)} - use Theme.easeEnter / Theme.easeExit")
                    m = WEIGHT.search(code)
                    if m:
                        problems.append(f"{f}:{n}: font weight {m.group(0)} - use Theme.fwBody / fwTitle / fwHeading")
                    m = CAPS.search(code)
                    if m:
                        problems.append(f"{f}:{n}: caps label {m.group(0)} - labels are sentence case, untracked")
            if f.name not in EXEMPT_HEX and HEX.search(code):
                problems.append(f"{f}:{n}: colour literal - use a Theme token or Theme.swatches")
    return problems


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "qml")
    problems = check(root)
    for p in problems:
        print(p)
    if problems:
        print(f"\n{len(problems)} literal(s) off the design tokens (see qml/Theme.qml).")
        return 1
    print("ui tokens: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
