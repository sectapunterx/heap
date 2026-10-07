import QtQuick
import TodoCpp

// The keyboard cursor: where the next key acts. Every control draws it with
// this one item — ClickArea, buttons, fields, list rows, calendar grids and
// board cards — so it looks the same wherever the keyboard is (APP-174).
// Put one inside the control (a Rectangle or Item with activeFocusOnTab) and
// it shows while the control has focus; set `visible` for a cursor that is
// not focus (a list's current row, a board card).
//
// A 2px line in Theme.focusRing — the cursor colour, 3:1 against every
// surface on every theme — just outside the control, and a soft halo of the
// same colour outside that. Selection is never drawn with it: a selected
// card shows a fill and a check mark instead.
Rectangle {
    id: ring
    objectName: "focus-ring"
    property Item target: parent
    // The halo inside the line instead of outside it: for a ring on the edge
    // of something in a clipping list (a board card fills its column's
    // width), where an outer halo would be cut off at the sides.
    property bool haloInside: false
    anchors.fill: parent
    anchors.margins: -3
    radius: (target && typeof target.radius === "number" ? target.radius : Theme.radiusSm) + 3
    color: "transparent"
    border.color: Theme.focusRing
    border.width: 2
    visible: !!target && target.activeFocus
    z: 100

    Rectangle {
        objectName: "focus-ring-halo"
        anchors.fill: parent
        anchors.margins: ring.haloInside ? ring.border.width : -Theme.focusHaloWidth
        radius: ring.haloInside ? Math.max(0, ring.radius - ring.border.width)
                                : ring.radius + Theme.focusHaloWidth
        color: "transparent"
        border.color: Theme.focusHalo
        border.width: Theme.focusHaloWidth
    }
}
