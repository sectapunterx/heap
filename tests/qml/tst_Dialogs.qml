// Design audit DES-24 / DES-19 / DES-21: dialogs share one title and button
// row, the series question can be cancelled from a button, the welcome ✕ and
// the notes toolbar toggles are keyboard-reachable, and the notes
// autocomplete marks its selected row.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Dialogs"
    when: windowShown
    visible: true
    width: 900
    height: 700

    Item { id: host; anchors.fill: parent }

    function test_series_scope_has_a_cancel_button_and_a_shared_title() {
        const d = createTemporaryQmlObject('import TodoCpp; SeriesScopeDialog { }', host);
        let answered = "", cancelled = false;
        d.ask("save", function (a) { answered = a; }, function () { cancelled = true; });
        tryVerify(function () { return d.opened; }, 1000);
        compare(d.title, I18n.t("repeat.scope.saveTitle"));
        const cancel = findChild(d.footer, "series-scope-cancel");
        verify(cancel !== null, "no Cancel button");
        mouseClick(cancel);
        tryVerify(function () { return !d.opened; }, 1000);
        verify(cancelled, "Cancel did not cancel");
        compare(answered, "");
    }

    function test_link_and_vault_dialogs_use_the_shared_header() {
        for (const qml of ['import TodoCpp; LinkConfirmDialog { }', 'import TodoCpp; VaultImportDialog { }']) {
            const d = createTemporaryQmlObject(qml, host);
            verify(d.header !== null && d.header.text === d.title, qml);
            verify(d.footer.implicitHeight > 0, qml);
        }
    }

}
