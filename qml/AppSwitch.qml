import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

// A themed on/off switch with its label (heap 2): the stock Basic track was
// 1.09:1 against a popup (DES-20). The label is the accessible name.
Switch {
    id: sw

    font.family: Theme.fontUi
    font.pixelSize: Theme.fsSm
    spacing: Theme.spMd
    Accessible.name: sw.text

    indicator: Rectangle {
        implicitWidth: 36
        implicitHeight: 20
        x: sw.leftPadding
        y: (sw.height - height) / 2
        radius: height / 2
        color: sw.checked ? Theme.accent : Theme.panel3
        border.color: sw.visualFocus ? Theme.focusRing : sw.checked ? Theme.accent : Theme.fieldBorder
        border.width: sw.visualFocus ? 2 : 1
        Rectangle {
            width: 16; height: 16; radius: 8
            x: sw.checked ? parent.width - width - 2 : 2
            y: 2
            color: Theme.knob
            border.color: Theme.fieldBorder
            border.width: 1
            Behavior on x { NumberAnimation { duration: Theme.durTap; easing.type: Theme.easeEnter } }
        }
    }
    contentItem: Text {
        leftPadding: sw.indicator.width + sw.spacing
        verticalAlignment: Text.AlignVCenter
        text: sw.text
        font: sw.font
        color: sw.enabled ? Theme.text : Theme.textDim
    }
}
