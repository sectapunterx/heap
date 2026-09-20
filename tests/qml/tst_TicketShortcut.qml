// "O" opens the selected ticket (HEAP-117). It is the first bare letter in the
// shortcut catalog, so the thing worth pinning is that it does not steal
// ordinary typing: Qt hands a focused text field the ShortcutOverride for an
// unmodified key below Key_Escape, which the docs do not spell out.
//
// Nothing here calls openTaskExternal — that would open a browser.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TicketShortcut"
    when: windowShown
    visible: true
    width: 400
    height: 220

    property int fired: 0

    Item {
        id: host
        anchors.fill: parent

        Shortcut {
            objectName: "ts-shortcut"
            sequence: "O"
            context: Qt.ApplicationShortcut
            onActivated: tc.fired++
        }

        TextField {
            id: field
            objectName: "ts-field"
            anchors.centerIn: parent
            width: 200
        }
    }

    function init() {
        tc.fired = 0;
        field.text = "";
        field.focus = false;
    }

    // The whole reason a bare letter is safe: typing into a field types.
    function test_letter_shortcut_does_not_steal_textfield_typing() {
        field.forceActiveFocus();
        verify(field.activeFocus);
        keyClick(Qt.Key_O);
        compare(field.text, "o", "the shortcut swallowed a keystroke meant for the field");
        compare(tc.fired, 0, "the shortcut fired while a text field had focus");
    }

    // …and with nothing focused it is a shortcut again.
    function test_fires_when_no_text_field_has_focus() {
        field.focus = false;
        host.forceActiveFocus();
        keyClick(Qt.Key_O);
        compare(tc.fired, 1, "the shortcut did not fire outside a text field");
    }

    // The binding the app actually ships, read back through the catalog.
    function test_default_binding_is_o_and_is_rebindable() {
        compare(AppController.defaultShortcutFor("task.openExternal"), "O");
        verify(AppController.shortcutLabel("task.openExternal").length > 0,
               "the shortcut has no translated label for the Settings list");
        verify(AppController.setShortcut("task.openExternal", "Ctrl+Shift+O"));
        compare(AppController.shortcutFor("task.openExternal"), "Ctrl+Shift+O");
        AppController.resetShortcut("task.openExternal");
        compare(AppController.shortcutFor("task.openExternal"), "O");
    }
}
