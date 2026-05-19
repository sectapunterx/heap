cmake_minimum_required(VERSION 3.21)
project(heap VERSION 0.4.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
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

qt_add_executable(heap
    src/main.cpp
    src/AppController.cpp
    src/Models.cpp
    src/SampleData.cpp
    src/CodeHighlighter.cpp
    src/NotesHighlighter.cpp
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
    SOURCES
        src/AppController.h
        src/Models.h
        src/SampleData.h
        src/CodeHighlighter.h
        src/NotesHighlighter.h
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
