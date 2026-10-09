// Keyboard-only reachability (audit UX-9): the filter bar, the mini week, the
// day panel, Settings' section list and search, and the Tweaks panel were
// mouse-only or trapped Tab. Drives the real Main.qml.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "KeyboardReach"
    when: windowShown

    property var win: null

    function initTestCase() {
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tc.win.width = 1456;
        tc.win.height = 939;
        wait(1200);
        const ps = popups();
        for (let i = 0; i < ps.length; i++) if (ps[i].opened) ps[i].close();
        tc.win.requestActivate();
        AppController.currentView = "board";
        tryVerify(function () { return tc.win.activeViewItem() !== null; }, 3000);
    }
    function cleanupTestCase() { if (tc.win) tc.win.destroy(); }
    function init() {
        AppController.currentView = "board";
        AppController.selectedDate = AppController.today;
        tc.win.prioritiesFilter = ({});
        tc.win.focusActiveView();
        wait(20);
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
    function find(root, pred) {
        if (!root) return null;
        if (pred(root)) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) { const r = find(kids[i], pred); if (r) return r; }
        return null;
    }
    function byName(name, root) { return find(root || tc.win.contentItem, function (it) { return it.objectName === name; }); }
    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); }
    function plusDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }

    function editor() {
        const ps = popups();
        for (let i = 0; i < ps.length; i++) if (String(ps[i]).indexOf("TaskEditor") === 0) return ps[i];
        return null;
    }
    function within(item, root) {
        for (let p = item; p; p = p.parent) if (p === root) return true;
        return false;
    }

    // Closing a popup hands the keyboard back to where it was (design audit
    // DES-1). Esc in the task editor left focus on a bare layout, so the
    // board's J/K and Return were dead until the next click.
    function test_closing_the_editor_gives_the_board_its_keys_back() {
        const b = tc.win.activeViewItem();
        verify(within(tc.win.activeFocusItem, b), "setup: the board has focus");
        const te = editor();
        verify(te !== null);
        te.showFor(AppController.newTaskDraft("todo"));
        tryVerify(function () { return te.opened; }, 2000);
        tryVerify(function () { return tc.win._focusInPopup; }, 2000);
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return !te.opened; }, 2000);
        tryVerify(function () { return within(tc.win.activeFocusItem, b); }, 2000,
                  "focus after Esc: " + tc.win.activeFocusItem);
    }

    // …and to the control that had it, not just to the view.
    function test_closing_the_editor_returns_focus_to_the_control() {
        const chip = byName("pri-P2");
        chip.forceActiveFocus(Qt.TabFocusReason);
        const te = editor();
        te.showFor(AppController.newTaskDraft("todo"));
        tryVerify(function () { return te.opened; }, 2000);
        tryVerify(function () { return tc.win._focusInPopup; }, 2000);
        te.close();
        tryVerify(function () { return !te.opened; }, 2000);
        tryVerify(function () { return tc.win.activeFocusItem === chip; }, 2000,
                  "focus after close: " + tc.win.activeFocusItem);
    }

    function test_filter_chips_toggle_from_the_keyboard() {
        const chip = byName("pri-P0");
        verify(chip !== null);
        verify(chip.activeFocusOnTab, "the P0 chip is not on the Tab path");
        chip.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(tc.win.prioritiesFilter["P0"], true);
        keyClick(Qt.Key_Space);
        compare(tc.win.prioritiesFilter["P0"], false);
        verify(byName("archived-toggle").activeFocusOnTab);
        // The board's sort sits beside the lens tabs now (APP-262).
        verify(byName("view-header-option") !== null);
    }

    // While a tabbed-to control has the keyboard, the board cursor keys wait;
    // Esc hands the keyboard back.
    function test_board_keys_wait_while_a_control_has_focus() {
        const b = tc.win.activeViewItem();
        const chip = byName("pri-P1");
        chip.forceActiveFocus(Qt.TabFocusReason);
        const before = b.cursorTaskId;
        keyClick(Qt.Key_Down);
        compare(b.cursorTaskId, before, "Down on a filter chip moved the board cursor");
        keyClick(Qt.Key_Escape);
        verify(!chip.activeFocus, "Esc must hand the keyboard back to the view");
    }

    function test_mini_week_and_day_panel_move_the_day() {
        const days = byName("miniweek-days");
        verify(days !== null);
        days.forceActiveFocus(Qt.TabFocusReason);
        const d0 = AppController.selectedDate;
        keyClick(Qt.Key_Right);
        verify(sameDay(AppController.selectedDate, plusDays(d0, 1)), "→ on the mini week");
        keyClick(Qt.Key_Home);
        verify(sameDay(AppController.selectedDate, AppController.today));

        const cal = find(tc.win.contentItem, function (it) { return String(it).indexOf("DayCalendar") === 0; });
        verify(cal !== null);
        verify(cal.activeFocusOnTab);
        cal.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Left);
        verify(sameDay(AppController.selectedDate, plusDays(AppController.today, -1)), "← on the day panel");
    }

    function test_settings_search_enter_opens_the_section() {
        AppController.currentView = "settings";
        tryVerify(function () { return tc.win.activeViewItem() && tc.win.activeViewItem().openSection !== undefined; });
        const sv = tc.win.activeViewItem();
        sv.activeSection = "profile";
        const search = byName("settings-search", sv);
        verify(search !== null);
        search.forceActiveFocus();
        for (const ch of "calendar") keyClick(ch.toUpperCase().charCodeAt(0));
        keyClick(Qt.Key_Return);
        compare(sv.activeSection, "calendar");
        sv.searchText = "";
        search.text = "";
        // The section list walks with ↑/↓.
        const row = byName("settings-nav-profile", sv);
        row.forceActiveFocus(Qt.TabFocusReason);
        compare(sv.activeSection, "profile");
        keyClick(Qt.Key_Down);
        compare(sv.activeSection, "appearance");
        verify(sv.openSection("notifications"));
        compare(sv.activeSection, "notifications");
    }

    function test_tweaks_does_not_trap_tab() {
        let tweaks = null;
        const ps = popups();
        for (let i = 0; i < ps.length; i++) if (String(ps[i]).indexOf("TweaksPanel") === 0) tweaks = ps[i];
        verify(tweaks !== null);
        AppController.currentView = "board";
        tc.win.runCommand("tweaks.open");
        tryCompare(tweaks, "opened", true);
        tweaks.contentItem.forceActiveFocus();
        keyClick(Qt.Key_Tab);
        const f = tc.win.activeFocusItem;
        verify(f !== null && String(f).indexOf("QQuickPopupItem") !== 0, "Tab stayed on the popup: " + f);
        keyClick(Qt.Key_Escape);
        tryCompare(tweaks, "opened", false);
    }

    // The paused-tour pill and its ✕ were bare MouseAreas (design audit
    // DES-19): now each is a named ClickArea, a Tab stop while the pill shows.
    function test_resume_guide_pill_is_named() {
        const resume = byName("resume-guide");
        const giveUp = byName("resume-guide-give-up");
        verify(resume !== null && giveUp !== null);
        compare(resume.Accessible.name, I18n.t("welcome.resume"));
        compare(giveUp.Accessible.name, I18n.t("welcome.giveUp"));
        compare(giveUp._tipText, I18n.t("welcome.giveUp"));
        compare(resume.activeFocusOnTab, resume.parent.visible);
    }
}
