// Who gets a key: the innermost thing that holds the keyboard.
//
// Board and calendar keys are application shortcuts, so Qt offered them before
// the focused item. Return in the header search opened the card under the board
// cursor, Down in a card's context menu moved the cursor behind it, Enter in
// "New column" opened the task editor, and the first Esc with a selection
// cleared the selection while the editor stayed open. Global shortcuts fired
// behind modals (Ctrl+3 under the task editor, Ctrl+K over the welcome tour),
// and a new task's editor opened with no focus, so what was typed went nowhere.
//
// Drives the real Main.qml with real key events.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "KeyScope"
    when: windowShown

    property var win: null
    property var seeded: []
    readonly property string probe: "scopeprobe"

    function initTestCase() {
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        verify(comp.status === Component.Ready, comp.errorString());
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tc.win.width = 1456;
        tc.win.height = 939;
        AppController.resetAllShortcuts();
        tryVerify(function () { return !tc.win.findChild || true; });
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
        seed();
        closeAll();
    }

    function cleanup() {
        closeAll();
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
        tc.win.searchText = "";
    }

    function seed() {
        tc.seeded = [];
        for (let i = 0; i < 3; i++) {
            const d = AppController.newTaskDraft("todo");
            d._isNew = true;
            d.id = "SCOPE-" + i;
            d.title = tc.probe + " card " + i;
            AppController.saveTask(d);
            tc.seeded.push(d.id);
        }
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
    function byName(root, name) { return find(root, function (it) { return it.objectName === name; }); }
    function dataByName(root, name) {
        const d = root.data || [];
        for (let i = 0; i < d.length; i++) if (d[i] && d[i].objectName === name) return d[i];
        return null;
    }
    function closeAll() {
        const ps = popups();
        for (let i = 0; i < ps.length; i++) if (ps[i].opened) ps[i].close();
        const b = tc.win.activeViewItem();
        wait(150);
        AppController.clearSelection();
        if (b && b.clearCursor) b.clearCursor();
        tc.win.focusActiveView();
        wait(20);
    }
    function board() { return tc.win.activeViewItem(); }

    // UX-1 / TASKS-10: Ctrl+N and type — the title gets every character.
    function test_new_task_editor_focuses_title() {
        const te = popup("TaskEditor");
        keyClick(Qt.Key_N, Qt.ControlModifier);
        tryCompare(te, "opened", true);
        keyClick(Qt.Key_A); keyClick(Qt.Key_B); keyClick(Qt.Key_C);
        const title = find(te.contentItem, function (it) { return it.placeholderText === I18n.t("editor.ph.titleShort"); });
        verify(title !== null);
        compare(title.text, "abc");
        keyClick(Qt.Key_Escape);
        tryCompare(te, "opened", false);
    }

    // UX-9: Tab leaves the description instead of typing a tab, and a list
    // line indents instead.
    function test_tab_leaves_description() {
        const te = popup("TaskEditor");
        te.showFor(AppController.newTaskDraft("todo"));
        tryCompare(te, "opened", true);
        const desc = byName(te.contentItem, "te-desc");
        desc.forceActiveFocus();
        keyClick(Qt.Key_Tab);
        compare(desc.text, "");
        verify(!desc.activeFocus, "Tab must move focus out of the description");
        desc.forceActiveFocus();
        desc.text = "- item";
        desc.cursorPosition = 6;
        keyClick(Qt.Key_Tab);
        compare(desc.text, "  - item");
        verify(desc.activeFocus);
        keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
        compare(desc.text, "- item");
        keyClick(Qt.Key_Escape);
        tryCompare(te, "opened", false);
    }

    // UX-2: the editor closes first, the selection is let go of second.
    function test_escape_closes_editor_before_selection() {
        AppController.setSelectedTaskIds([tc.seeded[0], tc.seeded[1]]);
        compare(AppController.selectionCount, 2);
        const te = popup("TaskEditor");
        te.showFor(Object.assign({}, AppController.taskById(tc.seeded[0])));
        tryCompare(te, "opened", true);
        keyClick(Qt.Key_Escape);
        tryCompare(te, "opened", false);
        compare(AppController.selectionCount, 2, "the first Esc belongs to the editor");
        tc.win.focusActiveView();
        keyClick(Qt.Key_Escape);
        compare(AppController.selectionCount, 0, "the second Esc lets go of the selection");
    }

    // UX-3 / TASKS-5 / UX-21: the header search keeps Return, Esc and arrows.
    function test_search_field_owns_its_keys() {
        const b = board();
        b.searchText = tc.probe;
        b.moveCursor(0, 1);
        const cursor = b.cursorTaskId;
        verify(cursor !== "");
        const te = popup("TaskEditor");
        const search = byName(tc.win.contentItem, "topbar-search");
        search.forceActiveFocus();
        keyClick(Qt.Key_S);
        keyClick(Qt.Key_Down);
        compare(b.cursorTaskId, cursor, "Down in the search moved the board cursor");
        keyClick(Qt.Key_Return);
        wait(100);
        compare(te.opened, false, "Return in the search opened the card under the cursor");
        verify(!search.activeFocus, "Return hands the keyboard back to the view");
        search.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(search.text, "", "Esc clears the search");
        verify(search.activeFocus);
        keyClick(Qt.Key_Escape);
        verify(!search.activeFocus, "a second Esc leaves the search");
    }

    // UX-3: a card's context menu keeps Down and Esc.
    function test_card_menu_owns_its_keys() {
        const b = board();
        b.searchText = tc.probe;
        b.moveCursor(0, 1);
        const cursor = b.cursorTaskId;
        const card = find(b, function (it) { return it.objectName === "tc-card" && it.visible && it.taskId === cursor; })
                  || find(b, function (it) { return it.objectName === "tc-card" && it.visible; });
        verify(card !== null);
        const menu = dataByName(card, "tc-menu");
        verify(menu !== null);
        menu.popup(card, 10, 10);
        tryCompare(menu, "opened", true);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        compare(b.cursorTaskId, cursor, "Down in the menu moved the board cursor");
        verify(menu.currentIndex >= 0, "Down must move through the menu");
        keyClick(Qt.Key_Escape);
        tryCompare(menu, "opened", false);
        verify(b.cursorVisible, "Esc closed the menu and nothing else");
    }

    // TASKS-5: Enter in "New column" creates the column, not a task editor.
    function test_add_column_enter_creates_column() {
        const b = board();
        const pop = dataByName(b, "add-column-popup");
        verify(pop !== null);
        const before = AppController.statuses.length;
        b.moveCursor(0, 1);
        pop.open();
        tryCompare(pop, "opened", true);
        const field = byName(pop.contentItem, "add-column-name");
        tryVerify(function () { return field.activeFocus; });
        keyClick(Qt.Key_Q); keyClick(Qt.Key_A);
        keyClick(Qt.Key_Return);
        tryCompare(pop, "opened", false);
        compare(popup("TaskEditor").opened, false, "Enter opened the task editor over the dialog");
        compare(AppController.statuses.length, before + 1);
        const sts = AppController.statuses;
        AppController.deleteStatus(sts[sts.length - 1].id);
    }

    // TASKS-5: Enter in the WIP dialog saves the limit.
    function test_wip_dialog_enter_saves() {
        const b = board();
        const wip = dataByName(b, "wip-popup");
        verify(wip !== null);
        b.moveCursor(0, 1);
        const st = AppController.statuses[0];
        wip.openFor(st.id, st.name, 0, null);
        tryCompare(wip, "opened", true);
        keyClick(Qt.Key_7);
        keyClick(Qt.Key_Return);
        tryCompare(wip, "opened", false);
        compare(popup("TaskEditor").opened, false);
        compare(AppController.statuses[0].wip, 7);
        AppController.setStatusWipLimit(st.id, 0);
    }

    // UX-22: global shortcuts stand down behind a modal.
    function test_global_shortcuts_wait_behind_modals() {
        const te = popup("TaskEditor");
        te.showFor(AppController.newTaskDraft("todo"));
        tryCompare(te, "opened", true);
        keyClick(Qt.Key_3, Qt.ControlModifier);
        compare(AppController.currentView, "board", "Ctrl+3 switched the view under the editor");
        keyClick(Qt.Key_Escape);
        tryCompare(te, "opened", false);

        const welcome = popup("WelcomePopup");
        welcome.open();
        tryCompare(welcome, "opened", true);
        keyClick(Qt.Key_K, Qt.ControlModifier);
        compare(popup("CommandPalette").opened, false, "Ctrl+K opened the palette over the tour");
        welcome.close();
        tryCompare(welcome, "opened", false);

        // …and work again once it is gone.
        tc.win.focusActiveView();
        keyClick(Qt.Key_K, Qt.ControlModifier);
        tryCompare(popup("CommandPalette"), "opened", true);
        keyClick(Qt.Key_Escape);
        tryCompare(popup("CommandPalette"), "opened", false);
    }
}
