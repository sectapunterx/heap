import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// "Send the status anyway?" (APP-204). The check heap makes right before a
// status write found the issue outside the user's filter — reassigned,
// moved out of the JQL — so nothing was sent. This is the only way it still
// goes out: the user reads which issue, where it stands in the tracker now
// and where it would go, and says so. Cancel is the default (focus, Enter,
// Esc), and cancelling leaves the card marked "not sent".
QQC.Dialog {
    id: root
    objectName: "trackerPushConfirm"
    property string taskId: ""
    property string key: ""
    property string issueTitle: ""
    property string tracker: ""
    property string remoteStatus: ""
    property string target: ""

    function ask(taskId, key, title, tracker, remoteStatus, target) {
        root.taskId = taskId;
        root.key = key;
        root.issueTitle = title;
        root.tracker = tracker;
        root.remoteStatus = remoteStatus;
        root.target = target;
        root.open();
    }

    modal: true
    QQC.Overlay.modal: ModalScrim {}
    parent: QQC.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(480, (parent ? parent.width : 480) - 32)
    padding: Theme.inset
    title: I18n.t("tracker.confirm.title")
    header: DialogHeader { text: root.title }
    background: ModalSurface {}
    onOpened: cancelBtn.forceActiveFocus(Qt.TabFocusReason)
    contentItem: ColumnLayout {
        spacing: Theme.spMd
        Text {
            objectName: "trackerPushConfirmBody"
            Layout.fillWidth: true
            text: I18n.t("tracker.confirm.body").arg(root.key).arg(root.issueTitle).arg(root.tracker)
                  .arg(root.remoteStatus.length > 0 ? root.remoteStatus : "—").arg(root.target)
            textFormat: Text.PlainText
            color: Theme.text
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
    }
    footer: DialogFooter {
        PillButton {
            id: cancelBtn
            objectName: "trackerPushConfirmCancel"
            text: I18n.t("common.cancel")
            Keys.onReturnPressed: root.close()
            Keys.onEnterPressed: root.close()
            onClicked: root.close()
        }
        PillButton {
            objectName: "trackerPushConfirmSend"
            text: I18n.t("tracker.confirm.send")
            danger: true
            onClicked: {
                root.close();
                AppController.confirmTrackerPush(root.taskId);
            }
        }
    }
}
