// Where the keyboard is after the window changes under it: a view switch, a
// dialog closing, the tour going away — and which keys stand down meanwhile.
//
// After Ctrl+7 focus stayed on the hidden board, so nothing typed reached the
// note and Tab walked the top bar (PERA-5). After a dialog opened from a
// button, focus went back to the empty header search, which drew its syntax
// hint over the view and ate the next click (PERO-1). The day keys (T, G,
// Alt+arrows) fired from the header search and over menus and confirm dialogs
// (SHELL-3).
//
// Drives the real Main.qml with real key events.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "FocusFlow"
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

    function cleanup() {
        const ps = popups();
        for (let i = 0; i < ps.length; i++) if (ps[i].opened) ps[i].close();
        wait(150);
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
        tc.win.searchText = "";
        const s = search();
        if (s) s.text = "";
        AppController.currentView = "board";
        wait(50);
        tc.win.focusActiveView();
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
    function search() {
        return find(tc.win.contentItem, function (it) { return it.objectName === "topbar-search"; });
    }
    function focusIsInView() {
        const v = tc.win.activeViewItem();
        for (let p = tc.win.activeFocusItem; p; p = p.parent) if (p === v) return true;
        return false;
    }
    function switchTo(view) {
        AppController.currentView = view;
        tryVerify(function () { return tc.win.activeViewItem() !== null && tc.win.activeViewItem().visible; }, 3000);
        wait(50);
    }

    // PERA-5: Notes takes the keyboard into the editor; back on the board it
    // is the board's.
    function test_view_switch_hands_the_keyboard_to_the_view() {
        tc.win.focusActiveView();
        switchTo("notes");
        tryVerify(function () { return tc.win.activeFocusItem && tc.win.activeFocusItem.objectName === "notesEditor"; },
                  2000, "focus after switching to Notes: " + typeName(tc.win.activeFocusItem));
        switchTo("board");
        tryVerify(focusIsInView, 2000, "focus after switching to the board: " + typeName(tc.win.activeFocusItem));
        switchTo("week");
        tryVerify(focusIsInView, 2000, "focus after switching to the week: " + typeName(tc.win.activeFocusItem));
    }

    // …but a query being typed in the header search stays where it is.
    function test_view_switch_leaves_a_typed_query_alone() {
        const s = search();
        s.forceActiveFocus();
        keyClick(Qt.Key_Q);
        switchTo("month");
        verify(s.activeFocus, "the switch took the keyboard out of the search");
    }

    // PERO-1: a dialog opened while the header search held focus with nothing
    // in it gives the keyboard to the view when it closes.
    function test_closing_a_dialog_skips_the_idle_header_search() {
        const s = search();
        s.forceActiveFocus();
        verify(s.activeFocus);
        const go = popup("go-to-date");
        go.openAt(AppController.selectedDate, tc.win.contentItem);
        tryCompare(go, "opened", true);
        keyClick(Qt.Key_Escape);
        tryCompare(go, "opened", false);
        tryVerify(focusIsInView, 2000, "focus after the dialog: " + typeName(tc.win.activeFocusItem));
        verify(!s.activeFocus);
    }

    // The tour going away leaves the keyboard in the view, not on the window.
    function test_closing_the_tour_focuses_the_view() {
        const w = popup("WelcomePopup");
        w.open();
        tryCompare(w, "opened", true);
        w.close();
        tryCompare(w, "opened", false);
        tryVerify(focusIsInView, 2000, "focus after the tour: " + typeName(tc.win.activeFocusItem));
    }

    // SHELL-3: the day keys wait while a text field or a dialog has the
    // keyboard, and work from the view.
    function test_day_keys_stand_down_in_fields_and_dialogs() {
        const day = new Date(2031, 4, 14);
        AppController.selectedDate = day;
        const s = search();
        s.forceActiveFocus();
        keyClick(Qt.Key_Left, Qt.AltModifier);
        verify(Qt.formatDate(AppController.selectedDate, "yyyy-MM-dd") === "2031-05-14",
               "Alt+Left in the header search moved the day");
        s.text = "";

        const b = tc.win.activeViewItem();
        const confirm = (function () {
            const d = b.data || [];
            for (let i = 0; i < d.length; i++) if (d[i] && d[i].objectName === "confirm-delete-column") return d[i];
            return null;
        })();
        verify(confirm !== null);
        tc.win.focusActiveView();
        confirm.open();
        tryCompare(confirm, "opened", true);
        keyClick(Qt.Key_G);
        wait(50);
        compare(popup("go-to-date").opened, false, "G opened go-to-date over a confirm dialog");
        keyClick(Qt.Key_Left, Qt.AltModifier);
        verify(Qt.formatDate(AppController.selectedDate, "yyyy-MM-dd") === "2031-05-14",
               "Alt+Left moved the day under a confirm dialog");
        confirm.close();
        tryCompare(confirm, "opened", false);
        tryVerify(function () { return !tc.win._dimmerShown; }, 2000);

        tc.win.focusActiveView();
        tryVerify(function () { return !tc.win._viewKeysBlocked; }, 2000);
        keyClick(Qt.Key_Left, Qt.AltModifier);
        compare(Qt.formatDate(AppController.selectedDate, "yyyy-MM-dd"), "2031-05-13", "Alt+Left from the view");
    }

    // SHELL-17: in the archive, Down from the view enters the list and moves
    // from card to card.
    function test_archive_rows_are_reachable_from_the_keyboard() {
        for (let i = 0; i < 2; i++) {
            const d = AppController.newTaskDraft("todo");
            d._isNew = true;
            d.id = "FOCUSARCH-" + i;
            d.title = "focusflow archived " + i;
            AppController.saveTask(d);
            AppController.setArchived(d.id, true);
            tc.seeded.push(d.id);
        }
        tc.win.searchText = "focusflow archived";
        switchTo("archive");
        const v = tc.win.activeViewItem();
        tryCompare(v, "count", 2);
        tryVerify(focusIsInView, 2000);
        keyClick(Qt.Key_Down);
        tryVerify(function () { return typeName(tc.win.activeFocusItem).indexOf("TaskCard") === 0; }, 2000,
                  "Down did not reach a card: " + typeName(tc.win.activeFocusItem));
        const first = tc.win.activeFocusItem.taskId;
        keyClick(Qt.Key_Down);
        tryVerify(function () { return tc.win.activeFocusItem.taskId !== first; }, 2000, "Down did not move to the next card");
        verify(tc.win.activeFocusItem.Accessible.name.indexOf("focusflow archived") >= 0);
    }
}
