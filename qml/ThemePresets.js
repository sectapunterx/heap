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
    id: "heap-dark", name: "heap. dark", base: "dark", contrast: "high", builtin: true,
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
    id: "heap-light", name: "heap. light", base: "light", contrast: "high", builtin: true,
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

// The APP-119 family: five dark themes, each a near-black ground tinted
// toward one hue and a single saturated accent for the primary button,
// selection, focus and the now line. Signal colours stay distinct from the
// accent (Crimson's blockers sit lighter and more coral than its red; Ochre's
// P1 is terracotta beside the amber; Fjord's done is yellow-green beside the
// teal; Dusk's review is pink beside the lavender). Design source: the
// "heap — dark themes" Claude Design canvas (one artboard per theme).
// Crimson and Graphite are high contrast as drawn. Ochre, Fjord and Dusk are
// the low-contrast set: body text eased toward the ground (about 11:1),
// hairlines closer to it and the colours a fifth less saturated, with textDim
// left where it was so it still clears AA.
var CRIMSON = {
    id: "crimson", name: "Crimson", base: "dark", contrast: "high", builtin: true,
    colors: {
        bg: "#090707", bg2: "#100e0e", panel: "#100e0e", panel2: "#181515", panel3: "#201d1d",
        border: "#272424", borderStrong: "#3a3737", text: "#edeaea", textMuted: "#c0bdbd",
        textDim: "#9b9797", textOnAccent: "#ffffff", textOnDanger: "#090707", textOnBadge: "#090707",
        accent: "#d42f34", accentStrong: "#ff6d67", accentSoft: "#331415", knob: "#edeaea",
        danger: "#f66c6d", warning: "#ebb854", success: "#5dc47e", info: "#61b1e6", toastBg: "#181515",
        toastBorder: "#3a3737", toastText: "#edeaea", scrim: "#99000000", p0: "#f66c6d", p1: "#f49752",
        p2: "#c0bdbd", p3: "#9b9797", stBacklog: "#6f6c6c", stTodo: "#c0bdbd", stProg: "#61b1e6",
        stHalf: "#ebb854", stBlocked: "#f66c6d", stReview: "#b88fe6", stDone: "#5dc47e", mStandup: "#61b1e6",
        mOneone: "#b88fe6", mSync: "#5fbab2", mFocus: "#5dc47e", nowLine: "#d42f34", synKeyword: "#ff6d67",
        synString: "#5dc47e", synNumber: "#ebb854", synComment: "#9b9797", synType: "#61b1e6",
        synBuiltin: "#b88fe6", codeBg: "#100e0e", code: "#c0bdbd", mention: "#61b1e6", ticket: "#c0bdbd",
        tag: "#b88fe6", math: "#ebb854", heading: "#ff6d67", highlightBg: "#4debb854", mdLink: "#ff6d67",
        mdCode: "#edeaea", mdCodeBg: "#181515", mdMention: "#61b1e6", mdTicket: "#ff6d67", mdTag: "#b88fe6",
        mdMath: "#ebb854", mdHighlight: "#4debb854"
    }
};

