// One task menu in every view (APP-268): the board's card and a view's own
// host build the same rows; "Done" is in it, with its key.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TaskMenu"
    when: windowShown
    visible: true
    width: 600
    height: 600

    Item { id: host; anchors.fill: parent }
    property var made: []
    function cleanup() {
        for (const id of tc.made) AppController.deleteTask(id);
        tc.made = [];
        AppController.clearPendingUndo();
    }
    function mkTask(title) {
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.title = title;
        AppController.saveTask(d);
        tc.made.push(d.id);
        return d.id;
    }
    function rows(menu) {
        const out = [];
        for (let i = 0; i < menu.count; i++) {
            const it = menu.itemAt(i);
            if (it && it.objectName) out.push(it.objectName);
        }
        return out;
    }

    function test_every_view_builds_the_same_menu() {
        const id = mkTask("menu probe");
        const card = createTemporaryQmlObject('import TodoCpp; TaskCard { width: 240 }', host);
        card.task = AppController.taskById(id);
        const viewHost = createTemporaryQmlObject('import TodoCpp; TaskMenuHost {}', host);
        viewHost.anchorItem = host;
        viewHost.taskId = id;
        const a = rows(card.contextMenu());
        const b = rows(viewHost.contextMenu());
        compare(a, b);
        verify(a.indexOf("tc-menu-done") >= 0, "no Done row: " + a);
        verify(a.indexOf("tc-menu-delete") > a.indexOf("tc-menu-archive"), "Delete is last");
    }

    // R3-046: a tracker's task shows the sheet's rows, in its order.
    function test_tracker_menu_is_the_sheets() {
        const h = createTemporaryQmlObject('import TodoCpp; TaskMenuHost {}', host);
        h.anchorItem = host;
        h.task = { id: "github-1", title: "t", status: "todo", priority: "P2",
                   ticket: { provider: "github", key: "#1", url: "https://example.com/1" } };
        const m = h.contextMenu();
        m.popup(host, 0, 0);
        tryVerify(() => m.opened, 1000);
        const shown = [];
        for (let i = 0; i < m.count; i++) {
            const it = m.itemAt(i);
            if (it && it.objectName && it.visible && it.height > 0 && String(it.objectName).indexOf("Sep") < 0) shown.push(it.objectName);
        }
        compare(shown, ["tc-menu-edit", "tc-menu-open", "tc-menu-done", "tc-menu-priority", "tc-menu-due",
                        "tc-menu-schedule", "tc-menu-copylink", "tc-menu-refresh", "tc-menu-delete", "tc-menu-delete-off"]);
        let off = null;
        for (let i = 0; i < m.count; i++) if (m.itemAt(i).objectName === "tc-menu-delete-off") off = m.itemAt(i);
        verify(!off.enabled);
        m.close();
    }
    // R3-044: the Done-stage column is last, after a separator, with d.
    function test_status_list_puts_done_last() {
        const id = mkTask("status probe");
        const h = createTemporaryQmlObject('import TodoCpp; TaskMenuHost {}', host);
        h.anchorItem = host;
        h.taskId = id;
        const s = h.statusMenu();
        const last = s.itemAt(s.count - 1);
        compare(AppController.statusCategory(last.modelData.id), "done");
        compare(s.itemAt(s.count - 2).objectName, "tc-status-doneSep");
        compare(last.hint, AppController.shortcutText("task.done"));
        compare(s.itemAt(1).hint, "", "no number keys drawn");
    }

    function test_done_row_runs_done_and_shows_its_key() {
        const id = mkTask("done probe");
        const h = createTemporaryQmlObject('import TodoCpp; TaskMenuHost {}', host);
        h.anchorItem = host;
        h.taskId = id;
        const m = h.contextMenu();
        let done = null;
        for (let i = 0; i < m.count; i++) if (m.itemAt(i).objectName === "tc-menu-done") done = m.itemAt(i);
        verify(done !== null);
        compare(done.hint, AppController.shortcutText("task.done"));
        h.markDone();
        compare(AppController.taskById(id).status, AppController.doneColumn());
        h.markDone();
        compare(AppController.taskById(id).status, "todo", "a second Done puts it back");
    }

    function test_a_missing_branch_says_why() {
        const id = mkTask("branch probe");
        const h = createTemporaryQmlObject('import TodoCpp; TaskMenuHost {}', host);
        h.anchorItem = host;
        h.taskId = id;
        const m = h.contextMenu();
        for (let i = 0; i < m.count; i++) {
            const it = m.itemAt(i);
            if (it.objectName !== "tc-menu-copybranch") continue;
            verify(!it.enabled);
            compare(it.note, I18n.t("taskmenu.why.noBranch"));
            return;
        }
        fail("no copy-branch row");
    }
}
