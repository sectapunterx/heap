// Calendar views after the 2026-09-30 audit (TIME-*). Each case names the
// finding it pins. The C++ halves are in tests/test_time_audit.cpp; these are
// about what the grids, the editor and the pickers do with real input.
import QtQuick
import QtTest
import QtQuick.Controls
import TodoCpp

TestCase {
    id: tc
    name: "TimeAudit"
    when: windowShown
    visible: true
    width: 1200
    height: 800

    Item { id: host; anchors.fill: parent }

    property var seeded: []
    property var seededTasks: []

    // Far out, so nothing an earlier run left behind is in range — the test
    // profile is never wiped.
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
    function addEvent(day, start, end, rule, title) {
        const ev = AppController.newEventDraft(start, day);
        ev.title = title || "audit sync";
        ev.end = end;
        ev.date = day;
        ev.rrule = rule || "";
        AppController.saveEvent(ev);
        tc.seeded.push(ev.id);
        return ev.id;
    }
    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteEvent(tc.seeded[i]);
        tc.seeded = [];
        for (let i = 0; i < tc.seededTasks.length; i++) AppController.deleteTask(tc.seededTasks[i]);
        tc.seededTasks = [];
        AppController.clearPendingUndo();
    }
    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function occOn(day) {
        const occ = AppController.eventOccurrences(day, day);
        return occ.length > 0 ? occ[0] : null;
    }
    function scrollToTop(root) {
        const stack = [root];
        while (stack.length > 0) {
            const it = stack.pop();
            if (it.contentY !== undefined && it.contentHeight > it.height) { it.contentY = 0; }
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) stack.push(kids[i]);
        }
        wait(20);
    }
    // In the test's own coordinates: the block follows the pointer, so moves
    // relative to it would add up.
    function dragBy(item, dx, dy) {
        const p = item.mapToItem(tc, item.width / 2, item.height / 2);
        mousePress(tc, p.x, p.y);
        for (let i = 1; i <= 10; i++) mouseMove(tc, p.x + dx * i / 10, p.y + dy * i / 10);
        mouseRelease(tc, p.x + dx, p.y + dy);
    }

    // ── TIME-17: a click on the day grid opens the editor, snapped ──

    // ── TIME-1: dragging one occurrence asks, and "this" moves only it ──

    // ── TIME-10: the after-midnight piece moves the event by the drag ──

    // ── TIME-4: the week grid's vertical drag reaches the model ──

    function test_week_vertical_drag_moves_the_event() {
        const day = probeDay(1223);
        clearRange(probeDay(1218), probeDay(1230));
        const id = addEvent(day, 10, 11);
        AppController.selectedDate = day;
        const wv = createTemporaryQmlObject('import TodoCpp; WeekView { anchors.fill: parent }', host);
        verify(wv !== null);
        wait(50);
        let block = null;
        const flat = wv.flatEvents;
        for (let i = 0; i < flat.length; i++) if (flat[i].id === id) block = i;
        verify(block !== null, "the event is in the week");
        // Find the delegate by walking for the event's title text's parent.
        const target = findDelegate(wv, id);
        verify(target !== null);
        dragBy(target, 0, wv.hourH * 2);
        wait(20);
        fuzzyCompare(AppController.eventById(id).start, 12, 0.01);
    }
    function findDelegate(root, id) {
        const stack = [root];
        while (stack.length > 0) {
            const it = stack.pop();
            if (it.modelData && it.modelData.id === id && it.modelData.occ !== undefined && it.effStart !== undefined) return it;
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) stack.push(kids[i]);
            if (it.contentItem && it.contentItem !== it) stack.push(it.contentItem);
        }
        return null;
    }

    // ── TIME-11: an event and a task block at the same time sit side by side ──

    // ── TIME-29: the empty-day hint is not drawn over task blocks ──

    // ── TIME-24 / TIME-32: the editor's parsing and rule builder ──

    function test_editor_reads_compact_times() {
        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        fuzzyCompare(ed.parseHourStrict("930"), 9.5, 0.001);
        fuzzyCompare(ed.parseHourStrict("9.30"), 9.5, 0.001);
        fuzzyCompare(ed.parseHourStrict("1415"), 14.25, 0.001);
        fuzzyCompare(ed.parseHourStrict("9"), 9, 0.001);
        verify(isNaN(ed.parseHourStrict("junk")));
        verify(isNaN(ed.parseHourStrict("")));
    }

    // DG-120: the panel saves on its own, so "refused" means nothing is
    // written — no name, no meeting; an end typed before the start keeps the
    // length instead of becoming a 23-hour event.
    function test_editor_refuses_an_empty_title_and_a_backwards_end() {
        const day = probeDay(1250);
        clearRange(day, day);
        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        const draft = AppController.newEventDraft(10, day);
        draft.title = "";
        ed.showForDraft(draft);
        const before = AppController.events.rowCount();
        findChild(ed, "event-title").text = "";
        ed._save("text");
        compare(AppController.events.rowCount(), before, "a nameless meeting is not made");

        findChild(ed, "event-title").text = "named";
        ed._save("text");
        tc.seeded.push(draft.id);
        compare(ed.applyWhen("11:00-10:00"), "");
        const back = AppController.eventById(draft.id);
        verify(back.end > back.start, "an end before the start is not saved as a 23-hour event");
        verify(back.end - back.start <= 1.01);
        ed.close();
    }

    // The repeat menu's kinds and the rules they stand for; a rule the menu
    // cannot show stays as written ("custom").
    function test_editor_builds_weekday_and_end_rules() {
        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        compare(ed.repeatKindOf("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"), "weekdays");
        compare(ed.ruleFor("weekdays"), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR");
        compare(ed.repeatKindOf("FREQ=WEEKLY;INTERVAL=2"), "biweekly");
        compare(ed.repeatKindOf("FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6"), "custom");
        compare(ed.repeatKindOf("FREQ=MONTHLY;BYDAY=-1FR"), "custom", "a rule the menu cannot show stays as text");
        compare(ed.repeatKindOf(""), "never");
    }

    function test_editor_saves_notes_link_and_reminder() {
        const day = probeDay(1265);
        clearRange(day, day);
        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        const draft = AppController.newEventDraft(10, day);
        ed.showForDraft(draft);
        findChild(ed, "event-title").text = "with extras";
        findChild(ed, "event-agenda").text = "agenda";
        findChild(ed, "event-call").text = "https://meet.example/x";
        ed.reminderMinutes = 15;
        ed._save("text");
        tc.seeded.push(draft.id);
        const back = AppController.eventById(draft.id);
        compare(back.notes, "agenda");
        compare(back.url, "https://meet.example/x");
        compare(back.reminderMinutes, 15);
    }

    // TIME-25 is moot with autosave: what is typed is written on close.
    function test_unsaved_edits_survive_a_first_close_request() {
        const day = probeDay(1270);
        clearRange(day, day);
        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        const draft = AppController.newEventDraft(10, day);
        ed.showForDraft(draft);
        findChild(ed, "event-title").text = "half typed";
        ed.close();
        verify(!ed.opened);
        tc.seeded.push(draft.id);
        compare(AppController.eventById(draft.id).title, "half typed", "closing writes what was typed");
    }

    // ── TIME-16: the date picker is keyboard-driven ──

    function test_date_picker_keys() {
        const dp = createTemporaryQmlObject('import TodoCpp; DatePickerPopup { }', host);
        let got = null;
        dp.picked.connect((d) => got = d);
        dp.openAt(new Date(2027, 0, 30), host);
        wait(10);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Right);
        compare(dp.selected.getMonth(), 1, "arrows cross into the next month");
        compare(dp.selected.getDate(), 1);
        keyClick(Qt.Key_PageDown);
        compare(dp.selected.getMonth(), 2);
        keyClick(Qt.Key_Return);
        verify(got !== null);
        compare(got.getDate(), 1);
        compare(got.getMonth(), 2);
    }

    function test_date_picker_respects_its_minimum() {
        const dp = createTemporaryQmlObject('import TodoCpp; DatePickerPopup { }', host);
        dp.minimumDate = new Date(2027, 0, 10);
        dp.openAt(new Date(2027, 0, 10), host);
        wait(10);
        keyClick(Qt.Key_Left);
        compare(dp.selected.getDate(), 10, "a day before the minimum is not reachable");
        dp.close();
    }

    // ── TIME-23: month paging keeps the 31st ──

    function test_month_paging_returns_to_the_31st() {
        const mv = createTemporaryQmlObject('import TodoCpp; MonthView { anchors.fill: parent }', host);
        const prev = AppController.selectedDate;
        AppController.selectedDate = new Date(2027, 0, 31);
        mv.step(1);
        compare(AppController.selectedDate.getDate(), 28);
        mv.step(1);
        compare(AppController.selectedDate.getMonth(), 2);
        compare(AppController.selectedDate.getDate(), 31, "March is on the 31st again");
        mv.step(1);
        compare(AppController.selectedDate.getDate(), 30);
        AppController.selectedDate = prev;
    }

    // ── TIME-22: a month cell lists events in time order ──

    function test_month_cell_events_are_time_sorted() {
        const day = probeDay(1280);
        clearRange(day, day);
        addEvent(day, 16, 17, "", "late");
        addEvent(day, 9, 10, "", "early");
        addEvent(day, 12, 13, "", "noon");
        AppController.selectedDate = day;
        const mv = createTemporaryQmlObject('import TodoCpp; MonthView { anchors.fill: parent }', host);
        let cell = null;
        for (let k = 0; k < mv.cells.length; k++) if (sameDay(mv.cells[k].date, day)) cell = mv.cells[k];
        verify(cell !== null);
        compare(cell.events.map(e => e.title).join(","), "early,noon,late");
    }

    // ── TIME-15: a scheduled task without a deadline shows in the week ──

    function test_week_shows_a_scheduled_task() {
        const day = probeDay(1290);
        clearRange(day, day);
        const at = new Date(day);
        at.setHours(14, 0, 0, 0);
        const draft = AppController.newTaskDraft("todo");
        draft.title = "planned, no deadline";
        draft.scheduledAt = at;
        draft.hasTime = true;
        AppController.saveTask(draft);
        tc.seededTasks.push(draft.id);
        AppController.selectedDate = day;
        const wv = createTemporaryQmlObject('import TodoCpp; WeekView { anchors.fill: parent }', host);
        let found = false;
        for (let i = 0; i < wv.flatBlocks.length; i++) if (wv.flatBlocks[i].id === draft.id) found = true;
        verify(found, "the task has a block on the week grid");
    }

    // ── TIME-28: the mini week counts occurrences ──

    // ── TIME-1: an occurrence moved days away shows on its new day ──

    function occOf(id, day) {
        const occ = AppController.eventOccurrences(day, day);
        for (let i = 0; i < occ.length; i++)
            if ((occ[i].masterId === id || occ[i].id === id) && sameDay(occ[i].date, day)) return occ[i];
        return null;
    }

    function test_moved_occurrence_shows_in_week() {
        const friday = new Date(2034, 0, 13);
        const monday = new Date(2034, 0, 16);
        clearRange(new Date(2034, 0, 1), new Date(2034, 0, 31));
        const id = addEvent(new Date(2034, 0, 6), 10, 11, "FREQ=WEEKLY", "moved friday");
        AppController.moveOccurrence(occOf(id, friday), 72, "this");
        verify(occOf(id, monday) !== null, "a day's own range has it on Monday");
        verify(occOf(id, friday) === null, "gone from its Friday");

        AppController.selectedDate = monday;
        const wv = createTemporaryQmlObject('import TodoCpp; WeekView { anchors.fill: parent }', host);
        let seen = false;
        for (const d of wv.eventDays.days)
            for (const e of d.events)
                if (e.title === "moved friday" && sameDay(d.date, monday)) seen = true;
        verify(seen, "the week of the new day draws it");
    }

    // ── TIME-2: an untouched repeat rule is saved back as it was given ──

    function test_editor_hands_back_an_untouched_rule() {
        const start = new Date(2034, 2, 6);  // a Monday
        clearRange(new Date(2034, 2, 1), new Date(2034, 3, 30));
        const id = addEvent(start, 10, 11, "FREQ=WEEKLY;BYDAY=MO", "imported weekly");
        AppController.deleteOccurrence(id, new Date(2034, 2, 13), "this");

        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        ed.showForOccurrence(occOf(id, new Date(2034, 2, 27)));
        findChild(ed, "event-title").text = "renamed weekly";
        compare(ed._draft().rrule, "FREQ=WEEKLY;BYDAY=MO", "an untouched rule goes back as given");
        AppController.saveOccurrence(ed._draft(), "all");
        ed.close();
        compare(AppController.eventById(id).rrule, "FREQ=WEEKLY;BYDAY=MO");
        verify(occOf(id, new Date(2034, 2, 13)) === null, "the deleted one stays deleted");
        compare(occOf(id, new Date(2034, 3, 3)).title, "renamed weekly");

        ed.close();
    }
}
