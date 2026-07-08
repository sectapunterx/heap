// Interactive welcome guide (stepped carousel) — QML behavior.
//
// Drives the real WelcomePopup from the TodoCpp module against a live
// AppController: step navigation, localized copy for every step, that finishing
// marks the guide seen, and that per-step actions route through the decoupled
// openAction / openHelp signals. Headless under offscreen QPA + Basic style.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "WelcomeGuide"
    when: windowShown
    visible: true
    width: 640
    height: 520

    Item { id: host; anchors.fill: parent }

    function mk() {
        const o = createTemporaryQmlObject('import TodoCpp; WelcomePopup { }', host);
        verify(o !== null, "failed to instantiate WelcomePopup");
        return o;
    }

    // It is a multi-step carousel now, not the old single-panel popup.
    function test_has_multiple_steps() {
        const w = mk();
        verify(w.steps.length >= 5, "guide should have several steps");
    }

    // Next advances, Back returns and is clamped, lastStep tracks the end.
    function test_step_navigation() {
        const w = mk();
        w.step = 0;
        verify(!w.lastStep);
        w._next();
        compare(w.step, 1);
        w._back();
        compare(w.step, 0);
        w._back();               // clamped at the first step
        compare(w.step, 0);
        w.step = w.steps.length - 1;
        verify(w.lastStep);      // Next now finishes instead of advancing
    }

    // Every step resolves a non-empty, actually-translated title + description.
    function test_steps_localized() {
        const w = mk();
        for (let i = 0; i < w.steps.length; ++i) {
            w.step = i;
            verify(I18n.t(w.cur.title).length > 0, "title key for step " + i);
            verify(I18n.t(w.cur.desc).length > 0, "desc key for step " + i);
            verify(I18n.t(w.cur.title) !== w.cur.title,
                   "title should be translated, not the raw key, at step " + i);
        }
    }

    // Finishing / skipping the guide marks it seen so it never auto-shows again.
    function test_finish_marks_seen() {
        const w = mk();
        w._finish();
        compare(AppController.welcomeSeen, true);
    }

    // A step's "open →" routes through openAction, "Learn more →" through
    // openHelp — the popup stays decoupled from the objects Main owns.
    function test_action_signals() {
        const w = mk();
        let action = "";
        let helpAnchor = "";
        w.openAction.connect(function(id) { action = id; });
        w.openHelp.connect(function(a) { helpAnchor = a; });
        w._doAction({ kind: "action", arg: "palette" });
        compare(action, "palette");
        w._learnMore("help-views");
        compare(helpAnchor, "help-views");
    }
}
