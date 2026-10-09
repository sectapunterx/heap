// The window's own furniture at small sizes (audit UX-7, 17, 18, 19, 23,
// 29, 31). Drives the real Main.qml.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ShellLayout"
    when: windowShown

    property var win: null
    property string savedProject: ""
    property string savedUser: ""

    function initTestCase() {
        tc.savedProject = AppController.crumbProject;
        tc.savedUser = AppController.crumbUser;
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        wait(1200);
        const ps = popups();
        for (let i = 0; i < ps.length; i++) if (ps[i].opened) ps[i].close();
        AppController.currentView = "board";
    }
    function cleanupTestCase() {
        AppController.crumbProject = tc.savedProject;
        AppController.crumbUser = tc.savedUser;
        if (tc.win) tc.win.destroy();
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
            if (String(ps[i]).indexOf(prefix) === 0 || ps[i].objectName === prefix) return ps[i];
        return null;
    }
    function find(root, pred) {
        if (!root) return null;
        if (pred(root)) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) { const r = find(kids[i], pred); if (r) return r; }
        return null;
    }
    function byName(name) { return find(tc.win.contentItem, function (it) { return it.objectName === name; }); }

    // UX-31: the title ends with the display name, so Windows does not add it
    // a second time.
    function test_window_title_names_the_app_once() {
        // lowkey since 0.8.0 (APP-280): the name alone, as the taskbar shows it.
        compare(tc.win.title, "lowkey");
    }

    // heap 2 (APP-258): every place by its key, from the real window.
    // Ctrl+1/2/3 are Today / Tasks / Knowledge, Ctrl+, Settings; Tasks and
    // Knowledge come back on the lens they were left on.
    function test_every_place_by_its_key() {
        tc.win.width = 1440;
        tc.win.height = 900;
        tc.win.requestActivate();
        AppController.currentView = "board";
        wait(50);
        keyClick(Qt.Key_1, Qt.ControlModifier);
        tryCompare(AppController, "currentView", "today");
        keyClick(Qt.Key_2, Qt.ControlModifier);
        tryCompare(AppController, "currentView", "board");
        tc.win.openLens("calendar");
        compare(AppController.currentView, "week");
        keyClick(Qt.Key_3, Qt.ControlModifier);
        tryCompare(AppController, "currentView", "notes");
        keyClick(Qt.Key_Comma, Qt.ControlModifier);
        tryCompare(AppController, "currentView", "settings");
        keyClick(Qt.Key_2, Qt.ControlModifier);
        tryCompare(AppController, "currentView", "week", 1000, "Tasks reopens on the calendar lens");
        // The List lens is its own view now (APP-263), not the timeline.
        tc.win.openLens("list");
        compare(AppController.currentView, "list");
        tc.win.openLens("board");
        compare(AppController.currentView, "board");
        tryCompare(AppController, "currentSection", "tasks");
    }

    // The top bar is gone (APP-258): no "+ Task", no panel toggle up there;
    // the sidebar's field and the header's lenses instead.
    function test_the_shell_has_no_top_bar() {
        compare(byName("topbar-new-task"), null);
        compare(byName("topbar-right-panel"), null);
        verify(byName("sidebar-new-task") !== null);
        AppController.currentView = "board";
        const header = byName("view-header");
        verify(header !== null && header.visible);
        AppController.currentView = "today";
        verify(!header.visible, "Today carries its own title");
        compare(byName("right-panel").visible, false, "Today is the day; no second one beside it");
        AppController.currentView = "board";
    }

    // Narrower than ~1100px the sidebar folds to its icons on its own.
    function test_a_narrow_window_folds_the_sidebar() {
        tc.win.width = 1440;
        const rail = byName("sidebar");
        tryCompare(rail, "expanded", true);
        tc.win.width = 1000;
        tryCompare(rail, "expanded", false);
        tc.win.width = 1440;
        tryCompare(rail, "expanded", true);
    }

    // UX-18: Go to date opens over the middle of the window, not its corner.
    function test_go_to_date_is_centred() {
        tc.win.width = 1400;
        tc.win.height = 900;
        const g = popup("go-to-date");
        g.openAt(AppController.selectedDate, tc.win.contentItem);
        tryCompare(g, "opened", true);
        wait(50);
        const x = g.x, w = g.width;
        g.close();
        verify(Math.abs(x + w / 2 - tc.win.width / 2) < 4, "centre at " + (x + w / 2));
    }

    // UX-29: at 1280 logical px (1080p at 150%) the calendar column folds, so
    // the board keeps more than two columns.
    function test_1280_folds_the_right_panel() {
        tc.win.width = 1280;
        AppController.currentView = "board";
        wait(50);
        compare(tc.win.rightPanelShown, false);
        tc.win.width = 1600;
        wait(50);
    }

    // UX-19: the close-to-tray dialog title is drawn in the theme.
    function test_close_dialog_is_themed() {
        const d = popup("close-to-tray-ask");
        verify(d !== null);
        verify(d.header && Qt.colorEqual(d.header.color, Theme.text), "unstyled dialog header");
    }

    // UX-23: an empty timeline without filters does not blame the filters.
    function test_timeline_empty_state_without_filters() {
        tc.win.searchText = "zzzz-no-such-task-zzzz";
        AppController.currentView = "timeline";
        tryVerify(function () { return tc.win.activeViewItem() !== null; });
        const v = tc.win.activeViewItem();
        tryVerify(function () { return find(v, function (it) { return it.objectName === "timeline-empty" && it.visible; }) !== null; });
        const t = find(v, function (it) { return it.objectName === "timeline-empty"; });
        compare(t.title, I18n.t("timeline.empty.title"), "with a search, the filters are the reason");
        compare(v._filtering, true);
        tc.win.searchText = "";
        compare(v._filtering, false);
        AppController.currentView = "board";
    }
}
