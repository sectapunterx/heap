// Side-by-side layout for events that share a time window (qml/Overlap.js).
//
// Two meetings at 10:00 were drawn exactly on top of each other in the week
// grid: the second hid the first, and only the top one could be clicked. The
// day grid had solved this and the week grid had never been taught, so the
// algorithm now lives in one place and both call it.
import QtQuick
import QtTest
import "../../qml/Overlap.js" as Overlap

TestCase {
    id: tc
    name: "Overlap"

    function ev(id, start, end) {
        return { id: id, start: start, end: end };
    }

    function test_one_event_takes_the_whole_width() {
        const m = Overlap.compute([ev("a", 10, 11)]);
        compare(m["a"].col, 0);
        compare(m["a"].cols, 1);
    }

    function test_two_overlapping_events_split_the_width() {
        const m = Overlap.compute([ev("a", 10, 11), ev("b", 10, 11)]);
        compare(m["a"].cols, 2);
        compare(m["b"].cols, 2);
        verify(m["a"].col !== m["b"].col, "they must not land in the same column");
    }

    function test_three_overlapping_events_split_three_ways() {
        const m = Overlap.compute([ev("a", 10, 12), ev("b", 10.5, 11), ev("c", 10.5, 11.5)]);
        compare(m["a"].cols, 3);
        compare(m["b"].cols, 3);
        compare(m["c"].cols, 3);
        const cols = [m["a"].col, m["b"].col, m["c"].col].sort();
        compare(cols, [0, 1, 2]);
    }

    // Events that merely touch do not overlap: a 10–11 and an 11–12 are
    // consecutive, and forcing them side by side would halve both for nothing.
    function test_back_to_back_events_do_not_overlap() {
        const m = Overlap.compute([ev("a", 10, 11), ev("b", 11, 12)]);
        compare(m["a"].cols, 1);
        compare(m["b"].cols, 1);
    }

    // A column frees up when its event ends, so a third event can reuse it
    // rather than making the whole cluster narrower.
    function test_a_column_is_reused_once_it_is_free() {
        const m = Overlap.compute([ev("a", 9, 10), ev("b", 9, 12), ev("c", 10, 11)]);
        compare(m["b"].cols, 2) << "only two are ever concurrent";
        compare(m["a"].col, m["c"].col);
    }

    // Every member of a cluster gets the cluster's count, so the widths match
    // and the events tile the day exactly instead of leaving a gap.
    function test_a_cluster_shares_one_column_count() {
        const m = Overlap.compute([ev("a", 9, 12), ev("b", 9.5, 10), ev("c", 10.5, 11)]);
        compare(m["a"].cols, m["b"].cols);
        compare(m["b"].cols, m["c"].cols);
    }

    // Two separate clusters are sized independently — a crowded morning must
    // not squeeze a lone afternoon meeting.
    function test_separate_clusters_are_independent() {
        const m = Overlap.compute([ev("a", 9, 10), ev("b", 9, 10), ev("late", 15, 16)]);
        compare(m["a"].cols, 2);
        compare(m["late"].cols, 1);
    }

    function test_input_order_does_not_matter() {
        const forward = Overlap.compute([ev("a", 9, 11), ev("b", 10, 12)]);
        const backward = Overlap.compute([ev("b", 10, 12), ev("a", 9, 11)]);
        compare(forward["a"].col, backward["a"].col);
        compare(forward["b"].col, backward["b"].col);
        compare(forward["a"].cols, backward["a"].cols);
    }

    function test_an_empty_day_is_an_empty_map() {
        const m = Overlap.compute([]);
        compare(Object.keys(m).length, 0);
    }

    // The week groups by day first: events on different days never overlap,
    // however close their hours are.
    function test_events_on_different_days_do_not_overlap() {
        const m = Overlap.computeByDay([[ev("mon", 10, 11)], [ev("tue", 10, 11)]]);
        compare(m["mon"].cols, 1);
        compare(m["tue"].cols, 1);
    }

    function test_by_day_keeps_each_days_own_clusters() {
        const m = Overlap.computeByDay([
            [ev("m1", 10, 11), ev("m2", 10, 11)],
            [ev("t1", 10, 11)]
        ]);
        compare(m["m1"].cols, 2);
        compare(m["t1"].cols, 1);
    }

    // A zero-length event is degenerate but must not break the sweep.
    function test_a_zero_length_event_is_handled() {
        const m = Overlap.compute([ev("a", 10, 10), ev("b", 10, 11)]);
        verify(m["a"] !== undefined);
        verify(m["b"] !== undefined);
    }
}
