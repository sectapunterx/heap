// Type to search on the board (APP-117, src/TypeAhead.*): a letter
// typed with no text field focused is handed over to start a search; one typed
// into a field stays in the field; a key with Ctrl, Alt or nothing printable
// is left to the shortcuts.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TypeAhead"
    when: windowShown
    visible: true
    width: 400
    height: 200

    Item {
        id: plain
        focus: true
        width: 100; height: 40
    }
    TextInput {
        id: field
        y: 60
        width: 200; height: 30
    }
    TypeAhead {
        id: ahead
        enabled: true
    }
    SignalSpy { id: spy; target: ahead; signalName: "typed" }

    function init() {
        spy.clear();
        field.text = "";
        ahead.enabled = true;
        plain.forceActiveFocus();
    }

    function test_a_letter_with_nothing_focused_starts_a_search() {
        keyClick(Qt.Key_Q);
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], "q");
    }

    function test_shift_types_a_capital() {
        keyClick("Q");
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], "Q");
    }

    function test_a_digit_counts() {
        keyClick(Qt.Key_7);
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], "7");
    }

    function test_a_focused_field_keeps_its_letters() {
        field.forceActiveFocus();
        keyClick(Qt.Key_Q);
        compare(spy.count, 0);
        compare(field.text, "q");
    }

    function test_modified_and_blank_keys_are_left_alone() {
        keyClick(Qt.Key_Q, Qt.ControlModifier);
        keyClick(Qt.Key_Q, Qt.AltModifier);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_Down);
        compare(spy.count, 0);
    }

    function test_disabled_takes_nothing() {
        ahead.enabled = false;
        keyClick(Qt.Key_Q);
        compare(spy.count, 0);
    }
}
