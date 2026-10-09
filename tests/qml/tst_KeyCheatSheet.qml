// The keyboard cheat sheet (APP-272): every catalogue key is on it, the
// search finds rows by action or key (in either layout), and a rebinding
// changes what it shows.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "KeyCheatSheet"
    when: windowShown
    width: 1300
    height: 900

    Component {
        id: sheetComp
        KeyCheatSheet {}
    }

    function make() {
        const s = createTemporaryObject(sheetComp, tc);
        verify(s !== null);
        return s;
    }

    function cleanup() {
        AppController.resetAllShortcuts();
    }

    // The sheet and the catalogue are the same set of actions.
    function test_the_sheet_is_the_catalogue() {
        const s = make();
        const shown = {};
        for (const id of s.allIds()) shown[id] = true;
        const ids = {};
        for (const c of AppController.shortcuts) {
            ids[c.id] = true;
            verify(shown[c.id] === true, c.id + " is not on the sheet");
        }
        for (const id in shown) verify(ids[id] === true, id + " is on the sheet but not in the catalogue");
    }

    function test_the_search_filters_by_action_and_by_key() {
        const s = make();
        const copyId = { ids: ["task.copyId"] };
        const board = { label: "keys.row.goBoard", ids: ["view.board"] };
        const palette = { ids: ["palette.open", "palette.open.alt"] };
        verify(s.matches(copyId, ""));
        verify(s.matches(copyId, AppController.shortcutLabel("task.copyId").slice(0, 4)), "by its name");
        verify(s.matches(copyId, "y y"), "by its key");
        verify(!s.matches(copyId, "g b"));
        verify(s.matches(board, "g b"));
        verify(s.matches(palette, "ctrl k"), "Ctrl K by its key");
        verify(s.matches(palette, "л"), "л is the K key of ЙЦУКЕН");
        verify(s.matches(palette, "к"), "к is k said in Russian");
        // On screen: a search hides the groups with nothing in it.
        s.open();
        tryCompare(s, "opened", true);
        s.query = "y y";
        wait(50);
        let shownGroups = 0;
        const grid = findGrid(s.contentItem);
        verify(grid !== null);
        for (let i = 0; i < grid.children.length; i++) {
            const g = grid.children[i];
            if (String(g.objectName).indexOf("key-sheet-group-") === 0 && g.visible) shownGroups++;
        }
        verify(shownGroups >= 1 && shownGroups <= 3, "groups shown for 'y y': " + shownGroups);
        s.close();
    }
    function findGrid(root) {
        if (!root) return null;
        if (root.columns !== undefined && root.rowSpacing !== undefined) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = findGrid(kids[i]);
            if (r) return r;
        }
        return null;
    }

    // A rebinding changes the key on the sheet.
    function test_a_rebinding_shows_on_the_sheet() {
        const s = make();
        compare(s.keysOf({ ids: ["task.copyId"] }), ["y y"]);
        verify(AppController.setShortcut("task.copyId", "Ctrl+Alt+I"));
        compare(s.keysOf({ ids: ["task.copyId"] }), [AppController.keyText("Ctrl+Alt+I")]);
        // A run of keys reads as one: "1…4".
        compare(s.keysOf({ range: true, ids: ["task.priority0", "task.priority1", "task.priority2", "task.priority3"] }), ["1…4"]);
    }
}
