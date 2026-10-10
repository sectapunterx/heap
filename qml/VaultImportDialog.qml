import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// "Импорт папки Markdown" (R2-070, sheet X/N-Dlg-Log-Import): the folder
// (mono), what it holds — files, how many become notes, how many tasks the
// open checklists would make — what is skipped, the "- [ ] → tasks" choice,
// and "Другая папка" / "Импортировать". Nothing runs before the click; the
// picker hands over a folder whose contents it does not show.
QQC.Dialog {
    id: root
    objectName: "vault-import-confirm"

    property url folder
    property var summary: ({})
    // Open "- [ ]" items of the new notes become tasks (sheet: on).
    property bool checklistTasks: true

    // Emitted with the import's own summary once it has run.
    signal imported(var result)
    // "Другая папка": the owner opens the picker again.
    signal otherFolderRequested()

    function openFor(folderUrl) {
        root.folder = folderUrl;
        root.summary = AppController.previewNotesFolder(folderUrl);
        root.open();
    }
    function run() {
        if (!goBtn.enabled) return;
        root.close();
        root.imported(AppController.importNotesFolder(root.folder, root.checklistTasks && (root.summary.checklistItems || 0) > 0));
    }

    modal: true
    QQC.Overlay.modal: ModalScrim {}
    parent: QQC.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(Theme.px(480), (parent ? parent.width : Theme.px(480)) - 2 * Theme.sp2xl)
    padding: Theme.inset
    title: I18n.t("notes.vault.previewTitle")

    header: DialogHeader { text: root.title }
    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: Theme.spSm
        Keys.onReturnPressed: root.run()
        Keys.onEnterPressed: root.run()
        Text {
            objectName: "vault-import-folder"
            Layout.fillWidth: true
            text: root.summary.folder || ""
            color: Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsSm
            wrapMode: Text.WrapAnywhere
        }
        // "42 файла · 38 станут заметками · из 4 чек-листов — 12 задач"
        Text {
            objectName: "vault-import-summary"
            Layout.topMargin: Theme.spSm
            Layout.fillWidth: true
            text: {
                const s = root.summary;
                if (s.error) return s.error;
                const parts = [I18n.count(s.files || 0, "notes.vault.files"),
                               I18n.count(s.imported || 0, "notes.vault.becomeNotes")];
                if ((s.updated || 0) > 0) parts.push(I18n.count(s.updated, "notes.vault.updatedN"));
                if ((s.unchanged || 0) + (s.kept || 0) > 0)
                    parts.push(I18n.count((s.unchanged || 0) + (s.kept || 0), "notes.vault.unchangedN"));
                if ((s.checklistItems || 0) > 0)
                    parts.push(I18n.t("notes.vault.fromChecklists")
                               .arg(I18n.count(s.checklists, "notes.vault.checklists"))
                               .arg(I18n.count(s.checklistItems, "notes.vault.tasksN")));
                return parts.join(" · ");
            }
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
        Text {
            objectName: "vault-import-skipped"
            Layout.fillWidth: true
            visible: (root.summary.skipped || 0) > 0
            text: I18n.count(root.summary.skipped || 0, "notes.vault.skippedN")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
        Text {
            visible: (root.summary.conflicts || 0) > 0
            Layout.fillWidth: true
            text: I18n.t("notes.vault.previewConflicts")
            color: Theme.warning
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }
        Item {
            objectName: "vault-import-checklists"
            Layout.topMargin: Theme.spSm
            visible: (root.summary.checklistItems || 0) > 0
            implicitWidth: checkRow.implicitWidth
            implicitHeight: checkRow.implicitHeight
            RowLayout {
                id: checkRow
                spacing: Theme.spSm
                Rectangle {
                    implicitWidth: Theme.px(14); implicitHeight: Theme.px(14)
                    radius: Theme.radiusXs
                    color: root.checklistTasks ? Theme.text : "transparent"
                    border.width: 1
                    border.color: root.checklistTasks ? Theme.text : Theme.fieldBorder
                    Icon {
                        anchors.centerIn: parent
                        visible: root.checklistTasks
                        name: "check"
                        size: Theme.px(12)
                        color: Theme.bg
                    }
                }
                Text {
                    text: I18n.t("notes.vault.checklistTasks")
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
                }
            }
            ClickArea {
                objectName: "vault-import-checklists-toggle"
                label: I18n.t("notes.vault.checklistTasks")
                onActivated: root.checklistTasks = !root.checklistTasks
            }
        }
    }

    footer: DialogFooter {
        PillButton {
            objectName: "vault-import-other"
            text: I18n.t("notes.vault.otherFolder")
            onClicked: { root.close(); root.otherFolderRequested(); }
        }
        PillButton {
            id: goBtn
            objectName: "vault-import-go"
            text: I18n.t("notes.vault.import")
            primary: true
            enabled: !root.summary.error && (root.summary.files || 0) > 0
            onClicked: root.run()
        }
    }
}
