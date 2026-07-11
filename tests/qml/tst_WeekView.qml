// WeekView: regression for the priority-sort falsy-zero bug. Within a day's
// task chips P0 (top tier) must sort before P1; `priRank[p] || 9` demoted P0's
// rank 0 to the unknown-priority fallback, sorting the most critical task last
// (and, on days with >4 tasks, out of the visible slice(0,4) entirely).
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "WeekView"
    when: windowShown
    visible: true
    width: 700
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function test_smoke_load() {
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        verify(wv !== null);
    }

    // Two tasks share one deadline day; the P0 must precede the P1 in that day's
    // sorted task list. Robust to leftover tasks (persistent qttest profile):
    // compares the two seeded ids by position, not absolute index.
    function test_p0_task_sorts_before_p1_in_day() {
        const prev = AppController.selectedDate;
        const day = new Date();
        day.setDate(day.getDate() + 592);
        day.setHours(0, 0, 0, 0);

        const p1 = AppController.newTaskDraft("todo");
        p1.title = "wv p1 probe"; p1.priority = "P1";
        p1.dueAt = day; p1.scheduledAt = day; p1.hasTime = false;
        AppController.saveTask(p1);

        const p0 = AppController.newTaskDraft("todo");
        p0.title = "wv p0 probe"; p0.priority = "P0";
        p0.dueAt = day; p0.scheduledAt = day; p0.hasTime = false;
        AppController.saveTask(p0);

        AppController.selectedDate = day;
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');

        // Pure builder called directly — no binding-timing dependency.
        const days = wv.buildDays();
        let dayTasks = null;
        for (let k = 0; k < days.length; k++)
            if (wv.isSameDay(days[k].date, day)) { dayTasks = days[k].tasks; break; }
        verify(dayTasks !== null, "the visible week must contain the deadline day");

        let iP0 = -1, iP1 = -1;
        for (let i = 0; i < dayTasks.length; i++) {
            if (dayTasks[i].id === p0.id) iP0 = i;
            if (dayTasks[i].id === p1.id) iP1 = i;
        }
        verify(iP0 >= 0 && iP1 >= 0, "both seeded tasks must land in the day");
        verify(iP0 < iP1, "P0 must sort before P1 (highest priority first)");

        AppController.deleteTask(p0.id);
        AppController.deleteTask(p1.id);
        AppController.selectedDate = prev;
    }

    // Weekend shading tracks the real day-of-week, not the column position. The
    // old `index >= 5` tinted Friday and missed Sunday under weekStart="sun";
    // isWeekendDate keys off the date. Jan 2026: 1st=Thu, so 2nd=Fri, 3rd=Sat,
    // 4th=Sun.
    function test_weekend_tracks_real_day_not_column() {
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        verify(!wv.isWeekendDate(new Date(2026, 0, 2)), "Friday is not a weekend");
        verify(wv.isWeekendDate(new Date(2026, 0, 3)),  "Saturday is a weekend");
        verify(wv.isWeekendDate(new Date(2026, 0, 4)),  "Sunday is a weekend");
        verify(!wv.isWeekendDate(null), "null is not a weekend");
    }
}
