// Closing a task on the board (APP-176): one card moved into Done folds into
// a bar and flies into the Done column's counter, which ticks up as it lands
// (APP-205: there is no stack of bars over Done any more). A bulk move and
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

    // Every item under `it` named `name`.
    function findAll(it, name) {
        const out = [];
        (function walk(x) {
            if (!x) return;
            if (x.objectName === name) out.push(x);
            const kids = x.children || [];
            for (let i = 0; i < kids.length; i++) walk(kids[i]);
        })(it);
        return out;
    }

    // The Done column's count pill.
    function doneCount(b) {
        const st = AppController.statuses;
        let idx = -1;
        for (let i = 0; i < st.length; i++) if (st[i].id === "done") idx = i;
        const pills = findAll(b, "column-count");
        compare(pills.length, st.length);
        // Pills come in column order, left to right.
        pills.sort((a, c) => a.mapToItem(null, 0, 0).x - c.mapToItem(null, 0, 0).x);
        return pills[idx];
    }
    function countText(pill) {
        for (let i = 0; i < pill.children.length; i++)
            if (pill.children[i].text !== undefined) return String(pill.children[i].text);
        return "";
    }

    function test_closing_one_card_flies_into_the_done_counter() {
        const from = beforeDone();
        if (!from) skip("no column before Done in this profile");
        motionOn(true);
        const ids = seed(1, from);
        const b = makeBoard();
        const pill = doneCount(b);
        compare(countText(pill), "0");
        b.cursorTaskId = ids[0];
        b.cursorVisible = true;
        b.moveCursorCard(1, 0);
        compare(AppController.taskById(ids[0]).status, "done");
        verify(b.stackRunning, "closing one card did not play the done moment");
        const flyer = findChild(b, "stack-flyer");
        verify(flyer.visible);
        // The counter waits for the card...
        compare(countText(pill), "0", "the count ticked before the card landed");
        // ...which flies to it.
        const target = pill.mapToItem(b, 0, 0);
        fuzzyCompare(flyer.toX, target.x, 0.5);
        fuzzyCompare(flyer.toW, pill.width, 0.5);
        tryVerify(function () { return !b.stackRunning; }, 3000, "the card never landed");
        compare(flyer.visible, false);
        compare(countText(pill), "1", "the count did not tick on landing");
    }

    // APP-205: no bars over Done, whatever it holds.
    function test_done_has_no_stack_bars() {
        const from = beforeDone();
        if (!from) skip("no column before Done in this profile");
        const ids = seed(7, "done");
        const b = makeBoard();
        compare(findAll(b, "done-stack").length, 0);
        compare(countText(doneCount(b)), "7");
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
        compare(b.stackRunning, false, "the done moment played with reduced motion");
        compare(countText(doneCount(b)), "1", "the count waited with reduced motion");
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
