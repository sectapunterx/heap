cmake_minimum_required(VERSION 3.21)
project(heap VERSION 0.4.2 LANGUAGES CXX)

# Windows resource compiler (windres on mingw / rc.exe on MSVC). Required so
# design/brand-export/icon/heap-icon.rc is actually compiled into heap.exe —
# without this, CMake silently skips .rc inputs and the PE icon resource is
# missing, leaving Explorer/taskbar with the default Qt icon in release.
if (WIN32)
    enable_language(RC)
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

find_package(Qt6 6.2 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Widgets)
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

qt_standard_project_setup(REQUIRES 6.4)

# WIN32 → GUI subsystem on Windows (no console); MACOSX_BUNDLE → a .app on
# macOS so windeployqt/macdeployqt and `install(... BUNDLE ...)` have a bundle
# to operate on. Each keyword applies only to its own platform.
qt_add_executable(heap WIN32 MACOSX_BUNDLE
    src/main.cpp
    src/AppController.cpp
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
    src/notify/NotificationCenter.cpp
    src/notify/NotificationCenter_tray.cpp
    $<$<PLATFORM_ID:Linux>:${CMAKE_SOURCE_DIR}/src/notify/NotificationCenter_linux.cpp>
        $<$<PLATFORM_ID:Windows>:${CMAKE_SOURCE_DIR}/design/brand-export/icon/heap-icon.rc>
)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/Brand.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/I18n.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# URI stays "TodoCpp" so existing `import TodoCpp` statements throughout qml/
# don't have to be touched. The user-facing app name is heap.
qt_add_qml_module(heap
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
        qml/DocsView.qml
        qml/DocsEditor.qml
        qml/MiniWeek.qml
        qml/DayCalendar.qml
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
        src/notify/NotificationCenter.h
)

target_include_directories(heap PRIVATE src)
target_link_libraries(heap PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
)
if(UNIX AND NOT APPLE)
    target_link_libraries(heap PRIVATE Qt6::DBus)
endif()

# Compile-time flag that AppController exposes as a CONSTANT Q_PROPERTY so QML
# can adapt the Settings UI: unimplemented sections are shown disabled in
# Release, and the "show unimplemented" toggle is added in Debug only.
target_compile_definitions(heap PRIVATE
    $<$<CONFIG:Debug>:HEAP_DEBUG_BUILD=1>
    $<$<CONFIG:RelWithDebInfo>:HEAP_DEBUG_BUILD=1>
)
if (TARGET Qt6::Svg)
    target_link_libraries(heap PRIVATE Qt6::Svg)
    target_compile_definitions(heap PRIVATE HEAP_HAS_SVG=1)
endif()

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
        design/brand-export/surfaces/heap-splash.svg
        design/brand-export/surfaces/heap-readme-banner.svg
        design/brand-export/surfaces/heap-marketing-hero.svg
        design/brand-export/surfaces/heap-og-card.svg
)

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
                COMMAND ${CMAKE_COMMAND} -E copy_directory "${MSYS_QML_DIR}/QtQuick"  "${PORTABLE_DIR}/QtQuick"
                COMMENT "Assembling portable bundle → ${PORTABLE_DIR}"
        )
    else()
        message(WARNING "windeployqt not found — portable target unavailable.")
    endif()
endif()