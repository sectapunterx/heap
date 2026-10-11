// The search box reaches the views once typing pauses (audit 2026-09-30,
// TASKS-23). At 3k tasks a keystroke that swaps most of the board's rows
// rebinds every visible card, and a quickly typed "priority:p0" paid that for
// every intermediate state — "priority:p" among them, which matches nothing
// and emptied the board for a frame. The field updates instantly; the views
// see the text ~120 ms after the last key.
//
// The real window, so this pins the wiring in Main.qml, not a look-alike.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "SearchLatency"
    when: windowShown

    property var win: null

    function initTestCase() {
        // The board before the window: switching to it afterwards hands the
        // keyboard to the view a tick later (Main.qml _focusSwitchedView), and
        // on a fresh profile, where the window opens on another view, that
        // took the search field's focus from the first test.
        AppController.currentView = "board";
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        verify(comp.status === Component.Ready, comp.errorString());
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tryVerify(() => tc.win.activeViewItem() !== null, 3000);
    }

    // Each test starts from an empty field. A fresh profile opens with a
    // query in it, which the first test's keys were added to.
    function init() {
        tc.win.searchText = "";
    }

    function cleanupTestCase() {
        if (tc.win) {
            tc.win.searchText = "";
            tc.win.destroy();
            tc.win = null;
        }
    }

    function find(o, pred) {
        if (!o) return null;
        if (pred(o)) return o;
        const kids = o.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = find(kids[i], pred);
            if (r) return r;
        }
        return null;
    }

    function topBar() {
        const t = find(tc.win.contentItem, o => typeof o.focusSearch === "function" && o.searchIsQuery !== undefined);
        verify(t !== null, "no top bar");
        return t;
    }

    // Real keys, not assignments: assigning the field's text from script would
    // drop the binding that keeps it in step with the window.
    function typeInField(bar, text) {
        tc.win.requestActivate();
        bar.focusSearch();  // selects what is there, so typing replaces it
        tryVerify(() => tc.win.activeFocusItem && typeof tc.win.activeFocusItem.selectAll === "function",
                  2000, "the search field never took focus");
        for (let i = 0; i < text.length; i++) keyClick(text[i]);
    }

    function test_typing_reaches_the_views_once_it_pauses() {
        const bar = topBar();
        const board = tc.win.activeViewItem();
        tc.win.searchText = "";

        // One key: the field has it at once, the views do not yet.
        typeInField(bar, "p");
        compare(bar.searchText, "p", "the field lags behind the key");
        compare(tc.win.searchText, "", "the views re-filtered on the keystroke itself");
        tryCompare(tc.win, "searchText", "p", 1000, "the text never reached the views");
        compare(board.searchText, "p");

        // A burst lands as its final text.
        const text = "priority:p0";
        typeInField(bar, text);
        compare(bar.searchText, text);
        tryCompare(tc.win, "searchText", text, 1000, "the query never reached the views");
        compare(board.searchText, text);
    }

    // Clearing from outside the field (profile switch, Esc) is not delayed
    // and is not undone by keys still waiting to be applied.
    function test_programmatic_clear_wins_over_pending_keys() {
        const bar = topBar();
        typeInField(bar, "pbc");
        tryCompare(tc.win, "searchText", "pbc", 1000);
        typeInField(bar, "zebra");
        tc.win.searchText = "";
        compare(bar.searchText, "", "the field did not follow the clear");
        wait(300);
        compare(tc.win.searchText, "", "a pending keystroke brought the cleared text back");
    }
}
