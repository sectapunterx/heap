# Runs the real heap binary with command lines it must refuse, and checks the
# refusal: exit 2 and a message on stderr, before any window or profile is
# opened (PLAT-1, audit 2026-09-30). Invoked by ctest as
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

function(expect_refused needle)
    execute_process(COMMAND "${HEAP_EXE}" ${ARGN}
            RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
    if (NOT rc STREQUAL "2")
        message(FATAL_ERROR "heap ${ARGN}: expected exit 2, got '${rc}'\nstderr: ${err}")
    endif ()
    string(FIND "${err}" "${needle}" at)
    if (at LESS 0)
        message(FATAL_ERROR "heap ${ARGN}: stderr lacks '${needle}'\nstderr: ${err}")
    endif ()
endfunction()

# The binary starts at all; without this a missing DLL would look like a pass.
expect_ok(--version)

expect_refused("unexpected argument 'positional_arg'" positional_arg)
expect_refused("unexpected argument 'board'" board)
expect_refused("unexpected argument 'extra'" --view board extra)
expect_refused("unexpected argument 'C:/tmp/dd'" --data-dir "${WORK_DIR}" C:/tmp/dd)
# --minimized (APP-154, the login entry) is a known flag: the refusal is about
# the stray argument, not "Unknown option 'minimized'".
expect_refused("unexpected argument 'extra'" --minimized extra)
# REL-2: unknown options were already refused.
expect_refused("Unknown option 'no-such-flag'" --no-such-flag)

file(GLOB leftovers "${WORK_DIR}/*")
if (leftovers)
    message(FATAL_ERROR "a refused command line still wrote: ${leftovers}")
endif ()
message("cli args: OK")
