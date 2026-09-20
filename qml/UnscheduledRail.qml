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

    // Roles by name. Counting offsets from Qt.UserRole by hand is how a filter
    // silently starts reading a different field — written that way first, the
    // `hasTime` check came out as the board's rank. roleNames() is not
    // invokable from QML, so TaskModel exposes roleOf() for exactly this.
    function _data(model, idx, name) {
        const r = model.roleOf(name);
        return r < 0 ? undefined : model.data(idx, r);
    }

    function _inRange(d) {
        for (let i = 0; i < root.days.length; i++) if (_sameDay(root.days[i], d)) return true;
        return false;
    }

    // Tasks due in the visible range that have no time on them yet.
    //
    // `hasTime` is the whole question: a deadline is a date, and a task only
    // counts as blocked out once it has an hour. A task already standing in
    // the grid must not also stand in the list of what is missing from it.
    function buildItems() {
        const _t = root.taskRev;
        const _e = root.eventRev;
        const tm = AppController.tasks;
        const out = [];
        const needle = root.searchText.trim().toLowerCase();
        for (let i = 0; i < tm.rowCount(); i++) {
            const idx = tm.index(i, 0);
            if (root._data(tm, idx, "archived")) continue;
            if (String(root._data(tm, idx, "status") || "") === "done") continue;
            const due = root._data(tm, idx, "deadline");
            if (!due || !due.getFullYear || !root._inRange(due)) continue;
            if (root._data(tm, idx, "hasTime")) continue;
            if (needle.length > 0) {
                const hay = String(root._data(tm, idx, "searchText") || "");
                if (hay.indexOf(needle) < 0) continue;
            }
            out.push({
                id:       String(root._data(tm, idx, "id")),
                title:    String(root._data(tm, idx, "title") || ""),
                priority: String(root._data(tm, idx, "priority") || "P3"),
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
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: I18n.t("rail.unscheduled").toUpperCase()
                color: Theme.textMuted
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                Layout.fillWidth: true
            }
            Text {
                text: root.items.length
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
        }

        // The rail's whole point is that it empties. Saying so beats an empty
        // box that reads as something failing to load.
        Text {
            visible: root.items.length === 0
            Layout.fillWidth: true
            text: I18n.t("rail.allBlocked")
            color: Theme.textDim
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            objectName: "unscheduled-list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.items
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: chip
                required property var modelData
                objectName: "unscheduled-" + chip.modelData.id
                width: list.width
                height: 44
                radius: 6
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
                    anchors.margins: 6
                    width: 3
                    radius: 1.5
                    color: chip.modelData.priority === "P0" ? Theme.p0
                         : chip.modelData.priority === "P1" ? Theme.p1
                         : chip.modelData.priority === "P2" ? Theme.p2 : Theme.p3
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 8
                    anchors.topMargin: 5; anchors.bottomMargin: 5
                    spacing: 1
                    Text {
                        text: chip.modelData.title
                        color: Theme.text
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: chip.modelData.id + " · " + Qt.formatDate(chip.modelData.deadline, "ddd d MMM")
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    drag.target: chip
                    drag.threshold: 5
                    cursorShape: dragArea.drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    property bool didDrag: false
                    onPressed: { chip.homeX = chip.x; chip.homeY = chip.y; didDrag = false; }
                    onPositionChanged: if (dragArea.drag.active) didDrag = true;
                    onReleased: {
                        // Home again either way: a drop that landed schedules
                        // the task and the list drops it, and one that missed
                        // must not leave the chip stranded mid-rail.
                        chip.Drag.drop();
                        chip.x = chip.homeX;
                        chip.y = chip.homeY;
                        if (!didDrag) root.taskClicked(chip.taskId);
                    }
                }
            }
        }
    }
}
