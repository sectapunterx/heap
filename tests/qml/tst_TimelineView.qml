// TimelineView: regression for the same-deadline priority tiebreak falsy-zero
// bug. Among tasks sharing a deadline within a bucket, P0 must order before P1;
// `priRank[p] || 9` demoted P0's rank 0 to the unknown fallback, sorting the
// most critical task last within the bucket.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TimelineView"
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
        const tv = make('import TodoCpp; TimelineView { anchors.fill: parent }');
        verify(tv !== null);
    }

    // Both tasks carry the same deadline → same bucket → the priority tiebreak
    // decides their order. Compare the two seeded ids by position (robust to any
    // other tasks that land in the same bucket).
    function test_p0_tiebreaks_before_p1_same_deadline() {
        const day = new Date();
        day.setDate(day.getDate() + 602);
        day.setHours(0, 0, 0, 0);

        const p1 = AppController.newTaskDraft("todo");
        p1.title = "tl p1 probe"; p1.priority = "P1";
        p1.dueAt = day; p1.scheduledAt = day; p1.hasTime = false;
        AppController.saveTask(p1);

        const p0 = AppController.newTaskDraft("todo");
        p0.title = "tl p0 probe"; p0.priority = "P0";
        p0.dueAt = day; p0.scheduledAt = day; p0.hasTime = false;
        AppController.saveTask(p0);

        const tv = make('import TodoCpp; TimelineView { anchors.fill: parent }');
        const groups = tv.buildGroups();

        let iP0 = -1, iP1 = -1;
        for (const k in groups) {
            const arr = groups[k];
            for (let i = 0; i < arr.length; i++) {
                if (arr[i].id === p0.id) iP0 = i;
                if (arr[i].id === p1.id) iP1 = i;
            }
        }
        verify(iP0 >= 0 && iP1 >= 0, "both tasks must be bucketed");
        verify(iP0 < iP1, "P0 must tiebreak before P1 at the same deadline");

        AppController.deleteTask(p0.id);
        AppController.deleteTask(p1.id);
    }

    function countRows(item, acc) {
        if (!item) return acc;
        if (String(item.objectName) === "tl-row") acc.n++;
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) countRows(kids[i], acc);
        return acc;
    }

    // The timeline builds the rows on screen, not one per task (audit A5):
    // 2000 tasks used to cost over a gigabyte of delegates.
    // Design audit DES-12: every bucket's label column is the same width, so
    // rows line up across buckets — "На следующей неделе" pushed its own
    // column wider and its rows started ~32px right of the others.
    function test_label_columns_line_up_across_buckets() {
        const saved = AppController.language;
        AppController.language = "ru";
        const next = new Date();
        next.setDate(next.getDate() + 8);
        next.setHours(0, 0, 0, 0);
        const d = AppController.newTaskDraft("todo");
        d._isNew = true; d.id = "TLV-ALIGN"; d.title = "align probe";
        d.dueAt = next; d.scheduledAt = next; d.hasTime = false;
        AppController.saveTask(d);
        const tv = make('import TodoCpp; TimelineView { anchors.fill: parent }');
        function widths() {
            const out = [];
            (function walk(it) {
                if (!it) return;
                if (it.objectName === "timeline-label-col" && it.visible) out.push(it.width);
                const kids = it.children || [];
                for (let i = 0; i < kids.length; i++) walk(kids[i]);
            })(tv);
            return out;
        }
        // Rows are laid out a frame or more after they are built (slow CI
        // runners showed 0 for the last ones); wait for the layout to settle.
        tryVerify(function () {
            const w = widths();
            return w.length > 0 && w.every(function (x) { return x > 0; });
        }, 3000, "label columns never got a width");
        const cols = widths();
        AppController.deleteTask("TLV-ALIGN");
        AppController.clearPendingUndo();
        AppController.language = saved;
        for (let i = 0; i < cols.length; i++) compare(cols[i], 160);
    }

    function test_a_long_timeline_builds_only_the_visible_rows() {
        const day = new Date();
        day.setDate(day.getDate() + 1);
        day.setHours(0, 0, 0, 0);
        const ids = [];
        for (let i = 0; i < 300; i++) {
            const d = AppController.newTaskDraft("todo");
            d._isNew = true;
            d.id = "TLV-" + i;
            d.title = "virtual " + i;
            d.dueAt = day; d.scheduledAt = day; d.hasTime = false;
            AppController.saveTask(d);
            ids.push(d.id);
        }
        const tv = make('import TodoCpp; TimelineView { anchors.fill: parent }');
        wait(0);
        const built = countRows(tv, { n: 0 }).n;
        verify(built > 0, "the timeline shows rows");
        verify(built < 150, "the timeline built " + built + " rows for 300 tasks");
        for (let i = 0; i < ids.length; i++) AppController.deleteTask(ids[i]);
        AppController.clearPendingUndo();
    }

    // APP-197: a row says what, when and where it stands; the key and the
    // description open under the cursor, and nothing on it is a pill.
    function test_a_row_is_title_due_and_status() {
        const day = new Date();
        day.setDate(day.getDate() + 1);
        day.setHours(0, 0, 0, 0);
        const d = AppController.newTaskDraft("todo");
        d._isNew = true; d.id = "TLV-CALM"; d.title = "calm row probe"; d.priority = "P0";
        d.desc = "calm row description"; d.branch = "feat/calm-row-branch";
        d.dueAt = day; d.scheduledAt = day; d.hasTime = false;
        AppController.saveTask(d);
        const tv = make('import TodoCpp; TimelineView { anchors.fill: parent }');
        tv.searchText = "calm row probe";
        function row() {
            let found = null;
            (function walk(it) {
                if (!it || found) return;
                if (it.objectName === "tl-row" && it.visible && it.t && it.t.id === "TLV-CALM") { found = it; return; }
                const kids = it.children || [];
                for (let i = 0; i < kids.length; i++) walk(kids[i]);
            })(tv);
            return found;
        }
        tryVerify(function () { return row() !== null; }, 3000, "no row for the probe");
        const r = row();
        verify(findChild(r, "tl-title").visible);
        verify(findChild(r, "tl-due").visible);
        verify(findChild(r, "tl-status").visible);
        compare(findChild(r, "tl-more").visible, false, "key and description show at rest");
        compare(Qt.colorEqual(findChild(r, "tl-due").color, Theme.danger), false, "tomorrow is not red");
        tv.cursorTaskId = "TLV-CALM";
        tryVerify(function () { return findChild(r, "tl-more").visible; }, 2000, "the cursor did not open the row");
        compare(findChild(r, "tl-key").text, "TLV-CALM");
        AppController.deleteTask("TLV-CALM");
        AppController.clearPendingUndo();
    }
}
