// Load-smoke, config-contract and function-contract tests for the Notes
// quick-capture popup (qml/QuickCaptureNotesPopup.qml). The component exposes
// no objectName on any child, so input-driven paths are intentionally omitted.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "QuickCaptureNotesPopup"
    when: windowShown
    visible: true
    width: 500
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // Smoke: the whole tree instantiates — MentionAutocomplete, PillButton,
    // Theme.* / I18n.t(...) bindings and the discard-confirm child popup all
    // resolve. A renamed property or missing type would return null here.
    function test_smoke_load() {
        const qc = make('import TodoCpp; QuickCaptureNotesPopup { }');
        verify(qc !== null, "QuickCaptureNotesPopup failed to instantiate");
    }

    // Config contract: the popup must stay modal and must NOT auto-close — it
    // owns all key handling so the Esc→discard-confirm flow can intercept Esc
    // (source comment, qml/QuickCaptureNotesPopup.qml:19-21).
    function test_popup_config_contract() {
        const qc = make('import TodoCpp; QuickCaptureNotesPopup { }');
        compare(qc.modal, true, "notes popup must be modal");
        compare(qc.closePolicy, Popup.NoAutoClose,
                "must not auto-close on Escape/outside-click");
        compare(qc.padding, 0, "padding is 0 (margins are per-child)");
        compare(qc.width, 600, "fixed 600px width");
    }

    // _submit() on an empty editor is a silent no-op: it hits the
    // body.trim().length === 0 guard and closes without appending a note
    // (qml/QuickCaptureNotesPopup.qml:30-40). Confirms editor/root ids resolve
    // and no spurious entry lands in AppController.notesState.
    function test_submit_empty_is_noop() {
        const qc = make('import TodoCpp; QuickCaptureNotesPopup { }');
        const before = AppController.notesState;
        qc._submit();                       // editor.text defaults to ""
        compare(AppController.notesState, before,
                "empty submit must not append a note entry");
        verify(!qc.opened, "empty submit must leave the popup closed");
    }

    // _maybeDiscard() on an empty editor closes silently instead of opening the
    // discard-confirm popup (qml/QuickCaptureNotesPopup.qml:42-48). No note is
    // written and the call must not throw.
    function test_maybe_discard_empty_is_noop() {
        const qc = make('import TodoCpp; QuickCaptureNotesPopup { }');
        const before = AppController.notesState;
        qc._maybeDiscard();                 // editor.text defaults to ""
        compare(AppController.notesState, before,
                "discard on empty editor must not touch notesState");
        verify(!qc.opened, "empty discard must leave the popup closed");
    }
}
