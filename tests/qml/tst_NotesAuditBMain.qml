// SHELL-1 through Main: the palette lists the notes.* actions and hands them
// to Main.runCommand, which used to log "palette: no command" and do nothing.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "NotesAuditBMain"
    when: windowShown

    property var win: null

    function initTestCase() {
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tc.win.width = 1456;
        tc.win.height = 939;
        wait(1200);
    }
    function cleanupTestCase() {
        AppController.currentView = "board";
        if (tc.win) tc.win.destroy();
    }

    function test_palette_notes_new_makes_a_note() {
        AppController.currentView = "board";
        const count = AppController.notes.rowCount();

        tc.win.runCommand("notes.new");

        tryCompare(AppController, "currentView", "notes");
        tryVerify(function () { return AppController.notes.rowCount() === count + 1; }, 3000,
                  "notes.new from the palette did nothing");
        AppController.deleteNote(AppController.activeNoteId);
        AppController.clearPendingUndo();
    }
}
