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

    // A synced ticket's id is lowercase by construction ("github-1234", built
    // from the provider id). The field used to uppercase it on open, so simply
    // opening a ticket and pressing Save re-keyed the row to GITHUB-1234 — a
    // rename the user never asked for, and a data loss if that id was taken.
    function test_opening_a_synced_ticket_does_not_rewrite_its_id() {
        const te = make('import TodoCpp; TaskEditor { }');
        const idField = findChild(te, "te-id");
        verify(idField !== null, "te-id not found");

        te.showFor({ id: "github-1234", title: "Fix the crash", _isNew: false });
        compare(idField.text, "github-1234", "the editor rewrote a synced ticket's id on open");
        te.close();
    }

    // …while a hand-typed new id still gets canonicalised.
    function test_a_new_id_is_still_uppercased_as_the_user_types() {
        const te = make('import TodoCpp; TaskEditor { }');
        const idField = findChild(te, "te-id");
        te.showFor({ id: "", title: "fresh", _isNew: true });
        idField.text = "lte-9000";
        compare(idField.text, "LTE-9000");
        te.close();
    }

    // ── Mirrored tracker issue (HEAP-117) ──
    // The editor edits heap's copy; the strip says whose issue it is, and warns
    // that the next sync overwrites the fields above it.
    function test_ticket_strip_shows_only_for_a_mirrored_issue() {
        const te = make('import TodoCpp; TaskEditor { }');
        const strip = findChild(te, "te-ticket-strip");
        verify(strip !== null, "te-ticket-strip not found");

        te.showFor({ id: "LTE-2700", title: "local work", _isNew: false, ticket: ({}) });
        verify(!strip.visible, "a local task grew a ticket strip");

        te.showFor({
            id: "github-1234",
            title: "Fix the crash",
            _isNew: false,
            ticket: {
                provider: "github",
                key: "#1234",
                url: "https://github.com/acme/web/issues/1234",
                assignee: "ada",
                author: "grace",
                issueType: "Bug",
                project: "acme/web",
                milestone: "v2",
                commentCount: 4
            }
        });
        verify(strip.visible, "a mirrored issue has no ticket strip");
        verify(findChild(te, "te-ticket-open").visible, "no open-in-tracker button");

        // Every fact the tracker gave is listed, and nothing it did not.
        const facts = te._ticketFacts;
        const values = facts.map(f => String(f.value));
        verify(values.indexOf("ada") >= 0, "the assignee is missing");
        verify(values.indexOf("grace") >= 0, "the reporter is missing");
        verify(values.indexOf("Bug") >= 0, "the issue type is missing");
        verify(values.indexOf("v2") >= 0, "the milestone is missing");
        verify(values.indexOf("4") >= 0, "the comment count is missing");
        te.close();
    }

    // -1 is "the provider did not say", which must not render as a count.
    function test_unknown_comment_count_is_not_listed() {
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor({
            id: "github-1", title: "t", _isNew: false,
            ticket: { provider: "github", key: "#1", url: "https://x.invalid/1", commentCount: -1 }
        });
        const values = te._ticketFacts.map(f => String(f.value));
        verify(values.indexOf("-1") < 0, "an unknown comment count was rendered");
        te.close();
    }

    // A mirrored issue is known by its tracker key, not the id the merge made.
    function test_header_shows_the_tracker_key() {
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor({
            id: "github-1234", title: "t", _isNew: false,
            ticket: { provider: "github", key: "#1234", url: "https://x.invalid/1234" }
        });
        compare(te._ticket.key, "#1234");
        verify(te._isTicket);
        te.close();
    }
}
