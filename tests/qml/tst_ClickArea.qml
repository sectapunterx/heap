// Design audit DES-19: ClickArea is what a hand-drawn clickable puts inside
// itself instead of a bare MouseArea — Tab, Return / Enter / Space, a name for
// a screen reader, a tooltip with the shortcut, and a 24px hit area.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ClickArea"
    when: windowShown
    visible: true
    width: 300
    height: 120

    property int fired: 0
    property int context: 0

    Row {
        x: 40; y: 40
        spacing: 20
        Item { id: before; width: 10; height: 10; activeFocusOnTab: true }
        Rectangle {
            id: small
            width: 16; height: 16; radius: 4
            ClickArea {
                id: area
                label: "Delete column"
                shortcutId: "undo"
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onActivated: tc.fired++
                onContextRequested: tc.context++
            }
        }
        Rectangle {
            width: 30; height: 30
            ClickArea { id: off; label: "Off"; enabled: false; onActivated: tc.fired++ }
        }
    }

    function init() { tc.fired = 0; tc.context = 0; before.forceActiveFocus(); }

    function test_on_the_tab_path_and_named() {
        verify(area.activeFocusOnTab);
        compare(area.Accessible.role, Accessible.Button);
        compare(area.Accessible.name, "Delete column");
        verify(!off.activeFocusOnTab, "a disabled ClickArea is still on the Tab path");
    }

    function test_keys_run_it() {
        area.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Enter);
        keyClick(Qt.Key_Space);
        compare(tc.fired, 3);
    }

    // A 16px parent still takes a click 4px outside its edge.
    function test_hit_area_is_at_least_24px() {
        mouseClick(small, -3, 8);
        compare(tc.fired, 1, "a click just outside the 16px shape missed");
        mouseClick(small, 8, 8, Qt.RightButton);
        compare(tc.context, 1);
    }

    function test_tooltip_carries_the_shortcut() {
        const keys = AppController.shortcutFor("undo");
        verify(keys.length > 0);
        compare(area._tipText, "Delete column  " + keys);
    }

    function test_disabled_ignores_clicks() {
        mouseClick(off.parent, 15, 15);
        compare(tc.fired, 0);
    }
}
