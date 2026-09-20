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

    // `items` is a binding over buildItems(), and buildItems() reads searchText
    // and prioritiesFilter through passesFilter(). Two handlers used to bump
    // modelRev on those properties to "re-evaluate buildItems via binding",
    // which was both redundant and a loop: prioritiesFilter's own default
    // binding is evaluated on its first read — inside this very binding — and
    // the change signal it emits bumped modelRev while items was still being
    // computed. Qt reported a binding loop and abandoned the evaluation.
    //
    // This pins both halves: no warning, and the list still tracks the filters.
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
            for (let i = 0; i < av.items.length; i++) if (av.items[i].id === id) return true;
            return false;
        }

        verify(has(t.id), "an archived task must be listed");

        // Read through the binding, not buildItems(): the point is that the
        // binding re-evaluates on its own.
        av.searchText = "zulu";
        verify(has(t.id), "the binding must re-run when searchText moves");
        av.searchText = "nothingmatchesthis";
        verify(!has(t.id), "and must narrow, not stay stale");
        av.searchText = "";

        av.prioritiesFilter = ({ P0: true });
        verify(!has(t.id), "the binding must re-run when prioritiesFilter moves");
        av.prioritiesFilter = ({ P1: true });
        verify(has(t.id));

        AppController.deleteTask(t.id);
    }
}
