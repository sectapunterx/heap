#!/usr/bin/env bash
# Runs ctest, and gives the suites that failed exactly one more try.
#
#   ctest_with_retry.sh <test-dir> [ctest args...]
#
# A suite that fails and then passes is flaky, not green: the job goes on, but
# it is named in a warning annotation and in the run summary, and the JUnit
# report written by the first run (pass --output-junit) still records the
# failure. That keeps a flake visible without anyone re-running the job by
# hand. A suite that fails twice fails the job.
set -uo pipefail

dir=$1
shift

if ctest --test-dir "$dir" "$@"; then
  exit 0
fi

failed_log="$dir/Testing/Temporary/LastTestsFailed.log"
failed=$(cut -d: -f2 "$failed_log" 2>/dev/null | paste -sd' ' -)
echo "::group::Re-running the failed suites once: $failed"
# Same arguments minus --output-junit, so the first run's report is kept.
retry_args=()
skip_next=0
for arg in "$@"; do
  if [[ $skip_next == 1 ]]; then skip_next=0; continue; fi
  case "$arg" in
    --output-junit) skip_next=1 ;;
    --output-junit=*) ;;
    *) retry_args+=("$arg") ;;
  esac
done
ctest --test-dir "$dir" --rerun-failed --output-on-failure "${retry_args[@]}"
status=$?
echo "::endgroup::"

if [[ $status == 0 ]]; then
  echo "::warning::flaky: failed, then passed on retry: $failed"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    # shellcheck disable=SC2016 # the backticks are Markdown, not a substitution
    printf '### Flaky tests\nFailed once, passed on retry: `%s`\n' "$failed" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

# heap_qml_tests also writes its results to a file (see tests/CMakeLists.txt),
# since its stdout is lost on Windows; name the failing cases from there.
qml_results="$dir/heap_qml_tests.txt"
if [[ -f $qml_results ]] && grep -q '^FAIL!' "$qml_results"; then
  echo "::group::heap_qml_tests failures"
  grep -A4 '^FAIL!' "$qml_results"
  echo "::endgroup::"
fi
exit "$status"
