// NotesView (qml/NotesView.qml) persistence.
//
// The view debounces its write to AppController.notesState by 250 ms, and
// Main.qml swaps views through a Loader — so the item is destroyed on every
// view switch. These cases pin the flush that keeps the last keystrokes:
// on destruction, and on quit (where destruction order against the
// AppController singleton is not defined).
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "NotesView"
    when: windowShown
    visible: true
    width: 600
    height: 400

    Item { id: host; anchors.fill: parent }

    // createTemporaryQmlObject() destroys at the end of the test function,
    // which is too late to observe the flush — these cases destroy by hand.
    function make() {
        const nv = Qt.createQmlObject('import TodoCpp; NotesView { anchors.fill: parent }', host, "tst_NotesView.make");
        verify(nv !== null);
        // Component.onCompleted loads notesState into the editor and only then
        // arms the persistence path.
        tryVerify(function () { return nv._loadedOnce; });
        return nv;
    }

    function editorOf(nv) {
        const ed = findChild(nv, "notesEditor");
        verify(ed !== null, "notesEditor not found — objectName renamed?");
        return ed;
    }

    function init() {
        // The QML test profile persists between runs, so each case starts from
        // a known canvas rather than whatever the previous one left behind.
        AppController.notesState = "";
    }

    // A keystroke inside the debounce window survives the view switch that
    // destroys the item. Without the flush this is the data-loss bug: the
    // 250 ms timer is destroyed with its view and never fires.
    function test_destruction_flushes_pending_edit() {
        const nv = make();
        const ed = editorOf(nv);

        ed.text = "# pending\n\nnot yet debounced";
        // Precondition: still only in the editor.
        compare(AppController.notesState, "");

        nv.destroy();
        wait(0);
        compare(AppController.notesState, "# pending\n\nnot yet debounced");
    }

    // aboutToQuit flushes the same pending edit while both the view and the
    // AppController singleton are still alive.
    function test_about_to_quit_flushes_pending_edit() {
        const nv = make();
        const ed = editorOf(nv);

        ed.text = "quit while typing";
        compare(AppController.notesState, "");

        // The real signal cannot be emitted from a test without ending the
        // run, so drive the handler the Connections block installs.
        nv._flushPending();
        compare(AppController.notesState, "quit while typing");

        nv.destroy();
        wait(0);
    }

    // The debounced path still works on its own: no destruction, no manual
    // flush, the timer fires and writes.
    function test_debounced_save_still_writes() {
        const nv = make();
        const ed = editorOf(nv);

        ed.text = "debounced";
        tryCompare(AppController, "notesState", "debounced");

        nv.destroy();
        wait(0);
    }

    // A flush with nothing pending must not write — otherwise destroying a
    // freshly opened view would stamp an empty canvas over the real note.
    function test_flush_without_pending_edit_is_a_noop() {
        AppController.notesState = "existing note";
        const nv = make();

        nv._flushPending();
        compare(AppController.notesState, "existing note");

        nv.destroy();
        wait(0);
        compare(AppController.notesState, "existing note");
    }
}
