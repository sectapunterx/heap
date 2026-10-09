// The Calendar lens (APP-264, APP-247): Day / Week / Month as one zoom, each
// thing once, the "Without a date" tray onto the grid and onto a month day,
// and the day's load in the header matching dayLoads().
//
// Runs against the live AppController, whose test profile persists between
// runs: every task here has its own id, is deleted before it is made and
// again at the end, and the dates are far from today.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "CalendarLens"
    when: windowShown
    visible: true
    width: 1400
    height: 900

    Item { id: host; anchors.fill: parent }

    // A Wednesday far from today.
    readonly property var wed: new Date(2031, 2, 12)

    function sameDay(a, b) {
        return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function seed(id, fields) {
        AppController.deleteTask(id);
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.id = id;
        d.title = id + " probe";
        for (const k in fields) d[k] = fields[k];
        verify(AppController.saveTask(d), "seeding " + id);
        tc._made.push(id);
    }
    function task(id) { return AppController.taskById(id); }

    property var _savedDate: null
    property var _made: []
    function init() {
        tc._savedDate = AppController.selectedDate;
        tc._made = [];
        AppController.selectedDate = tc.wed;
    }
    function cleanup() {
        for (let i = 0; i < tc._made.length; i++) AppController.deleteTask(tc._made[i]);
        AppController.clearPendingUndo();
        AppController.selectedDate = tc._savedDate;
    }
    function makeLens(zoom) {
        const o = createTemporaryQmlObject('import TodoCpp; CalendarView { anchors.fill: parent; zoom: "' + zoom + '" }', host);
        verify(o !== null);
        tryVerify(() => o.calendarView !== null, 2000);
        return o;
    }

    function test_the_zoom_is_one_grid_at_one_or_seven_days() {
        const lens = makeLens("day");
        compare(lens.calendarView.days.length, 1, "the day zoom is the selected day alone");
        verify(sameDay(lens.calendarView.days[0].date, tc.wed));
        lens.zoom = "week";
        tryVerify(() => lens.calendarView.days.length >= 5, 2000, "the week zoom is the week");
        lens.zoom = "month";
        tryVerify(() => lens.calendarView && lens.calendarView.cells !== undefined, 2000, "the month zoom is the month grid");
    }

    function test_a_task_with_a_time_is_not_also_a_flag() {
        seed("CAL-DUP", { dueAt: new Date(2031, 2, 12), dueHasTime: false,
                          scheduledAt: new Date(2031, 2, 12, 14, 0), scheduledHasTime: true });
        const lens = makeLens("day");
        const d = lens.calendarView.days[0];
        verify(d.blocks.some(b => b.id === "CAL-DUP"), "its block is on the grid");
        verify(!d.tasks.some(t => t.id === "CAL-DUP"), "and not also in the deadline row");
    }

    function test_the_day_header_load_matches_dayLoads() {
        seed("CAL-LOAD", { scheduledAt: new Date(2031, 2, 12, 10, 0), scheduledHasTime: true, estimateMinutes: 90 });
        const lens = makeLens("day");
        const l = AppController.dayLoads(tc.wed, 1)[0];
        verify(l.tasks >= 90, "the planned block counts");
        const label = findChild(lens, "week-load-0");
        verify(label !== null);
        // The sheets draw no load on the columns (DG-041): it is the day
        // name's tooltip.
        compare(label.loadText, lens.calendarView.loadLong(l));
        verify(label.loadText.indexOf(I18n.fmtMinutes(l.free)) >= 0, "the free time is said");
        // A new block on the day refreshes the header.
        seed("CAL-LOAD2", { scheduledAt: new Date(2031, 2, 12, 14, 0), scheduledHasTime: true, estimateMinutes: 60 });
        const l2 = AppController.dayLoads(tc.wed, 1)[0];
        verify(l2.tasks > l.tasks);
        // The header row is rebuilt with the day: look the label up again.
        tryVerify(() => {
            const now = findChild(lens, "week-load-0");
            return !!now && now.loadText === lens.calendarView.loadLong(l2);
        }, 2000, "the load refreshes");
    }

    function test_a_tray_task_is_planned_at_the_clicked_hour() {
        seed("CAL-TRAY", { scheduledAt: null, dueAt: null });
        const lens = makeLens("day");
        const tray = findChild(lens, "undated-tray");
        tryVerify(() => tray.items.some(t => t.id === "CAL-TRAY"), 2000, "the undated task is in the tray");
        tray.armedId = "CAL-TRAY";
        const grid = lens.calendarView;
        compare(grid.armedTaskId, "CAL-TRAY");
        const area = findChild(grid, "week-create-0");
        verify(area !== null);
        mouseClick(area, area.width / 2, 15 * grid.hourH + 2);
        const t = task("CAL-TRAY");
        verify(t.scheduledHasTime, "it has a time now");
        compare(t.scheduledAt.getHours(), 15);
        verify(sameDay(t.scheduledAt, tc.wed));
        compare(tray.armedId, "", "the pick is used up");        tryVerify(() => !tray.items.some(x => x.id === "CAL-TRAY"), 2000, "and it leaves the tray");
    }

    function test_a_tray_task_lands_on_a_month_day() {
        seed("CAL-MON", { scheduledAt: null, dueAt: null });
        const lens = makeLens("month");
        const tray = findChild(lens, "undated-tray");
        tryVerify(() => tray.items.some(t => t.id === "CAL-MON"), 2000);
        tray.armedId = "CAL-MON";
        const mv = lens.calendarView;
        let idx = -1;
        for (let i = 0; i < mv.cells.length; i++) if (sameDay(mv.cells[i].date, new Date(2031, 2, 20))) idx = i;
        verify(idx >= 0);
        const cell = findChild(mv, "month-cell-" + idx);
        mouseClick(cell, cell.width / 2, cell.height - 4);
        const t = task("CAL-MON");
        verify(sameDay(t.scheduledAt, new Date(2031, 2, 20)), "planned for that day");
        verify(!t.scheduledHasTime, "as a date");
        verify(!t.dueAt || isNaN(t.dueAt.getTime()), "the deadline stays empty");
    }

    function test_the_nav_steps_by_the_zoom() {
        const nav = createTemporaryQmlObject('import TodoCpp; CalendarNav { zoom: "day" }', host);
        nav.step(1);
        verify(sameDay(AppController.selectedDate, new Date(2031, 2, 13)));
        nav.zoom = "week";
        nav.step(-1);
        verify(sameDay(AppController.selectedDate, new Date(2031, 2, 6)));
        AppController.selectedDate = new Date(2031, 0, 31);
        nav.zoom = "month";
        nav.step(1);
        verify(sameDay(AppController.selectedDate, new Date(2031, 1, 28)), "31 Jan → 28 Feb");
    }

    function test_more_than_three_in_a_month_day_says_more() {
        for (let i = 0; i < 5; i++)
            seed("CAL-M" + i, { scheduledAt: new Date(2031, 2, 18), scheduledHasTime: false });
        const lens = makeLens("month");
        const mv = lens.calendarView;
        let idx = -1;
        for (let i = 0; i < mv.cells.length; i++) if (sameDay(mv.cells[i].date, new Date(2031, 2, 18))) idx = i;
        const cell = findChild(mv, "month-cell-" + idx);
        const more = findChild(cell, "month-more");
        verify(more.visible, "+N more");
        compare(more._extra, mv.cells[idx].tasks.length + mv.cells[idx].events.length - 3);
    }

    // DG-045 (X-Menus-Column): a right click on an empty slot opens the
    // slot's menu at that hour; on a meeting, the meeting's menu.
    function test_slot_and_meeting_have_their_menus() {
        const lens = makeLens("day");
        const grid = lens.calendarView;
        const area = findChild(grid, "week-create-0");
        verify(area !== null);
        mouseClick(area, area.width / 2, 14 * grid.hourH + 2, Qt.RightButton);
        verify(grid.menuSlot !== null, "the slot menu took the click");
        compare(grid.menuSlot.hour, 14);
        verify(sameDay(grid.menuSlot.date, tc.wed));
        // Nothing was made by the right click.
        compare(AppController.eventOccurrences(tc.wed, tc.wed).length, grid.days[0].events.length);

        const ev = AppController.newEventDraft(10, tc.wed);
        ev.title = "menu probe";
        AppController.saveEvent(ev);
        try {
            let opens = [];
            tryVerify(() => (opens = grid.flatEvents.filter(e => e.id === ev.id)).length === 1, 2000, "the meeting is on the grid");
            grid.openEventMenu(opens[0]);
            compare(grid.menuEvent.id, ev.id);
            verify(!grid._menuSeries, "a single meeting is not a series");
            // Duration from the menu: the same as stretching its edge.
            grid.setEventLength(0.5);
            tryVerify(() => Math.abs(AppController.eventById(ev.id).end - 10.5) < 1e-6, 2000, "the meeting is half an hour");
            // Duplicate: one more meeting with the same title and time.
            grid.duplicateEvent();
            const same = AppController.eventOccurrences(tc.wed, tc.wed).filter(e => e.title === "menu probe");
            compare(same.length, 2);
            for (const e of same) if (e.id !== ev.id) AppController.deleteEvent(e.id);
        } finally {
            AppController.deleteEvent(ev.id);
            AppController.clearPendingUndo();
        }
    }

    // DG-051: the day zoom's header says the facts, the deadlines follow.
    function test_the_day_header_line_says_the_facts() {
        seed("CAL-FACT", { dueAt: new Date(2031, 2, 12), dueHasTime: false, scheduledAt: null });
        const lens = makeLens("day");
        const grid = lens.calendarView;
        tryVerify(() => grid.days[0].tasks.some(t => t.id === "CAL-FACT"), 2000);
        verify(grid.dayFacts(grid.days[0]).indexOf(I18n.t("cal.dueColon")) >= 0, "the deadline is announced");
        verify(findChild(grid, "week-due-CAL-FACT") !== null, "and follows as a link");
    }
}
