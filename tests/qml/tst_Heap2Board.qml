// The board in the heap 2 style (APP-262, APP-281 A1/A3): columns share the
// width so six and a folded Done fit a 1440 px window, Done starts folded
// into a narrow column with "Show", the card shows P2/P3 only when it is
// detailed, and no card carries a branch (Review 3 reverted APP-281 A3).
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Heap2Board"
    when: windowShown
    visible: true
    // 1440 minus the sidebar (208) and the board's own margins.
    width: 1232
    height: 800

    Item { id: host; anchors.fill: parent }

    property var made: []

    function add(fields) {
        const d = AppController.newTaskDraft(fields.status || "todo");
        d._isNew = true;
        for (const k in fields) d[k] = fields[k];
        AppController.saveTask(d);
        tc.made.push(d.id);
        return d.id;
    }

    function cleanup() {
        for (let i = 0; i < tc.made.length; i++) AppController.deleteTask(tc.made[i]);
        AppController.clearPendingUndo();
        tc.made = [];
        Style.apply("bold");
    }

    function byName(item, name) {
        if (!item) return null;
        if (String(item.objectName) === name) return item;
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) {
            const f = byName(kids[i], name);
            if (f) return f;
        }
        return null;
    }
    function allByName(item, name, out) {
        if (!item) return out;
        if (String(item.objectName) === name && item.visible) out.push(item);
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) allByName(kids[i], name, out);
        return out;
    }

    function makeBoard() {
        const b = createTemporaryQmlObject('import TodoCpp; KanbanBoard { anchors.fill: parent }', host);
        verify(b !== null);
        wait(0);
        return b;
    }

    function test_six_columns_and_folded_done_fit_1440() {
        const board = makeBoard();
        // The stock board: six open stages and Done.
        verify(AppController.statuses.length >= 7);
        tryVerify(() => board.columnWidth >= board.minColumnWidth, 1000);
        compare(board.hiddenColumnsRight, 0, "a column is cut off at 1440 px");
        const doneId = AppController.doneColumn();
        verify(board.isFolded(doneId), "Done starts folded");
        // Every column carries the folded-Done item; only Done's is shown.
        const shown = allByName(board, "column-done-folded", []);
        compare(shown.length, 1);
        verify(byName(shown[0], "column-done-show").visible);
    }

    function test_show_opens_done_and_is_remembered() {
        const board = makeBoard();
        const doneId = AppController.doneColumn();
        board.toggleCollapsed(doneId);
        verify(!board.isFolded(doneId));
        const again = makeBoard();
        verify(!again.isFolded(doneId), "the open Done is remembered");
        again.toggleCollapsed(doneId);
        verify(again.isFolded(doneId));
    }

    function test_priority_on_the_card_follows_the_style() {
        // R3-030: bold marks P0/P1, quiet P0 only; P2/P3 never.
        add({ id: "H2B-1", title: "low priority card", priority: "P3", status: "todo" });
        add({ id: "H2B-1b", title: "high priority card", priority: "P1", status: "todo" });
        Style.apply("bold");
        const board = makeBoard();
        let p1 = null;
        tryVerify(() => {
            const all = allByName(board, "tc-priority", []);
            p1 = all.find(t => t.text === "P1") || null;
            return p1 !== null && p1.visible;
        }, 2000, "the bold card shows P1");
        const p3 = allByName(board, "tc-priority", []).find(t => t.text === "P3");
        verify(!p3 || !p3.visible, "P3 is blank in bold");
        Style.apply("quiet");
        verify(!p1.visible, "the quiet card hides P1");
        Style.apply("bold");
    }

    function test_no_card_shows_a_branch() {
        add({ id: "H2B-2", title: "branch card", status: "todo", branch: "feat/h2b-branch" });
        const board = makeBoard();
        tryVerify(() => allByName(board, "tc-title", []).some(t => t.text === "branch card"), 2000);
        // The sheet's card meta is id, date and priority: never the branch.
        const texts = (item, out) => {
            if (!item) return out;
            if (item.visible && typeof item.text === "string" && item.text.indexOf("h2b-branch") >= 0) out.push(item);
            const kids = item.children || [];
            for (let i = 0; i < kids.length; i++) texts(kids[i], out);
            return out;
        };
        compare(texts(board, []).length, 0, "no card shows the task's branch");
    }
}
