// Regressions from the 2026-09-30 audit, tasks area, B tier: quick capture,
// the board's keyboard moves under a sort and the timeline's row cache. Each
// case names the finding it pins.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "AuditTasksB"
    when: windowShown
    visible: true
    width: 1400
    height: 900

    Item { id: host; anchors.fill: parent }

    readonly property string probe: "auditprobeb"
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

    // The tasks whose title starts with the probe, by title.
    function probeTasks() {
        const out = {};
        const m = AppController.tasks;
        for (let i = 0; i < m.rowCount(); i++) {
            const t = AppController.taskById(String(m.data(m.index(i, 0), Qt.UserRole + 1)));
            if (String(t.title).indexOf(tc.probe) >= 0) out[t.title] = t;
        }
        return out;
    }

    function capture(text) {
        const before = probeTasks();
        const qc = make('import TodoCpp; QuickCapturePopup { }');
        qc.open();
        tryVerify(() => qc.opened);
        const input = findChild(qc, "qc-input");
        input.forceActiveFocus();
        input.text = text;
        input.cursorPosition = input.text.length;
        keyClick(Qt.Key_Return, Qt.ControlModifier);
        tryVerify(() => !qc.opened);
        const after = probeTasks();
        let made = null;
        for (const k in after) if (!before[k]) made = after[k];
        verify(made !== null, "capture made no task for: " + text);
        tc.seeded.push(made.id);
        return made;
    }

    // ── TASKS-7: a link in quick capture stays whole ──
    function test_quick_capture_keeps_a_link_whole() {
        const t = capture(tc.probe + " review https://github.com/sectapunterx/larra/pull/12");
        compare(t.title, tc.probe + " review https://github.com/sectapunterx/larra/pull/12");
        compare(t.desc, "");
        const u = capture(tc.probe + " read docs at http://example.com // later");
        compare(u.title, tc.probe + " read docs at http://example.com");
        compare(u.desc, "later");
    }

    // ── TASKS-8: a version number is not a due date ──
    function test_quick_capture_keeps_a_version_number() {
        const t = capture(tc.probe + " release 1.2.3 notes");
        compare(t.title, tc.probe + " release 1.2.3 notes");
        verify(!(t.dueAt && t.dueAt.getTime && !isNaN(t.dueAt.getTime())), "1.2.3 set a due date: " + t.dueAt);
        const u = capture(tc.probe + " read section 4.2 of the spec");
        compare(u.title, tc.probe + " read section 4.2 of the spec");
    }

    // ── TASKS-22: a ticket key another task holds stays in the title ──
    function test_a_taken_ticket_key_stays_in_the_title() {
        const holder = AppController.newTaskDraft("todo");
        holder._isNew = true;
        holder.id = "QAB-101";
        holder.title = tc.probe + " the ticket";
        verify(AppController.saveTask(holder));
        tc.seeded.push("QAB-101");
        const t = capture("QAB-101 " + tc.probe + " follow up with QA");
        verify(t.id !== "QAB-101", "the holder's id was reused");
        compare(t.title, "QAB-101 " + tc.probe + " follow up with QA");
        compare(AppController.taskById("QAB-101").title, tc.probe + " the ticket");
        // A free key still becomes the id and leaves the title.
        AppController.deleteTask("QAB-102");
        const f = capture("QAB-102 " + tc.probe + " fresh ticket");
        compare(f.id, "QAB-102");
        compare(f.title, tc.probe + " fresh ticket");
    }

    // ── TASKS-1: a keyboard move under a sort leaves the manual order alone ──
    function test_shift_k_under_a_sort_keeps_the_manual_order() {
        const k1 = addTask("todo", { title: "kb one", priority: "P1" });
        const k2 = addTask("todo", { title: "kb two", priority: "P3" });
        const k3 = addTask("todo", { title: "kb three", priority: "P0" });
        const b = make('import TodoCpp; KanbanBoard { anchors.fill: parent }');
        b.searchText = tc.probe + " kb";
        wait(0);
        const todoIds = () => b._visibleByColumn().filter(c => c.statusId === "todo")[0].ids.slice();
        const manual = todoIds();
        compare(manual, [k3, k2, k1], "new cards go on top");
        b.sortMode = "priority";
        wait(0);
        compare(todoIds(), [k3, k1, k2]);
        const notices = make('import QtTest; import TodoCpp; SignalSpy { target: AppController; signalName: "toast" }');
        b.cursorTaskId = k1;
        b.cursorVisible = true;
        b.moveCursorCard(0, -1);
        wait(0);
        compare(notices.count, 1, "the refusal says why");
        b.sortMode = "manual";
        wait(0);
        compare(todoIds(), manual, "Shift+K under a sort rewrote the manual order");
    }

    // ── TASKS-3: an id that comes back shows its new task on the timeline ──
    function test_timeline_shows_the_task_behind_a_returning_id() {
        failOnWarning(/TypeError/);
        const past = new Date(); past.setDate(past.getDate() - 20);
        const a = addTask("todo", { title: "alpha old", priority: "P0", dueAt: past });
        const tl = make('import TodoCpp; TimelineView { anchors.fill: parent }');
        tl.searchText = tc.probe;
        tryVerify(() => tl.groups.overdue && tl.groups.overdue.some(t => t.id === a));

        AppController.deleteTask(a);
        tc.seeded = tc.seeded.filter(x => x !== a);
        const b = addTask("todo", { title: "beta new", priority: "P3" });
        const d = Object.assign({}, AppController.taskById(b));
        d._isNew = false;
        d._originalId = b;
        d.id = a;
        verify(AppController.saveTask(d), "rename into the freed id");
        tc.seeded = tc.seeded.filter(x => x !== b);
        tc.seeded.push(a);
        tryVerify(() => tl.groups.nodl && tl.groups.nodl.some(t => t.id === a), 1000,
                  "the renamed task is not under No deadline");
        verify(!tl.groups.overdue.some(t => t.id === a), "the deleted task's row is still shown");
        compare(tl.groups.nodl.filter(t => t.id === a)[0].title, tc.probe + " beta new");
        compare(tl.groups.nodl.filter(t => t.id === a)[0].priority, "P3");
    }
}
