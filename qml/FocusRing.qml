import QtQuick
import TodoCpp

// The keyboard focus ring for a hand-drawn control: put one inside the
// control (a Rectangle or Item with activeFocusOnTab) and it shows while the
// control has focus. Drawn just outside the control, on the surface around
// it, in Theme.focusRing — 3:1 against every surface on every theme.
Rectangle {
    id: ring
    property Item target: parent
    anchors.fill: parent
    anchors.margins: -3
    radius: (target && typeof target.radius === "number" ? target.radius : Theme.radiusSm) + 3
    color: "transparent"
    border.color: Theme.focusRing
    border.width: 2
    visible: !!target && target.activeFocus
    z: 100
}
