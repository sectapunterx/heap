// Column sort order (TaskFilterProxy.sortMode).
//
// The board had no sorting at all — the column showed whatever order the model
// happened to be in. "manual" is the board's own rank, the one a drag writes;
// the others are read-only views over the same cards, so switching back to
// manual restores the arrangement rather than whatever the last sort left.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "BoardSort"
    when: windowShown
    visible: true
    width: 600
    height: 600

    Item { id: host; anchors.fill: parent }

    // The shared QML test profile is never wiped, so every seeded card carries
    // this token and the proxy is filtered to it.
    readonly property string probe: "sortprobe"
    property var seeded: []

    function seedCard(id, opts) {
        const statuses = AppController.statuses;
        const d = AppController.newTaskDraft(statuses[0].id);
        d._isNew = true;
        d.id = id;
        d.title = tc.probe + " " + (opts.title || id);
        d.priority = opts.priority || "P2";
        if (opts.dueAt !== undefined) {
            d.dueAt = opts.dueAt;
            d.hasTime = true;
        }
        AppController.saveTask(d);
        tc.seeded.push(id);
        return id;
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        AppController.clearPendingUndo();
        tc.seeded = [];
    }

    function makeProxy() {
        const p = createTemporaryQmlObject(
            'import TodoCpp; TaskFilterProxy { sourceModel: AppController.tasks }', host);
        verify(p !== null);
        p.status = AppController.statuses[0].id;
        p.searchText = tc.probe;
        return p;
    }

    function idsOf(proxy) {
        const out = [];
        for (let i = 0; i < proxy.rowCount(); i++) {
            out.push(proxy.data(proxy.index(i, 0), Qt.UserRole + 1));  // IdRole
        }
        return out;
    }

    function test_default_is_manual() {
        const p = makeProxy();
        compare(p.sortMode, "manual");
    }

    // Manual is the rank order a drag writes, which is what "the user arranged
    // this" means. New cards land on top, so seeding A then B then C shows
    // C, B, A.
    function test_manual_follows_rank() {
        seedCard("SORT-A", {});
        seedCard("SORT-B", {});
        seedCard("SORT-C", {});
        const p = makeProxy();

        compare(idsOf(p), ["SORT-C", "SORT-B", "SORT-A"]);
    }

    function test_priority_puts_p0_first() {
        seedCard("SORT-LOW", { priority: "P3" });
        seedCard("SORT-TOP", { priority: "P0" });
        seedCard("SORT-MID", { priority: "P2" });

        const p = makeProxy();
        p.sortMode = "priority";

        compare(idsOf(p), ["SORT-TOP", "SORT-MID", "SORT-LOW"]);
    }

    // The falsy-zero trap: P0 maps to rank 0, and `rank || 4` would send every
    // P0 to the bottom. That exact bug demoted P0 across four views once.
    function test_p0_is_not_demoted_by_a_falsy_zero() {
        seedCard("SORT-P0", { priority: "P0" });
        seedCard("SORT-P1", { priority: "P1" });

        const p = makeProxy();
        p.sortMode = "priority";

        compare(idsOf(p)[0], "SORT-P0");
    }

    function test_due_sorts_earliest_first() {
        const early = new Date(2027, 0, 10, 9, 0);
        const late = new Date(2027, 5, 10, 9, 0);
        seedCard("SORT-LATE", { dueAt: late });
        seedCard("SORT-EARLY", { dueAt: early });

        const p = makeProxy();
        p.sortMode = "due";

        compare(idsOf(p), ["SORT-EARLY", "SORT-LATE"]);
    }

    // A task with no due date is not "due at the epoch" — it belongs behind
    // everything that actually has one.
    function test_undated_cards_sort_last_under_due() {
        seedCard("SORT-NONE", {});
        seedCard("SORT-DATED", { dueAt: new Date(2027, 0, 10, 9, 0) });

        const p = makeProxy();
        p.sortMode = "due";

        compare(idsOf(p), ["SORT-DATED", "SORT-NONE"]);
    }

    function test_title_sorts_case_insensitively() {
        seedCard("SORT-1", { title: "zebra" });
        seedCard("SORT-2", { title: "Apple" });

        const p = makeProxy();
        p.sortMode = "title";

        // Both titles carry the probe prefix, so the comparison falls to the
        // word after it.
        compare(idsOf(p), ["SORT-2", "SORT-1"]);
    }

    // The whole point of keeping rank underneath: a sort is a view, and going
    // back to manual restores what the user arranged.
    function test_switching_back_to_manual_restores_the_arrangement() {
        seedCard("SORT-A", { priority: "P3" });
        seedCard("SORT-B", { priority: "P0" });
        const p = makeProxy();
        const manual = idsOf(p);

        p.sortMode = "priority";
        verify(idsOf(p)[0] === "SORT-B");

        p.sortMode = "manual";
        compare(idsOf(p), manual);
    }

    function test_an_unknown_mode_falls_back_to_manual() {
        seedCard("SORT-A", {});
        seedCard("SORT-B", {});
        const p = makeProxy();
        const manual = idsOf(p);

        p.sortMode = "not-a-mode";
        compare(idsOf(p), manual);
    }

    function test_empty_mode_means_manual() {
        const p = makeProxy();
        p.sortMode = "priority";
        p.sortMode = "";
        compare(p.sortMode, "manual");
    }
}
