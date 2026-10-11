// The idiot test of the task document (0.8.4 acceptance, IDIOT-DOC-*): with
// a side panel open, the keys never reach the view behind its scrim, the
// keyboard always comes back to the panel, and its hints are true in the
// state it opens in. Drives the real Main.qml.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "PanelKeys"
    when: windowShown

    property var win: null
    property var seeded: []
    readonly property string probe: "panelprobe"

    function initTestCase() {
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        verify(comp.status === Component.Ready, comp.errorString());
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tc.win.width = 1456;
        tc.win.height = 939;
        AppController.resetAllShortcuts();
        wait(1200);   // splash
        tc.win.requestActivate();
        AppController.currentView = "board";
        tryVerify(function () { return tc.win.activeViewItem() !== null; }, 3000);
        wait(100);
    }
    function cleanupTestCase() {
        if (tc.win) tc.win.destroy();
        tc.win = null;
    }
    function init() {
        tc.seeded = [];
        for (let i = 0; i < 3; i++) {
            const d = AppController.newTaskDraft("todo");
            d._isNew = true;
            d.id = "PANEL-" + i;
            d.title = tc.probe + " card " + i;
            AppController.saveTask(d);
            tc.seeded.push(d.id);
        }
        closeAll();
        AppController.currentView = "board";
        tc.win.searchText = tc.probe;
        wait(50);
    }
    function cleanup() {
        closeAll();
        AppController.clearSelection();
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
        tc.win.searchText = "";
    }

    function find(root, pred) {
        if (!root) return null;
        if (pred(root)) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = find(kids[i], pred);
            if (r) return r;
        }
        return null;
    }
    function byName(root, name) { return find(root, function (it) { return it.objectName === name; }); }
    function popups() {
        const out = [];
        const cd = tc.win.contentData;
        for (let i = 0; i < cd.length; i++) {
            const o = cd[i];
            if (o && o.opened !== undefined && o.open !== undefined) out.push(o);
        }
        return out;
    }
    function closeAll() {
        const ps = popups();
        for (let i = 0; i < ps.length; i++) if (ps[i].opened) ps[i].close();
        const doc = byName(tc.win.contentItem, "task-doc");
        if (doc && doc.opened) doc.close();
    }
    function doc() { return byName(tc.win.contentItem, "task-doc"); }
    function openDoc(id) {
        tc.win.openTask(id);
        const d = doc();
        tryCompare(d, "opened", true);
        tryVerify(function () { return tc.win._focusInPanel; }, 1000, "the keyboard is not in the document");
        return d;
    }
    function exists(id) { return !!AppController.taskById(id).id; }
    function typeText(t) { for (let i = 0; i < t.length; i++) keyClick(t[i]); }
    function focusName() { const f = tc.win.activeFocusItem; return String(f) + " " + (f ? f.objectName : ""); }

    // IDIOT-DOC-2/3, PERSONA-9: Delete, e, Space, Ctrl+A, j never touch the
    // board behind the document.
    function test_view_keys_stand_down_behind_the_document() {
        const d = openDoc("PANEL-0");
        keyClick(Qt.Key_Delete);
        keyClick(Qt.Key_E);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_A, Qt.ControlModifier);
        keyClick(Qt.Key_Delete);
        keyClick(Qt.Key_J);
        wait(100);
        for (let i = 0; i < tc.seeded.length; i++) {
            verify(exists(tc.seeded[i]), tc.seeded[i] + " was deleted behind the document");
            verify(!AppController.taskById(tc.seeded[i]).archived, tc.seeded[i] + " was archived behind the document");
        }
        compare(AppController.selectionCount, 0, "cards were selected behind the document");
        verify(d.opened);
    }

    // The owner's report: "/" from the hint opened the board's filter and
    // the task could not be reached again without the mouse. It opens the
    // insert menu in the text now.
    function test_slash_opens_the_insert_menu_not_the_filter() {
        const d = openDoc("PANEL-0");
        keyClick("/");
        const search = byName(tc.win.contentItem, "topbar-search");
        const body = byName(d, "task-doc-body");
        tryVerify(function () { return body.editing && String(body.editor.text).indexOf("/") >= 0; }, 1000,
                  "/ did not open the insert line: " + focusName());
        verify(!search.activeFocus, "/ went to the filter");
        compare(AppController.taskById("PANEL-0").title, tc.probe + " card 0", "/ was typed into the title");
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_Escape);
        tryCompare(d, "opened", false, 1000, "Esc did not get back out of the document");
    }

    // IDIOT-DOC-10: the "Done d" hint is true as the document opens.
    function test_d_is_done_in_the_document() {
        openDoc("PANEL-1");
        keyClick(Qt.Key_D);
        tryCompare(AppController.taskById("PANEL-1"), "status", "done");
        compare(AppController.taskById("PANEL-0").status, "todo", "d acted on a card behind");
    }

    // IDIOT-DOC-4: after a popup the keyboard comes back to the document,
    // and Esc closes it.
    function test_keyboard_comes_back_after_the_palette() {
        const d = openDoc("PANEL-0");
        const pal = popups().filter(function (p) { return String(p).indexOf("CommandPalette") === 0; })[0];
        verify(pal);
        keyClick(Qt.Key_K, Qt.ControlModifier);
        tryCompare(pal, "opened", true);
        keyClick(Qt.Key_Escape);
        tryCompare(pal, "opened", false);
        tryVerify(function () { return tc.win._focusInPanel; }, 1000, "the keyboard stayed on the board");
        wait(50);
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return !d.opened; }, 1000, "Esc back did not close the document: " + focusName());
    }

    // IDIOT-DOC-1: the body typed in one task never shows in the next one
    // whose stored text is the same (both empty).
    function test_the_body_of_one_task_does_not_leak_into_the_next() {
        const d = openDoc("PANEL-0");
        const body = byName(d, "task-doc-body");
        body.focusEditor();
        const field = byName(body, "md-block-field");
        tryVerify(function () { return field.visible && field.activeFocus; }, 1000);
        typeText("secret of zero");
        d.close();
        tryVerify(function () { return String(AppController.taskById("PANEL-0").desc).indexOf("secret of zero") >= 0; }, 2000);
        openDoc("PANEL-1");
        compare(body.source.text, "", "the last task's text is in this one");
        d.close();
        compare(String(AppController.taskById("PANEL-1").desc || ""), "");
    }

    // IDIOT-DOC-6: Esc in a chip's field gives the keyboard back.
    function test_esc_in_a_chip_field_hands_the_keyboard_back() {
        const d = openDoc("PANEL-0");
        const chips = byName(d, "task-doc-chips");
        verify(chips);
        const field = find(chips, function (it) { return it.cursorPosition !== undefined && it.visible === false; });
        if (!field) skip("no text chip in this layout");
        field.parent.clicked();
        tryVerify(function () { return field.activeFocus; }, 1000);
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return !field.activeFocus && tc.win._focusInPanel; }, 1000,
                  "a hidden field kept the keyboard: " + focusName());
        keyClick(Qt.Key_Escape);
        tryCompare(d, "opened", false);
    }
}
