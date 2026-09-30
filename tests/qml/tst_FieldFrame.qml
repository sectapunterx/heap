// Design audit DES-2: the editors' combo boxes and most text fields drew a
// fixed outline, so Tab moved through a form with no sign of where focus was.
// FieldFrame shows a thicker focusRing outline while its control has focus
// (and while a combo's list is open), and a 3:1 outline otherwise.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "FieldFrame"
    when: windowShown
    visible: true
    width: 400
    height: 200

    Column {
        TextField { id: field; width: 200; background: FieldFrame {} }
        ComboBox { id: combo; width: 200; model: ["a", "b"]; background: FieldFrame {} }
        TextField { id: other; width: 200 }
    }

    function test_text_field_shows_focus() {
        other.forceActiveFocus();
        const f = field.background;
        compare(String(f.border.color), String(Theme.fieldBorder));
        compare(f.border.width, 1);
        field.forceActiveFocus(Qt.TabFocusReason);
        compare(String(f.border.color), String(Theme.focusRing));
        compare(f.border.width, 2);
    }

    function test_combo_shows_focus_and_keeps_it_while_open() {
        other.forceActiveFocus();
        const f = combo.background;
        verify(!f.focused);
        combo.forceActiveFocus(Qt.TabFocusReason);
        verify(f.focused);
        compare(String(f.border.color), String(Theme.focusRing));
        combo.popup.open();
        tryVerify(function () { return combo.popup.visible; }, 1000);
        verify(f.focused, "a combo whose list is open lost its ring");
        combo.popup.close();
    }

    // The resting outline is the 3:1 field token, not the hairline divider.
    function test_resting_outline_is_the_field_token() {
        other.forceActiveFocus();
        verify(String(field.background.border.color) !== String(Theme.border) || String(Theme.border) === String(Theme.fieldBorder));
        compare(String(field.background.border.color), String(Theme.fieldBorder));
    }
}
