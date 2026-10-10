// 0.8.1 "editor & people" (R2-024, R2-042, R2-063, R2-069, DG-151, DG-002):
// the sheets' rows and keys, the add-person row, Esc keeping the quick note's
// draft, the profile delete confirmation, the people dialog's linked blocks.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "EditorPeople081"
    when: windowShown
    visible: true
    width: 900
    height: 700

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }
    function savePerson(id, name, role) {
        AppController.deletePerson(id);
        const d = AppController.newPersonDraft();
        d.id = id; d.name = name; d.role = role || "";
        verify(AppController.savePerson(d));
    }

    // R2-024: the six rows of the sheet, with the markdown keys on the right.
    function test_slash_menu_rows() {
        const ed = make('import TodoCpp; MdBlockEditor { width: 600; height: 400 }');
        const menu = findChild(ed, "md-slash-menu");
        verify(menu);
        const names = [];
        for (let i = 0; i < menu.count; i++) names.push(menu.itemAt(i).objectName);
        compare(names, ["md-slash-check", "md-slash-code", "md-slash-task", "md-slash-file", "md-slash-table", "md-slash-ref"]);
        compare(menu.itemAt(0).keyText, "[]");
        compare(menu.itemAt(1).keyText, "```");
        compare(menu.itemAt(2).keyText, "[[");
    }

    // The "/" is typed; Esc leaves it, a pick replaces it.
    function test_slash_typed_then_replaced() {
        const ed = make('import TodoCpp; MdBlockEditor { width: 600; height: 400 }');
        ed.focusEditor();
        const field = findChild(ed, "md-block-field");
        tryVerify(() => field.activeFocus, 1000);
        keyClick(Qt.Key_Slash);
        const menu = findChild(ed, "md-slash-menu");
        tryVerify(() => menu.opened, 1000);
        compare(field.text, "/");
        compare(menu.currentIndex, 0, "the first row is preselected");
        menu.itemAt(5).triggered();
        compare(field.text, "[](https://)");
        compare(field.cursorPosition, 1);
    }

    // R2-042: name left, role right, and the add row last.
    function test_mention_add_row() {
        savePerson("ep.oleg", "Олег Т.", "Tech Lead");
        const ac = make('import TodoCpp; MentionAutocomplete { }');
        const f = make('import QtQuick.Controls; TextField { width: 220 }');
        ac.target = f;
        f.text = "Спросить @ол";
        f.cursorPosition = f.text.length;
        ac.refresh();
        const list = ac._suggestions;
        verify(list.length >= 2);
        const oleg = list.find(x => x.id === "ep.oleg");
        verify(oleg);
        compare(oleg.role, "Tech Lead");
        verify(list[list.length - 1].add, "the last row adds a person");
        compare(list[list.length - 1].name, "ол");
        // Enter on an untouched list never makes a person.
        ac._selectedIdx = list.length - 1;
        compare(ac.accept(), false);
        // A click does.
        const before = AppController.people.rowCount();
        verify(ac.accept(true));
        compare(AppController.people.rowCount(), before + 1);
        const handle = f.text.substring("Спросить @".length).trim();
        compare(AppController.personById(handle).name, "Ол", "the mention names the new person");
        AppController.deletePerson(handle);
    }

    // R2-063: the person menu's header and rows.
    function test_person_menu() {
        savePerson("ep.masha", "Маша К.", "QA");
        const m = make('import TodoCpp; PersonMenu { }');
        m.openFor({ id: "ep.masha" });
        tryVerify(() => m.opened, 1000);
        const head = findChild(m, "menu-header");
        compare(head.text, "Маша К. · QA");
        verify(findChild(m, "person-menu-wrote"));
        verify(findChild(m, "person-menu-delete").danger);
        m.close();
    }

    // DG-151: delete asks, and only the typed name unlocks the button.
    function test_profile_delete_confirmation() {
        const d = make('import TodoCpp; ProfileDeleteDialog { }');
        d.openFor(AppController.activeProfileId);
        tryVerify(() => d.opened, 1000);
        const ok = findChild(d, "profile-delete-ok");
        compare(ok.enabled, false);
        const field = findChild(d, "profile-delete-confirm");
        field.text = d.profileName;
        compare(ok.enabled, true);
        verify(findChild(d, "small-dialog-fact").text.length > 0);
        d.close();
    }

    // R2-069: no buttons; Esc closes and the draft stays.
    function test_quick_note_esc_keeps_draft() {
        AppController.setQuickNoteDraft("", "");
        const qn = make('import TodoCpp; QuickCaptureNotesPopup { }');
        qn.open();
        tryVerify(() => qn.opened, 1000);
        const ed = findChild(qn, "quicknote-editor");
        tryVerify(() => ed.activeFocus, 1000);
        keyClick(Qt.Key_A);
        keyClick(Qt.Key_Escape);
        tryVerify(() => !qn.opened, 1000);
        qn.open();
        tryVerify(() => qn.opened, 1000);
        compare(ed.text, "a", "the draft came back");
        verify(findChild(qn, "quick-note-hint"));
        ed.text = "";
        qn.close();
        AppController.setQuickNoteDraft("", "");
    }

    // DG-002: the linked blocks are hidden when there is nothing to show.
    function test_people_dialog_hides_empty_blocks() {
        savePerson("ep.nolinks", "Ни Кто", "");
        const dlg = make('import TodoCpp; PeopleDialog { }');
        dlg.showFor("ep.nolinks");
        tryVerify(() => dlg.opened, 1000);
        compare(dlg.linkedTasks.length, 0);
        compare(dlg.meetings.length, 0);
        compare(findChild(dlg, "people-dialog-task"), null);
        dlg.close();
    }
}
