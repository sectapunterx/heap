import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Item {
    id: root
    width: 260
    height: collapsed ? 36 : col.implicitHeight + 28
    property bool collapsed: true

    Behavior on height { NumberAnimation { duration: 120 } }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
        opacity: 0.96
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "TWEAKS"
                color: Theme.textMuted
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
            Item { Layout.fillWidth: true }
            Text {
                text: root.collapsed ? "▾" : "▴"
                color: Theme.textDim
                font.pixelSize: 12
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.collapsed = !root.collapsed
            }
        }

        ColumnLayout {
            visible: !root.collapsed
            spacing: 10
            Layout.fillWidth: true

            Text { text: "Тема"; color: Theme.textDim; font.pixelSize: 11 }
            RowLayout {
                spacing: 4
                SegButton { text: "Тёмная";  active: AppController.theme === "dark";  onClicked: AppController.theme = "dark" }
                SegButton { text: "Светлая"; active: AppController.theme === "light"; onClicked: AppController.theme = "light" }
            }

            Text { text: "Плотность"; color: Theme.textDim; font.pixelSize: 11 }
            RowLayout {
                spacing: 4
                SegButton { text: "Compact"; active: AppController.density === "compact"; onClicked: AppController.density = "compact" }
                SegButton { text: "Comfy";   active: AppController.density === "comfy";   onClicked: AppController.density = "comfy" }
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
