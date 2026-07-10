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

# macOS: suites that compile GlobalHotkey.cpp also compile GlobalHotkey_mac.mm
# (added per-suite below), which uses Carbon. Link it for every test target here
# (directory-scoped) and make sure Objective-C++ is available. (HEAP-68)
if(APPLE)
    enable_language(OBJCXX)
    link_libraries("-framework Carbon")
endif()

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

# Recurrence engine (HEAP-77) — header-only, so only the test TU compiles.
add_executable(heap_recur_tests test_recur.cpp)
target_include_directories(heap_recur_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_recur_tests PRIVATE Qt6::Core GTest::gtest GTest::gtest_main)
add_test(NAME heap_recur_tests COMMAND heap_recur_tests)

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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Logger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notes/NoteLinks.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_SELECTION_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (APPLE)
    list(APPEND HEAP_SELECTION_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
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
        Qt6::Network
        Qt6::NetworkAuth
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Logger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notes/NoteLinks.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_NOTES_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (APPLE)
    list(APPEND HEAP_NOTES_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
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
        Qt6::Network
        Qt6::NetworkAuth
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
if (APPLE)
    list(APPEND HEAP_PLATFORM_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Logger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notes/NoteLinks.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_PERSISTENCE_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (APPLE)
    list(APPEND HEAP_PERSISTENCE_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
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
        Qt6::Network
        Qt6::NetworkAuth
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Logger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notes/NoteLinks.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_EXPORT_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (APPLE)
    list(APPEND HEAP_EXPORT_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
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
        Qt6::Network
        Qt6::NetworkAuth
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Logger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notes/NoteLinks.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_PROFILE_IO_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (APPLE)
    list(APPEND HEAP_PROFILE_IO_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
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
        Qt6::Network
        Qt6::NetworkAuth
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Logger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notes/NoteLinks.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_ONBOARDING_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (APPLE)
    list(APPEND HEAP_ONBOARDING_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
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
        Qt6::Network
        Qt6::NetworkAuth
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Logger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notes/NoteLinks.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_UNDO_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (APPLE)
    list(APPEND HEAP_UNDO_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
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
        Qt6::Network
        Qt6::NetworkAuth
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Logger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notes/NoteLinks.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_VIEW_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (APPLE)
    list(APPEND HEAP_VIEW_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
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
        Qt6::Network
        Qt6::NetworkAuth
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
#
# heap_coreplugin is force-linked WHOLE_ARCHIVE: it is a static library whose
# only job is a translation unit with the module's type-registration static
# initializer. Nothing in the test references a symbol from it, so a normal link
# lets the linker drop the whole archive (works on Windows by luck, stripped on
# Linux → "SideRail is not a type" at runtime). WHOLE_ARCHIVE keeps the init.
# heap_core reaches this target twice: once explicitly here (WHOLE_ARCHIVE, so
# the backing library's file-based QML component registrations are not stripped)
# and once more as a DEFAULT-feature interface dependency that heap_coreplugin
# propagates. CMake refuses the same library linked with two different link
# features ("heap_core ... has already occurred with the feature
# 'WHOLE_ARCHIVE'"), which fails configure on stock Ubuntu (apt Qt 6.4 /
# CMake 3.28). Pin WHOLE_ARCHIVE for every occurrence of heap_core in this
# target — including the propagated one — so both agree. (CMake >= 3.24)
set_property(TARGET heap_qml_tests PROPERTY LINK_LIBRARY_OVERRIDE_heap_core WHOLE_ARCHIVE)
target_link_libraries(heap_qml_tests PRIVATE
        heap_core
        "$<LINK_LIBRARY:WHOLE_ARCHIVE,heap_coreplugin>"
        Qt6::QuickTest
)

add_test(NAME heap_qml_tests
        COMMAND heap_qml_tests -input ${CMAKE_CURRENT_SOURCE_DIR}/qml)
set_tests_properties(heap_qml_tests PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# HEAP-71: the static TodoCpp module's file-based components (SideRail,
# ArchiveView, …) failed to resolve in the Quick Test binary on Linux under
# Ubuntu's apt Qt 6.4.2 (a qmlcachegen/static-module bug — "ArchiveView is not a
# type"). CI now provisions Qt 6.8 via install-qt-action (matching local), where
# they resolve, so Linux execution is re-enabled.

# ─── Integrations (tracker-sync StatusMap) tests ───
# Pure status/priority translation for the post-release tracker sync. No QObject,
# no network — Qt6::Core only.
add_executable(heap_integrations_tests
        test_integrations.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
)
target_include_directories(heap_integrations_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_integrations_tests PRIVATE
        Qt6::Core
        GTest::gtest
        GTest::gtest_main
)
add_test(NAME heap_integrations_tests COMMAND heap_integrations_tests)

# ─── Update (GitHub-Releases version compare) tests ───
# Covers heap::update::isNewerVersion. Updater.cpp carries a QObject (the QNAM
# client) so AUTOMOC + Qt6::Network are needed, but the tests exercise only the
# pure comparison — no network I/O.
add_executable(heap_update_tests
        test_update.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.h
)
set_target_properties(heap_update_tests PROPERTIES AUTOMOC ON)
target_include_directories(heap_update_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_update_tests PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::NetworkAuth
        GTest::gtest
        GTest::gtest_main
)
add_test(NAME heap_update_tests COMMAND heap_update_tests)

# ─── GitHub provider (issue parsing + push-state mapping) tests ───
# Pure helpers of the GitHub tracker sync (HEAP-74). GithubProvider.cpp carries
# the QNAM QObject so AUTOMOC + Qt6::Network are needed; the tests hit only the
# pure functions with canned JSON — no network I/O.
add_executable(heap_github_tests
        test_github.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
)
set_target_properties(heap_github_tests PROPERTIES AUTOMOC ON)
target_include_directories(heap_github_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_github_tests PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::NetworkAuth
        GTest::gtest
        GTest::gtest_main
)
add_test(NAME heap_github_tests COMMAND heap_github_tests)

# Jira provider parse/transition helpers — pure functions with canned JSON.
add_executable(heap_jira_tests
        test_jira.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
)
set_target_properties(heap_jira_tests PROPERTIES AUTOMOC ON)
target_include_directories(heap_jira_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_jira_tests PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::NetworkAuth
        GTest::gtest
        GTest::gtest_main
)
add_test(NAME heap_jira_tests COMMAND heap_jira_tests)

# GitLab provider parse/state helpers — pure functions with canned JSON.
add_executable(heap_gitlab_tests
        test_gitlab.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
)
set_target_properties(heap_gitlab_tests PROPERTIES AUTOMOC ON)
target_include_directories(heap_gitlab_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_gitlab_tests PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::NetworkAuth
        GTest::gtest
        GTest::gtest_main
)
add_test(NAME heap_gitlab_tests COMMAND heap_gitlab_tests)

# ─── Generic REST provider engine + registry + Trello + SecretStore tests ───
# Covers the descriptor-driven FieldMap parser, the provider registry's field
# mappings, the bespoke Trello parsers and the SecretStore cache. SecretStore is
# built here without HEAP_USE_KEYCHAIN so it uses its file fallback (no keychain
# dependency in the test). Providers carry QNAM QObjects → AUTOMOC + Network.
add_executable(heap_rest_providers_tests
        test_rest_providers.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
)
set_target_properties(heap_rest_providers_tests PROPERTIES AUTOMOC ON)
target_include_directories(heap_rest_providers_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_rest_providers_tests PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::NetworkAuth
        GTest::gtest
        GTest::gtest_main
)
add_test(NAME heap_rest_providers_tests COMMAND heap_rest_providers_tests)

# ─── Sync (BYOS serializer) tests ───
# Cover heap::sync::SyncSerializer — Profile/CalEvent ↔ git-friendly JSON with
# stable (id-sorted) ordering and idempotent round-trips. Pure data code; needs
# Qt6::Gui for QColor and Qt6::Qml only for the qqmlregistration.h header pulled
# in transitively by Models.h.
add_executable(heap_sync_tests
        test_sync_serializer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncSerializer.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncSerializer.h
)

target_include_directories(heap_sync_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_sync_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        GTest::gtest
        GTest::gtest_main
)

add_test(NAME heap_sync_tests COMMAND heap_sync_tests)

# ─── Query (Notes query-language parser) tests ───
# Pure tokenizer/parser for the embedded Notes query language. Qt6::Core only.
add_executable(heap_query_tests
        test_query_parser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/query/QueryParser.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/query/QueryParser.h
)
target_include_directories(heap_query_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_query_tests PRIVATE
        Qt6::Core
        GTest::gtest
        GTest::gtest_main
)
add_test(NAME heap_query_tests COMMAND heap_query_tests)

# ─── Sync (JsonMerger 3-way merge) tests ───
# Pure structural merge for the non-git BYOS backends. Qt6::Core only.
add_executable(heap_json_merger_tests
        test_json_merger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/JsonMerger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/JsonMerger.h
)
target_include_directories(heap_json_merger_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_json_merger_tests PRIVATE
        Qt6::Core
        GTest::gtest
        GTest::gtest_main
)
add_test(NAME heap_json_merger_tests COMMAND heap_json_merger_tests)

# ─── Models (QAbstractListModel subclasses) tests ───
# Direct role-mapping / upsert / mutation-guard / git-info / cycleState /
# todoCount coverage. Pure: no AppController, no QApplication.
add_executable(heap_models_tests
        test_models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Models.h
)
set_target_properties(heap_models_tests PROPERTIES AUTOMOC ON)
target_include_directories(heap_models_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(heap_models_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Test
        GTest::gtest
        GTest::gtest_main
)
add_test(NAME heap_models_tests COMMAND heap_models_tests)

# ─── AppController (shortcuts / scheduling / date + wrapper logic) tests ───
# Same headless boot + source set as the other AppController suites (offscreen
# QPA + test-mode paths); links GlobalHotkey since AppController references it.
set(HEAP_APPCTRL_SOURCES
        test_appcontroller.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/AppController.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/Logger.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/update/Updater.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/StatusMap.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GithubProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/JiraProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/GitlabProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/RestIssueProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderRegistry.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/ProviderDescriptor.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/TrelloProvider.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/SecretStore.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/OAuthManager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/integrations/IntegrationProvider.h
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
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/notes/NoteLinks.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/git/GitWatcher.h
)
if (WIN32)
    list(APPEND HEAP_APPCTRL_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_win.cpp
    )
endif ()
if (APPLE)
    list(APPEND HEAP_APPCTRL_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/GlobalHotkey_mac.mm
    )
endif ()
if (UNIX AND NOT APPLE)
    list(APPEND HEAP_APPCTRL_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/../src/notify/NotificationCenter_linux.cpp
    )
endif ()

add_executable(heap_appcontroller_tests ${HEAP_APPCTRL_SOURCES})
set_target_properties(heap_appcontroller_tests PROPERTIES AUTOMOC ON)

target_include_directories(heap_appcontroller_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

target_link_libraries(heap_appcontroller_tests PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Network
        Qt6::NetworkAuth
        Qt6::Widgets
        Qt6::Qml
        Qt6::Test
        GTest::gtest
)
if (UNIX AND NOT APPLE)
    find_package(Qt6 QUIET COMPONENTS DBus)
    if (TARGET Qt6::DBus)
        target_link_libraries(heap_appcontroller_tests PRIVATE Qt6::DBus)
    endif ()
endif ()

add_test(NAME heap_appcontroller_tests COMMAND heap_appcontroller_tests)

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
