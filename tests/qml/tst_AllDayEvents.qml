// All-day and spanning events in the views.
//
// The day and week grids read `start` and `end` off the model, so an event
// that is not one block on one day had nowhere to go. An all-day event now
// goes to a strip under the header; a timed event that crosses midnight stays
// on the grid and draws a piece per day.
//
// Segments.js is covered on its own in tst_Segments.qml. These cases are about
// what the views do with it.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "AllDayEvents"
    when: windowShown
    visible: true
    width: 1000
    height: 760

    Item { id: host; anchors.fill: parent }

    property var seeded: []

    // A day far enough out that nothing an earlier run left behind is on it —
    // the shared QML test profile is never wiped.
    function probeDay(offset) {
        const d = new Date();
        d.setDate(d.getDate() + offset);
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function addEvent(day, opts) {
        const ev = AppController.newEventDraft(opts.start !== undefined ? opts.start : 9, day);
        ev.title = opts.title || "probe";
        ev.end = opts.end !== undefined ? opts.end : 10;
        ev.date = day;
        if (opts.endDate) ev.endDate = opts.endDate;
        if (opts.allDay) ev.allDay = true;
        AppController.saveEvent(ev);
        tc.seeded.push(ev.id);
        return ev.id;
    }

    function clearDay(day) {
        const evs = AppController.events;
        for (let i = evs.rowCount() - 1; i >= 0; i--) {
            const idx = evs.index(i, 0);
            const d = evs.data(idx, Qt.UserRole + 7);
            if (d && d.getFullYear && d.getFullYear() === day.getFullYear()
                && d.getMonth() === day.getMonth() && d.getDate() === day.getDate())
                AppController.deleteEvent(String(evs.data(idx, Qt.UserRole + 1)));
        }
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteEvent(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
    }

    // ── What the model reports ──

    // The two roles are appended, never inserted: the calendar QML reads event
    // roles by numeric offset, so a renumbering would repoint every view at the
    // wrong field.
    function test_the_new_roles_sit_at_the_end() {
        const day = probeDay(520);
        clearDay(day);
        const id = addEvent(day, { allDay: true, title: "role probe" });

        const m = AppController.events;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            if (String(m.data(idx, Qt.UserRole + 1)) !== id) continue;
            compare(m.data(idx, Qt.UserRole + 11), true, "AllDayRole is +11");
            const end = m.data(idx, Qt.UserRole + 12);
            verify(end && end.getFullYear, "EndDateRole is +12 and always a date");
            return;
        }
        fail("the seeded event was not in the model");
    }

    // A single-day event reports its own day as its end, so a delegate never
    // has to test for a missing end date.
    function test_a_single_day_event_reports_its_own_day_as_the_end() {
        const day = probeDay(521);
        clearDay(day);
        const id = addEvent(day, { start: 9, end: 10 });

        const m = AppController.events;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            if (String(m.data(idx, Qt.UserRole + 1)) !== id) continue;
            const end = m.data(idx, Qt.UserRole + 12);
            compare(end.getDate(), day.getDate());
            return;
        }
        fail("the seeded event was not in the model");
    }

    // saveEvent() forces an all-day event's hours; they carry no meaning and
    // leaving whatever the editor had would make the grid draw it at 09:00.
    function test_saving_an_all_day_event_discards_its_hours() {
        const day = probeDay(522);
        clearDay(day);
        const id = addEvent(day, { allDay: true, start: 9, end: 10 });

        const m = AppController.events;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            if (String(m.data(idx, Qt.UserRole + 1)) !== id) continue;
            compare(m.data(idx, Qt.UserRole + 4), 0);
            compare(m.data(idx, Qt.UserRole + 5), 24);
            return;
        }
        fail("the seeded event was not in the model");
    }

    // ── The day grid ──

    // ── The week grid ──

    function makeWeek(day) {
        AppController.selectedDate = day;
        const wv = createTemporaryQmlObject(
            'import TodoCpp; WeekView { anchors.fill: parent }', host);
        verify(wv !== null);
        wait(0);
        return wv;
    }

    function test_the_week_shows_an_all_day_bar() {
        const day = probeDay(540);
        clearDay(day);
        const id = addEvent(day, { allDay: true, title: "conference" });

        const wv = makeWeek(day);
        verify(findChild(wv, "allday-" + id) !== null);
    }

    // A bar spanning three days is three columns wide, not one.
    function test_a_multi_day_bar_spans_its_columns() {
        // A Monday, so the three days never cross the week's edge: a bar that
        // runs into the next week is clipped to this one, and that depended
        // on which weekday "today + 541" happened to fall on.
        const first = probeDay(541);
        first.setDate(first.getDate() - (first.getDay() + 6) % 7);
        const last = new Date(first);
        last.setDate(first.getDate() + 2);
        clearDay(first);
        const shortId = addEvent(first, { allDay: true, title: "one day" });
        const longId = addEvent(first, { allDay: true, endDate: last, title: "three days" });

        const wv = makeWeek(first);
        const one = findChild(wv, "allday-" + shortId);
        const three = findChild(wv, "allday-" + longId);
        verify(one !== null && three !== null);
        verify(three.width > one.width * 2, "three days must be visibly wider than one");
    }

    // Overlapping bars stack rather than hiding each other.
    function test_overlapping_bars_take_different_rows() {
        const first = probeDay(545);
        clearDay(first);
        const a = addEvent(first, { allDay: true, endDate: probeDay(547), title: "a" });
        const b = addEvent(first, { allDay: true, endDate: probeDay(546), title: "b" });

        const wv = makeWeek(first);
        const barA = findChild(wv, "allday-" + a);
        const barB = findChild(wv, "allday-" + b);
        verify(barA !== null && barB !== null);
        verify(barA.y !== barB.y, "two bars covering the same day must not sit on top of each other");
    }

    // The week's overlap map is keyed per piece: the same event can appear in
    // several columns, and keying by event id let one day's piece overwrite
    // another's.
    function test_a_cross_midnight_event_appears_in_two_week_columns() {
        // Both halves must sit in one week: a probe day that lands on the
        // week's last day sends the second half into the next one.
        let offset = 550;
        while (probeDay(offset).getDay() !== 3) offset++;
        const first = probeDay(offset);
        const second = probeDay(offset + 1);
        clearDay(first);
        clearDay(second);
        const id = addEvent(first, { start: 22, end: 2, endDate: second, title: "night call" });

        const wv = makeWeek(first);
        let seen = 0;
        for (let i = 0; i < wv.flatEvents.length; i++)
            if (wv.flatEvents[i].id === id) seen++;
        compare(seen, 2, "one event, two pieces");
    }

    function test_the_week_strip_is_hidden_with_no_all_day_events() {
        const day = probeDay(552);
        clearDay(day);
        addEvent(day, { start: 9, end: 10 });

        const wv = makeWeek(day);
        const strip = findChild(wv, "allday-strip");
        verify(strip !== null);
        verify(!strip.visible);
    }
}
