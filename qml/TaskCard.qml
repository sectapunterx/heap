import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

Rectangle {
    id: card
    property var task           // QVariantMap-like with id,title,desc,priority,status,deadline,branch
    property string scheduled
    property string taskId: task ? task.id : ""
    signal clicked()

    radius: 8
    color: Theme.panel2
    border.color: hoverArea.containsMouse ? Theme.borderStrong : Theme.border
    border.width: 1
    opacity: dragArea.drag.active ? 0.5 : 1.0

    implicitWidth: parent ? parent.width : 260
    implicitHeight: contentCol.implicitHeight + 20

    // Drag.active is automatically driven by MouseArea.drag.active
    Drag.active: dragArea.drag.active
    Drag.dragType: Drag.Internal
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: 20

    property real homeX: 0
    property real homeY: 0

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        RowLayout {
            spacing: 6
            Text {
                text: card.task ? card.task.id : ""
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.weight: Font.Medium
            }
            Rectangle {
                radius: 4
                color: Theme.withAlpha(Theme.priorityColor(card.task ? card.task.priority : "P3"), 0.12)
                implicitWidth: priT.implicitWidth + 10
                implicitHeight: priT.implicitHeight + 2
                Text {
                    id: priT
                    anchors.centerIn: parent
                    text: card.task ? card.task.priority : ""
                    color: Theme.priorityColor(card.task ? card.task.priority : "P3")
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: card.task && card.task.branch && String(card.task.branch).length > 0
                text: card.task && card.task.branch
                      ? "⎇ " + String(card.task.branch).split("/").pop().substring(0, 18)
                      : ""
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        Text {
            Layout.fillWidth: true
            text: card.task ? card.task.title : ""
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            visible: card.task && card.task.desc && String(card.task.desc).length > 0
            text: card.task ? card.task.desc : ""
            color: Theme.textMuted
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        RowLayout {
            spacing: 8
            Text {
                property string dlText: {
                    if (!card.task || !card.task.deadline) return "";
                    const dl = card.task.deadline;
                    if (!dl.getTime) return "";
                    const t = AppController.today;
                    const ms = dl.getTime() - new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
                    const days = Math.round(ms / 86400000);
                    if (days < 0) return "⏱ " + (-days) + "d overdue";
                    if (days === 0) return "⏱ today";
                    if (days === 1) return "⏱ tomorrow";
                    return "⏱ " + days + "d";
                }
                visible: dlText.length > 0
                text: dlText
                color: {
                    if (!card.task || !card.task.deadline || !card.task.deadline.getTime) return Theme.textDim;
                    const dl = card.task.deadline;
                    const t = AppController.today;
                    const days = Math.round((dl.getTime() - new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime()) / 86400000);
                    if (days <= 0) return Theme.p0;
                    if (days <= 3) return Theme.p1;
                    return Theme.textDim;
                }
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                visible: card.scheduled && card.scheduled.length > 0
                radius: 4
                color: Theme.accentSoft
                implicitWidth: schedT.implicitWidth + 10
                implicitHeight: schedT.implicitHeight + 2
                Text {
                    id: schedT
                    anchors.centerIn: parent
                    text: "⏰ " + (card.scheduled || "")
                    color: Theme.accentStrong
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        drag.target: card
        drag.threshold: 5
        cursorShape: dragArea.drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property bool didDrag: false
        onPressed: (mouse) => {
            card.homeX = card.x; card.homeY = card.y; didDrag = false;
            if (mouse.button === Qt.RightButton) taskMenu.popup();
        }
        onPositionChanged: if (drag.active) didDrag = true
        onReleased: (mouse) => {
            const wasDrag = didDrag;
            card.Drag.drop();
            card.x = card.homeX; card.y = card.homeY;
            didDrag = false;
            if (!wasDrag && mouse.button === Qt.LeftButton) card.clicked();
        }
    }

    QQC.Menu {
        id: taskMenu
        QQC.MenuItem { text: "Открыть"; onTriggered: card.clicked() }
        QQC.MenuSeparator {}
        QQC.MenuItem { text: "Удалить"; onTriggered: AppController.deleteTask(card.taskId) }
    }
}
