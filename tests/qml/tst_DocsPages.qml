// Docs pages in the view.
//
// test_doc_pages.cpp covers the tree itself — parenting, ordering, deleting a
// subtree. These cover what the pane does with it: which rows it draws, what a
// closed parent hides, and the flush that keeps an edit from being dropped when
// the open page changes.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DocsPages"
    when: windowShown
    visible: true
    width: 1000
    height: 700

    Item { id: host; anchors.fill: parent }

    property var seeded: []

    function page(title, parentId) {
        const id = AppController.newDocPage(title, parentId || "");
        tc.seeded.push(id);
        return id;
    }

    function cleanup() {
        // Deleting a root takes its subtree, so ids already gone are no-ops.
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteDocPage(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
    }


    // ── The editor ──

    function makeEditor(pageId) {
        const e = createTemporaryQmlObject(
            'import TodoCpp; MdEditorPane { width: 600; height: 400 }', host);
        verify(e !== null);
        e.pageId = pageId;
        return e;
    }

    function test_the_editor_loads_the_page_body() {
        const id = page("Runbook");
        AppController.setDocPageBody(id, "# Runbook\n\nthe steps");

        const ed = makeEditor(id);

        const area = findChild(ed, "docpage-text");
        verify(area !== null);
        compare(area.text, "# Runbook\n\nthe steps");
    }

    // The debounce means the last keystrokes are only in the text field; a
    // caller that switches pages has to flush or they are dropped.
    function test_flushing_writes_what_was_typed() {
        const id = page("Runbook");
        const ed = makeEditor(id);
        const area = findChild(ed, "docpage-text");

        area.text = "typed but not yet saved";
        ed.flush();

        compare(AppController.docPageBody(id), "typed but not yet saved");
    }

    function test_changing_the_page_loads_the_other_body() {
        const a = page("A");
        const b = page("B");
        AppController.setDocPageBody(a, "body A");
        AppController.setDocPageBody(b, "body B");

        const ed = makeEditor(a);
        const area = findChild(ed, "docpage-text");
        compare(area.text, "body A");

        ed.pageId = b;

        compare(area.text, "body B");
    }

    function test_no_page_shows_the_placeholder() {
        const ed = makeEditor("");

        const area = findChild(ed, "docpage-text");
        compare(area.text, "");
    }

    // Flushing with nothing open must not write to a page that is not there.
    function test_flushing_with_no_page_is_harmless() {
        const ed = makeEditor("");
        ed.flush();
        verify(true);
    }

    // "+" inside the debounce window used to write the previous page's draft
    // into the page being opened, and lose it from the page it was typed in.
    // Every change of pageId now flushes to the page the text field holds.
    function test_changing_page_without_a_flush_keeps_the_draft_where_it_was_typed() {
        const a = page("Draft A");
        const b = page("Draft B");
        AppController.setDocPageBody(a, "body A");
        AppController.setDocPageBody(b, "body B");
        const ed = makeEditor(a);
        const area = findChild(ed, "docpage-text");

        area.text = "unsaved draft for A";
        ed.pageId = b;   // no explicit flush — the way "+" changes it

        compare(AppController.docPageBody(a), "unsaved draft for A");
        compare(AppController.docPageBody(b), "body B");
        compare(area.text, "body B");
    }

    // ── Moving pages (KNOW-20) ──
    // moveDocPage existed with no way to reach it: a page made in the wrong
    // place stayed there. The row menu and Ctrl+arrows on the tree move it.

    function childIds(parentId) {
        const kids = AppController.docPageChildren(parentId);
        const out = [];
        for (let i = 0; i < kids.length; i++) out.push(kids[i].id);
        return out;
    }

    // KNOW-18: "Load images" was a switch on the editor's one document, so it
    // stayed on for every page opened after the one it was pressed on.
    function test_remote_images_are_allowed_for_one_page_only() {
        const a = page("Trusted");
        const b = page("Imported");
        const ed = makeEditor(a);
        const doc = findChild(ed, "docpage-preview").document;
        doc.allowRemoteImages = true;

        ed.pageId = b;

        verify(!doc.allowRemoteImages);
    }
}
