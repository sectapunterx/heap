// The day grid.
//
// It used to run from workdayStart to workdayEnd — 9 to 19 by default — so an
// 07:00 standup or a 21:00 call was laid out off-grid: counted in the header's
// "N events" and drawn nowhere the user could reach it. The grid covers the
// whole day now and working hours only tint the background.
//
// DayCalendar is the most interaction-dense file in the app and had no tests
// of its own.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DayCalendar"
    when: windowShown
    visible: true
    width: 900
    height: 700

    Item { id: host; anchors.fill: parent }

    property var seededEvents: []
    property string seededTask: ""

    // A day far enough out that nothing an earlier run left behind is on it.
    // The shared QML test profile is never wiped.
    function probeDay(offset) {
        const d = new Date();
        d.setDate(d.getDate() + offset);
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function clearDay(day) {
        const evs = AppController.events;
        for (let i = evs.rowCount() - 1; i >= 0; i--) {
            const idx = evs.index(i, 0);
            const d = evs.data(idx, Qt.UserRole + 7);   // DateRole
            if (d && d.getFullYear
                && d.getFullYear() === day.getFullYear()
                && d.getMonth() === day.getMonth()
                && d.getDate() === day.getDate())
                AppController.deleteEvent(String(evs.data(idx, Qt.UserRole + 1)));
        }
    }

    function addEvent(day, start, end, title) {
        const ev = AppController.newEventDraft(start, day);
        ev.title = title;
        ev.end = end;
        ev.date = day;
        AppController.saveEvent(ev);
        tc.seededEvents.push(ev.id);
        return ev.id;
    }

    function cleanup() {
        for (let i = 0; i < tc.seededEvents.length; i++) AppController.deleteEvent(tc.seededEvents[i]);
        tc.seededEvents = [];
        if (tc.seededTask.length > 0) {
            AppController.deleteTask(tc.seededTask);
            tc.seededTask = "";
        }
        AppController.clearPendingUndo();
    }

    function makeDay() {
        const dc = createTemporaryQmlObject(
            'import TodoCpp; DayCalendar { anchors.fill: parent }', host);
        verify(dc !== null);
        wait(0);   // the view scrolls itself to the relevant hour on a callLater
        return dc;
    }

    // The bug this file exists for: the grid has to cover midnight to midnight,
    // not the working day.
    function test_the_grid_spans_the_whole_day() {
        const dc = makeDay();
        compare(dc.hoursStart, 0);
        compare(dc.hoursEnd, 24);
    }

    // Working hours still exist — they just tint rather than clip.
    function test_working_hours_are_reported_separately() {
        const dc = makeDay();
        compare(dc.workStart, AppController.workdayStart);
        compare(dc.workEnd, AppController.workdayEnd);
        verify(dc.workStart >= dc.hoursStart);
        verify(dc.workEnd <= dc.hoursEnd);
    }

    // An early meeting used to be drawn above the top of the grid, where
    // nothing could reach it.
    function test_an_event_before_the_working_day_is_reachable() {
        const day = probeDay(430);
        clearDay(day);
        AppController.selectedDate = day;
        const id = addEvent(day, 6.5, 7.5, "early standup");

        const dc = makeDay();
        const block = findChild(dc, "event-" + id);
        verify(block !== null, "an 06:30 event must render");
        verify(block.y >= 0, "and not above the top of the grid");
    }

    function test_an_event_after_the_working_day_is_reachable() {
        const day = probeDay(431);
        clearDay(day);
        AppController.selectedDate = day;
        const id = addEvent(day, 21, 22, "late call");

        const dc = makeDay();
        const block = findChild(dc, "event-" + id);
        verify(block !== null, "a 21:00 event must render");
        verify(block.y + block.height <= dc.hoursEnd * Theme.hourH + 1,
               "and inside the grid rather than past the bottom of it");
    }

    // Position is proportional to the hour, measured from midnight.
    function test_an_event_sits_at_its_own_hour() {
        const day = probeDay(432);
        clearDay(day);
        AppController.selectedDate = day;
        const early = addEvent(day, 8, 9, "eight");
        const late = addEvent(day, 20, 21, "twenty");

        const dc = makeDay();
        const a = findChild(dc, "event-" + early);
        const b = findChild(dc, "event-" + late);
        verify(a !== null && b !== null);
        verify(b.y > a.y, "a later event sits further down");
        // Twelve hours apart, at the grid's own scale.
        fuzzyCompare(b.y - a.y, 12 * Theme.hourH, 2);
    }

    function test_clamp_hour_covers_the_whole_day() {
        const dc = makeDay();
        compare(dc.clampHour(-5), 0);
        compare(dc.clampHour(30), 24);
        compare(dc.clampHour(6), 6);
        compare(dc.clampHour(23), 23);
    }

    // y → hour is measured from midnight now, not from the start of the
    // working day; a drag at the top of the grid means 00:00.
    function test_y_to_hour_starts_at_midnight() {
        const dc = makeDay();
        fuzzyCompare(dc.yToHour(0), 0, 0.001);
        fuzzyCompare(dc.yToHour(Theme.hourH * 9), 9, 0.001);
    }

    function test_snap_follows_the_setting() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = JSON.stringify({ calendar: { snapMinutes: 30 } });
        const dc = makeDay();

        fuzzyCompare(dc.snapHour(9.2), 9.0, 0.001);
        fuzzyCompare(dc.snapHour(9.4), 9.5, 0.001);

        AppController.appSettingsJson = saved;
    }

    // A task scheduled outside the working day used to be invisible for the
    // same reason its events were.
    function test_a_task_scheduled_late_renders() {
        const day = probeDay(433);
        clearDay(day);
        AppController.selectedDate = day;

        const at = new Date(day);
        at.setHours(22, 0, 0, 0);
        const draft = AppController.newTaskDraft("todo");
        draft.title = "late work";
        draft.scheduledAt = at;
        draft.dueAt = at;
        draft.hasTime = true;
        AppController.saveTask(draft);
        tc.seededTask = draft.id;

        const dc = makeDay();
        const block = findChild(dc, "taskblock-" + draft.id);
        verify(block !== null, "a task scheduled at 22:00 must render a block");
    }
}
