// The notes and doc page editors, driven with real keys (audit 2026-09-30).
//
// KNOW-5: formatting keys wrap the selection; Tab and heading cycling act on
// every selected line. KNOW-14: the doc page editor has the same keyboard.
// KNOW-15: the page head follows a rename. KNOW-7: the list is reachable at
// any width and the header names the open note. KNOW-8: the links pane shows
// who links here, and a link to an existing note is not "broken".
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "KnowEditors"
    when: windowShown
    visible: true
    width: 900
    height: 600

    Item { id: host; anchors.fill: parent }

    property var seeded: []
    property var pages: []

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteNote(tc.seeded[i]);
        tc.seeded = [];
        for (let i = 0; i < tc.pages.length; i++) AppController.deleteDocPage(tc.pages[i]);
        tc.pages = [];
    }

    function makeNotes(w) {
        const nv = createTemporaryQmlObject('import TodoCpp; NotesView { width: ' + (w || 900) + '; height: 600 }', host);
        tryVerify(function () { return nv._loadedOnce; });
        return nv;
    }
    function note(title, body) {
        const id = AppController.newNote(title);
        if (body !== undefined) AppController.setNoteBody(id, body);
        tc.seeded.push(id);
        return id;
    }

    function test_ctrl_b_wraps_the_selection_in_notes() {
        const id = note("sel probe", "one word here");
        AppController.activeNoteId = id;
        const nv = makeNotes();
        const ed = findChild(nv, "notesEditor");
        ed.forceActiveFocus();
        ed.select(4, 8);
        keyClick(Qt.Key_B, Qt.ControlModifier);
        compare(ed.text, "one **word** here");
        ed.select(0, 3);
        keyClick(Qt.Key_K, Qt.ControlModifier);
        compare(ed.text, "[one]() **word** here");
    }

    function test_tab_indents_every_selected_line() {
        const id = note("tab probe", "- a\n- b\n- c");
        AppController.activeNoteId = id;
        const nv = makeNotes();
        const ed = findChild(nv, "notesEditor");
        ed.forceActiveFocus();
        ed.select(0, ed.length);
        keyClick(Qt.Key_Tab);
        compare(ed.text, "  - a\n  - b\n  - c");
    }

    function test_slash_date_leaves_urls_alone() {
        const id = note("slash probe", "");
        AppController.activeNoteId = id;
        const nv = makeNotes();
        const ed = findChild(nv, "notesEditor");
        ed.forceActiveFocus();
        ed.text = "see http://x.com/now";
        ed.cursorPosition = ed.length;
        keyClick(Qt.Key_Return);
        compare(ed.text, "see http://x.com/now\n", "the URL is kept and Enter still ends the line");
        // A slash word of its own still expands.
        ed.text = "due /today";
        ed.cursorPosition = ed.length;
        keyClick(Qt.Key_Tab);
        verify(/^due \d{4}-\d{2}-\d{2}$/.test(ed.text), ed.text);
    }

    function test_the_header_names_the_open_note() {
        const id = note("Header probe");
        AppController.activeNoteId = id;
        const nv = makeNotes();
        tryCompare(findChild(nv, "notes-title"), "text", "Header probe");
    }

    function test_the_list_is_reachable_when_narrow() {
        const nv = makeNotes(700);
        const list = findChild(nv, "notes-list-pane");
        verify(list.visible, "700 px still has room for the list");
        nv.width = 480;
        verify(!list.visible, "folds away when there is no room");
        nv.toggleList();
        verify(list.visible, "and the toggle brings it back");
    }

    function test_links_pane_shows_incoming_and_resolves_outgoing() {
        const target = note("Link target probe", "# Link target probe\n");
        const other = note("Link source probe", "see [[Link target probe]] and [[Nowhere probe]]");
        AppController.activeNoteId = target;
        const nv = makeNotes();
        nv.showBacklinks = true;
        compare(nv._incoming.length, 1);
        compare(nv._incoming[0].noteId, other);

        AppController.activeNoteId = other;
        tryVerify(function () { return nv._outgoing.length === 2; });
        const byTarget = ({});
        for (let i = 0; i < nv._outgoing.length; i++) byTarget[nv._outgoing[i].target] = nv._outgoing[i];
        verify(byTarget["Link target probe"].resolved, "an existing note is not a broken link");
        verify(!byTarget["Nowhere probe"].resolved);
    }

    function test_doc_page_editor_has_the_markdown_keyboard() {
        const id = AppController.newDocPage("Keys probe");
        tc.pages.push(id);
        AppController.setDocPageBody(id, "- first");
        const pane = createTemporaryQmlObject('import TodoCpp; MdEditorPane { width: 800; height: 400 }', host);
        pane.pageId = id;
        const area = findChild(pane, "docpage-text");
        area.forceActiveFocus();
        area.cursorPosition = area.length;
        keyClick(Qt.Key_Return);
        compare(area.text, "- first\n- ");
        area.text = "bold me";
        area.select(0, 4);
        keyClick(Qt.Key_B, Qt.ControlModifier);
        compare(area.text, "**bold** me");
    }

    function test_doc_page_head_follows_a_rename() {
        const id = AppController.newDocPage("Before probe");
        tc.pages.push(id);
        const pane = createTemporaryQmlObject('import TodoCpp; MdEditorPane { width: 800; height: 400 }', host);
        pane.pageId = id;
        const head = findChild(pane, "docpage-title");
        compare(head.text, "Before probe");
        AppController.renameDocPage(id, "After probe");
        compare(head.text, "After probe");
    }
}
