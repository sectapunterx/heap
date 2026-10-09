// APP-126: a press on the empty space beside a dialog — the dimmed backdrop,
// left, right, above or below it — closes it, like Esc does. Dialogs that
// hold unsaved input go through their own discard check instead of closing
// outright, and a press beside a picker opened from a dialog closes only the
// picker.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DialogOutsideClick"
    when: windowShown
    visible: true
    width: 1200
    height: 900

    Item { id: host; anchors.fill: parent }
    // The rail button a popover hangs off (see Main._togglePopover).
    Item { id: railButton; x: 1100; y: 800; width: 24; height: 24 }

    function _make(qml) {
        const o = createTemporaryQmlObject('import TodoCpp; ' + qml, host);
        verify(o !== null, qml);
        return o;
    }

    // Far top-left corner of the window: outside every centred dialog.
    function _pressBeside() {
        mouseClick(tc, 6, 6);
        wait(50);
    }

    function test_a_press_beside_closes_the_dialog_data() {
        return [
            { tag: "CommandPalette", qml: "CommandPalette { }" },
            { tag: "HotkeysPanel", qml: "HotkeysPanel { }", popover: true },
            { tag: "WeeklyRecapDialog", qml: "WeeklyRecapDialog { }" },
            { tag: "SeriesScopeDialog", qml: "SeriesScopeDialog { }" },
            { tag: "SavedViewNameDialog", qml: "SavedViewNameDialog { }" },
            { tag: "ProfileEditor", qml: "ProfileEditor { }" },
            { tag: "PersonEditor", qml: "PersonEditor { }" },
            { tag: "PersonPicker", qml: "PersonPicker { }" },
            { tag: "LinkConfirmDialog", qml: "LinkConfirmDialog { }" },
            { tag: "VaultImportDialog", qml: "VaultImportDialog { }" },
            { tag: "QuickCapturePopup", qml: "QuickCapturePopup { }" },
            { tag: "QuickCaptureNotesPopup", qml: "QuickCaptureNotesPopup { }" },
            { tag: "WelcomePopup", qml: "WelcomePopup { }" },
            { tag: "TaskEditor", qml: "TaskEditor { }", fn: "task" },
            { tag: "EventCapture", qml: "EventCapture { }" },
        ];
    }

    function test_a_press_beside_closes_the_dialog(row) {
        const p = _make(row.qml);
        if (row.popover)
            p.parent = railButton;
        if (row.fn === "task")
            p.showFor(AppController.newTaskDraft("todo"));
        else if (row.fn === "event")
            p.showForDraft(AppController.newEventDraft(10, new Date()));
        else
            p.open();
        tryCompare(p, "opened", true);
        _pressBeside();
        verify(!p.visible, row.tag + " stayed open after a press beside it");
    }

    // A press on a dialog's own body (a label, padding) is not a press beside
    // it: in 0.7.0 it reached the overlay and closed the task editor on any
    // click.
    function test_a_press_inside_keeps_the_dialog_open_data() {
        return [
            { tag: "TaskEditor", qml: "TaskEditor { }", fn: "task" },
            { tag: "WelcomePopup", qml: "WelcomePopup { }" },
            { tag: "QuickCaptureNotesPopup", qml: "QuickCaptureNotesPopup { }" },
        ];
    }

    function test_a_press_inside_keeps_the_dialog_open(row) {
        const p = _make(row.qml);
        if (row.fn === "task")
            p.showFor(AppController.newTaskDraft("todo"));
        else if (row.fn === "event")
            p.showForDraft(AppController.newEventDraft(10, new Date()));
        else
            p.open();
        tryCompare(p, "opened", true);
        // Near the top edge, mid-width: the header, not a field or button.
        const inside = p.contentItem.mapToItem(tc, p.contentItem.width / 2, 4);
        mouseClick(tc, inside.x, inside.y);
        wait(50);
        verify(p.visible, row.tag + " closed after a press inside it");
        p.close();
    }

    // Typed text is not thrown away by a stray press: the editor asks first.
    function test_a_press_beside_an_edited_task_asks_first() {
        const ed = _make("TaskEditor { }");
        ed.showFor(AppController.newTaskDraft("todo"));
        tryCompare(ed, "opened", true);
        findChild(ed, "te-title").text = "half typed";
        _pressBeside();
        verify(ed.opened, "the edited task closed without asking");
        const prompt = findChild(ed, "te-discard-prompt");
        verify(prompt && prompt.opened, "no discard prompt");
        // The prompt is on top now: a second press is its business, not the
        // editor's, so the edits are still there.
        _pressBeside();
        verify(ed.opened);
        prompt.close();
        ed.close();
    }

    function test_a_press_beside_a_note_with_text_asks_first() {
        const qc = _make("QuickCaptureNotesPopup { }");
        qc.open();
        tryCompare(qc, "opened", true);
        findChild(qc, "quicknote-editor").text = "an idea";
        verify(qc.hasText);
        _pressBeside();
        verify(qc.opened, "the note was dropped without asking");
        qc.close();
    }
}
