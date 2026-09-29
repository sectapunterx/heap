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
// (Qt.lighter/darker of the Brand tokens) are baked in byte for byte. The one
// deliberate change: code was coloured three different ways (snippets, the
// notes editor, rendered code blocks); all three now use the syn* tokens,
// which follow what snippets used.
var HEAP_DARK = {
    id: "heap-dark", name: "heap. dark", base: "dark", builtin: true,
    colors: {
        bg: "#0b0e13", bg2: "#11151c", panel: "#14181f", panel2: "#1a1f29", panel3: "#1f2530",
        border: "#262d39", borderStrong: "#313a4a",
        text: "#e5ecf3", textMuted: "#8a94a3", textDim: "#808a9a",
        textOnAccent: "#06121a", textOnDanger: "#0b0b0f", textOnBadge: "#ffffff",
        accent: "#3bccdd", accentStrong: "#4aecff", accentSoft: "#2e3bccdd", knob: "#ffffff",
        danger: "#e6624c", warning: "#fe9c3a", success: "#78be7a", info: "#5aa3e6",
        toastBg: "#1f2530", toastBorder: "#313a4a", toastText: "#e5ecf3",
        scrim: "#8c000000",
        p0: "#e6624c", p1: "#fe9c3a", p2: "#d8c277", p3: "#7d9bc7",
        stBacklog: "#8a8e98", stTodo: "#86a0bd", stProg: "#32b2e7", stHalf: "#dcb86b",
        stBlocked: "#e6624c", stReview: "#bf94ec", stDone: "#78be7a",
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
        text: "#11151c", textMuted: "#5f6878", textDim: "#656e7d",
        textOnAccent: "#06121a", textOnDanger: "#0b0b0f", textOnBadge: "#ffffff",
        accent: "#178ea0", accentStrong: "#137888", accentSoft: "#1f178ea0", knob: "#ffffff",
        danger: "#c34a36", warning: "#bd7530", success: "#3e8a5d", info: "#1f6fb0",
        toastBg: "#f1f1f1", toastBorder: "#b8bdc5", toastText: "#11151c",
        scrim: "#8c000000",
        p0: "#c34a36", p1: "#bd7530", p2: "#9a8237", p3: "#496a91",
        stBacklog: "#7a808c", stTodo: "#5a6371", stProg: "#1f6fb0", stHalf: "#9a7a2b",
        stBlocked: "#c34a36", stReview: "#7a3e91", stDone: "#3e8a5d",
        mStandup: "#1f6fb0", mOneone: "#7a3e91", mSync: "#317e74", mFocus: "#3e8a5d", nowLine: "#c34a36",
        codeBg: "#eaecee", code: "#9a8237", synKeyword: "#178ea0", synString: "#9a8237",
        synNumber: "#3e8a5d", synComment: "#656e7d", synType: "#317e74", synBuiltin: "#7a3e91",
        mention: "#1f6fb0", ticket: "#9a8237", tag: "#7a3e91", math: "#7a3e91",
        heading: "#b58ad7", highlightBg: "#1f178ea0",
        mdLink: "#178ea0", mdCode: "#11151c", mdCodeBg: "#f8f8f8", mdMention: "#1f6fb0",
        mdTicket: "#178ea0", mdTag: "#7a3e91", mdMath: "#9a8237", mdHighlight: "#1f178ea0"
    }
};

var PRESETS = [HEAP_DARK, HEAP_LIGHT];

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
