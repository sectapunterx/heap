// The board's keyboard cursor.
//
// The board is the app's main surface and was mouse-only: no way to move
// between cards, open one, or move one, without dragging. These cases drive
// the board's public cursor functions directly — the shortcut wiring in
// Main.qml is thin, and offscreen key delivery is not something to build a
// suite on.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "BoardKeys"
    when: windowShown
    visible: true
    width: 1200
    height: 800

    Item { id: host; anchors.fill: parent }

    property var seeded: []

    // The QML test profile is shared and never wiped, so a board built here
    // shows whatever earlier runs left behind. Every seeded card carries this
    // token in its title and the board is filtered to it, which makes the
    // visible set exactly the cards a case created.
    readonly property string probe: "keyprobe"

    function seed(perColumn) {
        const statuses = AppController.statuses;
        tc.seeded = [];
        for (let c = 0; c < statuses.length; c++) {
            for (let i = 0; i < perColumn; i++) {
                const d = AppController.newTaskDraft(statuses[c].id);
                d._isNew = true;
                d.id = "KEY-" + c + "-" + i;
                d.title = tc.probe + " card " + c + "." + i;
                AppController.saveTask(d);
                tc.seeded.push(d.id);
            }
        }
    }

    function unseed() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        AppController.clearPendingUndo();
        tc.seeded = [];
    }

    function cleanup() {
        unseed();
    }

    function makeBoard() {
        const b = createTemporaryQmlObject(
            'import TodoCpp; KanbanBoard { anchors.fill: parent }', host);
        verify(b !== null);
        b.searchText = tc.probe;
        wait(0);   // let the per-column Repeaters populate
        return b;
    }

    // Column-major list of what is on screen, which is the order the cursor
    // walks. Built the same way the board builds it.
    function columns(board) {
        return board._visibleByColumn();
    }

    // A key arriving with no cursor yet has to land somewhere sensible rather
    // than doing nothing — otherwise the first press always looks broken.
    function test_first_move_adopts_the_first_card() {
        seed(2);
        const b = makeBoard();
        compare(b.cursorTaskId, "");

        b.moveCursor(0, 1);

        const cols = columns(b);
        verify(b.cursorTaskId !== "", "the first key press must adopt a card");
        compare(b.cursorTaskId, cols[0].ids[0]);
    }

    function test_down_and_up_walk_a_column() {
        seed(3);
        const b = makeBoard();
        const ids = columns(b)[0].ids;
        verify(ids.length >= 3);

        b.cursorTaskId = ids[0];
        b.moveCursor(0, 1);
        compare(b.cursorTaskId, ids[1]);
        b.moveCursor(0, 1);
        compare(b.cursorTaskId, ids[2]);
        b.moveCursor(0, -1);
        compare(b.cursorTaskId, ids[1]);
    }

    // Walking off either end stays put rather than wrapping — wrapping makes
    // "hold down j" scroll forever.
    function test_the_ends_of_a_column_hold() {
        seed(2);
        const b = makeBoard();
        const ids = columns(b)[0].ids;

        b.cursorTaskId = ids[0];
        b.moveCursor(0, -1);
        compare(b.cursorTaskId, ids[0]);

        b.cursorTaskId = ids[ids.length - 1];
        b.moveCursor(0, 1);
        compare(b.cursorTaskId, ids[ids.length - 1]);
    }

    function test_left_and_right_change_column() {
        seed(2);
        const b = makeBoard();
        const cols = columns(b);
        verify(cols.length >= 2);

        b.cursorTaskId = cols[0].ids[0];
        b.moveCursor(1, 0);
        compare(b.cursorTaskId, cols[1].ids[0]);
        b.moveCursor(-1, 0);
        compare(b.cursorTaskId, cols[0].ids[0]);
    }

    // Moving into a shorter column lands on its last card instead of falling
    // off the end.
    function test_moving_into_a_shorter_column_clamps() {
        const statuses = AppController.statuses;
        verify(statuses.length >= 2);
        tc.seeded = [];
        for (let i = 0; i < 3; i++) {
            const d = AppController.newTaskDraft(statuses[0].id);
            d._isNew = true; d.id = "KEY-A-" + i; d.title = tc.probe + " a" + i;
            AppController.saveTask(d); tc.seeded.push(d.id);
        }
        const one = AppController.newTaskDraft(statuses[1].id);
        one._isNew = true; one.id = "KEY-B-0"; one.title = tc.probe + " b0";
        AppController.saveTask(one); tc.seeded.push(one.id);

        const b = makeBoard();
        const cols = columns(b);

        b.cursorTaskId = cols[0].ids[2];   // third card of the tall column
        b.moveCursor(1, 0);
        compare(b.cursorTaskId, cols[1].ids[cols[1].ids.length - 1]);
    }

    // An empty column in the middle must not swallow the cursor.
    function test_an_empty_column_is_skipped() {
        const statuses = AppController.statuses;
        verify(statuses.length >= 3);
        tc.seeded = [];
        for (const c of [0, 2]) {
            const d = AppController.newTaskDraft(statuses[c].id);
            d._isNew = true; d.id = "KEY-S-" + c; d.title = tc.probe + " s" + c;
            AppController.saveTask(d); tc.seeded.push(d.id);
        }

        const b = makeBoard();
        const cols = columns(b);
        compare(cols[1].ids.length, 0, "the middle column must be empty for this case");

        b.cursorTaskId = cols[0].ids[0];
        b.moveCursor(1, 0);
        compare(b.cursorTaskId, cols[2].ids[0]);
    }

    function test_open_emits_task_clicked() {
        seed(1);
        const b = makeBoard();
        const ids = columns(b)[0].ids;
        let got = "";
        b.taskClicked.connect(function (id) { got = id; });

        b.cursorTaskId = ids[0];
        b.openCursor();

        compare(got, ids[0]);
    }

    function test_toggle_select_adds_and_removes() {
        seed(1);
        const b = makeBoard();
        const ids = columns(b)[0].ids;
        AppController.clearSelection();

        b.cursorTaskId = ids[0];
        b.toggleCursorSelection();
        verify(AppController.isTaskSelected(ids[0]));

        b.toggleCursorSelection();
        verify(!AppController.isTaskSelected(ids[0]));
    }

    // Moving a card (Shift+H/J/K/L, Ctrl+arrows): the card moves, and the
    // cursor stays on it.
    function test_moving_a_card_down_swaps_it_with_its_neighbour() {
        seed(3);
        const b = makeBoard();
        const before = columns(b)[0].ids.slice();

        b.cursorTaskId = before[0];
        b.moveCursorCard(0, 1);
        wait(0);

        const after = columns(b)[0].ids;
        compare(after[0], before[1]);
        compare(after[1], before[0]);
        compare(b.cursorTaskId, before[0], "the cursor follows the card it moved");
    }

    function test_moving_a_card_up_swaps_it_with_its_neighbour() {
        seed(3);
        const b = makeBoard();
        const before = columns(b)[0].ids.slice();

        b.cursorTaskId = before[2];
        b.moveCursorCard(0, -1);
        wait(0);

        const after = columns(b)[0].ids;
        compare(after[1], before[2]);
        compare(after[2], before[1]);
    }

    function test_moving_a_card_off_the_end_does_nothing() {
        seed(2);
        const b = makeBoard();
        const before = columns(b)[0].ids.slice();

        b.cursorTaskId = before[0];
        b.moveCursorCard(0, -1);
        wait(0);

        compare(columns(b)[0].ids, before);
    }

    function test_moving_a_card_right_changes_its_column() {
        seed(2);
        const b = makeBoard();
        const cols = columns(b);
        const moving = cols[0].ids[0];

        b.cursorTaskId = moving;
        b.moveCursorCard(1, 0);
        wait(0);

        const after = columns(b);
        verify(after[0].ids.indexOf(moving) < 0, "it left the old column");
        verify(after[1].ids.indexOf(moving) >= 0, "it arrived in the next one");
    }

    // ── APP-128: selecting from the keyboard ──

    // Shift+Down grows a range from where the run started; Shift+Up walks it
    // back. What was selected before the run stays selected.
    function test_shift_down_grows_and_shift_up_shrinks_the_range() {
        seed(4);
        const b = makeBoard();
        const ids = columns(b)[0].ids;
        const other = columns(b)[1].ids[0];
        AppController.setSelectedTaskIds([other]);

        b.cursorTaskId = ids[0];
        b.extendSelection(1);
        b.extendSelection(1);
        compare(b.cursorTaskId, ids[2]);
        verify(AppController.isTaskSelected(ids[0]) && AppController.isTaskSelected(ids[1]) && AppController.isTaskSelected(ids[2]));
        verify(!AppController.isTaskSelected(ids[3]));
        verify(AppController.isTaskSelected(other), "the earlier selection was dropped");

        b.extendSelection(-1);
        verify(!AppController.isTaskSelected(ids[2]), "walking back did not shrink the range");
        verify(AppController.isTaskSelected(ids[1]));

        // A plain move ends the run: the next Shift+Down starts a new one.
        b.moveCursor(0, 1);
        compare(b._selAnchor, "");
        AppController.clearSelection();
    }

    // Shift+Right takes the whole column and steps on, so a second press
    // takes the next column too.
    function test_shift_right_selects_the_column_and_steps_on() {
        seed(2);
        const b = makeBoard();
        const cols = columns(b);
        AppController.clearSelection();

        b.cursorTaskId = cols[0].ids[1];
        b.selectColumnAndStep(1);
        verify(AppController.isTaskSelected(cols[0].ids[0]) && AppController.isTaskSelected(cols[0].ids[1]));
        verify(cols[1].ids.indexOf(b.cursorTaskId) >= 0, "the cursor did not step right");
        compare(b.cursorTaskId, cols[1].ids[1], "the cursor keeps its depth");

        b.selectColumnAndStep(1);
        verify(AppController.isTaskSelected(cols[1].ids[0]) && AppController.isTaskSelected(cols[1].ids[1]));
        compare(AppController.selectionCount, 4);
        AppController.clearSelection();
    }

    // Ctrl+Right moves the whole selection to the next column; with nothing
    // selected it moves the cursor's card, as before.
    function test_ctrl_right_moves_the_selection() {
        seed(2);
        const b = makeBoard();
        const cols = columns(b);
        const a = cols[0].ids[0];
        const c = cols[0].ids[1];
        AppController.setSelectedTaskIds([a, c]);
        b.cursorTaskId = a;

        b.moveSelectionOrCard(1);
        wait(0);
        const after = columns(b);
        verify(after[1].ids.indexOf(a) >= 0 && after[1].ids.indexOf(c) >= 0, "the selection did not move");
        AppController.clearSelection();

        b.cursorTaskId = a;
        b.moveSelectionOrCard(1);
        wait(0);
        verify(columns(b)[2].ids.indexOf(a) >= 0, "the cursor's card did not move alone");
    }

    // A cursor pointing at a card a filter has hidden must not strand the
    // keyboard — the next key adopts something visible.
    function test_a_hidden_cursor_recovers() {
        seed(2);
        const b = makeBoard();
        b.cursorTaskId = "KEY-does-not-exist";

        b.moveCursor(0, 1);

        verify(b.cursorTaskId !== "KEY-does-not-exist");
        compare(b.cursorTaskId, columns(b)[0].ids[0]);
    }
}
