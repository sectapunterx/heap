// MentionAutocomplete (qml/MentionAutocomplete.qml) contract tests.
//
// Drives the trigger-range parser, the people/ticket suggestion filters and
// the in-place accept() against a live AppController (people + tasks). The
// component has no objectNames and its delegate declares `required property`,
// so there are no click-driven tests — API level only.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "MentionAutocomplete"
    when: windowShown
    visible: true
    width: 500
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function makeAc() {
        return make('import TodoCpp; MentionAutocomplete { }');
    }

    function makeField() {
        return make('import QtQuick.Controls; TextField { width: 220 }');
    }

    function findById(list, id) {
        for (let i = 0; i < list.length; ++i)
            if (list[i].id === id) return list[i];
        return null;
    }

    // ── smoke + defaults ──────────────────────────────────────────────

    function test_smoke_load() {
        const ac = makeAc();
        verify(ac !== null, "MentionAutocomplete failed to instantiate");
        compare(ac.maxRows, 8);
        compare(ac.enablePeople, true);
        compare(ac.enableTickets, true);
        compare(ac._suggestions.length, 0);
        compare(ac._trigger, "");
        compare(ac.isOpen, false);   // no suggestions → closed
    }

    // ── _currentTriggerRange(): the caret-walk parser ────────────────

    // "@" mid-text after a space → people trigger, correct span + prefix.
    function test_trigger_range_person_midtext() {
        const ac = makeAc();
        const f = makeField();
        f.text = "hi @jo";       // @ at index 3, prefix "jo"
        f.cursorPosition = 6;
        ac.target = f;

        const r = ac._currentTriggerRange();
        verify(r !== null, "@jo must be recognised as a trigger");
        compare(r.trigger, "@");
        compare(r.start, 3);     // index of the '@'
        compare(r.end, 6);       // caret
        compare(r.prefix, "jo");
    }

    // Trigger at the very start of the document (no lead char to inspect).
    function test_trigger_range_at_start_of_text() {
        const ac = makeAc();
        const f = makeField();
        f.text = "@bo";
        f.cursorPosition = 3;
        ac.target = f;

        const r = ac._currentTriggerRange();
        verify(r !== null, "@bo at start must be recognised");
        compare(r.trigger, "@");
        compare(r.start, 0);
        compare(r.end, 3);
        compare(r.prefix, "bo");
    }

    // "#" ticket trigger after whitespace.
    function test_trigger_range_ticket() {
        const ac = makeAc();
        const f = makeField();
        f.text = "see #he";      // # at index 4, prefix "he"
        f.cursorPosition = 7;
        ac.target = f;

        const r = ac._currentTriggerRange();
        verify(r !== null, "#he must be recognised as a ticket trigger");
        compare(r.trigger, "#");
        compare(r.start, 4);
        compare(r.end, 7);
        compare(r.prefix, "he");
    }

    // A '@' glued to a preceding handle char (an e-mail) must NOT trigger —
    // the lead char before '@' is 'a', not whitespace/punctuation.
    function test_trigger_range_rejects_email_lead() {
        const ac = makeAc();
        const f = makeField();
        f.text = "mail a@b";     // '@' at 6, lead char 'a' at 5
        f.cursorPosition = 8;
        ac.target = f;

        verify(ac._currentTriggerRange() === null,
               "a@b (e-mail) must not open the mention dropdown");
    }

    // enablePeople / enableTickets gate the corresponding trigger to null.
    function test_trigger_range_respects_enable_flags() {
        const ac = makeAc();
        const f = makeField();
        ac.target = f;

        ac.enablePeople = false;
        f.text = "@jo";
        f.cursorPosition = 3;
        verify(ac._currentTriggerRange() === null,
               "@ trigger must be suppressed when enablePeople is false");

        ac.enablePeople = true;
        ac.enableTickets = false;
        f.text = "#he";
        f.cursorPosition = 3;
        verify(ac._currentTriggerRange() === null,
               "# trigger must be suppressed when enableTickets is false");
    }

    // No trigger char / no target → null range and refresh() clears cleanly.
    function test_trigger_range_and_refresh_null_cases() {
        const ac = makeAc();

        // No target at all.
        verify(ac._currentTriggerRange() === null, "null target → null range");
        ac.refresh();
        compare(ac._suggestions.length, 0, "refresh with no target clears suggestions");

        // Target with plain text, no @/# before the caret.
        const f = makeField();
        f.text = "plain text";
        f.cursorPosition = 5;
        ac.target = f;
        verify(ac._currentTriggerRange() === null, "plain text → null range");
        ac.refresh();
        compare(ac._suggestions.length, 0, "refresh with no trigger clears suggestions");
    }

    // ── _peopleSuggestions() / _ticketSuggestions(): filter + role mapping ──

    // A person is matched by id-prefix and name-substring, and the returned
    // {id,name} reads the right roles (id=UserRole+1, name=UserRole+2). A
    // role swap would surface here.
    function test_people_suggestions_match_and_roles() {
        const pid = "acatokp.one";
        const pname = "AcatokpNamedPerson";
        AppController.deletePerson(pid);   // clear any leftover from a prior run
        AppController.savePerson({ _isNew: true, id: pid, name: pname, state: "todo" });

        const ac = makeAc();

        // id-prefix match (query is pre-lowercased by the contract).
        let out = ac._peopleSuggestions("acatokp");
        let hit = findById(out, pid);
        verify(hit !== null, "person not found by id-prefix query");
        compare(hit.name, pname, "name role (UserRole+2) mismapped");

        // name-substring match on a token unique to the name.
        out = ac._peopleSuggestions("named");
        verify(findById(out, pid) !== null, "person not found by name-substring query");

        // A non-matching query excludes the person.
        out = ac._peopleSuggestions("zzznomatchzzz");
        verify(findById(out, pid) === null, "non-matching query must not return the person");

        AppController.deletePerson(pid);
    }

    // A ticket is matched by title-substring, and the entry's `name` field
    // carries the TITLE (tasks role UserRole+2 = TitleRole).
    function test_ticket_suggestions_match_and_roles() {
        const draft = AppController.newTaskDraft("todo");
        draft.title = "EtprobeUniqueTicket";
        AppController.saveTask(draft);
        const tid = draft.id;
        verify(tid && tid.length > 0, "saved task must expose an id");

        const ac = makeAc();

        let out = ac._ticketSuggestions("etprobe");
        let hit = findById(out, tid);
        verify(hit !== null, "ticket not found by title-substring query");
        compare(hit.name, "EtprobeUniqueTicket", "ticket entry.name must carry the title");

        out = ac._ticketSuggestions("zzznomatchzzz");
        verify(findById(out, tid) === null, "non-matching query must not return the ticket");

        AppController.deleteTask(tid);
    }

    // ── refresh(): wires the parser to the suggestion source ─────────

    // Typing "@<prefix>" against a real person populates _suggestions, sets
    // the live trigger and resets the selection to the top. Reads plain
    // properties only, so it does not depend on the popup actually opening.
    function test_refresh_populates_people_trigger() {
        const pid = "brefreshp.one";
        AppController.deletePerson(pid);
        AppController.savePerson({ _isNew: true, id: pid, name: "BrefreshpPerson", state: "todo" });

        const ac = makeAc();
        const f = makeField();
        f.text = "@brefreshp";
        f.cursorPosition = f.text.length;
        ac.target = f;

        ac.refresh();
        compare(ac._trigger, "@", "refresh must record the active trigger");
        compare(ac._selectedIdx, 0, "refresh must reset the selection to the top");
        verify(ac._suggestions.length >= 1, "refresh must populate suggestions");
        verify(findById(ac._suggestions, pid) !== null, "the typed person must be suggested");

        ac.dismiss();
        AppController.deletePerson(pid);
    }

    // ── open-state behaviours (moveSelection / accept require isOpen) ──

    // moveSelection clamps _selectedIdx to [0, len-1] while the dropdown is
    // open. Two matching people guarantee at least two rows to move between.
    function test_move_selection_clamps_when_open() {
        const a = "cmovep.aaa", b = "cmovep.bbb";
        AppController.deletePerson(a);
        AppController.deletePerson(b);
        AppController.savePerson({ _isNew: true, id: a, name: "CmovepAaa", state: "todo" });
        AppController.savePerson({ _isNew: true, id: b, name: "CmovepBbb", state: "todo" });

        const ac = makeAc();
        const f = makeField();
        f.text = "@cmovep";
        f.cursorPosition = f.text.length;
        ac.target = f;
        ac.refresh();

        // The visible binding follows _suggestions; the popup opens in the
        // shown test window (proven by the DatePickerPopup/PersonEditor suites).
        tryVerify(function() { return ac.isOpen; }, 3000, "dropdown did not open");
        const n = ac._suggestions.length;
        verify(n >= 2, "expected at least two matching people");

        ac.moveSelection(+1);
        compare(ac._selectedIdx, 1, "down must advance the selection");
        ac.moveSelection(+50);
        compare(ac._selectedIdx, n - 1, "down must clamp at the last row");
        ac.moveSelection(-50);
        compare(ac._selectedIdx, 0, "up must clamp at the first row");

        ac.dismiss();
        AppController.deletePerson(a);
        AppController.deletePerson(b);
    }

    // accept() rewrites the trigger span in place with the canonical "@<id> "
    // and lands the caret after the insert (HEAP-65: edit via remove()+insert(),
    // never a whole-text reassignment).
    function test_accept_inserts_canonical_id_in_place() {
        const pid = "daccept.person";
        AppController.deletePerson(pid);
        AppController.savePerson({ _isNew: true, id: pid, name: "DacceptPerson", state: "todo" });

        const ac = makeAc();
        const f = makeField();
        f.text = "hi @daccept end";   // '@' at 3, prefix "daccept" ends at 11
        f.cursorPosition = 11;
        ac.target = f;
        ac.refresh();

        tryVerify(function() { return ac.isOpen; }, 3000, "dropdown did not open");
        verify(findById(ac._suggestions, pid) !== null, "the typed person must be the sole match");
        compare(ac._selectedIdx, 0);

        const ok = ac.accept();
        verify(ok, "accept must report success when a suggestion is committed");
        compare(f.text, "hi @daccept.person  end",
                "accept must splice the canonical id in place, keeping the tail");
        compare(f.cursorPosition, 19,
                "caret must land after the inserted mention, not at 0");
        compare(ac._suggestions.length, 0, "accept must clear the live suggestion list");
        compare(ac._trigger, "", "accept must clear the live trigger");

        AppController.deletePerson(pid);
    }

    // When closed, accept() is a no-op returning false, moveSelection does not
    // touch the selection, and dismiss() resets the transient state.
    function test_accept_and_move_noop_when_closed() {
        const ac = makeAc();
        compare(ac.isOpen, false);

        compare(ac.accept(), false, "accept must return false while closed");
        ac.moveSelection(+1);
        compare(ac._selectedIdx, 0, "moveSelection must be inert while closed");

        ac.dismiss();
        compare(ac._suggestions.length, 0);
        compare(ac._trigger, "");
    }
}
