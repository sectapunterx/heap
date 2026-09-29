.pragma library

// Every colour the app paints with, as named tokens, plus the built-in
// themes that fill them in.
//
// Theme.qml reads the active theme through resolve(); Settings → Appearance
// walks TOKENS to build the editor. A theme is { id, name, base, colors }:
// `base` is "dark" or "light" (which slot it belongs to and how high contrast
// pushes it), `colors` maps a token key to "#rrggbb" or "#aarrggbb".
//
// No `??` in this file: qmlcachegen 6.9.1 (what CI builds with) segfaults on
// the nullish operator in code a singleton resolves.

// The editor lists tokens in this order, grouped under `group`.
var GROUPS = ["surfaces", "lines", "text", "accent", "alerts", "overlay",
              "priority", "status", "events", "syntax",
              "editor", "markdown"];

var TOKENS = [
    { key: "bg",           group: "surfaces" },
    { key: "bg2",          group: "surfaces" },
    { key: "panel",        group: "surfaces" },
    { key: "panel2",       group: "surfaces" },
    { key: "panel3",       group: "surfaces" },

    { key: "border",       group: "lines" },
    { key: "borderStrong", group: "lines" },

    { key: "text",         group: "text" },
    { key: "textMuted",    group: "text" },
    { key: "textDim",      group: "text" },
    { key: "textOnAccent", group: "text" },
    { key: "textOnDanger", group: "text" },
    { key: "textOnBadge",  group: "text" },

    { key: "accent",       group: "accent" },
    { key: "accentStrong", group: "accent" },
    { key: "accentSoft",   group: "accent" },
    { key: "knob",         group: "accent" },

    { key: "danger",       group: "alerts" },
    { key: "warning",      group: "alerts" },
    { key: "success",      group: "alerts" },
    { key: "info",         group: "alerts" },
    { key: "toastBg",      group: "alerts" },
    { key: "toastBorder",  group: "alerts" },
    { key: "toastText",    group: "alerts" },

    { key: "scrim",        group: "overlay" },

    { key: "p0",           group: "priority" },
    { key: "p1",           group: "priority" },
    { key: "p2",           group: "priority" },
    { key: "p3",           group: "priority" },

    { key: "stBacklog",    group: "status" },
    { key: "stTodo",       group: "status" },
    { key: "stProg",       group: "status" },
    { key: "stHalf",       group: "status" },
    { key: "stBlocked",    group: "status" },
    { key: "stReview",     group: "status" },
    { key: "stDone",       group: "status" },

    { key: "mStandup",     group: "events" },
    { key: "mOneone",      group: "events" },
    { key: "mSync",        group: "events" },
    { key: "mFocus",       group: "events" },
    { key: "nowLine",      group: "events" },

    { key: "synKeyword",   group: "syntax" },
    { key: "synString",    group: "syntax" },
    { key: "synNumber",    group: "syntax" },
    { key: "synComment",   group: "syntax" },
    { key: "synType",      group: "syntax" },
    { key: "synBuiltin",   group: "syntax" },

    { key: "codeBg",       group: "editor" },
    { key: "code",         group: "editor" },
    { key: "mention",      group: "editor" },
    { key: "ticket",       group: "editor" },
    { key: "tag",          group: "editor" },
    { key: "math",         group: "editor" },
    { key: "heading",      group: "editor" },
    { key: "highlightBg",  group: "editor" },

    { key: "mdLink",       group: "markdown" },
    { key: "mdCode",       group: "markdown" },
    { key: "mdCodeBg",     group: "markdown" },
    { key: "mdMention",    group: "markdown" },
    { key: "mdTicket",     group: "markdown" },
    { key: "mdTag",        group: "markdown" },
    { key: "mdMath",       group: "markdown" },
    { key: "mdHighlight",  group: "markdown" }
];

