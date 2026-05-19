pragma Singleton
import QtQuick
import TodoCpp

// Theme adapts the heap. brand palette (`Brand` singleton) for the runtime
// app. Dark mode pulls straight from Brand. Light mode uses Brand's light*
// tokens plus a few derived shades. User settings (Settings → Appearance) and
// the Tweaks panel override `accent`, `reducedMotion`, `highContrast`, and
// font names at runtime.
QtObject {
    readonly property bool dark: AppController.theme === "dark"
    readonly property bool compact: AppController.density === "compact"

    // ── Settings JSON shadow (re-parsed when appSettingsJson changes) ──
    readonly property var _settings: {
        const raw = AppController.appSettingsJson || "";
        if (!raw.length) return ({});
        try { return JSON.parse(raw); } catch (e) { return ({}); }
    }
    readonly property var _appearance: (_settings && _settings.appearance) || ({})

    // ── Surfaces ──────────────────────────────────────────────────────
    readonly property color bg:           dark ? Brand.bg      : Brand.lightBg
    readonly property color bg2:          dark ? Brand.bg2     : Qt.darker(Brand.lightBg, 1.04)
    readonly property color panel:        dark ? Brand.panel   : Brand.lightPanel
    readonly property color panel2:       dark ? Brand.panel2  : Qt.darker(Brand.lightPanel, 1.03)
    readonly property color panel3:       dark ? Qt.lighter(Brand.panel2, 1.18) : Qt.darker(Brand.lightPanel, 1.06)

    // ── Lines + text — highContrast strengthens both ──────────────────
    readonly property color border:       highContrast ? (dark ? Qt.lighter(Brand.border, 1.6) : Qt.darker(Brand.lightBorder, 1.4))
                                                       : (dark ? Brand.border : Brand.lightBorder)
    readonly property color borderStrong: highContrast ? (dark ? Qt.lighter(Brand.border, 2.2) : Qt.darker(Brand.lightBorder, 1.8))
                                                       : (dark ? Qt.lighter(Brand.border, 1.3) : Qt.darker(Brand.lightBorder, 1.2))
    readonly property color text:         highContrast ? (dark ? "#ffffff" : "#000000")
                                                       : (dark ? Brand.text : Brand.lightText)
    readonly property color textMuted:    dark ? Brand.text3 : Brand.lightText3
    readonly property color textDim:      dark ? Brand.text4 : Qt.lighter(Brand.lightText3, 1.4)

    // ── Accent — Brand cyan by default, settings overrides win ───────
    readonly property color _defaultAccent: dark ? Brand.accent : Brand.lightAccent
    readonly property color accent:        _appearance.accent ? _appearance.accent : _defaultAccent
    readonly property color accentStrong:  dark ? Qt.lighter(accent, 1.18) : Qt.darker(accent, 1.18)
    readonly property color accentSoft:    Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.18 : 0.12)

    // ── Priority swatches — kept as warm/cool ramp distinct from brand ──
    readonly property color p0: dark ? "#e6624c" : "#c34a36"
    readonly property color p1: dark ? Brand.statusWarn : "#bd7530"
    readonly property color p2: dark ? "#d8c277" : "#9a8237"
    readonly property color p3: dark ? "#7d9bc7" : "#496a91"

    // ── Status — sourced from Brand semantic tokens ──────────────────
    readonly property color stBacklog: dark ? "#8a8e98" : "#7a808c"
    readonly property color stTodo:    dark ? Brand.statusTodo       : "#5a6371"
    readonly property color stProg:    dark ? Brand.statusInProgress : "#1f6fb0"
    readonly property color stHalf:    dark ? "#dcb86b" : "#9a7a2b"
    readonly property color stBlocked: dark ? "#e6624c" : "#c34a36"
    readonly property color stReview:  dark ? Brand.statusReview     : "#7a3e91"
    readonly property color stDone:    dark ? Brand.statusDone       : "#3e8a5d"

    // ── Event-type swatches ──────────────────────────────────────────
    readonly property color mStandup: dark ? "#5aa3e6" : "#1f6fb0"
    readonly property color mOneone:  dark ? "#c07acf" : "#7a3e91"
    readonly property color mSync:    dark ? "#6cc4b8" : "#317e74"
    readonly property color mFocus:   dark ? "#7cc492" : "#3e8a5d"

    // ── Geometry — pulled from Brand spacing/radius scale ────────────
    readonly property int rowH:   compact ? 32 : 44
    readonly property int pad:    compact ? Brand.spacing2 : Brand.spacing4
    readonly property int gap:    compact ? Brand.spacing2 : Brand.spacing3
    readonly property int radius: Brand.radiusMd
    readonly property int hourH:  compact ? 44 : 56

    // ── Accessibility / motion ───────────────────────────────────────
    readonly property bool reducedMotion: !!_appearance.reducedMotion
    readonly property bool highContrast:  !!_appearance.highContrast
    readonly property int animMs: reducedMotion ? 0 : 160
    function scaledMs(n) { return reducedMotion ? 0 : n; }

    // ── Typography — Brand defaults, overrideable via settings ───────
    readonly property string fontUi: _appearance.fontUI
        ? (_appearance.fontUI + ", " + Brand.fontSans + ", Inter, Segoe UI, Noto Sans, sans-serif")
        : (Brand.fontSans + ", Inter, Segoe UI, Noto Sans, sans-serif")
    readonly property string fontMono: _appearance.fontMono
        ? (_appearance.fontMono + ", " + Brand.fontMono + ", Fira Code, DejaVu Sans Mono, monospace")
        : (Brand.fontMono + ", Fira Code, DejaVu Sans Mono, monospace")

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function statusColor(id) {
        switch (id) {
            case "backlog": return stBacklog;
            case "todo":    return stTodo;
            case "prog":    return stProg;
            case "half":    return stHalf;
            case "blocked": return stBlocked;
            case "review":  return stReview;
            case "done":    return stDone;
        }
        return textMuted;
    }
    function priorityColor(p) {
        switch (p) { case "P0": return p0; case "P1": return p1; case "P2": return p2; case "P3": return p3; }
        return textMuted;
    }
    function eventColor(type) {
        switch (type) {
            case "standup": return mStandup;
            case "oneone":  return mOneone;
            case "sync":    return mSync;
            case "focus":   return mFocus;
        }
        return accent;
    }
}
