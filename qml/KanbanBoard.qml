import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

Item {
    id: root
    property string searchText: ""
    // How every column is ordered. "manual" is the board's own rank, which is
    // what a drag writes; the others are read-only views over the same cards,
    // so switching back to manual restores the order the user arranged rather
    // than whatever the last sort left behind.
    property string sortMode: "manual"
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

        function onStatusesChanged() { root._syncColumns(); }

        // Sidebar Blocked / Code Review buttons jump the board to a column.
        function onFocusedStatusChanged() {
            if (AppController.focusedStatus.length > 0) root.focusColumn(AppController.focusedStatus);
        }
    }

    // ── Columns, updated in place (TASKS-19) ──────────────────────────
    // AppController.statuses is a plain list, and a Repeater over a list
    // rebuilds every delegate whenever it changes: renaming one column threw
    // away all of them, with their scroll positions. This model is patched
    // row by row, so an edit touches only the column it is about.
    ListModel { id: colModel }
    function _syncColumns() {
        const sts = AppController.statuses;
        const want = {};
        for (let i = 0; i < sts.length; i++) want[sts[i].id] = true;
        for (let i = colModel.count - 1; i >= 0; i--)
            if (!want[colModel.get(i).sid]) colModel.remove(i);
        for (let i = 0; i < sts.length; i++) {
            const s = sts[i];
            const row = { sid: String(s.id), sname: String(s.name || ""), scolor: String(s.color || ""), swip: Number(s.wip || 0) };
            let at = -1;
            for (let j = i; j < colModel.count; j++) if (colModel.get(j).sid === row.sid) { at = j; break; }
            if (at < 0) { colModel.insert(i, row); continue; }
            if (at !== i) colModel.move(at, i, 1);
            const cur = colModel.get(i);
            if (cur.sname !== row.sname) colModel.setProperty(i, "sname", row.sname);
            if (cur.scolor !== row.scolor) colModel.setProperty(i, "scolor", row.scolor);
            if (cur.swip !== row.swip) colModel.setProperty(i, "swip", row.swip);
        }
    }

    // ── Collapsed columns (TASKS-32) ───────────────────────────────────
    // A column folded to a narrow strip keeps its name and count and gives
    // its width to the others. Remembered per column in the UI settings.
    property var collapsed: ({})
    function _loadCollapsed() {
        let s = {};
        try { s = JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { s = {}; }
        const ids = Array.isArray(s.boardCollapsed) ? s.boardCollapsed : [];
        const out = {};
        for (let i = 0; i < ids.length; i++) out[ids[i]] = true;
        root.collapsed = out;
    }
    function toggleCollapsed(statusId) {
        const next = Object.assign({}, root.collapsed);
        if (next[statusId]) delete next[statusId]; else next[statusId] = true;
        root.collapsed = next;
        let s = {};
        try { s = JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { s = {}; }
        s.boardCollapsed = Object.keys(next);
        AppController.appSettingsJson = JSON.stringify(s);
    }
    // Fold or unfold the column the keyboard cursor is in.
    function toggleCursorColumn() {
        const cols = _visibleByColumn();
        const pos = _cursorPos(cols);
        let c = pos ? pos.col : -1;
        if (c < 0 && colRepeater.count > 0) c = 0;
        const col = c >= 0 ? colRepeater.itemAt(c) : null;
        if (col) root.toggleCollapsed(col.statusId);
    }

    // True while any card's menu is up; Main.qml holds the board keys back.
    property int _openCardMenus: 0
    readonly property bool cardMenuOpen: _openCardMenus > 0
    // One of the board's own dialogs or menus is up (new column, WIP limit,
    // delete confirmation, a card menu). Main.qml keeps Ctrl+Z from acting
    // on the board behind it.
    readonly property bool dialogOpen: cardMenuOpen || addColumnPopup.opened || wipPopup.opened || archivePopup.opened
                                       || confirmDelete.opened || colorPopup.opened

    // One source of truth for the column width. focusColumn() scrolls by
    // index × width, so a literal here and a different literal in the delegate
    // silently put the wrong column on screen.
    readonly property int columnWidth: 280
    readonly property int foldedWidth: 44

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
        root._syncColumns();
        root._loadCollapsed();
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
    // The ring is drawn only once the keyboard has moved the cursor. A click
    // still puts the cursor on the card (so J/K carry on from there), but a
    // ring left behind by a mouse click read as the card being stuck
    // selected after its editor closed.
    property bool cursorVisible: false
    function clearCursor() {
        root.cursorTaskId = "";
        root.cursorVisible = false;
    }
    function clearSelectionAndCursor() {
        if (AppController.selectionCount > 0) AppController.clearSelection();
        root.clearCursor();
    }

    // Visible ids per column, in board order. The same walk _flatVisibleIds()
    // does, but keeping the column structure that left/right needs.
    function _visibleByColumn() {
        const cols = [];
        for (let c = 0; c < colRepeater.count; c++) {
            const col = colRepeater.itemAt(c);
            if (!col || !col.taskFilter) { cols.push({ statusId: "", ids: [] }); continue; }
            // A folded column shows no cards, so the cursor walks past it.
            cols.push({ statusId: col.statusId, ids: col.folded ? [] : col.taskFilter.ids() });
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

    // ── Selecting from the keyboard (APP-128) ─────────────────────────
    // Shift+Up/Down grows a range from an anchor, the card the run started
    // on, over whatever was selected before it; walking back shrinks the
    // range again. Any other cursor move (plain arrows, a click, a column
    // change) ends the run.
    property string _selAnchor: ""
    property var _selBase: []
    property bool _extending: false
    onCursorTaskIdChanged: if (!root._extending) root._selAnchor = ""
    function _placeCursor(id) {
        root._extending = true;
        root.cursorTaskId = id;
        root._extending = false;
    }
    function _union(a, b) {
        const out = a.slice();
        for (const id of b) if (out.indexOf(id) < 0) out.push(id);
        return out;
    }

    function extendSelection(dy) {
        root.cursorVisible = true;
        const cols = _visibleByColumn();
        const pos = _cursorPos(cols);
        if (!pos) { root.cursorTaskId = _firstVisible(cols); return; }
        const ids = cols[pos.col].ids;
        if (root._selAnchor === "" || ids.indexOf(root._selAnchor) < 0) {
            root._selAnchor = root.cursorTaskId;
            root._selBase = AppController.selectedTaskIds.filter((id) => id !== root.cursorTaskId);
        }
        const r = Math.max(0, Math.min(ids.length - 1, pos.row + dy));
        root._placeCursor(ids[r]);
        const a = ids.indexOf(root._selAnchor);
        const range = ids.slice(Math.min(a, r), Math.max(a, r) + 1);
        AppController.setSelectedTaskIds(root._union(root._selBase, range));
    }

    // Shift+Left/Right: the whole column the cursor is in joins the
    // selection, and the cursor steps to the next column with cards, so a
    // second press takes that one too.
    function selectColumnAndStep(dx) {
        root.cursorVisible = true;
        const cols = _visibleByColumn();
        const pos = _cursorPos(cols);
        if (!pos) { root.cursorTaskId = _firstVisible(cols); return; }
        AppController.setSelectedTaskIds(root._union(AppController.selectedTaskIds, cols[pos.col].ids));
        for (let c = pos.col + dx; c >= 0 && c < cols.length; c += dx) {
            if (cols[c].ids.length > 0) {
                root.cursorTaskId = cols[c].ids[Math.min(pos.row, cols[c].ids.length - 1)];
                return;
            }
        }
    }

    // Ctrl+Left/Right: the selection, when there is one, goes to the column
    // beside the cursor's (or beside the first selected card's); otherwise
    // the cursor's card moves, as Shift+H/L always did.
    function moveSelectionOrCard(dx) {
        if (AppController.selectionCount === 0) { root.moveCursorCard(dx, 0); return; }
        const cols = _visibleByColumn();
        let from = _cursorPos(cols);
        if (!from || !AppController.isTaskSelected(root.cursorTaskId)) {
            const first = AppController.selectedTaskIds[0];
            from = null;
            for (let c = 0; c < cols.length && !from; c++)
                if (cols[c].ids.indexOf(first) >= 0) from = { col: c, row: 0 };
        }
        if (!from) return;
        const c = from.col + dx;
        if (c < 0 || c >= cols.length || !cols[c].statusId) return;
        AppController.moveSelectedTasksToStatus(cols[c].statusId);
    }

    function moveCursor(dx, dy) {
        root.cursorVisible = true;
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
        root.cursorVisible = true;
        const cols = _visibleByColumn();
        if (!_cursorPos(cols)) { root.cursorTaskId = _firstVisible(cols); return; }
        if (root.cursorTaskId) root.taskClicked(root.cursorTaskId);
    }

    // The card the next key acts on: the cursor's, else the single selected
    // one, else the one under the pointer.
    function _actionCardId() {
        const cols = _visibleByColumn();
        if (root.cursorTaskId && _cursorPos(cols)) return root.cursorTaskId;
        if (AppController.selectionCount === 1) return AppController.selectedTaskIds[0];
        return root.hoveredTaskId || "";
    }
    function _cardItem(id) {
        for (let c = 0; c < colRepeater.count; c++) {
            const col = colRepeater.itemAt(c);
            if (!col || !col.taskList) continue;
            const list = col.taskList;
            const ids = col.taskFilter.ids();
            const row = ids.indexOf(id);
            if (row < 0) continue;
            list.positionViewAtIndex(row, ListView.Contain);
            list.forceLayout();
            return list.itemAtIndex(row);
        }
        return null;
    }
    // M (and the Menu key): the card menu for the card the keyboard is on.
    function openCursorMenu() {
        const id = root._actionCardId();
        if (!id) { root.moveCursor(0, 0); return; }
        root.cursorTaskId = id;
        root.cursorVisible = true;
        const card = root._cardItem(id);
        if (card && card.openMenu) card.openMenu();
    }
    // E: archive the selection, or the cursor's card when nothing is selected.
    function archiveCursor() {
        if (AppController.selectionCount > 0) { AppController.setSelectedTasksArchived(true); return; }
        const id = root._actionCardId();
        if (!id) return;
        // Keep the cursor on the board: step to a neighbour first.
        const cols = _visibleByColumn();
        const pos = _cursorPos(cols);
        if (pos && id === root.cursorTaskId) {
            const ids = cols[pos.col].ids;
            root.cursorTaskId = pos.row + 1 < ids.length ? ids[pos.row + 1] : (pos.row > 0 ? ids[pos.row - 1] : "");
        }
        AppController.setArchived(id, true);
    }

    function toggleCursorSelection() {
        root.cursorVisible = true;
        const cols = _visibleByColumn();
        if (!_cursorPos(cols)) { root.cursorTaskId = _firstVisible(cols); return; }
        if (root.cursorTaskId) AppController.toggleTaskSelection(root.cursorTaskId);
    }

    // Move the card under the cursor. Vertically it swaps with its neighbour;
    // horizontally it changes column, landing at the same depth.
    //
    // Under a sort the column order on screen is not the manual order: Shift+K
    // under "Priority" moved nothing visible and rewrote the manual order
    // behind it (TASKS-1, audit 2026-09-30). A sorted column has no position
    // to move to, so a vertical move says so and a column change keeps the
    // card where the sort puts it - the same rule as a drop.
    function moveCursorCard(dx, dy) {
        root.cursorVisible = true;
        const cols = _visibleByColumn();
        const pos = _cursorPos(cols);
        if (!pos) { root.cursorTaskId = _firstVisible(cols); return; }
        const id = root.cursorTaskId;
        const manual = root.sortMode === "manual";

        if (dy !== 0 && !manual) {
            AppController.showToast(I18n.t("board.sorted.noReorder"));
            return;
        }
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
        const beforeId = manual && pos.row < destIds.length ? destIds[pos.row] : "";
        AppController.moveTaskTo(id, cols[c].statusId, beforeId);
    }

    // Flat ordered list of visible task ids across the entire board, column
    // by column in render order, top-to-bottom inside each column. Used by
    // selectAllVisible() and shift-range select.
    function _flatVisibleIds() {
        const out = [];
        for (let c = 0; c < colRepeater.count; c++) {
            const col = colRepeater.itemAt(c);
            if (!col || !col.taskFilter) continue;
            const ids = col.taskFilter.ids();
            for (let i = 0; i < ids.length; i++) out.push(ids[i]);
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
        objectName: "board-hscroll"
        anchors.fill: parent
        anchors.leftMargin: Theme.sp2xl
        anchors.rightMargin: Theme.sp2xl
        anchors.topMargin: Theme.spXl
        anchors.bottomMargin: Theme.sp2xl
        contentWidth: rowL.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true
        // The columns that do not fit sit off to the right with nothing to
        // say so but a card cut in half (design audit DES-6): while the board
        // overflows, its scrollbar stays in view.
        ScrollBar.horizontal: ThinScrollBar {
            objectName: "board-hscrollbar"
            policy: hscroll.contentWidth > hscroll.width ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
        }
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
        // A click on empty board (between or below the columns) lets go of
        // the selection and the keyboard cursor. Cards take their own clicks
        // first, so this only sees the empty space.
        TapHandler {
            onTapped: root.clearSelectionAndCursor()
        }

        Row {
            id: rowL
            height: hscroll.height
            spacing: Theme.spXl

            Repeater {
                id: colRepeater
                model: colModel

                Rectangle {
                    id: col
                    required property string sid
                    required property string sname
                    required property string scolor
                    required property int swip
                    required property int index
                    readonly property string statusId: sid
                    readonly property string statusName: sname
                    readonly property color statusColor: scolor
                    readonly property bool folded: !!root.collapsed[col.statusId]
                    readonly property alias taskList: bodyFlick
                    readonly property alias taskFilter: colFilter
                    property bool dragOver: false
                    readonly property int visibleCount: colFilter.count
                    // Advisory work-in-progress limit. 0 = none. Over the
                    // limit the badge turns, and that is all it does: a hard
                    // cap would make a drag silently do nothing, which reads
                    // as a bug rather than as a rule.
                    readonly property int wipLimit: col.swip
                    readonly property bool overWip: col.wipLimit > 0 && col.visibleCount > col.wipLimit
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
                    // The icons also show while the keyboard is on one of them
                    // (design audit DES-19): hidden at rest, they stay on the
                    // Tab path, as IconButton's do.
                    readonly property bool headerKeyFocus: moveLeftIcon.keyFocused || moveRightIcon.keyFocused
                                                           || deleteIcon.keyFocused || foldIcon.keyFocused
                    readonly property bool headerRevealed: col.headerHovered || col.headerKeyFocus
                    // Briefly emphasised when the sidebar Blocked / Code Review
                    // button jumps focus to this column.
                    readonly property bool focusPulse: root._focusPulseStatus === col.statusId

                    width: col.folded ? root.foldedWidth : root.columnWidth
                    height: rowL.height
                    radius: Theme.radius
                    color: Theme.panel
                    border.color: (dragOver || focusPulse) ? Theme.accent : Theme.border
                    border.width: focusPulse ? 2 : 1
                    clip: true
                    Behavior on border.color { ColorAnimation { duration: Theme.scaledMs(180) } }

                    // Folded: the name runs down the strip, with the count; a
                    // click (or Z on the board) opens it again.
                    Item {
                        objectName: "column-folded"
                        anchors.fill: parent
                        visible: col.folded
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Theme.spLg
                            spacing: Theme.spLg
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 8; height: 8; radius: 4
                                color: col.statusColor
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: col.visibleCount
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsSm
                            }
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: foldedName.implicitHeight
                                height: foldedName.implicitWidth
                                Text {
                                    id: foldedName
                                    anchors.centerIn: parent
                                    rotation: 90
                                    text: col.statusName
                                    color: Theme.text
                                    font.pixelSize: Theme.fsMd
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                        ClickArea {
                            objectName: "column-expand"
                            enabled: col.folded
                            label: I18n.t("kanban.expand") + " " + col.statusName
                            tip: I18n.t("kanban.expand")
                            shortcutId: "board.collapseColumn"
                            onActivated: root.toggleCollapsed(col.statusId)
                        }
                        DropArea {
                            anchors.fill: parent
                            onDropped: (drop) => {
                                const src = drop.source;
                                if (!src || !src.taskId) return;
                                AppController.moveTaskTo(src.taskId, col.statusId, "");
                                drop.accept(Qt.MoveAction);
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        visible: !col.folded

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            color: Theme.panel2
                            HoverHandler { onHoveredChanged: col.headerHovered = hovered }
                            // The header's menu from the keyboard: Menu or
                            // Shift+F10 on any of its buttons, which pass the
                            // key up to here.
                            Keys.onMenuPressed: colHeaderMenu.popup()
                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) {
                                    colHeaderMenu.popup();
                                    event.accepted = true;
                                }
                            }
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 1; color: Theme.border
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spXl; anchors.rightMargin: Theme.spMd
                                spacing: Theme.spMd
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
                                        radius: Theme.radiusSm
                                        color: swatchMA.hovered ? Theme.panel3 : "transparent"
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8; height: 8; radius: 4
                                        color: col.statusColor
                                    }
                                    ClickArea {
                                        id: swatchMA
                                        objectName: "column-color"
                                        label: I18n.t("kanban.changeColor")
                                        onActivated: colorPopup.openFor(col.statusId, col.statusColor, colorSwatch)
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    Text {
                                        id: colName
                                        objectName: "column-name"
                                        visible: !col.renaming
                                        anchors.verticalCenter: parent.verticalCenter
                                        // The name as the user wrote it. Uppercase with
                                        // tracking shouted across seven columns and cut
                                        // "In progress" to "IN PROGR…" on a 1680px window.
                                        text: col.statusName
                                        color: Theme.text
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.fsMd
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
                                        background: Rectangle { radius: Theme.radiusSm; color: Theme.panel; border.color: Theme.accent; border.width: 1 }
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.fsMd
                                        font.weight: Font.DemiBold
                                        selectByMouse: true
                                        onAccepted: { AppController.renameStatus(col.statusId, text.trim()); col.renaming = false }
                                        onActiveFocusChanged: if (!activeFocus && col.renaming) { AppController.renameStatus(col.statusId, text.trim()); col.renaming = false }
                                        // Put the name back before letting go: hiding the
                                        // field blurs it, and the blur handler above commits
                                        // whatever is in it while renaming is still set.
                                        Keys.onEscapePressed: { text = col.statusName; col.renaming = false }
                                    }
                                }
                                Rectangle {
                                    id: cntPill
                                    radius: Theme.radiusPill
                                    color: col.overWip ? Theme.withAlpha(Theme.danger, 0.18) : Theme.panel3
                                    border.color: col.overWip ? Theme.danger : "transparent"
                                    border.width: 1
                                    implicitWidth: cntT.implicitWidth + 14
                                    implicitHeight: 18
                                    Text {
                                        id: cntT; anchors.centerIn: parent
                                        text: col.wipLimit > 0
                                            ? col.visibleCount + "/" + col.wipLimit
                                            : col.visibleCount
                                        color: col.overWip ? Theme.danger : Theme.textDim
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fsSm
                                        font.weight: col.overWip ? Font.DemiBold : Font.Normal
                                    }
                                    QQC.ToolTip.visible: col.overWip && wipHover.hovered
                                    QQC.ToolTip.text: I18n.t("kanban.wip.over").arg(col.statusName).arg(col.wipLimit)
                                    HoverHandler { id: wipHover }
                                }

                                Rectangle {
                                    width: 22; height: 22; radius: Theme.radiusSm
                                    color: addMA.hovered || addMA.keyboardFocused ? Theme.panel3 : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "+"
                                        color: addMA.hovered || addMA.keyboardFocused ? Theme.text : Theme.textDim
                                        font.pixelSize: Theme.fsLg
                                    }
                                    ClickArea {
                                        id: addMA
                                        objectName: "column-add"
                                        label: I18n.t("kanban.addTask")
                                        onActivated: root.createInStatus(col.statusId)
                                    }
                                }
                            }
                            // Move-left / Move-right / Delete / Fold, laid over the
                            // end of the name while the pointer is on the header
                            // (design audit DES-6). They used to hold four slots
                            // in the row even while hidden, which left the name
                            // about 100px: "To Do" read "To …" and "К выполнению"
                            // "К вып…" on a 1600px window. Laid over, the name
                            // gets the whole width at rest and still nothing
                            // reflows when the icons fade in. `visible` carries
                            // only the structural conditions.
                            Rectangle {
                                objectName: "column-hover-icons"
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spMd + 22 + Theme.spMd + cntPill.width + Theme.spMd
                                width: hoverIcons.implicitWidth + Theme.spSm
                                height: hoverIcons.implicitHeight
                                color: Theme.panel2
                                opacity: col.headerRevealed ? 1 : 0
                                visible: !col.renaming
                                z: 2
                                Row {
                                    id: hoverIcons
                                    anchors.right: parent.right
                                    spacing: Theme.spXs
                                    HoverIcon {
                                        id: moveLeftIcon
                                        objectName: "column-move-left"
                                        glyph: "‹"; tip: I18n.t("kanban.moveLeft")
                                        visible: !col.isFirst
                                        revealed: col.headerRevealed
                                        onActivated: AppController.moveStatus(col.statusId, col.index - 1)
                                    }
                                    HoverIcon {
                                        id: moveRightIcon
                                        objectName: "column-move-right"
                                        glyph: "›"; tip: I18n.t("kanban.moveRight")
                                        visible: !col.isLast
                                        revealed: col.headerRevealed
                                        onActivated: AppController.moveStatus(col.statusId, col.index + 1)
                                    }
                                    HoverIcon {
                                        id: deleteIcon
                                        objectName: "column-delete"
                                        glyph: "×"; tip: I18n.t("kanban.deleteColumn")
                                        danger: true
                                        visible: AppController.statuses.length > 1
                                        revealed: col.headerRevealed
                                        onActivated: root.requestDeleteColumn(col.statusId, col.statusName)
                                    }
                                    HoverIcon {
                                        id: foldIcon
                                        objectName: "column-fold"
                                        glyph: "⇤"; tip: I18n.t("kanban.collapse")
                                        shortcutId: "board.collapseColumn"
                                        revealed: col.headerRevealed
                                        onActivated: root.toggleCollapsed(col.statusId)
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

                            AppMenu {
                                id: colHeaderMenu
                                AppMenuItem { text: I18n.t("kanban.addTask"); onTriggered: root.createInStatus(col.statusId) }
                                AppMenuItem { text: I18n.t("kanban.rename"); onTriggered: { col.renaming = true; renameField.forceActiveFocus(); renameField.selectAll() } }
                                AppMenuItem { text: I18n.t("kanban.changeColorMenu"); onTriggered: colorPopup.openFor(col.statusId, col.statusColor, col) }
                                AppMenuItem { text: I18n.t("kanban.wip.set"); onTriggered: wipPopup.openFor(col.statusId, col.statusName, col.wipLimit, col) }
                                AppMenuItem { objectName: "col-archive-menu"; text: I18n.t("kanban.archive.set"); onTriggered: archivePopup.openFor(col.statusId, col.statusName) }
                                AppMenuItem { text: I18n.t("kanban.collapse"); onTriggered: root.toggleCollapsed(col.statusId) }
                                // A "doing" column books a focus block for a card
                                // that enters it, like In Progress (always on).
                                AppMenuItem {
                                    enabled: col.statusId !== "prog"
                                    text: (AppController.statuses, AppController.isDoingStatus(col.statusId))
                                          ? I18n.t("kanban.doing.off") : I18n.t("kanban.doing.on")
                                    onTriggered: AppController.setStatusDoing(col.statusId, !AppController.isDoingStatus(col.statusId))
                                }
                                AppMenuSeparator {}
                                AppMenuItem { text: I18n.t("kanban.moveLeft");  enabled: !col.isFirst; onTriggered: AppController.moveStatus(col.statusId, col.index - 1) }
                                AppMenuItem { text: I18n.t("kanban.moveRight"); enabled: !col.isLast;  onTriggered: AppController.moveStatus(col.statusId, col.index + 1) }
                                AppMenuSeparator {}
                                AppMenuItem { danger: true; text: I18n.t("kanban.deleteColumn"); enabled: AppController.statuses.length > 1; onTriggered: root.requestDeleteColumn(col.statusId, col.statusName) }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // A ListView, not a Repeater in a Flickable: only
                            // the cards on screen are built. A board of 2000
                            // tasks held 580 MB of delegates the other way.
                            ListView {
                                id: bodyFlick
                                objectName: "column-list"
                                anchors.fill: parent
                                anchors.margins: Theme.spMd
                                clip: true
                                spacing: Theme.spMd
                                // A couple of cards past each edge. Every card
                                // in the cache is rebound when a filter change
                                // reshuffles the column, and with pooled
                                // delegates scrolling no longer needs a deep
                                // pre-built margin to stay smooth.
                                cacheBuffer: 200
                                boundsBehavior: Flickable.StopAtBounds
                                flickableDirection: Flickable.VerticalFlick
                                // One proxy per column, so only the cards that
                                // belong here are in the model at all.
                                model: colFilter
                                // A search or filter change swaps most of the
                                // rows in every column at once; building a
                                // fresh TaskCard for each was ~2.5 ms a card
                                // and ~300 ms a keystroke at 3k tasks. Pooled
                                // delegates are rebound instead.
                                reuseItems: true
                                // pressDelay: 0 — same rationale as the
                                // outer hscroll: instant drag on cards.
                                pressDelay: 0

                                // Draggable thumb for tall columns — mouse wheel
                                // already scrolls (WheelHandler below); this adds
                                // a grabbable bar when a column overflows.
                                ScrollBar.vertical: ThinScrollBar {}

                                // The empty part of a column, like the empty
                                // board around it.
                                TapHandler {
                                    onTapped: root.clearSelectionAndCursor()
                                }

                                // Wheel scrolls this column vertically. Only a column
                                // with nothing to scroll hands the wheel to the board,
                                // which scrolls sideways. At the top or bottom edge the
                                // column keeps it: passing it on there sent the whole
                                // board sliding the moment a long column ran out.
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
                                        // A sideways swipe, or Shift+wheel, is for the board.
                                        const sideways = event.angleDelta.x !== 0
                                                         || (event.modifiers & Qt.ShiftModifier);
                                        if (sideways) { root._scrollOuter(event.angleDelta.x || dy); return; }
                                        if (dy === 0) return;
                                        const maxY = Math.max(0, bodyFlick.contentHeight - bodyFlick.height);
                                        if (maxY <= 0) { root._scrollOuter(dy); return; }
                                        const base = bodyAnim.running ? bodyAnim.to : bodyFlick.contentY;
                                        const newY = Math.max(0, Math.min(maxY, base - dy));
                                        if (newY === base) return;
                                        bodyAnim.from = bodyFlick.contentY;
                                        bodyAnim.to = newY;
                                        bodyAnim.restart();
                                    }
                                }

                                delegate: TaskCard {
                                            id: tc
                                            required property string id
                                            required property string title
                                            required property string desc
                                            required property string priority
                                            required property string status
                                            required property var checklist
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
                                            required property bool   dueHasTime
                                            required property var    scheduledAt
                                            required property bool   scheduledHasTime
                                            required property var    ticket
                                            required property string searchText
                                            required property int    attachmentCount
                                            width: bodyFlick.width
                                            // A pooled card waits, culled but still
                                            // a child of the list, until a row needs
                                            // it: hide it so it is not taken for a
                                            // card on the board (hover, focus, the
                                            // tree walks in tests), and drop the menu
                                            // it opened for another task.
                                            ListView.onPooled: {
                                                tc.releaseMenu();
                                                tc.visible = false;
                                            }
                                            ListView.onReused: tc.visible = true
                                            // A card dropped into another column
                                            // leaves this one while it is still
                                            // lifted into the drag layer. Hold its
                                            // removal until the drag lets go, or the
                                            // pool would hand a card parented to the
                                            // drag layer to another row.
                                            ListView.delayRemove: tc.Drag.active

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
                                                labels: tc.labels, dueAt: tc.dueAt, dueHasTime: tc.dueHasTime,
                                                scheduledAt: tc.scheduledAt, scheduledHasTime: tc.scheduledHasTime,
                                                ticket: tc.ticket, searchText: tc.searchText,
                                                checklist: tc.checklist, attachmentCount: tc.attachmentCount
                                            })
                                            // Which card a bare "O" acts on when
                                            // nothing is selected.
                                            onHoveredChanged: {
                                                if (hovered) root.hoveredTaskId = tc.id;
                                                else if (root.hoveredTaskId === tc.id) root.hoveredTaskId = "";
                                            }
                                            task: taskData
                                            cursored: root.cursorVisible && root.cursorTaskId === tc.id
                                            dragLayer: boardDragLayer
                                            scheduled: root.scheduleMap[tc.id] || ""
                                            // Clicking a card also puts the
                                            // keyboard cursor on it, so mouse
                                            // and keyboard never disagree about
                                            // where "here" is.
                                            onClicked: {
                                                root.cursorTaskId = tc.id;
                                                root.cursorVisible = false;
                                                root.taskClicked(tc.id);
                                            }
                                            onRangeSelectRequested: (anchorId) => root._rangeSelect(anchorId)
                                            onMenuOpenChanged: root._openCardMenus += menuOpen ? 1 : -1
                                            Component.onDestruction: if (menuOpen) root._openCardMenus--
                                        }

                                Text {
                                    visible: col.visibleCount === 0
                                    width: bodyFlick.width
                                    topPadding: Theme.spXl
                                    text: I18n.t("kanban.empty")
                                    color: Theme.textDim
                                    font.italic: true
                                    font.pixelSize: Theme.fsSm
                                    horizontalAlignment: Text.AlignHCenter
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

                                // Which card sits under `y` (in the list's content
                                // coordinates): the first whose midpoint the
                                // pointer is above. The dragged card is
                                // skipped — it is still in the column it came
                                // from, and counting it would make a one-place
                                // move look like no move at all.
                                function _slotAt(y, draggedId) {
                                    // Cards off screen are not built; the
                                    // ones around the pointer always are, so
                                    // skipping the unbuilt ones is safe.
                                    for (let i = 0; i < bodyFlick.count; i++) {
                                        const item = bodyFlick.itemAtIndex(i);
                                        if (!item) continue;
                                        if (item.taskId === draggedId) continue;
                                        if (y < item.y + item.height / 2) {
                                            return { id: item.taskId, y: item.y };
                                        }
                                    }
                                    return { id: "", y: bodyFlick.contentHeight };
                                }

                                function _update(drag) {
                                    const src = drag.source;
                                    const p = bodyFlick.contentItem.mapFromItem(colDrop, drag.x, drag.y);
                                    const slot = _slotAt(p.y, src && src.taskId ? src.taskId : "");
                                    colDrop.beforeId = slot.id;
                                    colDrop.indicatorY = slot.y;
                                }

                                // Files from a file manager are for the card
                                // under the pointer (TaskCard attaches them),
                                // not a move: let them through.
                                onEntered: (drag) => {
                                    if (drag.hasUrls && !(drag.source && drag.source["taskId"])) { drag.accepted = false; return; }
                                    col.dragOver = true; _update(drag);
                                }
                                onPositionChanged: (drag) => _update(drag)
                                onExited: col.dragOver = false
                                onDropped: (drop) => {
                                    col.dragOver = false;
                                    const src = drop.source;
                                    if (!src || !src.taskId) return;
                                    // Under a sort, a drop still changes the
                                    // column — it just cannot choose where in
                                    // it the card lands. A drop back into its
                                    // own column is no move at all: with no
                                    // anchor it used to send the card to the
                                    // end of the manual order (TASKS-1).
                                    const manual = root.sortMode === "manual";
                                    const target = manual ? colDrop.beforeId : "";
                                    if (AppController.isTaskSelected(src.taskId)
                                        && AppController.selectionCount > 1) {
                                        if (manual) AppController.moveSelectedTasksTo(col.statusId, target);
                                        else AppController.moveSelectedTasksToStatus(col.statusId);
                                    } else if (manual || AppController.taskById(src.taskId).status !== col.statusId) {
                                        AppController.moveTaskTo(src.taskId, col.statusId, target);
                                    }
                                    drop.accept(Qt.MoveAction);
                                }
                            }

                            // Where the card would land. Drawn over the body
                            // rather than between the cards so it does not
                            // shift them while the pointer moves.
                            Rectangle {
                                objectName: "drop-indicator"
                                // A drop cannot choose a position while a sort
                                // is deciding it, so the line would be a lie.
                                visible: col.dragOver && root.sortMode === "manual"
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
                            AppMenu {
                                id: bodyMenu
                                AppMenuItem { text: I18n.t("kanban.addTask"); onTriggered: root.createInStatus(col.statusId) }
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
                        statuses: AppController.statuses
                        showArchived: root.showArchived
                        searchText: root.searchText
                        priorities: root.activePriorities
                        sortMode: root.sortMode
                        today: AppController.today
                    }
                }
            }

            // "+ Add column" tile at the end of the row
            Rectangle {
                width: 200
                height: rowL.height
                radius: Theme.radius
                color: addColMA.hovered || addColMA.keyboardFocused ? Theme.panel2 : "transparent"
                border.color: Theme.border
                border.width: 1

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spSm
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "+"
                        color: addColMA.hovered || addColMA.keyboardFocused ? Theme.text : Theme.textDim
                        font.pixelSize: Theme.fsXl
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.t("kanban.newColumn")
                        color: addColMA.hovered || addColMA.keyboardFocused ? Theme.text : Theme.textDim
                        font.pixelSize: Theme.fsMd
                    }
                }
                ClickArea {
                    id: addColMA
                    objectName: "board-add-column"
                    label: I18n.t("kanban.newColumn")
                    showTip: false
                    onActivated: addColumnPopup.open()
                }
            }
        }
    }

    // ── Popups ──────────────────────────────────────────────────────────────

    Popup {
        id: addColumnPopup
        objectName: "add-column-popup"
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        width: 360
        anchors.centerIn: Overlay.overlay
        background: Rectangle { radius: Theme.radiusXl; color: Theme.panel; border.color: Theme.borderStrong; border.width: 1 }

        // Dimmed backdrop so the board stays visible behind the dialog.
        Overlay.modal: Rectangle { color: Theme.scrim }

        // Not `palette`: that is QQuickPopup's own property, which every
        // Control inside the popup resolves its colours through. Shadowing it
        // with an array of hex strings hands those controls an array where
        // they expect a palette.
        readonly property var swatches: Theme.swatches
        property color picked: swatches[0]

        function reset() { nameField.text = ""; picked = swatches[0] }
        onOpened: { reset(); nameField.forceActiveFocus() }

        contentItem: ColumnLayout {
            spacing: Theme.spLg
            Item { Layout.preferredHeight: 4 }
            Text {
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; text: I18n.t("kanban.newColumn"); color: Theme.text; font.pixelSize: Theme.fsLg; font.weight: Font.DemiBold
            }
            Text {
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; text: I18n.t("kanban.colName").toUpperCase(); color: Theme.textMuted; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            TextField {
                id: nameField
                objectName: "add-column-name"
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
                placeholderText: I18n.t("kanban.colName.ph")
                color: Theme.text
                placeholderTextColor: Theme.textDim
                background: FieldFrame {}
                onAccepted: saveBtn.activate()
            }
            Text {
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; text: I18n.t("common.color").toUpperCase(); color: Theme.textMuted; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            Row {
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                spacing: Theme.spSm
                Repeater {
                    model: addColumnPopup.swatches
                    delegate: Rectangle {
                        id: newSwatch
                        required property string modelData
                        required property int index
                        readonly property bool isPicked: String(addColumnPopup.picked).toLowerCase() === modelData.toLowerCase()
                        width: 24; height: 24; radius: 12
                        color: modelData
                        border.color: newSwatch.isPicked ? Theme.text : Theme.border
                        border.width: 2
                        ClickArea {
                            label: I18n.t("kanban.swatch").arg(newSwatch.index + 1)
                            showTip: false
                            role: Accessible.RadioButton
                            checkable: true
                            checked: newSwatch.isPicked
                            onActivated: addColumnPopup.picked = newSwatch.modelData
                        }
                    }
                }
            }
            RowLayout {
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.bottomMargin: Theme.sp2xl; Layout.topMargin: Theme.spMd
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
        padding: Theme.spMd
        background: Rectangle { radius: Theme.radiusLg; color: Theme.panel; border.color: Theme.borderStrong; border.width: 1 }
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
            spacing: Theme.spSm
            Repeater {
                model: colorPopup.swatches
                delegate: Rectangle {
                    id: pickSwatch
                    required property string modelData
                    required property int index
                    width: 22; height: 22; radius: 11
                    color: modelData
                    border.color: Theme.border
                    border.width: 1
                    ClickArea {
                        label: I18n.t("kanban.swatch").arg(pickSwatch.index + 1)
                        showTip: false
                        onActivated: {
                            AppController.setStatusColor(colorPopup.forStatusId, pickSwatch.modelData);
                            colorPopup.close();
                        }
                    }
                }
            }
        }
    }

    // A card being dragged is lifted in here, above every column. In its own
    // column it was clipped by the column and drawn under the columns to its
    // right, so it looked like it slid underneath them.
    Item {
        id: boardDragLayer
        objectName: "board-drag-layer"
        anchors.fill: parent
        z: 1000
    }

    // ── Inline components ───────────────────────────────────────────────────

    component HoverIcon: Rectangle {
        id: hoverIcon
        property string glyph: ""
        property string tip: ""
        property string shortcutId: ""
        property bool danger: false
        // Faded out rather than hidden: the slot stays in the header layout, so
        // nothing shifts when the pointer arrives and the icon is already under
        // the cursor when it fades in. Hidden, it takes no clicks, but it stays
        // on the Tab path and shows itself when the keyboard lands on it
        // (design audit DES-19).
        property bool revealed: false
        readonly property bool keyFocused: hoverIconMA.keyboardFocused
        readonly property bool shown: revealed || keyFocused
        readonly property bool hot: hoverIconMA.hovered || keyFocused
        signal activated()
        width: 20
        height: 20
        radius: Theme.radiusSm
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.scaledMs(90) } }
        color: hoverIcon.hot ? (danger ? Theme.withAlpha(Theme.danger, 0.16) : Theme.panel3)
                             : "transparent"
        border.color: hoverIcon.hot ? (danger ? Theme.danger : Theme.border) : "transparent"
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: hoverIcon.glyph
            color: hoverIcon.hot ? (hoverIcon.danger ? Theme.danger : Theme.text) : Theme.textMuted
            font.pixelSize: Theme.fsMd
            font.weight: Font.DemiBold
        }
        ClickArea {
            id: hoverIconMA
            label: hoverIcon.tip
            shortcutId: hoverIcon.shortcutId
            showTip: hoverIcon.shown
            acceptedButtons: hoverIcon.shown ? Qt.LeftButton : Qt.NoButton
            cursorShape: hoverIcon.shown ? Qt.PointingHandCursor : Qt.ArrowCursor
            onActivated: hoverIcon.activated()
        }
    }

    // ── Board-level empty state ──
    // Shown when the profile has no tasks at all (e.g. right after "Start
    // fresh"). Non-interactive so the column "+" affordances stay reachable.
    // Live tasks: a board whose every card is archived is empty too, and
    // says where they went (TASKS-33).
    readonly property int _boardTotal: AppController.statusCounts["_total"] || 0
    property int _allRows: AppController.tasks.rowCount()
    Connections {
        target: AppController.tasks
        function onModelReset()   { root._allRows = AppController.tasks.rowCount() }
        function onRowsInserted() { root._allRows = AppController.tasks.rowCount() }
        function onRowsRemoved()  { root._allRows = AppController.tasks.rowCount() }
    }
    // On a card of its own: laid straight over the columns, the text crossed
    // their borders and read as part of whichever column it touched.
    Rectangle {
        objectName: "board-empty"
        anchors.centerIn: parent
        width: boardEmptyCol.width + 2 * Theme.sp3xl
        height: boardEmptyCol.implicitHeight + 2 * Theme.sp2xl
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
        visible: root._boardTotal === 0
    }
    Column {
        id: boardEmptyCol
        anchors.centerIn: parent
        width: Math.min(parent.width - 96, 360)
        spacing: Theme.spMd
        visible: root._boardTotal === 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root._allRows > 0 ? I18n.t("board.empty.archivedTitle") : I18n.t("board.empty.title")
            color: Theme.text
            font.pixelSize: Theme.fsLg
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            // The keys as bound now, not as they shipped (design audit DES-15).
            text: root._allRows > 0
                  ? I18n.t("board.empty.archivedHint").arg(AppController.shortcutFor("view.archive")).arg(AppController.shortcutFor("task.new"))
                  : I18n.t("board.empty.hint").arg(AppController.shortcutFor("task.new")).arg(AppController.shortcutFor("quick-capture"))
            color: Theme.textMuted
            font.pixelSize: Theme.fsMd
        }
    }
    // ── Column delete: confirm when it is not empty ───────────────────
    // Deleting a column re-homes every card in it. That is undoable, but a
    // five-second toast is a poor place to discover that thirty cards just
    // moved — so a non-empty column asks first. An empty one does not: there
    // is nothing to lose and a dialog would only be in the way.
    //
    // The count is every card the delete re-homes — archived ones and the
    // ones a filter is hiding included. The column's visible count skipped
    // the confirmation for a column full of filtered-out cards (TASKS-8).
    function requestDeleteColumn(statusId, statusName) {
        const count = AppController.countByStatus(statusId);
        if (count <= 0) {
            AppController.deleteStatus(statusId);
            return;
        }
        confirmDelete.statusId = statusId;
        confirmDelete.statusName = statusName;
        confirmDelete.cardCount = count;
        confirmDelete.open();
    }

    QQC.Dialog {
        id: confirmDelete
        objectName: "confirm-delete-column"
        // Takes the keyboard, so Esc and Tab work in it and the board keys
        // behind it stand down.
        focus: true
        property string statusId: ""
        property string statusName: ""
        property int cardCount: 0

        modal: true
        anchors.centerIn: Overlay.overlay
        parent: Overlay.overlay
        padding: Theme.inset
        // Explicit, because the contentItem is a wrapping Text: without a width
        // of its own it sizes itself from the dialog, which is sizing itself
        // from the text. Qt reports that as a binding loop on implicitWidth and
        // settles on whatever it measured first.
        width: 420
        title: I18n.t("kanban.confirmDelete.title").arg(confirmDelete.statusName)

        background: Rectangle {
            radius: Theme.radiusXl
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        contentItem: Text {
            text: I18n.t("kanban.confirmDelete.body").arg(confirmDelete.cardCount)
            color: Theme.textMuted
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }

        footer: RowLayout {
            spacing: Theme.spMd
            Item { Layout.fillWidth: true }
            PillButton {
                text: I18n.t("common.cancel")
                onClicked: confirmDelete.close()
            }
            PillButton {
                objectName: "confirm-delete-ok"
                text: I18n.t("kanban.confirmDelete.ok")
                danger: true
                onClicked: {
                    AppController.deleteStatus(confirmDelete.statusId);
                    confirmDelete.close();
                }
            }
            Item { Layout.preferredWidth: 10 }
        }
    }

    // ── Work-in-progress limit ────────────────────────────────────────
    QQC.Dialog {
        id: wipPopup
        objectName: "wip-popup"
        property string statusId: ""
        property string statusName: ""

        function openFor(id, name, current, anchorItem) {
            wipPopup.statusId = id;
            wipPopup.statusName = name;
            wipField.text = current > 0 ? String(current) : "";
            wipPopup.open();
            wipField.forceActiveFocus();
            wipField.selectAll();
        }

        modal: true
        anchors.centerIn: Overlay.overlay
        parent: Overlay.overlay
        padding: Theme.inset
        title: I18n.t("kanban.wip.title").arg(wipPopup.statusName)

        background: Rectangle {
            radius: Theme.radiusXl
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        function commit() {
            AppController.setStatusWipLimit(wipPopup.statusId, parseInt(wipField.text || "0") || 0);
            wipPopup.close();
        }

        contentItem: ColumnLayout {
            spacing: Theme.spMd
            TextField {
                id: wipField
                objectName: "wip-field"
                Layout.fillWidth: true
                Layout.preferredWidth: 220
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 999 }
                placeholderText: "0"
                color: Theme.text
                font.family: Theme.fontMono
                background: FieldFrame {}
                onAccepted: wipPopup.commit()
            }
            Text {
                Layout.preferredWidth: 220
                text: I18n.t("kanban.wip.hint")
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
                wrapMode: Text.Wrap
            }
        }

        footer: RowLayout {
            spacing: Theme.spMd
            Item { Layout.fillWidth: true }
            PillButton { text: I18n.t("common.cancel"); onClicked: wipPopup.close() }
            PillButton { text: I18n.t("common.save"); onClicked: wipPopup.commit() }
            Item { Layout.preferredWidth: 10 }
        }
    }

    // ── Auto-archive (APP-122) ────────────────────────────────────────
    // Cards that sit in the column this many days go to the archive. For
    // Done it is the same number as Settings → Tasks.
    QQC.Dialog {
        id: archivePopup
        objectName: "archive-popup"
        property string statusId: ""
        property string statusName: ""

        function openFor(id, name) {
            archivePopup.statusId = id;
            archivePopup.statusName = name;
            const days = AppController.statusArchiveDays(id);
            archiveField.text = days > 0 ? String(days) : "";
            archivePopup.open();
            archiveField.forceActiveFocus();
            archiveField.selectAll();
        }

        modal: true
        anchors.centerIn: Overlay.overlay
        parent: Overlay.overlay
        padding: Theme.inset
        title: I18n.t("kanban.archive.title").arg(archivePopup.statusName)

        background: Rectangle {
            radius: Theme.radiusXl
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        function commit() {
            AppController.setStatusArchiveDays(archivePopup.statusId, parseInt(archiveField.text || "0") || 0);
            archivePopup.close();
        }

        contentItem: ColumnLayout {
            spacing: Theme.spMd
            TextField {
                id: archiveField
                objectName: "archive-field"
                Layout.fillWidth: true
                Layout.preferredWidth: 220
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 3650 }
                placeholderText: "0"
                color: Theme.text
                font.family: Theme.fontMono
                background: FieldFrame {}
                onAccepted: archivePopup.commit()
            }
            Text {
                Layout.preferredWidth: 220
                text: I18n.t("kanban.archive.hint")
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
                wrapMode: Text.Wrap
            }
        }

        footer: RowLayout {
            spacing: Theme.spMd
            Item { Layout.fillWidth: true }
            PillButton { text: I18n.t("common.cancel"); onClicked: archivePopup.close() }
            PillButton { objectName: "archive-save"; text: I18n.t("common.save"); onClicked: archivePopup.commit() }
            Item { Layout.preferredWidth: 10 }
        }
    }

}
