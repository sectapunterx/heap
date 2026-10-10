pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The standup draft (APP-170, X-Dlg-Recap): "Yesterday / Today / Blockers",
// built by AppController.standupDraft() from what lowkey already knows, in a
// field the person edits before copying it. Nothing is sent anywhere, and the
// text is not kept: closing drops it, opening builds a fresh one.
Popup {
    id: root
    objectName: "standup-draft"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: 0
    width: 428
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function showNow() {
        draftField.text = AppController.standupDraft();
        root.open();
    }
    function copy() {
        AppController.copyToClipboard(draftField.text);
        AppController.toast(I18n.t("standup.copied"));
        root.close();
    }

    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: 0
        Text {
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: I18n.t("standup.title")
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
        }
        Text {
            Layout.topMargin: Theme.spXs
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: I18n.t("standup.note")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
        ScrollView {
            Layout.topMargin: Theme.spLg
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Theme.px(280), draftField.implicitHeight + 2)
            clip: true
            TextArea {
                id: draftField
                objectName: "standup-draft-text"
                wrapMode: TextEdit.Wrap
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                color: Theme.text
                selectByMouse: true
                padding: Theme.spLg
                background: Rectangle {
                    radius: Theme.radiusMd
                    color: "transparent"
                    border.width: 1
                    border.color: draftField.activeFocus ? Theme.borderStrong : Theme.fieldBorder
                }
                Keys.onPressed: (e) => {
                    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) {
                        root.copy();
                        e.accepted = true;
                    }
                }
            }
        }
        RowLayout {
            Layout.margins: Theme.inset
            Layout.fillWidth: true
            spacing: Theme.spMd
            PillButton {
                id: copyBtn
                objectName: "standup-draft-copy"
                text: I18n.t("standup.copy")
                primary: true
                solid: Style.fills
                onClicked: root.copy()
            }
            PillButton {
                objectName: "standup-draft-close"
                text: I18n.t("common.close")
                onClicked: root.close()
            }
            Item { Layout.fillWidth: true }
        }
    }
    onOpened: draftField.forceActiveFocus()
}
