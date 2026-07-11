// DatePickerPopup contract tests (smoke + public API).
//
// Covers the picked(date) signal contract, openAt() seeding/anchoring, the
// month-nav _step() year wrap and the _sameDay() day comparator. The component
// has no objectNames, so there are no click-driven tests — API level only.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DatePickerPopup"
    when: windowShown
    visible: true
    width: 400
    height: 400

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // Smoke: the popup instantiates standalone against the live module.
    function test_smoke_load() {
        make('import TodoCpp; DatePickerPopup { }');
    }

    // Signal contract: picked(date value) carries the exact calendar day.
    function test_picked_signal_contract() {
        const dp = make('import TodoCpp; DatePickerPopup { }');
        const target = new Date();
        target.setDate(target.getDate() + 420);
        target.setHours(0, 0, 0, 0);

        let got = null;
        dp.picked.connect(function(value) { got = value; });
        dp.picked(target);

        verify(got !== null, "picked did not deliver its argument");
        compare(got.getFullYear(), target.getFullYear());
        compare(got.getMonth(), target.getMonth());
        compare(got.getDate(), target.getDate());
    }

    // openAt(d, anchor): seeds selected + the visible month/year from d,
    // reparents to the anchor and opens. Closed again so the modal overlay
    // never leaks into other tests.
    function test_open_at_seeds_selection() {
        const dp = make('import TodoCpp; DatePickerPopup { }');
        const target = new Date();
        target.setDate(target.getDate() + 421);
        target.setHours(0, 0, 0, 0);

        dp.openAt(target, host);
        tryCompare(dp, "opened", true);

        verify(dp._sameDay(dp.selected, target), "selected must match the seeded date");
        compare(dp._month, target.getMonth());
        compare(dp._year, target.getFullYear());
        compare(dp.parent, host);

        dp.close();
        tryCompare(dp, "opened", false);
    }

    // openAt(null): falls back to today. Captured before/after the call so a
    // midnight rollover between the two clock reads cannot flake the test.
    function test_open_at_null_defaults_to_today() {
        const dp = make('import TodoCpp; DatePickerPopup { }');
        const before = new Date();
        dp.openAt(null, host);
        const after = new Date();

        verify(dp._sameDay(dp.selected, before) || dp._sameDay(dp.selected, after),
               "openAt(null) must seed today's date");
        compare(dp._month, dp.selected.getMonth());
        compare(dp._year, dp.selected.getFullYear());

        dp.close();
        tryCompare(dp, "opened", false);
    }

    // _step(delta): month nav wraps December → January (and back) with the
    // year carried across the boundary.
    function test_step_wraps_year_boundaries() {
        const dp = make('import TodoCpp; DatePickerPopup { }');

        dp._month = 11;  // December
        dp._year = 2027;
        dp._step(1);
        compare(dp._month, 0);
        compare(dp._year, 2028);

        dp._step(-1);
        compare(dp._month, 11);
        compare(dp._year, 2027);

        dp._step(1);
        dp._step(1);     // Jan → Feb, no wrap
        compare(dp._month, 1);
        compare(dp._year, 2028);
    }

    // _sameDay(a, b): calendar-day equality — ignores time-of-day, rejects
    // different days and null/undefined operands.
    function test_same_day_comparison() {
        const dp = make('import TodoCpp; DatePickerPopup { }');
        const day = new Date();
        day.setDate(day.getDate() + 422);
        day.setHours(9, 15, 0, 0);
        const sameDayLater = new Date(day);
        sameDayLater.setHours(23, 45, 0, 0);
        const nextDay = new Date(day);
        nextDay.setDate(nextDay.getDate() + 1);

        verify(dp._sameDay(day, sameDayLater), "same day, different times → true");
        verify(!dp._sameDay(day, nextDay), "different days → false");
        verify(!dp._sameDay(null, day), "null lhs → falsy");
        verify(!dp._sameDay(day, null), "null rhs → falsy");
    }
}
