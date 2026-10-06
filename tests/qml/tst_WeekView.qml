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

    // Delegate wiring: under a Sunday-first week the first header column IS
    // Sunday and must be shaded as weekend. The old positional `index >= 5`
    // returns false for column 0, so this fails if the delegate binding is
    // reverted from isWeekendDate(date) back to the index test.
    function test_weekend_delegate_binding_under_sunday_first() {
        const savedSettings = AppController.appSettingsJson;
        const savedDate = AppController.selectedDate;

        AppController.appSettingsJson = JSON.stringify({ calendar: { weekStart: "sun" } });
        compare(Theme.weekStart, "sun", "precondition: settings must drive weekStart");
        AppController.selectedDate = new Date(2026, 0, 7);  // week starts Sun Jan 4

        const wv2 = make('import TodoCpp; WeekView { anchors.fill: parent }');
        const col0 = findChild(wv2, "wvHeadCol");   // first Repeater delegate = index 0
        verify(col0 !== null, "header column delegate not found");
        compare(col0.modelData.date.getDay(), 0, "first column must be Sunday under weekStart=sun");
        verify(col0.isWeekend, "the Sunday column must be shaded as weekend (not index >= 5)");

        AppController.appSettingsJson = savedSettings;
        AppController.selectedDate = savedDate;
    }
    // ── parity with the day grid ──────────────────────────────────────
    // The week clipped to the working day exactly as the day grid used to, so
    // an 07:00 standup or a 21:00 call was laid out off-grid: reachable in
    // neither view.

    function test_the_week_grid_spans_the_whole_day() {
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        compare(wv.hoursStart, 0);
        compare(wv.hoursEnd, 24);
    }

    function test_working_hours_are_reported_separately() {
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        compare(wv.workStart, AppController.workdayStart);
        compare(wv.workEnd, AppController.workdayEnd);
    }

    function test_clamp_and_convert_cover_the_whole_day() {
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        compare(wv.clampHour(-5), 0);
        compare(wv.clampHour(30), 24);
        fuzzyCompare(wv.yToHour(0), 0, 0.001);
    }

    // A click on an empty slot asks the shell to open the editor rather than
    // saving an untitled event, so cancelling leaves nothing behind.
    function test_create_requested_carries_the_hour_and_day() {
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        let gotHour = -1;
        let gotDay = null;
        wv.createRequested.connect(function (hour, day) { gotHour = hour; gotDay = day; });

        const when = new Date();
        wv.createRequested(14.5, when);

        compare(gotHour, 14.5);
        verify(gotDay !== null);
    }

    // Every day column accepts a dropped card, which is what time-blocking a
    // week looks like.
    function test_every_day_column_accepts_a_drop() {
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        wait(0);
        for (let i = 0; i < wv.days.length; i++) {
            verify(findChild(wv, "week-drop-" + i) !== null,
                   "day column " + i + " has no drop target");
        }
    }

    // Overlapping events are laid out side by side rather than on top of each
    // other. The map is keyed by event id.
    function test_overlaps_are_computed_for_the_week() {
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        verify(wv.overlaps !== undefined, "the week computes an overlap map");
    }

    function _probeDay(offset) {
        const d = new Date();
        d.setDate(d.getDate() + offset);
        d.setHours(0, 0, 0, 0);
        return d;
    }
    // Events this file seeded and a run that died left behind (the QML test
    // profile is never wiped).
    function _purge(prefix) {
        const evs = AppController.events;
        for (let i = evs.rowCount() - 1; i >= 0; i--) {
            const idx = evs.index(i, 0);
            if (String(evs.data(idx, Qt.UserRole + 2)).indexOf(prefix) === 0)
                AppController.deleteEvent(String(evs.data(idx, Qt.UserRole + 1)));
        }
    }

    // TIME-18: a week of a few hundred occurrences. Cutting them into day
    // pieces asked Segments.js about every occurrence on every day — ~2 s for
    // 420 occurrences — and a week step evaluated it twice. The bound is
    // generous (the fix measures ~10 ms for this; the old code ~700 ms).
    // Also checks the pieces of an overnight event are the same as before.
    function test_week_build_is_fast_and_cuts_overnight_pieces() {
        const prefix = "wv perf probe";
        _purge(prefix);
        const prev = AppController.selectedDate;
        const base = _probeDay(1500);
        const ids = [];
        for (let i = 0; i < 30; i++) {
            const ev = AppController.newEventDraft(8 + (i % 10), base);
            ev.title = prefix + " " + i;
            ev.end = ev.start + 1;
            ev.date = base;
            ev.rrule = "FREQ=DAILY";
            AppController.saveEvent(ev);
            ids.push(ev.id);
        }
        // 22:00 to 02:00 the next day, mid-week.
        const night = AppController.newEventDraft(22, _probeDay(1510));
        night.title = prefix + " night";
        night.date = _probeDay(1510);
        night.endDate = _probeDay(1511);
        night.start = 22;
        night.end = 2;
        AppController.saveEvent(night);
        ids.push(night.id);

        AppController.selectedDate = _probeDay(1510);
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        verify(wv.flatEvents.length >= 30 * 5, "the series did not reach the week: " + wv.flatEvents.length);

        const t0 = Date.now();
        for (let k = 0; k < 5; k++) wv.buildEventDays();
        const perBuild = (Date.now() - t0) / 5;
        verify(perBuild < 250, "cutting a week of occurrences took " + perBuild + " ms");

        const pieces = [];
        const days = wv.eventDays.days;
        for (let k = 0; k < days.length; k++)
            for (let j = 0; j < days[k].events.length; j++)
                if (days[k].events[j].id === night.id) pieces.push({ day: days[k].date, e: days[k].events[j] });
        if (pieces.length === 2) {
            verify(wv.isSameDay(pieces[0].day, _probeDay(1510)));
            compare(pieces[0].e.start, 22); compare(pieces[0].e.end, 24);
            verify(pieces[0].e.segFirst); verify(!pieces[0].e.segLast);
            compare(pieces[1].e.start, 0); compare(pieces[1].e.end, 2);
            verify(!pieces[1].e.segFirst); verify(pieces[1].e.segLast);
        } else {
            // The night ends past the week's last column: one piece, its start.
            compare(pieces.length, 1, "overnight event pieces: " + pieces.length);
            compare(pieces[0].e.start, 22);
            verify(pieces[0].e.segFirst);
        }

        wv.destroy();
        wait(0);
        for (let i = 0; i < ids.length; i++) AppController.deleteEvent(ids[i]);
        AppController.clearPendingUndo();
        AppController.selectedDate = prev;
    }

}
