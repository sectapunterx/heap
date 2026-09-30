// File attachments in the UI: the task editor's chips (mouse and keyboard),
// a new task's draft list, a drop on a card, the notes editor's links and
// chips, the renderer finding a stored image, and the Settings cleanup that
// asks before it deletes.
//
// The files attached are ones the repository already has (this test itself,
// a packaging script), so nothing has to be written from QML. Nothing here
// opens a file in another program: the one open that is driven is a script,
// which stops at the confirmation.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Attachments"
    when: windowShown
    visible: true
    width: 900
    height: 700

    Item { id: host; anchors.fill: parent }

    readonly property url plainFile: Qt.resolvedUrl("tst_Attachments.qml")
    readonly property url scriptFile: Qt.resolvedUrl("../../packaging/windows/copy-deps.sh")
    readonly property url hashFile: Qt.resolvedUrl("tst_NotesView.qml")

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function newTask(title) {
        const d = AppController.newTaskDraft("todo");
        d.title = title;
        verify(AppController.saveTask(d));
        return d.id;
    }

    function chipsIn(item) {
        const out = [];
        function walk(it) {
            if (!it) return;
            if (String(it.objectName).indexOf("att-chip-") === 0 && it.visible) out.push(it);
            const kids = it.children || [];
            for (let i = 0; i < kids.length; ++i) walk(kids[i]);
        }
        walk(item);
        return out;
    }

    function cleanup() {
        AppController.clearPendingUndo();
    }

    // ── Task editor ──────────────────────────────────────────────────

    function test_editor_attach_shows_a_chip_and_delete_key_detaches() {
        const id = newTask("att editor probe");
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(AppController.taskById(id));
        compare(te._attachments.length, 0);

        // The drop handler and the file dialog both end here.
        compare(te.attachUrls([tc.plainFile]), 1);
        compare(AppController.taskAttachments(id).length, 1, "attached to the stored task at once");
        const chips = findChild(te, "te-attachment-chips");
        verify(chips !== null);
        tryVerify(function () { return chipsIn(chips).length === 1; }, 2000);
        const chip = chipsIn(chips)[0];
        compare(findChild(chip, "att-name").text, "tst_Attachments.qml");
        verify(chip.activeFocusOnTab, "a chip is a Tab stop");
        verify(!te.isDirty(), "attaching to an existing task is saved, not a pending edit");

        chip.forceActiveFocus();
        keyClick(Qt.Key_Delete);
        tryVerify(function () { return AppController.taskAttachments(id).length === 0; }, 2000);
        tryVerify(function () { return chipsIn(chips).length === 0; }, 2000);

        // Undo from the toast puts it back, and the editor follows.
        AppController.undo();
        tryVerify(function () { return te._attachments.length === 1; }, 2000);
        te.close();
        AppController.deleteTask(id);
    }

    function test_editor_script_asks_before_opening() {
        const id = newTask("att script probe");
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(AppController.taskById(id));
        compare(te.attachUrls([tc.scriptFile]), 1);
        const chips = findChild(te, "te-attachment-chips");
        tryVerify(function () { return chipsIn(chips).length === 1; }, 2000);
        const chip = chipsIn(chips)[0];
        chip.forceActiveFocus();
        keyClick(Qt.Key_Return);
        const dlg = findChild(chips, "att-open-confirm");
        verify(dlg !== null);
        tryVerify(function () { return dlg.opened; }, 2000, "a script is confirmed first");
        dlg.close();
        te.close();
        AppController.deleteTask(id);
    }

    function test_new_task_keeps_files_in_the_draft_until_create() {
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(AppController.newTaskDraft("todo"));
        verify(te.isNew);
        compare(te.attachUrls([tc.plainFile, tc.plainFile]), 1);
        compare(te._attachments.length, 1, "the same file twice is one attachment");
        verify(te.isDirty(), "a new task's files are part of the unsaved draft");
        // Title, then Create.
        const title = findChild(te, "te-title");
        verify(title !== null);
        title.text = "att draft probe";
        verify(te._commit());
        let savedId = "";
        const m = AppController.tasks;
        for (let i = 0; i < m.rowCount(); i++) {
            if (String(m.data(m.index(i, 0), Qt.UserRole + 2)) === "att draft probe") savedId = String(m.data(m.index(i, 0), Qt.UserRole + 1));
        }
        verify(savedId.length > 0);
        compare(AppController.taskAttachments(savedId).length, 1);
        te.close();
        AppController.deleteTask(savedId);
    }

    // ── Card ─────────────────────────────────────────────────────────

    Component {
        id: cardComp
        TaskCard { width: 360 }
    }

    function test_drop_on_a_card_attaches_and_the_card_counts() {
        const id = newTask("att card probe");
        const card = cardComp.createObject(host, { task: { id: id, title: "att card probe", status: "todo", priority: "P2",
                                                           attachmentCount: 0 } });
        verify(card !== null);
        const chip = findChild(card, "tc-attachments");
        verify(chip !== null);
        verify(!chip.visible);
        compare(card.attachDroppedFiles([tc.plainFile, tc.scriptFile]), 2);
        compare(AppController.taskAttachments(id).length, 2);
        // The model role the board binds (TaskModel::AttachmentCountRole —
        // QML reads roles by their offset from Qt.UserRole, like the views do).
        const m = AppController.tasks;
        let count = -1;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            if (String(m.data(idx, Qt.UserRole + 1)) === id) count = m.data(idx, Qt.UserRole + 38);
        }
        compare(count, 2);
        card.task = { id: id, title: "att card probe", status: "todo", priority: "P2", attachmentCount: count };
        tryVerify(function () { return chip.visible; }, 2000);
        verify(String(chip.text).indexOf("2") >= 0);
        // One drop, one undo step.
        AppController.undo();
        compare(AppController.taskAttachments(id).length, 0);
        card.destroy();
        AppController.deleteTask(id);
    }

    // ── Notes ────────────────────────────────────────────────────────

    function test_notes_attach_inserts_a_link_and_chip_removes_it() {
        AppController.notesState = "";
        const nv = Qt.createQmlObject('import TodoCpp; NotesView { anchors.fill: parent }', host, "tst_Attachments.notes");
        tryVerify(function () { return nv._loadedOnce; });
        const editor = findChild(nv, "notesEditor");
        verify(editor !== null);
        editor.text = "Intro line";
        editor.cursorPosition = editor.text.length;
        compare(nv.attachUrls([tc.plainFile]), 1);
        verify(editor.text.indexOf("](attachments/") > 0, editor.text);
        // Its own paragraph, so an image would render as an image.
        verify(editor.text.indexOf("Intro line\n\n[") === 0 || editor.text.indexOf("Intro line\n\n![") === 0, editor.text);
        compare(nv._noteAttachments.length, 1);
        const strip = findChild(nv, "notes-attachment-chips");
        tryVerify(function () { return chipsIn(strip).length === 1; }, 2000);

        compare(nv.removeAttachmentRefs(nv._noteAttachments[0].id), 1);
        verify(editor.text.indexOf("attachments/") < 0, editor.text);
        compare(nv._noteAttachments.length, 0);
        // The removal was an ordinary edit: the editor's undo brings it back.
        editor.undo();
        verify(editor.text.indexOf("attachments/") > 0, "Ctrl+Z restores the link");
        nv.destroy();
        AppController.notesState = "";
    }

    // 2026-09-30 audit, KNOW-3: the cleanup between the chip's Remove and the
    // editor's Ctrl+Z used to delete the file the restored link points at.
    function test_notes_cleanup_spares_a_link_the_editor_can_undo() {
        AppController.notesState = "";
        const nv = Qt.createQmlObject('import TodoCpp; NotesView { anchors.fill: parent }', host, "tst_Attachments.notesUndo");
        tryVerify(function () { return nv._loadedOnce; });
        const editor = findChild(nv, "notesEditor");
        editor.text = "Intro";
        editor.cursorPosition = editor.text.length;
        compare(nv.attachUrls([tc.hashFile]), 1);
        const id = nv._noteAttachments[0].id;
        compare(nv.removeAttachmentRefs(id), 1);
        AppController.clearPendingUndo();

        AppController.cleanUpUnusedAttachments();
        verify(String(AppController.attachmentUrl(id)).length > 0, "the file is still there");
        editor.forceActiveFocus();
        keyClick(Qt.Key_Z, Qt.ControlModifier);
        verify(editor.text.indexOf("attachments/" + id) > 0, editor.text);
        tryVerify(function () { return nv._noteAttachments.length === 1 && nv._noteAttachments[0].exists; }, 2000);
        nv.destroy();
        AppController.notesState = "";
    }

    // ── Rendering ────────────────────────────────────────────────────

    MdDocument {
        id: doc
        imageBaseDir: AppController.dataDir + "/attachments"
    }

    function test_a_stored_image_renders_from_the_attachments_folder() {
        const stored = AppController.importAttachments([Qt.resolvedUrl("../../design/brand-export/icon/heap-icon.svg")]);
        if (stored.length === 0) skip("no icon in this checkout");
        const a = stored[0];
        verify(a.isImage, "an SVG is an image");
        verify(a.ref.indexOf("![") === 0, a.ref);
        doc.text = a.ref + "\n";
        tryVerify(function () { return doc.model && doc.model.rowCount() > 0; });
        // Whichever role carries it, the row points into the attachments folder.
        // MdBlockModel::ImageSourceRole.
        const url = String(doc.model.data(doc.model.index(0, 0), Qt.UserRole + 17));
        compare(url, String(AppController.attachmentUrl(a.id)));
    }

    // ── Settings → Data ──────────────────────────────────────────────

    function test_cleanup_asks_first_then_deletes() {
        // Something nothing refers to.
        const stored = AppController.importAttachments([tc.scriptFile]);
        compare(stored.length, 1);
        // Make sure nothing still refers to it from an earlier test's undo.
        AppController.clearPendingUndo();
        let refs = 0;
        const m = AppController.tasks;
        for (let i = 0; i < m.rowCount(); i++) {
            const tid = String(m.data(m.index(i, 0), Qt.UserRole + 1));
            if (AppController.taskAttachments(tid).some(x => x.id === stored[0].id)) refs++;
        }
        if (refs > 0) skip("a task in the persisted test profile still uses the file");
        const sv = make('import TodoCpp; SettingsView { anchors.fill: parent }');
        sv.activeSection = "data";
        tryVerify(function () { return findChild(sv, "att-cleanup-button") !== null; }, 3000);
        const btn = findChild(sv, "att-cleanup-button");
        tryVerify(function () { return btn.visible; }, 2000);
        btn.clicked();
        verify(AppController.attachmentUrl(stored[0].id).toString().length > 0, "the first press only asks");
        verify(String(btn.text).indexOf(I18n.t("att.cleanup.button")) < 0, "the button now says what it will delete");
        btn.clicked();
        compare(String(AppController.attachmentUrl(stored[0].id)), "", "the second press deletes");
        compare(AppController.unusedAttachments().count, 0);
    }
}
