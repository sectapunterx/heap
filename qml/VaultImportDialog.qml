import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// Confirm step for "Import notes folder…".
//
// The picker hands over a folder; what is in it is not visible from there, and
// the import used to run the moment the dialog closed. This says what will
// happen — how many notes are new, which ones change, which were edited on both
// sides and will arrive as a copy — before anything does.
QQC.Dialog {
    id: root
    objectName: "vault-import-confirm"

    property url folder
    property var summary: ({})

    // Emitted with the import's own summary once it has run.
    signal imported(var result)

    function openFor(folderUrl) {
        root.folder = folderUrl;
        root.summary = AppController.previewNotesFolder(folderUrl);
        root.open();
    }

    modal: true
    parent: QQC.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(480, (parent ? parent.width : 480) - 32)
    padding: Theme.inset
    title: I18n.t("notes.vault.previewTitle")

    header: DialogHeader { text: root.title }
    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: Theme.spMd
        Text {
            Layout.fillWidth: true
            text: root.summary.folder || ""
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsSm
            wrapMode: Text.WrapAnywhere
        }
        Text {
            objectName: "vault-import-summary"
            Layout.fillWidth: true
            text: root.summary.error
                  ? root.summary.error
                  : I18n.t("notes.vault.previewBody")
                        .arg(root.summary.files || 0)
                        .arg(root.summary.imported || 0)
                        .arg(root.summary.updated || 0)
                        .arg(root.summary.unchanged || 0)
                        .arg(root.summary.kept || 0)
                        .arg(root.summary.conflicts || 0)
                        .arg(root.summary.skipped || 0)
            color: Theme.textMuted
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
        Text {
            visible: (root.summary.conflicts || 0) > 0
            Layout.fillWidth: true
            text: I18n.t("notes.vault.previewConflicts")
            color: Theme.warning
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }
    }

    footer: DialogFooter {
        PillButton { text: I18n.t("common.cancel"); onClicked: root.close() }
        PillButton {
            objectName: "vault-import-go"
            text: I18n.t("notes.vault.import")
            primary: true
            enabled: !root.summary.error && (root.summary.files || 0) > 0
            onClicked: {
                root.close();
                root.imported(AppController.importNotesFolder(root.folder));
            }
        }
    }
}
