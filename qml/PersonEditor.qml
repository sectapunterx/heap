import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    width: 460
    anchors.centerIn: Overlay.overlay

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

    property var draft: ({})
    property bool isNew: false

    readonly property var palette: [
        "#d97a6c", "#c87fc7", "#6cc4b8", "#7da8d9",
        "#dcc06a", "#7cc492", "#e69854", "#a4a4d6"
    ]
    readonly property var states: ["todo", "pinged", "replied"]
    readonly property var stateLabels: ({
        todo: I18n.t("editor.person.state.todo"),
        pinged: I18n.t("editor.person.state.pinged"),
        replied: I18n.t("editor.person.state.replied")
    })

    // True while the user has not manually edited idField — keeps the id in
    // sync with the live name. Flips to false on first manual edit so we
    // don't clobber the user's chosen handle.
    property bool _idAutoDerived: true

    function showFor(initialDraft) {
        draft = initialDraft || {};
        isNew = !!draft._isNew;
        nameField.text     = draft.name || "";
        roleField.text     = draft.role || "";
        questionField.text = draft.question || "";
        idField.text       = draft.id || "";
        _idAutoDerived = isNew || (idField.text.length === 0);
        stateBox.currentIndex = Math.max(0, states.indexOf(draft.state || "todo"));
        const cur = String(draft.color || palette[0]).toLowerCase();
        let i = 0;
        for (let k = 0; k < palette.length; k++)
            if (palette[k].toLowerCase() === cur) { i = k; break; }
        colorSwatch.selectedIndex = i;
        open();
    }

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 12
        Item { Layout.preferredHeight: 4 }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: root.isNew ? I18n.t("editor.person.new") : I18n.t("editor.person.edit")
            color: Theme.text
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("editor.label.name").toUpperCase()
               color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        TextField {
            id: nameField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            placeholderText: I18n.t("editor.ph.fullName")
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
            placeholderTextColor: Theme.textDim
            // Re-derive idField while the user has not taken control of it.
            onTextChanged: {
                if (root._idAutoDerived) {
                    idField.text = AppController.suggestPersonId(
                        text, root.draft.id || "");
                }
            }
        }

        Text { Layout.leftMargin: 18; Layout.rightMargin: 18; text: "ID"
               color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        TextField {
            id: idField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            placeholderText: "e.zaharov"
            font.family: Theme.fontMono
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
            placeholderTextColor: Theme.textDim
            onActiveFocusChanged: if (activeFocus) root._idAutoDerived = false
        }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("editor.label.role").toUpperCase()
               color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        TextField {
            id: roleField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            placeholderText: "Tech Lead / QA / PHY team…"
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
            placeholderTextColor: Theme.textDim
        }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("editor.label.question").toUpperCase()
               color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        ScrollView {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            Layout.preferredHeight: 64
            TextArea {
                id: questionField
                placeholderText: I18n.t("editor.ph.question")
                wrapMode: TextEdit.Wrap
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: I18n.t("editor.label.status").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
                }
                ComboBox {
                    id: stateBox
                    Layout.fillWidth: true
                    model: [I18n.t("editor.person.state.todo"), I18n.t("editor.person.state.pinged"), I18n.t("editor.person.state.replied")]
                    background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                    contentItem: Text { text: stateBox.displayText; color: Theme.text; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: I18n.t("editor.label.avatar").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
                }
                Row {
                    id: colorSwatch
                    property int selectedIndex: 0
                    spacing: 4
                    Repeater {
                        model: root.palette
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: 22; height: 22; radius: 11
                            color: modelData
                            border.color: colorSwatch.selectedIndex === index ? Theme.text : "transparent"
                            border.width: 2
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: colorSwatch.selectedIndex = index
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.topMargin: 8; Layout.bottomMargin: 16
            spacing: 8
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
                onClicked: {
                    const d = {
                        _isNew: root.isNew,
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
                        color: root.palette[colorSwatch.selectedIndex]
                    };
                    AppController.savePerson(d);
                    root.close();
                }
            }
        }
    }
}
