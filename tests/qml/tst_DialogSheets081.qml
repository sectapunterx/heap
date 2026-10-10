// 0.8.1 sheets: the schedule field's Tab picker (N/X-Dlg-Schedule, R3-068/070),
// the web-link question (X-Dlg-Small, R3-076) and the saved-view name read
// from a query (R3-077).
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DialogSheets081"
    when: windowShown
    width: 900
    height: 700

    Item { id: host; anchors.fill: parent }

    function make(src) {
        const o = createTemporaryQmlObject(src, host);
        verify(o !== null);
        return o;
    }
    function byName(root, name) {
        if (!root) return null;
        if (root.objectName === name) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) {
            const f = byName(kids[i], name);
            if (f) return f;
        }
        if (root.contentItem && root.contentItem !== root) return byName(root.contentItem, name);
        return null;
    }

    // As many weeks as the month spans: October 2026 is five, not six.
    function test_grid_has_no_spare_week() {
        const dp = make('import TodoCpp; DatePickerPopup { }');
        dp._month = 9; dp._year = 2026;
        compare(dp._weeks, 5);
        dp._month = 7; dp._year = 2026;   // August 2026 starts on a Saturday
        compare(dp._weeks, 6);
    }

    // With times: the work day's hours, and the answer carries the hour.
    function test_hours_column_picks_a_time() {
        const dp = make('import TodoCpp; DatePickerPopup { withTimes: true }');
        const day = new Date(); day.setDate(day.getDate() + 430); day.setHours(15, 0, 0, 0);
        let got = null, timed = null;
        dp.pickedAt.connect(function (v, t) { got = v; timed = t; });
        dp.openAt(day, host, true);
        tryCompare(dp, "opened", true);
        compare(dp.hour, 15);
        compare(dp._hours.length, AppController.workdayEnd - AppController.workdayStart);
        verify(byName(dp.contentItem, "date-picker-hours").visible);
        verify(!byName(dp.contentItem, "date-picker-today").visible, "no Today button beside the hours");
        keyClick(Qt.Key_Tab);
        verify(dp._inTimes);
        keyClick(Qt.Key_Up);
        compare(dp.hour, 14);
        keyClick(Qt.Key_Return);
        verify(got !== null);
        verify(timed);
        compare(got.getHours(), 14);
        compare(got.getDate(), day.getDate());
    }

    function test_no_time_answers_a_date_only() {
        const dp = make('import TodoCpp; DatePickerPopup { withTimes: true }');
        let timed = null;
        dp.pickedAt.connect(function (v, t) { timed = t; });
        dp.openAt(new Date(), host, false);
        tryCompare(dp, "opened", true);
        compare(dp.hour, -1);
        keyClick(Qt.Key_Return);
        compare(timed, false);
    }

    // A web link asks first, with the address in full.
    function test_web_link_asks() {
        const d = make('import TodoCpp; LinkConfirmDialog { }');
        d.openLink("https://pay-provider.example/status/8812");
        tryCompare(d, "opened", true);
        verify(d.web);
        compare(d.title, I18n.t("md.link.web.title"));
        d.close();
        tryCompare(d, "opened", false);
    }

    function test_saved_view_name_reads_the_query() {
        const h = make('import TodoCpp; SavedViewsHost { }');
        compare(h.readableQuery("статус:заблокировано p0"), "Заблокировано · P0");
        compare(h.readableQuery('label:"two words" p1'), "Two words · P1");
        compare(h.readableQuery(""), "");
    }
}
