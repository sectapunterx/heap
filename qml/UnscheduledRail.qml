import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

// Tasks with a deadline and no time yet.
//
// Time-blocking worked in one direction only: the grids accepted a card
// dropped on an hour, and the only place to drag one from was the board. So
// planning a week meant switching views, remembering a title, switching back
// and finding the hour again.
//
// This is the other half — the list of what still needs a slot, beside the grid
// that has the slots. A task leaves the rail the moment it has a time, which is
// what makes the list shrink as the week fills up rather than repeating what is
// already planned.
Rectangle {
    id: root

    // The days on screen, so "unscheduled" means "unscheduled in what I am
    // looking at" rather than across all of history.
    property var days: []
    property string searchText: ""

    // Bumped by the models so the list rebuilds; the views already track these.
    property int taskRev: 0
    property int eventRev: 0

    signal taskClicked(string id)

    color: Theme.panel
    implicitWidth: 240

    function _midnight(d) {
        if (!d || !d.getFullYear) return null;
        return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }

    function _sameDay(a, b) {
        const x = _midnight(a), y = _midnight(b);
        return !!x && !!y && x.getTime() === y.getTime();
    }

    function _inRange(d) {
        for (let i = 0; i < root.days.length; i++) if (_sameDay(root.days[i], d)) return true;
        return false;
    }

    // Tasks due in the visible range that have no time on them yet.
    //
    // A task has its slot once it has an hour (`hasTime`) or a block on the
    // calendar that stands for it (a focus block or a linked meeting in the
    // range). The block is what counts for a task with a date-only deadline:
    // scheduling it no longer marks that deadline as timed (it read 00:00).
    // A task already standing in the grid must not also stand in the list of
    // what is missing from it.
    //
    // The candidates come from C++ (calendarTasks): reading roles of every
    // task in the profile for a week's worth was the slow part at 10k tasks.
    function buildItems() {
        const _t = root.taskRev;
        const _e = root.eventRev;
        const out = [];
        if (root.days.length === 0) return out;
        const first = root.days[0];
        const last = root.days[root.days.length - 1];
        const slotted = {};
        const occ = AppController.eventOccurrences(first, last);
        for (let i = 0; i < occ.length; i++) if (occ[i].taskId) slotted[String(occ[i].taskId)] = true;
        const needle = root.searchText.trim().toLowerCase();
        const list = AppController.calendarTasks(first, last, false);
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            if (t.status === "done" || t.dueDay < 0) continue;
            const due = t.deadline;
            if (!due || !due.getFullYear || !root._inRange(due)) continue;
            // Either clock puts it on the grid already (schema v10 keeps one per field).
            if (t.scheduledHasTime || t.dueHasTime || slotted[t.id]) continue;
            if (needle.length > 0 && String(t.searchText || "").indexOf(needle) < 0) continue;
            out.push({
                id:       String(t.id),
                title:    String(t.title || ""),
                priority: String(t.priority || "P3"),
                deadline: due
            });
        }
        // Soonest first, then by priority: the rail is a queue, and what is due
        // first is what needs a slot first.
        const rank = { P0: 0, P1: 1, P2: 2, P3: 3 };
        out.sort(function (a, b) {
            return (a.deadline.getTime() - b.deadline.getTime())
                || ((rank[a.priority] ?? 9) - (rank[b.priority] ?? 9));
        });
        return out;
    }
    readonly property var items: buildItems()

    Rectangle {
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1; color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spLg
        spacing: Theme.spMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spSm
            Text {
                text: I18n.t("rail.unscheduled")
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
                font.weight: Theme.fwTitle
                Layout.fillWidth: true
            }
            Text {
                text: root.items.length
                color: Theme.textDim
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsSm
            }
        }

        // The rail's whole point is that it empties. Saying so beats an empty
        // box that reads as something failing to load.
        Text {
            visible: root.items.length === 0
            Layout.fillWidth: true
            text: I18n.t("rail.allBlocked")
            color: Theme.textDim
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            objectName: "unscheduled-list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spSm
            model: root.items
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: chip
                required property var modelData
                objectName: "unscheduled-" + chip.modelData.id
                width: list.width
                height: 44
                radius: Theme.radiusMd
                color: dragArea.drag.active ? Theme.panel3 : Theme.panel2
                border.color: dragArea.containsMouse ? Theme.borderStrong : Theme.border
                border.width: 1

                // The grids read `taskId` off whatever is dropped on them, the
                // same property a board card exposes, so the rail needs no new
                // drop handling anywhere.
                property string taskId: chip.modelData.id
                property real homeX: 0
                property real homeY: 0

                Drag.active: dragArea.drag.active
                Drag.dragType: Drag.Internal
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: 20

                Rectangle {
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    anchors.margins: Theme.spSm
                    width: 3
                    radius: 1.5
                    color: chip.modelData.priority === "P0" ? Theme.p0
                         : chip.modelData.priority === "P1" ? Theme.p1
                         : chip.modelData.priority === "P2" ? Theme.p2 : Theme.p3
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.spMd
                    anchors.topMargin: Theme.spXs; anchors.bottomMargin: Theme.spXs
                    spacing: 1
                    Text {
                        text: chip.modelData.title
                        color: Theme.text
                        font.pixelSize: Theme.fsSm
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    // The key in mono, because it is an id; the date in the
                    // UI face with even digits (APP-200): set in mono it read
                    // as code, "вт 6 окт." in a typewriter.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spMd
                        Text {
                            objectName: "unscheduled-key"
                            text: chip.modelData.id
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsXs
                        }
                        Text {
                            objectName: "unscheduled-date"
                            text: I18n.fmtDate(chip.modelData.deadline, "weekdayDay")
                            color: Theme.textDim
                            font.family: Theme.fontUi
                            font.features: Theme.tabularNums
                            font.pixelSize: Theme.fsXs
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                // Opening from the keyboard (design audit DES-19). Under the
                // drag area and deaf to the pointer, so a press still drags.
                ClickArea {
                    objectName: "unscheduled-open"
                    label: chip.modelData.title
                    showTip: false
                    acceptedButtons: Qt.NoButton
                    onActivated: dragArea.open()
                }
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    drag.target: chip
                    drag.threshold: 5
                    cursorShape: dragArea.drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    property bool didDrag: false
                    // A click that did not drag, and Return on the ClickArea.
                    function open() { root.taskClicked(chip.taskId); }
                    onPressed: { chip.homeX = chip.x; chip.homeY = chip.y; didDrag = false; }
                    onPositionChanged: if (dragArea.drag.active) didDrag = true;
                    onReleased: {
                        // Home again either way: a drop that landed schedules
                        // the task and the list drops it, and one that missed
                        // must not leave the chip stranded mid-rail.
                        chip.Drag.drop();
                        chip.x = chip.homeX;
                        chip.y = chip.homeY;
                        if (!didDrag) dragArea.open();
                    }
                }
            }
        }
    }
}