var GRAPHITE = {
    id: "graphite", name: "Graphite", base: "dark", contrast: "high", builtin: true,
    colors: {
        bg: "#0e1115", bg2: "#16181d", panel: "#16181d", panel2: "#1e2125", panel3: "#26292e",
        border: "#2d3035", borderStrong: "#40444a", text: "#e9ebef", textMuted: "#bbbec3",
        textDim: "#95989f", textOnAccent: "#0a1018", textOnDanger: "#0e1115", textOnBadge: "#0e1115",
        accent: "#659ff4", accentStrong: "#75a9f6", accentSoft: "#232e3f", knob: "#e9ebef",
        danger: "#ef6663", warning: "#ebb854", success: "#5dc47e", info: "#51c6e0", toastBg: "#1e2125",
        toastBorder: "#40444a", toastText: "#e9ebef", scrim: "#99000000", p0: "#ef6663", p1: "#f49752",
        p2: "#bbbec3", p3: "#95989f", stBacklog: "#6c7076", stTodo: "#bbbec3", stProg: "#51c6e0",
        stHalf: "#ebb854", stBlocked: "#ef6663", stReview: "#b88fe6", stDone: "#5dc47e", mStandup: "#51c6e0",
        mOneone: "#b88fe6", mSync: "#57c5af", mFocus: "#5dc47e", nowLine: "#659ff4", synKeyword: "#75a9f6",
        synString: "#5dc47e", synNumber: "#ebb854", synComment: "#95989f", synType: "#51c6e0",
        synBuiltin: "#b88fe6", codeBg: "#16181d", code: "#bbbec3", mention: "#51c6e0", ticket: "#bbbec3",
        tag: "#b88fe6", math: "#ebb854", heading: "#75a9f6", highlightBg: "#4debb854", mdLink: "#75a9f6",
        mdCode: "#e9ebef", mdCodeBg: "#1e2125", mdMention: "#51c6e0", mdTicket: "#75a9f6", mdTag: "#b88fe6",
        mdMath: "#ebb854", mdHighlight: "#4debb854"
    }
};

var OCHRE = {
    id: "ochre", name: "Ochre", base: "dark", contrast: "low", builtin: true,
    colors: {
        bg: "#120d09", bg2: "#1a1511", panel: "#1a1511", panel2: "#221d18", panel3: "#2b2521",
        border: "#27211d", borderStrong: "#37302b", text: "#c3beba", textMuted: "#aea7a3",
        textDim: "#9e9791", textOnAccent: "#150e06", textOnDanger: "#120d09", textOnBadge: "#120d09",
        accent: "#e0a85d", accentStrong: "#e7b574", accentSoft: "#3c2d1b", knob: "#c3beba",
        danger: "#e17371", warning: "#d8c96a", success: "#67ba82", info: "#6eaed9", toastBg: "#221d18",
        toastBorder: "#37302b", toastText: "#c3beba", scrim: "#99000000", p0: "#e17371", p1: "#e3876b",
        p2: "#aea7a3", p3: "#9e9791", stBacklog: "#746e68", stTodo: "#aea7a3", stProg: "#6eaed9",
        stHalf: "#d8c96a", stBlocked: "#e17371", stReview: "#b998dd", stDone: "#67ba82", mStandup: "#6eaed9",
        mOneone: "#b998dd", mSync: "#6ab4ae", mFocus: "#67ba82", nowLine: "#e0a85d", synKeyword: "#e7b574",
        synString: "#67ba82", synNumber: "#d8c96a", synComment: "#9e9791", synType: "#6eaed9",
        synBuiltin: "#b998dd", codeBg: "#1a1511", code: "#aea7a3", mention: "#6eaed9", ticket: "#aea7a3",
        tag: "#b998dd", math: "#d8c96a", heading: "#e7b574", highlightBg: "#4dd8c96a", mdLink: "#e7b574",
        mdCode: "#c3beba", mdCodeBg: "#221d18", mdMention: "#6eaed9", mdTicket: "#e7b574", mdTag: "#b998dd",
        mdMath: "#d8c96a", mdHighlight: "#4dd8c96a"
    }
};

