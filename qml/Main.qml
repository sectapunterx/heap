import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import TodoCpp

ApplicationWindow {
    id: win
    visible: true
    width: 1440
    height: 900
    minimumWidth: 1100
    minimumHeight: 680
    title: "todo·cpp — LTE programmer's day"
    color: Theme.bg

    property string searchText: ""
    property var prioritiesFilter: ({})

    function activeCount() {
        return AppController.countByStatus("prog") + AppController.countByStatus("half");
    }
    function scheduleMap() {
        const out = {};
        const m = AppController.events;
        const sel = AppController.selectedDate;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            const date = m.data(idx, Qt.UserRole + 7);
            const taskId = m.data(idx, Qt.UserRole + 8);
            if (!taskId) continue;
            if (date && sel && date.getFullYear() === sel.getFullYear()
                    && date.getMonth() === sel.getMonth()
                    && date.getDate() === sel.getDate()) {
                out[taskId] = AppController.eventHourLabel(m.data(idx, Qt.UserRole + 4));
            }
        }
        return out;
    }
    property var _scheduleMap: scheduleMap()
    Connections {
        target: AppController.events
        function onRowsInserted() { win._scheduleMap = win.scheduleMap() }
        function onRowsRemoved()  { win._scheduleMap = win.scheduleMap() }
        function onDataChanged()  { win._scheduleMap = win.scheduleMap() }
    }
    Connections {
        target: AppController
        function onSelectedDateChanged() { win._scheduleMap = win.scheduleMap() }
        function onToast(msg) { toast.show(msg) }
    }

    GridLayout {
        anchors.fill: parent
        columns: 3
        rows: 2
        columnSpacing: 0
        rowSpacing: 0

        // Top bar spans all columns
        TopBar {
            Layout.row: 0; Layout.column: 0; Layout.columnSpan: 3
            Layout.fillWidth: true
            searchText: win.searchText
            onSearchTextChanged: win.searchText = searchText
            onNewTaskRequested: taskEditor.showFor(AppController.newTaskDraft("todo"))
        }

        // Side rail
        SideRail {
            Layout.row: 1; Layout.column: 0
            Layout.fillHeight: true
        }

        // Main column: filter bar + kanban
        Item {
            Layout.row: 1; Layout.column: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                FilterBar {
                    Layout.fillWidth: true
                    priorities: win.prioritiesFilter
                    totalCount: AppController.tasks.rowCount()
                    activeCount: win.activeCount()
                    blockedCount: AppController.countByStatus("blocked")
                    reviewCount: AppController.countByStatus("review")
                    onTogglePriority: (p) => {
                        const next = Object.assign({}, win.prioritiesFilter);
                        next[p] = !next[p];
                        win.prioritiesFilter = next;
                    }
                    onClearPriorities: win.prioritiesFilter = ({})
                }
                KanbanBoard {
                    id: board
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    searchText: win.searchText
                    prioritiesFilter: win.prioritiesFilter
                    scheduleMap: win._scheduleMap
                    onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                    onCreateInStatus: (s) => taskEditor.showFor(AppController.newTaskDraft(s))
                }
            }
        }

        // Right column
        Rectangle {
            Layout.row: 1; Layout.column: 2
            Layout.preferredWidth: 420
            Layout.fillHeight: true
            color: Theme.panel
            Rectangle {
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: 1; color: Theme.border
            }
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                MiniWeek { Layout.fillWidth: true }
                SplitView {
                    id: rightSplit
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    orientation: Qt.Vertical

                    handle: Rectangle {
                        implicitHeight: 6
                        color: SplitHandle.pressed ? Theme.accent
                             : SplitHandle.hovered ? Theme.borderStrong
                             : Theme.border
                        Rectangle {
                            anchors.centerIn: parent
                            width: 32; height: 2; radius: 1
                            color: SplitHandle.hovered ? Theme.text : Theme.textDim
                            opacity: 0.6
                        }
                    }

                    DayCalendar {
                        SplitView.fillHeight: true
                        SplitView.minimumHeight: 120
                        onEventClicked: (id) => eventEditor.showForId(id)
                    }
                    PeopleList {
                        SplitView.preferredHeight: 220
                        SplitView.minimumHeight: 64
                        onPersonRequested: (id) => personEditor.showFor(AppController.personById(id))
                        onNewPersonRequested: personEditor.showFor(AppController.newPersonDraft())
                    }
                }
            }
        }
    }

    TaskEditor   { id: taskEditor }
    EventEditor  { id: eventEditor }
    PersonEditor { id: personEditor }

    // Floating tweaks panel
    TweaksPanel {
        id: tweaks
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        z: 50
    }

    Toast {
        id: toast
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        z: 100
    }
}
