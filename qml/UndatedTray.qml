pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

// "Without a date" (APP-264): the tasks with no plan and no deadline, beside
// the calendar that has the days and hours for them. Drag one onto an hour or
// a day, or pick it and click the slot (or press S for the next free window).
// The same rule as "is:undated" in the list and the count on Today, narrowed
// by the section's query. Empty, it is not there at all.
Rectangle {
    id: root
    objectName: "undated-tray"

    property string searchText: ""
    // The task picked for a click on the grid; "" when none.
    property string armedId: ""
    signal taskOpened(string id)

    color: Theme.bg
    implicitWidth: Theme.px(260)

    ChangeTick { id: taskTick }
    Connections {
        target: AppController.tasks
        function onDataChanged() { taskTick.bump() }
        function onRowsInserted() { taskTick.bump() }
        function onRowsRemoved() { taskTick.bump() }
        function onModelReset() { taskTick.bump() }
    }
    // The revision is read in the expression itself: an unused local that
    // only reads it is dropped by the compiler, and with it the dependency.
    readonly property var items: taskTick.rev >= 0 ? AppController.undatedTasks(root.searchText) : []
    readonly property int count: root.items.length
    // A long tray gets its own find field (100+ tasks are a scroll otherwise).
    readonly property bool findable: root.count > 12
    readonly property var shown: {
        const needle = findField.text.trim().toLowerCase();
        if (!root.findable || needle.length === 0) return root.items;
        return root.items.filter(t => (t.id + " " + t.title).toLowerCase().indexOf(needle) >= 0);
    }
    onItemsChanged: if (root.armedId && !root.items.some(t => t.id === root.armedId)) root.armedId = ""

    // S on the picked task: the next free window of the selected day (APP-253).
    function scheduleArmed() {
        if (!root.armedId) return false;
        AppController.scheduleTaskAtNextFreeSlot(root.armedId, AppController.selectedDate);
        root.armedId = "";
        return true;
    }

    Rectangle {
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1
        color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spXl
        anchors.rightMargin: Theme.spLg
        anchors.topMargin: Theme.spLg
        spacing: Theme.spXs

        Row {
            spacing: Theme.spXs
            Text {
                text: I18n.t("tray.title")
                color: Theme.text
                font.pixelSize: Theme.fsMd
                font.weight: Theme.fwHeading
            }
            Text {
                objectName: "undated-tray-count"
                text: root.count
                color: Theme.textDim
                font.pixelSize: Theme.fsMd
                font.features: Theme.tabularNums
            }
        }
        Text {
            Layout.fillWidth: true
            text: I18n.t("tray.hint")
            color: Theme.textDim
            font.pixelSize: Theme.fsXs
            wrapMode: Text.Wrap
        }
        TextField {
            id: findField
            objectName: "undated-tray-find"
            visible: root.findable
            Layout.fillWidth: true
            placeholderText: I18n.t("tray.find")
            color: Theme.text
            placeholderTextColor: Theme.textDim
            font.pixelSize: Theme.fsSm
            background: FieldFrame {}
        }

        ListView {
            id: list
            objectName: "undated-tray-list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Theme.spSm
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                objectName: "undated-" + row.modelData.id
                width: list.width
                height: Theme.px(34)
                readonly property bool armed: root.armedId === row.modelData.id

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    color: row.armed ? Theme.accentSoft : rowArea.containsMouse ? Theme.panel2 : "transparent"
                    border.color: row.armed ? Theme.accent : "transparent"
                    border.width: row.armed ? 1 : 0
                }
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.border
                    opacity: 0.5
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spXs
                    anchors.rightMargin: Theme.spXs
                    spacing: Theme.spSm
                    StatusRing {
                        category: row.modelData.category || "todo"
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.title
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.pixelSize: Theme.fsSm
                        elide: Text.ElideRight
                    }
                }
                // The keyboard's way in: Return picks it, S plans it in the
                // next free window, O opens it.
                ClickArea {
                    id: rowKey
                    objectName: "undated-key-" + row.modelData.id
                    label: row.modelData.title
                    showTip: false
                    acceptedButtons: Qt.NoButton
                    onActivated: root.armedId = row.armed ? "" : row.modelData.id
                    Keys.onPressed: (event) => {
                        if (event.modifiers !== Qt.NoModifier) return;
                        if (event.key === Qt.Key_S) {
                            root.armedId = row.modelData.id;
                            root.scheduleArmed();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_O) {
                            root.taskOpened(row.modelData.id);
                            event.accepted = true;
                        }
                    }
                }
                // A click picks it (and a second one lets go), a double click
                // opens it, a drag carries it onto the grid.
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    drag.target: ghost
                    drag.threshold: 6
                    onPressed: (mouse) => {
                        const p = rowArea.mapToItem(root, mouse.x, mouse.y);
                        ghost.taskId = row.modelData.id;
                        ghost.title = row.modelData.title;
                        ghost.x = p.x - Theme.spMd;
                        ghost.y = p.y - ghost.height / 2;
                    }
                    onReleased: if (ghost.Drag.active) ghost.Drag.drop()
                    onClicked: root.armedId = row.armed ? "" : row.modelData.id
                    onDoubleClicked: root.taskOpened(row.modelData.id)
                    Binding {
                        target: root
                        property: "_dragging"
                        value: rowArea.drag.active
                        when: rowArea.pressed
                        restoreMode: Binding.RestoreValue
                    }
                }
            }
        }
    }

    // What a drag carries: the grid's DropArea reads `taskId`, and
    // `plainSchedule` tells it to plan the task rather than book a block.
    property bool _dragging: false
    Rectangle {
        id: ghost
        objectName: "undated-ghost"
        property string taskId: ""
        property string title: ""
        readonly property bool plainSchedule: true
        visible: ghost.Drag.active
        z: 100
        width: Math.min(Theme.px(220), ghostText.implicitWidth + 2 * Theme.spMd)
        height: Theme.px(26)
        radius: Theme.radiusSm
        color: Theme.panel2
        border.color: Theme.accent
        border.width: 1
        Drag.active: root._dragging
        Drag.source: ghost
        Drag.hotSpot.x: Theme.spMd
        Drag.hotSpot.y: ghost.height / 2
        Text {
            id: ghostText
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.spMd
            width: ghost.width - 2 * Theme.spMd
            text: ghost.title
            color: Theme.text
            font.pixelSize: Theme.fsSm
            elide: Text.ElideRight
        }
    }
}
