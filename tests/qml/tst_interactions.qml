// Click-driven interaction tests for real UI components (HEAP-49).
//
// Uses the component harness (heap_core) to instantiate FilterBar / SideRail
// against a live AppController and drive them with actual mouse events, so the
// full path button → MouseArea → signal / AppController state is exercised —
// not just the signal contract.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Interactions"
    when: windowShown
    visible: true
    width: 500
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // FilterBar: clicking a priority pill emits togglePriority(id).
    function test_filterbar_click_priority() {
        const fb = make('import TodoCpp; FilterBar { anchors.fill: parent }');
        let got = "";
        fb.togglePriority.connect(function(p) { got = p; });
        const pill = findChild(fb, "pri-P2");
        verify(pill !== null, "pri-P2 pill not found");
        mouseClick(pill);
        compare(got, "P2");
    }

    // FilterBar: clicking the Archived chip emits toggleArchived.
    function test_filterbar_click_archived() {
        const fb = make('import TodoCpp; FilterBar { anchors.fill: parent }');
        let n = 0;
        fb.toggleArchived.connect(function() { n++; });
        const chip = findChild(fb, "archived-toggle");
        verify(chip !== null, "archived-toggle not found");
        mouseClick(chip);
        compare(n, 1);
    }

    // SideRail: clicking the Docs button switches the active view.
    function test_siderail_click_docs() {
        AppController.currentView = "board";
        const rail = make('import TodoCpp; SideRail { width: 56; height: 480 }');
        const btn = findChild(rail, "rail-docs");
        verify(btn !== null, "rail-docs not found");
        mouseClick(btn);
        compare(AppController.currentView, "docs");
    }

    // SideRail: clicking Blocked jumps to the board + focuses the blocked column.
    function test_siderail_click_blocked() {
        AppController.currentView = "notes";
        const rail = make('import TodoCpp; SideRail { width: 56; height: 480 }');
        const btn = findChild(rail, "rail-blocked");
        verify(btn !== null, "rail-blocked not found");
        mouseClick(btn);
        compare(AppController.currentView, "board");
        compare(AppController.focusedStatus, "blocked");
    }

    // SideRail: clicking Code Review focuses the review column.
    function test_siderail_click_review() {
        AppController.currentView = "week";
        const rail = make('import TodoCpp; SideRail { width: 56; height: 480 }');
        const btn = findChild(rail, "rail-review");
        verify(btn !== null, "rail-review not found");
        mouseClick(btn);
        compare(AppController.currentView, "board");
        compare(AppController.focusedStatus, "review");
    }
}
