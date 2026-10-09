.pragma library

// A meeting's repeat rule in words, and the words of a one-line input made
// into a rule and a length (X-Dlg-Event, DG-120). Pure: the strings come in
// through `i18n` (the I18n singleton), so this file is testable alone.

var DAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];

function parts(rule) {
    var out = {};
    var chunks = String(rule || "").toUpperCase().replace(/^RRULE:/, "").split(";");
    for (var i = 0; i < chunks.length; i++) {
        var eq = chunks[i].indexOf("=");
        if (eq > 0) out[chunks[i].slice(0, eq)] = chunks[i].slice(eq + 1);
    }
    return out;
}

// "каждую неделю по пятницам", "раз в 2 недели", "по будням", "не повторяется".
// `startDay` (a Date) names the weekday of a weekly rule without BYDAY.
function describe(rule, startDay, i18n) {
    if (!rule || String(rule).trim().length === 0) return i18n.t("event.repeat.none");
    var p = parts(rule);
    var n = p.INTERVAL ? parseInt(p.INTERVAL) : 1;
    var days = p.BYDAY ? p.BYDAY.split(",") : [];
    var out = "";
    if (p.FREQ === "DAILY") out = n > 1 ? i18n.count(n, "event.repeat.everyNDays") : i18n.t("event.repeat.daily");
    else if (p.FREQ === "WEEKLY") {
        if (days.length === 5 && days.join(",") === "MO,TU,WE,TH,FR" && n === 1) out = i18n.t("event.repeat.weekdays");
        else {
            if (days.length === 0 && startDay && startDay.getDay) days = [DAYS[(startDay.getDay() + 6) % 7]];
            var names = days.map(function (d) { return i18n.t("event.repeat.on." + d); }).join(", ");
            out = n > 1 ? i18n.count(n, "event.repeat.everyNWeeks") : i18n.t("event.repeat.weeklyOn").arg(names);
        }
    } else if (p.FREQ === "MONTHLY") out = n > 1 ? i18n.count(n, "event.repeat.everyNMonths") : i18n.t("event.repeat.monthly");
    else if (p.FREQ === "YEARLY") out = i18n.t("event.repeat.yearly");
    else return String(rule);
    if (p.COUNT) out += " · " + i18n.count(parseInt(p.COUNT), "event.repeat.times");
    if (p.UNTIL) out += " · " + i18n.t("event.repeat.until").arg(p.UNTIL.slice(6, 8) + "." + p.UNTIL.slice(4, 6) + "." + p.UNTIL.slice(0, 4));
    return out;
}

// The rule a chrono recurrence ("every:week", "every:fri", "every:month:15")
// stands for.
function fromChrono(rec) {
    var r = String(rec || "");
    if (r.length === 0) return "";
    if (r === "every:day") return "FREQ=DAILY";
    if (r === "every:weekday") return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR";
    if (r === "every:week") return "FREQ=WEEKLY";
    var m = r.match(/^every:month:(\d+)$/);
    if (m) return "FREQ=MONTHLY;BYMONTHDAY=" + m[1];
    var d = r.match(/^every:(mon|tue|wed|thu|fri|sat|sun)$/);
    if (d) return "FREQ=WEEKLY;BYDAY=" + DAYS[["mon", "tue", "wed", "thu", "fri", "sat", "sun"].indexOf(d[1])];
    return "";
}

// What the chrono parser does not read, taken out of the line first:
// "каждые 2 недели" / "every 2 weeks" (a rule) and "на 1 ч" / "for 30 min"
// (a length). { text, rule, minutes, ruleText, lengthText }.
function extract(raw) {
    var text = String(raw || "");
    var out = { text: text, rule: "", minutes: 0, ruleText: "", lengthText: "" };
    var every = /(?:^|\s)(каждые|каждых|every)\s+(\d+)\s+(недел[а-яё]*|weeks?|дн[а-яё]*|days?|месяц[а-яё]*|months?)(?=\s|$)/i;
    var m = text.match(every);
    if (m) {
        var n = parseInt(m[2]);
        var unit = m[3].toLowerCase();
        var freq = /^(недел|week)/.test(unit) ? "WEEKLY" : /^(дн|day)/.test(unit) ? "DAILY" : "MONTHLY";
        out.rule = "FREQ=" + freq + (n > 1 ? ";INTERVAL=" + n : "");
        out.ruleText = m[0].trim();
        text = text.replace(m[0], " ");
    }
    var len = /(?:^|\s)(на|for)\s+(\d+(?:[.,]\d+)?)\s*(ч|час[а-яё]*|h|hours?|мин[а-яё]*|m|min|minutes?)(?=\s|$)/i;
    var l = text.match(len);
    if (l) {
        var v = parseFloat(l[2].replace(",", "."));
        var hours = /^(ч|час|h)/i.test(l[3]);
        out.minutes = Math.round(hours ? v * 60 : v);
        out.lengthText = l[0].trim();
        text = text.replace(l[0], " ");
    }
    out.text = text.replace(/\s+/g, " ").trim();
    return out;
}
