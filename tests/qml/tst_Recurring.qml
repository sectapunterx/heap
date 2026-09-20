// Repeating events in the views and the editor.
//
// A repeating event is stored once and expanded on read, so the thing a view
// draws is an occurrence, not a row. The expansion and the three edit scopes
// are covered in C++ (test_occurrences.cpp, test_series_edits.cpp); these cases
// are about the views reading the expansion and the editor carrying the series
// through.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Recurring"
    when: windowShown
    visible: true
    width: 1000
    height: 760

    Item { id: host; anchors.fill: parent }

    property var seeded: []

    // Far enough out that nothing an earlier run left behind is in range — the
    // shared QML test profile is never wiped.
    function probeDay(offset) {
        const d = new Date();
        d.setDate(d.getDate() + offset);
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function clearRange(from, to) {
        const evs = AppController.events;
        for (let i = evs.rowCount() - 1; i >= 0; i--) {
            const idx = evs.index(i, 0);
            const d = evs.data(idx, Qt.UserRole + 7);
            if (d && d.getFullYear && d >= from && d <= to)
                AppController.deleteEvent(String(evs.data(idx, Qt.UserRole + 1)));
        }
    }

    function addSeries(day, rule, title) {
        const ev = AppController.newEventDraft(10, day);
        ev.title = title || "weekly sync";
        ev.end = 11;
        ev.date = day;
        ev.rrule = rule;
        AppController.saveEvent(ev);
        tc.seeded.push(ev.id);
        return ev.id;
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteEvent(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
    }

    // ── The expansion, across the QML boundary ──

    function test_a_series_is_one_row_and_many_occurrences() {
        const day = probeDay(600);
        clearRange(day, probeDay(630));
        const before = AppController.events.rowCount();
        addSeries(day, "FREQ=WEEKLY");

        compare(AppController.events.rowCount(), before + 1, "a series is stored once");
        const occ = AppController.eventOccurrences(day, probeDay(621));
        compare(occ.length, 4);
    }

    // Everything the views need rides on the occurrence itself, so no delegate
    // has to know anything about recurrence.
    function test_an_occurrence_carries_its_series() {
        const day = probeDay(605);
        clearRange(day, probeDay(620));
        const id = addSeries(day, "FREQ=DAILY");

        const occ = AppController.eventOccurrences(day, probeDay(607));
        verify(occ.length >= 2);
        compare(occ[1].masterId, id);
        verify(occ[1].occurrenceDate !== undefined);
        verify(occ[1].generated);
        compare(occ[1].title, "weekly sync");
    }

    function test_an_ordinary_event_is_not_generated() {
        const day = probeDay(610);
        clearRange(day, probeDay(612));
        const ev = AppController.newEventDraft(10, day);
        ev.date = day;
        ev.title = "one off";
        AppController.saveEvent(ev);
        tc.seeded.push(ev.id);

        const occ = AppController.eventOccurrences(day, day);
        compare(occ.length, 1);
        verify(!occ[0].generated);
        compare(occ[0].masterId, "");
    }

    // ── The day grid ──

    function makeDay(day) {
        AppController.selectedDate = day;
        const dc = createTemporaryQmlObject(
            'import TodoCpp; DayCalendar { anchors.fill: parent }', host);
        verify(dc !== null);
        wait(0);
        return dc;
    }

    // The point of the whole thing: the second Monday shows a meeting that was
    // never written down.
    function test_a_later_occurrence_is_drawn() {
        const first = probeDay(615);
        clearRange(first, probeDay(640));
        const id = addSeries(first, "FREQ=WEEKLY");

        const dc = makeDay(probeDay(622));
        const block = findChild(dc, "event-" + id);
        verify(block !== null && block.visible, "the following week must draw it too");
        verify(block.repeating, "and know it belongs to a series");
    }

    function test_a_day_between_occurrences_is_empty() {
        const first = probeDay(645);
        clearRange(first, probeDay(670));
        const id = addSeries(first, "FREQ=WEEKLY");

        const dc = makeDay(probeDay(648));
        const block = findChild(dc, "event-" + id);
        verify(block === null || !block.visible);
    }

    // ── The three scopes, through the model ──

    function occurrenceOn(day) {
        const occ = AppController.eventOccurrences(day, day);
        return occ.length > 0 ? occ[0] : null;
    }

    function test_deleting_one_occurrence_leaves_the_series() {
        const first = probeDay(675);
        clearRange(first, probeDay(700));
        const id = addSeries(first, "FREQ=WEEKLY");
        const second = probeDay(682);

        AppController.deleteOccurrence(id, second, "this");

        compare(occurrenceOn(second), null, "that one is gone");
        verify(occurrenceOn(probeDay(689)) !== null, "the rest of the series is not");
        compare(AppController.events.rowCount() > 0, true);
    }

    function test_editing_one_occurrence_leaves_the_series() {
        const first = probeDay(705);
        clearRange(first, probeDay(730));
        addSeries(first, "FREQ=WEEKLY");
        const second = probeDay(712);

        const occ = occurrenceOn(second);
        verify(occ !== null);
        occ.title = "moved this week";
        AppController.saveOccurrence(occ, "this");
        tc.seeded.push(occ.id);

        compare(occurrenceOn(second).title, "moved this week");
        compare(occurrenceOn(probeDay(719)).title, "weekly sync");
    }

    function test_editing_all_rewrites_the_series() {
        const first = probeDay(735);
        clearRange(first, probeDay(760));
        addSeries(first, "FREQ=WEEKLY");

        const occ = occurrenceOn(probeDay(742));
        occ.title = "renamed";
        AppController.saveOccurrence(occ, "all");

        compare(occurrenceOn(first).title, "renamed");
        compare(occurrenceOn(probeDay(749)).title, "renamed");
    }

    // ── The editor ──

    function makeEditor() {
        const ed = createTemporaryQmlObject(
            'import TodoCpp; EventEditor { }', host);
        verify(ed !== null);
        return ed;
    }

    function test_the_editor_reads_the_rule_off_the_master() {
        const first = probeDay(765);
        clearRange(first, probeDay(790));
        addSeries(first, "FREQ=WEEKLY");

        const ed = makeEditor();
        ed.showForOccurrence(occurrenceOn(probeDay(772)));

        verify(ed.repeating, "an occurrence of a series is repeating");
        // The rule lives on the master; a generated instance carries none.
        compare(ed.customRule, "FREQ=WEEKLY");
        ed.close();
    }

    function test_the_editor_remembers_which_occurrence_it_opened() {
        const first = probeDay(795);
        clearRange(first, probeDay(820));
        addSeries(first, "FREQ=WEEKLY");
        const second = probeDay(802);

        const ed = makeEditor();
        ed.showForOccurrence(occurrenceOn(second));

        compare(ed.originalDate.getDate(), second.getDate());
        ed.close();
    }

    // An ordinary event must not be dragged into the series machinery.
    function test_an_ordinary_event_is_not_repeating_in_the_editor() {
        const day = probeDay(825);
        clearRange(day, day);
        const ev = AppController.newEventDraft(10, day);
        ev.date = day;
        AppController.saveEvent(ev);
        tc.seeded.push(ev.id);

        const ed = makeEditor();
        ed.showForOccurrence(occurrenceOn(day));

        verify(!ed.repeating);
        compare(ed.masterId, "");
        ed.close();
    }

    // A rule heap does not model is kept, not rewritten into the nearest one
    // it does.
    function test_an_unknown_rule_lands_on_custom() {
        const ed = makeEditor();
        const odd = "FREQ=WEEKLY;BYDAY=MO,WE,FR;INTERVAL=3";

        ed.showForOccurrence({ id: "x", title: "t", type: "sync", start: 9, end: 10,
                               date: probeDay(830), rrule: odd, masterId: "m",
                               occurrenceDate: probeDay(830) });

        compare(ed.customRule, odd, "the rule survives being displayed");
        ed.close();
    }
}
