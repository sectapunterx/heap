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

        compare(titlesOf(pane).length, before + 1);

        AppController.deleteNote(id);
        tc.seeded.splice(tc.seeded.indexOf(id), 1);

        compare(titlesOf(pane).length, before);
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
}
