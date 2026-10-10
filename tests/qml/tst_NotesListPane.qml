// The list of notes beside the editor.
//
// Notes were one document per profile, so this pane had nothing to show and did
// not exist. The grouping is the part worth pinning: pinned first, then
// folders, then loose notes — the order somebody scanning for a note uses,
// rather than the order they were created.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "NotesListPane"
    when: windowShown
    visible: true
    width: 400
    height: 700

    Item { id: host; anchors.fill: parent }

    property var seeded: []
    property string savedActive: ""

    function init() {
        tc.savedActive = AppController.activeNoteId;
    }

    function note(title, opts) {
        const id = AppController.newNote(title, (opts && opts.folder) || "");
        if (opts && opts.pinned) AppController.setNotePinned(id, true);
        if (opts && opts.body !== undefined) AppController.setNoteBody(id, opts.body);
        tc.seeded.push(id);
        return id;
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteNote(tc.seeded[i]);
        tc.seeded = [];
        if (tc.savedActive.length > 0) AppController.activeNoteId = tc.savedActive;
    }

    function makePane() {
        const p = createTemporaryQmlObject(
            'import TodoCpp; NotesListPane { width: 240; height: 600 }', host);
        verify(p !== null);
        return p;
    }

    // Only rows that are notes; the headers are furniture.
    function titlesOf(pane) {
        const out = [];
        for (let i = 0; i < pane.rows.length; i++)
            if (pane.rows[i].kind === "note") out.push(pane.rows[i].note.title);
        return out;
    }

    function headersOf(pane) {
        const out = [];
        for (let i = 0; i < pane.rows.length; i++)
            if (pane.rows[i].kind === "header") out.push(pane.rows[i].label);
        return out;
    }

    function test_a_note_appears_in_the_list() {
        note("alpha probe");

        const pane = makePane();

        verify(titlesOf(pane).indexOf("alpha probe") >= 0);
    }

    // A pinned note is what the reader wants first, whatever it is called.
    function test_pinned_notes_come_first() {
        note("zzz loose probe");
        note("aaa pinned probe", { pinned: true });

        const pane = makePane();
        const titles = titlesOf(pane);

        compare(titles[0], "aaa pinned probe");
        verify(headersOf(pane).length > 0);
    }

    // A pinned note belongs under Pinned, not also under its folder: it would
    // otherwise be in the list twice.
    function test_a_pinned_note_is_not_also_in_its_folder() {
        note("dual probe", { folder: "meetings", pinned: true });

        const pane = makePane();
        let seen = 0;
        for (let i = 0; i < pane.rows.length; i++)
            if (pane.rows[i].kind === "note" && pane.rows[i].note.title === "dual probe") seen++;

        compare(seen, 1);
    }

    function test_folders_become_headers() {
        note("filed probe", { folder: "meetings/2026" });

        const pane = makePane();

        verify(headersOf(pane).indexOf("meetings/2026") >= 0);
    }

    function test_notes_in_a_folder_follow_its_header() {
        note("filed probe", { folder: "zeta" });

        const pane = makePane();
        let headerAt = -1, noteAt = -1;
        for (let i = 0; i < pane.rows.length; i++) {
            if (pane.rows[i].kind === "header" && pane.rows[i].label === "zeta") headerAt = i;
            if (pane.rows[i].kind === "note" && pane.rows[i].note.title === "filed probe") noteAt = i;
        }
        verify(headerAt >= 0 && noteAt > headerAt);
    }

    function test_the_filter_narrows_the_list() {
        note("findme probe");
        note("somethingelse probe");

        const pane = makePane();
        pane.filter = "findme";

        compare(titlesOf(pane), ["findme probe"]);
    }

    // The excerpt is searchable too: people remember what a note said more
    // often than what they called it.
    function test_the_filter_matches_the_body() {
        note("opaque title probe", { body: "# opaque title probe\n\na memorable sentence" });

        const pane = makePane();
        pane.filter = "memorable";

        compare(titlesOf(pane).length, 1);
    }

    function test_a_filter_matching_nothing_empties_the_list() {
        note("probe");

        const pane = makePane();
        pane.filter = "zzzz-no-such-note";

        compare(pane.rows.length, 0);
    }

    // Creating and deleting have to reach the list without it being rebuilt by
    // hand, or the pane goes stale the moment anything changes.
    function test_the_list_follows_the_model() {
        const pane = makePane();
        const before = titlesOf(pane).length;

        const id = note("late probe");

        // Coalesced into one rebuild per event-loop turn (see rebuildNow).
        tryVerify(function () { return titlesOf(pane).length === before + 1; });

        AppController.deleteNote(id);
        tc.seeded.splice(tc.seeded.indexOf(id), 1);

        tryVerify(function () { return titlesOf(pane).length === before; });
    }

    // Audit KNOW-17: every debounced save of the open note rebuilt the list
    // and threw the reader back to the top. A save that changes nothing the
    // list shows must leave the rows — and the scroll — alone.
    function test_a_body_save_does_not_rebuild_or_scroll_the_list() {
        for (let i = 0; i < 40; i++) note("scroll probe " + (i < 10 ? "0" + i : i));
        const id = note("scroll probe zz", { body: "# scroll probe zz\n\nfirst line" });
        const pane = makePane();
        const list = findChild(pane, "note-list");
        list.contentY = 300;
        const before = pane.rows;
        AppController.setNoteBody(id, "# scroll probe zz\n\nfirst line\n\nmore typed below");
        wait(50);
        verify(pane.rows === before, "the rows were rebuilt for a change the list does not show");
        compare(list.contentY, 300);
    }

    // Creating many notes in a row rebuilds the list once, not once per note.
    function test_many_inserts_rebuild_once() {
        const pane = makePane();
        let rebuilt = 0;
        pane.rowsChanged.connect(function () { rebuilt++; });
        for (let i = 0; i < 30; i++) note("bulk probe " + i);
        tryVerify(function () { return titlesOf(pane).indexOf("bulk probe 29") >= 0; });
        verify(rebuilt <= 2, "rebuilt " + rebuilt + " times");
    }

    function test_activating_a_note_reports_its_id() {
        const id = note("activate probe");
        const pane = makePane();
        let got = "";
        pane.noteActivated.connect(function (x) { got = x; });

        const row = findChild(pane, "note-row-" + id);
        verify(row !== null, "the row must render");
        pane.noteActivated(id);

        compare(got, id);
    }

    // Stepping is how the keyboard moves between notes; headers are not
    // somewhere the selection can land.
    function test_stepping_skips_headers() {
        const a = note("aaa step probe", { pinned: true });
        const b = note("bbb step probe", { folder: "folder" });
        const pane = makePane();
        pane.filter = "step probe";
        let got = "";
        pane.noteActivated.connect(function (x) { got = x; });

        AppController.activeNoteId = a;
        pane.step(1);

        compare(got, b);
    }

    // Design audit DES-3: the list is on the Tab path, the arrows walk it and
    // the menu key opens the open note's menu (pin, rename, delete).
    function test_the_keyboard_walks_the_list_and_opens_the_menu() {
        const a = note("aaa keys probe");
        const b = note("bbb keys probe");
        const pane = makePane();
        pane.filter = "keys probe";
        let got = "";
        pane.noteActivated.connect(function (x) { got = x; AppController.activeNoteId = x; });
        AppController.activeNoteId = a;

        const list = findChild(pane, "note-list");
        verify(list.activeFocusOnTab, "the note list is not on the Tab path");
        list.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Down);
        compare(got, b);

        const row = pane._activeRowItem();
        verify(row !== null);
        keyClick(Qt.Key_Menu);
        tryVerify(function () { return row.menu.opened; }, 1000, "the menu key did not open the note's menu");
        row.menu.close();
    }

    // APP-116: dragging one note onto another merges it in, the dragged one's
    // text below the target's.
    function test_dragging_a_note_onto_another_merges_them() {
        const target = note("aaa merge probe", { body: "# aaa merge probe\n\ntarget text" });
        const source = note("bbb merge probe", { body: "# bbb merge probe\n\nsource text" });
        const pane = makePane();
        pane.filter = "merge probe";
        waitForRendering(pane);
        const from = findChild(pane, "note-row-" + source);
        const to = findChild(pane, "note-row-" + target);
        verify(from !== null && to !== null);

        const start = from.mapToItem(pane, from.width / 2, from.height / 2);
        const end = to.mapToItem(pane, to.width / 2, to.height / 2);
        mousePress(pane, start.x, start.y);
        for (let i = 1; i <= 8; i++)
            mouseMove(pane, start.x, start.y + (end.y - start.y) * i / 8);
        verify(findChild(pane, "note-drag-ghost").visible, "no drag ghost while dragging");
        mouseRelease(pane, end.x, end.y);

        tryVerify(function () { return AppController.notes.indexOfId(source) < 0; }, 1000, "the dragged note is still there");
        const body = AppController.noteBody(target);
        verify(body.indexOf("target text") < body.indexOf("## bbb merge probe"), body);
        verify(body.indexOf("source text") > 0, body);
        verify(!findChild(pane, "note-drag-ghost").visible);
    }

    // A note dropped on itself stays as it is.
    function test_dropping_a_note_on_itself_does_nothing() {
        const only = note("self merge probe", { body: "just me" });
        const pane = makePane();
        pane.filter = "self merge probe";
        waitForRendering(pane);
        const row = findChild(pane, "note-row-" + only);
        mousePress(row, 20, 10);
        for (let i = 1; i <= 6; i++) mouseMove(row, 20, 10 + i * 4);
        mouseRelease(row, 20, 30);
        verify(AppController.notes.indexOfId(only) >= 0);
        compare(AppController.noteBody(only), "just me");
    }

    function test_stepping_stops_at_the_ends() {
        const a = note("only step probe");
        const pane = makePane();
        pane.filter = "only step probe";
        let got = "";
        pane.noteActivated.connect(function (x) { got = x; });

        AppController.activeNoteId = a;
        pane.step(-1);

        compare(got, a, "stepping off the top stays put rather than wrapping");
    }

    // ── The catalogue in Knowledge (DG-070, DG-073) ──────────────────
    function withDocs(blob, fn) {
        const saved = AppController.docsState;
        AppController.docsState = JSON.stringify(blob);
        try { fn(); } finally { AppController.docsState = saved; }
    }
    function kindsOf(pane, kind) {
        return pane.rows.filter(function (r) { return r.kind === kind; });
    }
    readonly property var catalogue: ({
        sections: [{ id: "s", title: "S", items: [
            { ref: "RFC 9110", title: "HTTP probe", url: "https://example.org/9110", pinned: true },
            { ref: "RFC 8259", title: "JSON probe", url: "https://example.org/8259" }
        ] }],
        snippets: [{ title: "stand probe", lang: "sh", code: "make up", tags: [] }],
        contacts: [{ name: "Ada probe", role: "eng", mattermost: "@ada" }]
    })

    function test_only_pinned_references_are_listed_at_rest() {
        withDocs(tc.catalogue, function () {
            const pane = makePane();
            const refs = kindsOf(pane, "ref");
            compare(refs.length, 1);
            compare(refs[0].name, "HTTP probe");
            compare(headersOf(pane)[0], I18n.t("notes.pinned"));
            compare(kindsOf(pane, "snippet").length, 1);
            compare(kindsOf(pane, "contact").length, 0, "contacts only come up in a search");
        });
    }

    function test_a_search_reaches_the_whole_catalogue() {
        withDocs(tc.catalogue, function () {
            const pane = makePane();
            pane.setFilter("probe");
            const refs = kindsOf(pane, "ref");
            compare(refs.length, 2, "an unpinned reference is found");
            verify(headersOf(pane).indexOf(I18n.t("knowledge.refs")) >= 0);
            compare(kindsOf(pane, "contact").length, 1);
            compare(kindsOf(pane, "contact")[0].handle, "@ada");
        });
    }

    function test_pinning_a_reference_writes_only_its_flag() {
        withDocs(tc.catalogue, function () {
            const pane = makePane();
            pane.setRefPinned(0, 1, true);
            const d = JSON.parse(AppController.docsState);
            verify(d.sections[0].items[1].pinned === true);
            compare(d.sections[0].items[1].title, "JSON probe");
            compare(d.contacts.length, 1, "the rest of the blob is kept");
            pane.setRefPinned(0, 0, false);
            verify(JSON.parse(AppController.docsState).sections[0].items[0].pinned === undefined);
        });
    }

    function test_notes_are_listed_newest_first() {
        const a = note("older probe");
        wait(20);
        const b = note("newer probe");
        const pane = makePane();
        const t = titlesOf(pane);
        verify(t.indexOf("newer probe") < t.indexOf("older probe"));
    }
}
