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

    // DG-005 (X/N-Dlg-Small): every button is outlined, none is filled.
    // Neutral: the quiet line and the muted label.
    function test_neutral_style() {
        const b = make('import TodoCpp; PillButton { text: "n"; width: 120; height: 32 }');
        parkCursor();
        tryCompare(b, "hovered", false);
        verify(Qt.colorEqual(b.background.color, "#00000000"), "neutral is not filled");
        verify(Qt.colorEqual(b.background.border.color, Theme.buttonLine), "neutral border is the button line");
        compare(b.background.border.width, 1);
        compare(b.background.radius, Theme.radiusMd);
        verify(Qt.colorEqual(b.contentItem.color, Theme.buttonText), "neutral label is the button text");
        compare(b.contentItem.font.weight, Theme.fwBody);
        compare(b.contentItem.font.pixelSize, Theme.fsMd);
    }
    // Primary: the brighter line and the bright label — never a lavender fill.
    function test_primary_style() {
        const b = make('import TodoCpp; PillButton { text: "p"; primary: true }');
        parkCursor();
        verify(Qt.colorEqual(b.background.color, "#00000000"), "primary is not filled");
        verify(Qt.colorEqual(b.background.border.color, Theme.buttonLinePrimary), "primary has the brighter line");
        verify(Qt.colorEqual(b.contentItem.color, Theme.buttonTextPrimary), "primary label is the bright text");
    }
    // Danger: a danger line and a danger label.
    function test_danger_style() {
        const b = make('import TodoCpp; PillButton { text: "d"; danger: true }');
        parkCursor();
        verify(Qt.colorEqual(b.background.color, "#00000000"), "danger is not filled");
        verify(Qt.colorEqual(b.background.border.color, Theme.withAlpha(Theme.danger, 0.45)), "danger border must be danger @ 0.45");
        verify(Qt.colorEqual(b.contentItem.color, Theme.danger), "danger label must be Theme.danger");
    }
    // Danger wins over primary: a destructive primary still reads as danger.
    function test_danger_precedes_primary() {
        const b = make('import TodoCpp; PillButton { text: "pd"; primary: true; danger: true }');
        parkCursor();
        verify(Qt.colorEqual(b.background.border.color, Theme.withAlpha(Theme.danger, 0.45)), "danger must win the border");
        verify(Qt.colorEqual(b.contentItem.color, Theme.danger), "danger must win the label");
    }
    // Flags are live bindings: flipping them at runtime restyles the pill.
    function test_runtime_flag_flip() {
        const b = make('import TodoCpp; PillButton { text: "flip"; width: 120; height: 32 }');
        parkCursor();
        b.primary = true;
        verify(Qt.colorEqual(b.background.border.color, Theme.buttonLinePrimary), "flip to primary must restyle");
        b.primary = false;
        b.danger = true;
        verify(Qt.colorEqual(b.contentItem.color, Theme.danger), "flip to danger must restyle");
        b.danger = false;
        tryCompare(b, "hovered", false);
        verify(Qt.colorEqual(b.background.border.color, Theme.buttonLine), "flip back must restore the neutral line");
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

    // Keyboard and screen readers (audit B10): Tab reaches the pill, Space
    // presses it, and it is announced by its text.
    function test_keyboard_focus_and_accessible_name() {
        const b = make('import TodoCpp; PillButton { text: "Save" }');
        // Tab, not click: a click on "+ Task" must not keep the keyboard
        // away from the board once the editor closes.
        compare(b.focusPolicy, Qt.TabFocus);
        compare(b.Accessible.name, "Save");
        let clicks = 0;
        b.clicked.connect(function () { clicks++; });
        b.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(clicks, 1);
    }

    // APP-166: the pill's own click handler (it counts mouse uses of the
    // shortcut) does not replace the caller's.
    function test_shortcut_id_keeps_the_callers_handler() {
        const b = make('import TodoCpp; PillButton { text: "New"; width: 120; height: 32; shortcutId: "task.new";'
                       + ' property int hits: 0; onClicked: hits++ }');
        mouseClick(b);
        compare(b.hits, 1);
        parkCursor();
    }
}
