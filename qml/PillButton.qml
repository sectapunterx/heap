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
    // A catalogue shortcut that does what this pill does. A third click with
    // the mouse suggests the key once (APP-166).
    property string shortcutId: ""
    // A Button's clicked() is the same for Space and the mouse; a pill only
    // takes focus from Tab, so the pointer over it means it was clicked.
    onClicked: if (root.shortcutId.length > 0 && root.hovered && !root.visualFocus) AppController.noteMouseAction(root.shortcutId)

    padding: Theme.spMd
    leftPadding: Theme.spXl

    // Reachable with Tab and named for screen readers; the focus ring below
    // is the only sign of where the keyboard is.
    // Tab focus only: a pill clicked with the mouse must not keep the keyboard
    // (the board cursor keys stand down while a tabbed-to control has it).
    focusPolicy: Qt.TabFocus
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
        // Outlined, never filled (DG-005, X/N-Dlg-Small): the primary
        // action has the brighter line, a selected one the segment's look.
        color: selected ? Theme.segmentSelected
              : root.hovered ? Theme.withAlpha(Theme.text, 0.05) : "transparent"
        border.color: danger  ? Theme.withAlpha(Theme.danger, root.hovered ? 0.7 : 0.45)
                   : primary ? (root.hovered ? Theme.textDim : Theme.buttonLinePrimary)
                   : selected ? (Style.fills ? "transparent" : Theme.segmentSelectedLine)
                   : (root.hovered ? Theme.buttonLinePrimary : Theme.buttonLine)
        border.width: 1
        // The cursor sits outside the pill, on the surface around it: a
        // border on a primary button's accent fill was 1.1–1.4:1 and could
        // not be seen. Theme.focusRing holds 3:1 on every surface.
        FocusRing {
            objectName: "pill-focus-ring"
            visible: root.visualFocus
        }
    }
    contentItem: Text {
        text: root.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsMd
        font.weight: selected ? Theme.segmentSelectedWeight : Theme.fwBody
        color: danger ? Theme.danger
             : primary || selected || root.hovered ? Theme.buttonTextPrimary : Theme.buttonText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
