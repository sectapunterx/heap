// The task as a document (APP-265): edited from the keyboard, saved by
// itself, Esc back; the body edited block by block where it is drawn.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TaskDocument"
    when: windowShown
    visible: true
    width: 1100
    height: 760

    Item { id: host; anchors.fill: parent }
    property var made: []
    function cleanup() {
        for (const id of tc.made) AppController.deleteTask(id);
        tc.made = [];
        AppController.clearPendingUndo();
    }
    function mkTask(title, desc) {
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.title = title;
        d.desc = desc || "";
        AppController.saveTask(d);
        tc.made.push(d.id);
        return d.id;
    }
    function make() {
        const doc = createTemporaryQmlObject('import TodoCpp; TaskDocument { anchors.fill: parent }', host);
        verify(doc !== null);
        return doc;
    }
    function typeText(s) { for (let i = 0; i < s.length; i++) keyClick(s[i]); }

    function test_title_saves_by_itself() {
        const id = mkTask("doc probe");
        const doc = make();
        doc.open(id);
        verify(doc.opened);
        const title = findChild(doc, "task-doc-title");
        tryVerify(() => title.activeFocus, 1000, "the title did not get the keyboard");
        typeText(" two");
        tryVerify(() => AppController.taskById(id).title === "doc probe two", 3000, "the title was not saved");
        doc.close();
        verify(!doc.opened);
    }

    function test_body_is_edited_where_it_is_drawn() {
        const id = mkTask("body probe", "first line\n\n- [ ] item");
        const doc = make();
        doc.open(id);
        const body = findChild(doc, "task-doc-body");
        body.focusEditor();
        const field = findChild(body, "md-block-field");
        tryVerify(() => field.visible && field.activeFocus, 1000, "no block open for editing");
        compare(field.text, "first line");
        keyClick(Qt.Key_End);
        typeText(" more");
        doc.flush();
        compare(AppController.taskById(id).desc, "first line more\n\n- [ ] item");
        // Down at the block's end goes to the next block.
        keyClick(Qt.Key_Down);
        tryCompare(field, "text", "- [ ] item");
        // First Esc leaves the block, the second the document.
        keyClick(Qt.Key_Escape);
        verify(!field.visible);
        verify(doc.opened);
    }

    function test_empty_properties_are_not_shown() {
        const id = mkTask("chips probe");
        const doc = make();
        doc.open(id);
        verify(!findChild(doc, "task-doc-due").visible, "an empty due date was shown");
        verify(!findChild(doc, "task-doc-estimate").visible);
        verify(findChild(doc, "task-doc-add").visible, "no + property");
        verify(findChild(doc, "task-doc-status").visible);
    }

    function test_a_deleted_task_closes_the_document() {
        const id = mkTask("gone probe");
        const doc = make();
        doc.open(id);
        AppController.deleteTask(id);
        tryVerify(() => !doc.opened, 1000, "the document stayed on a deleted task");
    }

    function test_slash_offers_blocks() {
        const id = mkTask("slash probe");
        const doc = make();
        doc.open(id);
        const body = findChild(doc, "task-doc-body");
        body.focusEditor();
        const field = findChild(body, "md-block-field");
        tryVerify(() => field.activeFocus, 1000);
        keyClick(Qt.Key_Slash);
        const menu = findChild(body, "md-slash-menu");
        tryVerify(() => menu.opened, 1000, "/ did not open the insert menu");
        menu.itemAt(0).triggered();
        compare(field.text, "- [ ] ");
    }
}
