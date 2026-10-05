// Regressions from the 2026-09-30 audit, B tier: the board card's menu and
// cursor, the app's menus, drop-downs and text-field menu. Each case names
// the finding it pins.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "AuditMenus"
    when: windowShown
    visible: true
    width: 1400
    height: 900

    Item { id: host; anchors.fill: parent }

    readonly property string probe: "menuprobe"
    property var seeded: []

    function make(qml, parentItem) {
        const o = createTemporaryQmlObject(qml, parentItem || host);
        verify(o !== null);
        return o;
    }

    function addTask(status, title) {
        const d = AppController.newTaskDraft(status);
        d._isNew = true;
        d.title = tc.probe + " " + title;
        verify(AppController.saveTask(d), "seed save");
        tc.seeded.push(d.id);
        return d.id;
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        tc.seeded = [];
        AppController.clearPendingUndo();
        AppController.clearSelection();
    }

    function makeBoard(parentItem) {
        const b = make('import TodoCpp; KanbanBoard { anchors.fill: parent }', parentItem);
        b.searchText = tc.probe;
        wait(0);
        return b;
    }

    function indexOfItem(menu, name) {
        for (let i = 0; i < menu.count; i++) if (menu.itemAt(i) && menu.itemAt(i).objectName === name) return i;
        return -1;
    }

    function openCardMenu(b, id) {
        b.cursorTaskId = id;
        b.cursorVisible = true;
        b.openCursorMenu();
        const card = b._cardItem(id);
        verify(card !== null);
        const menu = findChild(card, "tc-menu");
        verify(menu !== null);
        tryVerify(() => menu.opened);
        return { card: card, menu: menu };
    }

    // ── PERA-2: Status › and Priority › open from the keyboard ──
    function test_right_opens_the_status_list_and_left_goes_back() {
        const id = addTask(AppController.statuses[0].id, "submenu");
        const b = makeBoard();
        const m = openCardMenu(b, id);
        const at = indexOfItem(m.menu, "tc-menu-status");
        verify(at > 0);
        m.menu.currentIndex = at;
        tryVerify(() => m.menu.itemAt(at).activeFocus, 1000, "the status row did not take the keyboard");
        keyClick(Qt.Key_Right);
        tryVerify(() => !m.menu.visible, 1000, "Right left the card menu open");
        tryVerify(() => findChild(m.card, "tc-status-menu") !== null, 1000, "Right did not open the status list");
        const list = findChild(m.card, "tc-status-menu");
        tryVerify(() => list.opened, 1000);
        // On the task's own status, so an Enter straight away changes nothing.
        const cur = AppController.statuses.findIndex(st => st.id === AppController.taskById(id).status);
        compare(list.currentIndex, cur);

        // Left: back to the card menu, on the row the list came from.
        tryVerify(() => list.itemAt(list.currentIndex).activeFocus, 1000);
        keyClick(Qt.Key_Left);
        tryVerify(() => !list.visible, 1000, "Left left the status list open");
        tryVerify(() => m.menu.opened, 1000, "Left did not go back to the card menu");
        compare(m.menu.currentIndex, at);

        // Esc closes the lot.
        tryVerify(() => m.menu.itemAt(at).activeFocus, 1000);
        keyClick(Qt.Key_Escape);
        tryVerify(() => !m.menu.visible && !list.visible, 1000);
        tryVerify(() => !b.cardMenuOpen);
    }

    function test_right_opens_the_priority_list_and_enter_picks() {
        const id = addTask(AppController.statuses[0].id, "priority");
        const b = makeBoard();
        const m = openCardMenu(b, id);
        const at = indexOfItem(m.menu, "tc-menu-priority");
        m.menu.currentIndex = at;
        tryVerify(() => m.menu.itemAt(at).activeFocus, 1000);
        keyClick(Qt.Key_Right);
        tryVerify(() => findChild(m.card, "tc-priority-menu") !== null, 1000, "Right did not open the priority list");
        const list = findChild(m.card, "tc-priority-menu");
        tryVerify(() => list.opened, 1000);
        list.currentIndex = 0;
        tryVerify(() => list.itemAt(0).activeFocus, 1000);
        keyClick(Qt.Key_Return);
        tryCompare(AppController.taskById(id), "priority", "P0");
        tryVerify(() => !list.visible);
    }

    // ── PERA-3: the card's keys are shown in its menu and the catalog ──
    function test_card_menu_rows_show_their_keys() {
        const id = addTask(AppController.statuses[0].id, "hints");
        const b = makeBoard();
        const m = openCardMenu(b, id);
        const archive = m.menu.itemAt(indexOfItem(m.menu, "tc-menu-archive"));
        compare(archive.hint, AppController.shortcutFor("board.archive"));
        verify(archive.hint.length > 0);
        const hint = findChild(archive, "menu-row-hint");
        verify(hint !== null && hint.visible && hint.text === archive.hint);
        verify(m.menu.itemAt(1).hint.length > 0, "Edit shows no key");
        m.menu.close();

        const ids = AppController.shortcuts.map(s => s.id);
        for (const k of ["board.cardMenu", "board.archive", "board.open", "board.collapseColumn"])
            verify(ids.indexOf(k) >= 0, k + " is not in the hotkeys catalog");
    }

    // ── VISU-19 / PERA-7: the board scrolls to the cursor ──
    function test_the_board_scrolls_to_a_cursor_past_the_right_edge() {
        const sts = AppController.statuses;
        verify(sts.length >= 4);
        const last = addTask(sts[sts.length - 1].id, "far right");
        const first = addTask(sts[0].id, "far left");
        const narrow = make('import QtQuick; Item { width: 640; height: 600 }');
        const b = makeBoard(narrow);
        const hs = findChild(b, "board-hscroll");
        verify(hs.contentWidth > hs.width, "the board must overflow for this case");
        compare(hs.contentX, 0);

        b.cursorVisible = true;
        b.cursorTaskId = last;
        tryVerify(() => hs.contentX > 0, 1000, "the board did not scroll to the cursor");
        // The cursor's column is wholly on screen.
        const col = findColumn(b, sts[sts.length - 1].id);
        verify(col !== null);
        verify(col.x >= hs.contentX && col.x + col.width <= hs.contentX + hs.width + 1,
               "the column is still cut: " + col.x + "+" + col.width + " vs " + hs.contentX + "+" + hs.width);

        b.cursorTaskId = first;
        tryCompare(hs, "contentX", 0);
    }

    function findColumn(item, statusId) {
        if (!item) return null;
        if (item.statusId === statusId && item.folded !== undefined) return item;
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = findColumn(kids[i], statusId);
            if (r) return r;
        }
        return null;
    }

    // ── VISU-4: selection and cursor look different ──
    function test_selection_and_cursor_are_told_apart() {
        const id = addTask(AppController.statuses[0].id, "looks");
        const card = make('import TodoCpp; TaskCard { width: 260 }');
        card.task = AppController.taskById(id);
        const ring = findChild(card, "tc-cursor-ring");
        const mark = findChild(card, "tc-selected-mark");
        verify(ring !== null && mark !== null);
        verify(!ring.visible && !mark.visible);

        card.cursored = true;
        verify(ring.visible, "the cursor has no ring");
        verify(!mark.visible);
        compare(card.border.width, 1);

        card.cursored = false;
        AppController.setSelectedTaskIds([id]);
        tryVerify(() => mark.visible, 1000, "a selected card has no check mark");
        verify(!ring.visible, "selection drew the cursor ring");
        compare(card.border.width, 2);
        verify(!Qt.colorEqual(card.color, Theme.panel2), "a selected card has no fill");
    }

    // ── VISP-5: a menu is as wide as its longest row ──
    function test_a_menu_widens_for_a_long_row_and_caps() {
        const menu = make('import TodoCpp; AppMenu { AppMenuItem { text: "short" } }');
        menu.open();
        tryVerify(() => menu.opened);
        compare(menu.width, menu.minWidth);
        menu.close();

        const wide = make('import TodoCpp; AppMenu { AppMenuItem { objectName: "long"; text: "Запланировать в календарь на следующий свободный слот" } }');
        wide.open();
        tryVerify(() => wide.opened);
        verify(wide.width > wide.minWidth, "the menu stayed at " + wide.width);
        verify(wide.width <= wide.maxWidth);
        const row = findChild(wide, "long");
        verify(row.contentItem.children[1].width <= row.availableWidth, "the label runs past the row");
        wide.close();

        const huge = make('import TodoCpp; AppMenu { AppMenuItem { objectName: "huge"; text: "' + "очень длинный пункт ".repeat(10) + '" } }');
        huge.open();
        tryVerify(() => huge.opened);
        compare(huge.width, huge.maxWidth);
        const label = findChild(huge, "huge").contentItem.children[1];
        verify(label.truncated, "a capped row must elide");
        huge.close();
    }

    // ── VISP-1: the text-field menu is the app's own, in its language ──
    function test_the_text_field_menu_is_localized_and_works() {
        const f = make('import QtQuick; import QtQuick.Controls; import TodoCpp; '
                       + 'TextField { id: f; width: 200; text: "hello world"; ContextMenu.menu: TextEditMenu { editor: f } }');
        const menu = f.ContextMenu.menu;
        verify(menu !== null, "the field has no menu");
        compare(menu.objectName, "text-edit-menu");
        menu.open();
        tryVerify(() => menu.opened);
        const names = ["text-edit-undo", "text-edit-redo", "text-edit-cut", "text-edit-copy",
                       "text-edit-paste", "text-edit-delete", "text-edit-select-all"];
        const keys = ["undo", "redo", "cut", "copy", "paste", "delete", "selectAll"];
        for (let i = 0; i < names.length; i++) {
            const it = findChild(menu, names[i]);
            verify(it !== null, names[i]);
            compare(it.text, I18n.t("textmenu." + keys[i]));
        }
        verify(!findChild(menu, "text-edit-copy").enabled, "copy with nothing selected");
        findChild(menu, "text-edit-select-all").triggered();
        compare(f.selectedText, "hello world");
        verify(findChild(menu, "text-edit-cut").enabled);
        findChild(menu, "text-edit-delete").triggered();
        compare(f.text, "");
        verify(findChild(menu, "text-edit-undo").enabled);
        menu.close();
    }

    // ── VISP-2: the editors' drop-downs are the app's own list ──
    function test_the_combo_list_is_an_app_menu_list() {
        const box = make('import TodoCpp; AppComboBox { width: 200; model: ["one", "two", "three"]; currentIndex: 1 }');
        box.popup.open();
        tryVerify(() => box.popup.opened);
        const lv = box.popup.contentItem;
        tryVerify(() => lv.count === 3);
        const row = lv.itemAtIndex(1);
        verify(row !== null);
        compare(row.height, 28);
        verify(row.current, "the current choice is not marked");
        verify(!lv.itemAtIndex(0).current);
        compare(box.popup.background.radius, Theme.radiusLg);
        box.popup.close();
    }

    // ── PERO-2: "+ Add" in a section files the entry in that section ──
    function test_the_doc_form_shows_the_section_it_was_opened_from() {
        const ed = make('import TodoCpp; DocsEditor { }');
        ed.sections = [{ id: "s-a", title: "Web", items: [] }, { id: "s-b", title: "Team links", items: [] }];
        const combo = findChild(ed, "docs-editor-section");
        verify(combo !== null);
        ed.kind = "doc";
        ed.isNew = true;
        ed.sectionId = "s-b";
        ed.draft = ({ ref: "", title: "", _sectionId: "s-b" });
        compare(combo.currentIndex, 1, "the form opened on another section");
        compare(combo.displayText, "Team links");
        // A second "+ Add", from the other section.
        ed.sectionId = "s-a";
        ed.draft = ({ ref: "", title: "", _sectionId: "s-a" });
        compare(combo.currentIndex, 0);
        compare(ed.draft._sectionId, "s-a");
    }
}
