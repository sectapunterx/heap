// Design audit DES-3: the Docs row actions (✎, ×) were Rectangle + MouseArea
// enabled only on hover, so edit and delete had no keyboard path at all.
// IconButton stays on the Tab path while hidden, shows itself on focus, runs
// on Return / Enter / Space and names itself to a screen reader.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "IconButton"
    when: windowShown
    visible: true
    width: 300
    height: 100

    property int fired: 0

    Row {
        Item { id: before; width: 10; height: 10; activeFocusOnTab: true }
        IconButton {
            id: btn
            glyph: "×"
            label: "Delete section"
            danger: true
            revealed: false
            onActivated: tc.fired++
        }
    }

    function init() { tc.fired = 0; before.forceActiveFocus(); }

    function test_hidden_until_it_gets_focus() {
        compare(btn.opacity, 0);
        verify(btn.activeFocusOnTab, "a hover-revealed action is still on the Tab path");
        btn.forceActiveFocus(Qt.TabFocusReason);
        verify(btn.activeFocus);
        verify(btn.shown);
        tryCompare(btn, "opacity", 1, 1000);
    }

    function test_keys_run_it() {
        btn.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Enter);
        compare(tc.fired, 3);
    }

    function test_names_itself() {
        compare(btn.Accessible.name, "Delete section");
        compare(btn.Accessible.role, Accessible.Button);
    }

    // Revealed by hover: the pointer can click it as before.
    function test_revealed_button_clicks() {
        btn.revealed = true;
        tryCompare(btn, "opacity", 1, 1000);
        mouseClick(btn);
        compare(tc.fired, 1);
        btn.revealed = false;
    }
}
