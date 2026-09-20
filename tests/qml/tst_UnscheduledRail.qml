// What still needs a slot.
//
// Time-blocking worked in one direction only: the grids accepted a card
// dropped on an hour, and the only place to drag one from was the board. So
// planning a week meant switching views, remembering a title, switching back
// and finding the hour again.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "UnscheduledRail"
    when: windowShown
    visible: true
    width: 1200
    height: 700

    Item { id: host; anchors.fill: parent }

    // The shared QML test profile is never wiped, so every seeded task carries
    // this token and the rail is filtered to it.
    readonly property string probe: "railprobe"
    property var seeded: []

    function probeDay(offset) {
        const d = new Date();
        d.setDate(d.getDate() + offset);
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function week(from) {
        const days = [];
        for (let i = 0; i < 7; i++) {
            const d = new Date(from);
            d.setDate(d.getDate() + i);
            days.push(d);
        }
        return days;
    }

    function seedTask(id, day, opts) {
        const statuses = AppController.statuses;
        const d = AppController.newTaskDraft(statuses[0].id);
        d._isNew = true;
        d.id = id;
        d.title = tc.probe + " " + ((opts && opts.title) || id);
        d.priority = (opts && opts.priority) || "P2";
        if (day) {
            const at = new Date(day);
            if (opts && opts.hour !== undefined) at.setHours(opts.hour, 0, 0, 0);
            d.dueAt = at;
            d.hasTime = !!(opts && opts.hasTime);
        }
        if (opts && opts.status) d.status = opts.status;
        AppController.saveTask(d);
        tc.seeded.push(id);
        return id;
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
    }

    function makeRail(days) {
        const r = createTemporaryQmlObject(
            'import TodoCpp; UnscheduledRail { width: 240; height: 500 }', host);
        verify(r !== null);
        r.days = days;
        r.searchText = tc.probe;
        r.taskRev = r.taskRev + 1;   // force a rebuild after the filter is set
        return r;
    }

    function idsOf(rail) {
        const out = [];
        for (let i = 0; i < rail.items.length; i++) out.push(rail.items[i].id);
        return out;
    }

    // The point of the rail: a task due this week with no hour on it.
    function test_a_dated_task_with_no_time_is_listed() {
        const day = probeDay(860);
        seedTask("RAIL-A", day, {});

        const rail = makeRail(week(day));

        compare(idsOf(rail), ["RAIL-A"]);
    }

    // The rail is what is MISSING from the grid. A task already standing in it
    // must not also stand in the list of what is not.
    function test_a_task_with_a_time_is_not_listed() {
        const day = probeDay(865);
        seedTask("RAIL-TIMED", day, { hour: 10, hasTime: true });

        const rail = makeRail(week(day));

        compare(idsOf(rail).indexOf("RAIL-TIMED"), -1);
    }

    function test_a_task_outside_the_range_is_not_listed() {
        const day = probeDay(870);
        seedTask("RAIL-FAR", probeDay(900), {});

        const rail = makeRail(week(day));

        compare(idsOf(rail).indexOf("RAIL-FAR"), -1);
    }

    // A task with no deadline at all has no week to belong to; it would sit in
    // every rail forever.
    function test_an_undated_task_is_not_listed() {
        const day = probeDay(875);
        seedTask("RAIL-NODATE", null, {});

        const rail = makeRail(week(day));

        compare(idsOf(rail).indexOf("RAIL-NODATE"), -1);
    }

    function test_a_done_task_is_not_listed() {
        const day = probeDay(880);
        const statuses = AppController.statuses;
        seedTask("RAIL-DONE", day, { status: "done" });

        const rail = makeRail(week(day));

        compare(idsOf(rail).indexOf("RAIL-DONE"), -1);
    }

    // Soonest first: the rail is a queue, and what is due first needs a slot
    // first.
    function test_the_soonest_deadline_comes_first() {
        const day = probeDay(885);
        const later = new Date(day); later.setDate(later.getDate() + 3);
        seedTask("RAIL-LATER", later, {});
        seedTask("RAIL-SOONER", day, {});

        const rail = makeRail(week(day));

        compare(idsOf(rail), ["RAIL-SOONER", "RAIL-LATER"]);
    }

    // The falsy-zero trap: P0 maps to rank 0, and `rank || 9` would send every
    // P0 to the bottom. That exact bug demoted P0 across four views once.
    function test_priority_breaks_a_tie_without_demoting_p0() {
        const day = probeDay(890);
        seedTask("RAIL-P3", day, { priority: "P3" });
        seedTask("RAIL-P0", day, { priority: "P0" });

        const rail = makeRail(week(day));

        compare(idsOf(rail)[0], "RAIL-P0");
    }

    // Every grid reads `taskId` off whatever is dropped on it, so the rail's
    // chips have to expose the same property a board card does — otherwise a
    // drop silently does nothing.
    function test_a_chip_exposes_the_task_id_a_drop_reads() {
        const day = probeDay(895);
        seedTask("RAIL-DRAG", day, {});

        const rail = makeRail(week(day));
        const chip = findChild(rail, "unscheduled-RAIL-DRAG");

        verify(chip !== null, "the chip must render");
        compare(chip.taskId, "RAIL-DRAG");
    }

    // Scheduling a task is what empties the rail; if the list did not react,
    // the same task would sit there after being blocked out.
    function test_scheduling_a_task_takes_it_off_the_rail() {
        const day = probeDay(898);
        seedTask("RAIL-GOES", day, {});
        const rail = makeRail(week(day));
        compare(idsOf(rail), ["RAIL-GOES"]);

        AppController.scheduleTask("RAIL-GOES", 10, day);
        rail.taskRev = rail.taskRev + 1;

        compare(idsOf(rail).indexOf("RAIL-GOES"), -1);
    }

    function test_an_empty_range_lists_nothing() {
        const rail = makeRail([]);
        compare(rail.items.length, 0);
    }
}
