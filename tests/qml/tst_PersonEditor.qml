// PersonEditor contract tests (smoke + public API).
//
// Covers standalone instantiation, the showFor() seeding paths (new draft,
// existing draft, id auto-derive re-arm, null fallback) and the Escape close
// policy, and the refusal of a taken id (SHELL-24). The component declares no
// signals, so there are no signal-contract tests — API level only.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "PersonEditor"
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

    // Smoke: the popup instantiates standalone against the live module, with
    // the documented defaults and the fixed state/swatch catalogues.
    function test_smoke_load() {
        const pe = make('import TodoCpp; PersonEditor { }');
        compare(pe.isNew, false);
        compare(pe._idAutoDerived, true);
        // "idle" leads: it is the neutral state an imported contact lands in,
        // and the one that keeps the rail's pending count honest.
        compare(pe.states.length, 4);
        compare(pe.states[0], "idle");
        compare(pe.states[1], "todo");
        compare(pe.states[2], "pinged");
        compare(pe.states[3], "replied");
        compare(pe.swatches.length, Theme.swatches.length);
        compare(pe.swatches[0], "#5cc2dd");
    }

    // The swatch list used to be called `palette`, which is QQuickPopup's own
    // property — the one every Control inside the dialog resolves its colours
    // through. Shadowing it handed those controls an array of hex strings where
    // they expect a palette, so `palette.text` came back undefined.
    function test_palette_belongs_to_the_control_not_to_the_swatches() {
        const pe = make('import TodoCpp; PersonEditor { }');
        verify(pe.swatches.length > 0, "the swatches must still be reachable");
        compare(pe.palette.length, undefined, "palette must not be an array");
        verify(pe.palette.text !== undefined, "and must still be a usable palette");
    }

    // showFor(new draft): flags isNew, keeps the id auto-derived from the name
    // and opens the popup. Closed again so the modal overlay never leaks into
    // other tests.
    function test_showfor_new_draft_opens() {
        const pe = make('import TodoCpp; PersonEditor { }');
        pe.showFor({ _isNew: true, name: "Draft Person" });
        tryCompare(pe, "opened", true);

        compare(pe.isNew, true);
        compare(pe._idAutoDerived, true);
        compare(pe.draft.name, "Draft Person");

        pe.close();
        tryCompare(pe, "opened", false);
    }

    // showFor(existing draft with id): edit mode — the user's chosen handle is
    // kept, so id auto-derivation must be off.
    function test_showfor_existing_draft() {
        const pe = make('import TodoCpp; PersonEditor { }');
        pe.showFor({ id: "p.probe", name: "Probe", role: "QA",
                     state: "replied", color: "#7da8d9" });
        tryCompare(pe, "opened", true);

        compare(pe.isNew, false);
        compare(pe._idAutoDerived, false);
        compare(pe.draft.id, "p.probe");
        compare(pe.draft.state, "replied");

        pe.close();
        tryCompare(pe, "opened", false);
    }

    // showFor(existing draft without id): a blank id re-arms auto-derivation
    // even in edit mode (the `isNew || idField empty` branch).
    function test_showfor_blank_id_rearms_auto_derive() {
        const pe = make('import TodoCpp; PersonEditor { }');
        pe.showFor({ name: "No Id Yet" });
        tryCompare(pe, "opened", true);

        compare(pe.isNew, false);
        compare(pe._idAutoDerived, true);

        pe.close();
        tryCompare(pe, "opened", false);
    }

    // showFor(null): falls back to an empty draft and still opens.
    function test_showfor_null_defaults() {
        const pe = make('import TodoCpp; PersonEditor { }');
        pe.showFor(null);
        tryCompare(pe, "opened", true);

        compare(pe.isNew, false);
        compare(Object.keys(pe.draft).length, 0);

        pe.close();
        tryCompare(pe, "opened", false);
    }

    // Escape closes the popup — pins the CloseOnEscape half of closePolicy.
    // The popup declares focus: true, so the key lands inside it once open.
    function test_escape_closes() {
        const pe = make('import TodoCpp; PersonEditor { }');
        pe.showFor({ _isNew: true });
        tryCompare(pe, "opened", true);

        keyClick(Qt.Key_Escape);
        tryCompare(pe, "opened", false);
    }

    // A new person with no name is refused by savePerson() without a toast;
    // the editor has to say why itself, not "see the message below" over no
    // message at all.
    function test_new_person_without_a_name_says_so() {
        const before = AppController.people.rowCount();
        const pe = make('import TodoCpp; PersonEditor { }');
        pe.showFor({ _isNew: true });
        tryCompare(pe, "opened", true);
        const nameField = findChild(pe.contentItem, "pe-name");
        nameField.text = "   ";
        pe._save();

        verify(pe.opened, "the editor stays open on the draft");
        const err = findChild(pe.contentItem, "pe-error");
        verify(err.visible);
        compare(err.text, I18n.t("editor.person.err.name"));
        verify(nameField.activeFocus, "the name field is where to fix it");
        compare(AppController.people.rowCount(), before);

        nameField.text = "Named";
        verify(!err.visible, "typing a name clears the message");
        pe.close();
        tryCompare(pe, "opened", false);
    }

    // SHELL-24: a new person typed onto an id someone already has used to
    // replace that person whole. The editor refuses, says who holds the id and
    // stays open on the draft; the existing person is unchanged.
    function test_new_person_on_a_taken_id_is_refused() {
        const victim = "shell24.victim";
        AppController.deletePerson(victim);   // the test profile persists
        verify(AppController.savePerson({ _isNew: true, id: victim, name: "Victim Person",
                                          role: "Tech Lead", question: "keep me", state: "todo" }));
        const before = AppController.people.rowCount();

        const pe = make('import TodoCpp; PersonEditor { }');
        pe.showFor(AppController.newContactDraft("Impostor"));
        tryCompare(pe, "opened", true);
        const idField = findChild(pe.contentItem, "pe-id");
        verify(idField !== null);
        idField.text = victim;
        pe._save();

        verify(pe.opened, "the editor stays open on the refused draft");
        const err = findChild(pe.contentItem, "pe-error");
        verify(err.visible);
        verify(err.text.indexOf("Victim Person") >= 0, err.text);
        const kept = AppController.personById(victim);
        compare(kept.name, "Victim Person");
        compare(kept.role, "Tech Lead");
        compare(kept.question, "keep me");
        compare(AppController.people.rowCount(), before);

        // A free id goes through, and the message goes away as the id changes.
        const freeId = "shell24.impostor";
        AppController.deletePerson(freeId);
        idField.text = freeId;
        verify(!err.visible);
        pe._save();
        tryCompare(pe, "opened", false);
        compare(AppController.personById(freeId).name, "Impostor");
        compare(AppController.personById(victim).name, "Victim Person");
        AppController.deletePerson(freeId);
        AppController.deletePerson(victim);
    }
}
