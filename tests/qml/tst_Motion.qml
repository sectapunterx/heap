// Micro-motions and empty states (APP-167): the pure rules in Motion.js,
// when a closed task plays the done moment (APP-176), and the EmptyState
// drawing.
import QtQuick
import QtTest
import TodoCpp
import "../../qml/Motion.js" as Motion

TestCase {
    id: tc
    name: "Motion"
    when: windowShown
    visible: true
    width: 400
    height: 400

    Item { id: host; anchors.fill: parent }

    // APP-176: closing one task plays the done moment; a bulk move, a move
    // inside Done and "Reduce motion" do not.
    function test_should_stack_only_for_one_card_into_done_with_motion() {
        verify(Motion.shouldStack(1, "prog", "done", 1));
        verify(!Motion.shouldStack(2, "prog", "done", 1), "a bulk move");
        verify(!Motion.shouldStack(0, "prog", "done", 1), "nothing moved");
        verify(!Motion.shouldStack(1, "prog", "review", 1), "not into Done");
        verify(!Motion.shouldStack(1, "done", "done", 1), "already done");
        verify(!Motion.shouldStack(1, "prog", "done", 0), "reduced motion");
    }

    function test_settle_offset_follows_motion() {
        const on = Motion.settleFrom(130, 90, 100, 60, 1);
        compare(on.x, 30);
        compare(on.y, 30);
        const off = Motion.settleFrom(130, 90, 100, 60, 0);
        compare(off.x, 0, "reduced motion: no spring");
        compare(off.y, 0);
    }

    function test_theme_duration_tokens() {
        verify(Theme.durTap <= Theme.durPop && Theme.durPop <= Theme.durMove);
        verify(Theme.durTap <= 150, "feedback stays under 150 ms");
        compare(Theme.durPopOut, Math.floor(Theme.durPop / 2), "leaving takes half the time");
        compare(Theme.motion, Theme.reducedMotion ? 0 : 1);
        if (Theme.reducedMotion) compare(Theme.durMove, 0);
    }

    // The stack replaced the check mark a card played when done (APP-167).
    function test_card_no_longer_plays_a_check_mark() {
        const card = createTemporaryQmlObject(
            'import TodoCpp; TaskCard { width: 260; task: ({ id: "MOT-1", title: "t", status: "done", priority: "P2", statusChangedAt: new Date() }) }', host);
        verify(card !== null);
        compare(findChild(card, "tc-done-mark"), null);
    }

    function test_stack_tokens() {
        const saved = AppController.appSettingsJson;
        AppController.appSettingsJson = JSON.stringify({ appearance: { reducedMotion: false } });
        const on = [Theme.durStack, Theme.durStackFold, Theme.durStackFly];
        AppController.appSettingsJson = JSON.stringify({ appearance: { reducedMotion: true } });
        const off = [Theme.durStack, Theme.durStackFold, Theme.durStackFly];
        AppController.appSettingsJson = saved;
        compare(on[0], 360);
        compare(on[1] + on[2], on[0], "fold and flight make the whole move");
        verify(on[1] < on[2], "the fold is the shorter half");
        compare(off, [0, 0, 0]);
    }

    function test_empty_state_draws_icon_title_and_line() {
        const e = createTemporaryQmlObject(
            'import TodoCpp; EmptyState { width: 300; icon: "heap-05-archive"; title: "Archive is empty"; line: "Archived cards land here." }', host);
        verify(e !== null);
        const icon = findChild(e, "empty-state-icon");
        verify(icon.visible);
        compare(String(icon.source), "qrc:/brand/icons/heap-05-archive.svg");
        compare(findChild(e, "empty-state-title").text, "Archive is empty");
        compare(findChild(e, "empty-state-line").text, "Archived cards land here.");
        const bare = createTemporaryQmlObject('import TodoCpp; EmptyState { width: 300; title: "Nothing" }', host);
        compare(findChild(bare, "empty-state-icon").visible, false);
        compare(findChild(bare, "empty-state-line").visible, false);
    }
}
