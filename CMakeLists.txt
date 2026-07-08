cmake_minimum_required(VERSION 3.21)
project(heap VERSION 0.4.6 LANGUAGES CXX)

# Windows resource compiler (windres on mingw / rc.exe on MSVC). Required so
# design/brand-export/icon/heap-icon.rc is actually compiled into heap.exe —
# without this, CMake silently skips .rc inputs and the PE icon resource is
# missing, leaving Explorer/taskbar with the default Qt icon in release.
if (WIN32)
    enable_language(RC)
endif ()

# Objective-C++ for the Carbon global-hotkey backend (GlobalHotkey_mac.mm). (HEAP-68)
if (APPLE)
    enable_language(OBJCXX)
endif ()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Emit compile_commands.json so clang-tidy / clangd / IDEs work out of the box
# (CI's clang-tidy job depends on this).
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── Optional build modes — toggled by CI ──────────────────────────
option(HEAP_ENABLE_COVERAGE   "Instrument heap for gcov coverage"          OFF)
option(HEAP_ENABLE_SANITIZERS "Build heap with AddressSanitizer + UBSan"   OFF)

if(HEAP_ENABLE_COVERAGE AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    message(STATUS "heap: coverage instrumentation ON")
    add_compile_options(-O0 -g --coverage -fprofile-update=atomic)
    add_link_options(--coverage)
endif()

if(HEAP_ENABLE_SANITIZERS AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    message(STATUS "heap: ASan + UBSan ON")
    add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

find_package(Qt6 6.2 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Widgets Network NetworkAuth)
# DBus is only needed for the Linux native notifications backend.
if(UNIX AND NOT APPLE)
    find_package(Qt6 6.2 REQUIRED COMPONENTS DBus)
endif()
# Qt6Svg is optional — it provides the `qsvg` image-format plugin so QML <Image>
# can render the heap. app icon (BrandLogo itself uses native primitives, so
# the brand still renders without it). Install with:
#   pacman -S mingw-w64-ucrt-x86_64-qt6-svg   (MSYS2 UCRT64)
#   apt install libqt6svg6-dev                (Debian / Ubuntu)
find_package(Qt6 6.2 QUIET OPTIONAL_COMPONENTS Svg)

# QtKeychain stores integration access tokens in the OS keychain (Windows
# Credential Manager / macOS Keychain / libsecret) instead of plaintext state.
# Optional: when absent, SecretStore falls back to a private secrets.json.
#   pacman -S mingw-w64-ucrt-x86_64-qtkeychain   (MSYS2 UCRT64)
#   apt install qtkeychain-qt6-dev               (Debian / Ubuntu)
find_package(Qt6Keychain QUIET)

qt_standard_project_setup(REQUIRES 6.4)

# ── Core library: all app logic + the TodoCpp QML module ──────────
# Extracted from the heap executable so the Qt Quick Test harness (tests/) can
# link the same C++ types + QML module and instantiate real components
# (SideRail, KanbanBoard, FilterBar, …) against a live AppController. The heap
# executable below becomes a thin shell that just loads Main.qml.
qt_add_library(heap_core STATIC
    src/AppController.cpp
    src/Logger.cpp
    src/Models.cpp
    src/SampleData.cpp
    src/CodeHighlighter.cpp
    src/NotesHighlighter.cpp
    src/chrono/ChronoTokenizer.cpp
    src/chrono/ChronoLocale_en.cpp
    src/chrono/ChronoLocale_ru.cpp
    src/chrono/ChronoParser.cpp
    src/git/BranchTaskMatcher.cpp
    src/git/GitWatcher.cpp
    src/text/TaskTextUtils.cpp
    src/query/QueryParser.cpp
    src/notes/NoteLinks.cpp
    src/notify/NotificationCenter.cpp
    src/notify/NotificationCenter_tray.cpp
    src/platform/GlobalHotkey.cpp
    src/integrations/StatusMap.cpp
    src/integrations/GithubProvider.cpp
    src/integrations/JiraProvider.cpp
    src/integrations/GitlabProvider.cpp
    src/integrations/RestIssueProvider.cpp
    src/integrations/ProviderRegistry.cpp
    src/integrations/TrelloProvider.cpp
    src/integrations/SecretStore.cpp
    src/integrations/OAuthManager.cpp
    src/sync/SyncSerializer.cpp
    src/sync/JsonMerger.cpp
    src/update/Updater.cpp
    $<$<PLATFORM_ID:Linux>:${CMAKE_SOURCE_DIR}/src/notify/NotificationCenter_linux.cpp>
        $<$<PLATFORM_ID:Windows>:${CMAKE_SOURCE_DIR}/src/platform/GlobalHotkey_win.cpp>
        $<$<PLATFORM_ID:Darwin>:${CMAKE_SOURCE_DIR}/src/platform/GlobalHotkey_mac.mm>
        $<$<PLATFORM_ID:Darwin>:${CMAKE_SOURCE_DIR}/src/platform/MacWindow.mm>
)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/Brand.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/I18n.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# URI stays "TodoCpp" so existing `import TodoCpp` statements throughout qml/
# don't have to be touched. The user-facing app name is heap.
qt_add_qml_module(heap_core
    URI TodoCpp
    VERSION 1.0
    RESOURCE_PREFIX "/qt/qml"
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/I18n.qml
        qml/TopBar.qml
        qml/SideRail.qml
        qml/FilterBar.qml
        qml/KanbanBoard.qml
        qml/TaskCard.qml
        qml/SelectionBar.qml
        qml/ArchiveView.qml
        qml/TimelineView.qml
        qml/WeekView.qml
        qml/MonthView.qml
        qml/DocsView.qml
        qml/DocsEditor.qml
        qml/MiniWeek.qml
        qml/DayCalendar.qml
        qml/DatePickerPopup.qml
        qml/PeopleList.qml
        qml/TaskEditor.qml
        qml/EventEditor.qml
        qml/PersonEditor.qml
        qml/TweaksPanel.qml
        qml/Toast.qml
        qml/PillButton.qml
        qml/ProfileEditor.qml
        qml/CommandPalette.qml
        qml/HotkeysPanel.qml
        qml/NotesView.qml
        qml/SettingsView.qml
        qml/HelpContent.qml
        qml/ThinScrollBar.qml
        qml/Brand.qml
        qml/BrandLogo.qml
        qml/SplashScreen.qml
        qml/QuickCapturePopup.qml
        qml/QuickCaptureNotesPopup.qml
        qml/MentionAutocomplete.qml
        qml/WelcomePopup.qml
        qml/Mention.js
    SOURCES
        src/AppController.h
        src/Models.h
        src/SampleData.h
        src/CodeHighlighter.h
        src/NotesHighlighter.h
        src/chrono/ChronoTypes.h
        src/chrono/ChronoTokenizer.h
        src/chrono/ChronoLocale.h
        src/chrono/ChronoParser.h
        src/git/BranchTaskMatcher.h
        src/git/GitTypes.h
        src/git/GitWatcher.h
        src/text/TaskTextUtils.h
        src/query/QueryParser.h
        src/notes/NoteLinks.h
        src/notify/NotificationCenter.h
        src/platform/GlobalHotkey.h
        src/integrations/IntegrationTypes.h
        src/integrations/StatusMap.h
        src/integrations/GithubProvider.h
        src/integrations/JiraProvider.h
        src/integrations/GitlabProvider.h
        src/integrations/IntegrationProvider.h
        src/integrations/ProviderDescriptor.h
        src/integrations/RestIssueProvider.h
        src/integrations/ProviderRegistry.h
        src/integrations/TrelloProvider.h
        src/integrations/SecretStore.h
        src/integrations/OAuthManager.h
        src/sync/SyncSerializer.h
        src/sync/JsonMerger.h
        src/update/Updater.h
)

target_include_directories(heap_core PUBLIC src)
target_link_libraries(heap_core PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::NetworkAuth
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
)
if(UNIX AND NOT APPLE)
    target_link_libraries(heap_core PUBLIC Qt6::DBus)
endif()
# Carbon backs the macOS global-hotkey (RegisterEventHotKey) in GlobalHotkey_mac.mm;
# AppKit backs the unified title bar (NSWindow restyle) in MacWindow.mm.
if(APPLE)
    target_link_libraries(heap_core PUBLIC "-framework Carbon" "-framework AppKit")
endif()

# Compile-time flag that AppController exposes as a CONSTANT Q_PROPERTY so QML
# can adapt the Settings UI: unimplemented sections are shown disabled in
# Release, and the "show unimplemented" toggle is added in Debug only.
target_compile_definitions(heap_core PRIVATE
    $<$<CONFIG:Debug>:HEAP_DEBUG_BUILD=1>
    $<$<CONFIG:RelWithDebInfo>:HEAP_DEBUG_BUILD=1>
)
# Single source of truth for the app version: the project() VERSION above.
# PUBLIC so the thin `heap` executable (src/main.cpp) inherits it for
# setApplicationVersion; AppController exposes it to QML as `appVersion`.
target_compile_definitions(heap_core PUBLIC HEAP_VERSION="${PROJECT_VERSION}")
if (TARGET Qt6::Svg)
    target_link_libraries(heap_core PUBLIC Qt6::Svg)
    target_compile_definitions(heap_core PRIVATE HEAP_HAS_SVG=1)
endif()

# QtKeychain (imported target `qt6keychain`) backs SecretStore's OS-keychain
# path; when it isn't found, SecretStore compiles the secrets.json fallback.
if (TARGET qt6keychain)
    target_link_libraries(heap_core PUBLIC qt6keychain)
    target_compile_definitions(heap_core PRIVATE HEAP_USE_KEYCHAIN=1)
    message(STATUS "heap: integration tokens stored in the OS keychain (QtKeychain)")
else()
    message(STATUS "heap: QtKeychain not found — integration tokens use the secrets.json fallback")
endif()

# ── Application executable — thin shell that loads Main.qml from heap_core ──
# WIN32 → GUI subsystem on Windows (no console); MACOSX_BUNDLE → a .app on macOS
# so windeployqt/macdeployqt and `install(... BUNDLE ...)` have a bundle to
# operate on. Each keyword applies only to its own platform. (HEAP-28)
qt_add_executable(heap WIN32 MACOSX_BUNDLE
    src/main.cpp
    $<$<PLATFORM_ID:Windows>:${CMAKE_SOURCE_DIR}/design/brand-export/icon/heap-icon.rc>
)
# Link the QML module plugin too: for a statically-linked qml module the plugin
# carries the type-registration + qmlcache resource init. Linking only the
# backing library lets the linker drop those symbols, so `import TodoCpp` (and
# Main.qml) fail to load at runtime. Linking the plugin force-references them.
target_link_libraries(heap PRIVATE heap_core heap_coreplugin)

# ── Brand assets (heap. logo + app icon, exported by design/brand-export) ──
qt_add_resources(heap "brand"
    PREFIX "/brand"
    BASE "design/brand-export"
    FILES
        design/brand-export/logo/heap-mark.svg
        design/brand-export/logo/heap-mark-light.svg
        design/brand-export/logo/heap-mark-mono.svg
        design/brand-export/logo/heap-lockup.svg
        design/brand-export/logo/heap-lockup-light.svg
        design/brand-export/logo/heap-wordmark.svg
        design/brand-export/logo/heap-wordmark-light.svg
        design/brand-export/icon/heap-icon.svg
        design/brand-export/icon/favicon.svg
        design/brand-export/icons/heap-01-board.svg
        design/brand-export/icons/heap-02-timeline.svg
        design/brand-export/icons/heap-03-week.svg
        design/brand-export/icons/heap-04-month.svg
        design/brand-export/icons/heap-05-archive.svg
        design/brand-export/icons/heap-06-blocked.svg
        design/brand-export/icons/heap-07-code-review.svg
        design/brand-export/icons/heap-08-docs.svg
        design/brand-export/icons/heap-09-notes.svg
        design/brand-export/icons/heap-10-hotkeys.svg
        design/brand-export/icons/heap-11-tweaks.svg
        design/brand-export/icons/heap-12-settings.svg
        design/brand-export/surfaces/heap-splash.svg
        design/brand-export/surfaces/heap-readme-banner.svg
        design/brand-export/surfaces/heap-marketing-hero.svg
        design/brand-export/surfaces/heap-og-card.svg
)

# ── macOS .app bundle metadata (HEAP-68) ──
# A real Info.plist (identifier, display name, high-DPI, min OS) instead of the
# generic one Qt auto-generates, plus the Dock/Finder icon. The .icns is used
# as-is when committed; otherwise it is generated here from the brand SVG at
# configure time (rsvg-convert + iconutil — `brew install librsvg`), so every
# macOS build (local dev, CI, release) carries the icon rather than only the
# release pipeline. If the tools are missing it falls back to Qt's default.
if(APPLE)
    set(MACOSX_BUNDLE_EXECUTABLE_NAME "heap")
    set(MACOSX_BUNDLE_BUNDLE_NAME "heap.")
    set(MACOSX_BUNDLE_GUI_IDENTIFIER "local.heap.app")
    set(MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}")
    set(MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}")
    set_target_properties(heap PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/packaging/macos/Info.plist.in")

    set(_heap_icns "${CMAKE_SOURCE_DIR}/design/brand-export/icon/heap.icns")
    set(_heap_icon_svg "${CMAKE_SOURCE_DIR}/design/brand-export/icon/heap-icon.svg")
    if(NOT EXISTS "${_heap_icns}")
        find_program(RSVG_CONVERT rsvg-convert)
        find_program(ICONUTIL iconutil)
        if(RSVG_CONVERT AND ICONUTIL AND EXISTS "${_heap_icon_svg}")
            set(_iconset "${CMAKE_BINARY_DIR}/heap.iconset")
            file(MAKE_DIRECTORY "${_iconset}")
            foreach(sz 16 32 128 256 512)
                math(EXPR sz2 "${sz} * 2")
                execute_process(COMMAND "${RSVG_CONVERT}" -w ${sz}  -h ${sz}  -a "${_heap_icon_svg}" -o "${_iconset}/icon_${sz}x${sz}.png")
                execute_process(COMMAND "${RSVG_CONVERT}" -w ${sz2} -h ${sz2} -a "${_heap_icon_svg}" -o "${_iconset}/icon_${sz}x${sz}@2x.png")
            endforeach()
            execute_process(COMMAND "${ICONUTIL}" -c icns "${_iconset}" -o "${CMAKE_BINARY_DIR}/heap.icns")
            if(EXISTS "${CMAKE_BINARY_DIR}/heap.icns")
                set(_heap_icns "${CMAKE_BINARY_DIR}/heap.icns")
            endif()
        else()
            message(STATUS "heap: no heap.icns and rsvg-convert/iconutil unavailable — bundle will use Qt's default icon")
        endif()
    endif()
    if(EXISTS "${_heap_icns}")
        set(MACOSX_BUNDLE_ICON_FILE "heap.icns")
        target_sources(heap PRIVATE "${_heap_icns}")
        set_source_files_properties("${_heap_icns}" PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
    endif()
endif()

install(TARGETS heap
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
)

option(HEAP_BUILD_TESTS "Build heap unit tests" ON)
if(HEAP_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# ─── Автоматическое создание Portable-сборки ───
if(WIN32)
    find_program(WINDEPLOYQT_EXECUTABLE windeployqt)

    if(WINDEPLOYQT_EXECUTABLE)
        # Параметризуем корень MSYS2: переопределяется через -DMSYS_ROOT=...
        # на CI и локально может отличаться только этим значением
        set(MSYS_ROOT "C:/msys64" CACHE PATH "MSYS2 installation root")
        set(MSYS_BIN_DIR "${MSYS_ROOT}/ucrt64/bin")
        set(MSYS_QML_DIR "${MSYS_ROOT}/ucrt64/share/qt6/qml")
        # Qt6 helper executables (qmlimportscanner etc.). MSYS2 places these
        # under share/qt6/libexec on current packages and share/qt6/bin on
        # older ones — include both so windeployqt's child process can launch
        # without needing PATH munging in the workflow.
        set(MSYS_QT_LIBEXEC "${MSYS_ROOT}/ucrt64/share/qt6/libexec")
        set(MSYS_QT_SHARE_BIN "${MSYS_ROOT}/ucrt64/share/qt6/bin")

        set(PORTABLE_DIR "${CMAKE_BINARY_DIR}/heap-portable")

        # PATH override for the windeployqt invocation only: prepend the Qt
        # tool dirs so its `QProcess::start("qmlimportscanner.exe")` finds
        # both the executable and the Qt6Core.dll it depends on. Bare
        # backslash-free, ';' separator — Windows form. We do NOT append
        # $ENV{PATH} because the value mixes UNIX-style ':' separators when
        # invoked from the msys2 shell, which would corrupt the resulting
        # PATH; system DLLs are still located via Windows default search.
        set(_windeploy_path
            "${MSYS_BIN_DIR};${MSYS_QT_LIBEXEC};${MSYS_QT_SHARE_BIN}")

        # Bundle the Universal CRT so the portable zip launches on a clean or
        # older Windows. heap.exe and the qwindows platform plugin statically
        # import api-ms-win-crt-*.dll; on a fully-updated Win10/11 those are an
        # OS component, but on a fresh/un-updated/LTSC/Win8.1 machine they are
        # absent and the loader aborts before main() with
        # "api-ms-win-crt-runtime-l1-1-0.dll was not found". Copying the SDK's
        # UCRT redist beside the exe (app-local deployment) is Microsoft's
        # supported fix. The DLLs only import ntdll/kernel32, so the copy-deps
        # closure stays clean.
        file(GLOB _ucrt_redist_dirs
             "C:/Program Files (x86)/Windows Kits/10/Redist/*/ucrt/DLLs/x64")
        if(_ucrt_redist_dirs)
            list(SORT _ucrt_redist_dirs)
            list(GET _ucrt_redist_dirs -1 _ucrt_dir)
            file(GLOB _ucrt_dlls "${_ucrt_dir}/*.dll")
        endif()
        if(_ucrt_dlls)
            message(STATUS "Portable: bundling UCRT redist from ${_ucrt_dir}")
            set(_copy_ucrt COMMAND ${CMAKE_COMMAND} -E copy ${_ucrt_dlls} "${PORTABLE_DIR}/")
        else()
            message(WARNING "Portable: Windows SDK UCRT redist not found — "
                            "portable bundle will rely on the OS Universal CRT "
                            "(fine on updated Win10/11, may fail on clean/old Windows).")
            set(_copy_ucrt COMMAND ${CMAKE_COMMAND} -E true)
        endif()

        add_custom_target(portable
                DEPENDS heap
                COMMAND ${CMAKE_COMMAND} -E rm -rf          "${PORTABLE_DIR}"
                COMMAND ${CMAKE_COMMAND} -E make_directory  "${PORTABLE_DIR}"
                COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:heap>" "${PORTABLE_DIR}/"
                COMMAND ${CMAKE_COMMAND} -E env "PATH=${_windeploy_path}"
                        ${WINDEPLOYQT_EXECUTABLE}
                        --no-translations
                        --qmldir "${CMAKE_SOURCE_DIR}/qml"
                        "${PORTABLE_DIR}/$<TARGET_FILE_NAME:heap>"
                COMMAND ${CMAKE_COMMAND} -E copy "${MSYS_BIN_DIR}/libstdc++-6.dll"    "${PORTABLE_DIR}/"
                COMMAND ${CMAKE_COMMAND} -E copy "${MSYS_BIN_DIR}/libgcc_s_seh-1.dll" "${PORTABLE_DIR}/"
                COMMAND ${CMAKE_COMMAND} -E copy "${MSYS_BIN_DIR}/libwinpthread-1.dll" "${PORTABLE_DIR}/"
                # Universal CRT redist (see _copy_ucrt above) — no-op when the
                # SDK redist was not found at configure time.
                ${_copy_ucrt}
                COMMAND ${CMAKE_COMMAND} -E copy_directory "${MSYS_QML_DIR}/QtQuick"  "${PORTABLE_DIR}/QtQuick"
                # windeployqt bundles Qt's own DLLs + plugins but not qtkeychain
                # (a non-Qt module) nor the transitive non-Qt deps of
                # Qt6Core/Qt6Gui/plugins (pcre2/zlib/zstd/double-conversion/
                # freetype/harfbuzz/icu/brotli/libjpeg/...). Statically walk the
                # PE import table of every bundled DLL/exe (objdump, not ldd —
                # ldd on CI lists only direct imports) and copy each dep from
                # ucrt64/bin; fails the build if the closure is incomplete.
                COMMAND bash "${CMAKE_SOURCE_DIR}/packaging/windows/copy-deps.sh"
                        "${PORTABLE_DIR}" "${MSYS_BIN_DIR}"
                COMMENT "Assembling portable bundle → ${PORTABLE_DIR}"
        )
    else()
        message(WARNING "windeployqt not found — portable target unavailable.")
    endif()
endif()