.pragma library

// Small pure rules of the 0.8.0 keymap (keymap.md, APP-272/279), shared by
// Main, the menus and the lists. No state: the caller passes what it has.

// A bare key ("D", "Shift+G", "?") or a two-key sequence ("G, B"): KeyRouter's.
// A chord with Ctrl, Alt or Meta is a Qt Shortcut's.
function isRouterSequence(seq) {
    if (!seq) return false;
    return seq.indexOf(", ") >= 0 || !/(^|\+)(Ctrl|Alt|Meta)\+/.test(seq);
}

// "undo.alt" and "savedView.3.alt" are a second key for the action before
// the suffix.
function baseId(id) {
    return String(id).replace(/\.alt\d*$/, "");
}

// A second d on the same tasks within half a second is Vim's "dd" habit,
// not "take Done back" (keymap rule 6).
function isRepeatedDone(key, now, lastKey, lastAt) {
    return key.length > 0 && key === lastKey && now - lastAt >= 0 && now - lastAt < 500;
}

// Type-ahead in a menu or a drop-down (APP-279): the first row from `from`
// on (wrapping) whose label, or a word of it, starts with what was typed.
// -1 when none does.
function typeAheadMatch(labels, typed, from) {
    const q = String(typed || "").toLowerCase();
    const n = labels.length;
    if (q.length === 0 || n === 0) return -1;
    const start = Math.max(0, Math.min(n - 1, from || 0));
    for (let pass = 0; pass < 2; pass++) {
        for (let k = 0; k < n; k++) {
            const i = (start + k) % n;
            const label = String(labels[i] === undefined || labels[i] === null ? "" : labels[i]).toLowerCase();
            if (label.length === 0) continue;
            if (pass === 0 ? label.indexOf(q) === 0 : label.split(/[\s·\-—/()«»"]+/).some(w => w.indexOf(q) === 0))
                return i;
        }
    }
    return -1;
}

// The Latin keys a run of Cyrillic was typed on (ЙЦУКЕН → QWERTY): "л" is
// the K key. For finding a key by what the fingers pressed.
function latinOf(text) {
    const cyr = "йцукенгшщзхъфывапролджэячсмитьбюё";
    const lat = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`";
    let out = "";
    const s = String(text || "").toLowerCase();
    for (let i = 0; i < s.length; i++) {
        const k = cyr.indexOf(s[i]);
        out += k >= 0 ? lat[k] : s[i];
    }
    return out;
}

// The Latin letter a Cyrillic one is written with ("к" → "k"): for finding
// a key by its name said in Russian.
function translit(text) {
    const map = { "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z",
                  "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
                  "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c", "ч": "ch", "ш": "sh", "щ": "sch",
                  "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya" };
    let out = "";
    const s = String(text || "").toLowerCase();
    for (let i = 0; i < s.length; i++) out += map[s[i]] !== undefined ? map[s[i]] : s[i];
    return out;
}

// What a run of typed letters adds up to: a new letter within `resetMs` of
// the last one extends the run, a later one starts a new run.
function typeAheadBuffer(buffer, letter, now, lastAt, resetMs) {
    return (now - lastAt <= (resetMs || 1000) ? String(buffer || "") : "") + letter;
}
