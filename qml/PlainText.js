.pragma library

// A task description is markdown. Where it is shown as a one- or two-line
// preview — a board card, a timeline row — it should read as prose, not as
// "**Steps:** - [ ] build - [x] test" (audit TASKS-33 / TASKS-30).
//
// `max` (optional) cuts the result at that many characters with an ellipsis.
function plain(md, max) {
    let s = String(md || "")
        .replace(/```[\s\S]*?```/g, " ")
        .replace(/`([^`]*)`/g, "$1")
        .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
        .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
        .replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, (m, a, b) => b || a)
        .replace(/^\s{0,3}#{1,6}\s+/gm, "")
        .replace(/^\s*>\s?/gm, "")
        .replace(/^\s*(?:[-*+]|\d+[.)])\s+\[[ xX]\]\s*/gm, "")
        .replace(/^\s*(?:[-*+]|\d+[.)])\s+/gm, "")
        .replace(/(\*\*|__)(.*?)\1/g, "$2")
        .replace(/(^|[^*])\*([^*\n]+)\*/g, "$1$2")
        .replace(/~~(.*?)~~/g, "$1")
        .replace(/\s+/g, " ")
        .trim();
    if (max && s.length > max) s = s.substring(0, max).trim() + "…";
    return s;
}
