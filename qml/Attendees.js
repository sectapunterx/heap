.pragma library

// Attendee-field helpers for the event editor. The field is a free-typed,
// comma-separated list of names; these find the name being typed, offer
// contacts for it and splice a pick back in. Kept free of QML so the rules are
// testable on plain strings.

// The comma-separated entry the caret sits in: its [start, end) span and the
// trimmed text typed so far (only up to the caret — what is right of it is not
// part of the query).
function tokenAt(text, caret) {
    text = text || "";
    if (caret < 0 || caret > text.length) caret = text.length;
    const start = text.lastIndexOf(",", caret - 1) + 1;
    let end = text.indexOf(",", caret);
    if (end < 0) end = text.length;
    return { start: start, end: end, query: text.substring(start, caret).trim() };
}

// Names already in the field, lower-cased, ignoring the entry being edited.
function listed(text, skipStart) {
    const out = [];
    let pos = 0;
    const parts = (text || "").split(",");
    for (let i = 0; i < parts.length; ++i) {
        const name = parts[i].trim().toLowerCase();
        if (pos !== skipStart && name.length > 0) out.push(name);
        pos += parts[i].length + 1;
    }
    return out;
}

// Candidates (maps with name / role / handle, as AppController.pingCandidates
// returns them) matching `query`: a name or handle starting with it ranks
// before one merely containing it. The same human can appear twice (a contact
// and a Person of the same name), and someone already in the field is not
// offered again.
function suggest(candidates, query, taken, max) {
    const q = (query || "").toLowerCase();
    const seen = {};
    for (let i = 0; i < (taken || []).length; ++i) seen[taken[i]] = true;
    const head = [], rest = [];
    for (let i = 0; i < (candidates || []).length; ++i) {
        const c = candidates[i];
        const name = String(c.name || "").trim();
        const key = name.toLowerCase();
        if (key.length === 0 || seen[key]) continue;
        const handle = String(c.handle || "").replace(/^@+/, "").toLowerCase();
        const words = key.split(/\s+/);
        let prefix = q.length === 0 || handle.indexOf(q) === 0;
        for (let w = 0; !prefix && w < words.length; ++w)
            if (words[w].indexOf(q) === 0) prefix = true;
        if (prefix) head.push(c);
        else if (key.indexOf(q) >= 0 || handle.indexOf(q) >= 0) rest.push(c);
        else continue;
        seen[key] = true;
    }
    return head.concat(rest).slice(0, max > 0 ? max : 6);
}

// `text` with the entry at `tok` replaced by `name`, followed by ", " so the
// next name can be typed straight away. Returns { text, caret }.
function apply(text, tok, name) {
    text = text || "";
    const before = text.substring(0, tok.start).replace(/\s+$/, "");
    const after = text.substring(tok.end).replace(/^,?\s*/, "");
    const lead = before.length > 0 ? before + " " : "";
    const head = lead + name + ", ";
    return { text: head + after, caret: head.length };
}