// heap. as it shipped before themes were editable. Derived shades
// (Qt.lighter/darker of the Brand tokens) are baked in byte for byte, with
// these deliberate changes:
// - code was coloured three different ways (snippets, the notes editor,
//   rendered code blocks); all three now use the syn* tokens, which follow
//   what snippets used;
// - colour is kept for what needs attention. P0/P1 keep their red and
//   orange, P2/P3 are greys; statuses are greys except work in progress
//   (blue), blocked (red) and done (green). Seven hues on a board of seven
//   columns told the eye nothing.
// - textMuted sits between text and textDim; it used to be within a few
//   points of textDim, so the app had two text levels, not three.
var HEAP_DARK = {
    id: "heap-dark", name: "heap. dark", base: "dark", builtin: true,
    colors: {
        bg: "#0b0e13", bg2: "#11151c", panel: "#14181f", panel2: "#1a1f29", panel3: "#1f2530",
        border: "#262d39", borderStrong: "#313a4a",
        text: "#e5ecf3", textMuted: "#a0aab8", textDim: "#808a9a",
        textOnAccent: "#06121a", textOnDanger: "#0b0b0f", textOnBadge: "#ffffff",
        accent: "#3bccdd", accentStrong: "#4aecff", accentSoft: "#2e3bccdd", knob: "#ffffff",
        danger: "#e6624c", warning: "#fe9c3a", success: "#78be7a", info: "#5aa3e6",
        toastBg: "#1f2530", toastBorder: "#313a4a", toastText: "#e5ecf3",
        scrim: "#8c000000",
        p0: "#e6624c", p1: "#fe9c3a", p2: "#a0aab8", p3: "#808a9a",
        stBacklog: "#6f7888", stTodo: "#8a94a3", stProg: "#5aa3e6", stHalf: "#5aa3e6",
        stBlocked: "#e6624c", stReview: "#a0aab8", stDone: "#78be7a",
        mStandup: "#5aa3e6", mOneone: "#c07acf", mSync: "#6cc4b8", mFocus: "#7cc492", nowLine: "#e6624c",
        codeBg: "#11151c", code: "#d8c277", synKeyword: "#3bccdd", synString: "#d8c277",
        synNumber: "#7cc492", synComment: "#808a9a", synType: "#6cc4b8", synBuiltin: "#c07acf",
        mention: "#5aa3e6", ticket: "#d8c277", tag: "#c07acf", math: "#c07acf",
        heading: "#b58ad7", highlightBg: "#2e3bccdd",
        mdLink: "#3bccdd", mdCode: "#e5ecf3", mdCodeBg: "#1a1f29", mdMention: "#32b2e7",
        mdTicket: "#3bccdd", mdTag: "#bf94ec", mdMath: "#d8c277", mdHighlight: "#2e3bccdd"
    }
};

var HEAP_LIGHT = {
    id: "heap-light", name: "heap. light", base: "light", builtin: true,
    colors: {
        bg: "#f3f5f8", bg2: "#eaecee", panel: "#ffffff", panel2: "#f8f8f8", panel3: "#f1f1f1",
        border: "#dde3ec", borderStrong: "#b8bdc5",
        text: "#11151c", textMuted: "#4b5463", textDim: "#656e7d",
        textOnAccent: "#06121a", textOnDanger: "#0b0b0f", textOnBadge: "#ffffff",
        accent: "#178ea0", accentStrong: "#137888", accentSoft: "#1f178ea0", knob: "#ffffff",
        danger: "#c34a36", warning: "#bd7530", success: "#3e8a5d", info: "#1f6fb0",
        toastBg: "#f1f1f1", toastBorder: "#b8bdc5", toastText: "#11151c",
        scrim: "#8c000000",
        p0: "#c34a36", p1: "#bd7530", p2: "#5f6878", p3: "#7a808c",
        stBacklog: "#8a909a", stTodo: "#6b7382", stProg: "#1f6fb0", stHalf: "#1f6fb0",
        stBlocked: "#c34a36", stReview: "#4b5463", stDone: "#3e8a5d",
        mStandup: "#1f6fb0", mOneone: "#7a3e91", mSync: "#317e74", mFocus: "#3e8a5d", nowLine: "#c34a36",
        codeBg: "#eaecee", code: "#9a8237", synKeyword: "#178ea0", synString: "#9a8237",
        synNumber: "#3e8a5d", synComment: "#656e7d", synType: "#317e74", synBuiltin: "#7a3e91",
        mention: "#1f6fb0", ticket: "#9a8237", tag: "#7a3e91", math: "#7a3e91",
        heading: "#b58ad7", highlightBg: "#1f178ea0",
        mdLink: "#178ea0", mdCode: "#11151c", mdCodeBg: "#f8f8f8", mdMention: "#1f6fb0",
        mdTicket: "#178ea0", mdTag: "#7a3e91", mdMath: "#9a8237", mdHighlight: "#1f178ea0"
    }
};