var FJORD = {
    id: "fjord", name: "Fjord", base: "dark", contrast: "low", builtin: true,
    colors: {
        bg: "#051013", bg2: "#0c181b", panel: "#0c181b", panel2: "#142023", panel3: "#1c292c",
        border: "#192528", borderStrong: "#263438", text: "#b7c1c4", textMuted: "#9fabae",
        textDim: "#8c9b9f", textOnAccent: "#051210", textOnDanger: "#051013", textOnBadge: "#051013",
        accent: "#60bfb1", accentStrong: "#77c9bb", accentSoft: "#183534", knob: "#b7c1c4",
        danger: "#e17371", warning: "#dcb363", success: "#8fc270", info: "#6eaed9", toastBg: "#142023",
        toastBorder: "#263438", toastText: "#b7c1c4", scrim: "#99000000", p0: "#e17371", p1: "#e49962",
        p2: "#9fabae", p3: "#8c9b9f", stBacklog: "#647175", stTodo: "#9fabae", stProg: "#6eaed9",
        stHalf: "#dcb363", stBlocked: "#e17371", stReview: "#b998dd", stDone: "#8fc270", mStandup: "#6eaed9",
        mOneone: "#b998dd", mSync: "#7eb8a4", mFocus: "#8fc270", nowLine: "#60bfb1", synKeyword: "#77c9bb",
        synString: "#8fc270", synNumber: "#dcb363", synComment: "#8c9b9f", synType: "#6eaed9",
        synBuiltin: "#b998dd", codeBg: "#0c181b", code: "#9fabae", mention: "#6eaed9", ticket: "#9fabae",
        tag: "#b998dd", math: "#dcb363", heading: "#77c9bb", highlightBg: "#4ddcb363", mdLink: "#77c9bb",
        mdCode: "#b7c1c4", mdCodeBg: "#142023", mdMention: "#6eaed9", mdTicket: "#77c9bb", mdTag: "#b998dd",
        mdMath: "#dcb363", mdHighlight: "#4ddcb363"
    }
};

var DUSK = {
    id: "dusk", name: "Dusk", base: "dark", contrast: "low", builtin: true,
    colors: {
        bg: "#0e0d16", bg2: "#16151f", panel: "#16151f", panel2: "#1e1d27", panel3: "#262530",
        border: "#22212b", borderStrong: "#32303c", text: "#bfbec7", textMuted: "#a8a7b3",
        textDim: "#9896a4", textOnAccent: "#0f0e17", textOnDanger: "#0e0d16", textOnBadge: "#0e0d16",
        accent: "#afa1e9", accentStrong: "#b8abed", accentSoft: "#2e2a41", knob: "#bfbec7",
        danger: "#e17371", warning: "#dcb363", success: "#67ba82", info: "#6eaed9", toastBg: "#1e1d27",
        toastBorder: "#32303c", toastText: "#bfbec7", scrim: "#99000000", p0: "#e17371", p1: "#e49962",
        p2: "#a8a7b3", p3: "#9896a4", stBacklog: "#6f6d79", stTodo: "#a8a7b3", stProg: "#6eaed9",
        stHalf: "#dcb363", stBlocked: "#e17371", stReview: "#de8fbd", stDone: "#67ba82", mStandup: "#6eaed9",
        mOneone: "#de8fbd", mSync: "#6ab4ae", mFocus: "#67ba82", nowLine: "#afa1e9", synKeyword: "#b8abed",
        synString: "#67ba82", synNumber: "#dcb363", synComment: "#9896a4", synType: "#6eaed9",
        synBuiltin: "#de8fbd", codeBg: "#16151f", code: "#a8a7b3", mention: "#6eaed9", ticket: "#a8a7b3",
        tag: "#de8fbd", math: "#dcb363", heading: "#b8abed", highlightBg: "#4ddcb363", mdLink: "#b8abed",
        mdCode: "#bfbec7", mdCodeBg: "#1e1d27", mdMention: "#6eaed9", mdTicket: "#b8abed", mdTag: "#de8fbd",
        mdMath: "#dcb363", mdHighlight: "#4ddcb363"
    }
};

