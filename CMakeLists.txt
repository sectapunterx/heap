cmake_minimum_required(VERSION 3.21)
project(heap VERSION 0.4.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.2 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Widgets)
# Qt6Svg is optional — it provides the `qsvg` image-format plugin so QML <Image>
# can render the heap. app icon (BrandLogo itself uses native primitives, so
# the brand still renders without it). Install with:
#   pacman -S mingw-w64-ucrt-x86_64-qt6-svg   (MSYS2 UCRT64)
#   apt install libqt6svg6-dev                (Debian / Ubuntu)
find_package(Qt6 6.2 QUIET OPTIONAL_COMPONENTS Svg)

qt_standard_project_setup(REQUIRES 6.4)

qt_add_executable(heap WIN32
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
)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/Brand.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# URI stays "TodoCpp" so existing `import TodoCpp` statements throughout qml/
# don't have to be touched. The user-facing app name is heap.
qt_add_qml_module(heap
    URI TodoCpp
    VERSION 1.0
    RESOURCE_PREFIX "/qt/qml"
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/TopBar.qml
        qml/SideRail.qml
        qml/FilterBar.qml
        qml/KanbanBoard.qml
        qml/TaskCard.qml
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
        qml/ThinScrollBar.qml
        qml/Brand.qml
        qml/BrandLogo.qml
        qml/SplashScreen.qml
        qml/QuickCapturePopup.qml
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
        design/brand-export/icon/heap-icon.svg
        design/brand-export/surfaces/heap-splash.svg
        design/brand-export/surfaces/heap-readme-banner.svg
        design/brand-export/surfaces/heap-marketing-hero.svg
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

# ─── Автоматическое создание Portable-сборки (для Windows / MSYS2) ───
if(WIN32)
    # Пытаемся найти windeployqt в путях системы
    find_program(WINDEPLOYQT_EXECUTABLE windeployqt)

    if(WINDEPLOYQT_EXECUTABLE)
        # Указываем имя папки, куда будет собираться портативная версия
        set(PORTABLE_DIR "${CMAKE_BINARY_DIR}/heap-portable")

        # Хардкодим пути MSYS2 UCRT64 (т.к. они стабильны для твоего окружения)
        set(MSYS_BIN_DIR "C:/msys64/ucrt64/bin")
        set(MSYS_QML_DIR "C:/msys64/ucrt64/share/qt6/qml")

        add_custom_target(portable
                # Указываем, что цель зависит от сборки самого приложения (heap)
                DEPENDS heap

                # 1. Очищаем старую папку (если есть) и создаем новую
                COMMAND ${CMAKE_COMMAND} -E rm -rf "${PORTABLE_DIR}"
                COMMAND ${CMAKE_COMMAND} -E make_directory "${PORTABLE_DIR}"

                # 2. Копируем свежесобранный .exe в новую папку
                COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:heap>" "${PORTABLE_DIR}/"

                # 3. Запускаем windeployqt для сбора библиотек Qt
                COMMAND ${WINDEPLOYQT_EXECUTABLE}
                --no-translations
                --qmldir "${CMAKE_SOURCE_DIR}/qml"
                "${PORTABLE_DIR}/$<TARGET_FILE_NAME:heap>"

                # 4. ВРУЧНУЮ копируем системные DLL от MinGW (которые windeployqt игнорирует)
                COMMAND ${CMAKE_COMMAND} -E copy "${MSYS_BIN_DIR}/libstdc++-6.dll" "${PORTABLE_DIR}/"
                COMMAND ${CMAKE_COMMAND} -E copy "${MSYS_BIN_DIR}/libgcc_s_seh-1.dll" "${PORTABLE_DIR}/"
                COMMAND ${CMAKE_COMMAND} -E copy "${MSYS_BIN_DIR}/libwinpthread-1.dll" "${PORTABLE_DIR}/"
                # Если понадобятся другие DLL (например, libzstd.dll), добавь их сюда по аналогии

                # 5. ВРУЧНУЮ копируем папку QtQuick (которую сканер MSYS2 часто пропускает)
                COMMAND ${CMAKE_COMMAND} -E copy_directory "${MSYS_QML_DIR}/QtQuick" "${PORTABLE_DIR}/QtQuick"

                COMMENT "Собираем готовую Portable-версию в папке ${PORTABLE_DIR}..."
        )
    else()
        message(WARNING "Утилита windeployqt не найдена. Portable-сборка недоступна.")
    endif()
endif()