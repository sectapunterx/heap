// The labelled, collapsible side rail.
//
// Expanded, every button carries its name and the groups get titles; collapsed
// it is the old 56px icon rail with tooltips. The state lives in Main — the
// rail only asks for a toggle — so the rail itself is tested for how it draws
// each state and that its toggle button asks.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "SideRail"
    when: windowShown
    visible: true
    width: 400
    height: 720

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function labelOf(rail, name) {
        const btn = findChild(rail, name);
        verify(btn !== null, name + " not found");
        const lbl = findChild(btn, "rail-label");
        verify(lbl !== null, "no label in " + name);
        return lbl;
    }

    function test_expanded_shows_labels() {
        const rail = make('import TodoCpp; SideRail { height: 700; expanded: true }');
        tryCompare(rail, "width", rail.expandedWidth, 1000);
        const lbl = labelOf(rail, "rail-board");
        verify(lbl.visible);
        compare(lbl.text, I18n.t("siderail.board"));
        tryCompare(lbl, "opacity", 1, 1000);
    }

    function test_collapsed_is_the_icon_rail() {
        const rail = make('import TodoCpp; SideRail { height: 700; expanded: false }');
        tryCompare(rail, "width", rail.collapsedWidth, 1000);
        verify(!labelOf(rail, "rail-board").visible);
        verify(!labelOf(rail, "rail-notes").visible);
    }

    function test_toggle_button_asks_main() {
        const rail = make('import TodoCpp; SideRail { height: 700; expanded: true }');
        let n = 0;
        rail.toggleRequested.connect(function () { n++; });
        const btn = findChild(rail, "rail-toggle");
        verify(btn !== null);
        mouseClick(btn);
        compare(n, 1);
        // The rail does not flip itself: Main owns and persists the state.
        verify(rail.expanded);
    }

    // Buttons stay clickable in both states — the icon cell never moves.
    function test_buttons_work_collapsed() {
        AppController.currentView = "board";
        const rail = make('import TodoCpp; SideRail { height: 700; expanded: false }');
        tryCompare(rail, "width", rail.collapsedWidth, 1000);
        const btn = findChild(rail, "rail-notes");
        mouseClick(btn, 18, btn.height / 2);
        compare(AppController.currentView, "notes");
        AppController.currentView = "board";
    }

    // Design audit DES-11: Blocked and Review jump to their column on the
    // board; the board stays the one place lit, not the board and "Blocked".
    function test_a_column_jump_does_not_light_a_second_place() {
        const rail = make('import TodoCpp; SideRail { height: 700 }');
        AppController.focusStatusColumn("blocked");
        compare(AppController.currentView, "board");
        verify(findChild(rail, "rail-board").active);
        verify(!findChild(rail, "rail-blocked").active);
        verify(!findChild(rail, "rail-review").active);
    }

    function test_shortcut_is_in_the_catalog() {
        verify(AppController.shortcutFor("rail.toggle").length > 0);
    }
}
