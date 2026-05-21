#!/usr/bin/env bash
# Print files changed between the PR base (or HEAD~1 on push) and HEAD,
# filtered by a regex of file extensions.
#
# Usage:
#   .github/scripts/changed_files.sh 'cpp|h|hpp'
#   BASE_SHA=origin/master .github/scripts/changed_files.sh 'qml'
#
# Designed to be safe under `set -e`: empty result exits 0, no output.
set -euo pipefail

exts="${1:?usage: changed_files.sh <ext-regex> (e.g. 'cpp|h|hpp')}"

# Resolve the base commit. In a PR workflow GITHUB_BASE_REF points to the
# target branch; on push we fall back to HEAD~1 so a "fresh commit on master"
# still has a meaningful diff.
if [[ -n "${BASE_SHA:-}" ]]; then
    base="$BASE_SHA"
elif [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    # tj-actions/checkout fetches the base ref under the same name.
    base="origin/${GITHUB_BASE_REF}"
else
    base="$(git rev-parse HEAD~1 2>/dev/null || echo HEAD)"
fi

git diff --name-only --diff-filter=ACMRT "$base" HEAD \
    | grep -E "\.($exts)$" || true
