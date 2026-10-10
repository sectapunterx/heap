pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp
import "WhatsNew.js" as WhatsNew

// "What's new in 0.8.x" (X/N-Ntf-OS, R2-054): once after an update to a new
// release line, then from Settings → About. The text is the line's own
// notes (WhatsNew.js), facts only. The controller knows the line the data
// last ran with (settings.lastRunVersion); a fresh install shows nothing.
Popup {
    id: root
    objectName: "whats-new"
    modal: true
    focus: true
    padding: 0
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    width: Math.min(460, (parent ? parent.width : 460) - 2 * Theme.sp2xl)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: ModalScrim {}
    background: ModalSurface {}

    readonly property var notes: WhatsNew.forVersion(AppController.appVersion)
    readonly property bool available: root.notes !== null
    readonly property string lang: I18n.lang === "ru" ? "ru" : "en"

    // At start: once after an update to a new release line (the controller
    // knows the line this data last ran with). A fresh install never sees it.
    function showIfUpdated() {
        if (!AppController.whatsNewDue) return false;
        AppController.ackWhatsNew();
        if (!root.available) return false;
        root.open();
        return true;
    }
    function showNow() {
        if (!root.available) return false;
        AppController.ackWhatsNew();
        root.open();
        return true;
    }
    onOpened: okBtn.forceActiveFocus(Qt.TabFocusReason)

    contentItem: ColumnLayout {
        spacing: 0
        Text {
            objectName: "whats-new-title"
            Layout.fillWidth: true
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("whatsnew.title").arg(AppController.appVersion)
            color: Theme.text
            font.family: Theme.fontUi
            // N/X-Ntf-OS: a 15px/600 heading over 13px body (R4-020).
            font.pixelSize: Theme.px(15)
            font.weight: Theme.fwHeading
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spXs
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.bottomMargin: Theme.spSm
            text: I18n.t("whatsnew.sub")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
        Repeater {
            model: root.notes ? root.notes.sections : []
            delegate: ColumnLayout {
                id: sec
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                spacing: Theme.sp2xs
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spMd
                    Layout.bottomMargin: Theme.spMd
                    implicitHeight: 1
                    color: Theme.border
                }
                Text {
                    Layout.fillWidth: true
                    text: sec.modelData.title[root.lang]
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
                }
                Text {
                    Layout.fillWidth: true
                    text: sec.modelData.body[root.lang]
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
                    lineHeight: 1.2
                    wrapMode: Text.Wrap
                }
            }
        }
        Text {
            visible: !!(root.notes && root.notes.moved)
            Layout.fillWidth: true
            Layout.topMargin: Theme.sp2xl
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("whatsnew.moved")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
        }
        Text {
            objectName: "whats-new-moved"
            visible: !!(root.notes && root.notes.moved)
            Layout.fillWidth: true
            Layout.topMargin: Theme.spSm
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: root.notes && root.notes.moved ? root.notes.moved[root.lang] : ""
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            lineHeight: 1.4
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spLg
            Layout.bottomMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Item { Layout.fillWidth: true }
            PillButton {
                id: okBtn
                objectName: "whats-new-ok"
                text: I18n.t("whatsnew.ok")
                primary: true
                Keys.onReturnPressed: root.close()
                Keys.onEnterPressed: root.close()
                onClicked: root.close()
            }
        }
    }
}
