// Design audit DES-19 / DES-22 / DES-18 in the calendar and board views: the
// hand-drawn buttons there (month ‹ ›, mode tabs, the weeks stepper, Today,
// the date picker's header and footer, the board's column header icons, the
// timeline's "Show done") were a bare MouseArea each — no Tab stop, no name,
// no keyboard way to run them. They carry a ClickArea now. These drive them
// with the keyboard only.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ClickAreaViews"
    when: windowShown
    visible: true
    width: 1200
    height: 700

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }
    function find(root, pred) {
        if (!root) return null;
        if (pred(root)) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) { const r = find(kids[i], pred); if (r) return r; }
        return null;
    }
    function byName(root, name) { return find(root, function (it) { return it.objectName === name; }); }
    // The ClickArea a hand-drawn button carries (or the named item itself, when
    // the name is on the ClickArea): the first one with its shape.
    function areaIn(item) {
        return find(item, function (it) {
            return it.keyboardFocused !== undefined && it.label !== undefined && it.activated !== undefined;
        });
    }
    function sameMonth(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth(); }

    function init() { AppController.selectedDate = AppController.today; }

    function test_month_nav_is_on_the_tab_path_named_and_runs_on_return() {
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        wait(20);
        const prev = areaIn(byName(mv, "month-prev"));
        const next = areaIn(byName(mv, "month-next"));
        verify(prev !== null && next !== null, "the ‹ › carry no ClickArea");
        verify(prev.activeFocusOnTab);
        compare(prev.Accessible.name, I18n.t("month.prev"));
        compare(next.Accessible.name, I18n.t("month.next"));
        verify(prev._tipText.indexOf(AppController.shortcutText("cal.prev")) > 0,
               "the tooltip does not name the key: " + prev._tipText);

        const d0 = AppController.selectedDate;
        prev.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        const back = new Date(d0.getFullYear(), d0.getMonth() - 1, 1);
        verify(sameMonth(AppController.selectedDate, back), "Return on ‹ did not step back a month");
        // Tab goes on to ›, and Space runs it.
        keyClick(Qt.Key_Tab);
        verify(next.activeFocus, "Tab from ‹ did not reach ›: " + tc.Window.activeFocusItem);
        keyClick(Qt.Key_Space);
        verify(sameMonth(AppController.selectedDate, d0), "Space on › did not step forward");
    }

    function test_month_mode_tabs_are_radio_buttons() {
        const mv = make('import TodoCpp; MonthView { anchors.fill: parent }');
        wait(20);
        const weeks = areaIn(byName(mv, "month-mode-weeks"));
        verify(weeks !== null);
        compare(weeks.Accessible.role, Accessible.RadioButton);
        verify(!weeks.checked);
        weeks.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        compare(mv.mode, "weeks");
        verify(weeks.checked);
        const more = areaIn(byName(mv, "month-more-weeks"));
        verify(more !== null && more.activeFocusOnTab);
        const n = mv.weeksCount;
        more.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        compare(mv.weeksCount, n + 1);
        compare(areaIn(byName(mv, "month-prev")).Accessible.name, I18n.t("month.prevWeeks"));
    }

    function test_week_arrows_say_what_they_do_and_name_the_key() {
        const wv = make('import TodoCpp; WeekView { anchors.fill: parent }');
        wait(20);
        const prev = byName(wv, "week-prev");
        const next = byName(wv, "week-next");
        verify(prev !== null && next !== null);
        compare(prev.Accessible.name, I18n.t("miniweek.prevWeek"));
        compare(next.Accessible.name, I18n.t("miniweek.nextWeek"));
        verify(prev.ToolTip.text.indexOf(AppController.shortcutFor("cal.prev")) > 0, prev.ToolTip.text);
        verify(next.ToolTip.text.indexOf(AppController.shortcutFor("cal.next")) > 0, next.ToolTip.text);
    }

    function test_date_picker_header_runs_from_the_keyboard() {
        const dp = make('import TodoCpp; DatePickerPopup { }');
        const start = new Date(2031, 4, 15);
        dp.openAt(start, host);
        tryCompare(dp, "opened", true);
        const prev = areaIn(byName(dp.contentItem, "date-picker-prev"));
        verify(prev !== null);
        compare(prev.Accessible.name, I18n.t("month.prev"));
        prev.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        compare(dp._month, 3);
        // Tab comes back round to the grid rather than leaving it for good.
        const today = areaIn(byName(dp.contentItem, "date-picker-today"));
        verify(today !== null && today.activeFocusOnTab);
        dp.close();
        tryCompare(dp, "opened", false);
    }

    // The header icons are hidden at rest and show while the keyboard is on
    // one of them; Return runs it.
    function test_kanban_header_icon_reveals_on_focus_and_runs_on_return() {
        const board = make('import TodoCpp; KanbanBoard { anchors.fill: parent }');
        wait(50);
        const icon = byName(board, "column-move-right");
        verify(icon !== null);
        const bar = byName(board, "column-hover-icons");
        compare(icon.opacity, 0, "the icon shows at rest");
        compare(bar.opacity, 0);
        const area = areaIn(icon);
        verify(area !== null && area.activeFocusOnTab, "a hidden header icon is off the Tab path");
        compare(area.Accessible.name, I18n.t("kanban.moveRight"));

        const first = AppController.statuses[0].id;
        area.forceActiveFocus(Qt.TabFocusReason);
        tryCompare(icon, "opacity", 1);
        tryCompare(bar, "opacity", 1);
        keyClick(Qt.Key_Return);
        tryVerify(function () { return AppController.statuses[1].id === first; }, 2000,
                  "Return on › did not move the column");
        AppController.moveStatus(first, 0);
        compare(AppController.statuses[0].id, first);
    }

    function test_kanban_column_add_is_reachable() {
        const board = make('import TodoCpp; KanbanBoard { anchors.fill: parent }');
        wait(50);
        const add = byName(board, "column-add");
        verify(add !== null);
        verify(add.activeFocusOnTab);
        compare(add.Accessible.name, I18n.t("kanban.addTask"));
        let got = "";
        board.createInStatus.connect(function (sid) { got = sid; });
        add.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        compare(got, AppController.statuses[0].id);
        const fold = areaIn(byName(board, "column-fold"));
        verify(fold._tipText.indexOf(AppController.shortcutText("board.collapseColumn")) > 0, fold._tipText);
    }

    function test_timeline_show_done_is_a_checkbox() {
        const tl = make('import TodoCpp; TimelineView { anchors.fill: parent }');
        wait(20);
        const area = areaIn(byName(tl, "timeline-show-done"));
        verify(area !== null);
        compare(area.Accessible.role, Accessible.CheckBox);
        compare(area.Accessible.name, I18n.t("timeline.showDone"));
        let n = 0;
        tl.toggleShowDone.connect(function () { n++; });
        area.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(n, 1);
    }
}
