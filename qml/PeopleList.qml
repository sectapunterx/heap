import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel2
    implicitHeight: Math.min(220, col.implicitHeight + 24)

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: 1; color: Theme.border
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            spacing: 6
            Text {
                text: "КОМУ НАПИСАТЬ"
                color: Theme.textMuted
                font.pixelSize: 11
                font.letterSpacing: 1
                font.weight: Font.DemiBold
            }
            Rectangle {
                radius: 999
                color: Theme.panel3
                implicitWidth: badge.implicitWidth + 12
                implicitHeight: 18
                Text {
                    id: badge
                    anchors.centerIn: parent
                    text: AppController.pendingPeopleCount() + " pending · " + AppController.people.rowCount()
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
                Connections {
                    target: AppController.people
                    function onDataChanged() { badge.text = AppController.pendingPeopleCount() + " pending · " + AppController.people.rowCount() }
                }
            }
            Item { Layout.fillWidth: true }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: AppController.people

            delegate: Rectangle {
                id: prow
                required property string id
                required property string name
                required property string role
                required property string question
                required property string state
                required property var color
                width: ListView.view.width
                height: layout.implicitHeight + 12
                radius: 7
                color: stateMA.containsMouse ? Theme.panel : "transparent"
                border.color: stateMA.containsMouse ? Theme.border : "transparent"
                border.width: 1

                RowLayout {
                    id: layout
                    anchors.fill: parent
                    anchors.leftMargin: 8; anchors.rightMargin: 8
                    anchors.topMargin: 6; anchors.bottomMargin: 6
                    spacing: 10

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: prow.color
                        Text {
                            anchors.centerIn: parent
                            text: {
                                const parts = prow.name.split(/\s+/);
                                return (parts[0] ? parts[0][0] : "") + (parts[1] ? parts[1][0] : "");
                            }
                            color: "#06121a"
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1
                        Text {
                            width: parent.width
                            text: prow.name + "  · " + prow.role
                            color: (prow.state === "todo") ? Theme.text : Theme.textMuted
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: prow.question
                            color: Theme.textMuted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.strikeout: prow.state === "replied"
                            opacity: prow.state === "replied" ? 0.6 : 1.0
                        }
                    }
                    Rectangle {
                        radius: 999
                        color: prow.state === "pinged" ? Theme.withAlpha(Theme.p1, 0.10)
                             : prow.state === "replied" ? Theme.withAlpha(Theme.stDone, 0.10)
                             : Theme.bg2
                        border.color: prow.state === "pinged" ? Theme.withAlpha(Theme.p1, 0.4)
                                    : prow.state === "replied" ? Theme.withAlpha(Theme.stDone, 0.4)
                                    : Theme.border
                        border.width: 1
                        implicitWidth: stT.implicitWidth + 14
                        implicitHeight: 20
                        Text {
                            id: stT
                            anchors.centerIn: parent
                            text: prow.state === "todo" ? "НАПИСАТЬ"
                                : prow.state === "pinged" ? "НАПИСАЛ"
                                : "ОТВЕТИЛ"
                            color: prow.state === "pinged" ? Theme.p1
                                 : prow.state === "replied" ? Theme.stDone
                                 : Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.letterSpacing: 1
                        }
                    }
                }

                MouseArea {
                    id: stateMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AppController.cyclePerson(prow.id)
                }
            }
        }
    }
}
