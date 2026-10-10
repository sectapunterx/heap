import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import TodoCpp

// A settings row with a text field (Settings, APP-172): the field commits on
// Enter or focus loss, never per keystroke; `commitPending()` flushes an edit
// before an action that does not take focus.
SettingsRow {
    id: textRow
    property string placeholder: ""
    property bool mono: false
    property bool secret: false
    // A password is masked even while focused.
    property bool alwaysMasked: false
    property string value: ""
    property int fieldWidth: 300
    property alias validator: textRowField.validator
    // A time of day: only H:mm / HH:mm is accepted, committed as HH:mm.
    property bool clockTime: false
    property bool upperCase: false
    readonly property RegularExpressionValidator _clockValidator: RegularExpressionValidator {
        regularExpression: /^([01]?[0-9]|2[0-3]):[0-5][0-9]$/
    }
    function _clock(t) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(String(t).trim());
        return m ? m[1].padStart(2, "0") + ":" + m[2] : t;
    }
    readonly property bool invalid: textRowField.text.length > 0 && !textRowField.acceptableInput
    signal committed(string text)
    function currentText() { return textRowField.text; }
    function clear() { textRowField.text = ""; }
    function pendingText() {
        return textRowField.text !== textRow.value ? textRowField.text : null;
    }
    // Flush a pending edit without waiting for focus loss: buttons here
    // never take focus.
    function commitPending() {
        const t = pendingText();
        if (t === null) return;
        if (textRowField.validator && !textRowField.acceptableInput) {
            textRowField.text = textRow.value;
            return;
        }
        textRow.committed(textRow.clockTime ? textRow._clock(t) : t);
    }
    hintColor: textRow.invalid ? Theme.danger : Theme.textDim
    // A direct child of the row: callers find the field among the row's
    // own children.
    control: TextField {
        id: textRowField
        ContextMenu.menu: TextEditMenu { editor: textRowField }
        objectName: textRow.objectName.length > 0 ? textRow.objectName + "-field" : ""
        validator: textRow.clockTime ? textRow._clockValidator : null
        Accessible.name: textRow.label
        Accessible.description: textRow.hint
        implicitWidth: textRow.fieldWidth
        implicitHeight: Theme.px(30)
        placeholderText: textRow.placeholder
        placeholderTextColor: Theme.textDim
        color: Theme.text
        font.family: textRow.mono ? Theme.fontMono : Theme.fontUi
        font.pixelSize: Theme.fsSm
        font.capitalization: textRow.upperCase ? Font.AllUppercase : Font.MixedCase
        echoMode: (textRow.alwaysMasked || (textRow.secret && !activeFocus)) ? TextInput.Password : TextInput.Normal
        background: FieldFrame { border.color: textRow.invalid ? Theme.danger : (textRowField.activeFocus ? Theme.focusRing : Theme.fieldBorder) }
        selectByMouse: true
        text: textRow.value
        // A long value (a JQL query) reads from its start, not its end.
        onTextChanged: if (!activeFocus) cursorPosition = 0
        onActiveFocusChanged: {
            if (!activeFocus) {
                textRow.commitPending();
                cursorPosition = 0;
            }
        }
        onAccepted: textRow.commitPending()
    }
}
