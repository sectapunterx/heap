// Names a saved view: "Save view…" and "Rename…". One field, Enter saves, Esc
// cancels — the whole point of a saved view is that it costs nothing to make.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    objectName: "saved-view-name-dialog"
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 420
    anchors.centerIn: Overlay.overlay
    Overlay.modal: Rectangle { color: Theme.scrim }

    // "save" | "rename"
    property string mode: "save"
    // What the view will capture, one line under the field, so the name is
    // chosen knowing what it names.
    property string summary: ""
    readonly property alias text: nameField.text

    // Emitted with the trimmed name; the dialog closes itself.
    signal accepted(string name)

    function openFor(mode, name, summary) {
        root.mode = mode;
        root.summary = summary || "";
        nameField.text = name || "";
        open();
        // Now, not on a later tick: a quick first keystroke would otherwise
        // land before the select-all and be replaced by it.
        nameField.forceActiveFocus();
        nameField.selectAll();
    }

    function submit() {
        const name = nameField.text.trim();
        if (name.length === 0) return;
        root.close();
        root.accepted(name);
    }

    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: Theme.spLg

        Text {
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: root.mode === "rename" ? I18n.t("savedview.dialog.renameTitle") : I18n.t("savedview.dialog.saveTitle")
            color: Theme.text
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
            elide: Text.ElideRight
        }
        TextField {
            id: nameField
            ContextMenu.menu: TextEditMenu { editor: nameField }
            objectName: "saved-view-name-field"
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            placeholderText: I18n.t("savedview.dialog.placeholder")
            maximumLength: 60
            background: Rectangle {
                radius: Theme.radiusMd
                color: Theme.panel2
                border.color: nameField.activeFocus ? Theme.accent : Theme.fieldBorder
                border.width: 1
            }
            color: Theme.text
            placeholderTextColor: Theme.textDim
            selectByMouse: true
            Accessible.name: I18n.t("savedview.dialog.placeholder")
            onAccepted: root.submit()
        }
        Text {
            visible: root.summary.length > 0
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: root.summary
            color: Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsSm
            elide: Text.ElideRight
        }
        RowLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.bottomMargin: Theme.inset
            spacing: Theme.spMd
            Text {
                Layout.fillWidth: true
                text: I18n.t("savedview.dialog.keys")
                color: Theme.textDim
                font.pixelSize: Theme.fsXs
                elide: Text.ElideRight
            }
            PillButton {
                objectName: "saved-view-cancel"
                text: I18n.t("common.cancel")
                onClicked: root.close()
            }
            PillButton {
                objectName: "saved-view-save"
                primary: true
                enabled: nameField.text.trim().length > 0
                text: root.mode === "rename" ? I18n.t("editor.btn.save") : I18n.t("savedview.dialog.save")
                onClicked: root.submit()
            }
        }
    }
}
