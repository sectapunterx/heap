// The first-run tour (APP-169) — QML behaviour.
//
// The pure state machine (Tour.js), then the real WelcomePopup against a live
// AppController: four steps, all localized; Enter with text on the capture
// step saves a real task and stays, Enter on an empty line moves on, Esc
// skips; finishing or skipping marks the tour seen; step actions pause it.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp
import "../../qml/Tour.js" as Tour

TestCase {
    id: tc
    name: "WelcomeGuide"
    when: windowShown
    visible: true
    width: 640
    height: 560

    Item { id: host; anchors.fill: parent }

    function mk() {
        const o = createTemporaryQmlObject('import TodoCpp; WelcomePopup { }', host);
        verify(o !== null, "failed to instantiate WelcomePopup");
        return o;
    }

    // ── Tour.js ──────────────────────────────────────────────────────
    function test_machine_has_four_steps() {
        compare(Tour.STEPS.length, 4);
        compare(Tour.STEPS[0], "capture");
        compare(Tour.STEPS[3], "bring");
    }

    function test_machine_enter_saves_then_moves_on() {
        compare(Tour.onKey(0, "enter", "buy milk").action, "save");
        compare(Tour.onKey(0, "enter", "buy milk").step, 0, "saving stays on the capture step");
        compare(Tour.onKey(0, "enter", "   ").action, "next", "blank text is not a task");
        compare(Tour.onKey(0, "enter", "").step, 1);
        compare(Tour.onKey(1, "enter", "ignored off the capture step").action, "next");
        compare(Tour.onKey(3, "enter", "").action, "finish");
    }

    function test_machine_esc_and_arrows() {
        for (let s = 0; s < 4; s++) compare(Tour.onKey(s, "esc", "x").action, "skip");
        compare(Tour.onKey(0, "left", "").action, "none");
        compare(Tour.onKey(2, "left", "").step, 1);
        compare(Tour.onKey(3, "right", "").action, "none");
        compare(Tour.onKey(1, "right", "").step, 2);
        compare(Tour.onKey(1, "tab", "").action, "none");
    }

    // ── WelcomePopup ─────────────────────────────────────────────────
    function test_four_localized_steps() {
        const w = mk();
        compare(w.steps.length, Tour.STEPS.length);
        for (let i = 0; i < w.steps.length; ++i) {
            w.step = i;
            compare(w.cur.id, Tour.STEPS[i]);
            verify(I18n.t(w.cur.title) !== w.cur.title, "title translated at step " + i);
            verify(I18n.t(w.cur.desc) !== w.cur.desc, "desc translated at step " + i);
        }
    }

    function test_step_navigation() {
        const w = mk();
        w.step = 0;
        verify(!w.lastStep);
        w._next();
        compare(w.step, 1);
        w._back();
        compare(w.step, 0);
        w._back();
        compare(w.step, 0);
        w.step = w.steps.length - 1;
        verify(w.lastStep);
    }

    // The capture step saves exactly what was typed, as a real task.
    function test_capture_step_saves_a_real_task() {
        const w = mk();
        w.open();
        tryCompare(w, "opened", true);
        const field = findChild(w.contentItem, "welcome-capture-field");
        verify(field !== null);
        tryVerify(function () { return field.activeFocus; }, 1000, "the capture field has the keyboard");
        const title = "tour probe " + Date.now();
        field.text = title;
        keyClick(Qt.Key_Return);
        compare(w.step, 0, "saving stays on the step");
        compare(field.text, "", "the field clears for another");
        compare(w.captured[w.captured.length - 1], title);
        verify(w.lastCapturedId.length > 0);
        const saved = AppController.taskById(w.lastCapturedId);
        compare(saved.title, title, "the task was saved, exactly as typed");
        compare(saved.status, "todo");
        AppController.deleteTask(w.lastCapturedId);
        keyClick(Qt.Key_Return);   // empty line → next step
        compare(w.step, 1);
        w._finish();
    }

    function test_esc_skips_and_marks_seen() {
        const w = mk();
        w.open();
        tryCompare(w, "opened", true);
        keyClick(Qt.Key_Escape);
        tryCompare(w, "opened", false);
        compare(AppController.welcomeSeen, true);
        verify(!w.paused);
    }

    function test_finish_marks_seen() {
        const w = mk();
        w._finish();
        compare(AppController.welcomeSeen, true);
    }

    // "Bring your stuff" asks Main for each picker; nothing is imported here.
    function test_bring_step_routes_each_import() {
        const w = mk();
        const asked = [];
        w.openAction.connect(function (id) { asked.push(id); });
        w.step = 3;
        w.open();
        tryCompare(w, "opened", true);
        const names = ["welcome-bring-vault", "welcome-bring-profile", "welcome-bring-integrations"];
        for (let i = 0; i < names.length; i++) {
            if (!w.opened) { w.open(); tryCompare(w, "opened", true); }
            const b = findChild(w.contentItem, names[i]);
            verify(b !== null && b.visible, names[i]);
            b.clicked();
            verify(w.paused, "an action pauses the tour, it does not end it");
        }
        compare(asked.join(","), "vault-import,profile-import,integrations");
        w._finish();
    }

    function test_action_signals() {
        const w = mk();
        let action = "";
        let helpAnchor = "";
        w.openAction.connect(function (id) { action = id; });
        w.openHelp.connect(function (a) { helpAnchor = a; });
        w._doAction({ kind: "action", arg: "palette" });
        compare(action, "palette");
        w._learnMore("help-views");
        compare(helpAnchor, "help-views");
    }

    function test_action_pauses_not_finishes() {
        const w = mk();
        w.step = 2;
        w._doAction({ kind: "view", arg: "board" });
        verify(w.paused);
        compare(w.step, 2, "the step is kept so the tour resumes there");
        const w2 = mk();
        w2._learnMore("help-tasks");
        verify(w2.paused);
        w2._finish();
        verify(!w2.paused);
        AppController.currentView = "board";
    }
}
