#!/usr/bin/env python3
"""Keep displayed dates and times on the UI-language formatter (APP-188).

A date the user reads goes through one table of named styles:
I18n.fmtDate / fmtTime / fmtDateTime in QML, heap::text::formatDate /
formatTime / formatDateTime (src/text/LocaleFormat.h) or
AppController::dateLabel / eventHourLabel in C++. The clock follows the
12h / 24h setting. Before this check there were 21 hand-picked patterns
("dd.MM HH:mm", "d MMM", "yyyy-MM-dd" in a header…) that read Russian-style
in English and ignored the clock setting.

Fails on:
  - QML/JS: toLocaleDateString / toLocaleTimeString / toLocaleString or
    Qt.formatDate / formatTime / formatDateTime with a literal pattern;
  - QML/JS: a clock built by hand, `String(d.getHours()).padStart(2, "0")`;
  - C++ (src/): .toString("…") / QStringLiteral("…") with a date pattern.

Machine formats stay: a pattern that starts with "yyyy" and has no month or
day names ("yyyy-MM-dd", "yyyy-MM-dd HH:mm"), or a packed one ("HHmmss"),
is ISO-like: for files, state, sort keys and text a parser reads back.
Anything else that really is not display text carries a `machine-format`
comment on its line.

Usage: date_format_check.py [qml-dir] [src-dir]   (default: qml src)
"""
import pathlib
import re
import sys

MARKER = "machine-format"
# The formatter itself.
EXEMPT = {"I18n.qml", "Theme.qml", "LocaleFormat.h"}

QML_CALL = re.compile(r"\b(?:toLocaleDateString|toLocaleTimeString|toLocaleString|"
                      r"formatDate|formatTime|formatDateTime)\s*\((?:[^()]|\([^()]*\))*?,\s*[\"']([^\"']*)[\"']")
# `String(d.getHours()).padStart(2, "0")`, or a helper's `p2(d.getHours()) + ":"`.
QML_CLOCK = re.compile(r"getHours\(\)\s*\)\s*(?:\.padStart|\+\s*[\"']:)|getMinutes\(\)\s*\)\s*\.padStart")
CPP_CALL = re.compile(r"\.toString\(\s*(?:QStringLiteral\(|QLatin1String\()?\s*\"([^\"]*)\"")
DATE_TOKENS = re.compile(r"(?:d{1,4}|M{1,4}|yy(?:yy)?|H{1,2}|h{1,2}|mm|ss|AP|ap)")


def is_machine(pattern: str) -> bool:
    if "MMM" in pattern or "ddd" in pattern:
        return False
    # ISO-like ("yyyy-MM-dd HH:mm") or packed with no separators ("HHmmss" in .ics).
    return pattern.startswith("yyyy") or re.fullmatch(r"[yMdHhms]+", pattern) is not None


def looks_like_date(pattern: str) -> bool:
    # "%1", "0x", hex widths and the like are not date patterns.
    stripped = re.sub(r"'[^']*'", "", pattern)
    return bool(DATE_TOKENS.search(stripped)) and not re.search(r"[A-Za-z]", DATE_TOKENS.sub("", stripped))


def check(qml_root: pathlib.Path, src_root: pathlib.Path):
    problems = []
    for f in sorted(list(qml_root.glob("*.qml")) + list(qml_root.glob("*.js"))):
        if f.name in EXEMPT:
            continue
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("//") or MARKER in line:
                continue
            for m in QML_CALL.finditer(line):
                if not is_machine(m.group(1)):
                    problems.append(f"{f}:{n}: date pattern \"{m.group(1)}\" - use I18n.fmtDate / fmtTime / fmtDateTime")
            if QML_CLOCK.search(line):
                problems.append(f"{f}:{n}: clock built by hand - use I18n.fmtTime (follows the 12h/24h setting)")
    for f in sorted(list(src_root.rglob("*.cpp")) + list(src_root.rglob("*.h"))):
        if f.name in EXEMPT:
            continue
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("//") or MARKER in line:
                continue
            for m in CPP_CALL.finditer(line):
                p = m.group(1)
                if looks_like_date(p) and not is_machine(p):
                    problems.append(f"{f}:{n}: date pattern \"{p}\" - use heap::text::formatDate / formatTime "
                                    "(src/text/LocaleFormat.h)")
    return problems


def main():
    qml_root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "qml")
    src_root = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "src")
    problems = check(qml_root, src_root)
    for p in problems:
        print(p)
    if problems:
        print(f"\n{len(problems)} displayed date(s) off the UI-language formatter (see src/text/LocaleFormat.h).")
        sys.exit(1)
    print("date formats ok")


if __name__ == "__main__":
    main()
