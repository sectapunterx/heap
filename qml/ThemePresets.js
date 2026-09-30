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
        text: "#e5ecf3", textMuted: "#a0aab8", textDim: "#86909f",
        textOnAccent: "#06121a", textOnDanger: "#0b0b0f", textOnBadge: "#ffffff",
        accent: "#3bccdd", accentStrong: "#4aecff", accentSoft: "#2e3bccdd", knob: "#ffffff",
        danger: "#e6624c", warning: "#fe9c3a", success: "#78be7a", info: "#5aa3e6",
        toastBg: "#1f2530", toastBorder: "#313a4a", toastText: "#e5ecf3",
        scrim: "#8c000000",
        p0: "#e6624c", p1: "#fe9c3a", p2: "#a0aab8", p3: "#86909f",
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
        textOnAccent: "#06121a", textOnDanger: "#ffffff", textOnBadge: "#ffffff",
        accent: "#178ea0", accentStrong: "#137888", accentSoft: "#1f178ea0", knob: "#ffffff",
        danger: "#b54432", warning: "#945c26", success: "#357650", info: "#1f6fb0",
        toastBg: "#f1f1f1", toastBorder: "#b8bdc5", toastText: "#11151c",
        scrim: "#8c000000",
        p0: "#b54432", p1: "#945c26", p2: "#5f6878", p3: "#646974",
        stBacklog: "#8a909a", stTodo: "#6b7382", stProg: "#1f6fb0", stHalf: "#1f6fb0",
        stBlocked: "#c34a36", stReview: "#4b5463", stDone: "#3e8a5d",
        mStandup: "#1f6fb0", mOneone: "#7a3e91", mSync: "#317e74", mFocus: "#3e8a5d", nowLine: "#c34a36",
        codeBg: "#eaecee", code: "#7a672c", synKeyword: "#137382", synString: "#7a672c",
        synNumber: "#35754f", synComment: "#616a78", synType: "#2d746b", synBuiltin: "#7a3e91",
        mention: "#1f6fb0", ticket: "#806c2e", tag: "#7a3e91", math: "#7a3e91",
        heading: "#9050c3", highlightBg: "#1f178ea0",
        mdLink: "#147989", mdCode: "#11151c", mdCodeBg: "#f8f8f8", mdMention: "#1f6fb0",
        mdTicket: "#147989", mdTag: "#7a3e91", mdMath: "#806c2e", mdHighlight: "#1f178ea0"
    }
};

// The kaneo family: dark, low-contrast, one hue family per theme. Built
// from the Minimal recipe (translucent hairline borders, a monochrome accent,
// colour kept to dots, chips and dates) with the neutrals tinted — Ash
// neutral, Stone warm, Slate cool, Sage green-grey — and every signal colour
// pulled toward grey. Body text sits near 12:1 on bg rather than Minimal's
// 17:1; textDim still clears 4.5:1 on bg, panel and panel2. Design source:
// the "heap themes" Claude Design project (tokens/<id>.css).
var ASH = {
    id: "ash", name: "Ash", base: "dark", builtin: true,
    colors: {
        bg: "#161616", bg2: "#121212", panel: "#1a1a1a", panel2: "#1f1f1f",
        panel3: "#262626", border: "#0fffffff", borderStrong: "#1affffff", text: "#d4d4d4",
        textMuted: "#a3a3a3", textDim: "#8c8c8c", textOnAccent: "#1a1a1a", textOnDanger: "#161616",
        textOnBadge: "#161616", accent: "#d4d4d4", accentStrong: "#e5e5e5", accentSoft: "#14ffffff",
        knob: "#a3a3a3", danger: "#cf7a7c", warning: "#c9ab70", success: "#83b39b",
        info: "#86a3c9", toastBg: "#1f1f1f", toastBorder: "#14ffffff", toastText: "#d4d4d4",
        scrim: "#99000000", p0: "#cf7a7c", p1: "#c99470", p2: "#a3a3a3",
        p3: "#8e8e8e", stBacklog: "#6e6e6e", stTodo: "#a3a3a3", stProg: "#86a3c9",
        stHalf: "#c9ab70", stBlocked: "#cf7a7c", stReview: "#a59bc6", stDone: "#83b39b",
        mStandup: "#86a3c9", mOneone: "#a59bc6", mSync: "#7eaeaa", mFocus: "#83b39b",
        nowLine: "#cf7a7c", synKeyword: "#a59bc6", synString: "#83b39b", synNumber: "#c9ab70",
        synComment: "#7e7e7e", synType: "#86a3c9", synBuiltin: "#d4d4d4", codeBg: "#121212",
        code: "#c4c4c4", mention: "#86a3c9", ticket: "#a3a3a3", tag: "#a59bc6",
        math: "#c9ab70", heading: "#a3a3a3", highlightBg: "#4dc9ab70", mdLink: "#94add0",
        mdCode: "#d4d4d4", mdCodeBg: "#1f1f1f", mdMention: "#86a3c9", mdTicket: "#d4d4d4",
        mdTag: "#a59bc6", mdMath: "#c9ab70", mdHighlight: "#4dc9ab70"
    }
};

