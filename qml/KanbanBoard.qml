import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

Item {
    id: root
    property string searchText: ""
    property var prioritiesFilter: ({})
    property var scheduleMap: ({})
    property bool showArchived: false
    // The card under the cursor, read by Main.qml so a single-key action knows
    // which ticket it means when nothing is selected (HEAP-117).
    property string hoveredTaskId: ""
    signal taskClicked(string id)
    signal createInStatus(string statusId)

    // Anchor for shift-click range selection. Reset when the selection
    // disappears so the next shift-click starts a fresh range.
    property string shiftAnchorId: ""
    Connections {
        target: AppController

        function onSelectedTaskIdsChanged() {
            if (AppController.selectionCount === 0) root.shiftAnchorId = "";
        }

        // Sidebar Blocked / Code Review buttons jump the board to a column.
        function onFocusedStatusChanged() {
            if (AppController.focusedStatus.length > 0) root.focusColumn(AppController.focusedStatus);
        }
    }

    // One source of truth for the column width. focusColumn() scrolls by
    // index × width, so a literal here and a different literal in the delegate
    // silently put the wrong column on screen.
    readonly property int columnWidth: 280

    // ── Column focus (sidebar Blocked / Code Review buttons) ──────────
    // Scroll the target status column into view and briefly highlight it.
    property string _focusPulseStatus: ""
    NumberAnimation {
        id: colScrollAnim
        target: hscroll; property: "contentX"
        duration: Theme.scaledMs(260); easing.type: Easing.OutCubic
    }
    Timer { id: focusPulseTimer; interval: 1100; onTriggered: root._focusPulseStatus = "" }

    function focusColumn(statusId) {
        const st = AppController.statuses;
        let idx = -1;
        for (let i = 0; i < st.length; ++i) { if (st[i].id === statusId) { idx = i; break; } }
        if (idx < 0) return;
        const colW = root.columnWidth + rowL.spacing;
        const maxX = Math.max(0, hscroll.contentWidth - hscroll.width);
        colScrollAnim.to = Math.max(0, Math.min(idx * colW, maxX));
        colScrollAnim.restart();
        root._focusPulseStatus = statusId;
        focusPulseTimer.restart();
    }

    // A focus requested from another view fires focusedStatusChanged before this
    // board exists; pick it up once the board is created and laid out.
    Component.onCompleted: {
        if (AppController.focusedStatus && AppController.focusedStatus.length > 0)
            Qt.callLater(function() { root.focusColumn(AppController.focusedStatus); });
    }

    // Walk every column's TaskCard repeater, collect ids of currently
    // visible cards (respects search/priority/archived filters), hand them
    // to AppController as the new selection set.
    function selectAllVisible() {
        AppController.setSelectedTaskIds(_flatVisibleIds());
    }

    // ── Keyboard cursor ───────────────────────────────────────────────
    // The board is the app's main surface and was mouse-only: there was no way
    // to move between cards, open one, or move one, without dragging.
    //
    // The cursor is a task id rather than a (column, row) pair, so it survives
    // a filter change, a drag, or the card moving column — all of which
    // renumber the rows underneath it.
    property string cursorTaskId: ""

    // Visible ids per column, in board order. The same walk _flatVisibleIds()
    // does, but keeping the column structure that left/right needs.
    function _visibleByColumn() {
        const cols = [];
        for (let c = 0; c < colRepeater.count; c++) {
            const col = colRepeater.itemAt(c);
            if (!col || !col.taskRepeater) { cols.push({ statusId: "", ids: [] }); continue; }
            const ids = [];
            const rep = col.taskRepeater;
            for (let i = 0; i < rep.count; i++) {
                const it = rep.itemAt(i);
                if (it && it.visible && it.taskId) ids.push(it.taskId);
            }
            cols.push({ statusId: col.statusId, ids: ids });
        }
        return cols;
    }

    // Where the cursor currently sits, or null when it points at nothing on
    // screen (a filter may have hidden it).
    function _cursorPos(cols) {
        for (let c = 0; c < cols.length; c++) {
            const r = cols[c].ids.indexOf(root.cursorTaskId);
            if (r >= 0) return { col: c, row: r };
        }
        return null;
    }

    // First visible card, used when a key arrives with no cursor yet.
    function _firstVisible(cols) {
        for (let c = 0; c < cols.length; c++)
            if (cols[c].ids.length > 0) return cols[c].ids[0];
        return "";
    }

    function moveCursor(dx, dy) {
        const cols = _visibleByColumn();
        const pos = _cursorPos(cols);
        if (!pos) {
            root.cursorTaskId = _firstVisible(cols);
            return;
        }
        let c = pos.col;
        let r = pos.row;
        if (dy !== 0) {
            r = Math.max(0, Math.min(cols[c].ids.length - 1, r + dy));
        }
        if (dx !== 0) {
            // Skip empty columns rather than stopping at one — a gap in the
            // middle of the board should not swallow the cursor.
            let next = c;
            for (let step = c + dx; step >= 0 && step < cols.length; step += dx) {
                if (cols[step].ids.length > 0) { next = step; break; }
            }
            c = next;
            r = Math.max(0, Math.min(cols[c].ids.length - 1, r));
        }
        if (cols[c].ids.length === 0) return;
        root.cursorTaskId = cols[c].ids[r];
    }

    function openCursor() {
        const cols = _visibleByColumn();
        if (!_cursorPos(cols)) { root.cursorTaskId = _firstVisible(cols); return; }
        if (root.cursorTaskId) root.taskClicked(root.cursorTaskId);
    }

    function toggleCursorSelection() {
        const cols = _visibleByColumn();
        if (!_cursorPos(cols)) { root.cursorTaskId = _firstVisible(cols); return; }
        if (root.cursorTaskId) AppController.toggleTaskSelection(root.cursorTaskId);
    }

    // Move the card under the cursor. Vertically it swaps with its neighbour;
    // horizontally it changes column, landing at the same depth.
    function moveCursorCard(dx, dy) {
        const cols = _visibleByColumn();
        const pos = _cursorPos(cols);
        if (!pos) { root.cursorTaskId = _firstVisible(cols); return; }
        const id = root.cursorTaskId;

        if (dy !== 0) {
            const ids = cols[pos.col].ids;
            const target = pos.row + dy;
            if (target < 0 || target >= ids.length) return;
            // Moving down means landing after the card currently below, which
            // is "before the one after that".
            const beforeId = dy > 0
                ? (target + 1 < ids.length ? ids[target + 1] : "")
                : ids[target];
            AppController.moveTaskTo(id, cols[pos.col].statusId, beforeId);
            return;
        }

        let c = pos.col + dx;
        if (c < 0 || c >= cols.length) return;
        const destIds = cols[c].ids;
        const beforeId = pos.row < destIds.length ? destIds[pos.row] : "";
        AppController.moveTaskTo(id, cols[c].statusId, beforeId);
    }

    // Flat ordered list of visible task ids across the entire board, column
    // by column in render order, top-to-bottom inside each column. Used by
    // selectAllVisible() and shift-range select.
    function _flatVisibleIds() {
        const out = [];
        for (let c = 0; c < colRepeater.count; c++) {
            const col = colRepeater.itemAt(c);
            if (!col || !col.taskRepeater) continue;
            const rep = col.taskRepeater;
            for (let i = 0; i < rep.count; i++) {
                const it = rep.itemAt(i);
                if (it && it.visible && it.taskId) out.push(it.taskId);
            }
        }
        return out;
    }

    // Shift-click range: spans the flat visible list (cross-column). First
    // shift-click sets the anchor; subsequent shift-click selects every
    // ticket between anchor and target inclusive.
    function _rangeSelect(targetId) {
        const ordered = _flatVisibleIds();
        if (ordered.length === 0) return;
        const haveAnchor = root.shiftAnchorId && ordered.indexOf(root.shiftAnchorId) >= 0;
        if (!haveAnchor) {
            root.shiftAnchorId = targetId;
            AppController.toggleTaskSelection(targetId);
            return;
        }
        const ai = ordered.indexOf(root.shiftAnchorId);
        const ti = ordered.indexOf(targetId);
        const lo = Math.min(ai, ti);
        const hi = Math.max(ai, ti);
        const merged = AppController.selectedTaskIds.slice();
        for (let i = lo; i <= hi; i++) {
            if (merged.indexOf(ordered[i]) < 0) merged.push(ordered[i]);
        }
        AppController.setSelectedTaskIds(merged);
    }

    // The priorities the filter bar has switched on, as a plain list for the
    // per-column proxies. Empty means "no priority filter" — which is what an
    // all-chips-off filter bar means, not "nothing passes".
    readonly property var activePriorities: {
        const out = [];
        for (const k in root.prioritiesFilter) if (root.prioritiesFilter[k]) out.push(k);
        return out;
    }

    function _scrollOuter(dy) {
        if (dy === 0) return;
        const maxX = Math.max(0, hscroll.contentWidth - hscroll.width);
        if (maxX <= 0) return;
        const base = outerAnim.running ? outerAnim.to : hscroll.contentX;
        const newX = Math.max(0, Math.min(maxX, base - dy));
        if (newX === base) return;
        outerAnim.from = hscroll.contentX;
        outerAnim.to = newX;
        outerAnim.restart();
    }

    NumberAnimation {
        id: outerAnim
        target: hscroll
        property: "contentX"
        duration: Theme.scaledMs(220)
        easing.type: Easing.OutCubic
    }

    Flickable {
        id: hscroll
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 12
        anchors.bottomMargin: 16
        contentWidth: rowL.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true
        // pressDelay: 0 — keep card-drag activation instant on press.
        // Horizontal flick by dragging empty board space is rarely used
        // on desktop (mouse wheel handles it via WheelHandler below).
        pressDelay: 0

        // Outer wheel: scroll the board horizontally with mouse-wheel.
        // Triggered when an inner WheelHandler sets event.accepted = false
        // (e.g. column at vertical-scroll edge or column header).
        // Handles wheel on column headers / gaps / "+ column" tile —
        // scrolls the board horizontally. Wheel inside a column body is
        // handled by the inner WheelHandler, which calls _scrollOuter()
        // when the column has no vertical overflow.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                root._scrollOuter(event.angleDelta.y || event.angleDelta.x);
            }
        }

        Row {
            id: rowL
            height: hscroll.height
            spacing: 12

            Repeater {
                id: colRepeater
                model: AppController.statuses

                Rectangle {
                    id: col
                    required property var modelData
                    required property int index
                    readonly property string statusId: modelData.id
                    readonly property string statusName: modelData.name
                    readonly property color statusColor: modelData.color
                    readonly property alias taskRepeater: colRep
                    property bool dragOver: false
                    readonly property int visibleCount: colFilter.count
                    property bool renaming: false
                    readonly property bool isFirst: index === 0
                    readonly property bool isLast:  index === AppController.statuses.length - 1
                    // Drives the reveal of the header's move/delete icons. A
                    // HoverHandler, not the MouseArea below the header row:
                    // hover stops at the first item that accepts it, so with a
                    // MouseArea driving this the icons vanished the moment the
                    // pointer touched the column name (or one of the icons),
                    // which made them impossible to click.
                    property bool headerHovered: false
                    // Briefly emphasised when the sidebar Blocked / Code Review
                    // button jumps focus to this column.
                    readonly property bool focusPulse: root._focusPulseStatus === col.statusId

                    width: root.columnWidth
                    height: rowL.height
                    radius: Theme.radius
                    color: Theme.panel
                    border.color: (dragOver || focusPulse) ? Theme.accent : Theme.border
                    border.width: focusPulse ? 2 : 1
                    clip: true
                    Behavior on border.color { ColorAnimation { duration: Theme.scaledMs(180) } }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            color: Theme.panel2
                            HoverHandler { onHoveredChanged: col.headerHovered = hovered }
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 1; color: Theme.border
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 8
                                spacing: 8
                                // The swatch itself stays 10px, but it opens the
                                // colour picker, so the thing you click is a
                                // 20px box around it — a 10x10 target was barely
                                // hittable and gave no hint it was a button.
                                Item {
                                    id: colorSwatch
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 5
                                        color: swatchMA.containsMouse ? Theme.panel3 : "transparent"
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 10; height: 10; radius: 3
                                        color: col.statusColor
                                    }
                                    MouseArea {
                                        id: swatchMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: colorPopup.openFor(col.statusId, col.statusColor, colorSwatch)
                                        ToolTip.visible: containsMouse
                                        ToolTip.delay: 400
                                        ToolTip.text: I18n.t("kanban.changeColor")
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    Text {
                                        id: colName
                                        visible: !col.renaming
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: col.statusName.toUpperCase()
                                        color: Theme.textMuted
                                        font.family: Theme.fontUi
                                        font.pixelSize: 11
                                        font.letterSpacing: 1
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        visible: !col.renaming
                                        onDoubleClicked: { col.renaming = true; renameField.forceActiveFocus(); renameField.selectAll() }
                                        cursorShape: Qt.IBeamCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: I18n.t("kanban.tip.rename")
                                        ToolTip.delay: 500
                                        hoverEnabled: true
                                    }
                                    TextField {
                                        id: renameField
                                        visible: col.renaming
                                        anchors.fill: parent
                                        text: col.statusName
                                        // Typing breaks the declarative binding above; re-sync to the
                                        // authoritative name every time the field opens so an
                                        // Escape-cancelled edit can't linger and be auto-committed by
                                        // the blur handler on the next rename.
                                        onVisibleChanged: if (visible) text = col.statusName
                                        color: Theme.text
                                        background: Rectangle { radius: 4; color: Theme.panel; border.color: Theme.accent; border.width: 1 }
                                        font.family: Theme.fontUi
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        selectByMouse: true
                                        onAccepted: { AppController.renameStatus(col.statusId, text.trim()); col.renaming = false }
                                        onActiveFocusChanged: if (!activeFocus && col.renaming) { AppController.renameStatus(col.statusId, text.trim()); col.renaming = false }
                                        Keys.onEscapePressed: { col.renaming = false }
                                    }
                                }
                                Rectangle {
                                    radius: 999
                                    color: Theme.panel3
                                    implicitWidth: cntT.implicitWidth + 14
                                    implicitHeight: 18
                                    Text {
                                        id: cntT; anchors.centerIn: parent
                                        text: col.visibleCount
                                        color: Theme.textDim
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }
                                }

                                // Move-left / Move-right / Delete. `visible` only
                                // carries the structural conditions; the reveal
                                // rides on opacity so the header doesn't reflow
                                // (name and counter used to jump sideways) and
                                // the icons keep a stable position to click.
                                HoverIcon {
                                    glyph: "‹"; tip: I18n.t("kanban.moveLeft")
                                    visible: !col.isFirst
                                    revealed: col.headerHovered
                                    onActivated: AppController.moveStatus(col.statusId, col.index - 1)
                                }
                                HoverIcon {
                                    glyph: "›"; tip: I18n.t("kanban.moveRight")
                                    visible: !col.isLast
                                    revealed: col.headerHovered
                                    onActivated: AppController.moveStatus(col.statusId, col.index + 1)
                                }
                                HoverIcon {
                                    glyph: "×"; tip: I18n.t("kanban.deleteColumn")
                                    danger: true
                                    visible: AppController.statuses.length > 1
                                    revealed: col.headerHovered
                                    onActivated: AppController.deleteStatus(col.statusId)
                                }

                                Rectangle {
                                    width: 22; height: 22; radius: 5
                                    color: addMA.containsMouse ? Theme.panel3 : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "+"
                                        color: addMA.containsMouse ? Theme.text : Theme.textDim
                                        font.pixelSize: 14
                                    }
                                    MouseArea {
                                        id: addMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.createInStatus(col.statusId)
                                    }
                                }
                            }
                            MouseArea {
                                id: headHover
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onClicked: (mouse) => { if (mouse.button === Qt.RightButton) colHeaderMenu.popup() }
                                z: -1
                            }

                            QQC.Menu {
                                id: colHeaderMenu
                                QQC.MenuItem { text: I18n.t("kanban.addTask"); onTriggered: root.createInStatus(col.statusId) }
                                QQC.MenuItem { text: I18n.t("kanban.rename"); onTriggered: { col.renaming = true; renameField.forceActiveFocus(); renameField.selectAll() } }
                                QQC.MenuItem { text: I18n.t("kanban.changeColorMenu"); onTriggered: colorPopup.openFor(col.statusId, col.statusColor, col) }
                                QQC.MenuSeparator {}
                                QQC.MenuItem { text: I18n.t("kanban.moveLeft");  enabled: !col.isFirst; onTriggered: AppController.moveStatus(col.statusId, col.index - 1) }
                                QQC.MenuItem { text: I18n.t("kanban.moveRight"); enabled: !col.isLast;  onTriggered: AppController.moveStatus(col.statusId, col.index + 1) }
                                QQC.MenuSeparator {}
                                QQC.MenuItem { text: I18n.t("kanban.deleteColumn"); enabled: AppController.statuses.length > 1; onTriggered: AppController.deleteStatus(col.statusId) }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Flickable {
                                id: bodyFlick
                                anchors.fill: parent
                                anchors.margins: 8
                                contentHeight: bodyCol.implicitHeight
                                clip: true
                                flickableDirection: Flickable.VerticalFlick
                                // pressDelay: 0 — same rationale as the
                                // outer hscroll: instant drag on cards.
                                pressDelay: 0

                                // Draggable thumb for tall columns — mouse wheel
                                // already scrolls (WheelHandler below); this adds
                                // a grabbable bar when a column overflows.
                                ScrollBar.vertical: ThinScrollBar {}

                                // Wheel scrolls this column vertically. When the column
                                // has no overflow or is already at the top/bottom edge,
                                // event.accepted = false lets the outer board scroll
                                // horizontally instead.
                                NumberAnimation {
                                    id: bodyAnim
                                    target: bodyFlick
                                    property: "contentY"
                                    duration: Theme.scaledMs(220)
                                    easing.type: Easing.OutCubic
                                }

                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: (event) => {
                                        const dy = event.angleDelta.y;
                                        if (dy === 0) return;
                                        const maxY = Math.max(0, bodyFlick.contentHeight - bodyFlick.height);
                                        if (maxY > 0) {
                                            const base = bodyAnim.running ? bodyAnim.to : bodyFlick.contentY;
                                            const newY = Math.max(0, Math.min(maxY, base - dy));
                                            if (newY !== base) {
                                                bodyAnim.from = bodyFlick.contentY;
                                                bodyAnim.to = newY;
                                                bodyAnim.restart();
                                                return;
                                            }
                                        }
                                        // No overflow or already at edge → pass through.
                                        root._scrollOuter(dy);
                                    }
                                }

                                Column {
                                    id: bodyCol
                                    width: bodyFlick.width
                                    spacing: 8

                                    Repeater {
                                        id: colRep
                                        // One proxy per column, so only the
                                        // cards that belong here are built. The
                                        // whole task model used to be the model
                                        // of every column's Repeater, with each
                                        // card hiding itself — N tasks × C
                                        // columns delegates, and a JS filter run
                                        // per card.
                                        model: colFilter

                                        TaskCard {
                                            id: tc
                                            required property string id
                                            required property string title
                                            required property string desc
                                            required property string priority
                                            required property string status
                                            required property var deadline
                                            required property string branch
                                            required property bool archived
                                            required property bool blockedStuck
                                            required property string prState
                                            required property int    prNumber
                                            required property string prUrl
                                            required property int    gitAhead
                                            required property int    gitBehind
                                            required property var    recentCommits
                                            required property int    trackedSeconds
                                            required property bool   isTiming
                                            required property string recurrence
                                            required property var    labels
                                            required property var    dueAt
                                            required property bool   hasTime
                                            required property var    ticket
                                            required property string searchText
                                            width: bodyCol.width

                                            readonly property var taskData: ({
                                                id: tc.id, title: tc.title, desc: tc.desc,
                                                priority: tc.priority, status: tc.status,
                                                deadline: tc.deadline, branch: tc.branch,
                                                archived: tc.archived, blockedStuck: tc.blockedStuck,
                                                prState: tc.prState, prNumber: tc.prNumber, prUrl: tc.prUrl,
                                                gitAhead: tc.gitAhead, gitBehind: tc.gitBehind,
                                                recentCommits: tc.recentCommits,
                                                trackedSeconds: tc.trackedSeconds, isTiming: tc.isTiming,
                                                recurrence: tc.recurrence,
                                                labels: tc.labels, dueAt: tc.dueAt, hasTime: tc.hasTime,
                                                ticket: tc.ticket, searchText: tc.searchText
                                            })
                                            // Which card a bare "O" acts on when
                                            // nothing is selected.
                                            onHoveredChanged: {
                                                if (hovered) root.hoveredTaskId = tc.id;
                                                else if (root.hoveredTaskId === tc.id) root.hoveredTaskId = "";
                                            }
                                            task: taskData
                                            cursored: root.cursorTaskId === tc.id
                                            scheduled: root.scheduleMap[tc.id] || ""
                                            // Clicking a card also puts the
                                            // keyboard cursor on it, so mouse
                                            // and keyboard never disagree about
                                            // where "here" is.
                                            onClicked: { root.cursorTaskId = tc.id; root.taskClicked(tc.id); }
                                            onRangeSelectRequested: (anchorId) => root._rangeSelect(anchorId)
                                        }
                                    }

                                    Text {
                                        visible: col.visibleCount === 0
                                        width: bodyCol.width
                                        topPadding: 12
                                        text: I18n.t("kanban.empty")
                                        color: Theme.textDim
                                        font.italic: true
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            DropArea {
                                id: colDrop
                                anchors.fill: parent

                                // The card the dragged one would land above,
                                // or "" for the end of the column. Recomputed
                                // as the pointer moves so the indicator and
                                // the drop agree.
                                property string beforeId: ""
                                property real indicatorY: 0

                                // Which card sits under `y` (in bodyCol's
                                // coordinates): the first whose midpoint the
                                // pointer is above. The dragged card is
                                // skipped — it is still in the column it came
                                // from, and counting it would make a one-place
                                // move look like no move at all.
                                function _slotAt(y, draggedId) {
                                    for (let i = 0; i < colRep.count; i++) {
                                        const item = colRep.itemAt(i);
                                        if (!item || !item.visible || item.taskId === draggedId) continue;
                                        if (y < item.y + item.height / 2) {
                                            return { id: item.taskId, y: item.y };
                                        }
                                    }
                                    return { id: "", y: bodyCol.height };
                                }

                                function _update(drag) {
                                    const src = drag.source;
                                    const p = bodyCol.mapFromItem(colDrop, drag.x, drag.y);
                                    const slot = _slotAt(p.y, src && src.taskId ? src.taskId : "");
                                    colDrop.beforeId = slot.id;
                                    colDrop.indicatorY = slot.y;
                                }

                                onEntered: (drag) => { col.dragOver = true; _update(drag); }
                                onPositionChanged: (drag) => _update(drag)
                                onExited: col.dragOver = false
                                onDropped: (drop) => {
                                    col.dragOver = false;
                                    const src = drop.source;
                                    if (!src || !src.taskId) return;
                                    if (AppController.isTaskSelected(src.taskId)
                                        && AppController.selectionCount > 1) {
                                        AppController.moveSelectedTasksTo(col.statusId, colDrop.beforeId);
                                    } else {
                                        AppController.moveTaskTo(src.taskId, col.statusId, colDrop.beforeId);
                                    }
                                    drop.accept(Qt.MoveAction);
                                }
                            }

                            // Where the card would land. Drawn over the body
                            // rather than between the cards so it does not
                            // shift them while the pointer moves.
                            Rectangle {
                                objectName: "drop-indicator"
                                visible: col.dragOver
                                x: 10
                                width: parent.width - 20
                                height: 2
                                radius: 1
                                color: Theme.accent
                                y: bodyFlick.y - bodyFlick.contentY + colDrop.indicatorY - 5
                                z: 20
                            }

                            // Right-click on empty body → Add task
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onClicked: (mouse) => { if (mouse.button === Qt.RightButton) bodyMenu.popup() }
                                z: -2
                            }
                            QQC.Menu {
                                id: bodyMenu
                                QQC.MenuItem { text: I18n.t("kanban.addTask"); onTriggered: root.createInStatus(col.statusId) }
                            }
                        }
                    }

                    // The column's own view of the task model: its status, plus
                    // whatever the filter bar and the search box say. Filtering
                    // in C++ is what keeps the delegate count proportional to
                    // the tasks rather than to tasks × columns.
                    TaskFilterProxy {
                        id: colFilter
                        sourceModel: AppController.tasks
                        status: col.statusId
                        showArchived: root.showArchived
                        searchText: root.searchText
                        priorities: root.activePriorities
                    }
                }
            }

            // "+ Add column" tile at the end of the row
            Rectangle {
                width: 200
                height: rowL.height
                radius: Theme.radius
                color: addColMA.containsMouse ? Theme.panel2 : "transparent"
                border.color: Theme.border
                border.width: 1

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "+"
                        color: addColMA.containsMouse ? Theme.text : Theme.textDim
                        font.pixelSize: 20
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.t("kanban.newColumn")
                        color: addColMA.containsMouse ? Theme.text : Theme.textDim
                        font.pixelSize: 12
                    }
                }
                MouseArea {
                    id: addColMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: addColumnPopup.open()
                }
            }
        }
    }

    // ── Popups ──────────────────────────────────────────────────────────────

    Popup {
        id: addColumnPopup
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        width: 360
        anchors.centerIn: Overlay.overlay
        background: Rectangle { radius: 12; color: Theme.panel; border.color: Theme.borderStrong; border.width: 1 }

        // Dimmed backdrop so the board stays visible behind the dialog.
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

        // Not `palette`: that is QQuickPopup's own property, which every
        // Control inside the popup resolves its colours through. Shadowing it
        // with an array of hex strings hands those controls an array where
        // they expect a palette.
        readonly property var swatches: [
            "#5cc2dd", "#8a8e98", "#9aa3b4", "#5aa9e6", "#dcb86b",
            "#e6624c", "#c07acf", "#6ec18a", "#6cc4b8", "#7da8d9"
        ]
        property color picked: swatches[0]

        function reset() { nameField.text = ""; picked = swatches[0] }
        onOpened: { reset(); nameField.forceActiveFocus() }

        contentItem: ColumnLayout {
            spacing: 10
            Item { Layout.preferredHeight: 4 }
            Text {
                Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("kanban.newColumn"); color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("kanban.colName").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            TextField {
                id: nameField
                Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
                placeholderText: "Review · QA · Stalled…"
                color: Theme.text
                placeholderTextColor: Theme.textDim
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                onAccepted: saveBtn.activate()
            }
            Text {
                Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("common.color").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            Row {
                Layout.leftMargin: 18; Layout.rightMargin: 18
                spacing: 6
                Repeater {
                    model: addColumnPopup.swatches
                    delegate: Rectangle {
                        required property string modelData
                        width: 24; height: 24; radius: 12
                        color: modelData
                        border.color: String(addColumnPopup.picked).toLowerCase() === modelData.toLowerCase() ? Theme.text : Theme.border
                        border.width: 2
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                   onClicked: addColumnPopup.picked = modelData }
                    }
                }
            }
            RowLayout {
                Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 16; Layout.topMargin: 8
                Item { Layout.fillWidth: true }
                PillButton {
                    text: I18n.t("common.cancel"); onClicked: addColumnPopup.close()
                }
                PillButton {
                    id: saveBtn
                    text: I18n.t("kanban.create"); primary: true
                    function activate() {
                        const n = nameField.text.trim();
                        if (n.length === 0) return;
                        AppController.addStatus(n, String(addColumnPopup.picked));
                        addColumnPopup.close();
                    }
                    onClicked: activate()
                }
            }
        }
    }

    Popup {
        id: colorPopup
        modal: false
        focus: true
        // Parented to the swatch it was opened from (see openFor), so "outside
        // the parent" is "outside the palette and the swatch" — a press anywhere
        // else closes it, while a press on the swatch falls through to openFor,
        // which toggles.
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        padding: 8
        background: Rectangle { radius: 10; color: Theme.panel; border.color: Theme.borderStrong; border.width: 1 }
        property string forStatusId: ""

        readonly property var swatches: addColumnPopup.swatches

        function openFor(id, currentColor, anchorItem) {
            const sameSwatch = colorPopup.opened && colorPopup.forStatusId === id;
            colorPopup.close();
            if (sameSwatch) return;
            forStatusId = id;
            if (anchorItem) {
                colorPopup.parent = anchorItem;
                const p = anchorItem.mapToItem(root, 0, 0);
                const wantX = Math.max(8, Math.min(p.x + anchorItem.width / 2 - 90,
                                                   root.width - colorPopup.width - 8));
                colorPopup.x = wantX - p.x;
                colorPopup.y = anchorItem.height + 6;
            }
            open();
        }

        contentItem: Grid {
            columns: 5
            spacing: 6
            Repeater {
                model: colorPopup.swatches
                delegate: Rectangle {
                    required property string modelData
                    width: 22; height: 22; radius: 11
                    color: modelData
                    border.color: Theme.border
                    border.width: 1
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            AppController.setStatusColor(colorPopup.forStatusId, modelData);
                            colorPopup.close();
                        }
                    }
                }
            }
        }
    }

    // ── Inline components ───────────────────────────────────────────────────

    component HoverIcon: Rectangle {
        id: hoverIcon
        property string glyph: ""
        property string tip: ""
        property bool danger: false
        // Faded out rather than hidden: the slot stays in the header layout, so
        // nothing shifts when the pointer arrives and the icon is already under
        // the cursor when it fades in. `enabled` keeps the invisible state from
        // being clickable.
        property bool revealed: false
        signal activated()
        Layout.preferredWidth: 20
        Layout.preferredHeight: 20
        radius: 4
        opacity: revealed ? 1 : 0
        enabled: revealed
        Behavior on opacity { NumberAnimation { duration: Theme.scaledMs(90) } }
        color: hoverIconMA.containsMouse ? (danger ? Theme.withAlpha(Theme.p0, 0.16) : Theme.panel3)
                                         : "transparent"
        border.color: hoverIconMA.containsMouse ? (danger ? Theme.p0 : Theme.border) : "transparent"
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: hoverIcon.glyph
            color: hoverIconMA.containsMouse ? (hoverIcon.danger ? Theme.p0 : Theme.text) : Theme.textMuted
            font.pixelSize: hoverIcon.glyph === "×" ? 13 : 12
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: hoverIconMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hoverIcon.activated()
            ToolTip.visible: containsMouse && hoverIcon.tip.length > 0
            ToolTip.text: hoverIcon.tip
            ToolTip.delay: 400
        }
    }

    // ── Board-level empty state ──
    // Shown when the profile has no tasks at all (e.g. right after "Start
    // fresh"). Non-interactive so the column "+" affordances stay reachable.
    property int _boardTotal: AppController.tasks.rowCount()
    Connections {
        target: AppController.tasks
        function onModelReset()   { root._boardTotal = AppController.tasks.rowCount() }
        function onRowsInserted() { root._boardTotal = AppController.tasks.rowCount() }
        function onRowsRemoved()  { root._boardTotal = AppController.tasks.rowCount() }
    }
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 360)
        spacing: 8
        visible: root._boardTotal === 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.t("board.empty.title")
            color: Theme.text
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: I18n.t("board.empty.hint")
            color: Theme.textMuted
            font.pixelSize: 12
        }
    }
}
