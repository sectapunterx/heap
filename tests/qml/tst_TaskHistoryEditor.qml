// The task editor's History fold (APP-165): folded by default with a count,
// opens to a newest-first list, and follows events that land while it is open.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TaskHistoryEditor"
    when: windowShown
    visible: true
    width: 520
    height: 640

    Item { id: host; anchors.fill: parent }

    function test_history_is_folded_counted_and_live() {
        const draft = AppController.newTaskDraft("todo");
        draft.title = "history probe";
        verify(AppController.saveTask(draft));
        const id = draft.id;
        AppController.moveTask(id, "prog");

        const te = createTemporaryQmlObject('import TodoCpp; TaskEditor { }', host);
        te.showFor(AppController.taskById(id));

        const toggle = findChild(te, "te-history-toggle");
        verify(toggle !== null && toggle.visible, "no history fold on a task with history");
        verify(!te.historyOpen, "history must start folded");
        const n = te._history.length;
        verify(n >= 2, "created + moved, got " + n);
        compare(findChild(te, "te-history-head").text, "▸  " + I18n.t("editor.history").arg(n));

        te.historyOpen = true;
        verify(findChild(te, "te-history").visible);
        // Newest first (the creation last), read as words, not ids. A move
        // can bring other changes in the same instant (a planned date), so
        // look for it rather than pin its index.
        compare(te._history[n - 1].kind, "created");
        const moved = te._history.filter(e => e.kind === "status");
        compare(moved.length, 1);
        verify(te._historyText(moved[0]).indexOf("→") > 0);

        // An event that lands while the editor is open shows up.
        AppController.moveTask(id, "done");
        verify(te._history.length > n, "an event that landed while open is missing");

        te.close();
        AppController.deleteTask(id);
    }

    function test_a_new_task_has_no_fold() {
        const te = createTemporaryQmlObject('import TodoCpp; TaskEditor { }', host);
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        te.showFor(d);
        verify(!findChild(te, "te-history-toggle").visible);
        te.close();
    }

    function test_strings_exist_in_both_languages() {
        const keys = ["editor.history", "history.created", "history.pulled", "history.pushed", "history.status",
                      "history.title", "history.priority", "history.due", "history.scheduled", "history.viaTracker"];
        for (let i = 0; i < keys.length; ++i) {
            verify(I18n.dict.en[keys[i]] !== undefined, keys[i] + " missing in en");
            verify(I18n.dict.ru[keys[i]] !== undefined, keys[i] + " missing in ru");
        }
    }
}