var STONE = {
    id: "stone", name: "Stone", base: "dark", builtin: true,
    colors: {
        bg: "#171514", bg2: "#131110", panel: "#1b1918", panel2: "#211e1c",
        panel3: "#2a2724", border: "#0fffffff", borderStrong: "#1affffff", text: "#d6d1cb",
        textMuted: "#a8a29d", textDim: "#958f8a", textOnAccent: "#1b1918", textOnDanger: "#171514",
        textOnBadge: "#171514", accent: "#d6d1cb", accentStrong: "#e7e2dc", accentSoft: "#14ffffff",
        knob: "#a8a29d", danger: "#c97b72", warning: "#c6a66c", success: "#95ad88",
        info: "#91a3b5", toastBg: "#211e1c", toastBorder: "#14ffffff", toastText: "#d6d1cb",
        scrim: "#99000000", p0: "#c97b72", p1: "#c79166", p2: "#a8a29d",
        p3: "#98928e", stBacklog: "#716b66", stTodo: "#a8a29d", stProg: "#91a3b5",
        stHalf: "#c6a66c", stBlocked: "#c97b72", stReview: "#b09ba8", stDone: "#95ad88",
        mStandup: "#91a3b5", mOneone: "#b09ba8", mSync: "#8dab9f", mFocus: "#95ad88",
        nowLine: "#c97b72", synKeyword: "#b09ba8", synString: "#95ad88", synNumber: "#c6a66c",
        synComment: "#847d77", synType: "#91a3b5", synBuiltin: "#d6d1cb", codeBg: "#131110",
        code: "#c9c3bc", mention: "#91a3b5", ticket: "#a8a29d", tag: "#b09ba8",
        math: "#c6a66c", heading: "#a8a29d", highlightBg: "#4dc6a66c", mdLink: "#a3b1be",
        mdCode: "#d6d1cb", mdCodeBg: "#211e1c", mdMention: "#91a3b5", mdTicket: "#d6d1cb",
        mdTag: "#b09ba8", mdMath: "#c6a66c", mdHighlight: "#4dc6a66c"
    }
};

var SLATE = {
    id: "slate", name: "Slate", base: "dark", builtin: true,
    colors: {
        bg: "#13161a", bg2: "#0f1215", panel: "#171a1f", panel2: "#1c2026",
        panel3: "#242931", border: "#0fffffff", borderStrong: "#1affffff", text: "#cdd3db",
        textMuted: "#9da5b0", textDim: "#8b949f", textOnAccent: "#171a1f", textOnDanger: "#13161a",
        textOnBadge: "#13161a", accent: "#bcc7d6", accentStrong: "#d3dbe6", accentSoft: "#14ffffff",
        knob: "#9da5b0", danger: "#c77c84", warning: "#c2a772", success: "#80ad9d",
        info: "#84a0c6", toastBg: "#1c2026", toastBorder: "#14ffffff", toastText: "#cdd3db",
        scrim: "#99000000", p0: "#c77c84", p1: "#c49174", p2: "#9da5b0",
        p3: "#8d95a1", stBacklog: "#687280", stTodo: "#9da5b0", stProg: "#84a0c6",
        stHalf: "#c2a772", stBlocked: "#c77c84", stReview: "#9d98c8", stDone: "#80ad9d",
        mStandup: "#84a0c6", mOneone: "#9d98c8", mSync: "#7aa8ad", mFocus: "#80ad9d",
        nowLine: "#c77c84", synKeyword: "#9d98c8", synString: "#80ad9d", synNumber: "#c2a772",
        synComment: "#747f8e", synType: "#84a0c6", synBuiltin: "#cdd3db", codeBg: "#0f1215",
        code: "#c0c7d0", mention: "#84a0c6", ticket: "#9da5b0", tag: "#9d98c8",
        math: "#c2a772", heading: "#9da5b0", highlightBg: "#4dc2a772", mdLink: "#90aad0",
        mdCode: "#cdd3db", mdCodeBg: "#1c2026", mdMention: "#84a0c6", mdTicket: "#cdd3db",
        mdTag: "#9d98c8", mdMath: "#c2a772", mdHighlight: "#4dc2a772"
    }
};

