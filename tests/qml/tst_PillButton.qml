// PillButton (qml/PillButton.qml): smoke-load, default flags/paddings, the
// neutral / primary / danger styling contract against the live Theme singleton,
// text passthrough, and click → clicked() incl. the enabled guard.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "PillButton"
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

    // Park the synthetic cursor away from the (top-left) button under test so
    // the hovered branch of the style bindings is off deterministically.
    function parkCursor() {
        mouseMove(host, host.width - 2, host.height - 2);
    }

    // Smoke: instantiates against the live TodoCpp module (Theme resolves).
    function test_smoke_load() {
        const b = make('import TodoCpp; PillButton { }');
        verify(b !== null);
    }

    // Both style flags default to off; pill paddings are fixed.
    function test_default_flags_and_padding() {
        const b = make('import TodoCpp; PillButton { text: "ok" }');
        compare(b.primary, false);
        compare(b.danger, false);
        compare(b.padding, 8);
        compare(b.leftPadding, 12);
        compare(b.rightPadding, 12);
    }

    // contentItem mirrors the button's text, initially and on change.
    function test_text_passthrough() {
        const b = make('import TodoCpp; PillButton { text: "Save" }');
        compare(b.contentItem.text, "Save");
        b.text = "Create";
        compare(b.contentItem.text, "Create");
    }

    // Neutral (default) variant: panel2 fill, Theme.border line, Theme.text
    // label at Medium weight.
    function test_neutral_style() {
        const b = make('import TodoCpp; PillButton { text: "n"; width: 120; height: 32 }');
        parkCursor();
        tryCompare(b, "hovered", false);
        verify(Qt.colorEqual(b.background.color, Theme.panel2), "neutral fill must be panel2");
        verify(Qt.colorEqual(b.background.border.color, Theme.border), "neutral border must be Theme.border");
        compare(b.background.border.width, 1);
        compare(b.background.radius, 6);
        verify(Qt.colorEqual(b.contentItem.color, Theme.text), "neutral label must be Theme.text");
        compare(b.contentItem.font.weight, Font.Medium);
        compare(b.contentItem.font.pixelSize, 12);
    }

    // Primary variant: accent fill, no border, fixed dark label at DemiBold —
    // what every "Save"/"Create" caller (EventEditor, DocsEditor, …) relies on.
    function test_primary_style() {
        const b = make('import TodoCpp; PillButton { text: "p"; primary: true }');
        verify(Qt.colorEqual(b.background.color, Theme.accent), "primary fill must be Theme.accent");
        verify(Qt.colorEqual(b.background.border.color, "#00000000"), "primary border must be transparent");
        verify(Qt.colorEqual(b.contentItem.color, "#06121a"), "primary label is the fixed dark ink");
        compare(b.contentItem.font.weight, Font.DemiBold);
    }

    // Danger variant: p0-tinted fill/border with a p0 label — the "Delete"
    // buttons (DocsEditor, EventEditor, PersonEditor, SelectionBar) contract.
    function test_danger_style() {
        const b = make('import TodoCpp; PillButton { text: "d"; danger: true }');
        verify(Qt.colorEqual(b.background.color, Theme.withAlpha(Theme.p0, 0.12)), "danger fill must be p0 @ 0.12");
        verify(Qt.colorEqual(b.background.border.color, Theme.withAlpha(Theme.p0, 0.4)), "danger border must be p0 @ 0.4");
        verify(Qt.colorEqual(b.contentItem.color, Theme.p0), "danger label must be Theme.p0");
        compare(b.contentItem.font.weight, Font.Medium);
    }

    // Precedence pin: primary wins over danger in every ternary chain
    // (background, border, label) when both flags are set.
    function test_primary_precedes_danger() {
        const b = make('import TodoCpp; PillButton { text: "pd"; primary: true; danger: true }');
        verify(Qt.colorEqual(b.background.color, Theme.accent), "primary must win the fill");
        verify(Qt.colorEqual(b.background.border.color, "#00000000"), "primary must win the border");
        verify(Qt.colorEqual(b.contentItem.color, "#06121a"), "primary must win the label");
    }

    // Flags are live bindings, not one-shot styling: flipping them at runtime
    // restyles the pill both ways.
    function test_runtime_flag_flip() {
        const b = make('import TodoCpp; PillButton { text: "flip"; width: 120; height: 32 }');
        parkCursor();
        b.primary = true;
        verify(Qt.colorEqual(b.background.color, Theme.accent), "flip to primary must restyle");
        b.primary = false;
        b.danger = true;
        verify(Qt.colorEqual(b.contentItem.color, Theme.p0), "flip to danger must restyle");
        b.danger = false;
        tryCompare(b, "hovered", false);
        verify(Qt.colorEqual(b.background.color, Theme.panel2), "flip back must restore the neutral fill");
    }

    // Hover restyle (panel3 fill + strong border) is intentionally not tested:
    // the offscreen QPA platform used by the suite does not synthesise a hover
    // enter, so `hovered` never flips true and the branch is unreachable here.
    // The neutral (non-hover) styling is already pinned by test_neutral_style.

    // A real mouse click reaches clicked() exactly once — the only wiring every
    // caller uses (onClicked: …).
    function test_click_emits_clicked() {
        const b = make('import TodoCpp; PillButton { text: "go"; width: 120; height: 32 }');
        let n = 0;
        b.clicked.connect(function() { n++; });
        mouseClick(b);
        compare(n, 1);
        parkCursor();
    }

    // enabled:false must swallow the click — QuickCapturePopup gates its
    // Create pill on `enabled: root._title.length > 0`.
    function test_disabled_swallows_click() {
        const b = make('import TodoCpp; PillButton { text: "no"; width: 120; height: 32; enabled: false }');
        let n = 0;
        b.clicked.connect(function() { n++; });
        mouseClick(b);
        compare(n, 0);
        parkCursor();
    }
}
