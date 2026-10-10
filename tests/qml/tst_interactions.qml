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
        // A meeting only when asked for (APP-266).
        findChild(qc, "qc-meeting").checked = true;
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
    function _capture(text, meeting) {
        const qc = make('import TodoCpp; QuickCapturePopup {}');
        let got = null;
        qc.captured.connect(function (title, body, taskId) { got = {title: title, body: body, taskId: taskId}; });
        findChild(qc, "qc-input").text = text;
        findChild(qc, "qc-meeting").checked = !!meeting;
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

    // APP-245: "when" and the deadline are two dates; one date is not both.
    function test_quickcapture_when_and_due_are_two_dates() {
        const got = tc._capture("two-dates probe tomorrow, due in 3 days");
        const t = AppController.taskById(got.taskId);
        compare(t.title, "two-dates probe");
        const today = new Date(); today.setHours(0, 0, 0, 0);
        const days = (d) => Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - today) / 86400000);
        compare(days(t.scheduledAt), 1, "when");
        compare(days(t.dueAt), 3, "due");
        verify(got.body.indexOf(I18n.t("quick.done.when").arg("").trim()) >= 0, got.body);
        verify(got.body.indexOf(I18n.t("quick.done.due").arg("").trim()) >= 0, got.body);
        AppController.deleteTask(got.taskId);

        const only = tc._capture("one-date probe tomorrow");
        const o = AppController.taskById(only.taskId);
        verify(!o.dueAt || isNaN(o.dueAt.getTime()), "a date with no deadline word set a deadline");
        AppController.deleteTask(only.taskId);
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
        const got = tc._capture("созвон с заказчиком завтра в 16:00-16:45", true);
        compare(got.title, I18n.t("quick.done.meeting.none"));
        verify(got.body.indexOf("16:00–16:45") >= 0, got.body);
        const ev = tc._eventOf(got.taskId);
        verify(ev !== null, "no event booked");
        compare(ev.type, "none", "a one-off call is untyped");
        AppController.deleteEvent(ev.id);
        AppController.deleteTask(got.taskId);

        const d = tc._capture("дейли завтра в 10:00", true);
        compare(d.title, I18n.t("quick.done.meeting.standup"));
        const dev = tc._eventOf(d.taskId);
        compare(dev.type, "standup");
        AppController.deleteEvent(dev.id);
        AppController.deleteTask(d.taskId);
    }

    // APP-266: the words "созвон"/"встреча" alone book nothing; a meeting is
    // only made with the box ticked.
    function test_quickcapture_meeting_words_book_nothing_by_themselves() {
        const got = tc._capture("встреча с дизайнером завтра в 11:00");
        compare(tc._eventOf(got.taskId), null);
        compare(got.title, I18n.t("quick.done.task").arg(tc._todoName()));
        AppController.deleteTask(got.taskId);
    }

    // × on a chip gives the words back to the title (APP-266).
    function test_quickcapture_chip_x_keeps_the_words() {
        const qc = make('import TodoCpp; QuickCapturePopup {}');
        qc.open();
        tryVerify(() => qc.opened);
        const input = findChild(qc, "qc-input");
        input.text = "Обзор пятницы";
        qc._refreshPreview();
        const when = findChild(qc, "qc-when");
        verify(when.visible, "no date chip");
        compare(qc._title, "Обзор");
        qc.rejectSpan("when");
        verify(!when.visible);
        compare(qc._title, "Обзор пятницы");
        let id = "";
        qc.captured.connect(function (t, b, taskId) { id = taskId; });
        qc._submit();
        const t = AppController.taskById(id);
        compare(t.title, "Обзор пятницы");
        verify(!t.scheduledAt || isNaN(t.scheduledAt.getTime()), "the rejected date was set anyway");
        AppController.deleteTask(id);
    }

    // Several pasted lines: one question, then "N tasks" makes N.
    function test_quickcapture_pasted_lines_ask_once() {
        const qc = make('import TodoCpp; QuickCapturePopup {}');
        qc.open();
        tryVerify(() => qc.opened);
        const input = findChild(qc, "qc-input");
        const before = AppController.tasks.rowCount();
        input.text = "paste-probe one\npaste-probe two\npaste-probe three";
        qc._submit();
        verify(findChild(qc, "qc-lines-ask").visible, "no question for a pasted block");
        compare(AppController.tasks.rowCount(), before, "it saved before asking");
        mouseClick(findChild(qc, "qc-lines-many"));
        compare(AppController.tasks.rowCount(), before + 3);
        const m = AppController.tasks;
        for (let i = m.rowCount() - 1; i >= 0; i--) {
            const id = String(m.data(m.index(i, 0), Qt.UserRole + 1));
            if (AppController.taskById(id).title.indexOf("paste-probe") === 0) AppController.deleteTask(id);
        }
    }

    // Empty input and Enter: nothing, and no complaint.
    function test_quickcapture_empty_enter_is_nothing() {
        const qc = make('import TodoCpp; QuickCapturePopup {}');
        const before = AppController.tasks.rowCount();
        findChild(qc, "qc-input").text = "   ";
        qc._submit();
        compare(AppController.tasks.rowCount(), before);
        compare(qc._hint, "");
    }

    // The same text makes the same task from every input (APP-266): the
    // quick input and the welcome tour's first task.
    function test_every_input_reads_the_same() {
        const text = "same-input probe tomorrow at 15:00 p1 #ops";
        const a = AppController.quickTaskDraft(text, new Date());
        const got = tc._capture(text);
        const t = AppController.taskById(got.taskId);
        compare(t.title, a.title);
        compare(t.priority, "P1");
        compare(t.labels.length, 1);
        compare(t.scheduledAt.getTime(), a.scheduledAt.getTime());
        verify(t.scheduledHasTime);
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
