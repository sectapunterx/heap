import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    height: 44
    property var priorities: ({})  // map P0..P3 -> bool
    property int totalCount: 0
    property int activeCount: 0
    property int blockedCount: 0
    property int reviewCount: 0
    property string viewLabel: "Board"

    signal togglePriority(string p)
    signal clearPriorities()

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1; color: Theme.border
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16; anchors.rightMargin: 16
        spacing: 8

        Text {
            text: "<b><font color=\"" + Theme.text + "\">" + root.viewLabel + "</font></b> · Filters:"
            textFormat: Text.RichText
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: 12
        }

        Repeater {
            model: ["P0", "P1", "P2", "P3"]
            delegate: Rectangle {
                required property string modelData
                property bool active: root.priorities[modelData] === true
                radius: 999
                color: active ? Theme.accentSoft : Theme.panel2
                border.color: active ? Theme.accent : Theme.border
                border.width: 1
                implicitWidth: chRow.implicitWidth + 20
                implicitHeight: 24
                RowLayout {
                    id: chRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 2
                        color: Theme.priorityColor(modelData)
                    }
                    Text {
                        text: modelData
                        color: parent.parent.active ? Theme.accentStrong : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePriority(modelData)
                }
            }
        }

        Rectangle {
            visible: {
                let any = false;
                for (const k in root.priorities) if (root.priorities[k]) any = true;
                return any;
            }
            radius: 999
            border.color: Theme.border; border.width: 1
            color: Theme.panel2
            implicitWidth: clrT.implicitWidth + 16
            implicitHeight: 24
            Text {
                id: clrT
                anchors.centerIn: parent
                text: "clear"
                color: Theme.textDim
                font.pixelSize: 11
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearPriorities()
            }
        }

        Item { Layout.fillWidth: true }

        Text {
            text: root.totalCount + " tasks · " + root.activeCount + " active · "
                  + root.blockedCount + " blocked · " + root.reviewCount + " review"
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: 11
        }
    }
}
