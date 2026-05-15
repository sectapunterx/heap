cmake_minimum_required(VERSION 3.21)
project(todocpp VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.2 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.4)

qt_add_executable(todocpp
    src/main.cpp
    src/AppController.cpp
    src/Models.cpp
    src/SampleData.cpp
)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(todocpp
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
        qml/MiniWeek.qml
        qml/DayCalendar.qml
        qml/PeopleList.qml
        qml/TaskEditor.qml
        qml/EventEditor.qml
        qml/PersonEditor.qml
        qml/TweaksPanel.qml
        qml/Toast.qml
        qml/PillButton.qml
    SOURCES
        src/AppController.h
        src/Models.h
        src/SampleData.h
)

target_include_directories(todocpp PRIVATE src)
target_link_libraries(todocpp PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)

install(TARGETS todocpp
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
)
