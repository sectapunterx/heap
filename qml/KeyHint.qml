import QtQuick
import TodoCpp

// A key beside the action it runs (APP-259): "d", "Shift S", "g b",
// "Ctrl K". Notation (keymap.md): a lowercase letter is the key without
// Shift, Shift is spelled out, a two-key sequence is written with a space.
// On-screen hints (the bar at the bottom, the selected card, a lens tab)
// follow Style.keyHints; a menu shows its keys always (`always: true`).
Text {
    id: root

    property string keys: ""
    property bool always: false

    visible: keys.length > 0 && (always || Style.keyHints)
    text: keys
    color: Theme.textDim
    font.family: Theme.fontMono
    font.pixelSize: Theme.fsXs
    verticalAlignment: Text.AlignVCenter
    Accessible.ignored: true
}
