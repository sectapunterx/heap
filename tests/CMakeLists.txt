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
find_package(Qt6 6.2 REQUIRED COMPONENTS Core Test)

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
