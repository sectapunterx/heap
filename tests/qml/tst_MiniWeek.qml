// MiniWeek (sidebar week strip): load-smoke against the live AppController plus
// the date math its rendering rests on — isoFor/isSameDay/startOfWeek/dayList —
// and the event-dot wiring (eventCountFor + the _eventsRev bump on model change).
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "MiniWeek"
    when: windowShown
    visible: true
    width: 400
    height: 400

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // The QML-test profile persists between runs and is shared by all tst_
    // files, so every method wipes the probe day it uses before and after.
    function _wipeEventsOn(day) {
        const evs = AppController.events;
        for (let i = evs.rowCount() - 1; i >= 0; i--) {
            const idx = evs.index(i, 0);
            const d = evs.data(idx, Qt.UserRole + 7);   // EventModel::DateRole
            if (d && d.getFullYear
                && d.getFullYear() === day.getFullYear()
                && d.getMonth() === day.getMonth()
                && d.getDate() === day.getDate())
                AppController.deleteEvent(String(evs.data(idx, Qt.UserRole + 1)));  // IdRole
        }
    }

    // Smoke: instantiates against the live singletons; a renamed property or a
    // missing type would make createTemporaryQmlObject return null.
    function test_smoke_load() {
        const mw = make('import TodoCpp; MiniWeek { width: 320 }');
        compare(mw._days.length, 7, "the strip always renders a full week");
        compare(mw.dowLabelsByJsDow.length, 7, "one label per JS day-of-week");
    }

    // isoFor: yyyy-MM-dd with zero padding. Qt.formatDate is the independent
    // reference implementation, so this is not circular.
    function test_isofor_formats_iso_date() {
        const mw = make('import TodoCpp; MiniWeek { width: 320 }');
        const d = new Date();
        d.setDate(d.getDate() + 465);
        d.setHours(0, 0, 0, 0);
        compare(mw.isoFor(d), Qt.formatDate(d, "yyyy-MM-dd"));
    }

    // isSameDay: date-only comparison — time of day must not matter, and
    // null/undefined must be rejected instead of throwing.
    function test_is_same_day() {
        const mw = make('import TodoCpp; MiniWeek { width: 320 }');
        const a = new Date();
        a.setDate(a.getDate() + 463);
        a.setHours(9, 15, 0, 0);
        const b = new Date(a);
        b.setHours(23, 59, 0, 0);
        verify(mw.isSameDay(a, b), "same calendar day, different clock time");
        const c = new Date(a);
        c.setDate(c.getDate() + 1);
        verify(!mw.isSameDay(a, c), "next day must not match");
        verify(!mw.isSameDay(null, a), "null lhs is not a match");
        verify(!mw.isSameDay(a, undefined), "undefined rhs is not a match");
    }

    // startOfWeek: lands on the configured first day of week (Theme.weekStart
    // is read-only, so the contract is checked against its current value),
    // never overshoots the input, and is idempotent.
    function test_start_of_week_contract() {
        const mw = make('import TodoCpp; MiniWeek { width: 320 }');
        const d = new Date();
        d.setDate(d.getDate() + 467);
        d.setHours(0, 0, 0, 0);
        const s = mw.startOfWeek(d);
        const expectedDow = Theme.weekStart === "sun" ? 0 : 1;
        compare(s.getDay(), expectedDow, "week starts on the configured day");
        const diffDays = Math.round((d.getTime() - s.getTime()) / 86400000);
        verify(diffDays >= 0 && diffDays < 7, "start of week is 0..6 days before the input");
        verify(mw.isSameDay(mw.startOfWeek(s), s), "startOfWeek is idempotent");
    }

    // refDate binds to AppController.selectedDate and _days re-evaluates from
    // it: 7 consecutive days from startOfWeek, containing the selected day.
    function test_daylist_follows_selected_date() {
        const prev = AppController.selectedDate;
        const day = new Date();
        day.setDate(day.getDate() + 460);
        day.setHours(0, 0, 0, 0);
        AppController.selectedDate = day;

        const mw = make('import TodoCpp; MiniWeek { width: 320 }');
        verify(mw.isSameDay(mw.refDate, day), "refDate follows AppController.selectedDate");
        compare(mw._days.length, 7);
        verify(mw.isSameDay(mw._days[0], mw.startOfWeek(day)), "strip begins at startOfWeek(refDate)");
        for (let i = 1; i < 7; i++) {
            const p = mw._days[i - 1];
            const next = new Date(p.getFullYear(), p.getMonth(), p.getDate() + 1);
            verify(mw.isSameDay(mw._days[i], next), "days are consecutive at index " + i);
        }
        let hit = false;
        for (let i = 0; i < 7; i++) if (mw.isSameDay(mw._days[i], day)) hit = true;
        verify(hit, "selected day is inside the rendered week");

        // Live re-evaluation: moving the selection a week ahead shifts the strip.
        const day2 = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 7);
        AppController.selectedDate = day2;
        verify(mw.isSameDay(mw.refDate, day2), "refDate tracks a later selection");
        verify(mw.isSameDay(mw._days[0], mw.startOfWeek(day2)), "_days re-evaluates with the selection");

        AppController.selectedDate = prev;  // restore global state for other tests
    }

    // eventCountFor scans the live events model by DateRole — the count feeds
    // the per-day dot indicator.
    function test_event_count_for() {
        const mw = make('import TodoCpp; MiniWeek { width: 320 }');
        const day = new Date();
        day.setDate(day.getDate() + 461);
        day.setHours(0, 0, 0, 0);

        _wipeEventsOn(day);
        compare(mw.eventCountFor(day), 0, "probe day starts empty");

        const ev = AppController.newEventDraft(AppController.workdayStart, day);
        ev.title = "miniweek count probe";
        ev.date = day;
        AppController.saveEvent(ev);
        compare(mw.eventCountFor(day), 1);

        const ev2 = AppController.newEventDraft(AppController.workdayStart + 2, day);
        ev2.title = "miniweek count probe 2";
        ev2.date = day;
        AppController.saveEvent(ev2);
        compare(mw.eventCountFor(day), 2);

        _wipeEventsOn(day);
        compare(mw.eventCountFor(day), 0, "probe day left clean");
    }

    // The Connections block bumps _eventsRev on rowsInserted/rowsRemoved —
    // that revision is what forces the dot indicators to re-query the model.
    // EventModel::upsert/removeById emit synchronously, so no waits needed.
    function test_events_rev_bumps_on_model_change() {
        const mw = make('import TodoCpp; MiniWeek { width: 320 }');
        const day = new Date();
        day.setDate(day.getDate() + 462);
        day.setHours(0, 0, 0, 0);
        _wipeEventsOn(day);

        const rev0 = mw._eventsRev;
        const ev = AppController.newEventDraft(AppController.workdayStart, day);
        ev.title = "miniweek rev probe";
        ev.date = day;
        AppController.saveEvent(ev);
        verify(mw._eventsRev > rev0, "rowsInserted must bump _eventsRev");

        const rev1 = mw._eventsRev;
        _wipeEventsOn(day);
        verify(mw._eventsRev > rev1, "rowsRemoved must bump _eventsRev");
    }
}
