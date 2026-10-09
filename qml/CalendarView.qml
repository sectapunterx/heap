pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import TodoCpp

// The Calendar lens of Tasks (APP-264): Day, Week and Month as one zoom of
// the same calendar, with the "Without a date" tray beside it. The range and
// the zoom are in the header (TopBar); the grid is the week grid at one or
// seven days, or the month. Each thing is shown once: a meeting filled, a
// task with a time outlined, a deadline without one as a flag.
Item {
    id: root
    objectName: "calendar-view"

    // "day" | "week" | "month"
    property string zoom: "week"
    property string searchText: ""
    property var prioritiesFilter: ({})
    property bool showArchived: false

    signal taskClicked(string id)
    signal eventClicked(string id, var occurrence)
    // A slot (or a stretch) on the grid: the shell opens the event editor.
    signal createRequested(real startHour, real endHour, date day)
    // "+N more" on a month day: that day, zoomed in.
    signal dayRequested(date day)

    // What the shell's keys act on (step, moves): the grid on screen.
    readonly property var calendarView: inner.item
    function step(dir) { if (root.calendarView) root.calendarView.step(dir); }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        // APP-255: the Jira sprint marker (SprintMarker.qml, fed by
        // AppController.sprintMarkers(from, to)) belongs above the grid,
        // between the header and the day columns: wrap the Loader below in a
        // ColumnLayout and put it first, from the week's / month's range.
        Loader {
            id: inner
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.zoom === "month" ? monthComp : gridComp
        }
        UndatedTray {
            id: tray
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.px(260)
            visible: tray.count > 0 && root.width > Theme.px(720)
            searchText: root.searchText
            onTaskOpened: (id) => root.taskClicked(id)
        }
    }

    // A picked tray task waits for a click on the grid; Esc lets it go.
    Keys.onEscapePressed: (event) => {
        if (tray.armedId) { tray.armedId = ""; event.accepted = true; }
        else event.accepted = false;
    }

    Component {
        id: gridComp
        WeekView {
            chrome: false
            zoom: root.zoom === "day" ? "day" : "week"
            searchText: root.searchText
            prioritiesFilter: root.prioritiesFilter
            showArchived: root.showArchived
            armedTaskId: tray.armedId
            onArmedUsed: tray.armedId = ""
            onTaskClicked: (id) => root.taskClicked(id)
            onEventClicked: (id, occurrence) => root.eventClicked(id, occurrence)
            onCreateRequested: (hour, day) => root.createRequested(hour, Math.min(24, hour + 1), day)
            onCreateRangeRequested: (startHour, endHour, day) => root.createRequested(startHour, endHour, day)
        }
    }
    Component {
        id: monthComp
        MonthView {
            chrome: false
            searchText: root.searchText
            prioritiesFilter: root.prioritiesFilter
            showArchived: root.showArchived
            armedTaskId: tray.armedId
            onArmedUsed: tray.armedId = ""
            onTaskClicked: (id) => root.taskClicked(id)
            onEventClicked: (id, occurrence) => root.eventClicked(id, occurrence)
            onDayRequested: (day) => root.dayRequested(day)
        }
    }
}
