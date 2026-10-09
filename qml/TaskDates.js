// How a task's date reads on a board card and in a list row (APP-262/263).
// Not a library: it uses the I18n and AppController singletons of the file
// that imports it.

// Whole days from `today` to `d` (negative = past); NaN for no date.
function daysFrom(d, today) {
    if (!d || !d.getTime || isNaN(d.getTime())) return NaN;
    const a = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
    const b = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    return Math.round((b - a) / 86400000);
}

// The card: "сегодня" / "завтра", a weekday this week ("сб"), else "13 окт";
// a clock time after it when the date has one. Past dates are counted.
function cardText(d, hasTime, today) {
    const days = daysFrom(d, today);
    if (isNaN(days)) return "";
    const clock = hasTime ? " " + I18n.fmtTime(d) : "";
    if (days < 0) return I18n.t("task.due.overdue").arg(-days) + clock;
    if (days === 0) return I18n.t("task.due.today") + clock;
    if (days === 1) return I18n.t("task.due.tomorrow") + clock;
    if (days < 7) return I18n.dayName(d.getDay()) + clock;
    return I18n.fmtDate(d, "dayMonth") + clock;
}

// The list row, right-aligned: "сегодня", "сб, 10 окт", "9 окт · 15:00".
function rowText(d, hasTime, today) {
    const days = daysFrom(d, today);
    if (isNaN(days)) return "";
    const clock = hasTime ? " · " + I18n.fmtTime(d) : "";
    if (days === 0) return I18n.t("task.due.today") + clock;
    if (days > 0 && days < 14) return I18n.fmtDate(d, "weekdayDay") + clock;
    return I18n.fmtDate(d, "dayMonth") + clock;
}
