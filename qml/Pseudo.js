.pragma library

// The pseudo-locale (APP-189): every English string with its letters
// accented, 40 % longer and bracketed, so a run of the app shows at a
// glance which text is cut short, which is not translated (it stays plain)
// and which layout has a width that only fits English. A development
// language, not one for users: HEAP_LANG=pseudo turns it on.
//
// Placeholders (%1), markup (<b>, &amp;) and line breaks are left as they
// are, so .arg() and rich text keep working.

const ACCENTS = {
    a: "á", b: "ƀ", c: "ç", d: "ð", e: "é", f: "ƒ", g: "ĝ", h: "ĥ", i: "í", j: "ĵ",
    k: "ķ", l: "ĺ", n: "ñ", o: "ó", r: "ŕ", s: "š", t: "ţ", u: "ú", w: "ŵ", y: "ý", z: "ž",
    A: "Á", C: "Ç", D: "Ð", E: "É", G: "Ĝ", H: "Ĥ", I: "Í", J: "Ĵ", K: "Ķ", L: "Ĺ",
    N: "Ñ", O: "Ó", R: "Ŕ", S: "Š", T: "Ţ", U: "Ú", W: "Ŵ", Y: "Ý", Z: "Ž"
};

// How much longer than English a translation can run.
const GROWTH = 0.4;

// What is copied through untouched: %1…%9, a tag, an entity, a newline.
const KEEP = /(%\d|<[^>]*>|&[a-zA-Z#0-9]+;|\n)/;

function accent(s) {
    let out = "";
    for (let i = 0; i < s.length; i++) {
        const c = s[i];
        out += ACCENTS[c] !== undefined ? ACCENTS[c] : c;
    }
    return out;
}

function pseudo(s) {
    const text = String(s === undefined || s === null ? "" : s);
    if (text.length === 0) return text;
    const parts = text.split(KEEP);
    let visible = 0;
    let body = "";
    for (let i = 0; i < parts.length; i++) {
        const p = parts[i];
        if (p.length === 0) continue;
        if (KEEP.test(p)) { body += p; continue; }
        visible += p.length;
        body += accent(p);
    }
    // The padding reads as words, so a label wraps the way a longer
    // translation would rather than as one unbreakable run.
    const extra = Math.max(1, Math.ceil(visible * GROWTH) - 2);
    let pad = "";
    for (let i = 0; i < extra; i++) pad += (i > 0 && i % 6 === 0) ? " " : "~";
    return "[" + body + " " + pad + "]";
}
