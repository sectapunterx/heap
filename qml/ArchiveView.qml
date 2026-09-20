import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp
import "Search.js" as Search

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

    function passesFilter(t) {
        // Clauses filter structurally, leftover words stay a substring test.
        if (!Search.accepts(AppController, root.searchText, root.modelRev, t)) return false;
        let any = false;
        for (const k in root.prioritiesFilter) if (root.prioritiesFilter[k]) {
            any = true;
            break;
        }
        if (any && !root.prioritiesFilter[t.priority]) return false;
        return true;
    }

    function statusInfo(id) {
        const list = AppController.statuses;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return {id: id, name: id, color: Theme.textDim};
    }

    // Snapshot of archived tasks. Rebuild on task-model mutations.
    property int modelRev: 0
    Connections {
        target: AppController.tasks

        function onDataChanged() {
            root.modelRev++
        }

        function onRowsInserted() {
            root.modelRev++
        }

        function onRowsRemoved() {
            root.modelRev++
        }

        function onModelReset() {
            root.modelRev++
        }
    }

    function buildItems() {
        // Dependencies of the `items` binding below, read unconditionally.
        // passesFilter() reads the last two, but only for rows that reach
        // it: with nothing archived it never runs, and a property that was
        // never read is not a dependency, so the list would go stale.
        const _rev = root.modelRev;
        const _q = root.searchText;
        const _pri = root.prioritiesFilter;
        const m = AppController.tasks;
        const out = [];
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            const archived = m.data(idx, Qt.UserRole + 9);
            if (!archived) continue;
            const t = {
                id: m.data(idx, Qt.UserRole + 1),
                title: m.data(idx, Qt.UserRole + 2),
                desc: m.data(idx, Qt.UserRole + 3),
                priority: m.data(idx, Qt.UserRole + 4),
                status: m.data(idx, Qt.UserRole + 5),
                deadline: m.data(idx, Qt.UserRole + 6),
                branch: m.data(idx, Qt.UserRole + 7),
                archived: true,
                blockedStuck: m.data(idx, Qt.UserRole + 10),
                prState: m.data(idx, Qt.UserRole + 11),
                prNumber: m.data(idx, Qt.UserRole + 12),
                prUrl: m.data(idx, Qt.UserRole + 13),
                gitAhead: m.data(idx, Qt.UserRole + 14),
                gitBehind: m.data(idx, Qt.UserRole + 15),
                recentCommits: m.data(idx, Qt.UserRole + 16),
                trackedSeconds: m.data(idx, Qt.UserRole + 17),
                isTiming: m.data(idx, Qt.UserRole + 18),
                recurrence: m.data(idx, Qt.UserRole + 19),
                // TaskCard also reads these, so without them archived cards
                // silently lost their labels and their clock time.
                dueAt: m.data(idx, Qt.UserRole + 21),
                hasTime: m.data(idx, Qt.UserRole + 22),
                labels: m.data(idx, Qt.UserRole + 29),
                // Archived tickets keep their badge and key (HEAP-117).
                ticket: m.data(idx, Qt.UserRole + 31),
                searchText: m.data(idx, Qt.UserRole + 32),
            };
            if (!root.passesFilter(t)) continue;
            out.push(t);
        }
        const priRank = {P0: 0, P1: 1, P2: 2, P3: 3};
        out.sort((a, b) => (priRank[a.priority] ?? 9) - (priRank[b.priority] ?? 9));
        return out;
    }

    // A real binding, so it re-evaluates when anything buildItems() reads
    // moves. It used to be helped along by `onSearchTextChanged: modelRev++`
    // and the same for prioritiesFilter — which was both redundant and a
    // binding loop: `prioritiesFilter`'s own default binding is evaluated on
    // its first read, which happens inside this binding, and the resulting
    // change signal bumped modelRev while `items` was still being computed.
    // Qt then reported a loop and abandoned that evaluation.
    readonly property var items: buildItems()

    function _flatVisibleIds() {
        const ids = [];
        for (let i = 0; i < items.length; i++) ids.push(items[i].id);
        return ids;
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
                anchors.leftMargin: 18; anchors.rightMargin: 18
                spacing: 12
                Column {
                    spacing: 1
                    Text {
                        text: I18n.t("archive.title")
                        color: Theme.text
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.items.length + " " + I18n.t("archive.count")
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                PillButton {
                    visible: root.items.length > 0
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

        // Body
        ScrollView {
            id: archScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            // Pin the content width instead of letting the ScrollView derive it
            // from the content: the content is a Layout whose own width came
            // from the view, so each rearrange fed the next one and Qt gave up
            // after two iterations ("recursive rearrange"), leaving the cards
            // laid out against a stale width.
            contentWidth: availableWidth

            ColumnLayout {
                width: archScroll.availableWidth
                spacing: 0

                Item {
                    visible: root.items.length === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "▤"
                            color: Theme.textDim
                            font.pixelSize: 32
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.t("archive.empty.title")
                            color: Theme.text
                            font.pixelSize: 13
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.t("archive.empty.hint")
                            color: Theme.textDim
                            font.pixelSize: 12
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    Layout.topMargin: 12
                    Layout.bottomMargin: 18
                    spacing: 8

                    Repeater {
                        model: root.items
                        // Anchors, not a RowLayout. TaskCard's height comes from
                        // wrapping text, so it is a height-for-width item: inside a
                        // Layout that has to know implicit sizes before it hands out
                        // widths, each pass changed the answer to the previous one
                        // and Qt aborted the rearrange after two iterations. Anchors
                        // settle the width first and let the height follow.
                        delegate: Item {
                            id: row
                            required property var modelData
                            readonly property var st: root.statusInfo(modelData.status)
                            Layout.fillWidth: true
                            implicitHeight: archCard.implicitHeight

                            // Status pill — gives context for "from which column".
                            Rectangle {
                                id: statusPill
                                width: 86
                                height: 24
                                y: (archCard.implicitHeight - height) / 2
                                anchors.left: parent.left
                                radius: 999
                                color: "transparent"
                                border.color: Theme.withAlpha(row.st.color, 0.45)
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: row.st.name
                                    color: row.st.color
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }

                            TaskCard {
                                id: archCard
                                anchors.left: statusPill.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.top: parent.top
                                task: row.modelData
                                onClicked: root.taskClicked(row.modelData.id)
                                onRangeSelectRequested: (anchorId) => root._rangeSelect(anchorId)
                                onHoveredChanged: {
                                    if (hovered) root.hoveredTaskId = row.modelData.id;
                                    else if (root.hoveredTaskId === row.modelData.id) root.hoveredTaskId = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
