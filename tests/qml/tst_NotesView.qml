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

    // ── The bug report: text written with no note open, then "+" ──
    //
    // Typing straight into the editor, or capturing with Ctrl+Shift+N, left the
    // text in notesState with no note behind it: shown, listed nowhere, gone
    // after a restart. And "+" pressed inside the 250 ms debounce replaced the
    // unsaved draft with the new note's heading.

    function noteHolding(needle) {
        const m = AppController.notes;
        for (let i = 0; i < m.rowCount(); i++) {
            const id = String(m.data(m.index(i, 0), m.roleOf("id")));
            if (AppController.noteBody(id).indexOf(needle) >= 0) return id;
        }
        return "";
    }

    property var madeNotes: []

    function cleanup() {
        for (let i = 0; i < tc.madeNotes.length; i++) AppController.deleteNote(tc.madeNotes[i]);
        tc.madeNotes = [];
    }

    // "+" inside the debounce window: the draft must stay in the note it was
    // typed in, and the new note must not inherit it.
    function test_plus_inside_the_debounce_keeps_the_draft() {
        const first = AppController.newNote("plus-race first");
        tc.madeNotes.push(first);
        const nv = make();
        const ed = editorOf(nv);

        ed.text = "# plus-race first\n\ndraft typed moments ago";
        // Precondition: the debounce has not fired, so it is only in the editor.
        verify(AppController.noteBody(first).indexOf("draft typed moments ago") < 0);

        const second = AppController.newNote("plus-race second");
        tc.madeNotes.push(second);

        verify(AppController.noteBody(first).indexOf("draft typed moments ago") >= 0,
               "the draft has to land in the note it was typed into");
        verify(AppController.noteBody(second).indexOf("draft typed moments ago") < 0,
               "and not in the note that was just made");
        nv.destroy();
        wait(0);
    }

    // No note open at all: typing makes one, and "+" afterwards keeps it.
    function test_typing_with_no_note_open_then_plus_keeps_both() {
        AppController.activeNoteId = "";
        AppController.notesState = "";
        const nv = make();
        const ed = editorOf(nv);

        const needle = "orphan-draft-" + Date.now();
        ed.text = needle;
        const made = AppController.newNote("after-orphan");
        tc.madeNotes.push(made);

        const holder = noteHolding(needle);
        verify(holder.length > 0, "the typed text has to become a note, not vanish");
        verify(holder !== made, "and a note of its own, not the one \"+\" made");
        tc.madeNotes.push(holder);
        nv.destroy();
        wait(0);
    }

    // Quick capture with no note open goes to a listed note.
    function test_quick_capture_with_no_note_open_is_listed() {
        AppController.activeNoteId = "";
        AppController.notesState = "";

        const needle = "captured-" + Date.now();
        AppController.appendNoteEntry(needle);

        const holder = noteHolding(needle);
        verify(holder.length > 0, "a captured note has to be a real note");
        compare(AppController.activeNoteId, holder);
        tc.madeNotes.push(holder);
    }
}
