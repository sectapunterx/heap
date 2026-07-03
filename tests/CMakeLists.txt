if(NOT CMAKE_PROJECT_NAME OR CMAKE_PROJECT_NAME STREQUAL "heap_tests")
    cmake_minimum_required(VERSION 3.21)
    project(heap_tests LANGUAGES CXX)
    set(CMAKE_CXX_STANDARD 20)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_CXX_EXTENSIONS OFF)
    enable_testing()
endif()

# Qt6::Test (provides QSignalSpy) is needed by heap_notify_tests even when
# this file is included as a subdirectory of the main project.
find_package(Qt6 6.2 REQUIRED COMPONENTS Core Gui Widgets Qml Test)

include(FetchContent)

FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.15.2
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(heap_chrono_tests
    test_chrono_parser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoTokenizer.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_en.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_ru.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoParser.cpp
)

target_include_directories(heap_chrono_tests PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_chrono_tests PRIVATE
    Qt6::Core
    GTest::gtest
    GTest::gtest_main
)

add_test(NAME heap_chrono_tests COMMAND heap_chrono_tests)

add_executable(heap_git_tests
    test_branch_task_matcher.cpp
    test_git_watcher_parse.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/BranchTaskMatcher.cpp
)

target_include_directories(heap_git_tests PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_git_tests PRIVATE
    Qt6::Core
    GTest::gtest
    GTest::gtest_main
)

add_test(NAME heap_git_tests COMMAND heap_git_tests)

add_executable(heap_text_tests
    test_task_text_utils.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
)

target_include_directories(heap_text_tests PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_text_tests PRIVATE
    Qt6::Core
    GTest::gtest
    GTest::gtest_main
)

add_test(NAME heap_text_tests COMMAND heap_text_tests)

# ─── Notification module tests ───
# Cover the routing-id helpers, the data structs, and the abstract
# NotificationCenter signal contract via an in-test mock backend. No real
# OS backend is linked, so the tests run headless on any CI runner.
add_executable(heap_notify_tests
    test_notification.cpp
    # AUTOMOC needs the header explicitly listed so the moc artifacts for
    # NotificationCenter (Q_OBJECT in the abstract base) are emitted into
    # this exe. Otherwise the linker complains about the missing vtable.
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.h
)
# Per-target AUTOMOC — the parent project sets this globally, but a stand-
# alone build of just `tests/` needs the property to be explicit.
set_target_properties(heap_notify_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_notify_tests PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_notify_tests PRIVATE
    Qt6::Core
    Qt6::Test
    GTest::gtest
    GTest::gtest_main
)

add_test(NAME heap_notify_tests COMMAND heap_notify_tests)

