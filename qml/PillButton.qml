import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

Button {
    id: root
    property bool primary: false
    property bool danger: false
    // A toggle that is on. Not `primary`: a filled accent pill is the one
    // action a screen offers, and a toggle painted the same way competed
    // with "+ Task" for it.
    property bool selected: false

    padding: Theme.spMd
    leftPadding: Theme.spXl

    // Reachable with Tab and named for screen readers; the focus ring below
    // is the only sign of where the keyboard is.
    focusPolicy: Qt.StrongFocus
    Accessible.role: Accessible.Button
    Accessible.name: root.text
    rightPadding: Theme.spXl

    // Every hand-rolled button in the app switches the cursor; this one is a
    // Controls Button, which doesn't, so pills were the only clickable things
    // that kept an arrow cursor. A HoverHandler adds it without touching clicks.
    HoverHandler {
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }
    // A disabled pill (e.g. "Create" before quick-capture has a title) used to
    // look exactly like an enabled one.
    opacity: enabled ? 1 : 0.45

    background: Rectangle {
        radius: Theme.radiusMd
        color: primary ? Theme.accent
              : danger  ? Theme.withAlpha(Theme.danger, 0.12)
              : selected ? Theme.accentSoft
              : root.hovered ? Theme.panel3 : Theme.panel2
        border.color: primary ? "transparent"
                   : danger  ? Theme.withAlpha(Theme.danger, 0.4)
                   : selected ? Theme.withAlpha(Theme.accent, 0.5)
                   : (root.hovered ? Theme.borderStrong : Theme.border)
        border.width: 1
        // The focus ring sits outside the pill, on the surface around it: an
        // accentStrong border on a primary button's accent fill was 1.1–1.4:1
        // and could not be seen. Theme.focusRing holds 3:1 on every surface.
        Rectangle {
            objectName: "pill-focus-ring"
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            color: "transparent"
            visible: root.visualFocus
            border.color: Theme.focusRing
            border.width: 2
        }
    }
    contentItem: Text {
        text: root.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsMd
        font.weight: primary ? Font.DemiBold : Font.Medium
        color: primary ? Theme.textOnAccent : danger ? Theme.danger : selected ? Theme.accentStrong : Theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
