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

    // ── Window geometry ───────────────────────────────────────────────
    // The window opened at a hardcoded 1440x900 in the same spot on every
    // launch, so resizing or moving it — or maximising it — was undone each
    // time the app started.
    //
    // Stored under settings.window in the same blob everything else uses.
    // SettingsView rewrites that blob wholesale but carries unknown top-level
    // keys across, so this survives a trip through the settings screen.
    property bool _geometryRestored: false

    // Builds the current view's loader on its first visit. Board, Notes and
    // Docs are never unloaded again.
    function activateCurrentView() {
        const v = AppController.currentView;
        if (v === "board") boardLoader.active = true;
        else if (v === "notes") notesLoader.active = true;
        else if (v === "docs") docsLoader.active = true;
    }

    // Whichever view is on screen. Four loaders now hold them — three kept
    // alive, one shared — so nothing outside should have to know which.
    function activeViewItem() {
        const v = AppController.currentView;
        if (v === "board") return boardLoader.item;
        if (v === "notes") return notesLoader.item;
        if (v === "docs") return docsLoader.item;
        return viewLoader.item;
    }

    function _settingsObject() {
        const raw = AppController.appSettingsJson || "";
        if (!raw.length) return ({});
        try { return JSON.parse(raw) || ({}); } catch (e) { return ({}); }
    }

    // True when at least a good part of `rect` lands on some screen. A window
    // restored onto a monitor that is no longer attached would otherwise open
    // off-screen with no way to drag it back.
    function _isOnAScreen(rect) {
        const screens = Qt.application.screens;
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            const ix = Math.max(0, Math.min(rect.x + rect.width,  s.virtualX + s.width)  - Math.max(rect.x, s.virtualX));
            const iy = Math.max(0, Math.min(rect.y + rect.height, s.virtualY + s.height) - Math.max(rect.y, s.virtualY));
            // A title bar's worth of overlap is enough to grab the window.
            if (ix >= 120 && iy >= 40) return true;
        }
        return false;
    }

    function _restoreGeometry() {
        const g = _settingsObject().window;
        if (!g) { win._geometryRestored = true; return; }

        const w = Math.max(win.minimumWidth,  Number(g.width)  || win.width);
        const h = Math.max(win.minimumHeight, Number(g.height) || win.height);
        const x = Number(g.x), y = Number(g.y);
        if (isFinite(x) && isFinite(y) && _isOnAScreen({ x: x, y: y, width: w, height: h })) {
            win.x = x;
            win.y = y;
        }
        win.width = w;
        win.height = h;
        if (g.maximized === true) win.visibility = Window.Maximized;
        win._geometryRestored = true;
    }

    // x/y/width/height change continuously while a window is dragged or
    // resized, so the write is debounced rather than run per frame.
    Timer {
        id: geometrySaveTimer
        interval: 400
        onTriggered: win._saveGeometry()
    }

    function _saveGeometry() {
        if (!win._geometryRestored) return;
        const maximized = win.visibility === Window.Maximized;
        const s = _settingsObject();
        // While maximised, x/y/width/height describe the maximised frame —
        // keep the last normal geometry so unmaximising after a restart does
        // not snap the window to the full screen size.
        const prev = s.window || ({});
        s.window = maximized
            ? { x: prev.x, y: prev.y, width: prev.width, height: prev.height, maximized: true }
            : { x: win.x, y: win.y, width: win.width, height: win.height, maximized: false };
        AppController.appSettingsJson = JSON.stringify(s);
    }

    onXChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    onYChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    onWidthChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    onHeightChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    onVisibilityChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    title: "heap. — Work, in one place."
    color: Theme.bg

    property string searchText: ""
    property var prioritiesFilter: ({})
    property bool showDoneTimeline: false
    property bool showArchived: false
    // Board column order. Lives on the window so it survives the board being
    // hidden, and so the filter bar and the board agree without either owning
    // the other.
    property string boardSortMode: "manual"

    // Reactive task / status counts. statusCounts is one pass over the model,
    // recomputed when the model changes; these used to be four separate full
    // scans, re-run from all four of the model's signals.
    readonly property var _counts: AppController.statusCounts
    readonly property int _activeCount:  (_counts["prog"] || 0) + (_counts["half"] || 0)
    readonly property int _blockedCount: _counts["blocked"] || 0
    readonly property int _reviewCount:  _counts["review"] || 0
    property int _taskCount: AppController.tasks.rowCount()
    Connections {
        target: AppController.tasks
        function onModelReset()   { win._taskCount = AppController.tasks.rowCount() }
        function onRowsInserted() { win._taskCount = AppController.tasks.rowCount() }
        function onRowsRemoved()  { win._taskCount = AppController.tasks.rowCount() }
    }

    Component.onCompleted: {
        _restoreGeometry();
        if (typeof INITIAL_VIEW !== "undefined" && INITIAL_VIEW && INITIAL_VIEW.length > 0)
            AppController.currentView = INITIAL_VIEW;
        // First run: greet the user once the overlay is ready.
        if (!AppController.welcomeSeen)
            Qt.callLater(welcome.open);
    }

    // Close-to-tray: on platforms that have a tray icon (Windows/macOS via the
    // notification tray fallback), the window hides instead of quitting so the
    // global capture hotkeys can summon it back. The tray menu's "Quit" calls
    // QCoreApplication::quit() directly, so a real exit bypasses this. On Linux
    // there is no tray icon, so closing quits as usual.
    readonly property bool _minimizeToTray: Qt.platform.os === "windows" || Qt.platform.os === "osx"
    onClosing: (close) => {
        if (win._minimizeToTray) {
            close.accepted = false;
            win.hide();
        }
    }

    // Open a side-rail popover next to its button — or close it if that same
    // button (or its shortcut) fired while the panel is already up.
    //
    // The popup is re-parented to the anchor so CloseOnPressOutsideParent means
    // "pressed outside the panel and outside the button that owns it": a press
    // anywhere else in the app dismisses it, while a press on the button itself
    // is left to the click handler below, which toggles. Positions are therefore
    // anchor-relative, but still clamped in window space so a rail button near
    // the bottom edge doesn't push the panel off-screen.
    // Everything that floats at the bottom centre — the selection bar, the
    // "continue tour" pill and the toast — used to be pinned to the same spot
    // and simply drew on top of each other (deleting a multi-selection put the
    // undo toast right over the selection bar). They stack instead.
    readonly property int _selectionBarSpace: AppController.selectionCount > 0 ? 68 : 0
    readonly property int _resumePillSpace: welcome.paused ? 52 : 0

    // True while anything modal-ish is up. A single-letter shortcut has to
    // stand down then: Qt only protects a focused text field, so a picker's
    // type-ahead or a read-only Text would otherwise swallow the keystroke or
    // let the shortcut fire over the dialog (HEAP-117).
    readonly property bool _overlayOpen: taskEditor.opened || eventEditor.opened
        || personEditor.opened || profileEditor.opened || welcome.opened
        || cmdPalette.opened || quickCapture.opened || quickCaptureNotes.opened
        || tweaks.opened || hotkeys.opened

    function _placePopover(pop, anchor) {
        const p = anchor.mapToItem(win.contentItem, 0, 0);
        const wantY = Math.max(8, Math.min(p.y, win.contentItem.height - pop.height - 8));
        pop.x = anchor.width + 6;
        pop.y = wantY - p.y;
    }
    function _togglePopover(pop, anchor) {
        if (pop.opened) {
            pop.close();
            return;
        }
        pop.parent = anchor;
        win._placePopover(pop, anchor);
        pop.open();
        // The Hotkeys panel sizes itself from its list's contentHeight, which is
        // still 0 on the very first open — re-clamp once it has a real height so
        // a bottom-anchored rail button can't push it off the window.
        Qt.callLater(function () { win._placePopover(pop, anchor); });
    }

    function activeCount() {
        return win._activeCount;
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
    // Bring the window to the foreground from any state (minimized, hidden to
    // tray, or merely unfocused). Shared by the two global-capture hotkeys and
    // the tray "Show" affordance.
    function _summon() {
        if (win.visibility === Window.Minimized || win.visibility === Window.Hidden || !win.visible)
            win.show();
        win.raise();
        win.requestActivate();
    }

    Connections {
        target: AppController
        function onSelectedDateChanged() { win._scheduleMap = win.scheduleMap() }
        // OS-level global hotkeys fired while the window may be minimized, in
        // the background, or hidden to the tray: bring it forward, then open the
        // matching Quick-capture popup.
        function onQuickCaptureRequested() {
            win._summon();
            quickCapture.open();
        }
        function onQuickCaptureNotesRequested() {
            win._summon();
            quickCaptureNotes.open();
        }
        // Tray click / "Show heap." menu entry — just restore the window.
        function onShowWindowRequested() { win._summon(); }
        function onToast(msg) { toast.show(msg) }
        function onUndoableToast(msg, secs) {
            toast.showWithAction(msg, I18n.t("undo.action"), secs, function () {
                AppController.undoLastDeletion()
            });
        }
        // A newer release was found — offer a one-click jump to the release page.
        function onUpdateAvailable(version, url) {
            toast.showWithAction(I18n.t("update.available").arg(version), I18n.t("update.download"), 10, function () {
                Qt.openUrlExternally(url)
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
            onOpenTweaks:  (anchor) => win._togglePopover(tweaks, anchor)
            onOpenHotkeys: (anchor) => win._togglePopover(hotkeys, anchor)
        }

        // Main column: filter bar + active view
        Item {
            Layout.row: 1; Layout.column: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // First-run demo banner: offer to clear the seeded sample data.
                Rectangle {
                    Layout.fillWidth: true
                    visible: AppController.demoActive
                    implicitHeight: visible ? 40 : 0
                    color: Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        spacing: 10
                        Text {
                            text: "✦  " + I18n.t("demo.banner.text")
                            color: Theme.text
                            font.pixelSize: 12
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        PillButton {
                            text: I18n.t("demo.banner.startFresh")
                            primary: true
                            onClicked: AppController.startFresh()
                        }
                        PillButton {
                            text: I18n.t("demo.banner.keep")
                            onClicked: AppController.dismissDemo()
                        }
                    }
                }

                FilterBar {
                    Layout.fillWidth: true
                    // Archive brings its own header and its own counter, and the
                    // fall-through label used to caption it "Docs".
                    visible: AppController.currentView !== "docs"
                          && AppController.currentView !== "notes"
                          && AppController.currentView !== "settings"
                          && AppController.currentView !== "archive"
                    viewLabel: AppController.currentView === "timeline" ? I18n.t("siderail.timeline")
                             : AppController.currentView === "week" ? I18n.t("siderail.week")
                             : AppController.currentView === "month" ? I18n.t("siderail.month")
                             : I18n.t("siderail.board")
                    priorities: win.prioritiesFilter
                    totalCount: win._taskCount
                    activeCount: win._activeCount
                    blockedCount: win._blockedCount
                    reviewCount: win._reviewCount
                    showArchived: win.showArchived
                    showSort: AppController.currentView === "board"
                    sortMode: win.boardSortMode
                    onSortModeRequested: (mode) => win.boardSortMode = mode
                    onTogglePriority: (p) => {
                        const next = Object.assign({}, win.prioritiesFilter);
                        next[p] = !next[p];
                        win.prioritiesFilter = next;
                    }
                    onClearPriorities: win.prioritiesFilter = ({})
                    onToggleArchived: win.showArchived = !win.showArchived
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Board, Notes and Docs are kept alive once visited.
                    // Swapping a Loader's sourceComponent destroys the item,
                    // and these three hold state the user notices losing: the
                    // board's scroll position and column focus, the note's
                    // caret, scroll and editor undo history, the docs
                    // section the user had scrolled to. Everything else is
                    // cheap to rebuild and stays on the shared loader below.
                    //
                    // They load lazily — `active` is flipped on first visit —
                    // so starting on the board does not build the notes
                    // editor and the docs catalogue too.
                    Loader {
                        id: boardLoader
                        anchors.fill: parent
                        visible: AppController.currentView === "board"
                        active: false
                        sourceComponent: boardComp
                    }
                    Loader {
                        id: notesLoader
                        anchors.fill: parent
                        visible: AppController.currentView === "notes"
                        active: false
                        sourceComponent: notesComp
                    }
                    Loader {
                        id: docsLoader
                        anchors.fill: parent
                        visible: AppController.currentView === "docs"
                        active: false
                        sourceComponent: docsComp
                    }

                    Loader {
                        id: viewLoader
                        anchors.fill: parent
                        visible: !boardLoader.visible && !notesLoader.visible && !docsLoader.visible
                        sourceComponent: {
                            if (AppController.currentView === "timeline") return timelineComp;
                            if (AppController.currentView === "week") return weekComp;
                            if (AppController.currentView === "month") return monthComp;
                            if (AppController.currentView === "archive") return archiveComp;
                            if (AppController.currentView === "settings") return settingsComp;
                            return null;
                        }
                    }

                    // First visit to one of the kept-alive views builds it.
                    // The function lives on `win` because a Connections handler
                    // does not resolve names from the scope its parent item
                    // declares them in — calling it unqualified from there is a
                    // ReferenceError, and the two views would never activate.
                    Connections {
                        target: AppController
                        function onCurrentViewChanged() { win.activateCurrentView(); }
                    }
                    Component.onCompleted: win.activateCurrentView()
                    SelectionBar {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 16
                        z: 50
                    }
                }
                Component {
                    id: boardComp
                    KanbanBoard {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        scheduleMap: win._scheduleMap
                        showArchived: win.showArchived
                        sortMode: win.boardSortMode
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
                        onEventClicked: (id, occurrence) => occurrence ? eventEditor.showForOccurrence(occurrence) : eventEditor.showForId(id)
                        // A click on an empty slot opens the editor on a draft
                        // rather than saving an untitled event: the user names
                        // it before it exists.
                        onCreateRequested: (hour, day) => {
                            const draft = AppController.newEventDraft(hour, day);
                            eventEditor.showForDraft(draft);
                        }
                    }
                }
                Component {
                    id: monthComp
                    MonthView {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        showArchived: win.showArchived
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                        onEventClicked: (id, occurrence) => occurrence ? eventEditor.showForOccurrence(occurrence) : eventEditor.showForId(id)
                    }
                }
                Component {
                    id: archiveComp
                    ArchiveView {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
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
                    NotesView {
                        // A palette hit in a note asks for the line its
                        // section starts on; clearing it afterwards lets the
                        // same line be requested twice.
                        jumpToLine: notesBridge.requestedLine
                        onJumpConsumed: notesBridge.requestedLine = -1
                    }
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
                        onEventClicked: (id, occurrence) => occurrence ? eventEditor.showForOccurrence(occurrence) : eventEditor.showForId(id)
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
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
    WelcomePopup {
        id: welcome
        // Per-step "open →" actions route here so the guide stays decoupled from
        // the popups/editors Main owns. Each _doAction() already finished the
        // guide, so the target surface is visible when we open it.
        onOpenAction: (id) => {
            if (id === "task-new")           taskEditor.showFor(AppController.newTaskDraft("todo"));
            else if (id === "quick-capture") quickCapture.open();
            else if (id === "palette")       cmdPalette.open();
            else if (id === "hotkeys")       rail.openHotkeys(rail.hotkeysAnchor);
        }
        // "Learn more →" — jump to Settings and scroll the Help doc to the anchor.
        onOpenHelp: (anchor) => {
            AppController.currentView = "settings";
            Qt.callLater(() => {
                const v = win.activeViewItem();
                if (v && v.openHelp)
                    v.openHelp(anchor);
            });
        }
    }

    // After a "delete all data" reset the controller rebuilds a fresh install;
    // jump back to the board and re-greet the user, mirroring true first-run.
    Connections {
        target: AppController
        function onFirstRunReset() {
            AppController.currentView = "board";
            welcome.step = 0;
            Qt.callLater(welcome.open);
        }
        // Settings → Help "Replay" re-opens the guide from the top without
        // touching any persisted onboarding flags.
        function onWelcomeReplayRequested() {
            welcome.step = 0;
            Qt.callLater(welcome.open);
        }
    }

    // Floating "continue tour" affordance, shown only while the welcome guide is
    // paused — i.e. the user tapped a step's "open →" / "Learn more →" and jumped
    // to a surface. Clicking the pill brings the tour back at the same step; the
    // ✕ gives up on it (marks it seen). This is what keeps an action from closing
    // the guide irreversibly.
    Rectangle {
        id: resumeGuidePill
        visible: welcome.paused
        enabled: visible
        z: 9000
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 + win._selectionBarSpace
        radius: 20
        height: 40
        width: pillRow.implicitWidth + 28
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1

        // Click anywhere on the pill → resume the tour.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: welcome.open()
        }
        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 12
            Text {
                text: I18n.t("welcome.resume")
                color: Theme.text
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Rectangle { width: 1; height: 18; color: Theme.border }
            // Give up on the tour. Nested (declared last) so it wins the click
            // over the pill; sized to 22px because the glyph's own bounds were a
            // ~10px target sitting right next to a much larger "resume" action.
            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 5
                color: giveUpMA.containsMouse ? Theme.panel3 : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: giveUpMA.containsMouse ? Theme.text : Theme.textMuted
                    font.pixelSize: 12
                }
                MouseArea {
                    id: giveUpMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: welcome._finish()
                }
            }
        }
    }
    QuickCapturePopup { id: quickCapture }
    QuickCaptureNotesPopup {
        id: quickCaptureNotes
    }

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
        onNavigateToNoteLine: (line) => notesBridge.requestedLine = line
    }

    // Anchor bridge — DocsView listens for changes and scrolls to the
    // anchorId set here (set, then cleared after one tick).
    QtObject {
        id: docsBridge
        property string requestedAnchor: ""
    }

    // The same idea for notes: a search hit sets the line it wants, NotesView
    // watches and puts the caret there.
    QtObject {
        id: notesBridge
        property int requestedLine: -1
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
        sequence: _kbd("quick-capture-notes")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: quickCaptureNotes.open()
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
        sequence: _kbd("view.month")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.currentView = "month"
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
        sequence: _kbd("view.archive")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.currentView = "archive"
    }
    Shortcut {
        sequence: _kbd("theme.toggle")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.theme = (AppController.theme === "dark" ? "light" : "dark")
    }
    Shortcut {
        sequence: _kbd("person.new")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: personEditor.showFor(AppController.newPersonDraft())
    }
    Shortcut {
        sequence: _kbd("profile.new")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: profileEditor.showCreate()
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
        sequence: _kbd("profile.weeklyReport")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        onActivated: AppController.copyWeeklyReportToClipboard()
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
        onActivated: AppController.undo()
    }
    Shortcut {
        sequence: _kbd("redo")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing && AppController.canRedo
        onActivated: AppController.redo()
    }
    Shortcut {
        sequence: _kbd("search.focus")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
        // The top bar's box searches tasks. In a view that has a search of its
        // own — Docs, and Notes once it grows one — Ctrl+F used to focus that
        // task box anyway, where typing did nothing to what was on screen.
        // Duck-typed so a view picks this up by declaring focusSearch().
        onActivated: {
            const view = win.activeViewItem();
            if (view && typeof view.focusSearch === "function") {
                view.focusSearch();
                return;
            }
            topBar.focusSearch();
        }
    }

    Shortcut {
        sequence: _kbd("selection.selectAll")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
            && (AppController.currentView === "board"
                || AppController.currentView === "timeline"
                || AppController.currentView === "week")
        onActivated: {
            const v = win.activeViewItem();
            if (v && v.selectAllVisible) v.selectAllVisible();
        }
    }
    Shortcut {
        sequence: _kbd("selection.clearSel")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
            && AppController.selectionCount > 0
        onActivated: AppController.clearSelection()
    }
    Shortcut {
        sequence: _kbd("selection.deleteSel")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing
            && AppController.selectionCount > 0
        onActivated: AppController.deleteSelectedTasks()
    }
    // Open the selected (or hovered) mirrored issue in its tracker (HEAP-117).
    // This is the first bare letter in the catalog. Qt hands a focused text
    // field the ShortcutOverride for an unmodified key, so typing "o" still
    // types it — but a read-only Text or a ComboBox's type-ahead would lose,
    // so the shortcut also stands down while any overlay is open.
    // ── Board keyboard cursor ─────────────────────────────────────────
    // The board was mouse-only: no way to move between cards, open one or
    // move one without dragging. Each of these stands down while an overlay
    // is open and off the board, exactly like task.openExternal below.
    //
    // The catalog holds the vim letter so it can be rebound; the arrow key is
    // a fixed alias alongside it, the way Ctrl+P aliases the palette.
    component BoardKey: Shortcut {
        context: Qt.ApplicationShortcut
        enabled: sequences.length > 0 && !hotkeys.isCapturing && !win._overlayOpen
            && AppController.currentView === "board"
    }

    BoardKey {
        sequences: [_kbd("board.cursorDown"), "Down"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursor) b.moveCursor(0, 1); }
    }
    BoardKey {
        sequences: [_kbd("board.cursorUp"), "Up"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursor) b.moveCursor(0, -1); }
    }
    BoardKey {
        sequences: [_kbd("board.cursorLeft"), "Left"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursor) b.moveCursor(-1, 0); }
    }
    BoardKey {
        sequences: [_kbd("board.cursorRight"), "Right"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursor) b.moveCursor(1, 0); }
    }
    BoardKey {
        sequences: [_kbd("board.open"), "Enter"]
        onActivated: { const b = win.activeViewItem(); if (b && b.openCursor) b.openCursor(); }
    }
    BoardKey {
        sequences: [_kbd("board.toggleSelect")]
        onActivated: { const b = win.activeViewItem(); if (b && b.toggleCursorSelection) b.toggleCursorSelection(); }
    }
    BoardKey {
        sequences: [_kbd("board.moveDown"), "Shift+Down"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursorCard) b.moveCursorCard(0, 1); }
    }
    BoardKey {
        sequences: [_kbd("board.moveUp"), "Shift+Up"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursorCard) b.moveCursorCard(0, -1); }
    }
    BoardKey {
        sequences: [_kbd("board.moveLeft"), "Shift+Left"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursorCard) b.moveCursorCard(-1, 0); }
    }
    BoardKey {
        sequences: [_kbd("board.moveRight"), "Shift+Right"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursorCard) b.moveCursorCard(1, 0); }
    }

    Shortcut {
        sequence: _kbd("task.openExternal")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !hotkeys.isCapturing && !win._overlayOpen
            && (AppController.currentView === "board"
                || AppController.currentView === "archive"
                || AppController.currentView === "timeline"
                || AppController.currentView === "week")
        onActivated: {
            // One selected card is unambiguous. Otherwise act on whatever the
            // cursor is over — never on a whole multi-selection, which would
            // open a browser tab per card.
            let id = "";
            if (AppController.selectionCount === 1) {
                id = AppController.selectedTaskIds[0];
            } else if (AppController.selectionCount === 0) {
                const v = win.activeViewItem();
                if (v && v.hoveredTaskId) id = v.hoveredTaskId;
            }
            if (id) AppController.openTaskExternal(id);
        }
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
        anchors.bottomMargin: 24 + win._selectionBarSpace + win._resumePillSpace
        anchors.horizontalCenter: parent.horizontalCenter
        z: 100
    }

    // Launch splash — covers the window until the scene is ready, then fades.
    // Honours reduced motion (no bar animation, no fade, dismissed promptly).
    SplashScreen {
        id: splash
        anchors.fill: parent
        z: 9999
        autoAnimate: !Theme.reducedMotion
        autoDuration: 900
        onFinished: splashFade.start()

        // Swallow input while the splash is up.
        MouseArea { anchors.fill: parent }

        // Reduced motion: the internal progress animation is off, so dismiss
        // via a short timer instead.
        Component.onCompleted: if (Theme.reducedMotion) splashReducedDismiss.start()
        Timer { id: splashReducedDismiss; interval: 250; onTriggered: splash.finished() }

        NumberAnimation {
            id: splashFade
            target: splash; property: "opacity"; to: 0
            duration: Theme.reducedMotion ? 0 : 350; easing.type: Easing.OutCubic
            onFinished: splash.visible = false
        }
    }
}
