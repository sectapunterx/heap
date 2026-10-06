.pragma library

// Pure helpers for the small motions (APP-167), so the rules are testable
// without a clock: callers pass `now`.

// How long after a task is marked done its card still celebrates it. The
// board builds a new card in the Done column for a moved task, so the card
// that shows the check mark is often one that did not exist a moment ago.
var DONE_WINDOW_MS = 1500;

function _ms(t) {
    if (t === undefined || t === null || t === "") return NaN;
    if (t instanceof Date) return t.getTime();
    if (typeof t === "number") return t;
    return new Date(t).getTime();
}

// True when a task with `status`, last changed at `changedAt` (a Date, an ISO
// string or ms), was marked done no longer than DONE_WINDOW_MS before `now`.
function justCompleted(status, changedAt, now) {
    if (status !== "done") return false;
    var at = _ms(changedAt);
    var n = _ms(now);
    if (isNaN(at) || isNaN(n)) return false;
    var age = n - at;
    return age >= 0 && age <= DONE_WINDOW_MS;
}

// Where a dropped card starts its settle: the offset from its home slot to
// the point it was let go, scaled by Theme.motion (0 with reduced motion), so
// it springs the rest of the way home instead of jumping.
function settleFrom(dropX, dropY, homeX, homeY, motion) {
    var m = motion > 0 ? 1 : 0;
    return { x: (dropX - homeX) * m, y: (dropY - homeY) * m };
}
