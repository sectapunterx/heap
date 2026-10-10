// Names a saved view: "Save as view" and "Rename" (X-Dlg-Small). The fact
// line says where it will appear and its key; Name and Query (mono) are the
// fields. Enter saves, Esc cancels — a saved view costs nothing to make.
import QtQuick
import QtQuick.Layouts
import TodoCpp

SmallDialog {
    id: root
    objectName: "saved-view-name-dialog"

    // "save" | "rename" | "edit" (name and query of a saved view)
    property string mode: "save"
    // The Alt digit the view will get (0 = none, past 9).
    property int slot: 0
    readonly property alias text: nameField.text
    readonly property alias query: queryField.text

    // Emitted with the trimmed name; the dialog closes itself. `query` holds
    // what the Query field says by then.
    signal named(string name)

    title: root.mode === "rename" ? I18n.t("savedview.dialog.renameTitle")
         : root.mode === "edit" ? I18n.t("savedview.dialog.editTitle") : I18n.t("savedview.dialog.saveTitle")
    fact: root.slot > 0 && root.slot <= 9 ? I18n.t("savedview.dialog.fact").arg(root.slot) : I18n.t("savedview.dialog.factNoKey")

    function openFor(mode, name, query, slot) {
        root.mode = mode;
        root.slot = slot || 0;
        nameField.text = name || "";
        queryField.text = query || "";
        open();
        // Now, not on a later tick: a quick first keystroke would otherwise
        // land before the select-all and be replaced by it.
        nameField.focusField();
    }

    function submit() {
        const name = nameField.text.trim();
        if (name.length === 0) return;
        root.close();
        root.named(name);
    }
    onAccepted: root.submit()

    DialogField {
        id: nameField
        fieldName: "saved-view-name-field"
        label: I18n.t("savedview.dialog.name")
        placeholderText: I18n.t("savedview.dialog.placeholder")
        maximumLength: 60
        onAccepted: root.submit()
    }
    DialogField {
        id: queryField
        fieldName: "saved-view-query-field"
        visible: root.mode !== "rename"
        label: I18n.t("savedview.dialog.query")
        mono: true
        onAccepted: root.submit()
    }

    buttons: [
        PillButton {
            objectName: "saved-view-cancel"
            text: I18n.t("common.cancel")
            onClicked: root.close()
        },
        PillButton {
            objectName: "saved-view-save"
            primary: true
            enabled: nameField.text.trim().length > 0
            text: I18n.t("editor.btn.save")
            onClicked: root.submit()
        }
    ]
}
