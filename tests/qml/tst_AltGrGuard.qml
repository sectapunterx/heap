// SHELL-2 (audit 2026-09-30): Windows reports AltGr as Ctrl+Alt, so the
// Ctrl+Alt+E / N / L shortcuts fired while typing and ate €, ę, ł, ń. With a
// text field focused the chord belongs to the field (AltGrGuard, installed on
// the application by main() and by the test runner); elsewhere it still fires.
import QtQuick
import QtQuick.Controls
import QtTest

TestCase {
    id: tc
    name: "AltGrGuard"
    when: windowShown
    visible: true
    width: 400
    height: 300

    property int fired: 0

    Shortcut {
        sequence: "Ctrl+Alt+E"
        context: Qt.ApplicationShortcut
        onActivated: tc.fired++
    }

    Column {
        TextField { id: field; width: 200 }
        TextArea { id: area; width: 200; height: 60 }
        TextField { id: ro; width: 200; readOnly: true }
        Rectangle { id: plain; width: 50; height: 20; focus: false; activeFocusOnTab: true }
    }

    function init() { tc.fired = 0; field.text = ""; area.text = ""; }

    function test_a_text_field_keeps_the_chord() {
        field.forceActiveFocus();
        verify(field.activeFocus);
        keyClick(Qt.Key_E, Qt.ControlModifier | Qt.AltModifier);
        compare(tc.fired, 0, "Ctrl+Alt+E fired while typing in a TextField");
    }

    function test_a_text_area_keeps_the_chord() {
        area.forceActiveFocus();
        keyClick(Qt.Key_E, Qt.ControlModifier | Qt.AltModifier);
        compare(tc.fired, 0, "Ctrl+Alt+E fired while typing in a TextArea");
    }

    function test_outside_a_text_field_it_still_fires() {
        plain.forceActiveFocus();
        keyClick(Qt.Key_E, Qt.ControlModifier | Qt.AltModifier);
        compare(tc.fired, 1);
    }

    function test_a_read_only_field_does_not_hold_it() {
        ro.forceActiveFocus();
        keyClick(Qt.Key_E, Qt.ControlModifier | Qt.AltModifier);
        compare(tc.fired, 1);
    }
}
