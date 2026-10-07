// What a sync shows (APP-180, APP-186): the dot on a card a sync brought in,
// gone once the card is opened or the keyboard cursor reaches it; the header
// dot that says a sync is out, only after 400 ms. The C++ side (which cards
// are new, the toast wording, the flag) is covered by test_sync_visibility.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "SyncVisibility"
    when: windowShown
    visible: true
    width: 1200
    height: 800

    Item { id: host; anchors.fill: parent }

    readonly property string probe: "newdotprobe"
    property var seeded: []

    function seed(n) {
        const st = AppController.statuses[0].id;
        tc.seeded = [];
        for (let i = 0; i < n; i++) {
            const d = AppController.newTaskDraft(st);
            d._isNew = true;
            d.id = "NEWDOT-" + i;
            d.title = tc.probe + " " + i;
            AppController.saveTask(d);
            tc.seeded.push(d.id);
        }
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) {
            AppController.markTaskSeen(tc.seeded[i]);
            AppController.deleteTask(tc.seeded[i]);
        }
        AppController.clearPendingUndo();
        tc.seeded = [];
    }

    function findByName(root, name) {
        if (!root) return null;
        if (root.objectName === name) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) {
            const hit = findByName(kids[i], name);
            if (hit) return hit;
        }
        if (root.contentItem && root.contentItem !== root) return findByName(root.contentItem, name);
        return null;
    }
    // The card of `id` on the board.
    function cardOf(board, id) {
        const stack = [board];
        while (stack.length) {
            const it = stack.pop();
            if (it.objectName === "tc-card" && it.taskId === id) return it;
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) stack.push(kids[i]);
            if (it.contentItem && it.contentItem !== it) stack.push(it.contentItem);
        }
        return null;
    }

    // ── The card's dot ──

    Component {
        id: cardComp
        TaskCard { width: 300 }
    }

    function test_dot_follows_the_unseen_mark() {
        const card = cardComp.createObject(host, { task: { id: "NEWDOT-X", title: "x", status: "todo", priority: "P2" } });
        const dot = findChild(card, "tc-new-dot");
        verify(dot !== null);
        verify(!dot.visible, "a dot on a card nobody marked");
        AppController.markTasksUnseen(["NEWDOT-X"]);
        verify(dot.visible, "a new card shows no dot");
        compare(dot.color, Theme.focusRing, "the dot is the cursor's colour");
        AppController.markTaskSeen("NEWDOT-X");
        verify(!dot.visible);
        card.destroy();
    }

    function test_cursor_reaching_the_card_clears_it() {
        seed(2);
        AppController.markTasksUnseen(tc.seeded);
        const b = createTemporaryQmlObject('import TodoCpp; KanbanBoard { anchors.fill: parent }', host);
        b.searchText = tc.probe;
        wait(0);
        const ids = b._visibleByColumn()[0].ids;
        verify(ids.length >= 2);
        const first = cardOf(b, ids[0]);
        verify(first !== null);
        verify(findChild(first, "tc-new-dot").visible);

        // A click puts the cursor there without showing it: that is not the
        // keyboard reaching the card.
        b.cursorTaskId = ids[0];
        verify(AppController.isTaskUnseen(ids[0]));

        b.moveCursor(0, 0);
        verify(!AppController.isTaskUnseen(ids[0]), "the cursor landed and the dot stayed");
        verify(!findChild(first, "tc-new-dot").visible);
        verify(AppController.isTaskUnseen(ids[1]), "a card the cursor never reached lost its dot");
        b.moveCursor(0, 1);
        verify(!AppController.isTaskUnseen(ids[1]));
    }

    function test_opening_the_card_clears_it() {
        seed(1);
        AppController.markTasksUnseen(tc.seeded);
        const te = createTemporaryQmlObject('import TodoCpp; TaskEditor { }', host);
        te.showFor(AppController.taskById(tc.seeded[0]));
        verify(!AppController.isTaskUnseen(tc.seeded[0]), "opened, still new");
        te.close();
    }

    // ── The header's sync dot ──

    function test_sync_dot_rule_takes_the_clock() {
        const bar = createTemporaryQmlObject('import TodoCpp; TopBar { width: 1100; syncing: false }', host);
        compare(bar.syncDotDelay, 400);
        verify(!bar.syncDotDue(true, 1000, 1399));
        verify(bar.syncDotDue(true, 1000, 1400));
        verify(!bar.syncDotDue(false, 1000, 5000), "a finished sync shows nothing");
        verify(!bar.syncDotDue(true, 0, 5000), "no start, no dot");
    }

    function test_sync_dot_waits_400ms_and_goes_with_the_sync() {
        const bar = createTemporaryQmlObject('import TodoCpp; TopBar { width: 1100; syncing: false }', host);
        const dot = findByName(bar, "topbar-sync-dot");
        verify(dot !== null);
        verify(!dot.visible);
        bar.syncing = true;
        wait(200);
        verify(!dot.visible, "a quick pull flashed the dot");
        tryVerify(function () { return dot.visible; }, 1000, "a slow sync never said so");
        bar.syncing = false;
        verify(!dot.visible, "the dot outlived the sync");
    }

    function test_quick_sync_never_shows_it() {
        const bar = createTemporaryQmlObject('import TodoCpp; TopBar { width: 1100; syncing: false }', host);
        const dot = findByName(bar, "topbar-sync-dot");
        bar.syncing = true;
        wait(100);
        bar.syncing = false;
        wait(500);
        verify(!dot.visible);
    }

    function test_sync_dot_click_asks_for_the_status() {
        const bar = createTemporaryQmlObject('import TodoCpp; TopBar { width: 1100; syncing: false }', host);
        const spy = createTemporaryQmlObject('import QtTest; SignalSpy { signalName: "syncStatusRequested" }', host);
        spy.target = bar;
        bar.syncing = true;
        const dot = findByName(bar, "topbar-sync-dot");
        tryVerify(function () { return dot.visible; }, 1000);
        mouseClick(dot);
        compare(spy.count, 1);
        bar.syncing = false;
    }
}
