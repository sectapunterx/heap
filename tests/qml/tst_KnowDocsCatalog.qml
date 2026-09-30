// Docs catalogue entries have ids of their own (audit KNOW-4) and deletions
// share AppController's undo stack (KNOW-23).
//
// Entries used to be found by their Ref. Two entries with no Ref — or the same
// one — were one entry to every operation: editing one overwrote the other,
// deleting one deleted both, and the single pending undo brought back one.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "KnowDocsCatalog"
    when: windowShown
    visible: true
    width: 1000
    height: 700

    Item { id: host; anchors.fill: parent }

    property string _saved: ""

    function init() {
        tc._saved = AppController.docsState;
        AppController.docsState = JSON.stringify({
            sections: [{ id: "refs", title: "Refs", items: [
                { ref: "", title: "First", desc: "one" },
                { ref: "", title: "Second", desc: "two" },
                { ref: "API", title: "Third", desc: "three" },
                { ref: "API", title: "Fourth", desc: "four" }
            ] }],
            snippets: [{ title: "snip", lang: "sh", code: "ls", tags: [] }],
            contacts: [{ name: "Ada", role: "eng" }]
        });
    }
    function cleanup() {
        AppController.docsState = tc._saved;
    }

    function make() {
        const dv = createTemporaryQmlObject('import TodoCpp; DocsView { anchors.fill: parent }', host);
        verify(dv !== null);
        return dv;
    }
    function items(dv) { return dv.sections[0].items; }
    function titles(dv) { return items(dv).map(function (i) { return i.title; }); }

    function test_ids_are_assigned_on_load_and_persisted() {
        const dv = make();
        const ids = items(dv).map(function (i) { return i.id; });
        compare(ids.length, 4);
        for (let i = 0; i < ids.length; i++) verify(!!ids[i], "entry " + i + " has an id");
        compare(new Set(ids).size, 4, "ids are distinct");
        wait(20);
        dv.flushPending();
        const stored = JSON.parse(AppController.docsState).sections[0].items;
        compare(stored[0].id, ids[0], "the migration is written back");
    }

    function test_editing_one_entry_without_a_ref_leaves_the_other() {
        const dv = make();
        const first = items(dv)[0];
        dv.openDocEdit("refs", first);
        const draft = Object.assign({}, first, { title: "First, edited", _sectionId: "refs" });
        dv.saveDoc(draft);
        compare(titles(dv), ["First, edited", "Second", "Third", "Fourth"]);
    }

    function test_editing_one_of_two_entries_with_the_same_ref() {
        const dv = make();
        const fourth = items(dv)[3];
        dv.openDocEdit("refs", fourth);
        dv.saveDoc(Object.assign({}, fourth, { title: "Fourth, edited", _sectionId: "refs" }));
        compare(titles(dv), ["First", "Second", "Third", "Fourth, edited"]);
    }

    function test_deleting_one_entry_without_a_ref_keeps_the_other_and_undo_restores_it() {
        const dv = make();
        dv.deleteDoc("refs", items(dv)[0].id);
        compare(titles(dv), ["Second", "Third", "Fourth"]);
        verify(AppController.hasPendingUndo);
        AppController.undo();
        compare(titles(dv), ["First", "Second", "Third", "Fourth"]);
    }

    function test_undo_is_multi_level_and_global() {
        const dv = make();
        dv.deleteSnippet(0);
        dv.deleteContact(0);
        compare(dv.snippets.length, 0);
        compare(dv.contacts.length, 0);
        AppController.undo();
        compare(dv.contacts.length, 1, "the contact comes back first");
        compare(dv.snippets.length, 0);
        AppController.undo();
        compare(dv.snippets.length, 1, "and the snippet is not lost behind it");
    }

    // 2026-09-30 audit, KNOW-2: an entry saved after a deletion keeps its edit
    // through the deletion's undo and redo. The undo used to put back the
    // whole catalogue as it was before the deletion.
    function test_undoing_a_delete_keeps_a_later_edit_to_another_entry() {
        AppController.clearPendingUndo();
        const dv = make();
        dv.flushPending();
        const first = items(dv)[0].id;
        dv.deleteDoc("refs", first);
        const second = items(dv)[0];
        dv.openDocEdit("refs", second);
        dv.saveDoc(Object.assign({}, second, { title: "EDITED AFTER DELETE", _sectionId: "refs" }));
        dv.flushPending();

        AppController.undo();
        compare(titles(dv), ["First", "EDITED AFTER DELETE", "Third", "Fourth"]);
        compare(items(dv)[0].id, first);
        AppController.redo();
        compare(titles(dv), ["EDITED AFTER DELETE", "Third", "Fourth"]);
    }
}
