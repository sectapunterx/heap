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
        const shownGroups = groups(s.contentItem, []).filter(g => g.visible).length;
        verify(shownGroups >= 1 && shownGroups <= 3, "groups shown for 'y y': " + shownGroups);
        s.close();
    }
    function groups(root, out) {
        if (!root) return out;
        if (String(root.objectName).indexOf("key-sheet-group-") === 0) out.push(root);
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) groups(kids[i], out);
        return out;
    }

    // DG-133: the areas of X-Keys and "Changed in 0.8.0", and nothing else —
    // no area for the rest of the catalogue, no row without a key.
    function test_only_the_sheet_areas_and_no_unbound_rows() {
        const s = make();
        s.open();
        tryCompare(s, "opened", true);
        wait(50);
        const ids = groups(s.contentItem, []).filter(g => g.visible).map(g => String(g.objectName).replace("key-sheet-group-", ""));
        compare(ids.sort(), ["changed", "copy", "find", "go", "move", "moveTask", "select", "task", "view"]);
        for (const g of s.groups)
            for (const r of g.rows) verify(r.ids.indexOf("view.archive") < 0 && r.ids.indexOf("view.docs") < 0);
        s.close();
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