var SAGE = {
    id: "sage", name: "Sage", base: "dark", builtin: true,
    colors: {
        bg: "#141613", bg2: "#101210", panel: "#181a17", panel2: "#1d201c",
        panel3: "#252923", border: "#0fffffff", borderStrong: "#1affffff", text: "#d0d6cc",
        textMuted: "#a0a79c", textDim: "#8e958a", textOnAccent: "#181a17", textOnDanger: "#141613",
        textOnBadge: "#141613", accent: "#aebfa5", accentStrong: "#c3d1bb", accentSoft: "#14ffffff",
        knob: "#a0a79c", danger: "#c47d73", warning: "#c1a96f", success: "#95b489",
        info: "#8aa5b3", toastBg: "#1d201c", toastBorder: "#14ffffff", toastText: "#d0d6cc",
        scrim: "#99000000", p0: "#c47d73", p1: "#c29269", p2: "#a0a79c",
        p3: "#8f968c", stBacklog: "#6b7268", stTodo: "#a0a79c", stProg: "#8aa5b3",
        stHalf: "#c1a96f", stBlocked: "#c47d73", stReview: "#a79db6", stDone: "#95b489",
        mStandup: "#8aa5b3", mOneone: "#a79db6", mSync: "#89aea2", mFocus: "#95b489",
        nowLine: "#c47d73", synKeyword: "#a79db6", synString: "#95b489", synNumber: "#c1a96f",
        synComment: "#788075", synType: "#8aa5b3", synBuiltin: "#d0d6cc", codeBg: "#101210",
        code: "#c3c9bf", mention: "#8aa5b3", ticket: "#a0a79c", tag: "#a79db6",
        math: "#c1a96f", heading: "#a0a79c", highlightBg: "#4dc1a96f", mdLink: "#9db6c0",
        mdCode: "#d0d6cc", mdCodeBg: "#1d201c", mdMention: "#8aa5b3", mdTicket: "#d0d6cc",
        mdTag: "#a79db6", mdMath: "#c1a96f", mdHighlight: "#4dc1a96f"
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
        textMuted: "#a3a3a3", textDim: "#8c8c8c", textOnAccent: "#262626", textOnDanger: "#141414",
        textOnBadge: "#141414", accent: "#f5f5f5", accentStrong: "#ffffff", accentSoft: "#14ffffff",
        knob: "#a3a3a3", danger: "#fb4b53", warning: "#fbbf24", success: "#34d399",
        info: "#60a5fa", toastBg: "#1c1c1c", toastBorder: "#14ffffff", toastText: "#f5f5f5",
        scrim: "#99000000", p0: "#fb4b53", p1: "#fb923c", p2: "#a3a3a3",
        p3: "#8b8b8b", stBacklog: "#737373", stTodo: "#a3a3a3", stProg: "#60a5fa",
        stHalf: "#fbbf24", stBlocked: "#f87171", stReview: "#a78bfa", stDone: "#34d399",
        mStandup: "#60a5fa", mOneone: "#a78bfa", mSync: "#2dd4bf", mFocus: "#34d399",
        nowLine: "#fb414a", synKeyword: "#a78bfa", synString: "#34d399", synNumber: "#fbbf24",
        synComment: "#7d7d7d", synType: "#60a5fa", synBuiltin: "#f5f5f5", codeBg: "#111111",
        code: "#d4d4d4", mention: "#60a5fa", ticket: "#a3a3a3", tag: "#a78bfa",
        math: "#fbbf24", heading: "#8b8b8b", highlightBg: "#4dfbbf24", mdLink: "#60a5fa",
        mdCode: "#e5e5e5", mdCodeBg: "#1c1c1c", mdMention: "#60a5fa", mdTicket: "#f5f5f5",
        mdTag: "#a78bfa", mdMath: "#fbbf24", mdHighlight: "#4dfbbf24"
    }
};

// The colours the user can give a column, a label, a person or a profile.
// They are stored as data (a column keeps its colour whatever the theme), so
// every picker offers the same ten: one hue per family, then two greys. The
// first is what a new column, person or profile starts with.
var SWATCHES = ["#5cc2dd", "#5aa9e6", "#a4a4d6", "#c07acf", "#e6624c",
                "#e69854", "#dcb86b", "#6ec18a", "#9aa3b4", "#8a8e98"];

var PRESETS = [HEAP_DARK, HEAP_LIGHT, MINIMAL_DARK, ASH, STONE, SLATE, SAGE];

