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

    function test_done_row_runs_done_and_shows_its_key() {
        const id = mkTask("done probe");
        const h = createTemporaryQmlObject('import TodoCpp; TaskMenuHost {}', host);
        h.anchorItem = host;
        h.taskId = id;
        const m = h.contextMenu();
        let done = null;
        for (let i = 0; i < m.count; i++) if (m.itemAt(i).objectName === "tc-menu-done") done = m.itemAt(i);
        verify(done !== null);
        compare(done.hint, AppController.shortcutFor("task.done"));
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
