.pragma library

// The second press of a two-step button (Restore this version, Reset all,
// Delete the files…) has to be a second decision. The armed state took the
// second click of a double-click, so a double-click restored a snapshot at
// once (IDIOT-SHELL-5). A confirming press that comes this soon after arming
// is ignored; the button stays armed.
var MIN_GAP_MS = 600;

// Whether a confirming press now is too close to the one that armed it.
function tooSoon(armedAt) {
    return Date.now() - armedAt < MIN_GAP_MS;
}
