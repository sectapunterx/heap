// The settings item index (APP-207, APP-210): every setting a search can
// find, with the section it lives in. Settings search and the Tweaks panel
// search read this one list — there is no second index.
//
// An entry names a setting by the I18n key of its title, so the text is
// looked up in the current language and in English at search time (people
// search in English in a Russian UI). A key with a "<key>.hint" sibling also
// matches on that hint.
//
// The rows are the source of truth: tests/test_settings_index.cpp reads
// qml/SettingsView.qml and fails when a SettingsRow's or SettingsGroup's
// title key is missing here, sits under another section, or when an entry
// here no longer belongs to any row. Add the row, then the line here.
//
// Kinds: "group" — a SettingsGroup heading; "row" — a SettingsRow (or a row
// derived from it); "card" — a self-drawn card found by its title text.
// Integration cards and their fields come from AppController's catalogue
// at build() time, so a new provider is searchable with no change here.
.pragma library

// Section catalogue, in nav order. SettingsView builds its nav from this.
var SECTIONS = [
    { id: "profile",       icon: "qrc:/brand/icons/heap-13-profile.svg" },
    { id: "appearance",    icon: "qrc:/brand/icons/heap-14-appearance.svg" },
    { id: "language",      icon: "qrc:/brand/icons/heap-15-language.svg" },
    { id: "notifications", icon: "qrc:/brand/icons/heap-16-notifications.svg" },
    // Gentle, opt-in heads-ups (APP-172).
    { id: "safety",        icon: "qrc:/brand/icons/heap-11-tweaks.svg" },
    { id: "calendar",      icon: "qrc:/brand/icons/heap-17-calendar.svg" },
    { id: "tasks",         icon: "qrc:/brand/icons/heap-01-board.svg" },
    { id: "shortcuts",     icon: "qrc:/brand/icons/heap-10-hotkeys.svg" },
    { id: "cpp",           icon: "qrc:/brand/icons/heap-18-code.svg", unimplemented: true },
    { id: "integrations",  icon: "qrc:/brand/icons/heap-19-integrations.svg" },
    { id: "git",           icon: "qrc:/brand/icons/heap-07-code-review.svg" },
    { id: "data",          icon: "qrc:/brand/icons/heap-20-data.svg" },
    { id: "help",          icon: "qrc:/brand/icons/heap-21-help.svg" },
    { id: "about",         icon: "qrc:/brand/icons/heap-22-about.svg" }
];

