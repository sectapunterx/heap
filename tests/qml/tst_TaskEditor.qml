// TaskEditor: regressions for two edit-path bugs.
//  (1) Delete keyed off the live editable idField instead of the stable
//      open-time id, so editing the id then hitting Delete was a silent no-op
//      (deleteTask misses, popup closes as if it worked).
//  (2) The recurrence dropdown lacked every:sat / every:sun, so a weekend
//      recurrence (which the chrono parser emits) mapped to "None" on open and
//      was overwritten to "" on save — silent data loss on edit.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TaskEditor"
    when: windowShown
    visible: true
    width: 520
    height: 640

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function taskExists(id) {
        const m = AppController.tasks;
        for (let i = 0; i < m.rowCount(); i++)
            if (String(m.data(m.index(i, 0), Qt.UserRole + 1)) === id) return true;
        return false;
    }

    // Delete must target root._originalId (the id captured when the editor
    // opened), not idField.text which the user can edit. Reproduces the silent
    // no-op: edit the id field, delete, and the ORIGINAL row must still be gone.
    function test_delete_uses_original_id_not_edited_field() {
        const draft = AppController.newTaskDraft("todo");
        draft.title = "te delete probe";
        AppController.saveTask(draft);
        const origId = draft.id;
        verify(taskExists(origId), "seed task must exist before delete");

        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(AppController.taskById(origId));   // opens as an existing task

        const idField = findChild(te, "te-id");
        verify(idField !== null, "te-id not found");
        idField.text = "ZZZ-999";                     // user edits the id, no Save

        const del = findChild(te, "te-delete");
        verify(del !== null, "te-delete not found");
        // Emit the button's clicked() — runs the exact onClicked handler a real
        // click would, deterministically (avoids offscreen Popup hit-testing).
        del.clicked();

        verify(!taskExists(origId),
               "Delete must remove the opened task by its original id");

        // Cleanup in case the fix regressed and the row survived.
        if (taskExists(origId)) AppController.deleteTask(origId);
    }

    // A task opened with a weekend recurrence must round-trip: the value Save
    // would write (recurBox._vals[currentIndex]) equals the opened recurrence,
    // not "" (which the missing sat/sun options collapsed it to).
    function test_recurrence_weekend_roundtrips() {
        const te = make('import TodoCpp; TaskEditor { }');
        const rec = findChild(te, "te-recurrence");
        verify(rec !== null, "te-recurrence not found");
        verify(rec._vals.indexOf("every:sat") >= 0, "every:sat must be an option");
        verify(rec._vals.indexOf("every:sun") >= 0, "every:sun must be an option");

        te.showFor({ id: "", title: "sat probe", recurrence: "every:sat", _isNew: true });
        compare(rec._vals[rec.currentIndex], "every:sat",
                "Saturday recurrence must survive open->save round-trip");

        te.showFor({ id: "", title: "sun probe", recurrence: "every:sun", _isNew: true });
        compare(rec._vals[rec.currentIndex], "every:sun",
                "Sunday recurrence must survive open->save round-trip");
        te.close();
    }
}
