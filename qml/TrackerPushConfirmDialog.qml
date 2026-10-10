import QtQuick
import TodoCpp

// The not-yours write (APP-204, X/N-Dlg-Conflict right, R2-033). The check
// lowkey makes right before a status write found the issue is not the
// user's any more — assigned to someone else, or out of the filter — so
// nothing was sent. The card says whose it is and asks once; there is no
// "don't ask again" for a ticket that is not yours. "Only here" is the
// default (focus, Enter, Esc) and leaves the card marked "not sent"; "Send
// anyway" is the only way the status still goes out.
SmallDialog {
    id: root
    objectName: "trackerPushConfirm"
    property string taskId: ""
    property string key: ""
    property string issueTitle: ""
    property string tracker: ""
    property string remoteStatus: ""
    property string target: ""
    property string assignee: ""

    function ask(taskId, key, title, tracker, remoteStatus, target) {
        root.taskId = taskId;
        root.key = key;
        root.issueTitle = title;
        root.tracker = tracker;
        root.remoteStatus = remoteStatus;
        root.target = target;
        const t = AppController.taskById(taskId);
        root.assignee = t && t.ticket && t.ticket.assignee ? String(t.ticket.assignee)
                      : (t && t.assignee ? String(t.assignee) : "");
        root.open();
    }

    width: Math.min(428, (parent ? parent.width : 428) - 32)
    title: root.assignee.length > 0 ? I18n.t("tracker.notMine.assigned").arg(root.assignee.replace(/\.$/, ""))
                                    : I18n.t("tracker.notMine.outside").arg(root.tracker)
    fact: I18n.t("tracker.notMine.body").arg(root.key).arg(root.tracker)
    onOpened: keepBtn.forceActiveFocus(Qt.TabFocusReason)
    onAccepted: root.close()

    buttons: [
        PillButton {
            id: keepBtn
            objectName: "trackerPushConfirmCancel"
            text: I18n.t("tracker.notMine.keep")
            primary: true
            solid: Style.fills
            Keys.onReturnPressed: root.close()
            Keys.onEnterPressed: root.close()
            onClicked: root.close()
        },
        PillButton {
            objectName: "trackerPushConfirmSend"
            text: I18n.t("tracker.confirm.send")
            onClicked: {
                root.close();
                AppController.confirmTrackerPush(root.taskId);
            }
        }
    ]
}
