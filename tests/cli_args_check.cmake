# Runs the real heap binary with command lines it must refuse, and checks the
# refusal: exit 1 (usage) and a message on stderr, before any window or profile
# is opened (PLAT-1, audit 2026-09-30). Then the command-line verbs (APP-173)
# against a scratch data dir: help, an empty list, add, list --json, now.
# Invoked by ctest as
#   cmake -DHEAP_EXE=<path> -DWORK_DIR=<dir> -P cli_args_check.cmake
#
# HEAP_DATA_DIR points at a scratch folder, so a build that regressed and
# started the GUI touches nothing real; the timeout then fails the check.

if (NOT EXISTS "${HEAP_EXE}")
    # The sanitizer job builds the test executables only, not the app.
    message("SKIPPED: ${HEAP_EXE} not built")
    return()
endif ()

file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")
set(ENV{HEAP_DATA_DIR} "${WORK_DIR}")
set(ENV{QT_QPA_PLATFORM} "offscreen")

function(expect_ok)
    execute_process(COMMAND "${HEAP_EXE}" ${ARGN}
            RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
    if (NOT rc STREQUAL "0")
        message(FATAL_ERROR "heap ${ARGN}: expected exit 0, got '${rc}'\nstdout: ${out}\nstderr: ${err}")
    endif ()
endfunction()

# Runs heap, expects exit `code` and `needle` in stdout.
function(expect_out code needle)
    execute_process(COMMAND "${HEAP_EXE}" ${ARGN}
            RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
    if (NOT rc STREQUAL "${code}")
        message(FATAL_ERROR "heap ${ARGN}: expected exit ${code}, got '${rc}'\nstdout: ${out}\nstderr: ${err}")
    endif ()
    string(FIND "${out}" "${needle}" at)
    if (at LESS 0)
        message(FATAL_ERROR "heap ${ARGN}: stdout lacks '${needle}'\nstdout: ${out}\nstderr: ${err}")
    endif ()
endfunction()

function(expect_refused needle)
    execute_process(COMMAND "${HEAP_EXE}" ${ARGN}
            RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
    if (NOT rc STREQUAL "1")
        message(FATAL_ERROR "heap ${ARGN}: expected exit 1, got '${rc}'\nstderr: ${err}")
    endif ()
    string(FIND "${err}" "${needle}" at)
    if (at LESS 0)
        message(FATAL_ERROR "heap ${ARGN}: stderr lacks '${needle}'\nstderr: ${err}")
    endif ()
endfunction()

# The binary starts at all; without this a missing DLL would look like a pass.
expect_ok(--version)
# APP-161: the opt-in timing flag is a known option.
expect_ok(--perf-log --version)

expect_refused("unexpected argument 'positional_arg'" positional_arg)
expect_refused("unexpected argument 'board'" board)
expect_refused("unexpected argument 'extra'" --view board extra)
expect_refused("unexpected argument 'C:/tmp/dd'" --data-dir "${WORK_DIR}" C:/tmp/dd)
# APP-171: --capture is an option heap knows (bound to a desktop shortcut).
expect_refused("unexpected argument 'extra'" --capture extra)
# --minimized (APP-154, the login entry) is a known flag: the refusal is about
# the stray argument, not "Unknown option 'minimized'".
expect_refused("unexpected argument 'extra'" --minimized extra)
# APP-155: a notification click's heap://notify URI is the one positional
# argument heap takes; any other heap:// is still refused...
expect_refused("unexpected argument 'heap://other'" heap://other)
expect_refused("unexpected argument 'heap://notify?id=a%3Ab'" "heap://notify?id=a%3Ab" extra)
# ...and a click naming a folder with no heap running there exits quietly,
# without starting one or writing anything into it.
expect_ok("heap://notify?id=deadline%3AT-1&action=open&dir=${WORK_DIR}/clicked")
if (EXISTS "${WORK_DIR}/clicked")
    message(FATAL_ERROR "a notification click created the folder its URI named")
endif ()
# REL-2: unknown options were already refused.
expect_refused("Unknown option 'no-such-flag'" --no-such-flag)
# A verb's own mistakes are usage errors too, and touch nothing.
expect_refused("add needs the text" add)
expect_refused("Unknown option 'stauts'" list --stauts done)
expect_refused("--status is not an option of 'now'" now --status done)

file(GLOB leftovers "${WORK_DIR}/*")
if (leftovers)
    message(FATAL_ERROR "a refused command line still wrote: ${leftovers}")
endif ()

# ── The verbs (APP-173), on an empty data dir ──
expect_out(0 "heap <command> [options]" --help)
expect_out(0 "now [--json]" help)
expect_out(0 "[]" list --data-dir "${WORK_DIR}" --json)
# Nothing current: silent and successful, as a shell prompt needs.
execute_process(COMMAND "${HEAP_EXE}" now --data-dir "${WORK_DIR}"
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
if (NOT rc STREQUAL "0" OR NOT out STREQUAL "")
    message(FATAL_ERROR "heap now with nothing current: rc '${rc}', stdout '${out}', stderr '${err}'")
endif ()
expect_out(0 "Added TASK-1: write the cli check" add "write the cli check p1" --data-dir "${WORK_DIR}")
expect_out(0 "\"priority\": \"P1\"" list --data-dir "${WORK_DIR}" --json)
expect_out(0 "Done TASK-1" done TASK-1 --data-dir "${WORK_DIR}")
expect_out(2 "" done NOPE-1 --data-dir "${WORK_DIR}")
message("cli args: OK")
