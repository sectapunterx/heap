// Closing a task on the board (APP-176): one card moved into Done folds into
// a bar and lays itself on the stack over the Done column. A bulk move and
// "Reduce motion" just move. The board's public functions are driven
// directly, as in tst_BoardKeys.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DoneStack"
    when: windowShown
    visible: true
    width: 1200
    height: 800

    Item { id: host; anchors.fill: parent }

    property var seeded: []
    readonly property string probe: "stackprobe"
    property string savedSettings: ""

    function initTestCase() {
        tc.savedSettings = AppController.appSettingsJson;
    }

    function cleanup() {
        AppController.appSettingsJson = tc.savedSettings;
        AppController.clearSelection();
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        AppController.clearPendingUndo();
        tc.seeded = [];
    }

    // The column just left of Done, where a card is one step from closing.
    function beforeDone() {
        const st = AppController.statuses;
        for (let i = 1; i < st.length; i++) if (st[i].id === "done") return st[i - 1].id;
        return "";
    }

    function seed(n, status) {
        const out = [];
        for (let i = 0; i < n; i++) {
            const d = AppController.newTaskDraft(status);
            d._isNew = true;
            // Unique per run: the test profile is never wiped.
            d.id = "STK-" + Date.now() + "-" + i;
            d.title = tc.probe + " " + i;
            AppController.saveTask(d);
            tc.seeded.push(d.id);
            out.push(d.id);
        }
        return out;
    }

    // Wide enough that every column, Done included, is on screen.
    function makeBoard() {
        const b = createTemporaryQmlObject(
            'import TodoCpp; KanbanBoard { width: 2400; height: 800 }', host);
        verify(b !== null);
        if (b.collapsed["done"]) b.toggleCollapsed("done");
        b.searchText = tc.probe;
        wait(0);
        return b;
    }

    function motionOn(on) {
        AppController.appSettingsJson = JSON.stringify({ appearance: { reducedMotion: !on } });
        compare(Theme.motion, on ? 1 : 0);
    }

    function test_closing_one_card_lays_it_on_the_stack() {
        const from = beforeDone();
        if (!from) skip("no column before Done in this profile");
        motionOn(true);
        const ids = seed(1, from);
        const b = makeBoard();
        b.cursorTaskId = ids[0];
        b.cursorVisible = true;
        b.moveCursorCard(1, 0);
        compare(AppController.taskById(ids[0]).status, "done");
        verify(b.stackRunning, "closing one card did not play the stack");
        const flyer = findChild(b, "stack-flyer");
        verify(flyer.visible);
        tryVerify(function () { return !b.stackRunning; }, 3000, "the stack never landed");
        compare(flyer.visible, false);
        // Every column has the slot; only Done fills it.
        let shown = 0;
        (function walk(it) {
            if (!it) return;
            if (it.objectName === "done-stack" && it.visible) shown++;
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) walk(kids[i]);
        })(b);
        compare(shown, 1, "no stack over Done");
    }

    function test_reduced_motion_just_moves() {
        const from = beforeDone();
        if (!from) skip("no column before Done in this profile");
        motionOn(false);
        const ids = seed(1, from);
        const b = makeBoard();
        b.cursorTaskId = ids[0];
        b.cursorVisible = true;
        b.moveCursorCard(1, 0);
        compare(AppController.taskById(ids[0]).status, "done");
        compare(b.stackRunning, false, "the stack played with reduced motion");
    }

    function test_a_bulk_move_just_moves() {
        const from = beforeDone();
        if (!from) skip("no column before Done in this profile");
        motionOn(true);
        const ids = seed(2, from);
        const b = makeBoard();
        AppController.setSelectedTaskIds(ids);
        b.cursorTaskId = ids[0];
        b.cursorVisible = true;
        b.moveSelectionOrCard(1);
        compare(AppController.taskById(ids[0]).status, "done");
        compare(AppController.taskById(ids[1]).status, "done");
        compare(b.stackRunning, false, "the stack played for a bulk move");
        // And the rule the board asks, for any count but one.
        compare(b.stackOnClose(ids[0], from, "done", 2), false);
    }

    function test_a_move_elsewhere_does_not_stack() {
        const st = AppController.statuses;
        if (st.length < 2 || st[0].id === "done" || st[1].id === "done") skip("profile shape");
        motionOn(true);
        const ids = seed(1, st[0].id);
        const b = makeBoard();
        b.cursorTaskId = ids[0];
        b.cursorVisible = true;
        b.moveCursorCard(1, 0);
        compare(AppController.taskById(ids[0]).status, st[1].id);
        compare(b.stackRunning, false);
    }
}