// Built-ins that were retired, and the one that replaces each, so a user who
// picked one lands on its nearest relative instead of the slot default.
var RETIRED = {
    "minimal-light": "heap-light", "muted-mauve": "stone", "graphite": "ash",
    "moss-mono": "sage", "nocturne": "slate"
};

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
// black. A retired built-in resolves to its replacement (RETIRED); any other
// unknown id falls back to the slot's default.
function resolve(id, customThemes, slot) {
    var fallback = builtin(slot === "light" ? DEFAULT_LIGHT : DEFAULT_DARK);
    var t = builtin(id) || _custom(id, customThemes) || builtin(RETIRED[id]);
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
    // JS `%` keeps the sign: magenta (#ff00ff) came out at -60°, fell into the
    // red branch below and softened to #d2002d.
    if (h < 0) h += 360;
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

// ── Contrast (WCAG 2.x) ─────────────────────────────────────────────────

// A colour laid over an opaque surface, as the eye sees it.
function _over(fg, bg) {
    var f = _parse(fg), b = _parse(bg), a = f.a / 255;
    return { a: 255, r: f.r * a + b.r * (1 - a), g: f.g * a + b.g * (1 - a), b: f.b * a + b.b * (1 - a) };
}

function _lum(c) {
    function ch(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

// Contrast ratio of `fg` drawn on `bg` (both "#rrggbb" / "#aarrggbb"; a
// translucent bg is taken over black, a translucent fg over bg).
function contrast(fg, bg) {
    var b = _over(bg, "#000000");
    var f = _over(fg, _fmt(b));
    var la = _lum(f), lb = _lum(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

function _minContrast(fg, surfaces) {
    var m = Infinity;
    for (var i = 0; i < surfaces.length; i++) m = Math.min(m, contrast(fg, surfaces[i]));
    return m;
}

// `fg`, moved toward white on a dark surface or black on a light one just
// far enough to reach `min` against every surface. A colour that already
// passes comes back unchanged, so this only ever repairs.
function ensureContrast(fg, surfaces, min) {
    if (!surfaces.length || _minContrast(fg, surfaces) >= min) return fg;
    var darkSurface = _lum(_over(surfaces[0], "#000000")) < 0.18;
    var target = darkSurface ? "#ffffff" : "#000000";
    var solid = _fmt(_over(fg, surfaces[0]));
    for (var t = 0.05; t <= 1.0001; t += 0.05) {
        var c = mix(solid, target, t);
        if (_minContrast(c, surfaces) >= min) return c;
    }
    return target;
}

// Tokens drawn as text on bg / panel / panel2, which WCAG AA holds to 4.5:1.
var TEXT_ROLES = ["textMuted", "textDim", "p0", "p1", "p2", "p3",
                  "danger", "warning", "success", "info", "accentStrong", "heading",
                  "mention", "ticket", "tag", "math",
                  "mdLink", "mdMention", "mdTicket", "mdTag", "mdMath"];
// Tokens drawn as text on codeBg.
var CODE_ROLES = ["synKeyword", "synString", "synNumber", "synComment", "synType", "synBuiltin", "code"];

// Every text-role token of `colors` brought up to AA where it falls short.
// panel3 is a surface too: it is the highlighted menu / palette row
// (Theme.rowHighlight) and hover fills, and textDim, P3 and headings sat at
// 4.1–4.4:1 on it in every dark theme.
function ensureTextContrast(colors) {
    var c = {};
    for (var k in colors) c[k] = colors[k];
    var surf = [colors.bg, _fmt(_over(colors.panel, colors.bg)), _fmt(_over(colors.panel2, colors.bg)),
                _fmt(_over(colors.panel3, colors.bg))];
    for (var i = 0; i < TEXT_ROLES.length; i++)
        c[TEXT_ROLES[i]] = ensureContrast(colors[TEXT_ROLES[i]], surf, 4.5);
    var code = [_fmt(_over(colors.codeBg, colors.bg))];
    for (var j = 0; j < CODE_ROLES.length; j++)
        c[CODE_ROLES[j]] = ensureContrast(colors[CODE_ROLES[j]], code, 4.5);
    return c;
}

// The theme's own label colour for `fill` while it reads at AA there, else
// black or white, whichever reads better.
function _labelOn(fill, bg, pref) {
    var f = _fmt(_over(fill, bg));
    if (contrast(pref, f) >= 4.5) return pref;
    return contrast("#000000", f) >= contrast("#ffffff", f) ? "#000000" : "#ffffff";
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
    // Losing saturation moves luminance too; a softened P1 or link must still
    // read at AA on the panels it sits on, and a button label on its fill
    // (heap. light's softened accent left textOnAccent at 3.9:1).
    c.textOnAccent = _labelOn(c.accent, c.bg, colors.textOnAccent);
    c.textOnDanger = _labelOn(c.danger, c.bg, colors.textOnDanger);
    return ensureTextContrast(c);
}
