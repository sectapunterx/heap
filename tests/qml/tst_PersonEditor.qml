// PersonEditor contract tests (smoke + public API).
//
// Covers standalone instantiation, the showFor() seeding paths (new draft,
// existing draft, id auto-derive re-arm, null fallback) and the Escape close
// policy. The component has no objectNames and declares no signals, so there
// are no click-driven or signal-contract tests — API level only.
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
    // the documented defaults and the fixed state/palette catalogues.
    function test_smoke_load() {
        const pe = make('import TodoCpp; PersonEditor { }');
        compare(pe.isNew, false);
        compare(pe._idAutoDerived, true);
        compare(pe.states.length, 3);
        compare(pe.states[0], "todo");
        compare(pe.states[1], "pinged");
        compare(pe.states[2], "replied");
        compare(pe.palette.length, 8);
        compare(pe.palette[0], "#d97a6c");
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
}
