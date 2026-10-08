.pragma library

// The toasts' clock (APP-225), kept pure so its rules are testable without
// one: callers pass `now`.
//
// A toast used to count down from the moment it was shown: 2.4 s for a
// notice, 5 s for an Undo, whether or not anyone could see it. On a big
// monitor, with the eyes on the other side of the screen, it was gone
// before it was noticed. Now:
//  - a notice stays about 4 s, a warning 5.5 s, an error 8 s, and anything
//    with an action (Undo, Retry, Show) at least 8 s, or longer if the
//    caller asked for longer;
//  - the countdown stands still while the toast cannot be read: the
//    pointer is on it, the keyboard is in it, the window is in the
//    background or minimized. It starts when the toast can be seen.
//
// A toast keeps `left` (ms still to run) and `since` (when that countdown
// last started, or -1 while it is held).

var INFO_MS = 4000;
var WARNING_MS = 5500;
var ERROR_MS = 8000;
var ACTION_MS = 8000;

// How long a toast of this kind stays up, in ms. `seconds` is what the
// caller asked for (0 = the kind's own); it can make a toast longer, never
// shorter than its kind and action allow.
function duration(kind, seconds, hasAction) {
    let ms = kind === "error" ? ERROR_MS : kind === "warning" ? WARNING_MS : INFO_MS;
    if (hasAction) ms = Math.max(ms, ACTION_MS);
    const asked = Number(seconds);
    if (isFinite(asked) && asked > 0) ms = Math.max(ms, Math.round(asked * 1000));
    return ms;
}

// What is left of a toast's time at `now`.
function remaining(item, now) {
    if (item.since === undefined || item.since < 0) return item.left;
    return item.left - Math.max(0, now - item.since);
}

// (Re)starts a toast's whole time: running from `now`, or held until it
// can be seen.
function start(item, ms, now, held) {
    item.left = ms;
    item.since = held ? -1 : now;
    return item;
}

// Stops the countdown, keeping what is left.
function hold(item, now) {
    if (item.since !== undefined && item.since >= 0) {
        item.left = remaining(item, now);
        item.since = -1;
    }
    return item;
}

// Lets a held countdown run on from `now`.
function resume(item, now) {
    if (item.since === undefined || item.since < 0) item.since = now;
    return item;
}

// Splits the stack at `now`: the toasts still up, how many ran out, and
// how long until the next one does (Infinity when none is counting down).
function sweep(items, now) {
    const keep = [];
    let next = Infinity;
    for (let i = 0; i < items.length; i++) {
        const left = remaining(items[i], now);
        if (left <= 0) continue;
        keep.push(items[i]);
        if (items[i].since >= 0) next = Math.min(next, left);
    }
    return { keep: keep, expired: items.length - keep.length, next: next };
}

// Where the stack sits: in the bottom-right corner of the work area once
// it is wide enough that the centre is far from where the eyes are, at
// the bottom centre otherwise.
function corner(areaWidth, wideFrom) {
    return areaWidth >= wideFrom;
}
