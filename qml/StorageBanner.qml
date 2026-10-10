import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import TodoCpp

// The storage line (X/N-Err-Storage, R2-037): the one place lowkey insists,
// because data is at stake. A full-width line over the content for as long
// as the last save did not land, state.json cannot be read, or it was
// written by a newer lowkey — never put away by itself and never by the user
// while the problem lasts. A write failure keeps retrying every 30 s; the
// one button saves the whole state elsewhere meanwhile. What startup found
// in a damaged file is the DamagedFileDialog, not this line.
Item {
    id: banner
    objectName: "storage-banner"

    // Bound to the controller; a test or a preview can set them by hand.
    property string state_: AppController.storageState
    property string reason: AppController.storageReason
    readonly property bool shown: state_ === "writeFailed" || state_ === "unreadable" || state_ === "tooNew"

    visible: shown
    implicitHeight: shown ? frame.implicitHeight + 2 * Theme.spLg : 0

    Rectangle {
        id: frame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spLg
        implicitHeight: Math.max(Theme.chipH + Theme.spLg, row.implicitHeight + 2 * Theme.spMd)
        radius: Theme.radiusMd
        // Bold says it in red; quiet in form and words.
        color: Style.urgency ? Theme.withAlpha(Theme.danger, 0.08) : "transparent"
        border.width: 1
        border.color: Style.urgency ? Theme.danger : Theme.borderStrong

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.leftMargin: Theme.spLg
            anchors.rightMargin: Theme.spMd
            spacing: Theme.spLg

            Icon {
                Layout.alignment: Qt.AlignVCenter
                name: "info"
                color: Style.urgency ? Theme.danger : Theme.text
            }
            Text {
                objectName: "storage-banner-title"
                Layout.alignment: Qt.AlignVCenter
                text: banner.state_ === "writeFailed"
                      ? (banner.reason.length > 0
                         ? I18n.t("storage.strip.title").arg(banner.reason)
                         : I18n.t("storage.strip.unwritable"))
                      : I18n.t("storage.strip.readOnly")
                textFormat: Text.PlainText
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                font.weight: Theme.fwTitle
            }
            Text {
                objectName: "storage-banner-text"
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: banner.state_ === "writeFailed" ? I18n.t("storage.strip.detail") : AppController.storageMessage
                textFormat: Text.PlainText
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                // Never elided: the end says which backup is shown (PLAT-8).
                wrapMode: Text.WordWrap
            }
            PillButton {
                objectName: "storage-banner-copy"
                visible: banner.state_ === "writeFailed"
                text: I18n.t("storage.strip.saveCopy")
                primary: true
                solid: Style.fills
                small: true
                onClicked: copyDialog.open()
            }
            PillButton {
                objectName: "storage-banner-retry"
                visible: banner.state_ === "unreadable"
                text: I18n.t("storage.retry")
                primary: true
                solid: Style.fills
                small: true
                onClicked: AppController.retryStorage()
            }
        }
    }

    FileDialog {
        id: copyDialog
        fileMode: FileDialog.SaveFile
        nameFilters: ["lowkey (*.json)", "All files (*)"]
        defaultSuffix: "json"
        title: I18n.t("storage.strip.saveCopy")
        onAccepted: AppController.saveStateCopyTo(selectedFile)
    }
}
