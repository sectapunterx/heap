// ThinScrollBar (translucent 6px thumb, fades when idle): load-smoke, the
// styling contract (AsNeeded policy, minimumSize, bare background), the
// fade-opacity binding, and real attached-to-Flickable tracking.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ThinScrollBar"
    when: windowShown
    visible: true
    width: 400
    height: 400

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // Smoke: a broken Theme reference or a renamed property would make
    // createTemporaryQmlObject return null. Also pins the two knobs every
    // caller relies on: AsNeeded (auto-hide) and the minimum thumb size.
    function test_smoke_load() {
        const sb = make('import TodoCpp; ThinScrollBar { }');
        compare(sb.policy, ScrollBar.AsNeeded, "callers rely on the auto-hide policy");
        fuzzyCompare(sb.minimumSize, 0.06, 0.001);
    }

    // The design-prototype thumb: 6px rounded rectangle, idle color is
    // Theme.text at 0.18 alpha, and the track is a bare Item (translucent
    // treatment — no background chrome).
    function test_thumb_visuals_and_bare_background() {
        const sb = make('import TodoCpp; ThinScrollBar { height: 120 }');
        // Park the cursor away from the bar so hovered/pressed are
        // deterministically false (a stray hover would pick the 0.30 color).
        mouseMove(tc, 350, 350);
        verify(!sb.pressed, "standalone bar must not start pressed");
        verify(!sb.hovered, "cursor parked away — bar must not be hovered");

        compare(sb.contentItem.implicitWidth, 6);
        compare(sb.contentItem.implicitHeight, 6);
        compare(sb.contentItem.radius, 3);

        const c = sb.contentItem.color;
        fuzzyCompare(c.a, 0.18, 0.01);
        fuzzyCompare(c.r, Theme.text.r, 0.01);
        fuzzyCompare(c.g, Theme.text.g, 0.01);
        fuzzyCompare(c.b, Theme.text.b, 0.01);

        verify(sb.background !== null, "background must exist (empty Item)");
        compare(sb.background.implicitWidth, 0);
        compare(sb.background.implicitHeight, 0);
    }

    // Fade contract ("fades when idle"): thumb opacity is 0 when idle, 1 when
    // the bar is active or policy is AlwaysOn. The opacity change runs through
    // a Behavior/NumberAnimation, so every step uses tryCompare — no bare
    // wait() on animation timing (duration also collapses to 0 under the
    // reduced-motion setting).
    function test_fade_when_idle_contract() {
        const sb = make('import TodoCpp; ThinScrollBar { height: 120 }');
        mouseMove(tc, 350, 350);  // ensure hovered is false
        sb.active = false;
        tryCompare(sb.contentItem, "opacity", 0.0);

        sb.policy = ScrollBar.AlwaysOn;
        tryCompare(sb.contentItem, "opacity", 1.0);

        sb.policy = ScrollBar.AsNeeded;
        tryCompare(sb.contentItem, "opacity", 0.0);

        sb.active = true;
        tryCompare(sb.contentItem, "opacity", 1.0);
    }

    // Real usage (DocsView/NotesView/KanbanBoard/SettingsView all attach it as
    // ScrollBar.vertical on a scrollable): size mirrors the viewport/content
    // ratio, position tracks contentY, and increase() drives the flickable.
    function test_attached_flickable_tracking() {
        const flick = make('import QtQuick; import QtQuick.Controls; import TodoCpp; '
            + 'Flickable { property alias bar: tsb; width: 200; height: 200; '
            + 'contentWidth: 200; contentHeight: 2000; '
            + 'ScrollBar.vertical: ThinScrollBar { id: tsb } }');
        const bar = flick.bar;
        verify(bar !== null, "attached ThinScrollBar not reachable via alias");

        // 200/2000 viewport ratio; layout is asynchronous → tryVerify.
        tryVerify(function() { return Math.abs(bar.size - 0.1) < 0.02; }, 5000,
                  "size must mirror the viewport/content ratio");
        tryVerify(function() { return bar.visible; }, 5000,
                  "overflowing content must show the AsNeeded bar");

        flick.contentY = 900;  // 45% of the 2000px content
        tryVerify(function() { return Math.abs(bar.position - 0.45) < 0.02; }, 5000,
                  "position must track contentY");

        // stepSize is unset → increase() steps by 0.1 → contentY 900 + 200.
        bar.increase();
        tryVerify(function() { return Math.abs(flick.contentY - 1100) < 30; }, 5000,
                  "increase() must scroll the attached flickable");
    }

    // AsNeeded semantics the component opts into. Qt's Basic ScrollBar keeps
    // `visible` true for every policy but AlwaysOff (visible: policy !==
    // AlwaysOff) — the auto-hide is expressed through `size`, which the attach
    // clamps to [0,1]: size == 1 means the content fits (nothing to scroll and
    // the thumb stays faded), size < 1 means it overflows and the thumb shows.
    function test_asneeded_size_reflects_overflow() {
        const flick = make('import QtQuick; import QtQuick.Controls; import TodoCpp; '
            + 'Flickable { property alias bar: tsb; width: 200; height: 200; '
            + 'contentWidth: 200; contentHeight: 100; '
            + 'ScrollBar.vertical: ThinScrollBar { id: tsb } }');
        const bar = flick.bar;
        verify(bar !== null, "attached ThinScrollBar not reachable via alias");

        // Content fits (100 < 200) → size clamps to 1.0, nothing to scroll.
        tryVerify(function() { return bar.size >= 1.0 - 0.001; }, 5000,
                  "content fitting the viewport must clamp size to 1.0");

        // Overflow → size drops below 1.0 and the thumb becomes scrollable.
        flick.contentHeight = 2000;
        tryVerify(function() { return bar.size < 1.0; }, 5000,
                  "overflowing content must drop size below 1.0");
    }
}
