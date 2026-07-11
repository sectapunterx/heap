// MonthView: month / custom-range calendar (companion to WeekView).
//
// Covers: load-smoke against the live AppController, the taskClicked /
// eventClicked signal contracts, the pure helpers (isSameDay, priColor,
// passesFilter), grid geometry + step() in both "month" and "weeks" modes,
// and buildCells() picking up real task deadlines and events from the models.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "MonthView"
    when: windowShown
    visible: true
    width: 600
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // Smoke: the component instantiates against the live singleton and the
    // default month grid is fully built (6 weeks x 7 days).
    function test_monthview_load() {
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        compare(mv.mode, "month");
        compare(mv.rows, 6);
        compare(mv.cells.length, 42);
    }

    // Signal contract: taskClicked carries the task id.
    function test_taskclicked_signal_contract() {
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        let got = "";
        mv.taskClicked.connect(function(id) { got = id; });
        mv.taskClicked("HEAP-mv-task");
        compare(got, "HEAP-mv-task");
    }

    // Signal contract: eventClicked carries the event id.
    function test_eventclicked_signal_contract() {
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        let got = "";
        mv.eventClicked.connect(function(id) { got = id; });
        mv.eventClicked("ev-mv-probe");
        compare(got, "ev-mv-probe");
    }

    // isSameDay compares calendar days, ignoring the clock, and rejects junk.
    function test_helpers_is_same_day() {
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        const a = new Date(2031, 4, 20, 9, 15);
        const b = new Date(2031, 4, 20, 23, 59);
        const c = new Date(2031, 4, 21, 0, 0);
        verify(mv.isSameDay(a, b), "same calendar day must match regardless of time");
        verify(!mv.isSameDay(a, c), "different days must not match");
        verify(!mv.isSameDay(null, b), "null is never the same day");
        verify(!mv.isSameDay(a, "not-a-date"), "non-dates are rejected");
    }

    // priColor maps priority ids onto the Theme palette (P3 is the fallback).
    function test_helpers_pri_color() {
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        compare(mv.priColor("P0"), Theme.p0);
        compare(mv.priColor("P1"), Theme.p1);
        compare(mv.priColor("P2"), Theme.p2);
        compare(mv.priColor("P3"), Theme.p3);
        compare(mv.priColor("unknown"), Theme.p3);
    }

    // passesFilter: done tasks are always hidden; searchText matches
    // case-insensitively across title/id/desc; the priority filter only kicks
    // in once at least one priority is enabled. Instance-local state only.
    function test_passes_filter_search_and_priority() {
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        const t = { id: "t-1", title: "Alpha task", desc: "", priority: "P2", status: "todo" };

        verify(mv.passesFilter(t), "plain todo task must pass the default filter");
        verify(!mv.passesFilter({ id: "t-2", title: "x", desc: "", priority: "P1", status: "done" }),
               "done tasks never pass");

        mv.searchText = "ALPHA";
        verify(mv.passesFilter(t), "search must match the title case-insensitively");
        mv.searchText = "zzz-no-match";
        verify(!mv.passesFilter(t), "non-matching search must filter the task out");
        mv.searchText = "";

        mv.prioritiesFilter = { "P1": true };
        verify(!mv.passesFilter(t), "P2 task must fail with only P1 enabled");
        mv.prioritiesFilter = { "P2": true };
        verify(mv.passesFilter(t), "P2 task must pass with P2 enabled");
    }

    // Month mode: 6x7 grid, title is the anchor month, and step() moves the
    // selected date one month (clamped to day 28) in either direction.
    function test_month_mode_grid_and_step() {
        const prev = AppController.selectedDate;
        const day = new Date();
        day.setDate(day.getDate() + 452);
        day.setHours(0, 0, 0, 0);
        AppController.selectedDate = day;

        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        compare(mv.rows, 6);
        compare(mv.cells.length, 42);
        compare(mv.rangeTitle(), Qt.formatDate(day, "MMMM yyyy"));

        mv.step(1);
        const fwd = new Date(day.getFullYear(), day.getMonth() + 1, Math.min(day.getDate(), 28));
        verify(mv.isSameDay(AppController.selectedDate, fwd),
               "step(1) must advance the selected date one month (day clamped to 28)");

        mv.step(-1);
        const back = new Date(fwd.getFullYear(), fwd.getMonth() - 1, Math.min(fwd.getDate(), 28));
        verify(mv.isSameDay(AppController.selectedDate, back),
               "step(-1) must go back one month");

        AppController.selectedDate = prev;
    }

    // Weeks mode: N x 7 grid anchored at the week of selectedDate, and step()
    // jumps by the whole visible span (rows * 7 days).
    function test_weeks_mode_grid_and_step() {
        const prev = AppController.selectedDate;
        const day = new Date();
        day.setDate(day.getDate() + 455);
        day.setHours(0, 0, 0, 0);
        AppController.selectedDate = day;

        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        mv.mode = "weeks";
        mv.weeksCount = 2;
        compare(mv.rows, 2);
        compare(mv.cells.length, 14);
        verify(mv.isSameDay(mv.cells[0].date, mv.startOfWeek(day)),
               "weeks grid must start at the week containing the anchor");

        mv.step(1);
        const fwd = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 14);
        verify(mv.isSameDay(AppController.selectedDate, fwd),
               "step(1) in weeks mode must jump rows*7 days forward");

        AppController.selectedDate = prev;
    }

    // rows clamps weeksCount into 1..8 without touching the property itself.
    function test_weeks_count_clamped() {
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        mv.mode = "weeks";
        mv.weeksCount = 0;
        compare(mv.rows, 1);
        compare(mv.cells.length, 7);
        mv.weeksCount = 99;
        compare(mv.rows, 8);
        compare(mv.cells.length, 56);
        mv.weeksCount = 3;
        compare(mv.rows, 3);
        compare(mv.cells.length, 21);
    }

    // buildCells places a real task (via DeadlineRole, the QDate of dueAt) into
    // the cell of its deadline day, and the search filter removes it again.
    function test_cells_include_task_deadline() {
        const prev = AppController.selectedDate;
        const day = new Date();
        day.setDate(day.getDate() + 453);
        day.setHours(12, 0, 0, 0);

        const draft = AppController.newTaskDraft("todo");
        draft.title = "monthview cell probe";
        draft.scheduledAt = day;
        draft.dueAt = day;
        draft.hasTime = false;
        AppController.saveTask(draft);

        AppController.selectedDate = day;
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');

        let cell = null;
        for (let k = 0; k < mv.cells.length; k++)
            if (mv.isSameDay(mv.cells[k].date, day)) { cell = mv.cells[k]; break; }
        verify(cell !== null, "the grid must contain a cell for the deadline day");

        let found = false;
        for (let i = 0; i < cell.tasks.length; i++)
            if (cell.tasks[i].id === draft.id) found = true;
        verify(found, "the task must land in its deadline day's cell");

        // Non-matching search filters it back out (direct call: no binding dep).
        mv.searchText = "zzz-no-such-task";
        const cells2 = mv.buildCells();
        let stillThere = false;
        for (let k = 0; k < cells2.length; k++) {
            if (!mv.isSameDay(cells2[k].date, day)) continue;
            for (let i = 0; i < cells2[k].tasks.length; i++)
                if (cells2[k].tasks[i].id === draft.id) stillThere = true;
        }
        verify(!stillThere, "a non-matching search must remove the task from the grid");

        AppController.deleteTask(draft.id);
        AppController.selectedDate = prev;
    }

    // buildCells places a real calendar event (DateRole) into its day's cell.
    // The probe day is emptied first: the test-mode profile persists between
    // runs, so leftovers from earlier runs would otherwise pile up.
    function test_cells_include_event() {
        const prev = AppController.selectedDate;
        const day = new Date();
        day.setDate(day.getDate() + 454);
        day.setHours(0, 0, 0, 0);

        const evs = AppController.events;
        for (let i = evs.rowCount() - 1; i >= 0; i--) {
            const idx = evs.index(i, 0);
            const d = evs.data(idx, Qt.UserRole + 7);   // date role
            if (d && d.getFullYear
                && d.getFullYear() === day.getFullYear()
                && d.getMonth() === day.getMonth()
                && d.getDate() === day.getDate())
                AppController.deleteEvent(String(evs.data(idx, Qt.UserRole + 1)));
        }

        const ev = AppController.newEventDraft(10, day);
        ev.title = "monthview event probe";
        ev.date = day;
        AppController.saveEvent(ev);

        AppController.selectedDate = day;
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');

        let cell = null;
        for (let k = 0; k < mv.cells.length; k++)
            if (mv.isSameDay(mv.cells[k].date, day)) { cell = mv.cells[k]; break; }
        verify(cell !== null, "the grid must contain a cell for the event day");

        let found = false;
        for (let i = 0; i < cell.events.length; i++)
            if (cell.events[i].id === ev.id) found = true;
        verify(found, "the event must land in its day's cell");

        AppController.deleteEvent(ev.id);
        AppController.selectedDate = prev;
    }
}
