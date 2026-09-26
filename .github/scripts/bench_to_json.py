#!/usr/bin/env python3
"""Turns the benchmark suites' printed timings into github-action-benchmark input.

heap_md_bench_tests and heap_save_bench_tests assert only a categorical budget
and print the actual numbers; this collects those numbers so the nightly job
can chart them and flag a drift long before a budget trips.

Usage: bench_to_json.py <output.json> <log>...
Writes the "customSmallerIsBetter" format: [{"name", "unit", "value"}, ...].
"""

import json
import re
import sys

PATTERNS = [
    # [ BENCH    ] 100 KB: best 170.35 ms, mean 180.13 ms
    (re.compile(r"\[ BENCH\s*\] (?P<what>[^:]+): best (?P<v>[\d.]+) ms"), "markdown parse {what} (best)", "ms"),
    # [ save-latency ] tasks=10000 state.json=5123 KiB best=120ms mean=...
    (re.compile(r"\[ save-latency \] tasks=(?P<what>\d+) .*? best=(?P<v>[\d.]+)ms"), "save {what} tasks (best)", "ms"),
]


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    results = []
    for log in sys.argv[2:]:
        with open(log, encoding="utf-8", errors="replace") as f:
            for line in f:
                for rx, name, unit in PATTERNS:
                    m = rx.search(line)
                    if m:
                        results.append({"name": name.format(what=m["what"].strip()), "unit": unit,
                                        "value": float(m["v"])})
    if not results:
        print("no benchmark lines found — did the suites' output format change?")
        return 1
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    for r in results:
        print(f"{r['name']}: {r['value']} {r['unit']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
