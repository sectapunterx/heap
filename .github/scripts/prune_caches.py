#!/usr/bin/env python3
"""Prunes the repository's GitHub Actions cache.

    prune_caches.py <owner/repo> [--dry-run]   (GH_TOKEN with actions: write)

The cache holds 10 GB; past that GitHub evicts the least recently used entries,
master's and feature's among them, and the next build starts cold. Most saves
add an entry under a new key (a run id, a timestamp, a file hash), so copies
pile up. Kept: on master and feature, the newest entry of each kind. Deleted:
older copies there, anything under a tag (no later run can read it), and
entries of other refs (PRs, branches) not used for two days.
"""
import json
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

LONG_LIVED = {"refs/heads/master", "refs/heads/feature"}
STALE_AFTER = timedelta(days=2)

# What makes two keys copies of one cache: the part a save varies.
VARYING = [
    re.compile(r"-\d{4}-\d\d-\d\dT[\d:.]+Z$"),  # hendrikmuhs/ccache-action timestamp
    re.compile(r"-[0-9a-f]{40}$"),  # commit sha
    re.compile(r"-\d{6,}$"),  # run id
    re.compile(r"(?<=-files:)[0-9a-f]+.*$"),  # setup-msys2 package-list hash
]


def kind(key):
    for pattern in VARYING:
        key = pattern.sub("", key)
    return key


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def main():
    repo = sys.argv[1]
    dry_run = "--dry-run" in sys.argv[2:]
    listing = gh("api", "--paginate", "--jq", ".actions_caches[]", f"repos/{repo}/actions/caches?per_page=100")
    caches = [json.loads(line) for line in listing.splitlines() if line.strip()]
    now = datetime.now(timezone.utc)
    newest = {}
    doomed = []
    for c in sorted(caches, key=lambda c: c["last_accessed_at"], reverse=True):
        ref = c["ref"]
        accessed = datetime.fromisoformat(c["last_accessed_at"].replace("Z", "+00:00"))
        if ref in LONG_LIVED:
            group = (ref, kind(c["key"]))
            if group in newest:
                doomed.append((c, "older copy"))
            else:
                newest[group] = c
        elif ref.startswith("refs/tags/"):
            doomed.append((c, "tag"))
        elif now - accessed > STALE_AFTER:
            doomed.append((c, "unused for 2 days"))

    freed = 0
    for c, why in doomed:
        if dry_run:
            print(f"would delete ({why}) {c['ref']} {c['key']} {c['size_in_bytes'] // 2**20} MB")
            freed += c["size_in_bytes"]
            continue
        try:
            gh("api", "-X", "DELETE", f"repos/{repo}/actions/caches/{c['id']}")
        except subprocess.CalledProcessError as e:
            # Evicted meanwhile, or another run's prune got there first.
            print(f"could not delete {c['key']}: {e.stderr.strip()}")
            continue
        freed += c["size_in_bytes"]
        print(f"deleted ({why}) {c['ref']} {c['key']} {c['size_in_bytes'] // 2**20} MB")
    left = sum(c["size_in_bytes"] for c in caches) - freed
    print(f"freed {freed / 2**30:.2f} GB; {left / 2**30:.2f} GB left in {len(caches) - len(doomed)} entries")


if __name__ == "__main__":
    main()
