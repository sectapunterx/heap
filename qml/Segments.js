.pragma library

// Cutting an event into the pieces a day can draw.
//
// An event used to be one block on one day, so every view could read `start`
// and `end` straight off the model. Two shapes broke that: an all-day event,
// which has no hours at all, and a timed event that crosses midnight, which is
// one event the user entered once and two blocks the grid has to draw.
//
// src/cal/EventSpan.h normalizes what gets stored — `endDate` is the last day
// covered, `allDay` means the hours carry no meaning. This turns that span into
// per-day pieces. Both are needed: the C++ side is what every write path goes
// through, and this is what every view reads.

// Midnight of the day `d` falls in, as a Date. Views hand us Dates that carry
// whatever time the model, a drag or a `new Date()` left on them, and two
// events on the same day must compare equal regardless.
function _midnight(d) {
    if (!d || !d.getFullYear) return null;
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function _days(a, b) {
    const x = _midnight(a), y = _midnight(b);
    if (!x || !y) return 0;
    // Through UTC, so a DST change inside the range cannot round the division
    // to the wrong whole day.
    return Math.round((Date.UTC(y.getFullYear(), y.getMonth(), y.getDate())
                     - Date.UTC(x.getFullYear(), x.getMonth(), x.getDate())) / 86400000);
}

function sameDay(a, b) {
    return _days(a, b) === 0;
}

// The last day an event covers. A single-day event reports its own day, so
// callers never have to test for a missing end date.
function lastDay(ev) {
    const start = _midnight(ev.date);
    if (!start) return null;
    const end = _midnight(ev.endDate);
    return (end && _days(start, end) > 0) ? end : start;
}

// Days touched, counting both ends. 1 for an ordinary event.
function dayCount(ev) {
    const start = _midnight(ev.date);
    if (!start) return 1;
    return Math.max(1, _days(start, lastDay(ev)) + 1);
}

function multiDay(ev) {
    return dayCount(ev) > 1;
}

// An all-day event has no hours to put on the grid, so it goes in the strip
// above it. A timed event that crosses midnight does NOT: it has real hours on
// each day it touches, and burying it in the strip would lose them.
function isStrip(ev) {
    return !!ev.allDay;
}

function covers(ev, day) {
    const start = _midnight(ev.date);
    if (!start || !_midnight(day)) return false;
    return _days(start, day) >= 0 && _days(day, lastDay(ev)) >= 0;
}

// The piece of `ev` that falls on `day`, or null when it falls on none.
//
// `first` and `last` say whether this piece carries the event's own start and
// end, so a delegate can round only the outer corners and label only the piece
// that begins the event.
function segmentOn(ev, day) {
    if (!covers(ev, day)) return null;
    const first = _days(ev.date, day) === 0;
    const last = _days(day, lastDay(ev)) === 0;
    return {
        id: ev.id,
        start: (ev.allDay || !first) ? 0 : ev.start,
        end: (ev.allDay || !last) ? 24 : ev.end,
        first: first,
        last: last,
        allDay: !!ev.allDay
    };
}

// Every timed piece that lands on `day`, shaped for Overlap.compute().
// All-day events are excluded: they belong to the strip, and letting them into
// the overlap sweep would squeeze every real meeting into a sliver.
function timedOn(events, day) {
    const out = [];
    for (let i = 0; i < events.length; i++) {
        const ev = events[i];
        if (isStrip(ev)) continue;
        const seg = segmentOn(ev, day);
        if (seg) out.push(seg);
    }
    return out;
}

// The all-day events covering `day`, longest first so the bars that span the
// most days sit at the top of the strip and stay visually continuous across
// the week instead of jumping rows. Ties break on the earlier start date —
// note `_days(b, a)`, since _days() counts forward from its first argument and
// a comparator wants the opposite sign.
function stripOn(events, day) {
    const out = [];
    for (let i = 0; i < events.length; i++) {
        if (isStrip(events[i]) && covers(events[i], day)) out.push(events[i]);
    }
    out.sort(function (a, b) {
        return (dayCount(b) - dayCount(a))
            || (_days(b.date, a.date))
            || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
    });
    return out;
}

// Rows for a week strip: each bar gets the first row where it does not collide
// with one already placed, so bars stack instead of overlapping. `days` is the
// list of days on screen, in order.
//
// Returns { id: row } plus the row count, since the strip's height is the
// caller's problem and it cannot know it before laying the bars out.
function stripRows(events, days) {
    if (!days || days.length === 0) return { rows: {}, count: 0 };
    // stripOn() answers for one day; the strip needs the union across the
    // range, in the same order, so a bar keeps its row as the week scrolls.
    const seen = {};
    const all = [];
    for (let d = 0; d < days.length; d++) {
        const onDay = stripOn(events, days[d]);
        for (let i = 0; i < onDay.length; i++) {
            if (!seen[onDay[i].id]) { seen[onDay[i].id] = true; all.push(onDay[i]); }
        }
    }
    all.sort(function (a, b) {
        return (dayCount(b) - dayCount(a))
            || (_days(b.date, a.date))
            || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
    });

    const rows = {};
    const rowEnds = [];   // the last day index occupied in each row
    for (let i = 0; i < all.length; i++) {
        const ev = all[i];
        const from = _days(days[0], ev.date);
        const to = _days(days[0], lastDay(ev));
        let placed = false;
        for (let r = 0; r < rowEnds.length; r++) {
            if (from > rowEnds[r]) { rowEnds[r] = to; rows[ev.id] = r; placed = true; break; }
        }
        if (!placed) { rows[ev.id] = rowEnds.length; rowEnds.push(to); }
    }
    return { rows: rows, count: rowEnds.length };
}

// Where a bar starts and how far it runs, in day indices clipped to the range
// on screen — a trip that began last week still shows its tail this week.
function barExtent(ev, days) {
    if (!days || days.length === 0) return null;
    const from = Math.max(0, _days(days[0], ev.date));
    const to = Math.min(days.length - 1, _days(days[0], lastDay(ev)));
    if (to < from) return null;
    return { from: from, span: (to - from) + 1,
             clippedStart: _days(days[0], ev.date) < 0,
             clippedEnd: _days(days[0], lastDay(ev)) > days.length - 1 };
}
