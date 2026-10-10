// Unit tests for the Theme singleton (qml/Theme.qml).
// Theme is `pragma Singleton` with no signals and no objectName, so we exercise
// its palette bindings, convenience reads, and pure functions directly, driving
// settings-dependent branches through the writable AppController.appSettingsJson
// (captured and restored inside each method so tests stay independent).
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp
import "../../qml/ThemePresets.js" as Presets

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
        compare(typeof Theme.durMove, "number");
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

    // ── Fonts: the bundled Golos Text / JetBrains Mono lead every chain ──
    // A fresh profile (no appearance, or the seeded one) and a profile that
    // still carries an old seeded default ("IBM Plex Sans", or the upstream
    // "Golos Text" / "JetBrains Mono" of 0.6.0) gets the bundled "heap ..."
    // faces; a font the user picked stays in front.
    function test_fontui_defaults_to_bundled_golos() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = JSON.stringify({});
        const fresh = Theme.fontUi;
        const freshMono = Theme.fontMono;
        AppController.appSettingsJson = JSON.stringify({ appearance: { fontUI: Brand.fontSans, fontMono: Brand.fontMono } });
        const seeded = Theme.fontUi;
        AppController.appSettingsJson = JSON.stringify({ appearance: { fontUI: "Golos Text", fontMono: "JetBrains Mono" } });
        const seeded060 = Theme.fontUi;
        const seeded060Mono = Theme.fontMono;
        AppController.appSettingsJson = JSON.stringify({ appearance: { fontUI: "IBM Plex Sans", fontMono: "JetBrains Mono" } });
        const legacy = Theme.fontUi;
        // A pick the machine has (the bundled mono, always there) stays; one
        // it lacks gives way to the bundled face instead of an arbitrary one.
        AppController.appSettingsJson = JSON.stringify({ appearance: { fontUI: "lowkey JetBrains Mono" } });
        const custom = Theme.fontUi;
        AppController.appSettingsJson = JSON.stringify({ appearance: { fontUI: "No Such Font heap", fontMono: "No Such Mono heap" } });
        const missing = Theme.fontUi;
        const missingMono = Theme.fontMono;
        AppController.appSettingsJson = saved;

        // One family each: Qt reads font.family as a single name, so a
        // "A, B, sans-serif" list matched nothing and drew in the system font.
        compare(fresh, "lowkey Golos Text");
        compare(freshMono, "lowkey JetBrains Mono");
        compare(seeded, "lowkey Golos Text");
        compare(seeded060, "lowkey Golos Text");
        compare(seeded060Mono, "lowkey JetBrains Mono");
        compare(legacy, "lowkey Golos Text");
        compare(custom, "lowkey JetBrains Mono");
        compare(missing, "lowkey Golos Text");
        compare(missingMono, "lowkey JetBrains Mono");
    }

    // quick_test_main registers the bundled fonts as main() does, so a Text
    // set in Theme's fonts really draws in them, at the weights the UI uses;
    // a Text with no family of its own gets Golos Text too (the application
    // font), not the system UI font.
    Text { id: uiProbe; text: "Ж"; font.family: Theme.fontUi; font.weight: Font.DemiBold }
    Text { id: monoProbe; text: "0"; font.family: Theme.fontMono; font.weight: Font.Medium }
    Text { id: plainProbe; text: "a" }
    function test_bundled_fonts_resolve() {
        compare(uiProbe.fontInfo.family, "lowkey Golos Text");
        compare(uiProbe.fontInfo.weight, Font.DemiBold);
        compare(monoProbe.fontInfo.family, "lowkey JetBrains Mono");
        compare(monoProbe.fontInfo.weight, Font.Medium);
        compare(plainProbe.fontInfo.family, "lowkey Golos Text");
    }

    // ── Weights (APP-193): three, one job each, and only the heading at 600 ──
    function test_three_weights() {
        compare(Theme.fwBody, Font.Normal);
        compare(Theme.fwTitle, Font.Medium);
        compare(Theme.fwHeading, Font.DemiBold);
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

    // ── Motion tokens (APP-175): tap < pop < move, leaving takes half,
    //    one curve in and one out, no overshoot ──
    function test_motion_tokens_with_motion_on() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = JSON.stringify({ appearance: { reducedMotion: false } });
        const d = [Theme.durTap, Theme.durPop, Theme.durMove,
                   Theme.durTapOut, Theme.durPopOut, Theme.durMoveOut, Theme.durPulse];
        AppController.appSettingsJson = saved;
        compare(d[0], 90);
        compare(d[1], 140);
        compare(d[2], 220);
        compare(d[3], 45);
        compare(d[4], 70);
        compare(d[5], 110);
        verify(d[6] > 0);
        compare(Theme.easeEnter, Easing.OutQuint);
        compare(Theme.easeExit, Easing.InCubic);
    }

    // ── "Reduce motion" = 0 ms for every duration token ──
    function test_reduced_motion_zeroes_every_duration() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = JSON.stringify({ appearance: { reducedMotion: true } });
        const reduced = Theme.reducedMotion;
        const motion = Theme.motion;
        const d = { durTap: Theme.durTap, durPop: Theme.durPop, durMove: Theme.durMove,
                    durTapOut: Theme.durTapOut, durPopOut: Theme.durPopOut,
                    durMoveOut: Theme.durMoveOut, durPulse: Theme.durPulse };
        AppController.appSettingsJson = saved;
        compare(reduced, true);
        compare(motion, 0);
        for (const k in d)
            compare(d[k], 0, k + " must be 0 with reduced motion");
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
        const durMove      = Theme.durMove;
        AppController.appSettingsJson = saved;

        compare(weekStart, "mon");
        compare(timeFormat, "24h");
        compare(snapMinutes, 15);
        compare(showWeekends, true);
        compare(reduced, false);
        compare(contrast, false);
        compare(durMove, 220);
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

    // ── minEventHours tracks the snap grid ──
    // The calendar's drag / resize floor used to be a hardcoded 0.25, which
    // fought a 30-minute snap: the drag allowed a length the save then rounded
    // away. It now follows snapMinutes, and never reaches zero.
    function test_min_event_hours_follows_snap() {
        const saved = AppController.appSettingsJson;

        AppController.appSettingsJson = JSON.stringify({ calendar: { snapMinutes: 30 } });
        const half = Theme.minEventHours;
        AppController.appSettingsJson = JSON.stringify({ calendar: { snapMinutes: 5 } });
        const five = Theme.minEventHours;
        AppController.appSettingsJson = saved;
        const fallback = Theme.minEventHours;

        compare(half, 0.5);
        fuzzyCompare(five, 5 / 60, 1e-9);
        compare(fallback, 0.25);
        verify(Theme.minEventHours > 0, "a zero floor would make events un-draggable");
    }

    // WCAG relative luminance of a QML colour.
    function _lum(c) {
        const f = (v) => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }
    function _contrast(a, b) {
        const la = _lum(a), lb = _lum(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    // The small dim text must be readable (audit B10): WCAG AA asks 4.5:1 —
    // in every built-in theme.
    function test_text_dim_meets_wcag_aa_on_every_surface() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        const fails = [];
        for (const t of Presets.PRESETS) {
            AppController.theme = t.base;
            AppController.appSettingsJson = JSON.stringify({ appearance: { darkPreset: t.id, lightPreset: t.id } });
            for (const surface of [Theme.bg, Theme.panel, Theme.panel2, Theme.surfaceCard, Theme.surfaceCardHover]) {
                const ratio = _contrast(Theme.textDim, surface);
                if (ratio < 4.5) fails.push(t.id + ": textDim on " + surface + " is " + ratio.toFixed(2) + ":1");
            }
        }
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;
        compare(fails.length, 0, fails.join("; "));
    }

    // A card stands on the ground by lightness, one step per level (APP-196):
    // on every dark theme 8–10 L* above bg and no border; a light theme keeps
    // its white card and the hairline. Columns have no fill at all.
    function test_cards_stand_on_the_ground_by_lightness() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        const fails = [];
        for (const t of Presets.PRESETS) {
            AppController.theme = t.base;
            AppController.appSettingsJson = JSON.stringify({ appearance: { darkPreset: t.id, lightPreset: t.id, contrast: "normal" } });
            compare(Theme.surfaceColumn.a, 0, t.id + ": a column has no fill");
            if (t.base !== "dark") {
                verify(Theme.cardBorder.a > 0, t.id + ": a light card keeps its hairline");
                continue;
            }
            const dL = Presets.lightness(String(Theme.surfaceCard)) - Presets.lightness(String(Theme.bg));
            // A heap 2 theme names its own card, a few L* above the ground
            // (the mockup's #13161b on #0c0e11); the others derive 8–10.
            const own = t.colors.card !== undefined;
            if (own ? (dL < 2 || dL > 6) : (dL < 8 || dL > 10))
                fails.push(t.id + ": card is " + dL.toFixed(1) + " L* above bg");
            if (Theme.cardBorder.a !== 0) fails.push(t.id + ": dark card has a border");
        }
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;
        compare(fails.length, 0, fails.join("; "));
    }

    // heap.'s own themes keep three text levels apart: textMuted used to sit
    // within a few points of textDim, so secondary and tertiary text looked
    // the same.
    function test_heap_themes_have_three_text_levels() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        const fails = [];
        for (const id of ["heap-dark", "heap-light"]) {
            const t = Presets.builtin(id);
            AppController.theme = t.base;
            AppController.appSettingsJson = JSON.stringify({ appearance: { darkPreset: id, lightPreset: id } });
            const text = _contrast(Theme.text, Theme.bg);
            const muted = _contrast(Theme.textMuted, Theme.bg);
            const dim = _contrast(Theme.textDim, Theme.bg);
            if (!(text - muted >= 1.5 && muted - dim >= 1.5))
                fails.push(id + ": text " + text.toFixed(2) + ", muted " + muted.toFixed(2) + ", dim " + dim.toFixed(2));
        }
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;
        compare(fails.length, 0, fails.join("; "));
    }

    // ── Scales ──────────────────────────────────────────────────────────

    // The type scale ascends and nothing the user reads is under 11px.
    function test_type_scale_ascends_from_eleven() {
        const s = [Theme.fsXs, Theme.fsSm, Theme.fsMd, Theme.fsLg, Theme.fsXl, Theme.fs2xl];
        verify(s[0] >= 11, "fsXs is " + s[0] + "px");
        for (let i = 1; i < s.length; i++) verify(s[i] > s[i - 1], "type scale step " + i + " does not ascend");
    }

    // Every size sits on the 1.125 scale from 13px (APP-181), not on the
    // old 11/12/13/15/20/28 list.
    function test_type_scale_is_modular() {
        compare(Theme.scale, 1);
        const steps = { fsSm: -1, fsMd: 0, fsLg: 1, fsXl: 3, fs2xl: 5 };
        for (const k in steps)
            compare(Theme[k], Math.round(13 * Math.pow(1.125, steps[k])), k);
        compare(Theme.fsXs, 11, "the floor");
        compare([Theme.fsXl, Theme.fs2xl], [19, 23]);
    }

    // Density moves the spacing scale, not just the hour height: compact
    // makes every step at least as tight and the common ones tighter.
    function test_compact_density_tightens_spacing() {
        const keys = ["sp2xs", "spXs", "spSm", "spMd", "spLg", "spXl", "sp2xl", "inset", "sp3xl"];
        const saved = AppController.density;
        AppController.density = "comfy";
        const roomy = keys.map(k => Theme[k]);
        AppController.density = "compact";
        const tight = keys.map(k => Theme[k]);
        AppController.density = saved;
        for (let i = 0; i < keys.length; i++) {
            verify(tight[i] <= roomy[i], keys[i] + " grows in compact");
            if (i > 0) verify(roomy[i] > roomy[i - 1], keys[i] + " does not ascend");
        }
        verify(tight[3] < roomy[3] && tight[5] < roomy[5], "compact left spMd / spXl as they were");
    }

    // ── Themes ──────────────────────────────────────────────────────────

    // Every built-in fills every token with a colour — a missing one would
    // fall back silently, a typo would paint nothing.
    function test_every_preset_defines_every_token() {
        const ids = {};
        for (const t of Presets.PRESETS) {
            verify(!ids[t.id], "duplicate preset id " + t.id);
            ids[t.id] = true;
            verify(t.base === "dark" || t.base === "light", t.id + " base");
            for (const tok of Presets.TOKENS)
                verify(Presets.isHex(t.colors[tok.key]), t.id + "." + tok.key + " = " + t.colors[tok.key]);
            for (const k in t.colors)
                verify(Presets.isToken(k) || Presets.EXTRA_KEYS.indexOf(k) >= 0, t.id + " has unknown token " + k);
        }
        for (const tok of Presets.TOKENS)
            verify(Presets.GROUPS.indexOf(tok.group) >= 0, tok.key + " in unknown group " + tok.group);
    }

    // Theme has a property for every token the editor offers, and it carries
    // the theme's value. Checking only that it exists let `onAccent` through:
    // QML reads an `on` + capital name as a signal handler, and the property
    // sat at black.
    function test_theme_exposes_every_token() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        const fails = [];
        for (const mode of ["dark", "light"]) {
            AppController.theme = mode;
            AppController.appSettingsJson = "";
            for (const tok of Presets.TOKENS) {
                verify(!/^on[A-Z]/.test(tok.key), tok.key + " reads as a signal handler in QML");
                if (!Qt.colorEqual(Theme[tok.key], Theme.active.colors[tok.key]))
                    fails.push(mode + " Theme." + tok.key + " = " + Theme[tok.key] + ", token " + Theme.active.colors[tok.key]);
            }
        }
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;
        compare(fails.length, 0, fails.join("; "));
    }

    // "The current theme" is preserved: the built-in heap. themes give the
    // colours the app shipped with before themes were editable.
    function test_heap_presets_match_the_shipped_palette() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        // Classic dark by name: the default dark is lowkey since 0.8.0.
        AppController.appSettingsJson = JSON.stringify({ appearance: { darkPreset: "heap-dark" } });
        AppController.theme = "dark";
        const d = { bg: String(Theme.bg), panel3: String(Theme.panel3), borderStrong: String(Theme.borderStrong),
                    accent: String(Theme.accent), accentStrong: String(Theme.accentStrong),
                    p0: String(Theme.p0), stDone: String(Theme.stDone), textDim: String(Theme.textDim) };
        AppController.theme = "light";
        const l = { bg: String(Theme.bg), bg2: String(Theme.bg2), panel2: String(Theme.panel2),
                    accent: String(Theme.accent), accentStrong: String(Theme.accentStrong), p0: String(Theme.p0) };
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;

        compare(d.bg, "#0b0e13");
        compare(d.panel3, String(Qt.lighter(Brand.panel2, 1.18)));
        compare(d.borderStrong, String(Qt.lighter(Brand.border, 1.3)));
        compare(d.accent, String(Brand.accent));
        compare(d.accentStrong, String(Qt.lighter(Brand.accent, 1.18)));
        compare(d.p0, "#e6624c");
        compare(d.stDone, String(Brand.statusDone));
        // Shipped as #808a9a; lifted just enough to read at AA on panel3.
        compare(d.textDim, "#86909f");
        // lowkey light: the heap 2 light palette (APP-259, sheet X-Oth-Light).
        compare(l.bg, "#f7f8fa");
        compare(l.bg2, "#eff1f4");
        compare(l.panel2, "#f2f4f7");
        compare(l.accent, String(Brand.lightAccent));
        compare(l.accentStrong, "#4a40a0");
        compare(l.p0, "#b23a33");  // AA on panel3 too
    }

    // Each slot shows its own theme; flipping AppController.theme flips slot.
    function test_slots_pick_their_own_theme() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        AppController.appSettingsJson = JSON.stringify({ appearance: {
            darkPreset: "heap-light", lightPreset: "heap-dark" } });
        AppController.theme = "dark";
        const inDark = Theme.activePresetId, darkBg = String(Theme.bg), darkFlag = Theme.dark;
        AppController.theme = "light";
        const inLight = Theme.activePresetId, lightBg = String(Theme.bg), lightFlag = Theme.dark;
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;

        compare(inDark, "heap-light");
        compare(darkBg, "#f7f8fa");
        // `dark` follows the colours, not the slot
        compare(darkFlag, false);
        compare(inLight, "heap-dark");
        compare(lightBg, "#0b0e13");
        compare(lightFlag, true);
    }

    function test_unknown_theme_falls_back_to_the_slot_default() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        AppController.theme = "light";
        AppController.appSettingsJson = JSON.stringify({ appearance: { lightPreset: "gone-theme" } });
        const bg = String(Theme.bg);
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;
        compare(bg, "#f7f8fa");
    }

    // A custom theme paints its own colours; a token it lacks or spells
    // wrong comes from the built-in of its base.
    function test_custom_theme_applies_with_fallbacks() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        AppController.theme = "dark";
        AppController.appSettingsJson = JSON.stringify({ appearance: {
            darkPreset: "custom-1",
            customThemes: [{ id: "custom-1", name: "Mine", base: "dark",
                             colors: { bg: "#101010", danger: "#ff0000", warning: "orange", accentSoft: "#40112233" } }]
        } });
        const bg = String(Theme.bg), danger = String(Theme.danger), warning = String(Theme.warning);
        // .a read now: a colour read off a property is a live reference and
        // would see the restored theme below.
        const softA = Theme.accentSoft.a, panel = String(Theme.panel), err = String(Theme.alertColor("error"));
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;

        compare(bg, "#101010");
        compare(danger, "#ff0000");
        compare(err, "#ff0000");
        compare(warning, "#fe9c3a");      // "orange" is not a hex token value
        compare(panel, "#14181f");        // absent → heap. dark
        fuzzyCompare(softA, 0x40 / 255, 0.01);
    }

    // A profile from before themes were editable keeps its accent until a
    // theme is picked for either slot.
    function test_legacy_accent_until_a_theme_is_picked() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        AppController.theme = "dark";
        AppController.appSettingsJson = JSON.stringify({ appearance: { accent: "#6ec18a" } });
        const legacy = String(Theme.accent);
        AppController.appSettingsJson = JSON.stringify({ appearance: { accent: "#6ec18a", darkPreset: "heap-dark" } });
        const picked = String(Theme.accent);
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;

        compare(legacy, "#6ec18a");
        compare(picked, "#3bccdd");
    }

    function test_validate_theme() {
        compare(Presets.validateTheme(null), null);
        compare(Presets.validateTheme("x"), null);
        compare(Presets.validateTheme({ colors: { bg: "red", nope: "#123456" } }), null);
        const v = Presets.validateTheme({ name: "  X  ", base: "light",
                                          colors: { bg: "#ABCDEF", nope: "#123456", text: "#11223344" } });
        compare(v.name, "X");
        compare(v.base, "light");
        compare(v.colors.bg, "#abcdef");
        compare(v.colors.text, "#11223344");
        compare(v.colors.nope, undefined);
        // a bare token map works too, and an unknown base means dark
        const bare = Presets.validateTheme({ accent: "#00ff00", base: "sepia" });
        compare(bare.colors.accent, "#00ff00");
        compare(bare.base, "dark");
    }

    // Export → import gives back the same palette.
    function test_export_round_trips() {
        const json = Presets.exportJson("heap-light", [], "light");
        const v = Presets.validateTheme(JSON.parse(json));
        const want = Presets.resolve("heap-light", [], "light").colors;
        compare(v.base, "light");
        for (const tok of Presets.TOKENS)
            compare(v.colors[tok.key], want[tok.key].toLowerCase(), tok.key);
    }

    // ── Contrast ────────────────────────────────────────────────────────

    // A profile that only has the old switch still means "high"; the
    // three-way setting wins once it is written.
    function test_contrast_reads_the_legacy_switch() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = JSON.stringify({ appearance: { highContrast: true } });
        const legacy = Theme.contrast, legacyHigh = Theme.highContrast;
        AppController.appSettingsJson = JSON.stringify({ appearance: { highContrast: true, contrast: "soft" } });
        const soft = Theme.contrast, softHigh = Theme.highContrast, softFlag = Theme.softContrast;
        AppController.appSettingsJson = JSON.stringify({ appearance: { contrast: "bogus" } });
        const bogus = Theme.contrast;
        AppController.appSettingsJson = saved;

        compare(legacy, "high");
        compare(legacyHigh, true);
        compare(soft, "soft");
        compare(softHigh, false);
        compare(softFlag, true);
        compare(bogus, "normal");
    }

    // Soft fades lines and colour but never text.
    function test_soft_contrast_quiets_chrome_not_text() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        AppController.theme = "dark";
        AppController.appSettingsJson = JSON.stringify({ appearance: { darkPreset: "heap-dark" } });
        const n = { border: Theme.border, danger: Theme.danger, text: String(Theme.text),
                    textDim: String(Theme.textDim), radius: Theme.radius, bg: String(Theme.bg) };
        const nBorderContrast = _contrast(Qt.tint(Theme.bg, Theme.border), Theme.bg);
        const nDangerSat = Theme.danger.hslSaturation;
        AppController.appSettingsJson = JSON.stringify({ appearance: { darkPreset: "heap-dark", contrast: "soft" } });
        const sBorderContrast = _contrast(Qt.tint(Theme.bg, Theme.border), Theme.bg);
        const sDangerSat = Theme.danger.hslSaturation;
        const s = { text: String(Theme.text), textDim: String(Theme.textDim), radius: Theme.radius, bg: String(Theme.bg) };
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;

        verify(sBorderContrast < nBorderContrast, "border must fade: " + sBorderContrast + " vs " + nBorderContrast);
        verify(sDangerSat < nDangerSat * 0.8, "danger must lose saturation: " + sDangerSat + " vs " + nDangerSat);
        compare(s.text, n.text);
        compare(s.textDim, n.textDim);
        compare(s.bg, n.bg);
        compare(s.radius, n.radius + 2);
    }

    // soften() keeps every token a valid colour, in every built-in.
    function test_soften_keeps_every_token_valid() {
        for (const t of Presets.PRESETS) {
            const c = Presets.soften(t.colors);
            for (const tok of Presets.TOKENS)
                verify(Presets.isHex(c[tok.key]), t.id + "." + tok.key + " = " + c[tok.key]);
        }
        // a translucent border fades by alpha, not by turning opaque
        // (Minimal dark's hairlines; lowkey's are opaque since heap 2)
        const b = Presets.soften(Presets.builtin("minimal-dark").colors).border;
        verify(parseInt(b.slice(1, 3), 16) < 0x0c, "translucent border got " + b);
    }

    // High contrast must still strengthen a theme whose borders are
    // translucent hairlines (heap. ink): lightening a 6% white changes nothing.
    function test_high_contrast_strengthens_translucent_borders() {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        AppController.theme = "dark";
        AppController.appSettingsJson = JSON.stringify({ appearance: { darkPreset: "heap-ink" } });
        const normal = _contrast(Qt.tint(Theme.bg, Theme.border), Theme.bg);
        AppController.appSettingsJson = JSON.stringify({ appearance: { darkPreset: "heap-ink", contrast: "high" } });
        const high = _contrast(Qt.tint(Theme.bg, Theme.border), Theme.bg);
        const alpha = Theme.border.a;
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;

        compare(alpha, 1);
        verify(high > normal * 1.2, "high " + high + " vs normal " + normal);
    }

    // A built-in that was retired resolves to its replacement, so a user who
    // had picked it keeps a theme of the same kind instead of the slot default.
    function test_retired_presets_resolve_to_their_replacement() {
        const cases = { "minimal-light": "heap-light", "ash": "graphite",
                        "stone": "ochre", "slate": "graphite", "sage": "fjord", "muted-mauve": "dusk",
                        "moss-mono": "fjord", "nocturne": "dusk" };
        for (const old in cases) {
            verify(!Presets.builtin(old), old + " is still a built-in");
            compare(Presets.resolve(old, [], "dark").id, cases[old], old);
        }
        compare(Presets.resolve("no-such-theme", [], "dark").id, Presets.DEFAULT_DARK);
    }

    // ── APP-127: an update never takes a theme away ─────────────────────

    // A retired built-in in a slot comes back as the user's own theme, with
    // the palette it shipped with, under the same id, so the slot still
    // shows it and not its replacement.
    function test_a_retired_theme_in_a_slot_is_kept() {
        const next = Presets.adoptRetired({ darkPreset: "ash", lightPreset: "minimal-light", contrast: "soft" });
        verify(next !== null);
        compare(next.darkPreset, "ash");
        compare(next.contrast, "soft");
        const ash = next.customThemes.find((t) => t.id === "ash");
        verify(ash !== undefined, "Ash was not kept");
        compare(ash.name, "Ash");
        compare(ash.colors.bg, Presets.RETIRED_PALETTES["ash"].colors.bg);
        const light = next.customThemes.find((t) => t.id === "minimal-light");
        compare(light.base, "light");
        compare(Presets.resolve("ash", next.customThemes, "dark").colors.bg, ash.colors.bg);
        compare(Presets.resolve("minimal-light", next.customThemes, "light").name, "Minimal light");
    }

    // A theme the user made from a retired one keeps its source too.
    function test_the_source_of_a_custom_theme_is_kept() {
        const mine = { id: "custom-1", name: "Mine", base: "dark", from: "slate", colors: { bg: "#000000" } };
        const next = Presets.adoptRetired({ darkPreset: "custom-1", customThemes: [mine] });
        verify(next !== null);
        compare(next.customThemes.length, 2);
        compare(next.customThemes[0].id, "custom-1");
        compare(next.customThemes[1].id, "slate");
    }

    // Runs once: what it kept is a custom theme now, and nothing else is
    // retired, so a second launch changes nothing.
    function test_keeping_runs_once() {
        const first = Presets.adoptRetired({ darkPreset: "nocturne" });
        compare(Presets.adoptRetired(first), null);
        compare(Presets.adoptRetired({ darkPreset: "heap-ink" }), null);
        compare(Presets.adoptRetired({}), null);
        compare(Presets.adoptRetired(null), null);
    }

    // The kept theme's name is free: a user theme already called "Sage"
    // makes it "Sage (2)".
    function test_a_kept_theme_never_shares_a_name() {
        const mine = { id: "custom-1", name: "Sage", base: "dark", colors: {} };
        const next = Presets.adoptRetired({ darkPreset: "sage", customThemes: [mine] });
        compare(next.customThemes[1].name, "Sage (2)");
    }

    function test_unique_name() {
        const customs = [{ id: "custom-1", name: "Mine", colors: {} },
                         { id: "custom-2", name: "Mine (2)", colors: {} }];
        compare(Presets.uniqueName("Other", customs), "Other");
        compare(Presets.uniqueName("Mine", customs), "Mine (3)");
        compare(Presets.uniqueName("mine", customs), "mine (3)", "names compare without case");
        compare(Presets.uniqueName("Crimson", []), "Crimson (2)", "built-in names are taken too");
    }

    // Minimal dark came back (APP-124) as a low-contrast theme, under its old
    // id, so a profile that still names it gets it again rather than Crimson.
    function test_minimal_dark_is_back_in_the_low_set() {
        const t = Presets.builtin("minimal-dark");
        verify(t !== null, "minimal-dark is not a built-in");
        compare(t.contrast, "low");
        compare(Presets.resolve("minimal-dark", [], "dark").id, "minimal-dark");
        compare(Presets.category(t, []), "low");
        // It is a built-in again, so APP-127 does not copy the old palette.
        compare(Presets.adoptRetired({ darkPreset: "minimal-dark" }), null);
    }

    function test_new_id_is_unused() {
        compare(Presets.newId([]), "custom-1");
        compare(Presets.newId([{ id: "custom-1" }, { id: "custom-2" }]), "custom-3");
        compare(Presets.newId([{ id: "custom-2" }]), "custom-1");
    }

    // ── Contrast (audit UX-8 / UX-15) ───────────────────────────────────

    // Runs `fn` once per built-in theme in each contrast mode, with that
    // theme active, and collects what it reports.
    function _eachThemeAndContrast(fn) {
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        const fails = [];
        for (const t of Presets.PRESETS) {
            for (const contrast of ["soft", "normal", "high"]) {
                AppController.theme = t.base;
                AppController.appSettingsJson = JSON.stringify({ appearance: {
                    darkPreset: t.id, lightPreset: t.id, contrast: contrast } });
                fn(t.id + "/" + contrast, fails);
            }
        }
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;
        return fails;
    }

    // Everything drawn as text — priorities, alerts, headings, links, code
    // comments — reads at WCAG AA (4.5:1) on bg, panel, panel2 and panel3 (the
    // highlighted row), in every
    // built-in theme and contrast mode. heap. light had P1 at 3.3:1, headings
    // at 2.5:1, links at 3.5:1; the dark kaneo themes had P3 and comments
    // near 3.5:1.
    function test_text_roles_meet_aa_everywhere() {
        const fails = _eachThemeAndContrast(function (tag, out) {
            const surfaces = [Theme.bg, Qt.tint(Theme.bg, Theme.panel), Qt.tint(Theme.bg, Theme.panel2),
                              Qt.tint(Theme.bg, Theme.panel3)];
            for (const key of Presets.TEXT_ROLES) {
                for (const s of surfaces) {
                    const r = Presets.contrast(String(Theme[key]), String(s));
                    if (r < 4.5) out.push(tag + " " + key + " on " + s + " = " + r.toFixed(2));
                }
            }
            for (const key of Presets.CODE_ROLES) {
                const r = Presets.contrast(String(Theme[key]), String(Qt.tint(Theme.bg, Theme.codeBg)));
                if (r < 4.5) out.push(tag + " " + key + " on codeBg = " + r.toFixed(2));
            }
        });
        compare(fails.length, 0, fails.join("; "));
    }

    // The keyboard focus ring and the highlighted-row marker stand out at
    // 3:1 from every surface they are drawn on.
    function test_focus_ring_is_visible_everywhere() {
        const fails = _eachThemeAndContrast(function (tag, out) {
            for (const s of [Theme.bg, Theme.panel, Theme.panel2, Theme.panel3]) {
                const r = Presets.contrast(String(Theme.focusRing), String(Qt.tint(Theme.bg, s)));
                if (r < 3) out.push(tag + " focusRing on " + s + " = " + r.toFixed(2));
            }
        });
        compare(fails.length, 0, fails.join("; "));
    }

    // Count badges: the label on a danger or accent fill reads at 4.5:1.
    function test_badge_text_reads_on_its_fill() {
        const fails = _eachThemeAndContrast(function (tag, out) {
            for (const fill of [Theme.danger, Theme.accent]) {
                const r = Presets.contrast(String(Theme.textOn(fill)), String(Qt.tint(Theme.bg, fill)));
                if (r < 4.5) out.push(tag + " badge on " + fill + " = " + r.toFixed(2));
            }
        });
        compare(fails.length, 0, fails.join("; "));
    }

    // A field's outline is its only edge (panel2 on panel is ~1.05:1), so
    // it reaches 3:1 for UI in every mode, not only in high contrast.
    function test_field_border_reaches_three_to_one() {
        const fails = _eachThemeAndContrast(function (tag, out) {
            for (const s of [Theme.bg, Theme.panel, Theme.panel2]) {
                const r = Presets.contrast(String(Theme.fieldBorder), String(Qt.tint(Theme.bg, s)));
                if (r < 3) out.push(tag + " fieldBorder on " + s + " = " + r.toFixed(2));
            }
        });
        compare(fails.length, 0, fails.join("; "));
    }

    // Labels on filled buttons read at AA at rest and on hover: heap. light
    // had textOnDanger at 3.9:1 and textOnAccent on its hover fill at 3.7:1.
    function test_filled_button_labels_read_on_their_fill() {
        const fails = _eachThemeAndContrast(function (tag, out) {
            const pairs = [["textOnAccent", Theme.textOnAccent, Theme.accent],
                           ["textOnAccent/hover", Theme.textOnAccent, Theme.accentHover],
                           ["textOnDanger", Theme.textOnDanger, Theme.danger]];
            for (const p of pairs) {
                const r = Presets.contrast(String(p[1]), String(Qt.tint(Theme.bg, p[2])));
                if (r < 4.5) out.push(tag + " " + p[0] + " = " + r.toFixed(2));
            }
        });
        compare(fails.length, 0, fails.join("; "));
    }

    // readable() lifts a data colour (a status) to AA on the panels and
    // leaves one that already passes alone.
    function test_readable_repairs_only_what_fails() {
        const fails = _eachThemeAndContrast(function (tag, out) {
            for (const c of ["#8a8e98", "#9aa3b4", "#6ec18a", "#5aa9e6"]) {
                const r = Presets.contrast(String(Theme.readable(c)), String(Qt.tint(Theme.bg, Theme.panel)));
                if (r < 4.5) out.push(tag + " readable(" + c + ") = " + r.toFixed(2));
            }
        });
        compare(fails.length, 0, fails.join("; "));
        compare(String(Theme.readable(String(Theme.text))), String(Theme.text));
    }

    // High contrast: lines, field outlines included, reach 3:1 for UI.
    function test_high_contrast_lines_reach_three_to_one() {
        const fails = _eachThemeAndContrast(function (tag, out) {
            if (tag.indexOf("/high") < 0) return;
            for (const line of ["border", "borderStrong"]) {
                for (const s of [Theme.bg, Theme.panel]) {
                    const r = Presets.contrast(String(Theme[line]), String(Qt.tint(Theme.bg, s)));
                    if (r < 3) out.push(tag + " " + line + " on " + s + " = " + r.toFixed(2));
                }
            }
        });
        compare(fails.length, 0, fails.join("; "));
    }

    // Soft contrast keeps a hue whose HSL angle comes out negative: magenta
    // softened to red (#d2002d) because JS `%` keeps the sign.
    function test_soften_keeps_magenta_magenta() {
        const c = Qt.color(Presets.desaturate("#ff00ff", 0.65));
        fuzzyCompare(c.hslHue * 360, 300, 2);
        fuzzyCompare(c.r, c.b, 0.02);
        verify(c.g < c.r, "green must stay the low channel: " + c);
        const pink = Qt.color(Presets.desaturate("#ff0080", 0.65));
        verify(pink.b > pink.g, "pink must keep its blue: " + pink);
    }

    // ensureContrast only repairs: a passing colour comes back unchanged.
    function test_ensure_contrast_only_repairs() {
        compare(Presets.ensureContrast("#ffffff", ["#000000"], 4.5), "#ffffff");
        const fixed = Presets.ensureContrast("#333333", ["#000000"], 4.5);
        verify(Presets.contrast(fixed, "#000000") >= 4.5, fixed);
        const onLight = Presets.ensureContrast("#dddddd", ["#ffffff"], 3);
        verify(Presets.contrast(onLight, "#ffffff") >= 3, onLight);
    }

    // APP-168: Appearance → Scale moves type and spacing live; the 11px
    // floor holds at 90 %, and a value out of range is ignored.
    function test_ui_scale_moves_type_and_spacing() {
        const saved = AppController.appSettingsJson;
        function withScale(s) {
            const o = JSON.parse(saved || "{}");
            o.appearance = Object.assign({}, o.appearance || {}, { uiScale: s });
            AppController.appSettingsJson = JSON.stringify(o);
        }
        try {
            withScale(1);
            const md = Theme.fsMd, xl = Theme.sp2xl, row = Theme.rowH;
            withScale(1.25);
            compare(Theme.scale, 1.25);
            compare(Theme.fsMd, Math.round(md * 1.25));
            compare(Theme.sp2xl, Math.round(xl * 1.25));
            compare(Theme.rowH, Math.round(row * 1.25));
            withScale(1.5);
            compare(Theme.fsMd, Math.round(md * 1.5));
            withScale(0.9);
            verify(Theme.fsXs >= 11, "the floor holds");
            verify(Theme.fsMd < md);
            withScale(7);
            compare(Theme.scale, 1, "out of range means 100 %");
        } finally {
            AppController.appSettingsJson = saved;
        }
    }

    // APP-183: with no scale of the user's own, the system's text size is
    // the scale (100 % under tests); a picked one wins.
    function test_unset_ui_scale_follows_the_system_text_size() {
        const saved = AppController.appSettingsJson;
        try {
            const o = JSON.parse(saved || "{}");
            o.appearance = Object.assign({}, o.appearance || {});
            delete o.appearance.uiScale;
            AppController.appSettingsJson = JSON.stringify(o);
            compare(Theme.systemScale(), AppController.systemUiScale(Theme.scaleSteps));
            compare(Theme.scale, Theme.systemScale());
            compare(Theme.systemScale(), 1, "tests read a 100 % system");
            o.appearance.uiScale = 1.25;
            AppController.appSettingsJson = JSON.stringify(o);
            compare(Theme.scale, 1.25);
        } finally {
            AppController.appSettingsJson = saved;
        }
    }
}
