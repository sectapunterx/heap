pragma Singleton
import QtQuick
import TodoCpp
import "ThemePresets.js" as Presets

// Theme is the runtime palette, geometry and settings reads. Colours come
// from the theme in the active slot (ThemePresets.js + the user's own themes
// in settings.appearance.customThemes); Settings → Appearance edits them.
// Geometry and fonts still come from the `Brand` singleton.
QtObject {
    readonly property bool compact: AppController.density === "compact"

    // ── Settings JSON shadow (re-parsed when appSettingsJson changes) ──
    readonly property var _settings: {
        const raw = AppController.appSettingsJson || "";
        if (!raw.length) return ({});
        try { return JSON.parse(raw); } catch (e) { return ({}); }
    }
    readonly property var _appearance: (_settings && _settings.appearance) || ({})
    readonly property var _calendar:   (_settings && _settings.calendar)   || ({})
    readonly property var _tasks:      (_settings && _settings.tasks)      || ({})
    readonly property var _notifications: (_settings && _settings.notifications) || ({})

    // Convenience reads — all view'ы / делегаты могут идти через Theme.
    readonly property string weekStart:    _calendar.weekStart    || "mon"
    readonly property string timeFormat:   _calendar.timeFormat   || "24h"
    // An explicit undefined check, not `??`: qmlcachegen 6.9.1 (what CI
    // builds with) segfaults AOT-compiling Main.qml when a singleton
    // property it resolves uses the nullish operator. Same shape as
    // showWeekends below, and it still keeps a stored 0 meaning 0.
    readonly property int    snapMinutes:  _calendar.snapMinutes === undefined ? 15 : _calendar.snapMinutes
    readonly property bool   showWeekends: _calendar.showWeekends === undefined ? true : !!_calendar.showWeekends
    // Shortest event the calendar lets you drag or resize into existence — one
    // snap step, matching heap::cal::clampHours on the save side. A hardcoded
    // 15 minutes here fought a 30-minute snap: the drag allowed a length the
    // save then rounded away.
    readonly property real   minEventHours: Math.max(1, snapMinutes) / 60

    // ── Palette — the theme in the active slot (Settings → Appearance) ──
    // AppController.theme picks the slot ("dark" / "light", Ctrl+Shift+T
    // flips it); appearance.darkPreset / lightPreset say which theme sits in
    // each. Every colour below is a token of that theme — ThemePresets.js
    // lists them and holds the built-ins.
    readonly property string slot: AppController.theme === "light" ? "light" : "dark"
    readonly property var customThemes: Array.isArray(_appearance.customThemes) ? _appearance.customThemes : []
    readonly property string darkPresetId:  typeof _appearance.darkPreset === "string" && _appearance.darkPreset.length
                                            ? _appearance.darkPreset : Presets.DEFAULT_DARK
    readonly property string lightPresetId: typeof _appearance.lightPreset === "string" && _appearance.lightPreset.length
                                            ? _appearance.lightPreset : Presets.DEFAULT_LIGHT
    readonly property string activePresetId: slot === "light" ? lightPresetId : darkPresetId
    readonly property var active: Presets.resolve(activePresetId, customThemes, slot)
    // Contrast: "soft" | "normal" | "high". A profile from before the
    // three-way setting only has highContrast, which still means "high".
    readonly property string contrast: _appearance.contrast === "soft" || _appearance.contrast === "normal"
                                       || _appearance.contrast === "high"
                                       ? _appearance.contrast
                                       : (_appearance.highContrast ? "high" : "normal")
    readonly property bool softContrast: contrast === "soft"
    readonly property var _c: softContrast ? Presets.soften(active.colors) : active.colors
    // A translucent border laid over the background, so high contrast has
    // something opaque to push on.
    readonly property color _solidBorder: Qt.tint(_c.bg, _c.border)
    // The theme's own base, not the slot: a light theme in the dark slot is
    // still light, and components that tint by `dark` must follow the colours.
    readonly property bool dark: active.base === "dark"

    // A profile from before themes were editable may carry appearance.accent.
    // It keeps working until the user picks a theme for either slot, then the
    // theme's own accent takes over.
    readonly property bool _legacyAccent: typeof _appearance.accent === "string"
                                          && /^#[0-9a-fA-F]{6}$/.test(_appearance.accent)
                                          && _appearance.darkPreset === undefined
                                          && _appearance.lightPreset === undefined
                                          && _appearance.accent.toLowerCase() !== String(_c.accent).toLowerCase()

    // ── Surfaces ──────────────────────────────────────────────────────
    readonly property color bg:     _c.bg
    readonly property color bg2:    _c.bg2
    readonly property color panel:  _c.panel
    readonly property color panel2: _c.panel2
    readonly property color panel3: _c.panel3

    // ── Lines + text — highContrast strengthens both ──────────────────
    // High contrast is the accessibility mode, so its lines — field outlines
    // included — reach WCAG's 3:1 for UI against bg and panel on every theme;
    // lightening Minimal's hairline left them at about 2:1.
    readonly property var _lineSurfaces: [String(_c.bg), String(Qt.tint(_c.bg, _c.panel)), String(Qt.tint(_c.bg, _c.panel2))]
    readonly property color border:       highContrast
        ? Presets.ensureContrast(String(dark ? Qt.lighter(_solidBorder, 1.6) : Qt.darker(_solidBorder, 1.4)), _lineSurfaces, 3.0)
        : _c.border
    readonly property color borderStrong: highContrast
        ? Presets.ensureContrast(String(dark ? Qt.lighter(_solidBorder, 2.2) : Qt.darker(_solidBorder, 1.8)), _lineSurfaces, 3.5)
        : _c.borderStrong
    // Outline of a text field, combo or checkbox — the only edge a control
    // drawn as panel2 on panel has, so it must reach WCAG's 3:1 for UI
    // (1.4.11) in every contrast mode. The hairline `border` stays for
    // dividers and cards, where it is decoration; on a field it was 1.2:1.
    readonly property color fieldBorder: Presets.ensureContrast(String(Qt.tint(_c.bg, _c.borderStrong)), _lineSurfaces, 3.0)
    readonly property color text:         highContrast ? (dark ? "#ffffff" : "#000000") : _c.text
    readonly property color textMuted:    _c.textMuted
    // The smallest text in the app uses this; every built-in theme keeps it
    // at WCAG AA (4.5:1) on bg, panel and panel2 (tst_Theme checks).
    readonly property color textDim:      _c.textDim
    // Text drawn on an accent / danger fill (primary buttons, badges).
    readonly property color textOnAccent: _c.textOnAccent
    readonly property color textOnDanger: _c.textOnDanger
    // Count badges on the side rail.
    readonly property color textOnBadge:  _c.textOnBadge

    // ── Accent ────────────────────────────────────────────────────────
    readonly property color accent:       _legacyAccent ? _appearance.accent : _c.accent
    readonly property color accentStrong: _legacyAccent ? (dark ? Qt.lighter(accent, 1.18) : Qt.darker(accent, 1.18)) : _c.accentStrong
    readonly property color accentSoft:   _legacyAccent ? Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.18 : 0.12) : _c.accentSoft
    // Hover fill of a primary (accent) button. accentStrong where the label
    // still reads on it; heap. light's accentStrong is darker than accent and
    // left textOnAccent at 3.7:1, so there the hover moves the other way.
    readonly property color accentHover: Presets.contrast(String(textOnAccent), String(accentStrong)) >= 4.5
        ? accentStrong
        : Presets.mix(String(accent), Presets.contrast(String(textOnAccent), "#000000") < 4.5 ? "#ffffff" : "#000000", 0.15)
    // Switch and slider handles.
    readonly property color knob:         _c.knob

    // ── Keyboard focus ────────────────────────────────────────────────
    // The ring around whatever has keyboard focus, and the marker on the
    // highlighted row of a menu or the palette. Both must stand out at 3:1
    // (WCAG 1.4.11) from every surface they are drawn on: accentStrong on a
    // primary button's accent fill was 1.1–1.4:1, and a highlighted menu row
    // was panel2 on panel, 1.03:1. The ring is drawn outside the control, on
    // the surface, so it is measured against the surfaces — and a theme
    // whose accentStrong is too faint for that gets a stronger one.
    readonly property color focusRing: Presets.ensureContrast(String(accentStrong),
        [String(bg), String(panel), String(panel2), String(panel3)], 3.0)
    // Fill of the highlighted menu / palette row; focusRing marks it.
    readonly property color rowHighlight: panel3

    // ── Alerts ────────────────────────────────────────────────────────
    readonly property color danger:      _c.danger
    readonly property color warning:     _c.warning
    readonly property color success:     _c.success
    readonly property color info:        _c.info
    readonly property color toastBg:     _c.toastBg
    readonly property color toastBorder: _c.toastBorder
    readonly property color toastText:   _c.toastText
    // Dim layer behind modal popups.
    readonly property color scrim:       _c.scrim

    // ── Priority ──────────────────────────────────────────────────────
    readonly property color p0: _c.p0
    readonly property color p1: _c.p1
    readonly property color p2: _c.p2
    readonly property color p3: _c.p3

    // ── Status ────────────────────────────────────────────────────────
    readonly property color stBacklog: _c.stBacklog
    readonly property color stTodo:    _c.stTodo
    readonly property color stProg:    _c.stProg
    readonly property color stHalf:    _c.stHalf
    readonly property color stBlocked: _c.stBlocked
    readonly property color stReview:  _c.stReview
    readonly property color stDone:    _c.stDone

    // ── Event-type swatches ──────────────────────────────────────────
    readonly property color mStandup: _c.mStandup
    readonly property color mOneone:  _c.mOneone
    readonly property color mSync:    _c.mSync
    readonly property color mFocus:   _c.mFocus
    // The "now" line across today in the day / week grids.
    readonly property color nowLine:  _c.nowLine

    // ── Syntax (code blocks and snippets) + markdown source editor ──
    readonly property color codeBg:      _c.codeBg
    readonly property color code:        _c.code
    readonly property color synKeyword:  _c.synKeyword
    readonly property color synString:   _c.synString
    readonly property color synNumber:   _c.synNumber
    readonly property color synComment:  _c.synComment
    readonly property color synType:     _c.synType
    readonly property color synBuiltin:  _c.synBuiltin
    readonly property color mention:     _c.mention
    readonly property color ticket:      _c.ticket
    readonly property color tag:         _c.tag
    readonly property color math:        _c.math
    readonly property color heading:     _c.heading
    readonly property color highlightBg: _c.highlightBg

    // ── Rendered markdown (MdDocument palette) ──────────────────────
    readonly property color mdLink:      _c.mdLink
    readonly property color mdCode:      _c.mdCode
    readonly property color mdCodeBg:    _c.mdCodeBg
    readonly property color mdMention:   _c.mdMention
    readonly property color mdTicket:    _c.mdTicket
    readonly property color mdTag:       _c.mdTag
    readonly property color mdMath:      _c.mdMath
    readonly property color mdHighlight: _c.mdHighlight

    // What every CodeHighlighter and MdDocument is handed, so a view cannot
    // drift from the theme by wiring its own mix of tokens.
    readonly property var codePalette: ({
        keyword: synKeyword, string: synString, comment: synComment,
        number: synNumber, type: synType, builtin: synBuiltin
    })
    readonly property var mdPalette: ({
        "text": text, "dim": textDim, "link": mdLink, "code": mdCode,
        "codeBackground": mdCodeBg, "highlightBackground": mdHighlight,
        "mention": mdMention, "ticket": mdTicket, "tag": mdTag, "math": mdMath
    })

    // What every colour picker offers for columns, labels, people and
    // profiles (ThemePresets.SWATCHES).
    readonly property var swatches: Presets.SWATCHES

    // Token by key, for the theme editor and alert kinds.
    function token(key) { return _c[key]; }
    // Text for a label on a coloured fill (count badges): the theme's own
    // textOnBadge when it reads at AA there, else whichever of the dark and
    // light on-colours reads better. White on heap. dark's cyan was 1.9:1.
    function textOn(fill) {
        const f = String(fill);
        const pref = String(textOnBadge);
        if (Presets.contrast(pref, f) >= 4.5) return textOnBadge;
        const alt = [String(textOnAccent), String(textOnDanger), "#ffffff", "#000000"];
        let best = pref, bestRatio = Presets.contrast(pref, f);
        for (let i = 0; i < alt.length; i++) {
            const r = Presets.contrast(alt[i], f);
            if (r > bestRatio) { best = alt[i]; bestRatio = r; }
        }
        return best;
    }
    // A colour that comes from the user's data (a status, a label), used as
    // text on the panels: kept as is where it reads at AA, else nudged just
    // far enough. A column's grey on heap. light's panel was 2.2:1.
    function readable(fg) {
        return Presets.ensureContrast(String(fg), [String(bg), String(Qt.tint(bg, panel)), String(Qt.tint(bg, panel2))], 4.5);
    }
    function alertColor(kind) {
        switch (kind) {
            case "error":   return danger;
            case "warning": return warning;
            case "success": return success;
        }
        return info;
    }

    // ── Geometry — pulled from Brand spacing/radius scale ────────────
    readonly property int rowH:   compact ? 32 : 44
    readonly property int pad:    compact ? Brand.spacing2 : Brand.spacing4
    readonly property int gap:    compact ? Brand.spacing2 : Brand.spacing3
    // Soft contrast rounds a little further; hairline borders read as
    // harsh on tight corners.
    readonly property int radius: softContrast ? Brand.radiusMd + 2 : Brand.radiusMd
    readonly property int hourH:  compact ? 44 : 56

    // ── Spacing scale ────────────────────────────────────────────────
    // Every `spacing`, margin and padding in the app picks one of these, so
    // Tweaks → Density moves the whole layout, not just the hour height.
    // Compact steps each one down a notch. 0 and 1px hairlines stay literal.
    readonly property int sp2xs: compact ? 1 : 2
    readonly property int spXs:  compact ? 3 : 4
    readonly property int spSm:  compact ? 4 : 6
    readonly property int spMd:  compact ? 6 : 8
    readonly property int spLg:  compact ? 8 : 10
    readonly property int spXl:  compact ? 10 : 12
    readonly property int sp2xl: compact ? 12 : 16
    // The inset dialogs, popups and settings cards keep from their edge.
    readonly property int inset: compact ? 14 : 18
    readonly property int sp3xl: compact ? 18 : 24

    // ── Radius scale ─────────────────────────────────────────────────
    readonly property int radiusXs: 2   // bars, hairline tracks
    readonly property int radiusSm: 4   // chips, badges, small buttons
    readonly property int radiusMd: 6   // inputs, pills, cards in lists
    readonly property int radiusLg: 10  // popups, menus
    readonly property int radiusXl: 12  // dialogs, large panels
    readonly property int radiusPill: 999

    // ── Type scale (px) ──────────────────────────────────────────────
    // Six steps. The floor is 11px: nothing the user has to read is smaller.
    readonly property int fsXs:  11  // chips, badges, uppercase section labels
    readonly property int fsSm:  12  // meta, descriptions, secondary text
    readonly property int fsMd:  13  // body, card titles, inputs
    readonly property int fsLg:  15  // dialog and section titles
    readonly property int fsXl:  20  // page headings
    readonly property int fs2xl: 28  // display (welcome, empty hero)

    // ── Accessibility / motion ───────────────────────────────────────
    readonly property bool reducedMotion: !!_appearance.reducedMotion
    readonly property bool highContrast:  contrast === "high"
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

    // Reactive hour formatter — picks 12h/24h based on settings.calendar.timeFormat.
    // Use everywhere a binding needs to refresh on the user flipping the setting;
    // AppController::eventHourLabel is the C++ equivalent for non-QML callers.
    function fmtHour(h) {
        const hh = Math.floor(h);
        const mm = Math.round((h - hh) * 60);
        const mmS = String(mm).padStart(2, "0");
        if (timeFormat === "12h") {
            const h12 = ((hh + 11) % 12) + 1;
            const ampm = hh < 12 ? "am" : "pm";
            return h12 + ":" + mmS + ampm;
        }
        return String(hh).padStart(2, "0") + ":" + mmS;
    }

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
            case "none":    return textMuted;   // a one-off meeting, no routine
        }
        return accent;
    }
}