// The author's desktop and editor themes (Confluence, space SD): Muted
// Mauve, and the Neovim themes Graphite («Графит»), moss-mono and nocturne.
// Palette values are theirs; tokens the palettes have no role for are mixed
// from neighbouring ones. textDim is lifted just enough toward the text
// colour to clear WCAG AA on bg / panel / panel2 — each palette's own "dim"
// sat at 3–4.5:1 on the raised panels.
var MUTED_MAUVE = {
    id: "muted-mauve", name: "Muted Mauve", base: "dark", builtin: true,
    colors: {
        bg: "#17141f", bg2: "#131019", panel: "#1e1a29", panel2: "#262035",
        panel3: "#3a3050", border: "#332b45", borderStrong: "#4a425b", text: "#c0b9cc",
        textMuted: "#a79fb5", textDim: "#8e879e", textOnAccent: "#17141f", textOnDanger: "#17141f",
        textOnBadge: "#17141f", accent: "#b49bd0", accentStrong: "#c2add8", accentSoft: "#2eb49bd0",
        knob: "#c0b9cc", danger: "#b98a95", warning: "#d8c19c", success: "#93ab97",
        info: "#9aa7cf", toastBg: "#262035", toastBorder: "#5cb49bd0", toastText: "#c0b9cc",
        scrim: "#8c0c0a10", p0: "#b98a95", p1: "#d8c19c", p2: "#93a8ad",
        p3: "#78718a", stBacklog: "#78718a", stTodo: "#a79fb5", stProg: "#9aa7cf",
        stHalf: "#d8c19c", stBlocked: "#b98a95", stReview: "#b49bd0", stDone: "#93ab97",
        mStandup: "#9aa7cf", mOneone: "#b49bd0", mSync: "#93a8ad", mFocus: "#93ab97",
        nowLine: "#d8c19c", synKeyword: "#b49bd0", synString: "#93ab97", synNumber: "#93a8ad",
        synComment: "#655e75", synType: "#8f7aa8", synBuiltin: "#9aa7cf", codeBg: "#1e1a29",
        code: "#93a8ad", mention: "#9aa7cf", ticket: "#93a8ad", tag: "#b49bd0",
        math: "#8f7aa8", heading: "#b49bd0", highlightBg: "#3a3050", mdLink: "#9aa7cf",
        mdCode: "#c0b9cc", mdCodeBg: "#262035", mdMention: "#9aa7cf", mdTicket: "#b49bd0",
        mdTag: "#b49bd0", mdMath: "#93a8ad", mdHighlight: "#3a3050"
    }
};

var GRAPHITE = {
    id: "graphite", name: "Graphite", base: "dark", builtin: true,
    colors: {
        bg: "#1a1b20", bg2: "#15161a", panel: "#212329", panel2: "#31313a",
        panel3: "#36383e", border: "#3e4147", borderStrong: "#44454b", text: "#c3c5cc",
        textMuted: "#9fa1a9", textDim: "#9799a2", textOnAccent: "#1a1b20", textOnDanger: "#1a1b20",
        textOnBadge: "#1a1b20", accent: "#93c088", accentStrong: "#a3d197", accentSoft: "#2e93c088",
        knob: "#c3c5cc", danger: "#e08f8d", warning: "#d9bf8f", success: "#93c088",
        info: "#86b5dd", toastBg: "#31313a", toastBorder: "#44454b", toastText: "#c3c5cc",
        scrim: "#8c000000", p0: "#e08f8d", p1: "#d9bf8f", p2: "#bfa0cf",
        p3: "#86b5dd", stBacklog: "#8a8c96", stTodo: "#9fa1a9", stProg: "#86b5dd",
        stHalf: "#d9bf8f", stBlocked: "#e08f8d", stReview: "#bfa0cf", stDone: "#93c088",
        mStandup: "#86b5dd", mOneone: "#bfa0cf", mSync: "#d9bf8f", mFocus: "#93c088",
        nowLine: "#e08f8d", synKeyword: "#93c088", synString: "#9fa1a9", synNumber: "#d9bf8f",
        synComment: "#8a8c96", synType: "#86b5dd", synBuiltin: "#ffffff", codeBg: "#212329",
        code: "#d9bf8f", mention: "#86b5dd", ticket: "#d9bf8f", tag: "#bfa0cf",
        math: "#d9bf8f", heading: "#86b5dd", highlightBg: "#3393c088", mdLink: "#86b5dd",
        mdCode: "#c3c5cc", mdCodeBg: "#31313a", mdMention: "#86b5dd", mdTicket: "#93c088",
        mdTag: "#bfa0cf", mdMath: "#d9bf8f", mdHighlight: "#3393c088"
    }
};

