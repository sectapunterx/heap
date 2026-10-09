// Knowledge (APP-269): Docs and Notes in one screen — the reference links,
// pages and snippets in the list beside the notes, the note edited where it
// is drawn, and the side with the tasks in the note and what links here.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Knowledge"
    when: windowShown
    visible: true
    width: 1300
    height: 800

    Item { id: host; anchors.fill: parent }

    property string _docs: ""
    function initTestCase() {
        _docs = AppController.docsState;
        AppController.docsState = JSON.stringify({
            sections: [{ id: "s", title: "Ref", items: [{ ref: "RFC 9110", title: "HTTP Semantics", url: "https://www.rfc-editor.org/rfc/rfc9110", pinned: true }] }],
            snippets: [{ title: "Run the stand", lang: "sh", code: "make up" }],
            contacts: []
        });
    }
    function cleanupTestCase() { AppController.docsState = tc._docs; }

    function make() {
        const nv = createTemporaryQmlObject('import TodoCpp; NotesView { anchors.fill: parent }', host);
        verify(nv !== null);
        return nv;
    }
    function rowsOf(nv, kind) {
        const list = findChild(nv, "notes-list-pane");
        list.rebuildNow();
        return list.rows.filter((r) => r.kind === kind);
    }

    function test_docs_sit_in_the_list_beside_the_notes() {
        const nv = make();
        const refs = rowsOf(nv, "ref");
        compare(refs.length, 1);
        compare(refs[0].tag, "RFC");
        verify(refs[0].title.indexOf("9110") >= 0);
        compare(rowsOf(nv, "snippet").length, 1);
        // The search finds a reference by its words.
        findChild(nv, "notes-list-pane").filter = "semantics";
        compare(rowsOf(nv, "ref").length, 1);
        compare(rowsOf(nv, "snippet").length, 0);
        findChild(nv, "notes-list-pane").filter = "";
    }

    function test_no_modes_the_note_is_edited_where_it_is_drawn() {
        const nv = make();
        compare(nv.viewMode, "live");
        const live = findChild(nv, "notes-live");
        verify(live.visible);
        verify(!findChild(nv, "notesEditor").visible);
        // The whole source is one switch away and back.
        nv.viewMode = "edit";
        verify(findChild(nv, "notesEditor").visible);
        nv.viewMode = "live";
    }

    function test_a_task_linking_the_note_is_a_backlink() {
        const noteId = AppController.newNote("Knowledge backlink");
        const draft = AppController.quickTaskDraft("linked task", new Date());
        draft.desc = "see [[Knowledge backlink]]";
        AppController.saveTask(draft);
        const nv = make();
        nv.showBacklinks = true;
        nv._refreshLinks();
        verify(nv._taskLinks.some((t) => t.id === draft.id), "the task is not in 'Linked here'");
        // And the note names the task back: "Mentioned in" on the task.
        AppController.setNoteBody(noteId, "about " + draft.id);
        verify(AppController.notesMentioningTask(draft.id).some((n) => n.id === noteId));
        compare(AppController.noteTaskRefs("about " + draft.id)[0].id, draft.id);
        AppController.deleteTask(draft.id);
        AppController.deleteNote(noteId);
    }
}
