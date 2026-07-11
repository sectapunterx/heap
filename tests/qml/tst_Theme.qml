// Unit tests for the Theme singleton (qml/Theme.qml).
// Theme is `pragma Singleton` with no signals and no objectName, so we exercise
// its palette bindings, convenience reads, and pure functions directly, driving
// settings-dependent branches through the writable AppController.appSettingsJson
// (captured and restored inside each method so tests stay independent).
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Theme"
    when: windowShown
    visible: true
    width: 200
    height: 200

    Item { id: host; anchors.fill: parent }

    // ── smoke: the singleton resolves and core tokens have sane types ──
    function test_singleton_resolves() {
        verify(Theme !== null, "Theme singleton must resolve");
        compare(typeof Theme.animMs, "number");
        verify(Theme.rowH > 0, "rowH must be positive");
        verify(Theme.pad > 0, "pad must be positive");
        verify(Theme.radius > 0, "radius must be positive");
        verify(Theme.hourH > 0, "hourH must be positive");
        verify(Theme.fontUi.length > 0, "fontUi must be non-empty");
        verify(Theme.fontMono.length > 0, "fontMono must be non-empty");
        compare(typeof Theme.dark, "boolean");
        compare(typeof Theme.compact, "boolean");
        compare(typeof Theme.reducedMotion, "boolean");
        compare(typeof Theme.highContrast, "boolean");
    }

    // ── withAlpha: keeps r/g/b, replaces alpha ──
    function test_withalpha_preserves_rgb_sets_alpha() {
        const c = Qt.rgba(0.2, 0.4, 0.6, 1.0);
        const half = Theme.withAlpha(c, 0.5);
        fuzzyCompare(half.r, 0.2, 0.01);
        fuzzyCompare(half.g, 0.4, 0.01);
        fuzzyCompare(half.b, 0.6, 0.01);
        fuzzyCompare(half.a, 0.5, 0.01);
        // alpha bounds are passed through untouched
        fuzzyCompare(Theme.withAlpha(c, 0.0).a, 0.0, 0.01);
        fuzzyCompare(Theme.withAlpha(c, 1.0).a, 1.0, 0.01);
        // original color is not mutated by the call
        fuzzyCompare(c.a, 1.0, 0.01);
    }

    // ── scaledMs: identity when motion is on, 0 when reduced ──
    function test_scaledms_matches_motion_state() {
        compare(Theme.scaledMs(0), 0);
        // animMs is defined as reducedMotion ? 0 : 160 — scaledMs(160) must agree.
        compare(Theme.scaledMs(160), Theme.animMs);
        if (Theme.reducedMotion) {
            compare(Theme.scaledMs(200), 0);
            compare(Theme.animMs, 0);
        } else {
            compare(Theme.scaledMs(200), 200);
            compare(Theme.animMs, 160);
        }
    }

    // ── statusColor: each known id maps to its swatch, unknown → textMuted ──
    function test_statuscolor_mapping() {
        compare(String(Theme.statusColor("backlog")), String(Theme.stBacklog));
        compare(String(Theme.statusColor("todo")),    String(Theme.stTodo));
        compare(String(Theme.statusColor("prog")),    String(Theme.stProg));
        compare(String(Theme.statusColor("half")),    String(Theme.stHalf));
        compare(String(Theme.statusColor("blocked")), String(Theme.stBlocked));
        compare(String(Theme.statusColor("review")),  String(Theme.stReview));
        compare(String(Theme.statusColor("done")),    String(Theme.stDone));
        // unknown / empty fall back to textMuted
        compare(String(Theme.statusColor("nope")), String(Theme.textMuted));
        compare(String(Theme.statusColor("")),     String(Theme.textMuted));
    }

    // ── priorityColor: P0..P3 → ramp, unknown → textMuted (callers pass
    //    uppercase "P0".."P3", e.g. FilterBar model + TaskCard task.priority) ──
    function test_prioritycolor_mapping() {
        compare(String(Theme.priorityColor("P0")), String(Theme.p0));
        compare(String(Theme.priorityColor("P1")), String(Theme.p1));
        compare(String(Theme.priorityColor("P2")), String(Theme.p2));
        compare(String(Theme.priorityColor("P3")), String(Theme.p3));
        compare(String(Theme.priorityColor("P4")), String(Theme.textMuted));
        compare(String(Theme.priorityColor("")),   String(Theme.textMuted));
    }

    // ── eventColor: known types → swatch, unknown → accent (default) ──
    function test_eventcolor_mapping() {
        compare(String(Theme.eventColor("standup")), String(Theme.mStandup));
        compare(String(Theme.eventColor("oneone")),  String(Theme.mOneone));
        compare(String(Theme.eventColor("sync")),    String(Theme.mSync));
        compare(String(Theme.eventColor("focus")),   String(Theme.mFocus));
        // default branch returns the live accent, not textMuted
        compare(String(Theme.eventColor("mystery")), String(Theme.accent));
        compare(String(Theme.eventColor("")),        String(Theme.accent));
    }

    // ── fmtHour, 24h format ── (settings forced + restored before asserting)
    function test_fmthour_24h() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = JSON.stringify({ calendar: { timeFormat: "24h" } });
        // read while the setting is active; restore before any assert can throw
        const v0   = Theme.fmtHour(0);
        const v9   = Theme.fmtHour(9);
        const v13  = Theme.fmtHour(13);
        const v23  = Theme.fmtHour(23);
        const half = Theme.fmtHour(9.5);
        const q    = Theme.fmtHour(0.25);
        const fmt  = Theme.timeFormat;
        AppController.appSettingsJson = saved;

        compare(fmt, "24h");
        compare(v0,  "00:00");
        compare(v9,  "09:00");
        compare(v13, "13:00");
        compare(v23, "23:00");
        compare(half, "09:30");
        compare(q,   "00:15");
    }

    // ── fmtHour, 12h format: am/pm + 12-hour clock boundaries ──
    function test_fmthour_12h() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = JSON.stringify({ calendar: { timeFormat: "12h" } });
        const midnight = Theme.fmtHour(0);
        const noon     = Theme.fmtHour(12);
        const onePm    = Theme.fmtHour(13);
        const elevenPm = Theme.fmtHour(23);
        const elevenAm = Theme.fmtHour(11);
        const oneAm    = Theme.fmtHour(1);
        const halfPast = Theme.fmtHour(9.5);
        const fmt      = Theme.timeFormat;
        AppController.appSettingsJson = saved;

        compare(fmt, "12h");
        compare(midnight, "12:00am");  // 0h → 12am
        compare(noon,     "12:00pm");  // 12h → 12pm
        compare(onePm,    "1:00pm");
        compare(elevenPm, "11:00pm");
        compare(elevenAm, "11:00am");
        compare(oneAm,    "1:00am");
        compare(halfPast, "9:30am");
    }

    // ── convenience reads fall back to defaults when settings are empty ──
    function test_calendar_defaults_when_settings_empty() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = "";   // → _settings === {}
        const weekStart    = Theme.weekStart;
        const timeFormat   = Theme.timeFormat;
        const snapMinutes  = Theme.snapMinutes;
        const showWeekends = Theme.showWeekends;
        const reduced      = Theme.reducedMotion;
        const contrast     = Theme.highContrast;
        const animMs       = Theme.animMs;
        AppController.appSettingsJson = saved;

        compare(weekStart, "mon");
        compare(timeFormat, "24h");
        compare(snapMinutes, 15);
        compare(showWeekends, true);
        compare(reduced, false);
        compare(contrast, false);
        compare(animMs, 160);
    }

    // ── explicit overrides win — notably showWeekends:false must survive
    //    (guards the `=== undefined ? true : !!x` logic against a `|| true` trap) ──
    function test_calendar_overrides_apply() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = JSON.stringify({
            calendar: { weekStart: "sun", snapMinutes: 30, showWeekends: false }
        });
        const weekStart    = Theme.weekStart;
        const snapMinutes  = Theme.snapMinutes;
        const showWeekends = Theme.showWeekends;
        AppController.appSettingsJson = saved;

        compare(weekStart, "sun");
        compare(snapMinutes, 30);
        compare(showWeekends, false);
    }

    // ── malformed settings JSON must not throw — Theme swallows the parse
    //    error and reverts every convenience read to its default ──
    function test_malformed_settings_falls_back() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = "{ not valid json";
        const weekStart    = Theme.weekStart;
        const timeFormat   = Theme.timeFormat;
        const snapMinutes  = Theme.snapMinutes;
        const showWeekends = Theme.showWeekends;
        AppController.appSettingsJson = saved;

        compare(weekStart, "mon");
        compare(timeFormat, "24h");
        compare(snapMinutes, 15);
        compare(showWeekends, true);
    }
}
