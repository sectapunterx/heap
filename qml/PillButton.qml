import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

Button {
    id: root
    property bool primary: false
    property bool danger: false

    padding: 8
    leftPadding: 12
    rightPadding: 12

    background: Rectangle {
        radius: 6
        color: primary ? Theme.accent
              : danger  ? Theme.withAlpha(Theme.p0, 0.12)
              : root.hovered ? Theme.panel3 : Theme.panel2
        border.color: primary ? "transparent"
                   : danger  ? Theme.withAlpha(Theme.p0, 0.4)
                   : (root.hovered ? Theme.borderStrong : Theme.border)
        border.width: 1
    }
    contentItem: Text {
        text: root.text
        font.family: Theme.fontUi
        font.pixelSize: 12
        font.weight: primary ? Font.DemiBold : Font.Medium
        color: primary ? "#06121a" : danger ? Theme.p0 : Theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
