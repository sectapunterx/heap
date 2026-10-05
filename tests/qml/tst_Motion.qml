// Micro-motions and empty states (APP-167): the pure timing rules in
// Motion.js, the check mark a card plays when its task is marked done, and
// the EmptyState drawing.
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

    function test_just_completed_window() {
        const now = new Date(2026, 9, 6, 12, 0, 0);
        const at = (ms) => new Date(now.getTime() - ms);
        verify(Motion.justCompleted("done", at(0), now));
        verify(Motion.justCompleted("done", at(Motion.DONE_WINDOW_MS), now));
        verify(!Motion.justCompleted("done", at(Motion.DONE_WINDOW_MS + 1), now), "too long ago");
        verify(!Motion.justCompleted("todo", at(10), now), "not done");
        verify(!Motion.justCompleted("done", undefined, now), "no change time");
        verify(!Motion.justCompleted("done", new Date(NaN), now), "an invalid date");
        verify(!Motion.justCompleted("done", new Date(now.getTime() + 5000), now), "a clock that went back");
        verify(Motion.justCompleted("done", at(200).toISOString(), now), "an ISO string");
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
        verify(Theme.durFast <= Theme.durBase && Theme.durBase <= Theme.durSlow);
        verify(Theme.durFast <= 150, "feedback stays under 150 ms");
        compare(Theme.motion, Theme.reducedMotion ? 0 : 1);
        if (Theme.reducedMotion) compare(Theme.durBase, 0);
    }

    function test_card_plays_check_mark_when_done() {
        const card = createTemporaryQmlObject(
            'import TodoCpp; TaskCard { width: 260; task: ({ id: "MOT-1", title: "t", status: "todo", priority: "P2" }) }', host);
        verify(card !== null);
        const mark = findChild(card, "tc-done-mark");
        verify(mark !== null);
        compare(mark.visible, false, "nothing on a card that is not done");
        card.task = ({ id: "MOT-1", title: "t", status: "done", priority: "P2" });
        if (Theme.motion > 0) {
            tryVerify(function () { return mark.visible; }, 1000, "the check mark shows");
            tryVerify(function () { return !mark.visible; }, 2000, "and fades");
        } else {
            wait(50);
            compare(mark.visible, false, "reduced motion: no check mark");
        }
    }

    function test_card_built_for_a_task_just_done_plays_too() {
        if (Theme.motion === 0) skip("reduced motion");
        const card = createTemporaryQmlObject(
            'import TodoCpp; TaskCard { width: 260; task: ({ id: "MOT-2", title: "t", status: "done", priority: "P2", statusChangedAt: new Date() }) }', host);
        const mark = findChild(card, "tc-done-mark");
        tryVerify(function () { return mark.visible; }, 1000);
        const old = createTemporaryQmlObject(
            'import TodoCpp; TaskCard { width: 260; task: ({ id: "MOT-3", title: "t", status: "done", priority: "P2", statusChangedAt: new Date(2020, 0, 1) }) }', host);
        wait(100);
        compare(findChild(old, "tc-done-mark").visible, false, "a card done long ago stays quiet");
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
