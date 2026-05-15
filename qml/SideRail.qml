import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    width: 56

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1; color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 14
        spacing: 6

        RailBtn { glyph: "▦"; tooltipText: "My board"; active: true }
        RailBtn { glyph: "⌧"; tooltipText: "Backlog"
                   countText: AppController.countByStatus("backlog") > 0 ? AppController.countByStatus("backlog") : ""
                   countColor: Theme.textDim }
        RailBtn { glyph: "⊘"; tooltipText: "Blocked"
                   countText: AppController.countByStatus("blocked") > 0 ? AppController.countByStatus("blocked") : ""
                   countColor: Theme.p0 }
        RailBtn { glyph: "⎇"; tooltipText: "Code Review"
                   countText: AppController.countByStatus("review") > 0 ? AppController.countByStatus("review") : ""
                   countColor: Theme.stReview }

        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 24; height: 1; color: Theme.border; Layout.topMargin: 6; Layout.bottomMargin: 6 }

        RailBtn { glyph: "C++"; tooltipText: "Compiler Explorer"; fontPx: 10 }
        RailBtn { glyph: "§"; tooltipText: "Docs" }

        Item { Layout.fillHeight: true }

        RailBtn { glyph: "⚙"; tooltipText: "Settings"; Layout.bottomMargin: 14 }
    }

    component RailBtn: Item {
        id: btn
        property string glyph: ""
        property string tooltipText: ""
        property bool active: false
        property string countText: ""
        property color countColor: Theme.p0
        property int fontPx: 14
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: btn.active ? Theme.accentSoft
                 : ma.containsMouse ? Theme.panel2 : "transparent"
        }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: btn.active ? Theme.accentStrong : (ma.containsMouse ? Theme.text : Theme.textMuted)
            font.family: Theme.fontMono
            font.pixelSize: btn.fontPx
        }
        Rectangle {
            visible: btn.countText !== ""
            anchors.top: parent.top; anchors.right: parent.right
            anchors.topMargin: 2; anchors.rightMargin: 2
            radius: 6
            color: btn.countColor
            implicitWidth: cntT.implicitWidth + 8
            implicitHeight: cntT.implicitHeight + 2
            Text {
                id: cntT
                anchors.centerIn: parent
                text: btn.countText
                color: "white"
                font.family: Theme.fontMono
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }
        MouseArea {
            id: ma; anchors.fill: parent; hoverEnabled: true
            ToolTip.visible: containsMouse && btn.tooltipText !== ""
            ToolTip.text: btn.tooltipText
            ToolTip.delay: 400
        }
    }
}
