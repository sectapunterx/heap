// Snapshot views rebuild once per burst of model changes (APP-203): a sync
// that changed forty cards rebuilt the week forty times in a row, freezing
// whatever was moving on screen. ChangeTick lets the first change through at
// once and folds the rest of the burst into one more rebuild.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ChangeTick"
    when: windowShown

    Item { id: host }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function test_a_single_change_shows_at_once() {
        const t = make('import TodoCpp; ChangeTick {}');
        t.bump();
        compare(t.rev, 1, "a single edit waited for the next pass");
        wait(0);
        compare(t.rev, 1, "a lone change rebuilt twice");
    }

    function test_a_burst_rebuilds_twice_not_per_change() {
        const t = make('import TodoCpp; ChangeTick {}');
        for (let i = 0; i < 40; i++) t.bump();
        compare(t.rev, 1);
        tryCompare(t, "rev", 2);
        wait(50);
        compare(t.rev, 2, "the burst kept rebuilding after it ended");
    }

    function test_the_next_turn_starts_fresh() {
        const t = make('import TodoCpp; ChangeTick {}');
        t.bump();
        wait(50);
        t.bump();
        compare(t.rev, 2, "a change after the burst had settled was held back");
    }

    // A view closed in the middle of a burst leaves nothing behind to run.
    function test_a_view_destroyed_mid_burst_is_quiet() {
        const t = make('import TodoCpp; ChangeTick {}');
        t.bump();
        t.bump();
        t.destroy();
        wait(50);
    }

    // The month grid keeps its cells across a task change and rebinds them.
    // A new cells array used to re-create all 42 cells and their chips.
    function test_month_cells_survive_a_task_change() {
        const day = new Date(2031, 6, 16);
        const was = AppController.selectedDate;
        AppController.selectedDate = day;
        const mv = make('import TodoCpp; MonthView { width: 700; height: 600 }');
        wait(0);
        const find = function () {
            const out = [];
            (function walk(it) {
                if (!it) return;
                if (it.cell !== undefined && it.cell.date !== undefined && mv.isSameDay(it.cell.date, day)) out.push(it);
                const kids = it.children || [];
                for (let i = 0; i < kids.length; i++) walk(kids[i]);
            })(mv);
            return out;
        };
        const before = find();
        compare(before.length, 1);
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.id = "TICK-" + Date.now();
        d.title = "month tick probe";
        d.dueAt = day;
        d.scheduledAt = day;
        d.hasTime = false;
        AppController.saveTask(d);
        wait(0);
        const after = find();
        compare(after.length, 1);
        verify(after[0] === before[0], "the cell was re-created for one task change");
        verify(after[0].cell.tasks.some(t => t.id === d.id), "the cell did not pick up the new task");
        AppController.deleteTask(d.id);
        AppController.clearPendingUndo();
        AppController.selectedDate = was;
    }
}
