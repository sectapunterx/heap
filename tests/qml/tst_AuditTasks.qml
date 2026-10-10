// Regressions from the 2026-09-30 audit, tasks area: the board, the card,
// the task editor, quick capture and the timeline. Each case names the
// finding it pins.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "AuditTasks"
    when: windowShown
    visible: true
    width: 1400
    height: 900

    Item { id: host; anchors.fill: parent }

    readonly property string probe: "auditprobe"
    property var seeded: []

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function addTask(status, fields) {
        const d = AppController.newTaskDraft(status);
        d._isNew = true;
        d.title = tc.probe + " " + (fields && fields.title ? fields.title : "card");
        for (const k in (fields || {})) if (k !== "title") d[k] = fields[k];
        verify(AppController.saveTask(d), "seed save");
        tc.seeded.push(d.id);
        return d.id;
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
    }

    function statusIds() {
        const out = [];
        for (let i = 0; i < AppController.statuses.length; i++) out.push(AppController.statuses[i].id);
        return out;
    }

    function makeBoard() {
        const b = make('import TodoCpp; KanbanBoard { anchors.fill: parent }');
        b.searchText = tc.probe;
        wait(0);
        return b;
    }

    // ── TASKS-19: a column edit does not rebuild every column ──
    function test_renaming_a_column_keeps_the_other_columns() {
        const b = makeBoard();
        const rep = findChild(b, "board-hscroll");
        verify(rep !== null);
        const first = b._visibleByColumn();
        verify(first.length >= 2);
        // The delegate object of the second column, before and after a rename
        // of the first.
        const colBefore = findColumn(b, first[1].statusId);
        const oldName = AppController.statuses[0].name;
        AppController.renameStatus(AppController.statuses[0].id, oldName + " x");
        wait(0);
        const colAfter = findColumn(b, first[1].statusId);
        verify(colBefore === colAfter, "the untouched column was rebuilt");
        AppController.renameStatus(AppController.statuses[0].id, oldName);
    }

    function findColumn(board, statusId) {
        const cols = [];
        collect(board, cols);
        for (let i = 0; i < cols.length; i++) if (cols[i].statusId === statusId) return cols[i];
        return null;
    }
    function collect(item, out) {
        if (!item) return;
        if (item.statusId !== undefined && item.taskFilter !== undefined) out.push(item);
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) collect(kids[i], out);
    }

    // ── TASKS-8: a filter hiding a column's cards does not skip the confirm ──
    function test_deleting_a_filtered_column_still_asks() {
        AppController.addStatus("Audit QA", "");
        const qa = statusIds().filter(id => id.indexOf("audit-qa") === 0)[0];
        verify(qa !== undefined);
        addTask(qa, { title: "hidden" });
        const b = makeBoard();
        b.searchText = "nothing-matches-this";
        wait(0);
        b.requestDeleteColumn(qa, "Audit QA");
        const dlg = findChild(b, "confirm-delete-column");
        verify(dlg !== null);
        verify(dlg.opened, "the column holds a card; the confirm must show");
        dlg.close();
        cleanup();
        AppController.deleteStatus(qa);
        AppController.clearPendingUndo();
    }

    // ── TASKS-32: collapsible columns, and the cursor walks past a folded one ──
    function test_a_folded_column_is_skipped_by_the_cursor() {
        const ids = statusIds();
        addTask(ids[0], { title: "a" });
        addTask(ids[1], { title: "b" });
        const b = makeBoard();
        b.toggleCollapsed(ids[0]);
        wait(0);
        verify(b.collapsed[ids[0]] === true);
        compare(b._visibleByColumn()[0].ids.length, 0);
        b.toggleCollapsed(ids[0]);
        verify(!b.collapsed[ids[0]]);
    }

    // ── UX-26 / TASKS-32: the card menu opens from the keyboard ──
    function test_the_cursor_card_menu_opens_from_the_keyboard() {
        const id = addTask(statusIds()[0], { title: "menu" });
        const b = makeBoard();
        b.cursorTaskId = id;
        b.cursorVisible = true;
        b.openCursorMenu();
        verify(b.cardMenuOpen, "the board must know a card menu is up");
        const menu = findChild(b._cardItem(id), "tc-menu");
        verify(menu !== null);
        tryVerify(() => menu.opened);
        verify(menuHas(menu, "tc-menu-archive"));
        verify(menuHas(menu, "tc-menu-status"));
        verify(menuHas(menu, "tc-menu-priority"));
        menu.close();
        tryVerify(() => !b.cardMenuOpen);
    }

    function menuHas(menu, name) {
        for (let i = 0; i < menu.count; i++) if (menu.itemAt(i) && menu.itemAt(i).objectName === name) return true;
        return false;
    }

    function test_archive_key_archives_the_cursor_card() {
        const id = addTask(statusIds()[0], { title: "arch" });
        const b = makeBoard();
        b.cursorTaskId = id;
        b.cursorVisible = true;
        b.archiveCursor();
        verify(AppController.taskById(id).archived === true);
    }

    // ── PLAT-24, TASKS-12, TASKS-33: what a card says ──
    function test_a_done_overdue_card_shows_no_overdue_badge() {
        const past = new Date(); past.setDate(past.getDate() - 5);
        const id = addTask("done", { title: "done late", dueAt: past, scheduledAt: past });
        const card = make('import TodoCpp; TaskCard { width: 260 }');
        card.task = AppController.taskById(id);
        card.task.deadline = past;
        const due = findChild(card, "tc-due");
        verify(!due.visible, "a finished task is not overdue");
    }

    function test_a_scheduled_only_task_shows_when() {
        const when = new Date(); when.setDate(when.getDate() + 2); when.setHours(14, 0, 0, 0);
        const id = addTask("todo", { title: "sched", scheduledAt: when, scheduledHasTime: true });
        const card = make('import TodoCpp; TaskCard { width: 260 }');
        card.task = AppController.taskById(id);
        const s = findChild(card, "tc-scheduled");
        verify(s.visible, "a task with only a schedule looked undated");
        verify(s.text.indexOf("14:00") >= 0, s.text);
    }

    // ── TASKS-9 / TASKS-28: the editor asks before throwing edits away ──
    function test_escape_on_an_edited_task_asks_first() {
        const id = addTask("todo", { title: "dirty" });
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(Object.assign({}, AppController.taskById(id)));
        tryVerify(() => te.opened);
        verify(!te.isDirty());
        // Change the title through the field the user types into.
        const fields = [];
        collectFields(te.contentItem, fields);
        verify(fields.length > 0);
        fields[0].text = tc.probe + " edited";
        verify(te.isDirty());

        te.requestClose();
        const prompt = findChild(te, "te-discard-prompt");
        verify(prompt !== null);
        tryVerify(() => prompt.opened);
        verify(te.opened, "the editor stays open behind the prompt");

        // Keep editing, then discard.
        const keep = findChild(te, "te-dirty-keep");
        keep.clicked();
        tryVerify(() => !prompt.opened);
        verify(te.opened);
        te.requestClose();
        tryVerify(() => prompt.opened);
        findChild(te, "te-dirty-discard").clicked();
        tryVerify(() => !te.opened);
        compare(AppController.taskById(id).title, tc.probe + " dirty", "discard saved nothing");
    }

    // ── TASKS-18 / SHELL-29 (audit 2026-09-30): opening another task from a
    // notification and quitting wait for the save/discard answer ──
    function test_the_next_step_waits_for_the_prompt() {
        const id = addTask("todo", { title: "settle" });
        const te = make('import TodoCpp; TaskEditor { }');
        let ran = 0;
        // Clean: at once.
        te.showFor(Object.assign({}, AppController.taskById(id)));
        tryVerify(() => te.opened);
        te.settleThen(() => ran++);
        compare(ran, 1, "a clean editor does not ask");

        const fields = [];
        collectFields(te.contentItem, fields);
        fields[0].text = tc.probe + " settled";
        const prompt = findChild(te, "te-discard-prompt");
        te.settleThen(() => ran++);
        tryVerify(() => prompt.opened);
        compare(ran, 1, "nothing runs before the answer");

        // Keep editing drops the step.
        findChild(te, "te-dirty-keep").clicked();
        tryVerify(() => !prompt.opened);
        compare(ran, 1);
        verify(te.opened);

        // Save: the edit is kept, then the step runs.
        te.settleThen(() => ran++);
        tryVerify(() => prompt.opened);
        findChild(te, "te-dirty-save").clicked();
        tryVerify(() => !te.opened);
        compare(ran, 2);
        compare(AppController.taskById(id).title, tc.probe + " settled");

        // Discard: nothing saved, then the step runs.
        te.showFor(Object.assign({}, AppController.taskById(id)));
        tryVerify(() => te.opened);
        const again = [];
        collectFields(te.contentItem, again);
        again[0].text = tc.probe + " thrown";
        te.settleThen(() => ran++);
        tryVerify(() => prompt.opened);
        findChild(te, "te-dirty-discard").clicked();
        tryVerify(() => !te.opened);
        compare(ran, 3);
        compare(AppController.taskById(id).title, tc.probe + " settled");
    }

    // The same, from the keyboard: Esc in a field asks, Esc keeps editing,
    // Enter saves.
    function test_the_prompt_is_keyboard_first() {
        const id = addTask("todo", { title: "keys" });
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(Object.assign({}, AppController.taskById(id)));
        tryVerify(() => te.opened);
        const fields = [];
        collectFields(te.contentItem, fields);
        fields[0].forceActiveFocus();
        fields[0].text = tc.probe + " keyed";
        keyClick(Qt.Key_Escape);
        const prompt = findChild(te, "te-discard-prompt");
        tryVerify(() => prompt.opened);
        // IDIOT-DOC-19: typing on — a word starting with d, then s — decides
        // nothing, and a key in the burst the prompt opened in is ignored.
        keyClick(Qt.Key_Escape);
        verify(prompt.opened, "a key in the opening burst answered the prompt");
        wait(450);
        keyClick(Qt.Key_D); keyClick(Qt.Key_E); keyClick(Qt.Key_S);
        verify(prompt.opened && te.opened, "a bare letter answered the prompt");
        keyClick(Qt.Key_Escape);
        tryVerify(() => !prompt.opened);
        verify(te.opened, "Esc in the prompt keeps editing");
        fields[0].forceActiveFocus();
        keyClick(Qt.Key_Escape);
        tryVerify(() => prompt.opened);
        wait(450);
        keyClick(Qt.Key_Return);
        tryVerify(() => !te.opened);
        compare(AppController.taskById(id).title, tc.probe + " keyed", "Enter in the prompt saves");
    }

    function collectFields(item, out) {
        if (!item) return;
        if (item.placeholderText !== undefined && item.text !== undefined && item.selectAll !== undefined
            && item.font && item.font.pixelSize === Theme.fsLg) out.push(item);
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) collectFields(kids[i], out);
        if (item.contentItem && item.contentItem !== item) collectFields(item.contentItem, out);
    }

    // UX-25: the status box is never narrower than its longest column name.
    function test_the_status_box_does_not_truncate() {
        const id = addTask("prog", { title: "status width" });
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(Object.assign({}, AppController.taskById(id)));
        tryVerify(() => te.opened);
        const box = findChild(te, "te-status");
        verify(box !== null);
        wait(50);
        verify(!box.contentItem.truncated, "status box shows \"" + box.displayText + "\" truncated at " + box.width);
        te.close();
    }

    function test_a_clean_editor_closes_on_request() {
        const id = addTask("todo", { title: "clean" });
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(Object.assign({}, AppController.taskById(id)));
        tryVerify(() => te.opened);
        te.requestClose();
        tryVerify(() => !te.opened);
    }

    function test_an_unreadable_date_is_refused_with_a_reason() {
        const te = make('import TodoCpp; TaskEditor { }');
        const d = AppController.newTaskDraft("todo");
        d.title = tc.probe + " bad date";
        te.showFor(d);
        tryVerify(() => te.opened);
        const fields = [];
        collectAll(te.contentItem, fields);
        const deadline = fields.filter(f => f.placeholderText === I18n.t("editor.ph.deadline"))[0];
        verify(deadline !== undefined);
        deadline.text = "blorp quux";
        verify(!te._commit());
        verify(te._error.length > 0);
        compare(AppController.taskById(d.id).id, undefined, "nothing was saved");
        te.close();
    }

    function collectAll(item, out) {
        if (!item) return;
        if (item.placeholderText !== undefined) out.push(item);
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) collectAll(kids[i], out);
        if (item.contentItem && item.contentItem !== item) collectAll(item.contentItem, out);
    }

    // ── TASKS-13: capture keeps #labels and p1, Enter does not rewrite #word ──
    function test_quick_capture_reads_priority_and_labels() {
        const qc = make('import TodoCpp; QuickCapturePopup { }');
        qc.open();
        tryVerify(() => qc.opened);
        const input = findChild(qc, "qc-input");
        input.forceActiveFocus();
        input.text = tc.probe + " fix login p1 #backend";
        input.cursorPosition = input.text.length;
        wait(120);
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        tryVerify(() => !qc.opened);
        // The newest task with the probe title.
        const m = AppController.tasks;
        let found = null;
        for (let i = 0; i < m.rowCount(); i++) {
            const t = AppController.taskById(String(m.data(m.index(i, 0), Qt.UserRole + 1)));
            if (t.title === tc.probe + " fix login") found = t;
        }
        verify(found !== null, "#backend must not be rewritten to a ticket id");
        tc.seeded.push(found.id);
        compare(found.priority, "P1");
        compare(found.labels.length, 1);
        compare(found.labels[0].id, "backend");
    }

    function test_a_bare_date_says_why_nothing_happened() {
        const qc = make('import TodoCpp; QuickCapturePopup { }');
        qc.open();
        tryVerify(() => qc.opened);
        const input = findChild(qc, "qc-input");
        input.text = "tomorrow";
        qc._submit();
        verify(qc.opened);
        verify(qc._hint.length > 0, "a date alone must explain itself");
        qc.close();
    }

    function test_ctrl_shift_enter_keeps_capture_open() {
        const qc = make('import TodoCpp; QuickCapturePopup { }');
        qc.open();
        tryVerify(() => qc.opened);
        const input = findChild(qc, "qc-input");
        input.forceActiveFocus();
        input.text = tc.probe + " first of several";
        keyClick(Qt.Key_Return, Qt.ControlModifier | Qt.ShiftModifier);
        verify(qc.opened, "Ctrl+Shift+Enter adds and stays open");
        compare(input.text, "");
        const m = AppController.tasks;
        for (let i = 0; i < m.rowCount(); i++) {
            const t = AppController.taskById(String(m.data(m.index(i, 0), Qt.UserRole + 1)));
            if (t.title === tc.probe + " first of several") tc.seeded.push(t.id);
        }
        compare(tc.seeded.length, 1);
        qc.close();
    }

    // ── APP-209: Enter and Shift+Enter are new lines, Ctrl+Enter saves ──
    // APP-266: Enter creates, Shift+Enter starts a new line; the lines after
    // the first are the description.
    function test_enter_saves_and_shift_enter_is_a_new_line() {
        const qc = make('import TodoCpp; QuickCapturePopup { }');
        qc.open();
        tryVerify(() => qc.opened);
        const input = findChild(qc, "qc-input");
        input.forceActiveFocus();
        input.text = tc.probe + " multi line";
        input.cursorPosition = input.text.length;
        keyClick(Qt.Key_Return, Qt.ShiftModifier);
        verify(qc.opened, "Shift+Enter saved instead of starting a new line");
        keyClick(Qt.Key_S);
        keyClick(Qt.Key_Return, Qt.ShiftModifier);
        keyClick(Qt.Key_T);
        compare(input.text, tc.probe + " multi line\ns\nt");
        verify(!findChild(qc, "qc-lines-ask").visible, "typed lines are not a paste");
        keyClick(Qt.Key_Return);
        tryVerify(() => !qc.opened);
        const m = AppController.tasks;
        let found = null;
        for (let i = 0; i < m.rowCount(); i++) {
            const t = AppController.taskById(String(m.data(m.index(i, 0), Qt.UserRole + 1)));
            if (t.title === tc.probe + " multi line") found = t;
        }
        verify(found !== null, "Enter did not save the first line as the title");
        tc.seeded.push(found.id);
        compare(found.desc, "s\nt");
    }

    function test_esc_still_closes_capture() {
        const qc = make('import TodoCpp; QuickCapturePopup { }');
        qc.open();
        tryVerify(() => qc.opened);
        const input = findChild(qc, "qc-input");
        input.forceActiveFocus();
        input.text = "draft";
        keyClick(Qt.Key_Escape);
        tryVerify(() => !qc.opened);
    }

}
