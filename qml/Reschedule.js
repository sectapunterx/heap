.pragma library

// Drag-to-reschedule (APP-249): the date arithmetic behind a drop or a key in
// Week, Month and Timeline. Pure — every function that needs "today" is
// handed it, so the rules are testable without a clock (tst_Reschedule.qml).
//
// Dates are local calendar days. A "timed" value keeps its hours and minutes;
// an untimed one is midnight and its clock means nothing.

function valid(d) {
    return !!d && typeof d.getTime === "function" && !isNaN(d.getTime());
}

// The calendar day of `d`, at midnight.
function dayOf(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function addDays(d, n) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes());
}

function sameDay(a, b) {
    return valid(a) && valid(b) && a.getFullYear() === b.getFullYear()
        && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

// Whole days from a to b (b - a), immune to DST.
function daysBetween(a, b) {
    return Math.round((Date.UTC(b.getFullYear(), b.getMonth(), b.getDate())
                     - Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) / 86400000);
}

// `day`, at the clock of `source` when it is timed, else at midnight.
function onDay(day, source, timed) {
    if (timed && valid(source))
        return new Date(day.getFullYear(), day.getMonth(), day.getDate(), source.getHours(), source.getMinutes());
    return new Date(day.getFullYear(), day.getMonth(), day.getDate());
}

// `day` at `hour` (hours since midnight, 13.5 = 13:30).
function atHour(day, hour) {
    const minutes = Math.max(0, Math.min(24 * 60 - 1, Math.round(hour * 60)));
    return new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.floor(minutes / 60), minutes % 60);
}

// A drop on a day cell (Month, and a Week day header): the task is planned
// for that day, at the time it was already planned for if it had one.
// Returns { when, timed }.
function dropOnDay(day, scheduledAt, scheduledHasTime) {
    const timed = !!scheduledHasTime && valid(scheduledAt);
    return { when: onDay(day, scheduledAt, timed), timed: timed };
}

// ── Timeline ──────────────────────────────────────────────────────────
// The groups are AppController.deadlineBucket's: calendar weeks Monday to
// Sunday. Which field a row is grouped by: its deadline, or — for a task
// that only has a schedule — when it is planned.
function fieldOf(row) {
    return row && row.scheduledOnly ? "scheduled" : "due";
}

// The days a group covers, relative to `today`: { from, to } (inclusive), or
// null for a group that is not a span of days ("nodl", "overdue") or that is
// empty today ("thisweek" on a Saturday or Sunday: tomorrow is the rest of it).
function bucketRange(bucket, today) {
    const t = dayOf(today);
    const dow = t.getDay() === 0 ? 7 : t.getDay();        // ISO: Mon=1..Sun=7
    const sunday = addDays(t, 7 - dow);
    switch (bucket) {
    case "today":    return { from: t, to: t };
    case "tomorrow": { const n = addDays(t, 1); return { from: n, to: n }; }
    case "thisweek": {
        const from = addDays(t, 2);
        return from <= sunday ? { from: from, to: sunday } : null;
    }
    case "nextweek": return { from: addDays(sunday, 1), to: addDays(sunday, 7) };
    case "later":    return { from: addDays(sunday, 8), to: null };
    default:         return null;
    }
}

function isWorkday(d) {
    const w = d.getDay();
    return w !== 0 && w !== 6;
}

// Where a row dropped on a group lands. Returns
//   { ok: false }                        — not a drop target (overdue, an
//                                          empty "this week", its own group)
//   { ok: true, clear: true }            — "No date": the field is cleared
//   { ok: true, clear: false, when, timed }
// The day: today and tomorrow are themselves; this week, next week and later
// take the first working day (Mon–Fri) of their span, or its first day when
// it has none. The clock time a timed value had is kept.
function timelineTarget(bucket, fromBucket, current, timed, today) {
    if (bucket === fromBucket || bucket === "overdue") return { ok: false };
    if (bucket === "nodl") return { ok: true, clear: true };
    const r = bucketRange(bucket, today);
    if (!r) return { ok: false };
    let day = r.from;
    for (let i = 0; i < 7; i++) {
        const d = addDays(r.from, i);
        if (r.to && d > r.to) break;
        if (isWorkday(d)) { day = d; break; }
    }
    const keep = !!timed && valid(current);
    return { ok: true, clear: false, when: onDay(day, current, keep), timed: keep };
}

// ── Keys ──────────────────────────────────────────────────────────────
// Ctrl+←/→ (a day) and Ctrl+Shift+←/→ (a week) on the focused task: the
// field moves by `days`, keeping its clock. A field with no date starts from
// `fallbackDay` (the day the task is shown on), else today.
function shiftByDays(current, timed, days, fallbackDay, today) {
    const base = valid(current) ? current : (valid(fallbackDay) ? dayOf(fallbackDay) : dayOf(today));
    const keep = !!timed && valid(current);
    return { when: onDay(addDays(dayOf(base), days), current, keep), timed: keep };
}

// Ctrl+↑/↓: a timed schedule moves by `steps` grid steps of `stepMinutes`,
// staying inside its day. null when there is no clock time to move.
function shiftByTime(current, timed, steps, stepMinutes) {
    if (!timed || !valid(current)) return null;
    const step = Math.max(1, stepMinutes | 0);
    const mins = current.getHours() * 60 + current.getMinutes() + steps * step;
    const clamped = Math.max(0, Math.min(24 * 60 - step, mins));
    return { when: new Date(current.getFullYear(), current.getMonth(), current.getDate(),
                            Math.floor(clamped / 60), clamped % 60), timed: true };
}
