// The board under the mouse: the wheel, a click on empty space, and a drag
// from one column to another.
//
// Three regressions: a long column that ran out of cards handed the wheel to
// the board, which slid sideways; a clicked card kept its cursor ring after
// its editor closed, and nothing took it away; a dragged card stayed inside
// its own column, clipped by it and drawn under the columns to its right.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "BoardMouse"
    when: windowShown
    visible: true
    width: 1200
    height: 700

    Item { id: host; anchors.fill: parent }

    property var seeded: []
    // The QML test profile is shared and never wiped; the board is filtered to
    // this token so it shows exactly the cards a case created.
    readonly property string probe: "mouseprobe"

    function seed(perColumn) {
        const statuses = AppController.statuses;
        tc.seeded = [];
        for (let c = 0; c < statuses.length; c++) {
            const n = perColumn[c] || 0;
            for (let i = 0; i < n; i++) {
                const d = AppController.newTaskDraft(statuses[c].id);
                d._isNew = true;
                d.id = "MSE-" + c + "-" + i;
                d.title = tc.probe + " card " + c + "." + i;
                AppController.saveTask(d);
                tc.seeded.push(d.id);
            }
        }
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        AppController.clearPendingUndo();
        AppController.clearSelection();
        tc.seeded = [];
    }

    function makeBoard() {
        const b = createTemporaryQmlObject(
            'import TodoCpp; KanbanBoard { anchors.fill: parent }', host);
        verify(b !== null);
        b.searchText = tc.probe;
        waitForRendering(b);
        return b;
    }

    // Every column's card list, left to right.
    function lists(item, out) {
        out = out || [];
        for (let i = 0; i < item.children.length; i++) {
            const c = item.children[i];
            if (c.objectName === "column-list") out.push(c);
            lists(c, out);
        }
        return out;
    }
    function columnLists(board) {
        const found = lists(board);
        found.sort((a, b) => a.mapToItem(board, 0, 0).x - b.mapToItem(board, 0, 0).x);
        return found;
    }
    function statusOf(id) { return AppController.taskById(id).status; }

    function test_wheel_at_the_bottom_of_a_long_column_does_not_move_the_board() {
        seed([30]);
        const b = makeBoard();
        const hs = findChild(b, "board-hscroll");
        verify(hs !== null);
        verify(hs.contentWidth > hs.width, "the board must be wider than the window for this case");
        const list = columnLists(b)[0];
        tryVerify(() => list.contentHeight > list.height, 2000, "the first column must overflow");

        // Far more wheel than the column has to give.
        for (let i = 0; i < 40; i++) mouseWheel(list, list.width / 2, list.height / 2, 0, -240);
        tryVerify(() => list.contentY >= list.contentHeight - list.height - 1, 3000,
                  "the column did not scroll to its end");
        wait(400);
        compare(hs.contentX, 0, "the board slid sideways once the column ran out");
    }

    function test_wheel_over_a_short_column_still_scrolls_the_board() {
        seed([1]);
        const b = makeBoard();
        const hs = findChild(b, "board-hscroll");
        const list = columnLists(b)[0];
        mouseWheel(list, list.width / 2, list.height / 2, 0, -240);
        tryVerify(() => hs.contentX > 0, 2000, "a column with nothing to scroll must hand the wheel to the board");
    }

    function test_click_on_empty_board_clears_cursor_and_selection() {
        seed([2, 1]);
        const b = makeBoard();
        b.moveCursor(0, 0);
        verify(b.cursorVisible && b.cursorTaskId !== "");
        AppController.setSelectedTaskIds([tc.seeded[0], tc.seeded[1]]);
        compare(AppController.selectionCount, 2);

        // Below the two cards of the first column.
        const list = columnLists(b)[0];
        mouseClick(list, list.width / 2, list.height - 20);
        compare(AppController.selectionCount, 0, "the selection survived a click on empty space");
        verify(!b.cursorVisible, "the cursor ring survived a click on empty space");
        compare(b.cursorTaskId, "");
    }

    function test_clicking_a_card_does_not_leave_a_cursor_ring() {
        seed([1]);
        const b = makeBoard();
        const list = columnLists(b)[0];
        tryVerify(() => list.itemAtIndex(0) !== null);
        const card = list.itemAtIndex(0);
        mouseClick(card, card.width / 2, 10);
        compare(b.cursorTaskId, tc.seeded[0], "a click still moves the cursor, so J/K carry on from there");
        verify(!b.cursorVisible, "a mouse click drew the keyboard ring");
        verify(!card.cursored);
    }

    function test_dragged_card_rides_above_the_columns_and_lands_in_another() {
        seed([1, 1]);
        const b = makeBoard();
        const cols = columnLists(b);
        tryVerify(() => cols[0].itemAtIndex(0) !== null);
        const card = cols[0].itemAtIndex(0);
        const layer = findChild(b, "board-drag-layer");
        verify(layer !== null);
        const homeParent = card.parent;
        const id = card.taskId;

        // In the board's coordinates: the card moves under the pointer, so
        // positions relative to it would chase themselves.
        const from = card.mapToItem(b, card.width / 2, 20);
        const to = cols[1].mapToItem(b, cols[1].width / 2, cols[1].height - 40);
        mousePress(b, from.x, from.y);
        for (let i = 1; i <= 12; i++)
            mouseMove(b, from.x + (to.x - from.x) * i / 12, from.y + (to.y - from.y) * i / 12);
        compare(card.parent, layer, "the dragged card stayed inside its own column");
        mouseRelease(b, to.x, to.y);
        tryVerify(() => statusOf(id) === AppController.statuses[1].id, 2000,
                  "the drop did not move the card");
        verify(homeParent !== layer);
    }
}
