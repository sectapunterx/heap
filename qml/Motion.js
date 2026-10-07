.pragma library

// Pure helpers for the small motions (APP-167), so the rules are testable
// without a clock: callers pass `now`.

// The stack over the Done column (APP-176): at most this many bars, newest
// on top, however long the column is.
var STACK_MAX = 5;

// Whether closing a task plays the stack: one card (`moved`), going into
// Done from another column, with motion on. A bulk move and "Reduce motion"
// just move.
function shouldStack(moved, fromStatus, toStatus, motion) {
    return moved === 1 && toStatus === "done" && fromStatus !== "done" && motion > 0;
}

// How many bars the stack shows for a Done column of `count` cards.
function stackBars(count) {
    return Math.max(0, Math.min(STACK_MAX, count | 0));
}

// The width of bar `i`, counted from the bottom, as a share of the column:
// uneven like the heap mark, widest at the base. Counted from the bottom so
// a bar laid on top leaves the ones under it as they were.
function stackBarWidth(i) {
    var w = [0.7, 0.54, 0.62, 0.42, 0.5];
    return w[((i % w.length) + w.length) % w.length];
}

// Where a dropped card starts its settle: the offset from its home slot to
// the point it was let go, scaled by Theme.motion (0 with reduced motion), so
// it glides the rest of the way home instead of jumping.
function settleFrom(dropX, dropY, homeX, homeY, motion) {
    var m = motion > 0 ? 1 : 0;
    return { x: (dropX - homeX) * m, y: (dropY - homeY) * m };
}
