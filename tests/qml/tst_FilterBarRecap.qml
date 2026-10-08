// The weekly recap button on the board's bar (APP-211): shown on the board
// only, a dot while this week's recap is unseen, and a click or the keyboard
// asks for the recap. The tooltip names the recap.open hotkey when one is set.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "FilterBarRecap"
    when: windowShown
    visible: true
    width: 1000
    height: 200

    Item { id: host; anchors.fill: parent }

    function make(show) {
        const bar = createTemporaryQmlObject('import TodoCpp; FilterBar { width: 1000 }', host);
        verify(bar !== null);
        bar.showRecap = show;
        return bar;
    }

    function test_only_where_asked() {
        verify(!findChild(make(false), "recap-button").visible);
        verify(findChild(make(true), "recap-button").visible);
    }

    function test_the_dot_follows_unseen() {
        const bar = make(true);
        const dot = findChild(findChild(bar, "recap-button"), "bar-chip-dot");
        verify(dot !== null);
        verify(!dot.visible);
        bar.recapUnseen = true;
        verify(dot.visible);
        compare(findChild(bar, "recap-button").tip, I18n.t("recap.button.unseen")
                + (AppController.shortcutFor("recap.open").length > 0 ? "  " + AppController.shortcutFor("recap.open") : ""));
        bar.recapUnseen = false;
        verify(!dot.visible);
    }

    function test_click_and_keyboard_ask_for_the_recap() {
        const bar = make(true);
        const btn = findChild(bar, "recap-button");
        let asked = 0;
        bar.recapRequested.connect(() => asked++);
        mouseClick(btn);
        compare(asked, 1);
        btn.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(asked, 2);
        verify(btn.activeFocusOnTab, "the button is not on the Tab path");
    }
}
