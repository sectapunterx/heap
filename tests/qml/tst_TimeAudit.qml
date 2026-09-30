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
    function makeDay(day) {
        AppController.selectedDate = day;
        const dc = createTemporaryQmlObject('import TodoCpp; DayCalendar { anchors.fill: parent }', host);
        verify(dc !== null);
        wait(0);
        return dc;
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

    function test_day_click_asks_for_an_editor_instead_of_saving() {
        const day = probeDay(1201);
        clearRange(day, day);
        const dc = makeDay(day);
        let got = null;
        dc.createRequested.connect((s, e, d) => { got = { s: s, e: e, d: d }; });
        const before = AppController.events.rowCount();
        const area = findChild(dc, "day-create-area");
        verify(area !== null);
        // 14:40 on the grid, which a 15-minute snap puts at 14:45.
        mouseClick(area, 20, Theme.hourH * (14 + 40 / 60));

        compare(AppController.events.rowCount(), before, "nothing is saved by a click");
        verify(got !== null, "the editor is asked for");
        fuzzyCompare(got.s, 14.75, 0.01);
        fuzzyCompare(got.e, 15.75, 0.01);
    }

    // ── TIME-1: dragging one occurrence asks, and "this" moves only it ──

    function test_dragging_an_occurrence_asks_and_moves_only_it() {
        const first = probeDay(1210);
        clearRange(first, probeDay(1216));
        const id = addEvent(first, 10, 11, "FREQ=DAILY;COUNT=5");
        const day = probeDay(1212);
        const dc = makeDay(day);
        const block = findChild(dc, "event-" + id);
        verify(block !== null && block.visible);

        dragBy(block, 0, Theme.hourH * 2);
        const scope = dc.scopePrompt;
        verify(scope !== null, "the scope dialog exists");
        verify(scope.opened, "the scope question is asked");
        scope.answer("this");
        wait(20);

        fuzzyCompare(occOn(day).start, 12, 0.01);
        fuzzyCompare(occOn(first).start, 10, 0.01);
        compare(AppController.eventOccurrences(first, probeDay(1216)).length, 5, "no occurrence vanished");
    }

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

    function test_task_block_and_event_do_not_overlap() {
        const day = probeDay(1240);
        clearRange(day, day);
        const evId = addEvent(day, 10, 11, "", "covering meeting");
        const at = new Date(day);
        at.setHours(10, 0, 0, 0);
        const draft = AppController.newTaskDraft("todo");
        draft.title = "side-by-side probe";
        draft.scheduledAt = at;
        draft.hasTime = true;
        AppController.saveTask(draft);
        tc.seededTasks.push(draft.id);

        const dc = makeDay(day);
        const ev = findChild(dc, "event-" + evId);
        const tb = findChild(dc, "taskblock-" + draft.id);
        verify(ev !== null && tb !== null);
        verify(tb.visible);
        verify(tb.x + tb.width <= ev.x + 1 || ev.x + ev.width <= tb.x + 1, "the two columns do not overlap");
        let got = "";
        dc.taskClicked.connect((tid) => got = tid);
        mouseClick(tb);
        compare(got, draft.id, "the task block takes its own click");
    }

    // ── TIME-29: the empty-day hint is not drawn over task blocks ──

    function test_no_events_hint_hides_under_task_blocks() {
        const day = probeDay(1245);
        clearRange(day, day);
        const at = new Date(day);
        at.setHours(15, 0, 0, 0);
        const draft = AppController.newTaskDraft("todo");
        draft.title = "hint probe";
        draft.scheduledAt = at;
        draft.hasTime = true;
        AppController.saveTask(draft);
        tc.seededTasks.push(draft.id);
        const dc = makeDay(day);
        compare(dc._visibleTaskBlocks, 1);
    }

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

    function test_editor_refuses_an_empty_title_and_a_backwards_end() {
        const day = probeDay(1250);
        clearRange(day, day);
        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        const draft = AppController.newEventDraft(10, day);
        ed.showForDraft(draft);
        const before = AppController.events.rowCount();
        findChild(ed, "event-title").text = "";
        ed._save();
        compare(AppController.events.rowCount(), before);
        verify(ed._error.length > 0);

        findChild(ed, "event-title").text = "named";
        findChild(ed, "event-start").text = "11:00";
        findChild(ed, "event-end").text = "10:00";
        ed._save();
        compare(AppController.events.rowCount(), before, "an end before the start is not saved as a 23-hour event");
        ed.close();
    }

    function test_editor_builds_weekday_and_end_rules() {
        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        const day = probeDay(1260);
        ed.showForDraft(AppController.newEventDraft(10, day));
        ed._loadRule("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR");
        compare(ed._kind(), "weekdays");
        compare(ed._ruleFromBox(), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR");

        ed._loadRule("FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6");
        compare(ed._kind(), "weekly");
        compare(ed.repeatDays.join(","), "1,3");
        compare(ed._ruleFromBox(), "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6");

        ed._loadRule("FREQ=MONTHLY;BYDAY=-1FR");
        compare(ed._kind(), "custom", "a rule the controls cannot show stays as text");
        compare(ed._ruleFromBox(), "FREQ=MONTHLY;BYDAY=-1FR");
        ed.close();
    }

    function test_editor_saves_notes_link_and_reminder() {
        const day = probeDay(1265);
        clearRange(day, day);
        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        const draft = AppController.newEventDraft(10, day);
        ed.showForDraft(draft);
        findChild(ed, "event-title").text = "with extras";
        findChild(ed, "event-notes").text = "agenda";
        findChild(ed, "event-link").text = "https://meet.example/x";
        findChild(ed, "event-location").text = "Room 1";
        findChild(ed, "event-reminder").currentIndex = ed.reminderChoices.indexOf(15);
        ed._save();
        tc.seeded.push(draft.id);
        const back = AppController.eventById(draft.id);
        compare(back.notes, "agenda");
        compare(back.url, "https://meet.example/x");
        compare(back.location, "Room 1");
        compare(back.reminderMinutes, 15);
    }

    // ── TIME-25: a click outside with unsaved edits asks first ──

    function test_unsaved_edits_survive_a_first_close_request() {
        const ed = createTemporaryQmlObject('import TodoCpp; EventEditor { }', host);
        ed.showForDraft(AppController.newEventDraft(10, probeDay(1270)));
        findChild(ed, "event-title").text = "half typed";
        ed._requestClose();
        verify(ed.opened, "the first request only warns");
        verify(ed._confirmDiscard);
        ed._requestClose();
        verify(!ed.opened, "the second one discards");
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

    function test_mini_week_counts_a_daily_series() {
        const first = probeDay(1300);
        clearRange(first, probeDay(1310));
        addEvent(first, 9, 10, "FREQ=DAILY");
        const mw = createTemporaryQmlObject('import TodoCpp; MiniWeek { }', host);
        verify(mw.eventCountFor(probeDay(1303)) >= 1, "a later day of the series has a dot");
    }
}
