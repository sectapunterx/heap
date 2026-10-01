import QtQuick
import QtQuick.Controls
import TodoCpp

// What a hand-drawn clickable (a Rectangle with a glyph or a label) puts
// inside itself instead of a bare MouseArea (design audit DES-19). About 150
// of them were MouseArea only: no Tab stop, no name for a screen reader, no
// keyboard way to run them, often a hit area under 24px. This one fills its
// parent and gives it all of that:
//
//   Rectangle {
//       width: 22; height: 22; radius: Theme.radiusSm
//       color: add.hovered ? Theme.panel3 : "transparent"
//       Text { anchors.centerIn: parent; text: "+" }
//       ClickArea { id: add; label: I18n.t("kanban.addTask"); onActivated: … }
//   }
//
// - Tab reaches it, Return / Enter / Space run it, the focus ring is drawn
//   around the parent's shape.
// - `label` is its accessible name and, unless `tip` says otherwise, its
//   tooltip; `shortcutId` adds the shortcut as bound now to the tooltip.
// - The hit area grows to `minTarget` (24px, WCAG 2.5.8) around a smaller
//   parent without moving anything.
// - `enabled: false` takes it off the Tab path and ignores the pointer; the
//   parent keeps drawing itself, so dim it there if it should look disabled.
Item {
    id: ca
    property string label: ""
    // Tooltip text; the label when empty. `showTip: false` for a control
    // whose label is already written on it.
    property string tip: ""
    property bool showTip: true
    // A catalogue shortcut to show in the tooltip ("Delete  Del").
    property string shortcutId: ""
    property int minTarget: 24
    property int acceptedButtons: Qt.LeftButton
    property int cursorShape: Qt.PointingHandCursor
    // Accessible role: Button by default; CheckBox for a toggle (set `checked`).
    property int role: Accessible.Button
    property bool checkable: false
    property bool checked: false

    readonly property bool hovered: ma.containsMouse
    readonly property bool pressed: ma.pressed
    readonly property bool keyboardFocused: ca.activeFocus

    signal activated()
    // Right button, when `acceptedButtons` asks for it.
    signal contextRequested(real x, real y)

    anchors.fill: parent
    activeFocusOnTab: ca.enabled && ca.visible

    Accessible.role: ca.role
    Accessible.name: ca.label
    Accessible.checkable: ca.checkable
    Accessible.checked: ca.checked
    Accessible.onPressAction: ca.activated()
    Accessible.onToggleAction: ca.activated()
    Keys.onReturnPressed: ca.activated()
    Keys.onEnterPressed: ca.activated()
    Keys.onSpacePressed: ca.activated()

    MouseArea {
        id: ma
        anchors.centerIn: parent
        width: Math.max(ca.width, ca.minTarget)
        height: Math.max(ca.height, ca.minTarget)
        hoverEnabled: true
        acceptedButtons: ca.acceptedButtons
        cursorShape: ca.cursorShape
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) ca.contextRequested(mouse.x, mouse.y);
            else ca.activated();
        }
    }

    readonly property string _tipText: {
        const base = ca.tip.length > 0 ? ca.tip : ca.label;
        const keys = ca.shortcutId.length > 0 ? AppController.shortcutFor(ca.shortcutId) : "";
        return keys.length > 0 && base.length > 0 ? base + "  " + keys : base;
    }
    ToolTip.visible: ca.showTip && ma.containsMouse && ca._tipText.length > 0
    ToolTip.delay: 500
    ToolTip.text: ca._tipText

    // var, not Item: the parent's `radius` is not an Item member.
    readonly property var _shape: ca.parent
    // Around the parent's shape, outside it, like FocusRing.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: (ca._shape && typeof ca._shape.radius === "number" ? ca._shape.radius : Theme.radiusSm) + 3
        color: "transparent"
        border.color: Theme.focusRing
        border.width: 2
        visible: ca.activeFocus
        z: 100
    }
}
