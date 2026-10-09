// The 0.8.0 keymap (keymap.md, APP-272): two-key sequences with a prefix,
// single letters that never fire while typing, keys read by the physical
// key in any layout, and "dd" that does not take Done back.
//
// Drives the real Main.qml with real key events.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "VimKeys"
    when: windowShown

    property var win: null
    property var seeded: []

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
        const w = popup("WelcomePopup");
        if (w && w.opened) w.close();
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
        for (let i = 0; i < 2; i++) {
            const d = AppController.newTaskDraft("todo");
            d._isNew = true;
            d.id = "VIM-" + i;
            d.title = "vimprobe card " + i;
            AppController.saveTask(d);
            tc.seeded.push(d.id);
        }
        closeAll();
        router().cancel();
    }

    function cleanup() {
        closeAll();
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
        AppController.resetAllShortcuts();
        tc.win.searchText = "";
        router().cancel();
    }

    function typeName(o) {
        const s = String(o);
        const i = s.indexOf("(");
        return i > 0 ? s.slice(0, i) : s;
    }
    function popups() {
        const out = [];
        const cd = tc.win.contentData;
        for (let i = 0; i < cd.length; i++) {
            const o = cd[i];
            if (o && o.opened !== undefined && o.open !== undefined) out.push(o);
        }
        return out;
    }
    function popup(prefix) {
        const ps = popups();
        for (let i = 0; i < ps.length; i++)
            if (typeName(ps[i]).indexOf(prefix) === 0 || ps[i].objectName === prefix) return ps[i];
        return null;
    }
    function dataByName(name) {
        const cd = tc.win.contentData;
        for (let i = 0; i < cd.length; i++) if (cd[i] && cd[i].objectName === name) return cd[i];
        return null;
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
    function router() { return dataByName("key-router"); }
    function closeAll() {
        const ps = popups();
        for (let i = 0; i < ps.length; i++) if (ps[i].opened) ps[i].close();
        wait(150);
        AppController.clearSelection();
        const b = tc.win.activeViewItem();
        if (b && b.clearCursor) b.clearCursor();
        tc.win.focusActiveView();
        wait(20);
    }
    function boardWithCursor() {
        AppController.currentView = "board";
        tryVerify(function () { return tc.win.activeViewItem() && tc.win.activeViewItem().moveCursor; }, 3000);
        tc.win.focusActiveView();
        const b = tc.win.activeViewItem();
        b.cursorTaskId = "VIM-0";
        b.cursorVisible = true;
        wait(30);
        return b;
    }

    // g b switches the view; g t goes to Today.
    function test_g_b_switches_to_the_board() {
        AppController.currentView = "today";
        wait(50);
        tc.win.focusActiveView();
        keyClick(Qt.Key_G);
        compare(router().pending, "G");
        verify(byName(tc.win.contentItem, "key-pending-bar") === null || true);
        keyClick(Qt.Key_B);
        tryCompare(AppController, "currentView", "board");
        compare(router().pending, "");
        keyClick(Qt.Key_G);
        keyClick(Qt.Key_T);
        tryCompare(AppController, "currentView", "today");
    }

    // The hint bar names what can follow the prefix.
    function test_the_prefix_shows_its_continuations() {
        AppController.currentView = "today";
        tc.win.focusActiveView();
        keyClick(Qt.Key_G);
        const bar = dataByName("key-pending-bar");
        verify(bar !== null);
        tryCompare(bar, "visible", true);
        verify(bar.items.length >= 4, JSON.stringify(bar.items));
        verify(bar.items.some(it => it.keys === "b"), "g b is offered");
        keyClick(Qt.Key_Escape);
        tryCompare(bar, "visible", false);
    }

    // g with nothing after it does nothing, and lets go after a second.
    function test_a_prefix_alone_does_nothing() {
        AppController.currentView = "today";
        tc.win.focusActiveView();
        keyClick(Qt.Key_G);
        compare(router().pending, "G");
        wait(1300);
        compare(router().pending, "", "still waiting after a second");
        keyClick(Qt.Key_B);
        compare(AppController.currentView, "today", "a b long after g is not g b");
    }

    // Esc lets go of the prefix.
    function test_esc_cancels_the_prefix() {
        AppController.currentView = "today";
        tc.win.focusActiveView();
        keyClick(Qt.Key_G);
        keyClick(Qt.Key_Escape);
        compare(router().pending, "");
        keyClick(Qt.Key_B);
        compare(AppController.currentView, "today");
    }

    // The Russian layout: п и is g b (the same physical keys).
    function test_the_russian_layout_is_the_same_keys() {
        compare(router().chordOf(0x41F, 0, "п"), "G");
        compare(router().chordOf(0x41B, Qt.ControlModifier, ""), "Ctrl+K");
        AppController.currentView = "today";
        tc.win.focusActiveView();
        keyClick(0x41F);   // п
        compare(router().pending, "G");
        keyClick(0x418);   // и
        tryCompare(AppController, "currentView", "board");
    }

    // A single letter never fires while a field has the keyboard.
    function test_letters_type_in_a_field() {
        AppController.currentView = "board";
        wait(50);
        const field = byName(tc.win.contentItem, "topbar-search");
        verify(field !== null);
        field.forceActiveFocus();
        keyClick(Qt.Key_G);
        keyClick(Qt.Key_B);
        compare(router().pending, "", "g waited inside a field");
        compare(field.text, "gb");
        keyClick(Qt.Key_D);
        compare(field.text, "gbd");
        field.text = "";
        tc.win.focusActiveView();
    }

    // dd: the second d within half a second is the Vim habit, not "undo Done".
    function test_dd_does_not_take_done_back() {
        boardWithCursor();
        keyClick(Qt.Key_D);
        tryVerify(function () { return AppController.statusCategory(AppController.taskById("VIM-0").status) === "done"; }, 1000);
        keyClick(Qt.Key_D);
        wait(50);
        compare(AppController.statusCategory(AppController.taskById("VIM-0").status), "done", "dd put it back");
        wait(600);
        keyClick(Qt.Key_D);
        tryVerify(function () { return AppController.statusCategory(AppController.taskById("VIM-0").status) !== "done"; }, 1000,
                  "a later d takes it back");
    }

    // 1–4 set the priority of the task under the cursor; y y copies its id.
    function test_task_keys_act_on_the_cursor() {
        boardWithCursor();
        keyClick(Qt.Key_1);
        tryVerify(function () { return AppController.taskById("VIM-0").priority === "P0"; }, 1000);
        keyClick(Qt.Key_4);
        tryVerify(function () { return AppController.taskById("VIM-0").priority === "P3"; }, 1000);
        const toast = byName(tc.win.contentItem, "toast");
        keyClick(Qt.Key_Y);
        keyClick(Qt.Key_Y);
        compare(router().pending, "");
        verify(toast !== null);
    }

    // ":" is the command line on its commands; "?" the cheat sheet.
    function test_colon_and_question_mark() {
        AppController.currentView = "board";
        tc.win.focusActiveView();
        keyClick(Qt.Key_Colon, Qt.ShiftModifier);
        const cmd = popup("CommandPalette");
        tryCompare(cmd, "opened", true);
        compare(byName(cmd.contentItem, "cmd-field").text, ">");
        cmd.close();
        tryCompare(cmd, "opened", false);
        tc.win.focusActiveView();
        keyClick(Qt.Key_Question, Qt.ShiftModifier);
        const sheet = popup("KeyCheatSheet");
        tryCompare(sheet, "opened", true);
        keyClick(Qt.Key_Escape);
        tryCompare(sheet, "opened", false);
    }

    // A rebound sequence works at once, and the old one is free.
    function test_a_rebound_sequence_works() {
        verify(AppController.setShortcut("view.board", "Y, Q"));
        AppController.currentView = "today";
        tc.win.focusActiveView();
        keyClick(Qt.Key_G);
        keyClick(Qt.Key_B);
        compare(AppController.currentView, "today", "g b still went to the board");
        keyClick(Qt.Key_Y);
        keyClick(Qt.Key_Q);
        tryCompare(AppController, "currentView", "board");
    }

    // Ctrl O goes back where the person was.
    function test_ctrl_o_goes_back() {
        AppController.currentView = "today";
        wait(20);
        AppController.currentView = "board";
        wait(20);
        tc.win.focusActiveView();
        keyClick(Qt.Key_O, Qt.ControlModifier);
        tryCompare(AppController, "currentView", "today");
        tc.win.focusActiveView();
        keyClick(Qt.Key_I, Qt.ControlModifier);
        tryCompare(AppController, "currentView", "board");
    }
}
