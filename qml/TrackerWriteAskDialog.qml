import QtQuick
import QtQuick.Layouts
import TodoCpp

// Before a status write (X/N-Dlg-Conflict left, R3-147): only where the
// user turned writes on for that tracker. "Отправить статус в Jira?", the
// ticket, "from → to", and "don't ask again for Jira". "Send" is the main
// button (Enter); "Only here" keeps the column in lowkey and sends nothing.
// Esc leaves the card marked "not sent", with its own send link.
SmallDialog {
    id: root
    objectName: "trackerWriteAsk"
    property string taskId: ""
    property string key: ""
    property string issueTitle: ""
    property string tracker: ""
    property string providerId: ""
    property string from: ""
    property string to: ""
    property bool dontAsk: false
    // Several cards moved at once ask one after another.
    property var _queue: []

    function ask(taskId, key, title, tracker, providerId, from, to) {
        const item = { taskId: taskId, key: key, title: title, tracker: tracker, providerId: providerId, from: from, to: to };
        if (root.opened) { root._queue = root._queue.concat([item]); return; }
        root._show(item);
    }
    function _show(it) {
        root.taskId = it.taskId;
        root.key = it.key;
        root.issueTitle = it.title;
        root.tracker = it.tracker;
        root.providerId = it.providerId;
        root.from = it.from;
        root.to = it.to;
        root.dontAsk = false;
        root.open();
    }
    function _answer(send) {
        if (root.dontAsk) AppController.setTrackerAskBeforeWrite(root.providerId, false);
        const id = root.taskId;
        root.close();
        if (send) AppController.retryTrackerPush(id);
        else AppController.discardTrackerPush(id);
    }
    onClosed: {
        if (root._queue.length === 0) return;
        const next = root._queue[0];
        root._queue = root._queue.slice(1);
        Qt.callLater(() => root._show(next));
    }

    width: Math.min(428, (parent ? parent.width : 428) - 32)
    title: I18n.t("tracker.ask.title").arg(root.tracker)
    fact: root.key + " · " + root.issueTitle
    factColor: Theme.textMuted
    onOpened: sendBtn.forceActiveFocus(Qt.TabFocusReason)
    onAccepted: root._answer(true)

    Text {
        objectName: "trackerWriteAskMove"
        Layout.fillWidth: true
        visible: root.to.length > 0
        textFormat: Text.PlainText
        text: (root.from.length > 0 ? root.from + " → " : "") + root.to
        color: Theme.textMuted
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsMd
        elide: Text.ElideRight
    }
    // "Больше не спрашивать для Jira": a box and its words, one click target.
    Item {
        objectName: "trackerWriteAskDontAsk"
        implicitWidth: dontAskRow.implicitWidth
        implicitHeight: dontAskRow.implicitHeight
    Row {
        id: dontAskRow
        spacing: Theme.spSm
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.px(14); height: Theme.px(14)
            radius: Theme.radiusXs
            color: root.dontAsk ? Theme.text : "transparent"
            border.width: 1
            border.color: root.dontAsk ? Theme.text : Theme.borderStrong
            Icon {
                anchors.centerIn: parent
                visible: root.dontAsk
                name: "check"
                size: Theme.px(10)
                color: Theme.bg
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.t("tracker.ask.dontAsk").arg(root.tracker)
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
        }
    }
        ClickArea {
            label: I18n.t("tracker.ask.dontAsk").arg(root.tracker)
            role: Accessible.CheckBox
            checkable: true
            checked: root.dontAsk
            onActivated: root.dontAsk = !root.dontAsk
        }
    }

    buttons: [
        PillButton {
            objectName: "trackerWriteAskKeep"
            text: I18n.t("tracker.ask.keep")
            onClicked: root._answer(false)
        },
        PillButton {
            id: sendBtn
            objectName: "trackerWriteAskSend"
            text: I18n.t("tracker.ask.send")
            primary: true
            solid: Style.fills
            Keys.onReturnPressed: root._answer(true)
            Keys.onEnterPressed: root._answer(true)
            onClicked: root._answer(true)
        }
    ]
}
