import QtQuick
import QtQuick.Layouts
import TodoCpp

// Persistent storage-health banner (PLAT-1/4/5). Stays up for as long as
// state.json cannot be read, is from a newer heap, or the last save failed —
// a toast that is gone in two seconds is how edits used to vanish unnoticed.
Rectangle {
    id: banner
    objectName: "storage-banner"

    readonly property string state_: AppController.storageState
    readonly property bool retryable: state_ === "unreadable" || state_ === "writeFailed"
    // What startup found and did about a damaged state.json (PLAT-6): nothing
    // is failing now, so it can be put away once read.
    readonly property bool notice: state_ === "recovered" || state_ === "damaged"
    readonly property bool mild: state_ === "tooNew" || state_ === "recovered"

    visible: state_ !== "" && state_ !== "ok"
    implicitHeight: visible ? Math.max(40, row.implicitHeight + Theme.spMd * 2) : 0
    color: banner.mild ? Theme.panel2 : Theme.panel3
    border.color: banner.mild ? Theme.warning : Theme.danger
    border.width: 1

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Theme.sp2xl
        anchors.rightMargin: Theme.spLg
        spacing: Theme.spLg

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Theme.spSm
            implicitHeight: Theme.spSm
            radius: Theme.spSm / 2
            color: banner.mild ? Theme.warning : Theme.danger
        }
        Text {
            objectName: "storage-banner-text"
            text: AppController.storageMessage
            color: Theme.text
            font.pixelSize: Theme.fsMd
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        PillButton {
            objectName: "storage-banner-retry"
            visible: banner.retryable
            primary: true
            text: I18n.t("storage.retry")
            onClicked: AppController.retryStorage()
        }
        PillButton {
            objectName: "storage-banner-folder"
            text: I18n.t("storage.openFolder")
            onClicked: Qt.openUrlExternally("file:///" + AppController.dataDir)
        }
        PillButton {
            objectName: "storage-banner-dismiss"
            visible: banner.notice
            text: I18n.t("banner.dismiss")
            onClicked: AppController.dismissStorageNotice()
        }
    }
}
