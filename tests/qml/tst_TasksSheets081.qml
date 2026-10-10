// The Tasks screens against their 0.8.1 sheets (H2-Board / Q-Board, H2-List,
// X-Menus-*): the default "не готово" condition and its chip, the quiet
// conditions row, the selection bar's words and keys, the menus' context
// lines, the text field menu's task link.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TasksSheets081"
    when: windowShown
    visible: true
    width: 1200
    height: 800

    Item { id: host; anchors.fill: parent }

    function find(root, name) {
        if (!root) return null;
        if (root.objectName === name) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) {
            const f = find(kids[i], name);
            if (f) return f;
        }
        return null;
    }
    function findIn(menu, name) {
        for (let i = 0; i < menu.count; i++) {
            const it = menu.itemAt(i);
            if (it && it.objectName === name) return it;
        }
        return null;
    }
    property string _style: ""
    function initTestCase() { tc._style = Style.base; }
    function cleanup() {
        Style.apply(tc._style || "bold");
        AppController.clearSelection();
    }

    // DG-020: "is:open" reads as the sheet's "статус не готово" chip, and
    // the board names its profile beside it.
    function test_default_condition_is_a_status_chip() {
        Style.apply("bold");
        const bar = createTemporaryQmlObject('import TodoCpp; TopBar { width: 1100; section: "tasks"; view: "board"; profileName: "Example" }', host);
        bar.searchText = "is:open";
        waitForRendering(bar);
        compare(bar.conditions.length, 1);
        compare(bar.conditions[0].key, I18n.t("query.key.status"));
        compare(bar.conditions[0].value, I18n.t("query.notDone"));
        const prof = find(bar, "query-chip-profile");
        verify(prof && prof.visible, "the board shows its profile");
        verify(find(bar, "query-save-view").visible, "Save as view is always there");
        compare(find(bar, "topbar-search").placeholderText, I18n.t("query.placeholder"));
        bar.view = "list";
        verify(!find(bar, "query-chip-profile").visible, "the list has no profile chip (H2-List)");
        // The calendar has no query line while only the default is set.
        bar.view = "week";
        verify(!bar.queryShown);
        bar.searchText = "is:open p1";
        verify(bar.queryShown, "a real filter is never out of sight");
    }

    // DG-021: quiet draws the conditions as plain chips plus "изменить
    // фильтр", which opens the field.
    function test_quiet_row_opens_the_field() {
        Style.apply("quiet");
        const bar = createTemporaryQmlObject('import TodoCpp; TopBar { width: 1100; section: "tasks"; view: "board"; profileName: "Example" }', host);
        bar.searchText = "is:open";
        waitForRendering(bar);
        verify(find(bar, "view-header-query-quiet").visible);
        verify(!find(bar, "view-header-query").visible, "no box at rest");
        bar.focusEnd();
        tryVerify(() => find(bar, "view-header-query").visible, 1000);
        tryVerify(() => find(bar, "topbar-search").activeFocus, 1000);
        bar.leaveRequested();
        tryVerify(() => !find(bar, "view-header-query").visible, 1000, "folds back when the keyboard leaves");
    }

    // DG-030: a start begins from "не готово"; a saved status query is kept.
    function test_default_query_on_start() {
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        verify(comp.status === Component.Ready, comp.errorString());
        const win = comp.createObject(null);
        verify(win !== null);
        compare(win.defaultQuery("", false), "is:open");
        compare(win.defaultQuery("p1", false), "is:open p1");
        compare(win.defaultQuery("status:blocked", false), "status:blocked");
        compare(win.defaultQuery("", true), "", "filters saved since 0.8.1 stay as they are");
        win.destroy();
    }

    // DG-026: words with their keys; Done and Schedule run the window's d / s.
    function test_selection_bar_words_and_keys() {
        Style.apply("bold");
        AppController.deleteTask("SHEET-1");
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.id = "SHEET-1";
        d.title = "sheet probe";
        verify(AppController.saveTask(d));
        AppController.setSelectedTaskIds(["SHEET-1"]);
        const bar = createTemporaryQmlObject('import TodoCpp; SelectionBar { property string ran: ""; onCommandRequested: (id) => ran = id }', host);
        waitForRendering(bar);
        for (const n of ["sel-done", "sel-schedule", "sel-priority", "sel-move", "sel-archive", "sel-delete", "sel-clear"])
            verify(find(bar, n) !== null, n);
        compare(find(bar, "sel-done").keys, AppController.shortcutText("task.done"));
        find(bar, "sel-schedule").activated();
        compare(bar.ran, "task.schedule");
        AppController.clearSelection();
        AppController.deleteTask("SHEET-1");
        AppController.clearPendingUndo();
    }
}
