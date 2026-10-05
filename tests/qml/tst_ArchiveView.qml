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

    // TASKS-5: status: names a column as the board shows it, in the archive
    // too. The archive's proxy had no column list, so only ids matched.
    function test_status_by_column_name() {
        const sts = AppController.statuses;
        let col = null;
        for (let i = 0; i < sts.length; i++)
            if (sts[i].name.toLowerCase() !== sts[i].id.toLowerCase()) { col = sts[i]; break; }
        verify(col !== null, "no column whose name differs from its id");

        const t = AppController.newTaskDraft(col.id);
        t.title = "qzarch name probe";
        AppController.saveTask(t);
        AppController.setArchived(t.id, true);

        const av = make('import TodoCpp; ArchiveView { anchors.fill: parent }');
        av.searchText = 'qzarch status:"' + col.name + '"';
        const items = av.buildItems();
        let found = false;
        for (let i = 0; i < items.length; i++) if (items[i].id === t.id) found = true;
        verify(found, "status:\"" + col.name + "\" did not find the archived task");

        AppController.deleteTask(t.id);
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

    // The feed tracks the search box and the priority chips on its own, with
    // no binding loop. (It used to be a JS `items` binding over buildItems(),
    // where a modelRev bump inside the evaluation looped; it is a C++ proxy
    // now, and this pins that it still narrows and widens with the filters.)
    function test_items_track_the_filters_without_a_binding_loop() {
        // Armed before anything is built: failOnWarning only catches what is
        // emitted after the call, and the loop fires during construction.
        failOnWarning(/Binding loop detected/);
        failOnWarning(/recursive rearrange/);

        const t = AppController.newTaskDraft("todo");
        t.title = "arch loop probe zulu"; t.priority = "P1";
        AppController.saveTask(t);
        AppController.setArchived(t.id, true);

        const av = make('import TodoCpp; ArchiveView { anchors.fill: parent }');

        function has(id) {
            const items = av.buildItems();
            for (let i = 0; i < items.length; i++) if (items[i].id === id) return true;
            return false;
        }

        verify(has(t.id), "an archived task must be listed");

        av.searchText = "zulu";
        verify(has(t.id), "the feed must follow searchText");
        av.searchText = "nothingmatchesthis";
        verify(!has(t.id), "and must narrow, not stay stale");
        av.searchText = "";

        av.prioritiesFilter = ({ P0: true });
        verify(!has(t.id), "the feed must follow prioritiesFilter");
        av.prioritiesFilter = ({ P1: true });
        verify(has(t.id));

        AppController.deleteTask(t.id);
    }

    // Audit 2026-09-30 (TASKS-4 / PLAT-12): the archive built a full TaskCard —
    // each with its own 13-item menu — for every archived task, up front:
    // 1561 archived tasks took 2.4 GB and 12 s. It is a ListView now, so the
    // number of cards is bounded by the viewport, not by the archive, and no
    // card has built a menu until one is opened.
    function test_archive_builds_only_the_cards_on_screen() {
        const ids = [];
        for (let i = 0; i < 300; i++) {
            const t = AppController.newTaskDraft("done");
            t.title = "arch scale probe " + i;
            AppController.saveTask(t);
            ids.push(t.id);
        }
        AppController.setSelectedTaskIds(ids);
        AppController.setSelectedTasksArchived(true);
        AppController.clearSelection();

        const av = make('import TodoCpp; ArchiveView { anchors.fill: parent }');
        const list = findChild(av, "archive-list");
        verify(list !== null, "the archive is not a ListView");
        tryVerify(() => list.count >= 300, 2000, "the feed lost archived rows");
        compare(av.count, list.count);

        let cards = 0, menus = 0;
        function walk(o) {
            if (!o) return;
            if (o.objectName === "tc-card") {
                cards++;
                if (findChild(o, "tc-menu")) menus++;
            }
            for (let i = 0; i < o.children.length; i++) walk(o.children[i]);
        }
        walk(list.contentItem);
        verify(cards > 0, "no card on screen");
        verify(cards < 60, "the archive built " + cards + " cards for a 500px viewport");
        compare(menus, 0, "cards built their context menus up front");

        // Restoring one card drops one row; the rest stay.
        AppController.setArchived(ids[0], false);
        compare(av.buildItems().some(r => r.id === ids[0]), false, "a restored task stayed in the archive");
        compare(av.count, list.count);

        // Undo puts it back.
        AppController.undo();
        verify(av.buildItems().some(r => r.id === ids[0]), "undo of a restore did not re-archive");

        // Select-all takes the whole feed, not just the cards on screen.
        av.selectAllVisible();
        compare(AppController.selectionCount, av.count);
        AppController.clearSelection();

        for (let i = 0; i < ids.length; i++) AppController.deleteTask(ids[i]);
        AppController.clearPendingUndo();
    }
}
