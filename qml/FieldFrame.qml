import QtQuick
import TodoCpp

// The background of a text field or combo box: panel2 with an outline that
// reads at 3:1 (Theme.fieldBorder), and a thicker Theme.focusRing outline
// while the control has the keyboard (design audit DES-2). The editors'
// combos drew a fixed border, so Tab moved through them with no sign of
// where focus was. Use as `background: FieldFrame {}`.
Rectangle {
    // var, not Item: the combo's `popup` is not an Item member.
    property var control: parent
    // A combo keeps the ring while its list is open.
    readonly property bool focused: !!control && (control.activeFocus
        || (!!control.popup && control.popup.visible === true))
    radius: Theme.radiusMd
    color: Theme.panel2
    border.color: focused ? Theme.focusRing : Theme.fieldBorder
    border.width: focused ? 2 : 1
}