var MOSS_MONO = {
    id: "moss-mono", name: "moss-mono", base: "dark", builtin: true,
    colors: {
        bg: "#212121", bg2: "#1c1c1c", panel: "#1d1d1d", panel2: "#2a2a2a",
        panel3: "#373737", border: "#2f2f2f", borderStrong: "#4c4c4c", text: "#d9d9d9",
        textMuted: "#a6a6a6", textDim: "#969696", textOnAccent: "#212121", textOnDanger: "#212121",
        textOnBadge: "#212121", accent: "#7db07a", accentStrong: "#94be92", accentSoft: "#2e7db07a",
        knob: "#e6e6e6", danger: "#c07a70", warning: "#c2a97a", success: "#7db07a",
        info: "#a5a5a5", toastBg: "#2a2a2a", toastBorder: "#4c4c4c", toastText: "#d9d9d9",
        scrim: "#8c000000", p0: "#c07a70", p1: "#c2a97a", p2: "#b0a377",
        p3: "#969696", stBacklog: "#818181", stTodo: "#aeaeae", stProg: "#e6e6e6",
        stHalf: "#c2a97a", stBlocked: "#c07a70", stReview: "#b9b9b9", stDone: "#7db07a",
        mStandup: "#c6c6c6", mOneone: "#aeaeae", mSync: "#bdbdbd", mFocus: "#7db07a",
        nowLine: "#7db07a", synKeyword: "#7db07a", synString: "#a6a6a6", synNumber: "#bdbdbd",
        synComment: "#777777", synType: "#c6c6c6", synBuiltin: "#e6e6e6", codeBg: "#1c1c1c",
        code: "#bdbdbd", mention: "#d0d0d0", ticket: "#c6c6c6", tag: "#aeaeae",
        math: "#b9b9b9", heading: "#7db07a", highlightBg: "#373737", mdLink: "#7db07a",
        mdCode: "#d9d9d9", mdCodeBg: "#2a2a2a", mdMention: "#d0d0d0", mdTicket: "#7db07a",
        mdTag: "#aeaeae", mdMath: "#bdbdbd", mdHighlight: "#373737"
    }
};

var NOCTURNE = {
    id: "nocturne", name: "nocturne", base: "dark", builtin: true,
    colors: {
        bg: "#15181d", bg2: "#111418", panel: "#1a1e24", panel2: "#1f262d",
        panel3: "#253039", border: "#2b353e", borderStrong: "#39414a", text: "#a8b2bd",
        textMuted: "#929da8", textDim: "#828d99", textOnAccent: "#15181d", textOnDanger: "#15181d",
        textOnBadge: "#15181d", accent: "#7d9cc0", accentStrong: "#9cb4ce", accentSoft: "#2e7d9cc0",
        knob: "#e6ebf0", danger: "#b57f7f", warning: "#b5a67f", success: "#7fa8a0",
        info: "#7d9cc0", toastBg: "#1f262d", toastBorder: "#39414a", toastText: "#a8b2bd",
        scrim: "#8c000000", p0: "#b57f7f", p1: "#b5a67f", p2: "#a89ab8",
        p3: "#7d9cc0", stBacklog: "#7d8894", stTodo: "#a8b2bd", stProg: "#7d9cc0",
        stHalf: "#b5a67f", stBlocked: "#b57f7f", stReview: "#a89ab8", stDone: "#7fa8a0",
        mStandup: "#7d9cc0", mOneone: "#a89ab8", mSync: "#7fa8a0", mFocus: "#e6ebf0",
        nowLine: "#b57f7f", synKeyword: "#7d9cc0", synString: "#7fa8a0", synNumber: "#a89ab8",
        synComment: "#5a646f", synType: "#7fa8a0", synBuiltin: "#e6ebf0", codeBg: "#1a1e24",
        code: "#a89ab8", mention: "#7d9cc0", ticket: "#a89ab8", tag: "#7fa8a0",
        math: "#a89ab8", heading: "#7d9cc0", highlightBg: "#253039", mdLink: "#7d9cc0",
        mdCode: "#e6ebf0", mdCodeBg: "#1a1e24", mdMention: "#7d9cc0", mdTicket: "#a89ab8",
        mdTag: "#7fa8a0", mdMath: "#a89ab8", mdHighlight: "#253039"
    }
};

