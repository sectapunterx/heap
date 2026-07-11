// ArchiveView: regression for the priority-sort falsy-zero bug. Archived tasks
// are ordered by priority with P0 the top tier; `priRank[p] || 9` demoted P0's
// rank 0 to the unknown fallback, sinking the most critical archived task to the
// bottom of the list.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ArchiveView"
    when: windowShown
    visible: true
    width: 700
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function test_smoke_load() {
        const av = make('import TodoCpp; ArchiveView { anchors.fill: parent }');
        verify(av !== null);
    }

    // Archive a P1 then a P0 task; buildItems must place the P0 before the P1.
    // Compares the two seeded ids by position (robust to previously archived
    // tasks in the persistent qttest profile).
    function test_p0_sorts_before_p1() {
        const p1 = AppController.newTaskDraft("todo");
        p1.title = "arch p1 probe"; p1.priority = "P1";
        AppController.saveTask(p1);

        const p0 = AppController.newTaskDraft("todo");
        p0.title = "arch p0 probe"; p0.priority = "P0";
        AppController.saveTask(p0);

        AppController.setArchived(p1.id, true);
        AppController.setArchived(p0.id, true);

        const av = make('import TodoCpp; ArchiveView { anchors.fill: parent }');
        const items = av.buildItems();

        let iP0 = -1, iP1 = -1;
        for (let i = 0; i < items.length; i++) {
            if (items[i].id === p0.id) iP0 = i;
            if (items[i].id === p1.id) iP1 = i;
        }
        verify(iP0 >= 0 && iP1 >= 0, "both archived tasks must be present");
        verify(iP0 < iP1, "P0 must sort before P1 in the archive list");

        AppController.deleteTask(p0.id);
        AppController.deleteTask(p1.id);
    }
}
