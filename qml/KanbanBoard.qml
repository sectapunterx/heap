import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Item {
    id: root
    property string searchText: ""
    property var prioritiesFilter: ({})
    property var scheduleMap: ({})
    signal taskClicked(string id)
    signal createInStatus(string statusId)

    function passesFilter(taskObj) {
        const q = (root.searchText || "").toLowerCase();
        if (q && q.length > 0) {
            const hay = ((taskObj.title || "") + " " + (taskObj.id || "") + " " + (taskObj.desc || "")).toLowerCase();
            if (hay.indexOf(q) < 0) return false;
        }
        let anyPri = false;
        for (const k in root.prioritiesFilter) if (root.prioritiesFilter[k]) { anyPri = true; break; }
        if (anyPri && !root.prioritiesFilter[taskObj.priority]) return false;
        return true;
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

        Row {
            id: rowL
            height: hscroll.height
            spacing: 12

            Repeater {
                model: AppController.statuses

                Rectangle {
                    id: col
                    required property var modelData
                    required property int index
                    readonly property string statusId: modelData.id
                    readonly property string statusName: modelData.name
                    readonly property color statusColor: modelData.color
                    property bool dragOver: false
                    property int visibleCount: 0

                    width: 280
                    height: rowL.height
                    radius: Theme.radius
                    color: Theme.panel
                    border.color: dragOver ? Theme.accent : Theme.border
                    border.width: 1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            color: Theme.panel2
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 1; color: Theme.border
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 8
                                spacing: 8
                                Rectangle { width: 10; height: 10; radius: 3; color: col.statusColor }
                                Text {
                                    text: col.statusName.toUpperCase()
                                    color: Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.letterSpacing: 1
                                    font.weight: Font.DemiBold
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
                                Item { Layout.fillWidth: true }
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

                                Column {
                                    id: bodyCol
                                    width: bodyFlick.width
                                    spacing: 8

                                    Repeater {
                                        id: colRep
                                        model: AppController.tasks

                                        TaskCard {
                                            id: tc
                                            required property string id
                                            required property string title
                                            required property string desc
                                            required property string priority
                                            required property string status
                                            required property var deadline
                                            required property string branch
                                            width: bodyCol.width

                                            readonly property var taskData: ({
                                                id: tc.id, title: tc.title, desc: tc.desc,
                                                priority: tc.priority, status: tc.status,
                                                deadline: tc.deadline, branch: tc.branch
                                            })
                                            task: taskData
                                            scheduled: root.scheduleMap[tc.id] || ""
                                            visible: tc.status === col.statusId && root.passesFilter(taskData)
                                            onClicked: root.taskClicked(tc.id)

                                            onVisibleChanged: col.recountSoon()
                                            Component.onCompleted: col.recountSoon()
                                            Component.onDestruction: col.recountSoon()
                                        }
                                    }

                                    Text {
                                        visible: col.visibleCount === 0
                                        width: bodyCol.width
                                        topPadding: 12
                                        text: "— пусто —"
                                        color: Theme.textDim
                                        font.italic: true
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: col.dragOver = true
                                onExited: col.dragOver = false
                                onDropped: (drop) => {
                                    col.dragOver = false;
                                    const src = drop.source;
                                    if (src && src.taskId) {
                                        AppController.moveTask(src.taskId, col.statusId);
                                        drop.accept(Qt.MoveAction);
                                    }
                                }
                            }
                        }
                    }

                    function recountSoon() { recountTimer.restart() }
                    Timer {
                        id: recountTimer
                        interval: 0
                        repeat: false
                        onTriggered: {
                            let n = 0;
                            for (let i = 0; i < colRep.count; i++) {
                                const it = colRep.itemAt(i);
                                if (it && it.visible) n++;
                            }
                            col.visibleCount = n;
                        }
                    }

                    Connections {
                        target: root
                        function onSearchTextChanged() { col.recountSoon() }
                        function onPrioritiesFilterChanged() { col.recountSoon() }
                    }
                }
            }
        }
    }
}
