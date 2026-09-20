// Moving around the calendar, and finding an event without paging to it.
//
// The calendar was mouse-only: the only way to reach next week was the header
// button, and the only way to reach a meeting you knew the name of was to page
// to the week it was in. Ctrl+K reached the board, the notes and the docs, and
// stopped at the calendar.
//
// The shortcut wiring in Main.qml is thin and offscreen key delivery is not
// something to build a suite on, so these drive the public step() the keys call
// and the palette entries AppController builds.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "CalendarNav"
    when: windowShown
    visible: true
    width: 1000
    height: 700

    Item { id: host; anchors.fill: parent }

    property var seeded: []
    property var savedDate: undefined

    function probeDay(offset) {
        const d = new Date();
        d.setDate(d.getDate() + offset);
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function init() {
        tc.savedDate = AppController.selectedDate;
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteEvent(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
        if (tc.savedDate) AppController.selectedDate = tc.savedDate;
    }

    function makeWeek(day) {
        AppController.selectedDate = day;
        const wv = createTemporaryQmlObject(
            'import TodoCpp; WeekView { anchors.fill: parent }', host);
        verify(wv !== null);
        wait(0);
        return wv;
    }

    function daysBetween(a, b) {
        return Math.round((Date.UTC(b.getFullYear(), b.getMonth(), b.getDate())
                         - Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) / 86400000);
    }

    // ── Stepping ──

    // step() is the name MonthView already used, so the keyboard can move the
    // date without knowing which calendar is on screen.
    function test_the_week_steps_a_week_at_a_time() {
        const day = probeDay(900);
        const wv = makeWeek(day);
        const before = wv.weekStart;

        wv.step(1);

        compare(daysBetween(before, wv.weekStart), 7);
    }

    function test_the_week_steps_backwards() {
        const day = probeDay(910);
        const wv = makeWeek(day);
        const before = wv.weekStart;

        wv.step(-1);

        compare(daysBetween(before, wv.weekStart), -7);
    }

    // Stepping there and back is where off-by-one errors show up.
    function test_stepping_back_and_forth_returns_to_the_same_week() {
        const day = probeDay(920);
        const wv = makeWeek(day);
        const before = wv.weekStart;

        wv.step(1);
        wv.step(-1);

        compare(daysBetween(before, wv.weekStart), 0);
    }

    function test_the_month_steps_a_month_at_a_time() {
        AppController.selectedDate = new Date(2027, 2, 15);
        const mv = createTemporaryQmlObject(
            'import TodoCpp; MonthView { anchors.fill: parent }', host);
        verify(mv !== null);

        mv.step(1);

        compare(AppController.selectedDate.getMonth(), 3);
    }

    // ── Events in the palette ──

    function addEvent(day, title, opts) {
        const ev = AppController.newEventDraft(10, day);
        ev.title = title;
        ev.end = 11;
        ev.date = day;
        if (opts && opts.rrule) ev.rrule = opts.rrule;
        if (opts && opts.allDay) ev.allDay = true;
        AppController.saveEvent(ev);
        tc.seeded.push(ev.id);
        return ev.id;
    }

    function paletteEntriesFor(id) {
        const out = [];
        const all = AppController.commandPaletteEntries();
        for (let i = 0; i < all.length; i++) {
            if (all[i].kind === "event" && all[i].eventId === id) out.push(all[i]);
        }
        return out;
    }

    function test_an_event_is_findable_in_the_palette() {
        const day = probeDay(930);
        const id = addEvent(day, "palette probe meeting");

        const hits = paletteEntriesFor(id);
        compare(hits.length, 1);
        compare(hits[0].label, "palette probe meeting");
        verify(hits[0].eventDate !== undefined, "it has to carry a date to navigate to");
    }

    // An entry without a date could only drop the reader on today, which is
    // not where the meeting is.
    function test_the_entry_carries_the_day_to_navigate_to() {
        const day = probeDay(935);
        const id = addEvent(day, "dated probe meeting");

        const hits = paletteEntriesFor(id);
        compare(hits.length, 1);
        compare(daysBetween(day, hits[0].eventDate), 0);
    }

    // A repeating event says so, because one entry stands for the whole series.
    function test_a_repeating_event_is_marked_as_such() {
        const day = probeDay(940);
        const id = addEvent(day, "repeating probe meeting", { rrule: "FREQ=WEEKLY" });

        const hits = paletteEntriesFor(id);
        compare(hits.length, 1);
        verify(hits[0].sub.indexOf("repeats") >= 0);
    }

    // One entry per series, not one per occurrence: the palette's cost must not
    // depend on how far ahead people plan.
    function test_a_series_contributes_one_entry() {
        const day = probeDay(945);
        const id = addEvent(day, "single entry probe", { rrule: "FREQ=DAILY" });

        compare(paletteEntriesFor(id).length, 1);
    }

    // An untitled event would show as a blank row nothing could identify.
    function test_an_untitled_event_is_not_listed() {
        const day = probeDay(950);
        const ev = AppController.newEventDraft(10, day);
        ev.title = "";
        ev.date = day;
        AppController.saveEvent(ev);
        tc.seeded.push(ev.id);

        compare(paletteEntriesFor(ev.id).length, 0);
    }

    // An all-day event has no hour to show, and showing 00:00 would read as a
    // meeting at midnight.
    function test_an_all_day_event_shows_no_time() {
        const day = probeDay(955);
        const id = addEvent(day, "all day probe", { allDay: true });

        const hits = paletteEntriesFor(id);
        compare(hits.length, 1);
        verify(hits[0].sub.indexOf("00:00") < 0);
    }
}
