pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The standup draft (APP-170): "Yesterday / Today / Blockers", built by
// AppController.standupDraft() from what heap already knows, in a field the
// user edits before copying it. Nothing is sent anywhere, and the text is not
// kept: closing the dialog drops it, opening it builds a fresh one.
Dialog {
    id: root
    objectName: "standup-draft"
    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: Theme.inset
    width: 560
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function showNow() {
        draftField.text = AppController.standupDraft();
        root.open();
    }

    header: DialogHeader { text: I18n.t("standup.title") }
    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: Theme.spLg

        Text {
            Layout.fillWidth: true
            text: I18n.t("standup.note")
            color: Theme.textMuted
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 320
            clip: true
            TextArea {
                id: draftField
                objectName: "standup-draft-text"
                wrapMode: TextEdit.Wrap
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsSm
                color: Theme.text
                selectByMouse: true
                background: FieldFrame {}
            }
        }
    }

    footer: DialogFooter {
        PillButton {
            objectName: "standup-draft-refresh"
            text: I18n.t("standup.refresh")
            onClicked: draftField.text = AppController.standupDraft()
        }
        PillButton {
            objectName: "standup-draft-close"
            text: I18n.t("common.close")
            onClicked: root.close()
        }
        PillButton {
            id: copyBtn
            objectName: "standup-draft-copy"
            text: I18n.t("standup.copy")
            primary: true
            onClicked: {
                AppController.copyToClipboard(draftField.text);
                AppController.toast(I18n.t("standup.copied"));
                root.close();
            }
        }
    }
    onOpened: draftField.forceActiveFocus()
}
