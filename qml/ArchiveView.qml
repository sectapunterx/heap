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
    // The card under the cursor, for the single-key ticket action (HEAP-117).
    property string hoveredTaskId: ""

    signal taskClicked(string id)

    // Shift-click range select within the archive feed (flat order).
    property string shiftAnchorId: ""
    Connections {
        target: AppController

        function onSelectedTaskIdsChanged() {
            if (AppController.selectionCount === 0) root.shiftAnchorId = "";
        }
    }

    function statusInfo(id) {
        const list = AppController.statuses;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return {id: id, name: id, color: Theme.textDim};
    }

    // The archive's feed: a C++ proxy over the task model, archived rows only,
    // filtered by the same search box and priority chips the board uses and
    // sorted P0 first. It used to be a JS snapshot of every archived task fed
    // to a Repeater of full TaskCards — 1561 archived tasks cost 2.4 GB and
    // 12 s to open, and every edit anywhere rebuilt the lot. The proxy updates
    // row by row, and the ListView below only builds the cards on screen.
    readonly property var activePriorities: {
        const out = [];
        for (const k in root.prioritiesFilter) if (root.prioritiesFilter[k]) out.push(k);
        return out;
    }
    TaskFilterProxy {
        id: archFilter
        objectName: "archive-filter"
        sourceModel: AppController.tasks
        archivedOnly: true
        // As on the board: status: by column name and relative dates need
        // the columns and today, or "status:\"Code Review\"" finds nothing
        // here while a saved view counts it (TASKS-5).
        statuses: AppController.statuses
        today: AppController.today
        newIds: AppController.syncNewTaskIds
        searchText: root.searchText
        priorities: root.activePriorities
        sortMode: "priority"
    }
    readonly property alias count: archFilter.count

    // The feed as plain rows, in display order: {id, priority, status}. For
    // callers that want the list rather than the view; nothing on screen
    // reads it.
    function buildItems() {
        const out = [];
        const n = archFilter.rowCount();
        for (let i = 0; i < n; i++) {
            const idx = archFilter.index(i, 0);
            out.push({
                id: archFilter.data(idx, Qt.UserRole + 1),
                priority: archFilter.data(idx, Qt.UserRole + 4),
                status: archFilter.data(idx, Qt.UserRole + 5),
            });
        }
        return out;
    }

    function _flatVisibleIds() {
        return archFilter.ids();
    }

    function selectAllVisible() {
        AppController.setSelectedTaskIds(_flatVisibleIds());
    }

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

    // Keyboard (SHELL-17): every archived card is a Tab stop with its name;
    // ↑/↓ also walk the list from card to card, Return opens one (TaskCard),
    // the Menu key (or Shift+F10) opens its menu — restore and delete are
    // there. ↓ on the view itself, where a view switch leaves focus, enters
    // the list. The keys a card does not take reach the list, which handles
    // them for whichever card holds focus.
    function _cardAt(i) {
        const it = archList.itemAtIndex(i);
        if (!it) return null;
        const kids = it.children;
        for (let k = 0; k < kids.length; k++)
            if (typeof kids[k].openMenu === "function") return kids[k];
        return null;
    }
    function _focusedRow() {
        const f = root.Window.activeFocusItem;
        if (!f) return -1;
        const p = f.mapToItem(archList.contentItem, f.width / 2, f.height / 2);
        return archList.indexAt(p.x, p.y);
    }
    function focusRow(i) {
        if (archList.count === 0) return false;
        const at = Math.max(0, Math.min(archList.count - 1, i));
        archList.currentIndex = at;
        archList.positionViewAtIndex(at, ListView.Contain);
        const card = root._cardAt(at);
        if (!card) return false;
        card.forceActiveFocus(Qt.TabFocusReason);
        return true;
    }
    Keys.onDownPressed: root.focusRow(Math.max(0, archList.currentIndex))
    Accessible.role: Accessible.Pane
    Accessible.name: I18n.t("archive.title")

    Rectangle {
        anchors.fill: parent; color: Theme.bg
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header strip
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: Theme.panel
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: Theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.inset; anchors.rightMargin: Theme.inset
                spacing: Theme.spXl
                Column {
                    spacing: 1
                    Text {
                        text: I18n.t("archive.title")
                        color: Theme.text
                        font.pixelSize: Theme.fsLg
                        font.weight: Theme.fwHeading
                    }
                    Text {
                        text: archFilter.count + " " + I18n.t("archive.count")
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.features: Theme.tabularNums
                        font.pixelSize: Theme.fsSm
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                PillButton {
                    visible: archFilter.count > 0
                    text: I18n.t("archive.selectAll")
                    onClicked: root.selectAllVisible()
                }
                PillButton {
                    visible: AppController.selectionCount > 0
                    text: I18n.t("archive.restoreSelected")
                    primary: true
                    onClicked: AppController.setSelectedTasksArchived(false)
                }
            }
        }

        // Body — a virtualised list. Only the cards in view (plus a screen of
        // cache) exist, and scrolled-out delegates are pooled and reused.
        ListView {
            id: archList
            objectName: "archive-list"
            Accessible.role: Accessible.List
            Accessible.name: I18n.t("archive.title")
            // The cards are the stops, not the list.
            keyNavigationEnabled: false
            Keys.onUpPressed: root.focusRow(root._focusedRow() - 1)
            Keys.onDownPressed: {
                const at = root._focusedRow();
                root.focusRow(at < 0 ? 0 : at + 1);
            }
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) {
                    const card = root._cardAt(root._focusedRow());
                    if (card) card.openMenu();
                    event.accepted = true;
                }
            }
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThinScrollBar {}
            model: archFilter
            reuseItems: true
            cacheBuffer: 600
            spacing: Theme.spMd
            topMargin: Theme.spXl
            bottomMargin: Theme.inset

            Item {
                visible: archFilter.count === 0
                width: archList.width
                height: 220
                EmptyState {
                    objectName: "archive-empty"
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 2 * Theme.sp3xl, 420)
                    icon: "heap-05-archive"
                    title: I18n.t("archive.empty.title")
                    line: I18n.t("archive.empty.hint")
                }
            }

            // Anchors, not a RowLayout. TaskCard's height comes from wrapping
            // text, so it is a height-for-width item: inside a Layout that has
            // to know implicit sizes before it hands out widths, each pass
            // changed the answer to the previous one and Qt aborted the
            // rearrange after two iterations. Anchors settle the width first
            // and let the height follow.
            delegate: Item {
                id: row
                required property string id
                required property string title
                required property string desc
                required property string priority
                required property string status
                required property var deadline
                required property string branch
                required property bool blockedStuck
                required property string prState
                required property string prMove
                required property string prMoveReason
                required property int prNumber
                required property string prUrl
                required property int gitAhead
                required property int gitBehind
                required property var recentCommits
                required property int trackedSeconds
                required property bool isTiming
                required property string recurrence
                required property var labels
                required property var dueAt
                required property bool hasTime
                required property var ticket
                required property string searchText
                required property var checklist
                required property int attachmentCount
                readonly property var st: root.statusInfo(row.status)
                x: Theme.inset
                width: archList.width - 2 * Theme.inset
                height: archCard.implicitHeight

                // A pooled row waits, culled but still a child of the list,
                // until another row needs it: hide it so it is not taken for a
                // row on screen, and let the menu go with the task it was
                // opened for.
                ListView.onPooled: {
                    archCard.releaseMenu();
                    row.visible = false;
                }
                ListView.onReused: row.visible = true

                // Status pill — gives context for "from which column".
                Rectangle {
                    id: statusPill
                    width: 86
                    height: 24
                    y: (archCard.implicitHeight - height) / 2
                    anchors.left: parent.left
                    radius: Theme.radiusPill
                    color: "transparent"
                    border.color: Theme.withAlpha(row.st.color, 0.45)
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: row.st.name
                        color: Theme.readable(row.st.color)
                        font.pixelSize: Theme.fsXs
                        font.weight: Theme.fwTitle
                    }
                }

                TaskCard {
                    id: archCard
                    anchors.left: statusPill.right
                    anchors.leftMargin: Theme.spLg
                    anchors.right: parent.right
                    anchors.top: parent.top
                    task: ({
                        id: row.id, title: row.title, desc: row.desc,
                        priority: row.priority, status: row.status,
                        deadline: row.deadline, branch: row.branch,
                        archived: true, blockedStuck: row.blockedStuck,
                        prState: row.prState, prNumber: row.prNumber, prUrl: row.prUrl,
                        prMove: row.prMove, prMoveReason: row.prMoveReason,
                        gitAhead: row.gitAhead, gitBehind: row.gitBehind,
                        recentCommits: row.recentCommits,
                        trackedSeconds: row.trackedSeconds, isTiming: row.isTiming,
                        recurrence: row.recurrence,
                        // TaskCard also reads these, so without them archived
                        // cards silently lost their labels and their clock time.
                        labels: row.labels, dueAt: row.dueAt, hasTime: row.hasTime,
                        // Archived tickets keep their badge and key (HEAP-117).
                        ticket: row.ticket, searchText: row.searchText,
                        checklist: row.checklist, attachmentCount: row.attachmentCount
                    })
                    onClicked: root.taskClicked(row.id)
                    onRangeSelectRequested: (anchorId) => root._rangeSelect(anchorId)
                    onHoveredChanged: {
                        if (hovered) root.hoveredTaskId = row.id;
                        else if (root.hoveredTaskId === row.id) root.hoveredTaskId = "";
                    }
                }
            }
        }
    }
}