// heap. ink: the Minimal recipe (neutral surfaces, translucent hairlines, a
// monochrome accent) in the brand's own colours. Navy-black
// surfaces and the mark's ink greys from design/brand-export, a monochrome
// accent like the logo, hairlines tinted with the ink, and the brand cyan
// kept for links, mentions and keywords.
var HEAP_INK = {
    id: "heap-ink", name: "heap. ink", base: "dark", contrast: "high", builtin: true,
    colors: {
        bg: "#0b0e13", bg2: "#080a0e", panel: "#0f1218", panel2: "#141820",
        panel3: "#1a1f29", border: "#14c6d0dc", borderStrong: "#26c6d0dc", text: "#e5ecf3",
        textMuted: "#a6b0bd", textDim: "#8a94a3", textOnAccent: "#0b0e13", textOnDanger: "#0b0e13",
        textOnBadge: "#0b0e13", accent: "#e8eef4", accentStrong: "#ffffff", accentSoft: "#1ac6d0dc",
        knob: "#a6b0bd", danger: "#e6624c", warning: "#fe9c3a", success: "#78be7a",
        info: "#32b2e7", toastBg: "#141820", toastBorder: "#1ac6d0dc", toastText: "#e5ecf3",
        scrim: "#99000000", p0: "#e6624c", p1: "#fe9c3a", p2: "#a6b0bd",
        p3: "#8a94a3", stBacklog: "#6f7888", stTodo: "#86a0bd", stProg: "#32b2e7",
        stHalf: "#d8c277", stBlocked: "#e6624c", stReview: "#bf94ec", stDone: "#78be7a",
        mStandup: "#32b2e7", mOneone: "#bf94ec", mSync: "#3bccdd", mFocus: "#78be7a",
        nowLine: "#e6624c", synKeyword: "#3bccdd", synString: "#78be7a", synNumber: "#d8c277",
        synComment: "#7d8797", synType: "#86a0bd", synBuiltin: "#e5ecf3", codeBg: "#080a0e",
        code: "#c6d0dc", mention: "#3bccdd", ticket: "#a6b0bd", tag: "#bf94ec",
        math: "#d8c277", heading: "#a6b0bd", highlightBg: "#4dd8c277", mdLink: "#3bccdd",
        mdCode: "#e5ecf3", mdCodeBg: "#141820", mdMention: "#3bccdd", mdTicket: "#e5ecf3",
        mdTag: "#bf94ec", mdMath: "#d8c277", mdHighlight: "#4dd8c277"
    }
};

// The colours the user can give a column, a label, a person or a profile.
// They are stored as data (a column keeps its colour whatever the theme), so
// every picker offers the same ten: one hue per family, then two greys. The
// first is what a new column, person or profile starts with.
var SWATCHES = ["#5cc2dd", "#5aa9e6", "#a4a4d6", "#c07acf", "#e6624c",
                "#e69854", "#dcb86b", "#6ec18a", "#9aa3b4", "#8a8e98"];

var PRESETS = [HEAP_DARK, HEAP_LIGHT, HEAP_INK, CRIMSON, GRAPHITE, OCHRE, FJORD, DUSK];

// Built-ins that were retired, and the one that replaces each, so a user who
// picked one lands on its nearest relative instead of the slot default.
var RETIRED = {
    "minimal-light": "heap-light", "minimal-dark": "crimson",
    "ash": "graphite", "stone": "ochre", "slate": "graphite", "sage": "fjord",
    "muted-mauve": "dusk", "moss-mono": "fjord", "nocturne": "dusk"
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

// The two groups the theme picker shows: high contrast (crisp text, strong
// signal colours) and low contrast (softer text and hairlines, for long
// sessions and dark rooms).
var CATEGORIES = ["high", "low"];

// Which group `t` belongs in. A built-in says so; a custom theme takes its
// source's group while it has one, else is measured: body text under 13:1 on
// the ground reads as low contrast.
function category(t, customThemes) {
    var seen = {};
    while (t && t.contrast !== "high" && t.contrast !== "low" && t.from && !seen[t.from]) {
        seen[t.from] = true;
        var from = builtin(t.from) || builtin(RETIRED[t.from]) || _custom(t.from, customThemes);
        if (!from) break;
        t = from;
    }
    if (!t) return "high";
    if (t.contrast === "high" || t.contrast === "low") return t.contrast;
    var c = t.colors || {};
    if (!isHex(c.text) || !isHex(c.bg)) return "high";
    return contrast(c.text, c.bg) >= 13 ? "high" : "low";
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
