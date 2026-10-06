// Tests for qml/HotkeysPanel.qml — the rebindable-hotkey catalog Popup.
// Load-smoke + _labelFor() function contract + isCapturing/capturingId
// property contract + onClosed reset behaviour. The panel declares no custom
// signals and no objectName, so there is no signal- or click-layer to cover.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "HotkeysPanel"
    when: windowShown
    visible: true
    width: 500
    height: 500

    Item { id: host; anchors.fill: parent }

    function make() {
        const o = createTemporaryQmlObject('import TodoCpp; HotkeysPanel { }', host);
        verify(o !== null, "HotkeysPanel failed to instantiate");
        return o;
    }

    // smoke: the Popup (with its inline BindingRow/KeyCaptureChip components and
    // the AppController.shortcuts-bound ListView) resolves and instantiates.
    function test_smoke_load() {
        const panel = make();
        verify(panel !== null);
    }

    // _labelFor() guards a falsy id and returns "" without touching the
    // controller (source: `if (!actionId) return "";`).
    function test_label_for_empty_returns_empty() {
        const panel = make();
        compare(panel._labelFor(""), "");
    }

    // _labelFor(id) forwards to AppController.shortcutLabel(id) for a real
    // catalog entry; both must agree and be non-empty.
    function test_label_for_known_matches_controller() {
        const panel = make();
        const expected = AppController.shortcutLabel("palette.open");
        verify(expected.length > 0, "seeded catalog must label palette.open");
        compare(panel._labelFor("palette.open"), expected);
    }

    // An id absent from the catalog yields "" (shortcutLabel returns "" for a
    // missing index, and _labelFor passes it straight through).
    function test_label_for_unknown_returns_empty() {
        const panel = make();
        compare(panel._labelFor("__no_such_action__"), "");
    }

    // isCapturing follows capturingId — the one action whose chip records.
    function test_is_capturing_tracks_capturing_id() {
        const panel = make();
        compare(panel.capturingId, "", "fresh panel records nothing");
        verify(!panel.isCapturing);
        panel.capturingId = "task.new";
        verify(panel.isCapturing);
        panel.capturingId = "";
        verify(!panel.isCapturing);
    }

    // Closing the panel ends a capture, so global shortcuts come back.
    function test_closed_resets_capture() {
        const panel = make();
        panel.parent = host;
        panel.open();
        tryVerify(function() { return panel.visible; }, 2000, "panel did not open");
        panel.capturingId = "task.new";
        panel.close();
        tryCompare(panel, "capturingId", "");
        verify(!panel.isCapturing);
    }

    function field(panel, id) {
        const find = function (it) {
            if (!it) return null;
            if (it.objectName === "hotkey-chip-" + id) return it;
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) { const r = find(kids[i]); if (r) return r; }
            return null;
        };
        // The list builds the rows on screen only; scroll the one asked for in.
        panel.revealRow(id);
        return find(panel.contentItem);
    }

    function openPanel() {
        AppController.resetAllShortcuts();
        const panel = make();
        panel.parent = host;
        panel.open();
        tryVerify(function() { return panel.opened; }, 2000);
        return panel;
    }

    // UX-4: a rebind ends the capture even though committing rebuilds the list
    // and destroys the chip that was recording. It used to throw
    // "cancelCapture is not a function" and leave isCapturing stuck on, which
    // kept every global shortcut dead until the panel was closed.
    function test_commit_releases_capture() {
        const panel = openPanel();
        tryVerify(function () { return field(panel, "view.archive") !== null; }, 2000, "no chip for view.archive");
        const f = field(panel, "view.archive");
        verify(f !== null);
        f.forceActiveFocus();
        keyClick(Qt.Key_Return);                 // start recording
        compare(panel.capturingId, "view.archive");
        keyClick(Qt.Key_Y, Qt.ControlModifier | Qt.ShiftModifier);
        keyClick(Qt.Key_Return);                 // save
        compare(panel.capturingId, "");
        verify(!panel.isCapturing);
        compare(AppController.shortcutFor("view.archive"), "Ctrl+Shift+Y");
        AppController.resetAllShortcuts();
        panel.close();
    }

    // UX-4: Enter on a focused chip starts recording — it used to commit an
    // empty sequence and unbind the action — and a stray letter while not
    // recording binds nothing.
    function test_enter_on_chip_starts_capture_not_unbind() {
        const panel = openPanel();
        const before = AppController.shortcutFor("view.board");
        verify(before.length > 0);
        tryVerify(function () { return field(panel, "view.board") !== null; }, 2000, "no chip for view.board");
        const f = field(panel, "view.board");
        f.forceActiveFocus();
        keyClick(Qt.Key_X);
        compare(panel.capturingId, "", "a letter must not start a capture");
        keyClick(Qt.Key_Return);
        compare(AppController.shortcutFor("view.board"), before, "Enter unbound the action");
        compare(panel.capturingId, "view.board", "Enter must start recording");
        keyClick(Qt.Key_Escape);
        compare(panel.capturingId, "");
        compare(AppController.shortcutFor("view.board"), before);
        panel.close();
    }

    // UX-4: "↺ all" asks first — one press arms, the second resets.
    function test_reset_all_needs_a_second_press() {
        const panel = openPanel();
        AppController.setShortcut("view.archive", "Ctrl+Shift+Y");
        panel._pressResetAll();
        compare(AppController.shortcutFor("view.archive"), "Ctrl+Shift+Y", "one press reset everything");
        verify(panel.resetAllArmed);
        panel._pressResetAll();
        verify(AppController.shortcutFor("view.archive") !== "Ctrl+Shift+Y");
        verify(!panel.resetAllArmed);
        panel.close();
    }

    // APP-166: the cheat-sheet is complete — every catalogue entry exactly
    // once — and grouped, each group's heading on its first row.
    function test_rows_cover_the_catalogue_grouped() {
        const panel = make();
        const rows = panel.rows;
        compare(rows.length, AppController.shortcuts.length);
        const seen = {};
        let lastGroup = -1;
        for (let i = 0; i < rows.length; i++) {
            verify(!seen[rows[i].id], rows[i].id + " listed twice");
            seen[rows[i].id] = true;
            const g = panel.groupOrder.indexOf(rows[i].group);
            verify(g >= 0, "unknown group " + rows[i].group);
            verify(g >= lastGroup, "groups come in order");
            compare(rows[i].first, g !== lastGroup, "heading on the first row of " + rows[i].group);
            lastGroup = g;
            verify(I18n.t("hotkeys.group." + rows[i].group) !== "hotkeys.group." + rows[i].group);
        }
        compare(panel.groupOf("view.week"), "views");
        compare(panel.groupOf("board.cursorDown"), "board");
        compare(panel.groupOf("cal.today"), "calendar");
        compare(panel.groupOf("notes.new"), "notes");
        compare(panel.groupOf("palette.open"), "general");
    }
}