// Minimal: neutral surfaces, hairline translucent borders, a monochrome
// accent, and colour kept to the small things — dots, chips, dates. Tokens
// read off kaneo.app's stylesheet (its shadcn .dark / :root variables).
var MINIMAL_DARK = {
    id: "minimal-dark", name: "Minimal dark", base: "dark", builtin: true,
    colors: {
        bg: "#141414", bg2: "#111111", panel: "#171717", panel2: "#1c1c1c",
        panel3: "#232323", border: "#0fffffff", borderStrong: "#1affffff", text: "#f5f5f5",
        textMuted: "#a3a3a3", textDim: "#868686", textOnAccent: "#262626", textOnDanger: "#141414",
        textOnBadge: "#141414", accent: "#f5f5f5", accentStrong: "#ffffff", accentSoft: "#14ffffff",
        knob: "#a3a3a3", danger: "#fb414a", warning: "#fbbf24", success: "#34d399",
        info: "#60a5fa", toastBg: "#1c1c1c", toastBorder: "#14ffffff", toastText: "#f5f5f5",
        scrim: "#99000000", p0: "#fb414a", p1: "#fb923c", p2: "#a3a3a3",
        p3: "#737373", stBacklog: "#737373", stTodo: "#a3a3a3", stProg: "#60a5fa",
        stHalf: "#fbbf24", stBlocked: "#f87171", stReview: "#a78bfa", stDone: "#34d399",
        mStandup: "#60a5fa", mOneone: "#a78bfa", mSync: "#2dd4bf", mFocus: "#34d399",
        nowLine: "#fb414a", synKeyword: "#a78bfa", synString: "#34d399", synNumber: "#fbbf24",
        synComment: "#737373", synType: "#60a5fa", synBuiltin: "#f5f5f5", codeBg: "#111111",
        code: "#d4d4d4", mention: "#60a5fa", ticket: "#a3a3a3", tag: "#a78bfa",
        math: "#fbbf24", heading: "#737373", highlightBg: "#14ffffff", mdLink: "#60a5fa",
        mdCode: "#e5e5e5", mdCodeBg: "#1c1c1c", mdMention: "#60a5fa", mdTicket: "#f5f5f5",
        mdTag: "#a78bfa", mdMath: "#fbbf24", mdHighlight: "#14ffffff"
    }
};

var MINIMAL_LIGHT = {
    id: "minimal-light", name: "Minimal light", base: "light", builtin: true,
    colors: {
        bg: "#ffffff", bg2: "#fafafa", panel: "#fafafa", panel2: "#f5f5f5",
        panel3: "#ebebeb", border: "#14000000", borderStrong: "#1f000000", text: "#262626",
        textMuted: "#525252", textDim: "#686868", textOnAccent: "#fafafa", textOnDanger: "#ffffff",
        textOnBadge: "#ffffff", accent: "#262626", accentStrong: "#0a0a0a", accentSoft: "#12000000",
        knob: "#ffffff", danger: "#dc2626", warning: "#d97706", success: "#059669",
        info: "#2563eb", toastBg: "#ffffff", toastBorder: "#14000000", toastText: "#262626",
        scrim: "#66000000", p0: "#dc2626", p1: "#ea580c", p2: "#737373",
        p3: "#a3a3a3", stBacklog: "#a3a3a3", stTodo: "#737373", stProg: "#2563eb",
        stHalf: "#d97706", stBlocked: "#dc2626", stReview: "#7c3aed", stDone: "#059669",
        mStandup: "#2563eb", mOneone: "#7c3aed", mSync: "#0d9488", mFocus: "#059669",
        nowLine: "#dc2626", synKeyword: "#7c3aed", synString: "#059669", synNumber: "#b45309",
        synComment: "#a3a3a3", synType: "#2563eb", synBuiltin: "#262626", codeBg: "#fafafa",
        code: "#404040", mention: "#2563eb", ticket: "#525252", tag: "#7c3aed",
        math: "#b45309", heading: "#a3a3a3", highlightBg: "#12000000", mdLink: "#2563eb",
        mdCode: "#262626", mdCodeBg: "#f5f5f5", mdMention: "#2563eb", mdTicket: "#262626",
        mdTag: "#7c3aed", mdMath: "#b45309", mdHighlight: "#12000000"
    }
};

