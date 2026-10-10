import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// One field of a small dialog (X-Dlg-Small): a small muted label over an
// outlined input. `mono` for a query or an address.
ColumnLayout {
    id: root
    property string label: ""
    property bool mono: false
    property alias text: input.text
    property alias placeholderText: input.placeholderText
    property alias maximumLength: input.maximumLength
    readonly property alias input: input
    property string fieldName: ""
    signal accepted()

    function focusField() { input.forceActiveFocus(); input.selectAll(); }

    Layout.fillWidth: true
    spacing: Theme.spXs

    Text {
        text: root.label
        color: Theme.textMuted
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsXs
    }
    TextField {
        id: input
        objectName: root.fieldName
        ContextMenu.menu: TextEditMenu { editor: input }
        Layout.fillWidth: true
        implicitHeight: Theme.chipH + Theme.spSm
        leftPadding: Theme.spMd
        rightPadding: Theme.spMd
        color: Theme.text
        placeholderTextColor: Theme.textDim
        font.family: root.mono ? Theme.fontMono : Theme.fontUi
        font.pixelSize: root.mono ? Theme.fsSm : Theme.fsMd
        selectByMouse: true
        Accessible.name: root.label
        background: Rectangle {
            radius: Theme.radiusMd
            color: "transparent"
            border.width: 1
            border.color: input.activeFocus ? Theme.borderStrong : Theme.fieldBorder
        }
        onAccepted: root.accepted()
    }
}
