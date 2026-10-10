pragma Singleton
import QtQuick
import TodoCpp

// The interface style of heap 2 (APP-275): "Насыщенный" (bold) or "Тихий"
// (quiet), each a set of switches that can also be flipped one by one — a set
// that matches neither is "custom". Screens read only these flags (and the
// Theme tokens that follow them), never "if quiet" by name.
//
// settings.appearance.style   "bold" | "quiet" — the base set
// settings.appearance.styleFlags   { flag: value } overrides on top of it
//
// Bold is the default for new installs and for an upgrade from 0.7.x (owner,
// 2026-10-09). Meeting / task icons are not a switch: without them a meeting
// and a task cannot be told apart.
QtObject {
    id: style

    // The two sets, flag by flag.
    readonly property var presets: ({
        "bold": {
            urgency: true,          // amber "now" / timer / P1, red P0 / today / blocked
            counters: true,         // counts beside sections and My views
            keyHints: true,         // key hints on screen (the bar, the selected card)
            chipFill: true,         // filled, coloured chips; quiet keeps the outline only
            factsLine: true,        // the grey facts line under the date on Today
            todayExtras: "open",    // "People to ping" / "No date" on Today: open | collapsed | hidden
            // Board cards (APP-281 A1): "detailed" adds the description's
            // first line, any priority, the branch / PR mark and the
            // checklist; "compact" is the title, the key and the date.
            cardDensity: "detailed"
        },
        "quiet": {
            urgency: false,
            counters: false,
            keyHints: false,
            chipFill: false,
            factsLine: true,
            todayExtras: "collapsed",
            cardDensity: "compact"
        }
    })
    readonly property var flagKeys: ["urgency", "counters", "keyHints", "chipFill", "factsLine", "todayExtras", "cardDensity"]
    readonly property string defaultStyle: "bold"

    readonly property var _settings: {
        const raw = AppController.appSettingsJson || "";
        if (!raw.length) return ({});
        try { return JSON.parse(raw); } catch (e) { return ({}); }
    }
    readonly property var _appearance: (_settings && _settings.appearance) || ({})

    // The set the flags start from, and the overrides on top of it.
    readonly property string base: _appearance.style === "quiet" ? "quiet" : (_appearance.style === "bold" ? "bold" : defaultStyle)
    readonly property var _overrides: _appearance.styleFlags && typeof _appearance.styleFlags === "object" ? _appearance.styleFlags : ({})

    function _flag(key) {
        const o = _overrides[key];
        const p = presets[base][key];
        if (o === undefined || o === null) return p;
        return typeof p === "boolean" ? !!o : String(o);
    }

    readonly property bool urgency: _flag("urgency")
    readonly property bool counters: _flag("counters")
    readonly property bool keyHints: _flag("keyHints")
    readonly property bool chipFill: _flag("chipFill")
    readonly property bool factsLine: _flag("factsLine")
    readonly property string todayExtras: {
        const v = _flag("todayExtras");
        return v === "collapsed" || v === "hidden" ? v : "open";
    }

    readonly property string cardDensity: _flag("cardDensity") === "compact" ? "compact" : "detailed"
    readonly property bool detailedCards: cardDensity === "detailed"

    // "bold" | "quiet" when the flags are exactly one of the sets, else "custom".
    readonly property string name: {
        const now = { urgency: urgency, counters: counters, keyHints: keyHints, chipFill: chipFill,
                      factsLine: factsLine, todayExtras: todayExtras, cardDensity: cardDensity };
        for (const n of ["bold", "quiet"]) {
            let same = true;
            for (const k of flagKeys)
                if (presets[n][k] !== now[k]) { same = false; break; }
            if (same) return n;
        }
        return "custom";
    }
    readonly property bool quiet: name === "quiet"

    function _write(appearancePatch, removeKeys) {
        const s = Object.assign({}, _settings);
        const a = Object.assign({}, s.appearance || {}, appearancePatch);
        for (const k of removeKeys || []) delete a[k];
        s.appearance = a;
        AppController.appSettingsJson = JSON.stringify(s);
    }

    // Switch to a whole set; every flag follows it.
    function apply(styleName) {
        if (styleName !== "bold" && styleName !== "quiet") return;
        _write({ style: styleName }, ["styleFlags"]);
    }

    // One switch on its own. A value equal to the set's own is dropped, so a
    // flag flipped back reads as the set again, not as "custom".
    function setFlag(key, value) {
        if (flagKeys.indexOf(key) < 0) return;
        const flags = Object.assign({}, _overrides);
        const own = presets[base][key];
        const v = typeof own === "boolean" ? !!value : String(value);
        if (v === own) delete flags[key]; else flags[key] = v;
        _write({ style: base, styleFlags: flags }, []);
    }

    // "Switch style" in the command line: bold ↔ quiet; custom goes to bold.
    function toggle() {
        apply(name === "bold" ? "quiet" : "bold");
    }
}