// The colours the user can give a column, a label, a person or a profile.
// They are stored as data (a column keeps its colour whatever the theme), so
// every picker offers the same ten: one hue per family, then two greys. The
// first is what a new column, person or profile starts with.
var SWATCHES = ["#5cc2dd", "#5aa9e6", "#a4a4d6", "#c07acf", "#e6624c",
                "#e69854", "#dcb86b", "#6ec18a", "#9aa3b4", "#8a8e98"];

var PRESETS = [HEAP_DARK, HEAP_LIGHT, MINIMAL_DARK, MINIMAL_LIGHT,
               MUTED_MAUVE, GRAPHITE, MOSS_MONO, NOCTURNE];

var DEFAULT_DARK = "heap-dark";
var DEFAULT_LIGHT = "heap-light";

var _HEX = /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;

function isHex(s) {
    return typeof s === "string" && _HEX.test(s);
}

function isToken(key) {
    for (var i = 0; i < TOKENS.length; i++)
        if (TOKENS[i].key === key) return true;
    return false;
}

function builtin(id) {
    for (var i = 0; i < PRESETS.length; i++)
        if (PRESETS[i].id === id) return PRESETS[i];
    return null;
}

function _custom(id, customThemes) {
    if (!Array.isArray(customThemes)) return null;
    for (var i = 0; i < customThemes.length; i++) {
        var t = customThemes[i];
        if (t && t.id === id) return t;
    }
    return null;
}

// Every theme the user can pick: built-ins first, then their own.
function all(customThemes) {
    var out = PRESETS.slice();
    if (Array.isArray(customThemes)) {
        for (var i = 0; i < customThemes.length; i++) {
            var t = customThemes[i];
            if (t && typeof t.id === "string" && !builtin(t.id)) out.push(t);
        }
    }
    return out;
}

// The theme `id` names, with every token filled in. A custom theme is laid
// over the built-in of its base, so a theme saved before a token existed, or
// one with a broken value, still paints that token instead of leaving it
// black. An unknown id falls back to the slot's default.
function resolve(id, customThemes, slot) {
    var fallback = builtin(slot === "light" ? DEFAULT_LIGHT : DEFAULT_DARK);
    var t = builtin(id) || _custom(id, customThemes);
    if (!t) return fallback;
    var base = t.base === "light" ? HEAP_LIGHT : HEAP_DARK;
    var colors = {};
    for (var i = 0; i < TOKENS.length; i++) {
        var k = TOKENS[i].key;
        var v = t.colors ? t.colors[k] : undefined;
        colors[k] = isHex(v) ? v : base.colors[k];
    }
    return { id: t.id, name: t.name || t.id, base: base.base, builtin: !!t.builtin, colors: colors };
}

// A theme from outside (pasted JSON) cut down to what resolve() accepts:
// known tokens with valid hex values. Returns null when nothing usable is
// left, so the caller can say so instead of adding an empty theme.
function validateTheme(obj) {
    if (!obj || typeof obj !== "object") return null;
    var src = obj.colors && typeof obj.colors === "object" ? obj.colors : obj;
    var colors = {};
    var n = 0;
    for (var i = 0; i < TOKENS.length; i++) {
        var k = TOKENS[i].key;
        if (isHex(src[k])) { colors[k] = src[k].toLowerCase(); n++; }
    }
    if (n === 0) return null;
    var name = typeof obj.name === "string" && obj.name.trim().length ? obj.name.trim().slice(0, 60) : "";
    return { name: name, base: obj.base === "light" ? "light" : "dark", colors: colors };
}

// A fresh id no existing custom theme uses.
function newId(customThemes) {
    var n = 1;
    while (_custom("custom-" + n, customThemes)) n++;
    return "custom-" + n;
}

// What export writes: the full resolved palette, so the JSON is complete
// even for a custom theme that relied on its base for some tokens.
function exportJson(id, customThemes, slot) {
    var t = resolve(id, customThemes, slot);
    return JSON.stringify({ name: t.name, base: t.base, colors: t.colors }, null, 2);
}

