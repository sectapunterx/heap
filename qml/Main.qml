import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import TodoCpp

ApplicationWindow {
    id: win
    visible: true
    width: 1440
    height: 900
    minimumWidth: 1100
    minimumHeight: 680
    title: "heap. — Work, in one place."
    color: Theme.bg

    property string searchText: ""
    property var prioritiesFilter: ({})
    property bool showDoneTimeline: false
    property bool showArchived: false

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
            toast.showWithAction(msg, I18n.t("undo.action"), secs, function () {
                AppController.undoLastDeletion()
            });
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
            id: topBar
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
            onExportJsonRequested: {
                exportJsonDialog.currentFile = "file:///" + (
                    (AppController.activeProfileId || "profile") + ".todocpp.json"
                );
                exportJsonDialog.open();
            }
            onImportJsonRequested: importJsonDialog.open()
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
            onOpenHotkeys: (anchor) => {
                const p = anchor.mapToItem(win.contentItem, 0, 0);
                hotkeys.x = p.x + anchor.width + 6;
                hotkeys.y = Math.max(8, Math.min(p.y, win.contentItem.height - hotkeys.height - 8));
                hotkeys.open();
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
                          && AppController.currentView !== "notes"
                          && AppController.currentView !== "settings"
                    viewLabel: AppController.currentView === "board" ? "Board"
                             : AppController.currentView === "timeline" ? "Timeline"
                             : AppController.currentView === "week" ? "Week"
                             : "Docs"
                    priorities: win.prioritiesFilter
                    totalCount: win._taskCount
                    activeCount: win._activeCount
                    blockedCount: win._blockedCount
                    reviewCount: win._reviewCount
                    showArchived: win.showArchived
                    onTogglePriority: (p) => {
                        const next = Object.assign({}, win.prioritiesFilter);
                        next[p] = !next[p];
                        win.prioritiesFilter = next;
                    }
                    onClearPriorities: win.prioritiesFilter = ({})
                    onToggleArchived: win.showArchived = !win.showArchived
                }
                Loader {
                    id: viewLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: {
                        if (AppController.currentView === "timeline") return timelineComp;
                        if (AppController.currentView === "week")     return weekComp;
                        if (AppController.currentView === "docs")     return docsComp;
                        if (AppController.currentView === "notes")    return notesComp;
                        if (AppController.currentView === "settings") return settingsComp;
                        return boardComp;
                    }
                }
                Component {
                    id: boardComp
                    KanbanBoard {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        scheduleMap: win._scheduleMap
                        showArchived: win.showArchived
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
                        showArchived: win.showArchived
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                        onToggleShowDone: win.showDoneTimeline = !win.showDoneTimeline
                    }
                }
                Component {
                    id: weekComp
                    WeekView {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        showArchived: win.showArchived
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
                Component {
                    id: notesComp
                    NotesView {}
                }
                Component {
                    id: settingsComp
                    SettingsView {
                        // Expose a "bus" the inner buttons can hit to open
                        // popups owned by Main (HotkeysPanel + FileDialog).
                        property var settingsBus: QtObject {
                            function openHotkeys() { rail.openHotkeys(rail.hotkeysAnchor) }
                            function exportJson()  { exportJsonDialog.open() }
                            function importJson()  { importJsonDialog.open() }
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
    QuickCapturePopup { id: quickCapture }

    // GitWatcher → TaskEditor bridge: TopBar "Open" button on the focus
    // banner emits openTaskRequested; route it through the same showFor()
    // path used by Kanban / Timeline / palette.
    Connections {
        target: AppController
        function onOpenTaskRequested(taskId) {
            taskEditor.showFor(Object.assign({}, AppController.taskById(taskId)));
        }
    }

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

    // ── Rebindable application shortcuts ──────────────────────────────
    // Each Shortcut's sequence is bound through _kbd(id), which depends on
    // AppController.shortcuts (a Q_PROPERTY) so the binding re-evaluates on
    // shortcutsChanged — rebinding in the Hotkeys panel applies instantly.
    function _kbd(id) {
        const list = AppController.shortcuts;
        for (let i = 0; i < list.length; i++)
            if (list[i].id === id) return list[i].sequence;
        return "";
    }

    Shortcut {
        sequence: _kbd("palette.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: cmdPalette.open()
    }
    // Built-in alias: Ctrl+P always opens the palette, independent of the
    // catalog. If the user rebinds palette.open elsewhere, this still works.
    Shortcut {
        sequence: "Ctrl+P"
        context: Qt.ApplicationShortcut
        enabled: !hotkeys.isCapturing
        onActivated: cmdPalette.open()
    }

    Shortcut {
        sequence: _kbd("task.new")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: taskEditor.showFor(AppController.newTaskDraft("todo"))
    }
    Shortcut {
        sequence: _kbd("quick-capture")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: quickCapture.open()
    }
    Shortcut {
        sequence: _kbd("view.board")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.currentView = "board"
    }
    Shortcut {
        sequence: _kbd("view.timeline")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.currentView = "timeline"
    }
    Shortcut {
        sequence: _kbd("view.week")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.currentView = "week"
    }
    Shortcut {
        sequence: _kbd("view.docs")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.currentView = "docs"
    }
    Shortcut {
        sequence: _kbd("view.notes")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.currentView = "notes"
    }
    Shortcut {
        sequence: _kbd("view.settings")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.currentView = "settings"
    }
    Shortcut {
        sequence: _kbd("profile.next")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: {
            const list = AppController.profiles;
            if (list.length === 0) return;
            let idx = -1;
            for (let i = 0; i < list.length; i++) if (list[i].id === AppController.activeProfileId) idx = i;
            const next = list[((idx >= 0 ? idx : 0) + 1) % list.length];
            AppController.activeProfileId = next.id;
        }
    }
    Shortcut {
        sequence: _kbd("profile.prev")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: {
            const list = AppController.profiles;
            if (list.length === 0) return;
            let idx = 0;
            for (let i = 0; i < list.length; i++) if (list[i].id === AppController.activeProfileId) idx = i;
            const prev = list[(idx - 1 + list.length) % list.length];
            AppController.activeProfileId = prev.id;
        }
    }
    Shortcut {
        sequence: _kbd("profile.exportMd")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.copyActiveProfileMarkdownToClipboard()
    }
    Shortcut {
        sequence: _kbd("tweaks.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: rail.openTweaks(rail.tweaksAnchor)
    }
    Shortcut {
        sequence: _kbd("hotkeys.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: rail.openHotkeys(rail.hotkeysAnchor)
    }
    Shortcut {
        sequence: _kbd("undo")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing && AppController.hasPendingUndo
        onActivated: AppController.undoLastDeletion()
    }
    Shortcut {
        sequence: _kbd("search.focus")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: topBar.focusSearch()
    }

    Connections {
        target: AppController
        function onActiveProfileChanged() {
            win.searchText = "";
            win.prioritiesFilter = ({});
            AppController.selectedDate = AppController.today;
        }
    }

    // Tweaks + Hotkeys popovers (opened from the side rail)
    TweaksPanel  { id: tweaks }
    HotkeysPanel { id: hotkeys }

    // ── Profile import / export via JSON file ──────────────────────────
    FileDialog {
        id: exportJsonDialog
        fileMode: FileDialog.SaveFile
        nameFilters: ["heap. profile (*.json)", "All files (*)"]
        defaultSuffix: "json"
        title: I18n.t("dialog.exportProfile.title")
        onAccepted: {
            if (AppController.exportActiveProfileToFile(selectedFile))
                toast.show(I18n.t("toast.profile.exported"));
            else
                toast.show(I18n.t("toast.profile.exportFail"));
        }
    }
    FileDialog {
        id: importJsonDialog
        fileMode: FileDialog.OpenFile
        nameFilters: ["heap. profile (*.json)", "All files (*)"]
        title: I18n.t("dialog.importProfile.title")
        onAccepted: {
            const err = AppController.importProfileFromJson === undefined
                ? "" : AppController.importProfileFromFile(selectedFile, true);
            if (err && err.length > 0)
                toast.show(I18n.t("toast.profile.importFail") + err);
        }
    }

    Toast {
        id: toast
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        z: 100
    }
}
