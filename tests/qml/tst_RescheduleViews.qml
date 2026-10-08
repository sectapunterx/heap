// Drag-to-reschedule in Week, Month and Timeline (APP-249): a drop writes the
// date, Esc during the drag leaves it alone, and the undo takes the drop back.
// The move keys' view half (moveKeyTaskByDays) is driven directly; Main.qml's
// Shortcuts only call it.
//
// The views run against the live AppController, whose test profile persists
// between runs (%APPDATA%\qttest\heap_qml_tests): every task here has an id
// of its own, is deleted before it is made and again at the end.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "RescheduleViews"
    when: windowShown
    visible: true
    width: 1200
    height: 900

    Item { id: host; anchors.fill: parent }

    // A Wednesday far from today, so nothing else on the profile is in its week.
    readonly property var wed: new Date(2031, 2, 12)

    function day(y, m, d, h, min) { return new Date(y, m - 1, d, h || 0, min || 0); }
    function sameMinute(a, b) { return !!a && !!b && a.getTime() === b.getTime(); }
    function sameDay(a, b) {
        return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function seed(id, fields) {
        AppController.deleteTask(id);
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.id = id;
        d.title = id + " probe";
        for (const k in fields) d[k] = fields[k];
        verify(AppController.saveTask(d), "seeding " + id);
    }
    function task(id) { return AppController.taskById(id); }

    property var _savedDate: null
    property var _made: []
    function init() {
        tc._savedDate = AppController.selectedDate;
        tc._made = [];
    }
    function cleanup() {
        for (let i = 0; i < tc._made.length; i++) AppController.deleteTask(tc._made[i]);
        AppController.clearPendingUndo();
        AppController.selectedDate = tc._savedDate;
    }
    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }
    function center(item) { return { x: item.width / 2, y: item.height / 2 }; }
    // A press on `item` and a walk of the pointer, in `view` coordinates, to
    // `to` — in steps, past the drag threshold.
    function dragTo(view, item, to, release) {
        const c = center(item);
        const from = item.mapToItem(view, c.x, c.y);
        mousePress(item, c.x, c.y);
        for (let i = 1; i <= 10; i++)
            mouseMove(view, from.x + (to.x - from.x) * i / 10, from.y + (to.y - from.y) * i / 10);
        if (release !== false) mouseRelease(view, to.x, to.y);
    }

    // ── Timeline ─────────────────────────────────────────────────────
    function makeTimeline() {
        const tv = make('import TodoCpp; TimelineView { anchors.fill: parent }');
        tv._rebuild();
        return tv;
    }
    function timelineRow(tv, id) {
        let found = null;
        tryVerify(function () {
            (function walk(it) {
                if (!it || found) return;
                if (String(it.objectName) === "tl-row" && it.t && it.t.id === id && it.visible) { found = it; return; }
                const kids = it.children || [];
                for (let i = 0; i < kids.length; i++) walk(kids[i]);
            })(tv);
            return found !== null;
        }, 3000, "row " + id);
        return found;
    }
    function scrollTo(tv, id) {
        const list = findChild(tv, "timeline-rows");
        for (let i = 0; i < tv.flatRows.length; i++)
            if (tv.flatRows[i].kind === "task" && tv.flatRows[i].task.id === id) { list.positionViewAtIndex(i, ListView.Beginning); break; }
    }
    function laterDue() {
        const t = AppController.today;
        return new Date(t.getFullYear(), t.getMonth(), t.getDate() + 40);
    }
    function tomorrow() {
        const t = AppController.today;
        return new Date(t.getFullYear(), t.getMonth(), t.getDate() + 1);
    }

    function test_timeline_drop_on_a_group_moves_the_deadline_and_undo_restores() {
        const id = "RSV-TL1";
        tc._made.push(id);
        const due = laterDue();
        seed(id, { dueAt: due, scheduledAt: null, dueHasTime: false });
        const tv = makeTimeline();
        scrollTo(tv, id);
        const row = timelineRow(tv, id);

        // The group bar shows once the drag is on; the pill is the target.
        const c = center(row);
        const from = row.mapToItem(tv, c.x, c.y);
        mousePress(row, c.x, c.y);
        mouseMove(tv, from.x + 10, from.y + 10);
        verify(tv.drag !== null, "the drag started");
        const pill = findChild(tv, "tl-drop-tomorrow");
        verify(pill && pill.visible);
        const to = pill.mapToItem(tv, pill.width / 2, pill.height / 2);
        mouseMove(tv, to.x, to.y);
        compare(tv.dragBucket, "tomorrow");
        const hint = findChild(tv, "reschedule-hint-text");
        verify(hint.text.length > 0 && hint.text.indexOf(I18n.t("drag.field.due")) === 0,
               "the hint names the field that changes: " + hint.text);
        mouseRelease(tv, to.x, to.y);

        verify(sameDay(task(id).dueAt, tomorrow()), "deadline is tomorrow");
        verify(AppController.undoEntry(AppController.undoSerialForToast()));
        verify(sameDay(task(id).dueAt, due), "undo puts it back");
    }

    function test_timeline_esc_cancels() {
        const id = "RSV-TL2";
        tc._made.push(id);
        const due = laterDue();
        seed(id, { dueAt: due, scheduledAt: null, dueHasTime: false });
        const tv = makeTimeline();
        scrollTo(tv, id);
        const row = timelineRow(tv, id);
        const c = center(row);
        const from = row.mapToItem(tv, c.x, c.y);
        mousePress(row, c.x, c.y);
        mouseMove(tv, from.x + 10, from.y + 10);
        const pill = findChild(tv, "tl-drop-nodl");
        const to = pill.mapToItem(tv, pill.width / 2, pill.height / 2);
        mouseMove(tv, to.x, to.y);
        keyClick(Qt.Key_Escape);
        verify(tv.drag === null, "Esc ended the drag");
        mouseMove(tv, to.x + 2, to.y);
        mouseRelease(tv, to.x + 2, to.y);
        verify(sameDay(task(id).dueAt, due), "nothing changed");
    }

    function test_timeline_schedule_only_row_moves_when_not_a_deadline() {
        const id = "RSV-TL3";
        tc._made.push(id);
        const t = AppController.today;
        const at = new Date(t.getFullYear(), t.getMonth(), t.getDate() + 40, 15, 30);
        seed(id, { dueAt: null, scheduledAt: at, scheduledHasTime: true });
        const tv = makeTimeline();
        tv.cursorTaskId = id;
        verify(tv.moveKeyTaskByDays(-39), "the key moves it");
        const now = task(id);
        verify(sameMinute(now.scheduledAt, new Date(t.getFullYear(), t.getMonth(), t.getDate() + 1, 15, 30)), "a schedule-only row moves its schedule, clock kept");
        verify(!now.dueAt || isNaN(new Date(now.dueAt).getTime()), "no deadline appears");
        AppController.undo();
        verify(sameMinute(task(id).scheduledAt, at));
    }

    // ── Week ─────────────────────────────────────────────────────────
    function makeWeek() {
        AppController.selectedDate = tc.wed;
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent; railWanted: false }');
        wait(50);
        const scroll = findChild(wv, "week-hour-scroll");
        tryVerify(function () { return scroll.contentItem && scroll.contentItem.height > 0; }, 2000);
        wait(100);
        scroll.contentItem.contentY = 8 * wv.hourH;   // 08:00 at the top
        wait(20);
        return wv;
    }
    function dayIndexOf(wv, d) {
        for (let i = 0; i < wv.days.length; i++) if (sameDay(wv.days[i].date, d)) return i;
        return -1;
    }

    function test_week_task_block_moves_to_another_day_and_hour() {
        const id = "RSV-WK1";
        tc._made.push(id);
        seed(id, { scheduledAt: day(2031, 3, 12, 10, 0), scheduledHasTime: true, estimateMinutes: 60 });
        const wv = makeWeek();
        const block = findChild(wv, "week-taskblock-" + id);
        verify(block, "the block is drawn");
        const move = findChild(block, "week-taskblock-move");
        const c = center(move);
        const from = move.mapToItem(wv, c.x, c.y);
        const dayW = findChild(wv, "wvHeadCol").width;
        dragTo(wv, move, { x: from.x + dayW, y: from.y + 2 * wv.hourH }, false);
        const hint = findChild(wv, "reschedule-hint-text");
        verify(hint.visible && hint.text.indexOf(I18n.t("drag.field.scheduled")) === 0, "the hint says when: " + hint.text);
        mouseRelease(wv, from.x + dayW, from.y + 2 * wv.hourH);

        const next = wv.days[dayIndexOf(wv, day(2031, 3, 12)) + 1].date;
        verify(sameMinute(task(id).scheduledAt, new Date(next.getFullYear(), next.getMonth(), next.getDate(), 12, 0)),
               "planned for the next day at 12:00, got " + task(id).scheduledAt);
        AppController.undo();
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 12, 10, 0)), "undo restores");
    }

    function test_week_task_block_esc_cancels() {
        const id = "RSV-WK2";
        tc._made.push(id);
        seed(id, { scheduledAt: day(2031, 3, 12, 10, 0), scheduledHasTime: true, estimateMinutes: 60 });
        const wv = makeWeek();
        const block = findChild(wv, "week-taskblock-" + id);
        const move = findChild(block, "week-taskblock-move");
        const c = center(move);
        const from = move.mapToItem(wv, c.x, c.y);
        dragTo(wv, move, { x: from.x, y: from.y + 3 * wv.hourH }, false);
        verify(block.dragDy !== 0, "the block follows the pointer");
        keyClick(Qt.Key_Escape);
        compare(block.dragDy, 0, "Esc puts it back");
        mouseMove(wv, from.x, from.y + 4 * wv.hourH);
        mouseRelease(wv, from.x, from.y + 4 * wv.hourH);
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 12, 10, 0)), "nothing changed");
    }

    function test_week_task_block_stretch_sets_the_estimate() {
        const id = "RSV-WK3";
        tc._made.push(id);
        seed(id, { scheduledAt: day(2031, 3, 12, 10, 0), scheduledHasTime: true, estimateMinutes: 60 });
        const wv = makeWeek();
        const block = findChild(wv, "week-taskblock-" + id);
        const bottom = findChild(block, "week-taskblock-bottom");
        const c = center(bottom);
        const from = bottom.mapToItem(wv, c.x, c.y);
        dragTo(wv, bottom, { x: from.x, y: from.y + wv.hourH });
        compare(task(id).estimateMinutes, 120);
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 12, 10, 0)), "the start stays");
        AppController.undo();
        compare(task(id).estimateMinutes, 60);
    }

    function test_week_chip_moves_to_another_day() {
        const id = "RSV-WK4";
        tc._made.push(id);
        seed(id, { scheduledAt: day(2031, 3, 12), scheduledHasTime: false });
        const wv = makeWeek();
        const chip = findChild(wv, "week-due-" + id);
        verify(chip, "the chip is drawn");
        const c = center(chip);
        const from = chip.mapToItem(wv, c.x, c.y);
        const dayW = findChild(wv, "wvHeadCol").width;
        dragTo(wv, chip, { x: from.x + dayW, y: from.y });
        const next = wv.days[dayIndexOf(wv, day(2031, 3, 12)) + 1].date;
        verify(sameMinute(task(id).scheduledAt, new Date(next.getFullYear(), next.getMonth(), next.getDate())), "the next day, no time");
        verify(!task(id).scheduledHasTime);
        verify(AppController.undoEntry(AppController.undoSerialForToast()));
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 12)));
    }

    function test_week_chip_esc_cancels_and_key_moves() {
        const id = "RSV-WK5";
        tc._made.push(id);
        seed(id, { scheduledAt: day(2031, 3, 12), scheduledHasTime: false });
        const wv = makeWeek();
        const chip = findChild(wv, "week-due-" + id);
        const c = center(chip);
        const from = chip.mapToItem(wv, c.x, c.y);
        const dayW = findChild(wv, "wvHeadCol").width;
        dragTo(wv, chip, { x: from.x + dayW, y: from.y }, false);
        verify(wv.chipDrag !== null);
        keyClick(Qt.Key_Escape);
        verify(wv.chipDrag === null);
        mouseRelease(wv, from.x + dayW, from.y);
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 12)), "Esc: nothing changed");

        // The key equivalent: a week later.
        wv.keyTaskId = id;
        wv.keyTaskDay = day(2031, 3, 12);
        verify(wv.moveKeyTaskByDays(7));
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 19)));
    }

    // ── Month ────────────────────────────────────────────────────────
    function makeMonth() {
        AppController.selectedDate = tc.wed;
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        wait(50);
        return mv;
    }
    function cellOf(mv, d) {
        for (let i = 0; i < mv.cells.length; i++)
            if (sameDay(mv.cells[i].date, d)) return findChild(mv, "month-cell-" + i);
        return null;
    }

    function test_month_drop_keeps_the_time_and_undo_restores() {
        const id = "RSV-MO1";
        tc._made.push(id);
        seed(id, { scheduledAt: day(2031, 3, 12, 9, 30), scheduledHasTime: true });
        const mv = makeMonth();
        const chip = findChild(mv, "month-task-" + id);
        verify(chip, "the chip is drawn");
        const target = cellOf(mv, day(2031, 3, 20));
        const to = target.mapToItem(mv, target.width / 2, target.height - 4);
        dragTo(mv, chip, to, false);
        const hint = findChild(mv, "reschedule-hint-text");
        verify(hint.visible && hint.text.indexOf(I18n.t("drag.field.scheduled")) === 0, "the hint says when: " + hint.text);
        mouseRelease(mv, to.x, to.y);
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 20, 9, 30)), "the 20th, 09:30 kept");
        verify(AppController.undoEntry(AppController.undoSerialForToast()));
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 12, 9, 30)));
    }

    function test_month_esc_cancels() {
        const id = "RSV-MO2";
        tc._made.push(id);
        seed(id, { scheduledAt: day(2031, 3, 12), scheduledHasTime: false });
        const mv = makeMonth();
        const chip = findChild(mv, "month-task-" + id);
        const target = cellOf(mv, day(2031, 3, 20));
        const to = target.mapToItem(mv, target.width / 2, target.height - 4);
        dragTo(mv, chip, to, false);
        verify(mv.drag !== null);
        keyClick(Qt.Key_Escape);
        verify(mv.drag === null);
        mouseRelease(mv, to.x, to.y);
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 12)));
    }

    function test_month_a_deadline_chip_plans_the_day_and_leaves_the_deadline() {
        const id = "RSV-MO3";
        tc._made.push(id);
        seed(id, { dueAt: day(2031, 3, 12), dueHasTime: false, scheduledAt: null });
        const mv = makeMonth();
        mv.keyTaskId = id;
        mv.keyTaskDay = day(2031, 3, 12);
        verify(mv.moveKeyTaskByDays(1));
        verify(sameMinute(task(id).scheduledAt, day(2031, 3, 13)), "planned the day after the one it was shown on");
        verify(sameMinute(task(id).dueAt, day(2031, 3, 12)), "the deadline stays");
    }
}
