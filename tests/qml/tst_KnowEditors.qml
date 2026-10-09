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

    // DG-071: the line above the note says what it is and how fresh; there
    // is no toolbar.
    function test_the_meta_line_says_note_and_when() {
        const id = note("Meta probe");
        AppController.activeNoteId = id;
        const nv = makeNotes();
        const meta = findChild(nv, "notes-meta");
        verify(meta !== null);
        const edited = I18n.t("know.edited").arg(I18n.t("know.ago.now"));
        tryCompare(meta, "text", Style.quiet ? edited : I18n.t("know.kind.note") + " · " + edited);
        compare(findChild(nv, "notes-mode-toggle"), null, "no Source button");
        compare(findChild(nv, "notes-attach"), null, "no attach button");
    }

    function test_ago_reads_minutes_hours_and_days() {
        const nv = makeNotes();
        const now = new Date(2026, 9, 9, 12, 0, 0);
        compare(nv.agoText(new Date(2026, 9, 9, 11, 59, 40), now), I18n.t("know.ago.now"));
        compare(nv.agoText(new Date(2026, 9, 9, 11, 55, 0), now), I18n.t("know.ago.min").arg(5));
        compare(nv.agoText(new Date(2026, 9, 9, 9, 0, 0), now), I18n.t("know.ago.hours").arg(3));
        compare(nv.agoText(new Date(2026, 9, 8, 9, 0, 0), now), I18n.t("know.ago.yesterday"));
        compare(nv.agoText(null, now), "");
    }

    // DG-070: a page of the former Docs catalogue opens in the document.
    function test_a_doc_page_opens_in_the_document() {
        const id = AppController.newDocPage("Page probe");
        tc.pages.push(id);
        const nv = makeNotes(1200);
        nv.openPage(id);
        const page = findChild(nv, "knowledge-page");
        verify(page.visible);
        compare(page.pageId, id);
        verify(!findChild(nv, "notes-live").visible, "the note gives way to the page");
        verify(!findChild(nv, "notes-links-pane").visible);
        const n = note("Back probe");
        AppController.activeNoteId = n;
        compare(nv.pageId, "", "opening a note closes the page");
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

    // DG-072: the column beside the note — backlinks, external links.
    function test_links_column_shows_backlinks_and_external_links() {
        const target = note("Link target probe", "# Link target probe\n\n[RFC 6585](https://www.rfc-editor.org/rfc/rfc6585 \"429 Too Many Requests\")");
        const other = note("Link source probe", "see [[Link target probe]]");
        AppController.activeNoteId = target;
        const nv = makeNotes(1200);
        verify(nv.showBacklinks, "shown when there is room");
        tryVerify(function () { return nv._incoming.length === 1; });
        compare(nv._incoming[0].noteId, other);
        tryVerify(function () { return nv._external.length === 1; });
        compare(nv._external[0].label, "RFC 6585");
        compare(nv._external[0].title, "429 Too Many Requests");
        verify(findChild(nv, "incoming-" + other) !== null);
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

    // Ctrl+Shift+Z within the debounce: the page's last keystrokes go into it
    // before the redo deletes it again, so the next undo brings them back.
    function test_undo_flushes_the_doc_page_editor() {
        const id = AppController.newDocPage("Flush probe");
        tc.pages.push(id);
        const pane = createTemporaryQmlObject('import TodoCpp; MdEditorPane { width: 800; height: 400 }', host);
        pane.pageId = id;
        AppController.deleteDocPage(id);
        AppController.undo();
        compare(AppController.docPageBody(id), "# Flush probe\n\n");
        const area = findChild(pane, "docpage-text");
        area.forceActiveFocus();
        area.cursorPosition = area.length;
        keyClick(Qt.Key_Z);
        verify(pane._dirty, "the keystroke is still only in the editor");
        AppController.redo();
        wait(400);
        AppController.undo();
        compare(AppController.docPageBody(id), "# Flush probe\n\nz");
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
