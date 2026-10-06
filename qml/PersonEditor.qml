import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 460
    anchors.centerIn: Overlay.overlay

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle { color: Theme.scrim }

    property var draft: ({})
    property bool isNew: false

    // Not `palette`: that is QQuickPopup's own property, which every
    // Control inside this dialog resolves its colours through. Shadowing
    // it with an array of hex strings hands those controls an array where
    // they expect a palette.
    readonly property var swatches: Theme.swatches
    readonly property var states: ["idle", "todo", "pinged", "replied"]
    readonly property var stateLabels: ({
        idle: I18n.t("editor.person.state.idle"),
        todo: I18n.t("editor.person.state.todo"),
        pinged: I18n.t("editor.person.state.pinged"),
        replied: I18n.t("editor.person.state.replied")
    })

    // True while the user has not manually edited idField — keeps the id in
    // sync with the live name. Flips to false on first manual edit so we
    // don't clobber the user's chosen handle.
    property bool _idAutoDerived: true
    // Why the last save was refused; the dialog stays open on the draft.
    property string _error: ""

    function showFor(initialDraft) {
        draft = initialDraft || {};
        isNew = !!draft._isNew;
        nameField.text     = draft.name || "";
        roleField.text     = draft.role || "";
        questionField.text = draft.question || "";
        idField.text       = draft.id || "";
        _error = "";
        _idAutoDerived = isNew || (idField.text.length === 0);
        stateBox.currentIndex = Math.max(0, states.indexOf(draft.state || "todo"));
        const cur = String(draft.color || swatches[0]).toLowerCase();
        let i = 0;
        for (let k = 0; k < swatches.length; k++)
            if (swatches[k].toLowerCase() === cur) { i = k; break; }
        colorSwatch.selectedIndex = i;
        open();
        // Someone picked in PersonPicker arrives with their name, role and id
        // already filled in from the contact — the only thing left to type is
        // what you need from them.
        if ((draft.name || "").length > 0)
            questionField.forceActiveFocus();
        else
            nameField.forceActiveFocus();
    }

    // Shared by the Save button and the Ctrl+Return shortcut.
    function _save() {
        const d = {
            _isNew: root.isNew,
            // Carried through from PersonPicker: which Docs contact this
            // person came from, or that a contact should be created for them.
            // savePerson() reads both — dropping them here would leave the
            // rail and Docs unlinked.
            _contactKey: root.draft._contactKey || "",
            _createContact: !!root.draft._createContact,
            // The id this person had when the editor opened: moving to an id
            // someone else holds is refused, like a new person taking one.
            _originalId: root.isNew ? "" : (root.draft.id || ""),
            // Prefer the explicit idField value; fall back to the
            // auto-suggested slug when the user left it blank.
            id: (idField.text || "").trim().length > 0
                  ? idField.text.trim()
                  : AppController.suggestPersonId(
                        nameField.text, root.draft.id || ""),
            name: nameField.text,
            role: roleField.text,
            question: questionField.text,
            state: root.states[stateBox.currentIndex],
            color: root.swatches[colorSwatch.selectedIndex]
        };
        // savePerson() refuses a nameless person too, but says nothing for a
        // new one — so say it here, where the name is typed.
        if (d.name.trim().length === 0) {
            root._error = I18n.t("editor.person.err.name");
            nameField.forceActiveFocus();
            return;
        }
        // An id someone already has would replace that person whole
        // (SHELL-24). Say who holds it and keep the draft.
        const holder = AppController.personById(d.id);
        if (holder && holder.id && (root.isNew || d.id !== d._originalId)) {
            root._error = I18n.t("editor.person.err.idTaken").arg(d.id).arg(holder.name || holder.id);
            idField.forceActiveFocus();
            idField.selectAll();
            return;
        }
        if (!AppController.savePerson(d)) {
            root._error = I18n.t("editor.err.refused");
            return;
        }
        root.close();
    }

    // Keyboard-first — see TaskEditor.
    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: root.opened
        onActivated: root._save()
    }

    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: Theme.spXl
        Item { Layout.preferredHeight: 4 }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: root.isNew ? I18n.t("editor.person.new") : I18n.t("editor.person.edit")
            color: Theme.text
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
        }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; text: I18n.t("editor.label.name")
               color: Theme.textDim; font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle }
        TextField {
            id: nameField
            ContextMenu.menu: TextEditMenu { editor: nameField }
            objectName: "pe-name"
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            placeholderText: I18n.t("editor.ph.fullName")
            background: FieldFrame {}
            color: Theme.text
            placeholderTextColor: Theme.textDim
            // Re-derive idField while the user has not taken control of it.
            onTextChanged: {
                root._error = "";
                if (root._idAutoDerived) {
                    idField.text = AppController.suggestPersonId(
                        text, root.draft.id || "");
                }
            }
        }

        Text { Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; text: I18n.t("editor.label.id")
               color: Theme.textDim; font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle }
        TextField {
            id: idField
            ContextMenu.menu: TextEditMenu { editor: idField }
            objectName: "pe-id"
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            placeholderText: "e.zaharov"
            font.family: Theme.fontMono
            background: FieldFrame {}
            color: Theme.text
            placeholderTextColor: Theme.textDim
            onActiveFocusChanged: if (activeFocus) root._idAutoDerived = false
            onTextChanged: root._error = ""
        }
        Text {
            objectName: "pe-error"
            visible: root._error.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: root._error
            textFormat: Text.PlainText
            color: Theme.danger
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; text: I18n.t("editor.label.role")
               color: Theme.textDim; font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle }
        TextField {
            id: roleField
            ContextMenu.menu: TextEditMenu { editor: roleField }
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            placeholderText: "Tech Lead / QA / PHY team…"
            background: FieldFrame {}
            color: Theme.text
            placeholderTextColor: Theme.textDim
        }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; text: I18n.t("editor.label.question")
               color: Theme.textDim; font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle }
        ScrollView {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            Layout.preferredHeight: 64
            TextArea {
                id: questionField
                ContextMenu.menu: TextEditMenu { editor: questionField }
                placeholderText: I18n.t("editor.ph.question")
                wrapMode: TextEdit.Wrap
                background: FieldFrame {}
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }
        }

        RowLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            spacing: Theme.spXl
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spXs
                Text {
                    text: I18n.t("editor.label.status"); color: Theme.textDim; font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle
                }
                AppComboBox {
                    id: stateBox
                    Layout.fillWidth: true
                    // One entry per `root.states`, in the same order: _save()
                    // indexes one by the other, so a three-item model against
                    // four states saved "pinged" when the user picked
                    // "answered". "no action needed" also belongs here — it is
                    // how someone leaves the People rail without being deleted.
                    model: [I18n.t("editor.person.state.idle"), I18n.t("editor.person.state.todo"),
                            I18n.t("editor.person.state.pinged"), I18n.t("editor.person.state.replied")]
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spXs
                Text {
                    text: I18n.t("editor.label.avatar"); color: Theme.textDim; font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle
                }
                Row {
                    id: colorSwatch
                    property int selectedIndex: 0
                    spacing: Theme.spXs
                    Repeater {
                        model: root.swatches
                        delegate: Rectangle {
                            id: swatch
                            required property string modelData
                            required property int index
                            width: 22; height: 22; radius: 11
                            color: modelData
                            border.color: colorSwatch.selectedIndex === index ? Theme.text : "transparent"
                            border.width: 2
                            ClickArea {
                                label: I18n.t("swatch.name").arg(swatch.index + 1)
                                role: Accessible.RadioButton
                                checkable: true
                                checked: colorSwatch.selectedIndex === swatch.index
                                onActivated: colorSwatch.selectedIndex = swatch.index
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.topMargin: Theme.spMd; Layout.bottomMargin: Theme.sp2xl
            spacing: Theme.spMd
            PillButton {
                visible: !root.isNew
                text: I18n.t("common.delete"); danger: true
                onClicked: {
                    AppController.deletePerson(root.draft.id);
                    root.close();
                }
            }
            Item { Layout.fillWidth: true }
            PillButton {
                text: I18n.t("common.cancel"); onClicked: root.close()
            }
            PillButton {
                text: root.isNew ? I18n.t("editor.btn.add") : I18n.t("editor.btn.save")
                primary: true
                onClicked: root._save()
            }
        }
    }
}
