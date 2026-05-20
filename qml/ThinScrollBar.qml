// Thin translucent scrollbar that mirrors the design prototype's
// styles.css scrollbar treatment (6-8px thumb, fades when idle).
// Use as: ScrollBar.vertical: ThinScrollBar {}
import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

ScrollBar {
    id: sb
    policy: ScrollBar.AsNeeded
    minimumSize: 0.06

    contentItem: Rectangle {
        implicitWidth: 6
        implicitHeight: 6
        radius: 3
        color: sb.pressed ? Theme.withAlpha(Theme.text, 0.45)
             : sb.hovered ? Theme.withAlpha(Theme.text, 0.30)
             :              Theme.withAlpha(Theme.text, 0.18)
        opacity: sb.policy === ScrollBar.AlwaysOn || sb.active || sb.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.scaledMs(180) } }
        Behavior on color   { ColorAnimation  { duration: Theme.scaledMs(120) } }
    }

    background: Item {}
}