// ── Soft contrast ───────────────────────────────────────────────────────
// Settings → Appearance → Contrast → Soft, over any theme: borders fade to
// hairlines, the raised panels close in on the panel, and every coloured
// token loses a third of its saturation, so colour still tells things apart
// but nothing shouts. Text is left alone — its contrast is what keeps the
// app readable, and textDim stays at WCAG AA.

function _parse(s) {
    var h = s.charAt(0) === "#" ? s.slice(1) : s;
    var a = 255;
    if (h.length === 8) { a = parseInt(h.slice(0, 2), 16); h = h.slice(2); }
    return { a: a, r: parseInt(h.slice(0, 2), 16), g: parseInt(h.slice(2, 4), 16), b: parseInt(h.slice(4, 6), 16) };
}

function _fmt(c) {
    function h2(n) { n = Math.max(0, Math.min(255, Math.round(n))); return (n < 16 ? "0" : "") + n.toString(16); }
    return "#" + (c.a < 255 ? h2(c.a) : "") + h2(c.r) + h2(c.g) + h2(c.b);
}

// Toward `to` by t, alpha included.
function mix(from, to, t) {
    var a = _parse(from), b = _parse(to);
    return _fmt({ a: a.a + (b.a - a.a) * t, r: a.r + (b.r - a.r) * t,
                  g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t });
}

// Scale HSL saturation by k, keeping hue, lightness and alpha.
function desaturate(s, k) {
    var c = _parse(s);
    var r = c.r / 255, g = c.g / 255, b = c.b / 255;
    var max = Math.max(r, g, b), min = Math.min(r, g, b);
    var l = (max + min) / 2, d = max - min;
    if (d === 0) return s;
    var sat = d / (1 - Math.abs(2 * l - 1));
    var h;
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
    sat *= k;
    var C = (1 - Math.abs(2 * l - 1)) * sat, X = C * (1 - Math.abs((h / 60) % 2 - 1)), m = l - C / 2;
    var rgb = h < 60 ? [C, X, 0] : h < 120 ? [X, C, 0] : h < 180 ? [0, C, X]
            : h < 240 ? [0, X, C] : h < 300 ? [X, 0, C] : [C, 0, X];
    return _fmt({ a: c.a, r: (rgb[0] + m) * 255, g: (rgb[1] + m) * 255, b: (rgb[2] + m) * 255 });
}

function _scaleAlpha(s, k) {
    var c = _parse(s);
    c.a = c.a * k;
    return _fmt(c);
}

// Tokens that carry a colour for meaning, not structure.
var _COLOURED = ["accent", "accentStrong", "danger", "warning", "success", "info",
                 "p0", "p1", "p2", "p3",
                 "stBacklog", "stTodo", "stProg", "stHalf", "stBlocked", "stReview", "stDone",
                 "mStandup", "mOneone", "mSync", "mFocus", "nowLine",
                 "synKeyword", "synString", "synNumber", "synType", "synBuiltin",
                 "code", "mention", "ticket", "tag", "math", "heading",
                 "mdLink", "mdMention", "mdTicket", "mdTag", "mdMath"];

// Closer to `bg` by t. A translucent colour already lets the surface through,
// so it fades by alpha; mixing it with an opaque colour would raise it.
function _fade(s, bg, t) {
    return _parse(s).a < 255 ? _scaleAlpha(s, 1 - t) : mix(s, bg, t);
}

function soften(colors) {
    var c = {};
    for (var k in colors) c[k] = colors[k];
    c.border = _fade(colors.border, colors.bg, 0.5);
    c.borderStrong = _fade(colors.borderStrong, colors.bg, 0.4);
    c.toastBorder = _fade(colors.toastBorder, colors.toastBg, 0.5);
    c.panel2 = _fade(colors.panel2, colors.panel, 0.4);
    c.panel3 = _fade(colors.panel3, colors.panel, 0.3);
    c.accentSoft = _scaleAlpha(colors.accentSoft, 0.7);
    c.highlightBg = _scaleAlpha(colors.highlightBg, 0.7);
    c.mdHighlight = _scaleAlpha(colors.mdHighlight, 0.7);
    c.scrim = _scaleAlpha(colors.scrim, 0.8);
    for (var i = 0; i < _COLOURED.length; i++)
        c[_COLOURED[i]] = desaturate(colors[_COLOURED[i]], 0.65);
    return c;
}
