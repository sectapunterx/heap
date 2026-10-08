// The date arithmetic behind drag-to-reschedule (qml/Reschedule.js, APP-249).
// No clock: "today" is handed in, so every rule is checked against fixed days.
import QtQuick
import QtTest
import "../../qml/Reschedule.js" as R

TestCase {
    name: "Reschedule"

    // Wed 14 Oct 2026. Its week runs Mon 12 – Sun 18.
    readonly property var wed: new Date(2026, 9, 14)

    function d(y, m, day, h, min) { return new Date(y, m - 1, day, h || 0, min || 0); }
    function sameMinute(a, b) { return a.getTime() === b.getTime(); }

    // ── Month / week day drops ──
    function test_a_drop_on_a_day_keeps_the_planned_time() {
        const r = R.dropOnDay(d(2026, 10, 20), d(2026, 10, 14, 9, 30), true);
        verify(sameMinute(r.when, d(2026, 10, 20, 9, 30)));
        verify(r.timed);
    }
    function test_a_drop_on_a_day_without_a_time_is_the_day() {
        const r = R.dropOnDay(d(2026, 10, 20), d(2026, 10, 14, 9, 30), false);
        verify(sameMinute(r.when, d(2026, 10, 20)));
        verify(!r.timed);
        const none = R.dropOnDay(d(2026, 10, 20), null, true);
        verify(sameMinute(none.when, d(2026, 10, 20)));
        verify(!none.timed, "no schedule, no time to keep");
    }
    function test_at_hour() {
        verify(sameMinute(R.atHour(d(2026, 10, 20), 13.5), d(2026, 10, 20, 13, 30)));
        verify(sameMinute(R.atHour(d(2026, 10, 20), 24), d(2026, 10, 20, 23, 59)), "24:00 is the last minute of the day");
    }

    // ── Timeline groups ──
    function test_field_follows_the_grouping() {
        compare(R.fieldOf({ scheduledOnly: true }), "scheduled");
        compare(R.fieldOf({ scheduledOnly: false }), "due");
    }
    function test_today_and_tomorrow_are_themselves() {
        const t = R.timelineTarget("today", "later", d(2026, 11, 30), false, wed);
        verify(t.ok && !t.clear);
        verify(sameMinute(t.when, d(2026, 10, 14)));
        const n = R.timelineTarget("tomorrow", "today", d(2026, 10, 14), false, wed);
        verify(sameMinute(n.when, d(2026, 10, 15)));
    }
    function test_this_week_is_its_first_workday() {
        // Today Wed: this week is Fri 16 – Sun 18; Fri is a workday.
        const t = R.timelineTarget("thisweek", "today", d(2026, 10, 14), false, wed);
        verify(sameMinute(t.when, d(2026, 10, 16)));
        // Today Thu 15: this week is Sat 17 – Sun 18, no workday — its first day.
        const thu = R.timelineTarget("thisweek", "today", null, false, d(2026, 10, 15));
        verify(thu.ok);
        verify(sameMinute(thu.when, d(2026, 10, 17)));
    }
    function test_this_week_is_not_a_target_at_the_weekend() {
        verify(!R.timelineTarget("thisweek", "today", null, false, d(2026, 10, 17)).ok, "Saturday");
        verify(!R.timelineTarget("thisweek", "today", null, false, d(2026, 10, 18)).ok, "Sunday");
        // Friday: tomorrow is Saturday, so this week is only Sunday.
        verify(sameMinute(R.timelineTarget("thisweek", "today", null, false, d(2026, 10, 16)).when, d(2026, 10, 18)));
    }
    function test_next_week_and_later_take_their_monday() {
        verify(sameMinute(R.timelineTarget("nextweek", "today", null, false, wed).when, d(2026, 10, 19)));
        verify(sameMinute(R.timelineTarget("later", "today", null, false, wed).when, d(2026, 10, 26)));
        // From a Sunday, next week starts tomorrow.
        verify(sameMinute(R.timelineTarget("nextweek", "today", null, false, d(2026, 10, 18)).when, d(2026, 10, 19)));
    }
    function test_a_timed_value_keeps_its_clock() {
        const t = R.timelineTarget("tomorrow", "today", d(2026, 10, 14, 16, 45), true, wed);
        verify(t.timed);
        verify(sameMinute(t.when, d(2026, 10, 15, 16, 45)));
    }
    function test_no_date_clears_and_overdue_or_own_group_is_no_target() {
        const c = R.timelineTarget("nodl", "today", d(2026, 10, 14), false, wed);
        verify(c.ok && c.clear);
        verify(!R.timelineTarget("overdue", "today", d(2026, 10, 14), false, wed).ok);
        verify(!R.timelineTarget("today", "today", d(2026, 10, 14), false, wed).ok);
    }
    function test_the_dates_land_in_the_group_they_were_dropped_on() {
        // The same rule as AppController.deadlineBucket, by construction.
        const r = R.bucketRange("nextweek", wed);
        verify(sameMinute(r.from, d(2026, 10, 19)));
        verify(sameMinute(r.to, d(2026, 10, 25)));
        compare(R.bucketRange("later", wed).to, null);
    }

    // ── Keys ──
    function test_a_day_and_a_week_keep_the_clock() {
        const r = R.shiftByDays(d(2026, 10, 14, 9, 0), true, 1, null, wed);
        verify(sameMinute(r.when, d(2026, 10, 15, 9, 0)));
        const w = R.shiftByDays(d(2026, 10, 14, 9, 0), true, -7, null, wed);
        verify(sameMinute(w.when, d(2026, 10, 7, 9, 0)));
    }
    function test_a_move_from_nothing_starts_at_the_shown_day_or_today() {
        verify(sameMinute(R.shiftByDays(null, false, 1, d(2026, 10, 20), wed).when, d(2026, 10, 21)));
        verify(sameMinute(R.shiftByDays(null, false, 1, null, wed).when, d(2026, 10, 15)));
    }
    function test_a_day_across_a_month_end() {
        verify(sameMinute(R.shiftByDays(d(2026, 10, 31), false, 1, null, wed).when, d(2026, 11, 1)));
    }
    function test_time_steps_stay_in_the_day() {
        verify(sameMinute(R.shiftByTime(d(2026, 10, 14, 9, 0), true, 1, 15).when, d(2026, 10, 14, 9, 15)));
        verify(sameMinute(R.shiftByTime(d(2026, 10, 14, 0, 0), true, -1, 15).when, d(2026, 10, 14, 0, 0)));
        verify(sameMinute(R.shiftByTime(d(2026, 10, 14, 23, 45), true, 1, 15).when, d(2026, 10, 14, 23, 45)));
        compare(R.shiftByTime(d(2026, 10, 14), false, 1, 15), null, "an untimed value has no clock to move");
    }
}
