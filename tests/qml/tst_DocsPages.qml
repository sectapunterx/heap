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

    function makePane() {
        const p = createTemporaryQmlObject(
            'import TodoCpp; DocsPagesPane { width: 900; height: 600 }', host);
        verify(p !== null);
        return p;
    }

    function idsOf(pane) {
        const out = [];
        for (let i = 0; i < pane.rows.length; i++) out.push(pane.rows[i].id);
        return out;
    }

    function test_a_root_page_is_a_row() {
        const id = page("Runbook");

        const pane = makePane();

        verify(idsOf(pane).indexOf(id) >= 0);
    }

    // A deep tree drawn wide open is a wall of rows nobody asked for.
    function test_a_child_is_hidden_until_its_parent_is_opened() {
        const parent = page("Top");
        const child = page("Under", parent);

        const pane = makePane();
        verify(idsOf(pane).indexOf(child) < 0, "closed by default");

        pane.toggle(parent);

        verify(idsOf(pane).indexOf(child) >= 0, "opening the parent shows it");
    }

    function test_toggling_twice_closes_again() {
        const parent = page("Top");
        const child = page("Under", parent);
        const pane = makePane();

        pane.toggle(parent);
        pane.toggle(parent);

        verify(idsOf(pane).indexOf(child) < 0);
    }

    // Indentation is what makes a flat ListView read as a tree.
    function test_a_child_row_is_indented() {
        const parent = page("Top");
        const child = page("Under", parent);
        const pane = makePane();
        pane.toggle(parent);

        let parentDepth = -1, childDepth = -1;
        for (let i = 0; i < pane.rows.length; i++) {
            if (pane.rows[i].id === parent) parentDepth = pane.rows[i].depth;
            if (pane.rows[i].id === child) childDepth = pane.rows[i].depth;
        }
        compare(parentDepth, 0);
        compare(childDepth, 1);
    }

    // So a row knows whether to draw a disclosure triangle.
    function test_a_parent_says_it_has_children() {
        const parent = page("Top");
        page("Under", parent);
        const pane = makePane();

        for (let i = 0; i < pane.rows.length; i++)
            if (pane.rows[i].id === parent) { verify(pane.rows[i].hasChildren); return; }
        fail("the parent row was not found");
    }

    function test_a_leaf_says_it_has_none() {
        const id = page("Alone");
        const pane = makePane();

        for (let i = 0; i < pane.rows.length; i++)
            if (pane.rows[i].id === id) { verify(!pane.rows[i].hasChildren); return; }
        fail("the row was not found");
    }

    // Hiding a match because its parent happens to be closed is the one thing a
    // search must not do, so the filter flattens the tree rather than pruning it.
    function test_the_filter_reaches_into_closed_branches() {
        const parent = page("Top");
        const child = page("BuriedTreasure", parent);

        const pane = makePane();
        verify(idsOf(pane).indexOf(child) < 0, "closed to begin with");

        pane.filter = "BuriedTreasure";

        compare(idsOf(pane), [child]);
    }

    function test_a_filter_matching_nothing_empties_the_tree() {
        page("Runbook");
        const pane = makePane();

        pane.filter = "zzzz-no-such-page";

        compare(pane.rows.length, 0);
    }

    // Creating and deleting must reach the pane without it being rebuilt by
    // hand, or the tree goes stale the moment anything changes.
    function test_the_tree_follows_the_model() {
        const pane = makePane();
        const before = pane.rows.length;

        const id = page("Late");

        compare(pane.rows.length, before + 1);

        AppController.deleteDocPage(id);
        tc.seeded.splice(tc.seeded.indexOf(id), 1);

        compare(pane.rows.length, before);
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
}
