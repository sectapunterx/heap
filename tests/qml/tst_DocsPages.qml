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

    // Design audit DES-3: the tree is on the Tab path; the arrows walk it and
    // fold / unfold, Enter opens the page, the menu key opens the row menu.
    function test_the_keyboard_walks_the_tree() {
        const parent = page("aaa kb parent");
        const child = page("kb child", parent);
        const pane = makePane();
        pane.filter = "";
        const tree = findChild(pane, "docpage-tree");
        verify(tree.activeFocusOnTab, "the page tree is not on the Tab path");
        tree.forceActiveFocus(Qt.TabFocusReason);
        const at = idsOf(pane).indexOf(parent);
        verify(at >= 0);
        tree.currentIndex = at;
        verify(!pane.isExpanded(parent));
        keyClick(Qt.Key_Right);
        verify(pane.isExpanded(parent), "→ did not unfold the page");
        verify(idsOf(pane).indexOf(child) >= 0);
        keyClick(Qt.Key_Left);
        verify(!pane.isExpanded(parent), "← did not fold the page");
        keyClick(Qt.Key_Return);
        compare(AppController.activeDocPageId, parent);
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

    function test_a_page_moves_up_and_down_among_its_siblings() {
        const top = page("move top");
        const a = page("A", top);
        const b = page("B", top);
        const c = page("C", top);
        const pane = makePane();

        verify(!pane.canMove(a, "up"));
        verify(!pane.canMove(c, "down"));
        pane.movePage(c, "up");
        compare(childIds(top), [a, c, b]);
        pane.movePage(a, "down");
        compare(childIds(top), [c, a, b]);
        pane.movePage(a, "down");
        compare(childIds(top), [c, b, a]);
    }

    function test_a_page_nests_under_the_one_above_and_back_out() {
        const top = page("nest top");
        const a = page("A", top);
        const b = page("B", top);
        const pane = makePane();

        verify(!pane.canMove(top, "out"), "a root page has nowhere further out");
        verify(!pane.canMove(a, "in"), "the first sibling has nothing above it");
        pane.movePage(b, "in");
        compare(childIds(a), [b]);
        compare(childIds(top), [a]);
        pane.movePage(b, "out");
        compare(childIds(top), [a, b], "out lands just below its old parent");
        pane.movePage(a, "out");
        const roots = childIds("");
        compare(roots.indexOf(a), roots.indexOf(top) + 1);
    }

    function test_ctrl_arrows_move_the_current_page() {
        const top = page("aaa kb move top");
        const a = page("A", top);
        const b = page("B", top);
        const pane = makePane();
        pane.filter = "";
        pane.toggle(top);
        const tree = findChild(pane, "docpage-tree");
        tree.forceActiveFocus(Qt.TabFocusReason);
        tree.currentIndex = idsOf(pane).indexOf(b);

        keyClick(Qt.Key_Up, Qt.ControlModifier);
        compare(childIds(top), [b, a]);
        compare(pane.rows[tree.currentIndex].id, b, "the cursor stays on the page that moved");
        keyClick(Qt.Key_Down, Qt.ControlModifier);
        compare(childIds(top), [a, b]);
        keyClick(Qt.Key_Right, Qt.ControlModifier);
        compare(childIds(a), [b]);
        keyClick(Qt.Key_Left, Qt.ControlModifier);
        compare(childIds(top), [a, b]);
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
