// Menus and drop-downs from the keyboard (APP-279): a list opened from a row
// goes back with ← and Esc, digits pick in Priority, letters find a row,
// keys on the rows come from the catalogue, a drop-down finds by typing.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "MenuKeys"
    when: windowShown
    width: 900
    height: 700

    Item {
        id: anchorBox
        x: 40; y: 40
        width: 200; height: 30
    }

    Component {
        id: hostComp
        TaskMenuHost { anchorItem: anchorBox }
    }
    Component {
        id: comboComp
        AppComboBox {
            x: 300; y: 40
            width: 200
            model: ["Backlog", "To do", "Done", "Doing", "Готово", "Голос"]
        }
    }

    function init() {
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.id = "MENU-1";
        d.title = "menu probe";
        d.priority = "P2";
        AppController.saveTask(d);
    }
    function cleanup() {
        AppController.deleteTask("MENU-1");
        AppController.clearPendingUndo();
        AppController.resetAllShortcuts();
    }

    function host() {
        const h = createTemporaryObject(hostComp, tc, { taskId: "MENU-1" });
        verify(h !== null);
        return h;
    }
    function rowNamed(menu, name) {
        for (let i = 0; i < menu.count; i++) {
            const it = menu.itemAt(i);
            if (it && it.objectName === name) return i;
        }
        return -1;
    }

    // M → Priority → ← is the menu again, on the Priority row; Esc too.
    function test_a_list_goes_back_to_its_menu() {
        const h = host();
        h.openMenu();
        const menu = h.menu;
        tryCompare(menu, "opened", true);
        menu.currentIndex = rowNamed(menu, "tc-menu-priority");
        keyClick(Qt.Key_Right);
        tryVerify(function () { return h.priorityList && h.priorityList.opened; }, 2000);
        compare(h.priorityList.itemAt(0).objectName, "tc-priority-back", "the list starts with ‹ back");
        compare(h.priorityList.currentIndex, 3, "on the task's own P2 (after ‹ back)");
        keyClick(Qt.Key_Left);
        tryVerify(function () { return menu.opened && !h.priorityList.opened; }, 2000);
        compare(menu.currentIndex, rowNamed(menu, "tc-menu-priority"));
        // Esc in the list goes back too; Esc in the menu closes it all.
        menu.currentIndex = rowNamed(menu, "tc-menu-priority");
        keyClick(Qt.Key_Right);
        tryVerify(function () { return h.priorityList.opened; }, 2000);
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return menu.opened && !h.priorityList.opened; }, 2000);
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return !menu.opened; }, 2000);
    }

    // 1–4 in the Priority list set the priority.
    function test_digits_pick_in_the_priority_list() {
        const h = host();
        h.openSubMenu("priority");
        tryVerify(function () { return h.priorityList && h.priorityList.opened; }, 2000);
        keyClick(Qt.Key_1);
        tryVerify(function () { return AppController.taskById("MENU-1").priority === "P0"; }, 2000);
        tryVerify(function () { return !h.priorityList.opened; }, 2000);
    }

    // The keys on the rows are the catalogue's, as written in the keymap, and
    // follow a rebinding.
    function test_row_keys_follow_the_catalogue() {
        const h = host();
        h.openMenu();
        const menu = h.menu;
        tryCompare(menu, "opened", true);
        const schedule = menu.itemAt(rowNamed(menu, "tc-menu-schedule"));
        compare(schedule.hint, AppController.shortcutText("task.schedule"));
        compare(schedule.hint, "s");
        compare(menu.itemAt(rowNamed(menu, "tc-menu-copyid")).hint, "y y");
        compare(menu.itemAt(rowNamed(menu, "tc-menu-done")).hint, "d");
        // Open shows Return as the sheet writes it, ↵ (X-Menus-Task, DG-027).
        compare(menu.itemAt(rowNamed(menu, "tc-menu-edit")).hint, "↵");
        verify(AppController.setShortcut("task.schedule", "Ctrl+Alt+S"));
        compare(schedule.hint, AppController.keyText("Ctrl+Alt+S"));
        menu.close();
        // The Priority list shows 1–4.
        h.openSubMenu("priority");
        tryVerify(function () { return h.priorityList.opened; }, 2000);
        compare(h.priorityList.itemAt(1).hint, "1");
        compare(h.priorityList.itemAt(4).hint, "4");
        h.priorityList.close();
    }

    // Letters find a row by the start of its name.
    function test_typing_finds_a_row() {
        const h = host();
        h.openMenu();
        const menu = h.menu;
        tryCompare(menu, "opened", true);
        const archive = rowNamed(menu, "tc-menu-archive");
        const label = String(menu.itemAt(archive).text);
        for (let i = 0; i < 3; i++) menu.typeKey({ text: label[i], modifiers: 0 });
        compare(menu.currentIndex, archive, "typed " + label.slice(0, 3));
        menu.close();
        // Cyrillic, through the same rule.
        h.openSubMenu("status");
        tryVerify(function () { return h.statusList.opened; }, 2000);
        const names = AppController.statuses.map(st => st.name);
        const target = names.length - 1;
        const word = names[target];
        h.statusList._typed = "";
        for (let i = 0; i < Math.min(3, word.length); i++) h.statusList.typeKey({ text: word[i], modifiers: 0 });
        compare(h.statusList.itemAt(h.statusList.currentIndex).text, word);
        h.statusList.close();
    }

    // A drop-down finds by typing; Enter takes it.
    function test_a_dropdown_finds_by_typing() {
        const box = createTemporaryObject(comboComp, tc);
        box.forceActiveFocus();
        keyClick(Qt.Key_D);
        keyClick(Qt.Key_O);
        keyClick(Qt.Key_I);
        tryCompare(box.popup, "visible", true);
        compare(box.typedIndex, 3, "doi → Doing");
        keyClick(Qt.Key_Return);
        tryCompare(box, "currentIndex", 3);
        tryCompare(box.popup, "visible", false);
        // "гот" (typed as text: QTest has no Cyrillic key codes).
        box._typedAt = 0;
        box.typeAhead("г");
        box.typeAhead("о");
        box.typeAhead("т");
        compare(box.textAt(box.typedIndex), "Готово");
        box.popup.close();
    }
}
