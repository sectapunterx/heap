// The toast stack (audit UX-16).
//
// One slot used to hold every notice, so a later toast replaced a pending
// "Undo" and the undo was gone; the bar had no width cap (1093px at 1100);
// and every toast from C++ arrived as "info", failures included.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Toast"
    when: windowShown
    visible: true
    width: 1100
    height: 600

    Item { id: host; anchors.fill: parent }

    function make() {
        const t = createTemporaryQmlObject(
            'import TodoCpp; Toast { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter }', host);
        verify(t !== null);
        return t;
    }

    function cards(t) {
        const out = [];
        const walk = function (it) {
            if (!it) return;
            if (it.objectName === "toast-card") out.push(it);
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) walk(kids[i]);
        };
        walk(t);
        return out;
    }

    function test_undo_toast_survives_later_toasts() {
        const t = make();
        let undone = 0;
        t.showWithAction("Deleted: A", "Undo", 10, function () { undone++; });
        t.show("Saved");
        t.show("Synced");
        t.show("Another thing");
        wait(0);
        let undo = null;
        for (const c of cards(t)) if (c.modelData.actionLabel === "Undo") undo = c;
        verify(undo !== null, "a later toast replaced the Undo toast");
        verify(t.count <= t.maxVisible);
        const ma = (function find(it) {
            if (it.cursorShape === Qt.PointingHandCursor && it.clicked !== undefined) return it;
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) { const r = find(kids[i]); if (r) return r; }
            return null;
        })(undo);
        mouseClick(ma);
        compare(undone, 1);
    }

    function test_action_toasts_queue_rather_than_replace() {
        const t = make();
        for (let i = 0; i < 4; i++) t.showWithAction("Deleted " + i, "Undo", 10, function () {});
        compare(t.count, t.maxVisible);
        compare(t._queue.length, 1, "the fourth waits for a slot");
        t.dismiss(t._items[0].id);
        compare(t.count, t.maxVisible);
        compare(t._queue.length, 0);
    }

    function test_width_is_capped_and_long_text_wraps() {
        const t = make();
        let longText = "";
        for (let i = 0; i < 60; i++) longText += "word" + i + " ";
        t.show(longText);
        wait(0);
        const c = cards(t)[0];
        verify(c.width <= 560, "toast is " + c.width + "px wide");
        verify(c.height > 40, "long text should wrap onto more lines");
    }

    function test_kind_tints_and_errors_stay_longer() {
        const t = make();
        t.show("Sync failed", "error");
        compare(t.kind, "error");
        verify(t._items[0].ms > 2400, "an error must stay up longer than a notice");
    }

    function test_plain_duplicate_refreshes_instead_of_stacking() {
        const t = make();
        t.show("Sync is running");
        t.show("Sync is running");
        compare(t.count, 1);
    }

    function test_toasts_expire() {
        const t = make();
        t._push({ id: 99, message: "brief", kind: "info", actionLabel: "", actionFn: null, ms: 50 });
        compare(t.count, 1);
        tryCompare(t, "count", 0, 1000);
    }
}