# ─── Selection (AppController multi-select) tests ───
# Cover the multi-select state machine and bulk ops on AppController:
# toggle/set/clear/selectAll, bulk delete with undo restoration, bulk
# move/archive, and clearSelection on view/profile change.
#
# Links the same sources as the main `heap` target *minus* QML registration
# (no Qt6::Quick) — AppController's own implementation only needs Core/Gui/
# Widgets/Qml + Test. Uses offscreen QGuiApplication + AppDataLocation test
# mode so it runs headless and never touches the user's real state file.
set(HEAP_SELECTION_SOURCES
        test_selection.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/SampleData.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoTokenizer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_en.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_ru.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoParser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/BranchTaskMatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_tray.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_SELECTION_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (UNIX AND NOT APPLE)
    list(APPEND HEAP_SELECTION_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_linux.cpp
    )
endif ()

add_executable(heap_selection_tests ${HEAP_SELECTION_SOURCES})
set_target_properties(heap_selection_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_selection_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_selection_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Qml
        Qt6::Test
        GTest::gtest
        GTest::gtest_main
)
if (UNIX AND NOT APPLE)
    find_package(Qt6 QUIET COMPONENTS DBus)
    if (TARGET Qt6::DBus)
        target_link_libraries(heap_selection_tests PRIVATE Qt6::DBus)
    endif ()
endif ()

add_test(NAME heap_selection_tests COMMAND heap_selection_tests)

# ─── Notes (Quick-capture appendNoteEntry) tests ───
# Cover AppController::appendNoteEntry — the C++ side of the Ctrl+Shift+N
# popup: empty-input guard, first-entry vs subsequent-entry formatting,
# trimming, and the notesStateChanged signal contract. Boots the same
# offscreen QApplication + QStandardPaths test mode used by the selection
# suite so it runs headless and never touches the real state.json.
set(HEAP_NOTES_SOURCES
        test_notes.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/SampleData.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoTokenizer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_en.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_ru.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoParser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/BranchTaskMatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_tray.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_NOTES_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (UNIX AND NOT APPLE)
    list(APPEND HEAP_NOTES_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_linux.cpp
    )
endif ()

add_executable(heap_notes_tests ${HEAP_NOTES_SOURCES})
set_target_properties(heap_notes_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_notes_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_notes_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Qml
        Qt6::Test
        GTest::gtest
)
if (UNIX AND NOT APPLE)
    find_package(Qt6 QUIET COMPONENTS DBus)
    if (TARGET Qt6::DBus)
        target_link_libraries(heap_notes_tests PRIVATE Qt6::DBus)
    endif ()
endif ()

add_test(NAME heap_notes_tests COMMAND heap_notes_tests)

# ─── Platform (global hotkey) tests ───
# Cover heap::platform::decodeSequence — the portable QKeySequence → (key,mods)
# parser the Windows RegisterHotKey backend feeds off. On Windows the native
# backend is linked too (create() references it); elsewhere the .cpp compiles
# with the no-op fallback.
set(HEAP_PLATFORM_SOURCES
        test_global_hotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.h
)
if (WIN32)
    list(APPEND HEAP_PLATFORM_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()

add_executable(heap_platform_tests ${HEAP_PLATFORM_SOURCES})
set_target_properties(heap_platform_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_platform_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_platform_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        GTest::gtest
        GTest::gtest_main
)
if (WIN32)
    target_link_libraries(heap_platform_tests PRIVATE user32)
endif ()

add_test(NAME heap_platform_tests COMMAND heap_platform_tests)

# ─── Persistence (corrupt-state recovery) tests ───
# Cover AppController::loadStateOnStart() crash/corruption handling (HEAP-50):
# recover from the newest valid backup, otherwise quarantine the damaged
# state.json instead of letting the demo seed overwrite it. Same headless boot
# (offscreen QPA + AppDataLocation test mode) as the selection / notes suites.
set(HEAP_PERSISTENCE_SOURCES
        test_persistence.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/SampleData.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoTokenizer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_en.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_ru.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoParser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/BranchTaskMatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_tray.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_PERSISTENCE_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (UNIX AND NOT APPLE)
    list(APPEND HEAP_PERSISTENCE_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_linux.cpp
    )
endif ()

add_executable(heap_persistence_tests ${HEAP_PERSISTENCE_SOURCES})
set_target_properties(heap_persistence_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_persistence_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_persistence_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Qml
        Qt6::Test
        GTest::gtest
)
if (UNIX AND NOT APPLE)
    find_package(Qt6 QUIET COMPONENTS DBus)
    if (TARGET Qt6::DBus)
        target_link_libraries(heap_persistence_tests PRIVATE Qt6::DBus)
    endif ()
endif ()

add_test(NAME heap_persistence_tests COMMAND heap_persistence_tests)

# ─── Markdown export tests ───
# Cover AppController::copyActiveProfileMarkdownToClipboard() (HEAP-53): renders
# the active profile to Markdown and puts it on the clipboard. Same headless
# boot (offscreen QPA + AppDataLocation test mode) as the other AppController
# suites; QClipboard works in-process under the offscreen platform.
set(HEAP_EXPORT_SOURCES
        test_export_markdown.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/SampleData.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoTokenizer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_en.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_ru.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoParser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/BranchTaskMatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_tray.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_EXPORT_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (UNIX AND NOT APPLE)
    list(APPEND HEAP_EXPORT_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_linux.cpp
    )
endif ()

add_executable(heap_export_tests ${HEAP_EXPORT_SOURCES})
set_target_properties(heap_export_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_export_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_export_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Qml
        Qt6::Test
        GTest::gtest
)
if (UNIX AND NOT APPLE)
    find_package(Qt6 QUIET COMPONENTS DBus)
    if (TARGET Qt6::DBus)
        target_link_libraries(heap_export_tests PRIVATE Qt6::DBus)
    endif ()
endif ()

add_test(NAME heap_export_tests COMMAND heap_export_tests)

# ─── Profile I/O (export/import events) tests ───
# Cover AppController profile export/import of calendar events (HEAP-54): export
# includes the active profile's events, import restores them re-attributed with
# fresh ids. Same headless boot as the other AppController suites.
set(HEAP_PROFILE_IO_SOURCES
        test_profile_io.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/SampleData.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoTokenizer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_en.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_ru.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoParser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/BranchTaskMatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_tray.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_PROFILE_IO_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (UNIX AND NOT APPLE)
    list(APPEND HEAP_PROFILE_IO_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_linux.cpp
    )
endif ()

add_executable(heap_profile_io_tests ${HEAP_PROFILE_IO_SOURCES})
set_target_properties(heap_profile_io_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_profile_io_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_profile_io_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Qml
        Qt6::Test
        GTest::gtest
)
if (UNIX AND NOT APPLE)
    find_package(Qt6 QUIET COMPONENTS DBus)
    if (TARGET Qt6::DBus)
        target_link_libraries(heap_profile_io_tests PRIVATE Qt6::DBus)
    endif ()
endif ()

add_test(NAME heap_profile_io_tests COMMAND heap_profile_io_tests)

# ─── Onboarding (first-run flags + startFresh) tests ───
# Cover AppController welcomeSeen / demoActive persistence and startFresh()
# (HEAP-51). Same headless boot as the other AppController suites.
set(HEAP_ONBOARDING_SOURCES
        test_onboarding.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/SampleData.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoTokenizer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_en.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_ru.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoParser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/BranchTaskMatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_tray.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_ONBOARDING_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (UNIX AND NOT APPLE)
    list(APPEND HEAP_ONBOARDING_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_linux.cpp
    )
endif ()

add_executable(heap_onboarding_tests ${HEAP_ONBOARDING_SOURCES})
set_target_properties(heap_onboarding_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_onboarding_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_onboarding_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Qml
        Qt6::Test
        GTest::gtest
)
if (UNIX AND NOT APPLE)
    find_package(Qt6 QUIET COMPONENTS DBus)
    if (TARGET Qt6::DBus)
        target_link_libraries(heap_onboarding_tests PRIVATE Qt6::DBus)
    endif ()
endif ()

add_test(NAME heap_onboarding_tests COMMAND heap_onboarding_tests)

# ─── Sample data (seed content) tests ───
# Cover SampleData seed invariants (HEAP-56): events spread across the week and
# the demo content is generic, not the old telecom workload. Uses only the plain
# Task/Person/CalEvent structs, so it links SampleData.cpp alone (Qt6::Gui for
# QColor in people()); no QApplication needed.
add_executable(heap_sampledata_tests
        test_sampledata.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/SampleData.cpp
)
target_include_directories(heap_sampledata_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_sampledata_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Qml   # Models.h includes <qqmlregistration.h>
        GTest::gtest
)
add_test(NAME heap_sampledata_tests COMMAND heap_sampledata_tests)

# ─── Undo (task move / archive) tests ───
# Cover the extended single-level undo (HEAP-59): moveTask and setArchived arm
# undo and undoLastDeletion() restores the prior status / archived flag. Same
# headless boot as the other AppController suites.
set(HEAP_UNDO_SOURCES
        test_undo.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/SampleData.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoTokenizer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_en.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_ru.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoParser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/BranchTaskMatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_tray.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_UNDO_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (UNIX AND NOT APPLE)
    list(APPEND HEAP_UNDO_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_linux.cpp
    )
endif ()

add_executable(heap_undo_tests ${HEAP_UNDO_SOURCES})
set_target_properties(heap_undo_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_undo_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_undo_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Qml
        Qt6::Test
        GTest::gtest
)
if (UNIX AND NOT APPLE)
    find_package(Qt6 QUIET COMPONENTS DBus)
    if (TARGET Qt6::DBus)
        target_link_libraries(heap_undo_tests PRIVATE Qt6::DBus)
    endif ()
endif ()

add_test(NAME heap_undo_tests COMMAND heap_undo_tests)

# ─── View navigation / status-column focus tests ───
# Cover AppController::focusStatusColumn — the sidebar Blocked / Code Review
# entry point (HEAP-69): switches to the board view and records the focused
# status; plus countByStatus which feeds the sidebar badges. Same headless boot
# as the other AppController suites.
set(HEAP_VIEW_SOURCES
        test_view.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/SampleData.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoTokenizer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_en.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoLocale_ru.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/chrono/ChronoParser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/BranchTaskMatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_tray.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_VIEW_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (UNIX AND NOT APPLE)
    list(APPEND HEAP_VIEW_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_linux.cpp
    )
endif ()

add_executable(heap_view_tests ${HEAP_VIEW_SOURCES})
set_target_properties(heap_view_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_view_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_view_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Qml
        Qt6::Test
        GTest::gtest
)
if (UNIX AND NOT APPLE)
    find_package(Qt6 QUIET COMPONENTS DBus)
    if (TARGET Qt6::DBus)
        target_link_libraries(heap_view_tests PRIVATE Qt6::DBus)
    endif ()
endif ()

add_test(NAME heap_view_tests COMMAND heap_view_tests)

# ─── QML (Qt Quick Test) tests ───
# Drive the QML layer directly instead of only the C++ backend. Currently
# covers the mention-commit helper (qml/Mention.js) — caret placement after an
# @person / #ticket insertion (HEAP-65). Runs headless under the offscreen QPA
# platform with the Basic Controls style. tst_*.qml live in tests/qml and are
# discovered via the -input dir handed to the QUICK_TEST_MAIN runner.
find_package(Qt6 REQUIRED COMPONENTS QuickTest Quick QuickControls2)

# qt_add_executable (not plain add_executable) so Qt finalization runs
# qt_import_qml_plugins(): the statically-linked TodoCpp module plugin
# (heap_coreplugin) is imported and its type registrations survive. With a plain
# add_executable the plugin init is stripped on Linux and `import TodoCpp` types
# ("SideRail is not a type") fail to resolve at runtime.
qt_add_executable(heap_qml_tests quick_test_main.cpp)
# AUTOMOC for the Setup QObject in quick_test_main.cpp (has Q_OBJECT).
set_target_properties(heap_qml_tests PROPERTIES AUTOMOC ON)

# QUICK_TEST_MAIN scans this directory for tst_*.qml at runtime. Baking it as a
# compile definition is the canonical wiring (more reliable than -input across
# platforms); the source tree is present in local + CI checkouts.
target_compile_definitions(heap_qml_tests PRIVATE
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")

# Link the app's core library + its QML module plugin so the tests can
# `import TodoCpp` and instantiate real components (SideRail, KanbanBoard,
# FilterBar, …) against a live AppController. heap_core PUBLIC-links Quick etc.
target_link_libraries(heap_qml_tests PRIVATE
        heap_core
        heap_coreplugin
        Qt6::QuickTest
)

add_test(NAME heap_qml_tests
        COMMAND heap_qml_tests -input ${CMAKE_CURRENT_SOURCE_DIR}/qml)
set_tests_properties(heap_qml_tests PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# ─── Aggregate target ───
# Build target that depends on every executable defined in this directory.
# CI builds `heap_all_tests`; adding a new test exe via add_executable() in
# this CMakeLists.txt is enough — no CI workflow edit needed.
#
# Filters BUILDSYSTEM_TARGETS to EXECUTABLE so FetchContent-pulled libraries
# (gtest, gtest_main) defined in their own subdirectory are not picked up
# anyway, but the type guard keeps the rule explicit.
get_property(_heap_dir_targets DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        PROPERTY BUILDSYSTEM_TARGETS)
set(_heap_test_exes "")
foreach (_t IN LISTS _heap_dir_targets)
    get_target_property(_type ${_t} TYPE)
    if (_type STREQUAL "EXECUTABLE")
        list(APPEND _heap_test_exes ${_t})
    endif ()
endforeach ()
add_custom_target(heap_all_tests DEPENDS ${_heap_test_exes})
