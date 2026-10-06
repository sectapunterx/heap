.pragma library

// The first-run tour (APP-169) as a pure state machine, so the keyboard
// contract is testable without the popup: four steps, Enter moves on, Esc
// skips, ←/→ step back and forth. On the capture step Enter with text saves
// that text as a task and stays, so a second one can follow; Enter on an
// empty line moves on.

var STEPS = ["capture", "views", "keys", "bring"];

// key: "enter" | "esc" | "left" | "right". Returns { action, step }:
//   action "save"   → save `captureText` as a task, stay on `step`
//          "next" / "back" → go to `step`
//          "finish" → the last step's Enter: the tour is done
//          "skip"   → Esc: the tour is dismissed (also "done", never re-shown)
//          "none"   → nothing to do
function onKey(step, key, captureText) {
    var last = STEPS.length - 1;
    var s = Math.max(0, Math.min(last, step | 0));
    if (key === "esc") return { action: "skip", step: s };
    if (key === "enter") {
        if (STEPS[s] === "capture" && String(captureText || "").trim().length > 0)
            return { action: "save", step: s };
        if (s >= last) return { action: "finish", step: s };
        return { action: "next", step: s + 1 };
    }
    if (key === "left") return s > 0 ? { action: "back", step: s - 1 } : { action: "none", step: s };
    if (key === "right") return s < last ? { action: "next", step: s + 1 } : { action: "none", step: s };
    return { action: "none", step: s };
}
