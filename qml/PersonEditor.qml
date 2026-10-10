// A person (X-Dlg-Small "Человек"): Name and What to ask, for "Кому
// написать" and @mentions. New and edit alike. The handle is made from the
// name; role, state and colour are kept as they are (they come from an
// import or from the Today rail).
import QtQuick
import QtQuick.Layouts
import TodoCpp

SmallDialog {
    id: root
    objectName: "person-editor"

    property var draft: ({})
    property bool isNew: false
    // Why the last save was refused; the dialog stays open on the draft.
    property string _error: ""

    title: I18n.t("editor.person.title")
    fact: I18n.t("editor.person.fact")

    function showFor(initialDraft) {
        draft = initialDraft || {};
        isNew = !!draft._isNew || !(draft.id && String(draft.id).length > 0);
        nameField.text = draft.name || "";
        questionField.text = draft.question || "";
        _error = "";
        open();
        if ((draft.name || "").length > 0) questionField.focusField();
        else nameField.focusField();
    }

    function _save() {
        const name = nameField.text.trim();
        if (name.length === 0) {
            root._error = I18n.t("editor.person.err.name");
            nameField.input.forceActiveFocus();
            return;
        }
        const d = {
            _isNew: root.isNew,
            _contactKey: root.draft._contactKey || "",
            _createContact: !!root.draft._createContact,
            _originalId: root.isNew ? "" : (root.draft.id || ""),
            // A new person's handle comes from the name and is free by
            // construction; an existing one keeps theirs.
            id: root.isNew ? AppController.suggestPersonId(name, "") : root.draft.id,
            name: name,
            role: root.draft.role || "",
            question: questionField.text.trim(),
            state: root.draft.state || "todo",
            color: root.draft.color || Theme.swatches[0]
        };
        if (!AppController.savePerson(d)) {
            root._error = I18n.t("editor.err.refused");
            return;
        }
        root.close();
    }
    onAccepted: root._save()

    DialogField {
        id: nameField
        fieldName: "pe-name"
        label: I18n.t("editor.label.name")
        onAccepted: questionField.focusField()
        onTextChanged: root._error = ""
    }
    DialogField {
        id: questionField
        fieldName: "pe-question"
        label: I18n.t("editor.label.question")
        onAccepted: root._save()
    }
    Text {
        objectName: "pe-error"
        visible: root._error.length > 0
        Layout.fillWidth: true
        text: root._error
        color: Theme.danger
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsSm
        wrapMode: Text.Wrap
    }

    buttons: [
        PillButton {
            objectName: "pe-cancel"
            text: I18n.t("common.cancel")
            onClicked: root.close()
        },
        PillButton {
            objectName: "pe-save"
            primary: true
            text: I18n.t("editor.btn.save")
            onClicked: root._save()
        }
    ]
}
