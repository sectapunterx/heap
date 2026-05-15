import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    height: 48

    property alias searchText: searchField.text
    signal newTaskRequested()

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1; color: Theme.border
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16; anchors.rightMargin: 16
        spacing: 14

        // Brand
        RowLayout {
            spacing: 8
            Rectangle {
                width: 10; height: 10; radius: 3
                color: Theme.accent
                layer.enabled: true
            }
            Text {
                text: "todo<span style=\"color:" + Theme.textMuted + "\">·</span>cpp"
                textFormat: Text.RichText
                color: Theme.text
                font.family: Theme.fontMono
                font.weight: Font.DemiBold
                font.pixelSize: 13
            }
        }

        // Breadcrumbs
        Text {
            text: "<b>eNB-core</b> / " + AppController.sprintLabel() + " / <b>You</b>"
            textFormat: Text.RichText
            color: Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: 12
        }

        Item { Layout.fillWidth: true }

        // Search
        Rectangle {
            Layout.preferredWidth: 280
            Layout.preferredHeight: 28
            radius: 6
            color: Theme.panel2
            border.color: Theme.border
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 6
                spacing: 4
                Text { text: "⌕"; color: Theme.textDim; font.pixelSize: 11 }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Поиск задач, ID, branch…"
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    background: Item {}
                    selectByMouse: true
                }
                Rectangle {
                    radius: 4
                    border.color: Theme.border; border.width: 1
                    color: "transparent"
                    width: kbd.implicitWidth + 10; height: 16
                    Text {
                        id: kbd; anchors.centerIn: parent
                        text: "⌘K"; color: Theme.textDim
                        font.family: Theme.fontMono; font.pixelSize: 10
                    }
                }
            }
        }

        PillButton {
            text: "+ Task"
            primary: true
            onClicked: root.newTaskRequested()
        }
    }
}
