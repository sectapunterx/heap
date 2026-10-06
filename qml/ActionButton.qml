import QtQuick
import TodoCpp

// A text button drawn the way Settings draws its actions (Connect, Test,
// Sync now, Export, Restore, Wipe…) that the keyboard can reach (design
// audit DES-8). Those were Rectangle + MouseArea: no Tab stop, no name for a
// screen reader, no disabled look. This one sits on the Tab path, runs on
// Return / Enter / Space, shows the FocusRing, and dims when disabled.
//
// `busy` is for an action that is waiting on the network (design audit
// DES-5): the label says what is happening and a second press does nothing
// until the result comes back. The button keeps keyboard focus while busy —
// disabling the item would drop focus to the window mid-action.
Rectangle {
    id: btn
    property string text: ""
    // "secondary" (panel fill), "primary" (accent fill), "danger" (tinted
    // danger), "quiet" (secondary with a dim label, e.g. Disconnect).
    property string kind: "secondary"
    // A two-step destructive action that is armed: the next press commits.
    property bool armed: false
    // Secondary at rest, accent under the pointer (Download update).
    property bool hoverAccent: false
    property bool busy: false
    property string busyText: ""
    signal activated()

    // What a press does right now; false while disabled or busy.
    readonly property bool available: enabled && !busy
    readonly property bool hot: ma.containsMouse && available
    readonly property string shownText: busy && busyText.length > 0 ? busyText : text

    function press() {
        if (btn.available) btn.activated()
    }

    implicitWidth: label.implicitWidth + 2 * Theme.spXl
    implicitHeight: 30
    radius: Theme.radiusMd
    opacity: !enabled ? 0.45 : (busy ? 0.75 : 1)
    color: {
        if (btn.kind === "primary") return btn.hot ? Theme.accentHover : Theme.accent
        if (btn.kind === "danger") return btn.armed ? Theme.danger
            : Theme.withAlpha(Theme.danger, btn.hot ? 0.20 : 0.10)
        if (btn.hoverAccent && btn.hot) return Theme.accent
        return btn.hot ? Theme.panel3 : Theme.panel2
    }
    border.color: btn.kind === "primary" ? Theme.accent
                : (btn.kind === "danger" || btn.armed) ? Theme.danger
                : Theme.border
    border.width: 1

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: btn.shownText
    Accessible.onPressAction: btn.press()
    Keys.onReturnPressed: btn.press()
    Keys.onEnterPressed: btn.press()
    Keys.onSpacePressed: btn.press()

    Text {
        id: label
        anchors.centerIn: parent
        text: btn.shownText
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsMd
        font.weight: btn.kind === "primary" ? Font.DemiBold
                   : btn.kind === "danger" ? Font.Medium : Font.Normal
        color: {
            if (btn.kind === "primary") return Theme.textOnAccent
            if (btn.kind === "danger") return btn.armed ? Theme.textOnDanger : Theme.danger
            if (btn.armed) return Theme.danger
            if (btn.hoverAccent && btn.hot) return Theme.textOnAccent
            return btn.kind === "quiet" ? Theme.textDim : Theme.text
        }
        // A slow pulse says "working" without a spinner asset.
        SequentialAnimation on opacity {
            running: btn.busy && !Theme.reducedMotion
            loops: Animation.Infinite
            onRunningChanged: if (!running) label.opacity = 1
            NumberAnimation { to: 0.45; duration: Theme.durPulse; easing.type: Theme.easePulse }
            NumberAnimation { to: 1; duration: Theme.durPulse; easing.type: Theme.easePulse }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: btn.press()
    }
    FocusRing {}
}
