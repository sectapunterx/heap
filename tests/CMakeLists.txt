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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/text/TaskTextUtils.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
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
