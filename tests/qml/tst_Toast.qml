// The toast stack (audit UX-16, APP-225).
//
// One slot used to hold every notice, so a later toast replaced a pending
// "Undo" and the undo was gone; the bar had no width cap (1093px at 1100);
// and every toast from C++ arrived as "info", failures included.
// APP-225: on a big monitor the toasts were small, far from the eyes and
// gone before they were seen. Their time now stands still while they are
// hovered, focused or the window is in the background; they last by kind;
// a wide work area gets them in its bottom-right corner.
import QtQuick
import QtTest
import TodoCpp
import "../../qml/ToastTiming.js" as Timing

TestCase {
    id: tc
    name: "Toast"
    when: windowShown
    visible: true
    width: 1100
    height: 600

    property string savedSettings: ""

    Item { id: host; anchors.fill: parent }

    function initTestCase() { tc.savedSettings = AppController.appSettingsJson; }
    function cleanup() { AppController.appSettingsJson = tc.savedSettings; }

    // The window an offscreen test runs in may or may not count as active;
    // the timing tests say themselves whether the toasts can be seen.
    function make(extra) {
        const t = createTemporaryQmlObject(
            'import TodoCpp; Toast { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; '
            + (extra || "") + ' }', host);
        verify(t !== null);
        t.appVisible = true;
        t.hoverHeld = false;
        return t;
    }

    function cards(t) {
        const out = [];
        const walk = function (it) {
            if (!it) return;
            if (it.objectName === "toast-card") out.push(it);
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) walk(kids[i]);
        };
        walk(t);
        return out;
    }

    function child(root, name) {
        if (!root) return null;
        if (root.objectName === name) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = child(kids[i], name);
            if (r) return r;
        }
        return null;
    }

    function test_undo_toast_survives_later_toasts() {
        const t = make();
        let undone = 0;
        t.showWithAction("Deleted: A", "Undo", 10, function () { undone++; });
        t.show("Saved");
        t.show("Synced");
        t.show("Another thing");
        wait(0);
        let undo = null;
        for (const c of cards(t)) if (c.modelData.actionLabel === "Undo") undo = c;
        verify(undo !== null, "a later toast replaced the Undo toast");
        verify(t.count <= t.maxVisible);
        const ma = (function find(it) {
            if (it.cursorShape === Qt.PointingHandCursor && it.clicked !== undefined) return it;
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) { const r = find(kids[i]); if (r) return r; }
            return null;
        })(undo);
        mouseClick(ma);
        compare(undone, 1);
    }

    function test_action_toasts_queue_rather_than_replace() {
        const t = make();
        for (let i = 0; i < 4; i++) t.showWithAction("Deleted " + i, "Undo", 10, function () {});
        compare(t.count, t.maxVisible);
        compare(t._queue.length, 1, "the fourth waits for a slot");
        t.dismiss(t._items[0].id);
        compare(t.count, t.maxVisible);
        compare(t._queue.length, 0);
    }

    function test_width_is_capped_and_long_text_wraps() {
        const t = make();
        let longText = "";
        for (let i = 0; i < 60; i++) longText += "word" + i + " ";
        t.show(longText);
        wait(0);
        const c = cards(t)[0];
        verify(c.width <= Theme.toastMaxWidth, "toast is " + c.width + "px wide");
        verify(c.height > 3 * Theme.fsLg, "long text should wrap onto more lines");
    }

    function test_kind_tints_and_errors_stay_longer() {
        const t = make();
        t.show("Sync failed", "error");
        compare(t.kind, "error");
        verify(t._items[0].ms > Timing.duration("info", 0, false), "an error must stay up longer than a notice");
    }

    function test_plain_duplicate_refreshes_instead_of_stacking() {
        const t = make();
        t.show("Sync is running");
        t.show("Sync is running");
        compare(t.count, 1);
    }

    function test_toasts_expire() {
        const t = make();
        t._push({ id: 99, message: "brief", kind: "info", actionLabel: "", actionFn: null, ms: 50 });
        compare(t.count, 1);
        tryCompare(t, "count", 0, 1000);
    }

    // ── APP-225: durations ──────────────────────────────────────────────
    function test_durations_by_kind() {
        compare(Timing.duration("info", 0, false), 4000);
        compare(Timing.duration("success", 0, false), 4000);
        compare(Timing.duration("warning", 0, false), 5500);
        compare(Timing.duration("error", 0, false), 8000);
        compare(Timing.duration("info", 0, true), 8000, "an Undo stays at least 8 s");
        compare(Timing.duration("info", 5, true), 8000, "a caller's 5 s Undo is lifted to 8 s");
        compare(Timing.duration("info", 15, true), 15000, "a longer ask is kept");
        compare(Timing.duration("error", 3, true), 8000);
        const t = make();
        t.show("note");
        t.show("careful", "warning");
        t.showWithAction("Deleted", "Undo", 5, function () {});
        compare(t._items[0].ms, 4000);
        compare(t._items[1].ms, 5500);
        compare(t._items[2].ms, 8000);
    }

    // The clock itself, with `now` passed in.
    function test_timing_rules_are_pure() {
        const a = Timing.start({}, 1000, 0, false);
        compare(Timing.remaining(a, 400), 600);
        Timing.hold(a, 400);
        compare(Timing.remaining(a, 5000), 600, "held: time stands still");
        Timing.resume(a, 5000);
        compare(Timing.remaining(a, 5500), 100);
        const b = Timing.start({}, 1000, 0, true);
        compare(Timing.remaining(b, 99999), 1000, "shown while unseen: the countdown has not started");
        const s = Timing.sweep([a, b], 5600);
        compare(s.keep.length, 1);
        compare(s.expired, 1);
        compare(s.next, Infinity, "nothing left is counting down");
        verify(!Timing.corner(1100, 1200));
        verify(Timing.corner(1440, 1200));
    }

    // ── APP-225: the countdown waits for the user ───────────────────────
    function test_timer_pauses_while_hovered() {
        const t = make();
        t.hoverHeld = true;
        t._push({ id: 101, message: "hovered", kind: "info", actionLabel: "", actionFn: null, ms: 80 });
        verify(t.held);
        wait(300);
        compare(t.count, 1, "a hovered toast ran out");
        t.hoverHeld = false;
        tryCompare(t, "count", 0, 1000);
    }

    function test_timer_pauses_while_window_inactive() {
        const t = make();
        t._push({ id: 102, message: "running", kind: "info", actionLabel: "", actionFn: null, ms: 400 });
        t.appVisible = false;
        verify(t.held);
        const left = Timing.remaining(t._items[0], Date.now());
        wait(600);
        compare(t.count, 1, "a toast ran out behind another window");
        verify(Math.abs(Timing.remaining(t._items[0], Date.now()) - left) < 1, "time moved while held");
        t.appVisible = true;
        tryCompare(t, "count", 0, 1500);
    }

    function test_shown_while_minimized_starts_counting_when_seen() {
        const t = make();
        t.appVisible = false;
        t._push({ id: 103, message: "while away", kind: "info", actionLabel: "", actionFn: null, ms: 80 });
        wait(300);
        compare(t.count, 1);
        compare(Timing.remaining(t._items[0], Date.now()), 80);
        t.appVisible = true;
        tryCompare(t, "count", 0, 1000);
    }

    function test_timer_pauses_while_action_focused() {
        const t = make();
        t.showWithAction("Deleted", "Undo", 0, function () {});
        let act = null;
        tryVerify(function () { act = child(t, "toast-action"); return act !== null; }, 1000);
        act.forceActiveFocus();
        tryCompare(t, "focusInside", true);
        verify(t.held);
        verify(t._items[0].since < 0, "the countdown kept going with the keyboard on the toast");
        act.focus = false;
        host.forceActiveFocus();
        tryCompare(t, "held", false);
        verify(t._items[0].since >= 0);
    }

    function test_app_visible_follows_the_window() {
        const t = createTemporaryQmlObject('import TodoCpp; Toast {}', host);
        compare(t.appVisible, t.Window.active);
    }

    // ── APP-225: where the stack sits ───────────────────────────────────
    function test_narrow_area_keeps_bottom_centre() {
        const t = createTemporaryQmlObject('import TodoCpp; Toast { width: 1000; areaWidth: 1000; anchors.bottom: parent.bottom }', host);
        t.appVisible = true;
        t.show("centred");
        wait(0);
        verify(!t.wide);
        const st = child(t, "toast-stack");
        verify(Math.abs(st.x + st.width / 2 - t.width / 2) <= 1, "stack at " + st.x);
    }

    function test_wide_area_puts_the_stack_bottom_right() {
        const w = Theme.toastWideFrom + 300;
        const t = createTemporaryQmlObject('import TodoCpp; Toast { width: ' + w + '; areaWidth: ' + w + '; anchors.bottom: parent.bottom }', host);
        t.appVisible = true;
        t.show("short");
        t.show("a somewhat longer second notice", "warning");
        wait(0);
        verify(t.wide);
        const st = child(t, "toast-stack");
        compare(st.x + st.width, w - Theme.sp3xl);
        for (const c of cards(t)) {
            compare(c.x + c.width, st.width, "every card is flush right");
            verify(c.width <= Theme.toastMaxWidth);
        }
    }

    // ── APP-225: how it looks and arrives ───────────────────────────────
    function test_kind_icon_and_accent_bar() {
        const t = make();
        t.show("note");
        t.show("broke", "error");
        wait(0);
        const cs = cards(t);
        compare(cs.length, 2);
        verify(child(cs[0], "toast-kind-icon") !== null);
        verify(!child(cs[0], "toast-accent").visible, "a notice has no accent bar");
        verify(child(cs[1], "toast-accent").visible, "an error has the accent bar");
        compare(child(cs[1], "toast-message").font.pixelSize, Theme.fsLg);
    }

    function test_new_toast_slides_in_rebuilt_ones_do_not() {
        AppController.appSettingsJson = JSON.stringify({ appearance: { reducedMotion: false } });
        compare(Theme.reducedMotion, false);
        const t = make();
        t.show("first");
        wait(0);
        let c = cards(t)[0];
        verify(c.entering);
        verify(c.transform[0].y > 0 || c.opacity < 1, "a new toast appeared without its entrance");
        tryCompare(c.transform[0], "y", 0, 1000);
        t.show("second");
        wait(0);
        const cs = cards(t);
        compare(cs.length, 2);
        const first = cs.filter(k => k.modelData.message === "first")[0];
        const second = cs.filter(k => k.modelData.message === "second")[0];
        // Whether the Repeater kept the first card or rebuilt it, it must
        // stand still: no second slide, no fade.
        compare(first.transform[0].y, 0, "the first toast played its entrance again");
        compare(first.opacity, 1);
        verify(second.entering);
        tryVerify(function () { return first.y < second.y; }, 1000, "the newest toast is at the bottom");
    }

    function test_reduced_motion_only_appears() {
        AppController.appSettingsJson = JSON.stringify({ appearance: { reducedMotion: true } });
        compare(Theme.reducedMotion, true);
        const t = make();
        t.show("broke", "error");
        wait(0);
        const c = cards(t)[0];
        compare(c.transform[0].y, 0, "it moved with Reduce motion on");
        compare(c.opacity, 1);
        compare(child(c, "toast-pulse").opacity, 0, "the border pulsed with Reduce motion on");
    }
}
