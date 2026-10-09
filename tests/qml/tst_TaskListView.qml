// Tasks → List (APP-263): groups by date on seeded tasks, "No date" folded
// with its count, the other groupings, j/k + v + d on a selection, and a
// thousand tasks built as a handful of rows.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TaskListView"
    when: windowShown
    visible: true
    width: 1100
    height: 700

    Item { id: host; anchors.fill: parent }

    property var made: []

    function day(n) {
        const t = AppController.today;
        return new Date(t.getFullYear(), t.getMonth(), t.getDate() + n);
    }
    function add(fields) {
        const d = AppController.newTaskDraft(fields.status || "todo");
        d._isNew = true;
        for (const k in fields) d[k] = fields[k];
        AppController.saveTask(d);
        tc.made.push(d.id);
        return d.id;
    }
    function cleanup() {
        AppController.clearSelection();
        for (let i = 0; i < tc.made.length; i++) AppController.deleteTask(tc.made[i]);
        AppController.clearPendingUndo();
        tc.made = [];
    }
    function makeList(query, group) {
        const l = createTemporaryQmlObject('import TodoCpp; TaskListView { anchors.fill: parent }', host);
        verify(l !== null);
        l.searchText = query;
        l.groupBy = group || "date";
        l.refresh();
        return l;
    }
    function groups(l) {
        return l._all.filter(r => r.kind === "group").map(r => r.groupId);
    }

    function test_groups_by_date_with_no_date_folded() {
        add({ id: "TLV-1", title: "tlv today", scheduledAt: day(0) });
        add({ id: "TLV-2", title: "tlv tomorrow", scheduledAt: day(1) });
        add({ id: "TLV-3", title: "tlv nodate" });
        add({ id: "TLV-4", title: "tlv late", scheduledAt: day(-3) });
        const l = makeList("tlv");
        const g = groups(l);
        compare(g[0], "overdue:", "overdue comes first when there is one");
        verify(g.indexOf("today:") >= 0 && g.indexOf("tomorrow:") >= 0 && g.indexOf("none:") >= 0);
        // Folded: the group is there, its rows are not.
        verify(l.isFolded("none:"));
        verify(!l._rows.some(r => r.kind === "task" && r.id === "TLV-3"));
        compare(l.taskCount, 4);
        l.toggleGroup("none:");
        verify(l._rows.some(r => r.kind === "task" && r.id === "TLV-3"));
        l.toggleGroup("none:");
    }

    function test_group_by_status_follows_the_columns() {
        add({ id: "TLV-5", title: "tlvs a", status: "review" });
        add({ id: "TLV-6", title: "tlvs b", status: "todo" });
        const l = makeList("tlvs", "status");
        compare(groups(l), ["status:todo", "status:review"]);
    }

    function test_j_k_v_and_done_on_the_selection() {
        add({ id: "TLV-7", title: "tlvk one", scheduledAt: day(0) });
        add({ id: "TLV-8", title: "tlvk two", scheduledAt: day(0) });
        const l = makeList("tlvk");
        l.moveCursor(0, 1);
        compare(l.cursorTaskId, "TLV-7");
        l.toggleCursorSelection();
        l.moveCursor(0, 1);
        compare(l.cursorTaskId, "TLV-8");
        l.toggleCursorSelection();
        compare(AppController.selectionCount, 2);
        AppController.toggleDone(AppController.selectedTaskIds);
        const done = AppController.doneColumn();
        compare(AppController.taskById("TLV-7").status, done);
        compare(AppController.taskById("TLV-8").status, done);
        AppController.undo();
        compare(AppController.taskById("TLV-7").status, "todo");
    }

    function test_a_thousand_tasks_build_a_screenful() {
        for (let i = 0; i < 1000; i++)
            add({ id: "TLVP-" + i, title: "tlvp " + i, scheduledAt: day(i % 20) });
        const t0 = Date.now();
        const l = makeList("tlvp");
        const ms = Date.now() - t0;
        console.log("TaskListView: 1000 tasks -> rows in " + ms + " ms");
        compare(l.taskCount, 1000);
        const view = findChild(l, "task-list");
        verify(view !== null);
        let built = 0;
        const kids = view.contentItem.children;
        for (let i = 0; i < kids.length; i++) if (kids[i].visible) built++;
        verify(built < 120, "the list built " + built + " rows for 1000 tasks");
    }
}
