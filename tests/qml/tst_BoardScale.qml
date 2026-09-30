// How many card delegates does the board actually build? Nothing measured
// this, and the board's own structure makes the answer surprising: the task
// model is the model of the Repeater inside EVERY status column, and a card
// that belongs elsewhere hides itself with `visible:`. So the count is
// columns × tasks, not tasks.
//
// This is a measurement, not a budget. It prints the numbers and asserts only
// the property that matters — that the board builds a number of delegates
// proportional to the tasks, not to tasks × columns.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "BoardScale"
    when: windowShown
    visible: true
    width: 1200
    height: 800

    Item { id: host; anchors.fill: parent }

    property var seededIds: []

    function seed(n) {
        const statuses = AppController.statuses;
        tc.seededIds = [];
        for (let i = 0; i < n; i++) {
            const d = AppController.newTaskDraft(statuses[i % statuses.length].id);
            d._isNew = true;
            d.id = "PERF-" + i;
            d.title = "task " + i;
            AppController.saveTask(d);
            tc.seededIds.push(d.id);
        }
    }

    function unseed() {
        for (let i = 0; i < tc.seededIds.length; i++) AppController.deleteTask(tc.seededIds[i]);
        AppController.clearPendingUndo();
        tc.seededIds = [];
    }

    function countCards(item, acc) {
        if (!item) return acc;
        // `shown` skips the cards a column keeps pooled for reuse: a pooled
        // card stays a child of the list until a row needs it, and hides
        // itself while it waits. Counting it would make a search that
        // narrowed every column look like it narrowed nothing.
        if (String(item.objectName) === "tc-card" && (!acc.shown || item.visible)) acc.n++;
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) countCards(kids[i], acc);
        return acc;
    }

    function cleanupTestCase() {
        unseed();
    }

    function test_the_board_builds_one_delegate_per_task_not_per_column() {
        const n = 300;
        seed(n);

        const board = createTemporaryQmlObject(
            'import TodoCpp; KanbanBoard { anchors.fill: parent }', host);
        verify(board !== null);
        wait(0);   // let the Repeaters populate

        const columns = AppController.statuses.length;
        const acc = countCards(board, { n: 0 });
        console.log("BoardScale: " + n + " tasks, " + columns + " columns -> "
                    + acc.n + " card delegates");

        // The bug, stated as a bound: one card per task, give or take the
        // couple a column may keep around, NOT one per task per column.
        verify(acc.n <= n * 2,
               "the board built " + acc.n + " delegates for " + n + " tasks across "
               + columns + " columns — it is instantiating every task in every column");
        // And the columns are virtualised: a tall column builds what fits on
        // screen, not every card it holds (audit A5).
        verify(acc.n < n / 2,
               "the board built " + acc.n + " delegates for " + n + " tasks — columns are not virtualised");
        unseed();
    }

    // Filtering moved from a per-card JS predicate into the per-column proxy,
    // so the behaviour the user sees has to be re-checked at the board level:
    // each column shows its own status, the counts add up, and a search
    // narrows every column at once.
    function test_each_column_shows_only_its_own_tasks_and_counts_them() {
        seed(40);
        const board = createTemporaryQmlObject(
            'import TodoCpp; KanbanBoard { anchors.fill: parent }', host);
        verify(board !== null);
        wait(0);

        // Every task lands in exactly one column, so the per-status tallies
        // must add back up to the model's row count.
        const total = AppController.tasks.rowCount();
        let summed = 0;
        const seen = {};
        for (let c = 0; c < AppController.statuses.length; c++) {
            const id = AppController.statuses[c].id;
            seen[id] = 0;
        }
        for (let i = 0; i < AppController.tasks.rowCount(); i++) {
            const idx = AppController.tasks.index(i, 0);
            const st = String(AppController.tasks.data(idx, Qt.UserRole + 5));
            if (seen[st] !== undefined) seen[st]++;
        }
        for (const k in seen) summed += seen[k];
        compare(summed, total, "every task belongs to exactly one column");

        // The lists lay their cards out on their next polish, not inside the
        // property write, so every count below waits for the board to settle
        // rather than sampling it after a single event-loop turn — which was
        // whatever the previous run had left in the pool.
        const shown = () => countCards(board, { n: 0, shown: true }).n;
        tryVerify(() => shown() > 0, 2000, "the board shows no cards");
        wait(50);
        const full = shown();

        board.searchText = "task 1";
        const matching = shownIdsAllowed(board);
        verify(matching.count > 0, "a search that matches something must leave something");
        tryVerify(() => shown() < full && shown() > 0, 2000,
                  "a search must narrow the board (" + shown() + " vs " + full + ")");
        // Every card still on the board is one the columns kept.
        const stray = [];
        forEachShownCard(board, c => { if (!matching.ids[c.taskId]) stray.push(c.taskId); });
        compare(stray.length, 0, "cards the search filtered out are still on the board: " + stray.join(", "));

        board.searchText = "";
        tryVerify(() => shown() >= full, 2000, "clearing the search did not bring the cards back");
    }

    // The ids every column's proxy admits, i.e. what the board may show.
    function shownIdsAllowed(board) {
        const out = { ids: {}, count: 0 };
        function rec(o) {
            if (!o) return;
            if (o.taskFilter !== undefined && o.statusId !== undefined) {
                const ids = o.taskFilter.ids();
                for (let i = 0; i < ids.length; i++) { out.ids[ids[i]] = true; out.count++; }
            }
            const kids = o.children || [];
            for (let i = 0; i < kids.length; i++) rec(kids[i]);
        }
        rec(board);
        return out;
    }

    function forEachShownCard(item, fn) {
        if (!item) return;
        if (String(item.objectName) === "tc-card" && item.visible) fn(item);
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) forEachShownCard(kids[i], fn);
    }
}
