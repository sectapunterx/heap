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
    property bool showDoneTimeline: false

    // Reactive task / status counts — QAbstractItemModel signals refresh
    // these on profile switch (modelReset) and on individual mutations.
    property int _taskCount:    AppController.tasks.rowCount()
    property int _activeCount:  AppController.countByStatus("prog") + AppController.countByStatus("half")
    property int _blockedCount: AppController.countByStatus("blocked")
    property int _reviewCount:  AppController.countByStatus("review")
    function _recountStatuses() {
        _taskCount    = AppController.tasks.rowCount();
        _activeCount  = AppController.countByStatus("prog") + AppController.countByStatus("half");
        _blockedCount = AppController.countByStatus("blocked");
        _reviewCount  = AppController.countByStatus("review");
    }
    Connections {
        target: AppController.tasks
        function onModelReset()   { win._recountStatuses() }
        function onRowsInserted() { win._recountStatuses() }
        function onRowsRemoved()  { win._recountStatuses() }
        function onDataChanged()  { win._recountStatuses() }
    }

    Component.onCompleted: {
        if (typeof INITIAL_VIEW !== "undefined" && INITIAL_VIEW && INITIAL_VIEW.length > 0)
            AppController.currentView = INITIAL_VIEW;
    }

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
        function onModelReset()   { win._scheduleMap = win.scheduleMap() }
    }
    Connections {
        target: AppController
        function onSelectedDateChanged() { win._scheduleMap = win.scheduleMap() }
        function onToast(msg) { toast.show(msg) }
        function onUndoableToast(msg, secs) {
            toast.showWithAction(msg, "Отменить", secs, function () { AppController.undoLastDeletion() });
        }
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
            onNewProfileRequested: profileEditor.showCreate()
            onRenameProfileRequested: {
                const list = AppController.profiles;
                const id = AppController.activeProfileId;
                for (let i = 0; i < list.length; i++) if (list[i].id === id)
                    profileEditor.showRename(list[i].id, list[i].name, list[i].color);
            }
            onDuplicateProfileRequested: {
                const list = AppController.profiles;
                const id = AppController.activeProfileId;
                for (let i = 0; i < list.length; i++) if (list[i].id === id)
                    profileEditor.showDuplicate(list[i].id, list[i].name, list[i].color);
            }
        }

        // Side rail
        SideRail {
            id: rail
            Layout.row: 1; Layout.column: 0
            Layout.fillHeight: true
            onOpenTweaks: (anchor) => {
                const p = anchor.mapToItem(win.contentItem, 0, 0);
                tweaks.x = p.x + anchor.width + 6;
                tweaks.y = Math.max(8, Math.min(p.y, win.contentItem.height - tweaks.height - 8));
                tweaks.open();
            }
        }

        // Main column: filter bar + active view
        Item {
            Layout.row: 1; Layout.column: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                FilterBar {
                    Layout.fillWidth: true
                    visible: AppController.currentView !== "docs"
                    viewLabel: AppController.currentView === "board" ? "Board"
                             : AppController.currentView === "timeline" ? "Timeline"
                             : AppController.currentView === "week" ? "Week"
                             : "Docs"
                    priorities: win.prioritiesFilter
                    totalCount: win._taskCount
                    activeCount: win._activeCount
                    blockedCount: win._blockedCount
                    reviewCount: win._reviewCount
                    onTogglePriority: (p) => {
                        const next = Object.assign({}, win.prioritiesFilter);
                        next[p] = !next[p];
                        win.prioritiesFilter = next;
                    }
                    onClearPriorities: win.prioritiesFilter = ({})
                }
                Loader {
                    id: viewLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: {
                        if (AppController.currentView === "timeline") return timelineComp;
                        if (AppController.currentView === "week")     return weekComp;
                        if (AppController.currentView === "docs")     return docsComp;
                        return boardComp;
                    }
                }
                Component {
                    id: boardComp
                    KanbanBoard {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        scheduleMap: win._scheduleMap
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                        onCreateInStatus: (s) => taskEditor.showFor(AppController.newTaskDraft(s))
                    }
                }
                Component {
                    id: timelineComp
                    TimelineView {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        scheduleMap: win._scheduleMap
                        showDone: win.showDoneTimeline
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                        onToggleShowDone: win.showDoneTimeline = !win.showDoneTimeline
                    }
                }
                Component {
                    id: weekComp
                    WeekView {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                        onEventClicked: (id) => eventEditor.showForId(id)
                    }
                }
                Component {
                    id: docsComp
                    DocsView {
                        id: docsView
                        Connections {
                            target: docsBridge
                            function onRequestedAnchorChanged() {
                                if (docsBridge.requestedAnchor.length > 0) {
                                    Qt.callLater(function () {
                                        docsView.scrollToAnchor(docsBridge.requestedAnchor);
                                        docsBridge.requestedAnchor = "";
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        // Right column
        Rectangle {
            Layout.row: 1; Layout.column: 2
            Layout.preferredWidth: 420
            Layout.minimumWidth: 360
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

    TaskEditor    { id: taskEditor }
    EventEditor   { id: eventEditor }
    PersonEditor  { id: personEditor }
    ProfileEditor { id: profileEditor }

    CommandPalette {
        id: cmdPalette
        onOpenTask: (taskId) => taskEditor.showFor(Object.assign({}, AppController.taskById(taskId)))
        onOpenPerson: (personId) => personEditor.showFor(AppController.personById(personId))
        onNavigateToDoc: (sectionId) => docsBridge.requestedAnchor = "sec-" + sectionId
        onNavigateToSnippets: docsBridge.requestedAnchor = "sec-snippets"
        onNavigateToContacts: docsBridge.requestedAnchor = "sec-contacts"
    }

    // Anchor bridge — DocsView listens for changes and scrolls to the
    // anchorId set here (set, then cleared after one tick).
    QtObject {
        id: docsBridge
        property string requestedAnchor: ""
    }

    Shortcut {
        sequences: ["Ctrl+K", "Ctrl+P"]
        context: Qt.ApplicationShortcut
        onActivated: cmdPalette.open()
    }

    Connections {
        target: AppController
        function onActiveProfileChanged() {
            win.searchText = "";
            win.prioritiesFilter = ({});
            AppController.selectedDate = AppController.today;
        }
    }

    // Tweaks popover (opened from the side rail)
    TweaksPanel { id: tweaks }

    Toast {
        id: toast
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        z: 100
    }
}
