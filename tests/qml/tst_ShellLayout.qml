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

    // UX-7: long names elide instead of pushing "+ Task" off the window.
    function test_long_names_keep_the_top_bar_on_screen() {
        tc.win.width = 1100;
        tc.win.height = 720;
        AppController.crumbProject = "a-very-long-project-name-that-goes-on-and-on-forever";
        AppController.crumbUser = "someone.with.a.really.long.handle.indeed";
        const pid = AppController.activeProfileId;
        const oldName = AppController.profileById(pid).name;
        AppController.renameProfile(pid, "Payments platform · checkout · very long profile name");
        wait(100);
        const btn = byName("topbar-new-task");
        const toggle = byName("topbar-right-panel");
        const r1 = btn.mapToItem(null, btn.width, 0).x;
        const r2 = toggle.mapToItem(null, toggle.width, 0).x;
        AppController.renameProfile(pid, oldName);
        verify(r1 <= tc.win.width, "+ Task ends at " + r1);
        verify(r2 <= tc.win.width, "panel toggle ends at " + r2);
    }

    // APP-198: "+ Task" is a quiet button; a filled one is only a dialog's
    // confirm, so the brightest spot on the screen is not a shortcut.
    function test_new_task_is_a_quiet_button() {
        const btn = byName("topbar-new-task");
        compare(btn.primary, false);
        verify(!Qt.colorEqual(btn.background.color, Theme.accent), "no accent fill");
    }

    // UX-17: the Tweaks panel fits a 720px window on its first open.
    function test_tweaks_fits_a_small_window() {
        tc.win.width = 1100;
        tc.win.height = 720;
        const tweaks = popup("TweaksPanel");
        tc.win.runCommand("tweaks.open");
        tryCompare(tweaks, "opened", true);
        wait(100);
        const bottom = tweaks.contentItem.mapToItem(null, 0, tweaks.height).y;
        tweaks.close();
        verify(bottom <= tc.win.height, "Tweaks ends at " + bottom + " in a " + tc.win.height + "px window");
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
