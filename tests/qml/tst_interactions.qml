// Click-driven interaction tests for real UI components (HEAP-49).
//
// Uses the component harness (heap_core) to instantiate FilterBar / SideRail
// against a live AppController and drive them with actual mouse events, so the
// full path button → MouseArea → signal / AppController state is exercised —
// not just the signal contract.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Interactions"
    when: windowShown
    visible: true
    width: 500
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // FilterBar: clicking a priority pill emits togglePriority(id).
    function test_filterbar_click_priority() {
        const fb = make('import TodoCpp; FilterBar { anchors.fill: parent }');
        let got = "";
        fb.togglePriority.connect(function(p) { got = p; });
        const pill = findChild(fb, "pri-P2");
        verify(pill !== null, "pri-P2 pill not found");
        mouseClick(pill);
        compare(got, "P2");
    }

    // FilterBar: clicking the Archived chip emits toggleArchived.
    function test_filterbar_click_archived() {
        const fb = make('import TodoCpp; FilterBar { anchors.fill: parent }');
        let n = 0;
        fb.toggleArchived.connect(function() { n++; });
        const chip = findChild(fb, "archived-toggle");
        verify(chip !== null, "archived-toggle not found");
        mouseClick(chip);
        compare(n, 1);
    }



    // DayCalendar: a task scheduled at a clock time renders a block in the grid,
    // and clicking it opens the task. The block shipped as a bare Rectangle, so
    // the click was swallowed and nothing happened (HEAP-115 regression). The
    // second compare pins the other half: the click must not reach the
    // create-an-event MouseArea layered underneath.
    //
    // Event rectangles are stacked above task blocks and would eat the click, so
    // the probe day is emptied of events first. Test-mode AppDataLocation is not
    // wiped between runs, so a leftover event on that day is a real hazard.
    function test_daycalendar_click_task_block() {
        const day = new Date();
        day.setDate(day.getDate() + 400);
        day.setHours(0, 0, 0, 0);

        const evs = AppController.events;
        for (let i = evs.rowCount() - 1; i >= 0; i--) {
            const idx = evs.index(i, 0);
            const d = evs.data(idx, Qt.UserRole + 7);   // date role
            if (d && d.getFullYear
                && d.getFullYear() === day.getFullYear()
                && d.getMonth() === day.getMonth()
                && d.getDate() === day.getDate())
                AppController.deleteEvent(String(evs.data(idx, Qt.UserRole + 1)));
        }

        const at = new Date(day);
        at.setHours(AppController.workdayStart, 0, 0, 0);

        const draft = AppController.newTaskDraft("todo");
        draft.title = "day-block click probe";
        draft.scheduledAt = at;
        draft.dueAt = at;
        draft.hasTime = true;
        AppController.saveTask(draft);

        AppController.selectedDate = day;
        const dc = make('import TodoCpp; DayCalendar { anchors.fill: parent }');
        // The grid spans the whole day now, so the working hours are well
        // below the top of it. The view scrolls itself to the relevant hour on
        // a callLater; without waiting for that the block is under the fold
        // and the click lands on whatever is on screen instead.
        wait(0);
        const block = findChild(dc, "taskblock-" + draft.id);
        verify(block !== null, "scheduled task did not render a day-grid block");

        let got = "";
        dc.taskClicked.connect(function(tid) { got = tid; });
        const eventsBefore = evs.rowCount();

        mouseClick(block);

        compare(got, draft.id);
        compare(evs.rowCount(), eventsBefore);
    }

    // DayCalendar: a task scheduled at a clock time draws its own block, but a
    // "sync" capture also creates a meeting event linked to that task. The event
    // stands in for the task, so the task's own block must be suppressed on that
    // day — otherwise "синк с @hb" renders twice (HEAP-115 regression).
    function test_daycalendar_hides_task_block_with_linked_event() {
        const day = new Date();
        day.setDate(day.getDate() + 402);
        day.setHours(0, 0, 0, 0);

        const evs = AppController.events;
        for (let i = evs.rowCount() - 1; i >= 0; i--) {
            const idx = evs.index(i, 0);
            const ed = evs.data(idx, Qt.UserRole + 7);
            if (ed && ed.getFullYear
                && ed.getFullYear() === day.getFullYear()
                && ed.getMonth() === day.getMonth()
                && ed.getDate() === day.getDate())
                AppController.deleteEvent(String(evs.data(idx, Qt.UserRole + 1)));
        }

        const at = new Date(day);
        at.setHours(AppController.workdayStart + 1, 0, 0, 0);

        const draft = AppController.newTaskDraft("todo");
        draft.title = "синк dedup probe";
        draft.scheduledAt = at;
        draft.dueAt = at;
        draft.hasTime = true;
        AppController.saveTask(draft);

        AppController.selectedDate = day;
        const dc = make('import TodoCpp; DayCalendar { anchors.fill: parent }');
        const block = findChild(dc, "taskblock-" + draft.id);

        // Control: with no linked event, the block is visible.
        verify(block !== null, "scheduled task did not render a day-grid block");
        verify(block.visible, "task block should be visible before a linked event exists");

        // Add the meeting event that links back to the task.
        const ev = AppController.newEventDraft(AppController.workdayStart + 1, day);
        ev.type = "sync";
        ev.title = "синк dedup probe";
        ev.taskId = draft.id;
        ev.date = day;
        AppController.saveEvent(ev);
        wait(50);

        // The linked event now stands in for the task → its block is hidden.
        verify(!block.visible, "task block must be hidden once a linked meeting event exists");
    }

    // QuickCapture "sync": one task + one linked meeting event, and the "// …"
    // tail lands on BOTH the task description and the event's context.
    // Reproduces three reported bugs:
    //   (a) the day view showed both the meeting event AND the task's own block
    //       (the event's taskId must match the task id so the block is hidden);
    //   (b) the "// comment" was dropped instead of saved to desc;
    //   (c) the comment was saved only to the task, not the sync event context.
    function test_quickcapture_sync_links_event_and_saves_comment() {
        const tasks = AppController.tasks;
        const evs   = AppController.events;
        const tasksBefore = tasks.rowCount();
        const evsBefore   = evs.rowCount();

        const qc = make('import TodoCpp; QuickCapturePopup {}');
        const input = findChild(qc, "qc-input");
        verify(input !== null, "qc-input not found");

        // No explicit _refreshPreview(): _submit() must recompute from the
        // current text itself. Before that fix, the debounced _meta/_preview are
        // still at their defaults here, so submit dropped the comment (and could
        // create an unlinked event / no task at all).
        input.text = "синк с @hb в 16:00 // обсудить релиз";
        qc._submit();

        compare(tasks.rowCount(), tasksBefore + 1, "expected exactly one new task");
        compare(evs.rowCount(),   evsBefore + 1,   "expected exactly one meeting event");

        const tIdx = tasks.index(tasks.rowCount() - 1, 0);
        const taskId = String(tasks.data(tIdx, Qt.UserRole + 1));  // IdRole
        const desc   = String(tasks.data(tIdx, Qt.UserRole + 3));  // DescRole

        compare(desc, "обсудить релиз", "the // comment was not saved to the task desc");

        const eIdx = evs.index(evs.rowCount() - 1, 0);
        const evTaskId  = String(evs.data(eIdx, Qt.UserRole + 8));   // TaskIdRole
        const evContext = String(evs.data(eIdx, Qt.UserRole + 10));  // ContextRole
        compare(evTaskId, taskId, "meeting event not linked to task → day block duplicates it");
        compare(evContext, "обсудить релиз", "the // comment must also ride onto the sync event context");
    }

    // Quick capture reports what it made, readably: the headline says what it
    // is and where it went, the body quotes the title and lists only what was
    // set. A task no longer gets a "TODO-N" placeholder id.
    function _capture(text) {
        const qc = make('import TodoCpp; QuickCapturePopup {}');
        let got = null;
        qc.captured.connect(function (title, body, taskId) { got = {title: title, body: body, taskId: taskId}; });
        findChild(qc, "qc-input").text = text;
        qc._submit();
        verify(got !== null, "captured() not emitted for " + text);
        return got;
    }
    function _todoName() {
        const sts = AppController.statuses;
        for (let i = 0; i < sts.length; ++i) if (sts[i].id === "todo") return sts[i].name;
        return "todo";
    }
    function _eventOf(taskId) {
        const evs = AppController.events;
        for (let i = 0; i < evs.rowCount(); ++i) {
            const idx = evs.index(i, 0);
            if (String(evs.data(idx, Qt.UserRole + 8)) === taskId)
                return { id: String(evs.data(idx, Qt.UserRole + 1)), type: String(evs.data(idx, Qt.UserRole + 3)) };
        }
        return null;
    }

    function test_quickcapture_reports_a_task() {
        const got = tc._capture("capture-report probe tomorrow at 15:00 p1 // with notes");
        verify(got.taskId.indexOf("TODO-") !== 0, "placeholder id: " + got.taskId);
        compare(got.title, I18n.t("quick.done.task").arg(tc._todoName()));
        const lines = got.body.split("\n");
        compare(lines[0], I18n.t("quick.quote").arg("capture-report probe"));
        verify(lines[1].indexOf(I18n.t("quick.day.tomorrow")) >= 0 && lines[1].indexOf("15:00") > 0,
               "relative day and time: " + lines[1]);
        verify(lines.indexOf(I18n.t("quick.done.priority").arg("P1")) > 0, got.body);
        compare(lines[lines.length - 1], I18n.t("quick.done.note").arg("with notes"));
        compare(AppController.taskById(got.taskId).priority, "P1");
        AppController.deleteTask(got.taskId);
    }

    function test_quickcapture_ticket_key_becomes_the_id() {
        AppController.deleteTask("QCP-4242");
        const got = tc._capture("QCP-4242 fix the capture probe");
        compare(got.taskId, "QCP-4242");
        compare(AppController.taskById("QCP-4242").title, "fix the capture probe");
        verify(got.body.indexOf(I18n.t("quick.done.ticket").arg("QCP-4242")) >= 0, got.body);
        AppController.deleteTask("QCP-4242");
    }

    function test_quickcapture_reports_a_meeting_with_its_type() {
        const got = tc._capture("созвон с заказчиком завтра в 16:00-16:45");
        compare(got.title, I18n.t("quick.done.meeting.none"));
        verify(got.body.indexOf("16:00–16:45") >= 0, got.body);
        const ev = tc._eventOf(got.taskId);
        verify(ev !== null, "no event booked");
        compare(ev.type, "none", "a one-off call is untyped");
        AppController.deleteEvent(ev.id);
        AppController.deleteTask(got.taskId);

        const d = tc._capture("дейли завтра в 10:00");
        compare(d.title, I18n.t("quick.done.meeting.standup"));
        const dev = tc._eventOf(d.taskId);
        compare(dev.type, "standup");
        AppController.deleteEvent(dev.id);
        AppController.deleteTask(d.taskId);
    }

    function test_quickcapture_untimed_meeting_says_so() {
        const got = tc._capture("встреча с дизайнером по онбордингу");
        verify(got.body.indexOf(I18n.t("quick.done.noTime")) >= 0, got.body);
        compare(tc._eventOf(got.taskId), null);
        AppController.deleteTask(got.taskId);
    }

    // The capture window hosts its own popups and hides itself once they close.
    function test_capture_window_hides_after_close() {
        const cw = make('import TodoCpp; CaptureWindow {}');
        cw.summon("task");
        verify(cw.visible, "summon must show the window");
        verify(cw.busy);
        cw.summon("note");   // switches popups, stays up
        verify(cw.visible);
        verify(cw.busy);
        const task = findChild(cw.contentItem, "capture-task");
        const note = findChild(cw.contentItem, "capture-note");
        verify(task !== null && note !== null);
        verify(!task.opened && note.opened, "a second summon switches to the other popup");
        note.close();
        tryVerify(() => !cw.visible, 1000, "window must hide once its popup closes");
        cw.destroy();
    }

    // TaskEditor: ticking "Someday" files the task under Backlog — the status
    // box flips to Backlog immediately as feedback (saveTask enforces it too).
    function test_taskeditor_someday_files_under_backlog() {
        const te = make('import TodoCpp; TaskEditor {}');
        const someday = findChild(te, "te-someday");
        const status  = findChild(te, "te-status");
        verify(someday !== null, "te-someday not found");
        verify(status !== null,  "te-status not found");

        // Backlog is a default column; find its index in the status box.
        const sts = AppController.statuses;
        let backlogIdx = -1;
        for (let i = 0; i < sts.length; ++i) if (sts[i].id === "backlog") { backlogIdx = i; break; }
        verify(backlogIdx >= 0, "expected a default backlog column");

        status.currentIndex = (backlogIdx + 1) % sts.length;  // anything but backlog
        someday.checked = true;
        compare(status.currentIndex, backlogIdx, "ticking Someday must move the status box to Backlog");
    }

}