// [section, kind, title key], in page order.
var ITEMS = [
    ["profile", "group", "settings.profile.group.you"],
    ["profile", "row", "settings.profile.fullName"],
    ["profile", "row", "settings.profile.handle"],
    ["profile", "row", "settings.profile.role"],
    ["profile", "row", "settings.profile.team"],
    ["profile", "group", "settings.profile.group.avatar"],
    ["profile", "row", "settings.profile.avatarColor"],

    ["appearance", "group", "settings.appearance.group.mode"],
    ["appearance", "row", "settings.appearance.theme"],
    ["appearance", "row", "settings.appearance.scale"],
    ["appearance", "row", "settings.appearance.density"],
    ["appearance", "row", "settings.appearance.contrast"],
    ["appearance", "row", "settings.appearance.cursorColor"],
    ["appearance", "group", "settings.appearance.group.themes"],
    ["appearance", "group", "settings.appearance.group.behaviour"],
    ["appearance", "row", "settings.appearance.reducedMotion"],
    ["appearance", "row", "settings.system.closeToTray"],
    ["appearance", "row", "settings.system.startAtLogin"],
    ["appearance", "row", "settings.system.startMinimized"],
    ["appearance", "group", "settings.sound.group"],
    ["appearance", "row", "settings.sound.enabled"],
    ["appearance", "row", "settings.sound.volume"],
    ["appearance", "row", "settings.sound.meeting"],
    ["appearance", "row", "settings.sound.meetingMinutes"],

    ["language", "row", "settings.language.label"],

    ["notifications", "group", "settings.notif.sub.deadlines"],
    ["notifications", "row", "settings.notif.deadlineReminders"],
    ["notifications", "row", "settings.notif.leadHours"],
    ["notifications", "row", "settings.notif.meetingReminders"],
    ["notifications", "row", "settings.notif.meetingLead"],
    ["notifications", "row", "settings.notif.snoozeShort"],
    ["notifications", "row", "settings.notif.snoozeLong"],
    ["notifications", "row", "settings.notif.standupReminder"],
    ["notifications", "group", "settings.notif.sub.channels"],
    ["notifications", "row", "settings.notif.desktopNotif"],
    ["notifications", "row", "settings.notif.test"],
    ["notifications", "row", "settings.notif.soundOnPing"],
    ["notifications", "row", "settings.notif.blockedDigest"],
    ["notifications", "row", "settings.notif.weeklyRecap"],
    ["notifications", "group", "settings.notif.sub.quiet"],
    ["notifications", "row", "settings.notif.quietHours"],
    ["notifications", "row", "common.from"],
    ["notifications", "row", "common.to"],

    ["safety", "group", "settings.safety.group.endOfDay"],
    ["safety", "row", "settings.safety.endOfDay"],
    ["safety", "row", "settings.safety.endOfDayTime"],
    ["safety", "row", "settings.safety.staleDays"],
    ["safety", "group", "settings.safety.group.waiting"],
    ["safety", "row", "settings.safety.waiting"],
    ["safety", "row", "settings.safety.waitingDays"],
    ["safety", "group", "settings.safety.group.seen"],
    ["safety", "row", "settings.safety.seen"],
    ["safety", "group", "settings.safety.group.immersion"],
    ["safety", "row", "settings.safety.immersion"],
    ["safety", "row", "settings.safety.immersionPassMeetings"],
    ["safety", "group", "settings.safety.group.standup"],
    ["safety", "row", "settings.safety.standup"],

    ["calendar", "group", "settings.cal.group.week"],
    ["calendar", "row", "settings.cal.weekStart"],
    ["calendar", "row", "settings.cal.timeFormat"],
    ["calendar", "row", "settings.cal.showWeekends"],
    ["calendar", "row", "settings.cal.workDays"],
    ["calendar", "group", "settings.cal.workHours"],
    ["calendar", "row", "settings.cal.workStart"],
    ["calendar", "row", "settings.cal.workEnd"],
    ["calendar", "row", "settings.cal.snap"],
    ["calendar", "group", "settings.cal.focus"],
    ["calendar", "row", "settings.cal.autoFocus"],
    ["calendar", "row", "settings.cal.focusDuration"],
    ["calendar", "row", "settings.cal.standupTime"],

    ["tasks", "group", "settings.tasks.group.new"],
    ["tasks", "row", "settings.tasks.idPrefix"],
    ["tasks", "row", "settings.tasks.renameExisting"],
    ["tasks", "row", "settings.tasks.defaultPriority"],
    ["tasks", "row", "settings.tasks.defaultColumn"],
    ["tasks", "group", "settings.tasks.automations"],
    ["tasks", "row", "settings.tasks.archiveDone"],
    ["tasks", "row", "settings.tasks.blockedHi"],
    ["tasks", "row", "settings.tasks.branchOnReview"],

    ["shortcuts", "row", "settings.shortcuts.sub"],
    ["shortcuts", "row", "settings.shortcuts.mouseHints"],
    ["shortcuts", "group", "settings.shortcuts.group.all"],

    ["cpp", "group", "settings.cpp.group.toolchain"],
    ["cpp", "row", "settings.cpp.compiler"],
    ["cpp", "row", "settings.cpp.standard"],
    ["cpp", "row", "settings.cpp.sanitizer"],
    ["cpp", "row", "settings.cpp.buildType"],
    ["cpp", "group", "settings.cpp.group.tools"],
    ["cpp", "row", "settings.cpp.bazelArgs"],
    ["cpp", "row", "settings.cpp.godbolt"],
    ["cpp", "row", "settings.cpp.inlineAsm"],

    ["integrations", "card", "intinfo.title"],
    ["integrations", "group", "health.title"],
    ["integrations", "card", "calsub.title"],
    ["integrations", "card", "settings.integrations.autoSync"],
    // The card row names its tracker ("%1"); search shows it with a generic word.
    ["integrations", "card", "settings.integrations.writeStatus", "settings.integrations.writeStatus.any"],
    ["integrations", "group", "settings.integrations.group.services"],

    ["git", "group", "settings.git.repos"],
    ["git", "group", "settings.git.autoOn"],
    ["git", "row", "settings.git.autoMove"],
    ["git", "row", "settings.git.autoFocus"],
    ["git", "row", "settings.git.prState"],
    ["git", "row", "settings.git.showMove"],

    ["data", "group", "settings.data.backups"],
    ["data", "row", "settings.data.autoBackup"],
    ["data", "row", "settings.data.interval"],
    ["data", "row", "settings.data.timeMachine"],
    ["data", "group", "settings.data.restore"],
    ["data", "group", "settings.data.importExport"],
    ["data", "group", "att.cleanup.title"],
    ["data", "group", "settings.data.danger"],
    ["data", "row", "settings.data.reset"],
    ["data", "row", "settings.data.wipe"],

    ["about", "row", "settings.about.version"],
    ["about", "row", "settings.about.channel"],
    ["about", "row", "settings.about.storage"],
    ["about", "row", "settings.about.engine"],
    ["about", "group", "settings.about.updates"],
    ["about", "row", "settings.about.autoCheck"],
    ["about", "group", "settings.about.diagnostics"]
];

