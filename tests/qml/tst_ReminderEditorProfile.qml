// PRES-1 (audit 2026-10-06): a reminder about a task of another profile,
// clicked while a task editor is open with edits, switched the profile under
// the editor; its Save then wrote the edited task as a same-id copy into the
// other profile and left the task itself unchanged. Through the real Main.qml:
// Open settles the editor first and only then goes to the other profile; Done
// leaves the window's profile alone.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ReminderEditorProfile"
    when: windowShown

    property var win: null
    property string pA: ""
    property var made: []
    property var seeded: []

    function initTestCase() {
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tc.win.width = 1400;
        tc.win.height = 900;
        tc.win.show();
        wait(1200);
        tc.pA = AppController.activeProfileId;
    }
    function cleanupTestCase() {
        if (tc.win) tc.win.destroy();
    }
    function cleanup() {
        const d = tc.doc();
        if (d && d.opened) d.close();
        AppController.activeProfileId = tc.pA;
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        tc.seeded = [];
        for (let i = 0; i < tc.made.length; i++) AppController.deleteProfile(tc.made[i]);
        tc.made = [];
        AppController.clearPendingUndo();
    }

    // The task document (APP-265) in place of the modal editor: it saves by
    // itself, so "settling" it is writing what is typed into its own task
    // before anything switches the profile.
    function doc() {
        return findChild(tc.win, "task-doc");
    }

    function mk(title) {
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.title = title;
        verify(AppController.saveTask(d), "seed save");
        return d.id;
    }

    // "<profile>:<status>:<title>" for every profile holding `id`.
    function where(id) {
        const out = [];
        const keep = AppController.activeProfileId;
        const profs = AppController.profiles;
        for (let i = 0; i < profs.length; i++) {
            AppController.activeProfileId = String(profs[i].id);
            const t = AppController.taskById(id);
            if (t && t.id) out.push(String(profs[i].id) + ":" + t.status + ":" + t.title);
        }
        AppController.activeProfileId = keep;
        return out;
    }

    // T1 in A (active), T2 in a fresh profile B; T1 open as a document with
    // its title edited and not yet saved.
    function setUp(tag) {
        const t1 = mk("pres1 T1 " + tag);
        tc.seeded.push(t1);
        const pB = AppController.createProfile("pres1 B " + tag + " " + Date.now(), "");
        verify(pB.length > 0);
        tc.made.push(pB);
        const t2 = mk("pres1 T2 " + tag);
        AppController.activeProfileId = tc.pA;
        verify(AppController.handleNotificationUri("heap://notify?id=deadline:" + t1 + "&action=open"));
        tryVerify(() => tc.doc() && tc.doc().opened && tc.doc().taskId === t1, 3000, "T1 did not open");
        findChild(tc.doc(), "task-doc-title").text = "pres1 EDITED " + tag;
        return { t1: t1, t2: t2, pB: pB };
    }

    function test_open_settles_the_editor_before_switching() {
        const s = tc.setUp("open");
        verify(AppController.handleNotificationUri("heap://notify?id=deadline:" + s.t2 + "&action=open"));
        tryCompare(AppController, "activeProfileId", s.pB);
        tryVerify(() => tc.doc().opened && tc.doc().taskId === s.t2, 3000, "T2 did not open");
        compare(findChild(tc.doc(), "task-doc-title").text, "pres1 T2 open");
        // T1's edit was saved where T1 lives (where() walks the profiles).
        compare(tc.where(s.t1), [tc.pA + ":todo:pres1 EDITED open"]);
    }

    function test_done_leaves_the_open_editor_in_its_profile() {
        const s = tc.setUp("done");
        verify(AppController.handleNotificationUri("heap://notify?id=deadline:" + s.t2 + "&action=done"));
        wait(100);
        compare(AppController.activeProfileId, tc.pA, "Done switched the profile under the document");
        compare(tc.where(s.t2), [s.pB + ":done:pres1 T2 done"]);
        tc.doc().flush();
        compare(tc.where(s.t1), [tc.pA + ":todo:pres1 EDITED done"]);
    }

    // Whatever switches the profile, the document saves into its own first.
    function test_save_goes_back_to_the_editors_profile() {
        const s = tc.setUp("back");
        AppController.activeProfileId = s.pB;
        verify(!tc.doc().opened, "the document stayed open over another profile");
        AppController.activeProfileId = tc.pA;
        compare(tc.where(s.t1), [tc.pA + ":todo:pres1 EDITED back"]);
    }
}
