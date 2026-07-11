// Tests for qml/HotkeysPanel.qml — the rebindable-hotkey catalog Popup.
// Load-smoke + _labelFor() function contract + isCapturing/_activeCaptures
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

    // isCapturing is the derived predicate _activeCaptures > 0. Drive the
    // backing counter (a plain instance property on a throwaway object → no
    // global state) and check the readonly predicate tracks it.
    function test_is_capturing_tracks_active_captures() {
        const panel = make();
        compare(panel._activeCaptures, 0, "fresh panel starts with no captures");
        verify(!panel.isCapturing);

        panel._activeCaptures = 2;
        verify(panel.isCapturing, "isCapturing must be true while captures are active");

        panel._activeCaptures = 0;
        verify(!panel.isCapturing);
    }

    // Closing the panel resets the capture counter (source: onClosed:
    // _activeCaptures = 0) so a chip left mid-capture cannot leave global
    // Shortcuts disabled after the panel goes away.
    function test_closed_resets_active_captures() {
        const panel = make();
        panel.parent = host;              // give the Popup a window to open into
        panel.open();
        tryVerify(function() { return panel.visible; }, 2000, "panel did not open");

        panel._activeCaptures = 3;
        panel.close();
        // onClosed fires when the close settles; wait for the counter to reset.
        tryCompare(panel, "_activeCaptures", 0);
        verify(!panel.isCapturing);
    }
}