function _en(i18n, key) {
    const v = i18n.dict.en[key];
    return v === undefined ? "" : String(v);
}

// The searchable list. `lang` is only there so a binding that calls this
// re-runs when the language flips; `catalog` is
// AppController.integrationCatalog().
function build(i18n, lang, catalog) {
    const out = [];
    for (let i = 0; i < ITEMS.length; i++) {
        const it = ITEMS[i];
        const key = it[2];
        const hasHint = i18n.dict.en[key + ".hint"] !== undefined;
        // A title with a "%1" gets the word named by the entry's 4th field.
        const argKey = it.length > 3 ? it[3] : "";
        const fill = (s, lang) => argKey === "" ? s : s.replace("%1", lang === "en" ? _en(i18n, argKey) : i18n.t(argKey));
        out.push({
            id: it[0] + ":" + key,
            section: it[0],
            kind: it[1],
            key: key,
            objectName: "",
            title: fill(i18n.t(key), ""),
            titleEn: fill(_en(i18n, key), "en"),
            hint: hasHint ? i18n.t(key + ".hint") : "",
            hintEn: hasHint ? _en(i18n, key + ".hint") : ""
        });
    }
    const providers = catalog || [];
    for (let p = 0; p < providers.length; p++) {
        const prov = providers[p];
        out.push({
            id: "integrations:" + prov.id, section: "integrations", kind: "card", key: "",
            objectName: "int-card-" + prov.id,
            title: String(prov.name), titleEn: "", hint: "", hintEn: ""
        });
        const fields = prov.fields || [];
        for (let f = 0; f < fields.length; f++) {
            out.push({
                id: "integrations:" + prov.id + ":" + fields[f].key, section: "integrations", kind: "card",
                key: "", objectName: "int-card-" + prov.id,
                title: String(prov.name) + ": " + String(fields[f].label), titleEn: "", hint: "", hintEn: ""
            });
        }
    }
    // Nav order, so the provider cards sit with the rest of Integrations.
    const rank = {};
    for (let s = 0; s < SECTIONS.length; s++) rank[SECTIONS[s].id] = s;
    return out.map((it, i) => ({ it: it, i: i }))
              .sort((a, b) => (rank[a.it.section] - rank[b.it.section]) || (a.i - b.i))
              .map((x) => x.it);
}

function norm(q) {
    return String(q || "").toLowerCase().trim();
}

function _has(s, q) {
    return s.length > 0 && s.toLowerCase().indexOf(q) >= 0;
}

// Does `text` (in either language) contain the normalised query `q`?
function textMatches(q, a, b) {
    return _has(String(a || ""), q) || _has(String(b || ""), q);
}

function itemMatches(item, q) {
    if (q.length === 0) return false;
    return textMatches(q, item.title, item.titleEn) || textMatches(q, item.hint, item.hintEn);
}

// The items `query` finds, in page order: title matches before hint-only
// matches, so "sound" lists the sound switches before rows that mention it.
function search(items, query) {
    const q = norm(query);
    if (q.length === 0) return [];
    const byTitle = [];
    const byHint = [];
    for (let i = 0; i < items.length; i++) {
        const it = items[i];
        if (textMatches(q, it.title, it.titleEn)) byTitle.push(it);
        else if (textMatches(q, it.hint, it.hintEn)) byHint.push(it);
    }
    return byTitle.concat(byHint);
}

// section id → number of matched items.
function counts(matches) {
    const out = {};
    for (let i = 0; i < matches.length; i++)
        out[matches[i].section] = (out[matches[i].section] || 0) + 1;
    return out;
}
