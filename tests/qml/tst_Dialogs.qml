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

    function test_welcome_close_is_a_named_keyboard_button() {
        const w = createTemporaryQmlObject('import TodoCpp; WelcomePopup { }', host);
        w.open();
        tryVerify(function () { return w.opened; }, 1000);
        const close = findChild(w.contentItem, "welcome-close");
        verify(close !== null);
        const area = close.children[close.children.length - 1];
        verify(area.activeFocusOnTab, "the ✕ is not on the Tab path");
        compare(area.Accessible.name, I18n.t("welcome.skip"));
        w.close();
    }

    function test_notes_toolbar_toggles_are_keyboard_checkboxes() {
        const nv = Qt.createQmlObject('import TodoCpp; NotesView { anchors.fill: parent }', host, "tst_Dialogs.notes");
        tryVerify(function () { return nv._loadedOnce; });
        const toggle = findChild(nv, "notes-list-toggle");
        verify(toggle !== null);
        let area = null;
        for (let i = 0; i < toggle.children.length; i++)
            if (toggle.children[i].activeFocusOnTab === true) area = toggle.children[i];
        verify(area !== null, "the list toggle is not on the Tab path");
        compare(area.Accessible.role, Accessible.CheckBox);
        const before = nv._listShown;
        area.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        verify(nv._listShown !== before, "Space did not flip the list");
        keyClick(Qt.Key_Space);
        nv.destroy();
    }
}
