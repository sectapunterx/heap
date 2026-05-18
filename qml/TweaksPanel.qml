import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: false
    focus: true
    padding: 0
    width: 260
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 0

        // Header
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            Layout.topMargin: 0
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 8
                Text {
                    text: "TWEAKS"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 22; height: 22; radius: 5
                    color: closeMA.containsMouse ? Theme.panel3 : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.textDim
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: closeMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14; Layout.rightMargin: 14
            Layout.topMargin: 12; Layout.bottomMargin: 14
            spacing: 14

            ColumnLayout {
                spacing: 6
                Layout.fillWidth: true
                Text { text: "Внешний вид"; color: Theme.textDim; font.pixelSize: 10; font.letterSpacing: 1; font.weight: Font.DemiBold }
                Text { text: "Тема"; color: Theme.textMuted; font.pixelSize: 11 }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    SegButton { text: "Тёмная";  active: AppController.theme === "dark";  onClicked: AppController.theme = "dark" }
                    SegButton { text: "Светлая"; active: AppController.theme === "light"; onClicked: AppController.theme = "light" }
                }
                Text { text: "Плотность"; color: Theme.textMuted; font.pixelSize: 11; topPadding: 6 }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    SegButton { text: "Compact"; active: AppController.density === "compact"; onClicked: AppController.density = "compact" }
                    SegButton { text: "Comfy";   active: AppController.density === "comfy";   onClicked: AppController.density = "comfy" }
                }
            }

            // Hint that workday hours now live in Settings → Calendar.
            Text {
                Layout.fillWidth: true
                text: "Рабочие часы и другие параметры — в Settings"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }
    }

    component SegButton: Rectangle {
        property string text: ""
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: 6
        color: active ? Theme.accent : (segMA.containsMouse ? Theme.panel3 : Theme.panel2)
        border.color: active ? "transparent" : Theme.border
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: parent.active ? "#06121a" : Theme.text
            font.pixelSize: 12
            font.weight: parent.active ? Font.DemiBold : Font.Medium
        }
        MouseArea {
            id: segMA
            x: 0; y: 0; width: parent.width; height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
