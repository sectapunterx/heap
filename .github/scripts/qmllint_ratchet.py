#!/usr/bin/env python3
"""Ratchet on qmllint findings: no QML file may get more of them.

The UI carries a few thousand qmllint findings from before the linter ran in
CI, too many to clear in one go and not all of them real. Instead of ignoring
them all, this keeps a per-file count in a baseline and fails when a file's
count grows, so new code is held to the linter while old findings are paid
down file by file. When a count drops, it says so: lower the baseline in the
same change so the gain cannot be lost again.

Usage:
  qmllint_ratchet.py <qmllint.json> <baseline.json>            check
  qmllint_ratchet.py <qmllint.json> <baseline.json> --update   rewrite baseline

<qmllint.json> is what `cmake --build build --target all_qmllint_json` writes.
The counts depend on the Qt version's qmllint, so the baseline must come from
the Qt that CI runs (install-qt-action 6.9.1): take it from the job's
`qmllint` artifact rather than from a local build on a different Qt.
"""

import json
import sys
from collections import Counter
from pathlib import Path


def counts(report_path: Path) -> Counter:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    result = Counter()
    for entry in report.get("files", []):
        name = entry["filename"].replace("\\", "/")
        # Key by the path under the repo's qml/ dir, so the baseline does not
        # depend on where the checkout lives.
        key = "qml/" + name.split("/qml/", 1)[-1] if "/qml/" in name else name
        result[key] += sum(1 for w in entry.get("warnings", []) if w.get("type") != "info")
    return result


def write_baseline(path: Path, current: Counter) -> None:
    path.write_text(json.dumps(dict(sorted(current.items())), indent=2) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    report, baseline_path = Path(sys.argv[1]), Path(sys.argv[2])
    current = counts(report)

    if "--update" in sys.argv[3:]:
        write_baseline(baseline_path, current)
        print(f"baseline written: {sum(current.values())} findings in {len(current)} files")
        return 0

    if not baseline_path.exists():
        # First run on a new Qt or a fresh checkout of this script: record where
        # things stand instead of failing; commit the file from the artifact.
        write_baseline(baseline_path, current)
        print(f"::warning::no qmllint baseline yet - wrote {baseline_path} with {sum(current.values())} findings; "
              f"commit it from the job's qmllint artifact")
        return 0

    baseline = Counter(json.loads(baseline_path.read_text(encoding="utf-8")))
    worse = {f: (baseline[f], n) for f, n in current.items() if n > baseline[f]}
    better = {f: (baseline[f], n) for f, n in current.items() if n < baseline[f]}
    better.update({f: (baseline[f], 0) for f in baseline if f not in current and baseline[f] > 0})

    for f, (was, now) in sorted(worse.items()):
        print(f"::error file={f}::qmllint findings went from {was} to {now} - fix the new ones "
              f"(the job's qmllint artifact lists them)")
    for f, (was, now) in sorted(better.items()):
        print(f"::notice file={f}::qmllint findings dropped from {was} to {now} - lower the baseline "
              f"with --update in this change")
    print(f"qmllint: {sum(current.values())} findings (baseline {sum(baseline.values())}), "
          f"{len(worse)} file(s) worse, {len(better)} better")
    return 1 if worse else 0


if __name__ == "__main__":
    sys.exit(main())
