#!/usr/bin/env python3
"""Ratchet on qmllint findings: no QML file may get more of them.

The UI carries qmllint findings from before the linter ran in CI, too many to
clear in one go and not all of them real. Instead of ignoring them all, this
keeps a per-file count in a baseline and fails when a file's count grows, so
new code is held to the linter while old findings are paid down file by file.
When a count drops, it says so: lower the baseline in the same change so the
gain cannot be lost again.

A count can also grow without the change adding a finding: qmllint re-types a
file when a component or C++ type it uses changes, and shifts the count of a
file nobody touched. With --diff, only findings on the lines the change itself
added or edited fail the check, each shown as an annotation on its line; growth
anywhere else is a warning that says to take the new baseline.

Usage:
  qmllint_ratchet.py <qmllint.json> <baseline.json>                  check
  qmllint_ratchet.py <qmllint.json> <baseline.json> --diff <ref>     check, judged on lines changed since <ref>
  qmllint_ratchet.py <qmllint.json> <baseline.json> --update         rewrite baseline

<qmllint.json> is what `cmake --build build --target all_qmllint_json` writes.
The counts depend on the Qt version's qmllint, so the baseline must come from
the Qt that CI runs (install-qt-action 6.9.1): take it from the job's
`qmllint` artifact rather than from a local build on a different Qt.
"""

import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

# Enough to point at the problem; the artifact has the full report.
MAX_ANNOTATIONS_PER_FILE = 25


def repo_key(filename: str) -> str:
    # Key by the path under the repo's qml/ dir, so the baseline does not
    # depend on where the checkout lives.
    name = filename.replace("\\", "/")
    return "qml/" + name.split("/qml/", 1)[-1] if "/qml/" in name else name


def findings(report_path: Path) -> dict:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    result = defaultdict(list)
    for entry in report.get("files", []):
        key = repo_key(entry["filename"])
        for w in entry.get("warnings", []):
            if w.get("type") != "info":
                result[key].append(w)
    return result


def counts(found: dict) -> Counter:
    return Counter({f: len(ws) for f, ws in found.items()})


def changed_lines(ref: str) -> dict:
    """Lines added or edited since <ref>, per repo-relative QML/JS file."""
    out = subprocess.run(["git", "diff", "-U0", "--no-color", ref, "--", "*.qml", "*.js"],
                         check=True, capture_output=True, text=True, encoding="utf-8").stdout
    result = defaultdict(set)
    current = None
    for line in out.splitlines():
        if line.startswith("+++ "):
            path = line[4:].strip()
            current = path[2:] if path.startswith("b/") else None
        elif line.startswith("@@") and current:
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            start, length = int(m.group(1)), int(m.group(2) or "1")
            result[current].update(range(start, start + length))
    return result


def annotate(level: str, f: str, w: dict) -> None:
    line = w.get("line") or 1
    col = w.get("column") or 1
    msg = w.get("message", "").replace("\n", " ")
    print(f"::{level} file={f},line={line},col={col}::qmllint [{w.get('id', w.get('type'))}] {msg}")


def write_baseline(path: Path, current: Counter) -> None:
    path.write_text(json.dumps(dict(sorted(current.items())), indent=2) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    report, baseline_path = Path(sys.argv[1]), Path(sys.argv[2])
    args = sys.argv[3:]
    found = findings(report)
    current = counts(found)

    if "--update" in args:
        write_baseline(baseline_path, current)
        print(f"baseline written: {sum(current.values())} findings in {len(current)} files")
        return 0

    if not baseline_path.exists():
        # First run on a new Qt or a fresh checkout of this script: record where
        # things stand instead of failing; commit the file from the artifact.
        write_baseline(baseline_path, current)
        print("::group::baseline")
        print(baseline_path.read_text(encoding="utf-8"))
        print("::endgroup::")
        print(f"::warning::no qmllint baseline yet - wrote {baseline_path} with {sum(current.values())} findings; "
              f"commit it from the job's qmllint artifact")
        return 0

    touched = None
    if "--diff" in args:
        ref = args[args.index("--diff") + 1]
        try:
            touched = changed_lines(ref)
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"::warning::qmllint ratchet: cannot diff against {ref} ({e}); judging on counts alone")

    baseline = Counter(json.loads(baseline_path.read_text(encoding="utf-8")))
    worse = {f: (baseline[f], n) for f, n in current.items() if n > baseline[f]}
    better = {f: (baseline[f], n) for f, n in current.items() if n < baseline[f]}
    better.update({f: (baseline[f], 0) for f in baseline if f not in current and baseline[f] > 0})

    failed = []
    for f, (was, now) in sorted(worse.items()):
        if touched is None:
            print(f"::error file={f}::qmllint findings went from {was} to {now} - fix the new ones")
            for w in found[f][:MAX_ANNOTATIONS_PER_FILE]:
                annotate("warning", f, w)
            failed.append(f)
            continue
        on_changed = [w for w in found[f] if (w.get("line") or 0) in touched.get(f, set())]
        if on_changed:
            print(f"::error file={f}::qmllint findings went from {was} to {now}; "
                  f"{len(on_changed)} on lines this change wrote (annotated)")
            for w in on_changed[:MAX_ANNOTATIONS_PER_FILE]:
                annotate("error", f, w)
            failed.append(f)
        else:
            print(f"::warning file={f}::qmllint findings went from {was} to {now}, none on lines this change "
                  f"wrote (a type it uses changed) - take the new count with --update from the qmllint artifact")
    for f, (was, now) in sorted(better.items()):
        print(f"::notice file={f}::qmllint findings dropped from {was} to {now} - lower the baseline "
              f"with --update in this change")
    print(f"qmllint: {sum(current.values())} findings (baseline {sum(baseline.values())}), "
          f"{len(worse)} file(s) grew, {len(failed)} with findings in changed lines, {len(better)} better")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
