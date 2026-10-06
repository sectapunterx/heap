import QtQuick
import QtQuick.Controls
import TodoCpp

// A small glyph button (✎, ×) that the keyboard can reach (design audit
// DES-3). The Docs row actions were Rectangle + MouseArea enabled only on
// hover, so edit and delete had no keyboard path at all. This one sits on
// the Tab path even while hidden, shows itself when it gets focus, runs on
// Return / Enter / Space, and names itself to a screen reader and in a
// tooltip. Callers that reveal their actions on hover bind `revealed`.
Rectangle {
    id: btn
    property string glyph: ""
    property string label: ""
    property bool danger: false
    // False hides the button until the pointer (or focus) reaches it.
    property bool revealed: true
    // The fill at rest: the Docs headers draw on the page, the cards on panel2.
    property color restColor: Theme.panel2
    signal activated()

    readonly property bool shown: revealed || activeFocus
    readonly property bool hot: ma.containsMouse || activeFocus

    width: 22
    height: 22
    radius: Theme.radiusSm
    opacity: shown ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: btn.shown ? Theme.durTap : Theme.durTapOut
            easing.type: btn.shown ? Theme.easeEnter : Theme.easeExit
        }
    }
    color: hot ? (danger ? Theme.withAlpha(Theme.danger, 0.16) : Theme.panel3) : restColor
    border.color: hot && danger ? Theme.danger : Theme.border
    border.width: 1

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: btn.activated()
    Keys.onReturnPressed: btn.activated()
    Keys.onEnterPressed: btn.activated()
    Keys.onSpacePressed: btn.activated()

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        color: btn.hot && btn.danger ? Theme.danger : Theme.textMuted
        font.pixelSize: btn.danger ? Theme.fsMd : Theme.fsSm
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: btn.shown
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
    }
    ToolTip.visible: ma.containsMouse && btn.label.length > 0
    ToolTip.delay: 500
    ToolTip.text: btn.label
    FocusRing {}
}
