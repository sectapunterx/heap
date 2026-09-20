// Which views survive a view switch.
//
// Every view used to hang off one Loader whose sourceComponent was swapped, so
// switching away destroyed the item: the board lost its scroll position and
// column focus, and the notes editor lost its caret, its scroll and its whole
// undo history. Board, Notes and Docs are kept alive now; the cheap views are
// still rebuilt on demand.
//
// The window itself is instantiated so this tests the real wiring in Main.qml
// rather than a look-alike.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ViewLifetime"
    when: windowShown

    property var win: null
    property string savedView: ""

    function initTestCase() {
        tc.savedView = AppController.currentView;
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        verify(comp.status === Component.Ready, comp.errorString());
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
    }

    function cleanupTestCase() {
        if (tc.win) {
            tc.win.destroy();
            tc.win = null;
        }
        AppController.currentView = tc.savedView;
    }

    function show(view) {
        AppController.currentView = view;
        // The loaders latch on currentViewChanged; give the item a turn to
        // come up before asking for it.
        tryVerify(function () { return tc.win.activeViewItem() !== null; }, 3000,
                  "no item for view " + view);
        return tc.win.activeViewItem();
    }

    // The three that hold state the user would notice losing.
    function test_board_survives_a_round_trip() {
        const first = show("board");
        show("timeline");
        const second = show("board");
        compare(second, first, "the board must be the same item, not a rebuilt one");
    }

    function test_notes_survives_a_round_trip() {
        const first = show("notes");
        show("board");
        const second = show("notes");
        compare(second, first, "the notes editor must keep its caret, scroll and undo history");
    }

    function test_docs_survives_a_round_trip() {
        const first = show("docs");
        show("board");
        const second = show("docs");
        compare(second, first);
    }

    // Board, Notes and Docs coexist once visited — one does not replace another.
    function test_the_kept_views_do_not_evict_each_other() {
        const board = show("board");
        const notes = show("notes");
        const docs = show("docs");
        show("board");

        compare(tc.win.activeViewItem(), board);
        verify(notes !== null);
        verify(docs !== null);
        verify(board !== notes && notes !== docs);
    }

    // Exactly one view is on screen at a time — keeping three alive must not
    // stack them.
    function test_only_the_current_view_is_visible() {
        show("notes");
        const notes = tc.win.activeViewItem();
        verify(notes.visible || notes.parent.visible, "the current view is shown");

        show("board");
        // The notes item still exists, but its loader is hidden.
        verify(!notes.parent.visible, "a view that is not current must be hidden");
    }

    // The cheap views are still rebuilt, which is what keeps three live views
    // from becoming eight.
    function test_a_cheap_view_is_rebuilt() {
        const first = show("timeline");
        show("board");
        const second = show("timeline");
        verify(second !== first, "timeline is cheap to rebuild and is not kept alive");
    }
}
