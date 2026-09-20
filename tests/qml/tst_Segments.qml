// Cutting an event into the pieces a day can draw (qml/Segments.js).
//
// An event used to be one block on one day. An all-day event has no hours at
// all, and a timed event that crosses midnight is one event the user entered
// once and two blocks the grid has to draw. Every view now reads its pieces
// from here instead of taking `start` and `end` off the model directly.
import QtQuick
import QtTest
import "../../qml/Segments.js" as Seg

TestCase {
    id: tc
    name: "Segments"

    function day(offset) {
        const d = new Date(2026, 8, 21);   // a Monday
        d.setDate(d.getDate() + offset);
        return d;
    }

    // Views hand these around with whatever time of day happens to be on them,
    // which is exactly the trap the module has to survive.
    function noon(offset) {
        const d = day(offset);
        d.setHours(12, 30, 0, 0);
        return d;
    }

    function ev(id, from, to, start, end, allDay) {
        return {
            id: id,
            date: day(from),
            endDate: to === null ? undefined : day(to),
            start: start,
            end: end,
            allDay: !!allDay
        };
    }

    function test_an_ordinary_event_covers_one_day() {
        const e = ev("a", 0, null, 9, 10, false);
        compare(Seg.dayCount(e), 1);
        verify(!Seg.multiDay(e));
        verify(Seg.covers(e, day(0)));
        verify(!Seg.covers(e, day(1)));
        verify(!Seg.covers(e, day(-1)));
    }

    // The time of day on the Date must not decide which day an event is on.
    function test_the_clock_on_a_date_is_ignored() {
        const e = ev("a", 0, null, 9, 10, false);
        verify(Seg.covers(e, noon(0)));
        verify(Seg.sameDay(day(0), noon(0)));
    }

    function test_a_missing_end_date_means_the_same_day() {
        const e = ev("a", 0, null, 9, 10, false);
        compare(Seg.lastDay(e).getDate(), day(0).getDate());
    }

    // An end date before the start is corrupt input, not a negative span.
    function test_an_end_date_before_the_start_is_ignored() {
        const e = ev("a", 0, -3, 9, 10, false);
        compare(Seg.dayCount(e), 1);
    }

    function test_a_multi_day_event_covers_every_day_between() {
        const e = ev("a", 0, 2, 9, 10, false);
        compare(Seg.dayCount(e), 3);
        verify(Seg.multiDay(e));
        verify(Seg.covers(e, day(0)));
        verify(Seg.covers(e, day(1)));
        verify(Seg.covers(e, day(2)));
        verify(!Seg.covers(e, day(3)));
    }

    // The reason this file exists: 22:00 Monday to 02:00 Tuesday is two blocks.
    function test_a_cross_midnight_event_yields_two_segments() {
        const e = ev("a", 0, 1, 22, 2, false);

        const first = Seg.segmentOn(e, day(0));
        compare(first.start, 22);
        compare(first.end, 24);
        verify(first.first);
        verify(!first.last);

        const second = Seg.segmentOn(e, day(1));
        compare(second.start, 0);
        compare(second.end, 2);
        verify(!second.first);
        verify(second.last);
    }

    // A middle day of a long timed event is the whole day.
    function test_a_middle_day_runs_midnight_to_midnight() {
        const e = ev("a", 0, 2, 22, 2, false);
        const mid = Seg.segmentOn(e, day(1));
        compare(mid.start, 0);
        compare(mid.end, 24);
        verify(!mid.first);
        verify(!mid.last);
    }

    function test_a_day_outside_the_span_has_no_segment() {
        const e = ev("a", 0, 1, 22, 2, false);
        compare(Seg.segmentOn(e, day(5)), null);
    }

    // An all-day event has no hours, whatever happens to be stored in them.
    function test_an_all_day_segment_has_no_hours() {
        const e = ev("a", 0, null, 9, 10, true);
        const seg = Seg.segmentOn(e, day(0));
        compare(seg.start, 0);
        compare(seg.end, 24);
        verify(seg.allDay);
    }

    // A cross-midnight event keeps its hours and stays on the grid; only an
    // all-day event moves to the strip.
    function test_only_all_day_events_go_in_the_strip() {
        verify(Seg.isStrip(ev("a", 0, null, 9, 10, true)));
        verify(!Seg.isStrip(ev("b", 0, 1, 22, 2, false)));
        verify(!Seg.isStrip(ev("c", 0, null, 9, 10, false)));
    }

    function test_timed_on_excludes_all_day_events() {
        const evs = [ev("timed", 0, null, 9, 10, false), ev("allday", 0, null, 0, 24, true)];
        const out = Seg.timedOn(evs, day(0));
        compare(out.length, 1);
        compare(out[0].id, "timed");
    }

    function test_timed_on_includes_the_tail_of_a_cross_midnight_event() {
        const evs = [ev("night", 0, 1, 22, 2, false)];
        const out = Seg.timedOn(evs, day(1));
        compare(out.length, 1);
        compare(out[0].start, 0);
        compare(out[0].end, 2);
    }

    function test_strip_on_reports_only_the_days_covered() {
        const evs = [ev("trip", 0, 2, 0, 24, true)];
        compare(Seg.stripOn(evs, day(1)).length, 1);
        compare(Seg.stripOn(evs, day(3)).length, 0);
    }

    // The longest bar first, so a week's strip does not reshuffle as the eye
    // moves across it.
    function test_strip_on_puts_the_longest_bar_first() {
        const evs = [ev("short", 1, null, 0, 24, true), ev("long", 0, 4, 0, 24, true)];
        const out = Seg.stripOn(evs, day(1));
        compare(out.length, 2);
        compare(out[0].id, "long");
    }

    function week() {
        const days = [];
        for (let i = 0; i < 7; i++) days.push(day(i));
        return days;
    }

    function test_two_disjoint_bars_share_a_row() {
        const evs = [ev("a", 0, 1, 0, 24, true), ev("b", 3, 4, 0, 24, true)];
        const laid = Seg.stripRows(evs, week());
        compare(laid.count, 1);
        compare(laid.rows["a"], 0);
        compare(laid.rows["b"], 0);
    }

    function test_two_overlapping_bars_stack() {
        const evs = [ev("a", 0, 3, 0, 24, true), ev("b", 2, 4, 0, 24, true)];
        const laid = Seg.stripRows(evs, week());
        compare(laid.count, 2);
        verify(laid.rows["a"] !== laid.rows["b"]);
    }

    // Bars that touch end-to-start still need separate rows: Monday–Tuesday and
    // Tuesday–Wednesday share Tuesday.
    function test_bars_that_share_a_day_stack() {
        const evs = [ev("a", 0, 1, 0, 24, true), ev("b", 1, 2, 0, 24, true)];
        const laid = Seg.stripRows(evs, week());
        compare(laid.count, 2);
    }

    function test_an_empty_range_lays_out_nothing() {
        const laid = Seg.stripRows([], week());
        compare(laid.count, 0);
    }

    function test_a_bar_reports_where_it_starts_and_how_far_it_runs() {
        const e = ev("a", 1, 3, 0, 24, true);
        const ext = Seg.barExtent(e, week());
        compare(ext.from, 1);
        compare(ext.span, 3);
        verify(!ext.clippedStart);
        verify(!ext.clippedEnd);
    }

    // A trip that began last week still shows its tail this week rather than
    // vanishing or drawing off the left edge.
    function test_a_bar_from_before_the_range_is_clipped_to_it() {
        const e = ev("a", -3, 1, 0, 24, true);
        const ext = Seg.barExtent(e, week());
        compare(ext.from, 0);
        compare(ext.span, 2);
        verify(ext.clippedStart);
    }

    function test_a_bar_running_past_the_range_is_clipped_to_it() {
        const e = ev("a", 5, 20, 0, 24, true);
        const ext = Seg.barExtent(e, week());
        compare(ext.from, 5);
        compare(ext.span, 2);
        verify(ext.clippedEnd);
    }

    function test_a_bar_entirely_outside_the_range_has_no_extent() {
        const e = ev("a", 20, 22, 0, 24, true);
        compare(Seg.barExtent(e, week()), null);
    }

    // A month boundary is where naive day arithmetic breaks.
    function test_a_span_across_a_month_boundary_counts_correctly() {
        const e = { id: "a", date: new Date(2026, 8, 29), endDate: new Date(2026, 9, 2),
                    start: 0, end: 24, allDay: true };
        compare(Seg.dayCount(e), 4);   // Sep 29, Sep 30, Oct 1, Oct 2
        verify(Seg.covers(e, new Date(2026, 9, 1)));
    }

    // And a year boundary.
    function test_a_span_across_a_year_boundary_counts_correctly() {
        const e = { id: "a", date: new Date(2026, 11, 30), endDate: new Date(2027, 0, 2),
                    start: 0, end: 24, allDay: true };
        compare(Seg.dayCount(e), 4);
        verify(Seg.covers(e, new Date(2027, 0, 1)));
    }

    function test_a_missing_date_does_not_throw() {
        const e = { id: "a", date: undefined, endDate: undefined, start: 9, end: 10, allDay: false };
        compare(Seg.dayCount(e), 1);
        verify(!Seg.covers(e, day(0)));
        compare(Seg.segmentOn(e, day(0)), null);
    }
}
