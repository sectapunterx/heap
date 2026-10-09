pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// A comment being written for the ticket (APP-241). Saved here as it is
// typed — through a close, a restart, a pull, "out of the filter". lowkey
// never sends it: "Copy and open the ticket" puts it on the clipboard and
// opens the ticket in the browser, and the person pastes and sends it there.
// Copying does not clear it; "Clear" is its own action, with undo.
ColumnLayout {
    id: root
    objectName: "task-doc-draft"

    property string taskId: ""
    property int rev: 0
    property string trackerName: ""

    readonly property string _stored: root.rev >= 0 && root.taskId.length > 0 ? AppController.taskCommentDraft(root.taskId) : ""
    property bool _open: false
    readonly property bool _shown: root._open || root._stored.length > 0

    spacing: Theme.spXs

    function flush() {
        saveTimer.stop();
        if (field.text !== root._stored) AppController.setTaskCommentDraft(root.taskId, field.text);
    }
    onTaskIdChanged: { root._open = false; field.text = root._stored; }
    on_StoredChanged: if (!field.activeFocus && field.text !== root._stored) field.text = root._stored

    Text {
        objectName: "task-doc-draft-start"
        visible: !root._shown
        text: "+ " + I18n.t("local.draft.start")
        color: startCA.hovered ? Theme.text : Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsXs
        ClickArea {
            id: startCA
            label: parent.text
            onActivated: { root._open = true; field.forceActiveFocus(); }
        }
    }

    RowLayout {
        visible: root._shown
        Layout.fillWidth: true
        spacing: Theme.spMd
        Text {
            text: I18n.t("local.draft.title")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
        }
        Text {
            Layout.fillWidth: true
            text: I18n.t("local.draft.never").arg(root.trackerName)
            elide: Text.ElideRight
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
        }
    }
    QQC.TextArea {
        id: field
        objectName: "task-doc-draft-field"
        visible: root._shown
        Layout.fillWidth: true
        Layout.minimumHeight: Theme.chipH * 2
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        selectByMouse: true
        placeholderText: I18n.t("local.draft.ph")
        placeholderTextColor: Theme.textDim
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsSm
        background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.panel2
            border.width: 1
            border.color: field.activeFocus ? Theme.focusRing : Theme.border
        }
        onTextChanged: if (field.activeFocus) saveTimer.restart()
        onActiveFocusChanged: if (!activeFocus) root.flush()
        Keys.onEscapePressed: { root.flush(); field.focus = false; }
    }
    Timer { id: saveTimer; interval: 400; onTriggered: root.flush() }
    Connections {
        target: Qt.application
        function onAboutToQuit() { root.flush(); }
    }

    RowLayout {
        visible: root._shown
        spacing: Theme.spMd
        PillButton {
            objectName: "task-doc-draft-copy"
            text: I18n.t("local.draft.copyOpen")
            enabled: field.text.trim().length > 0
            onClicked: {
                root.flush();
                const url = AppController.copyCommentDraft(root.taskId);
                if (url.length > 0) Qt.openUrlExternally(url);
            }
        }
        PillButton {
            objectName: "task-doc-draft-clear"
            text: I18n.t("local.draft.clear")
            enabled: field.text.length > 0
            onClicked: {
                saveTimer.stop();
                AppController.setTaskCommentDraft(root.taskId, field.text);
                AppController.clearTaskCommentDraft(root.taskId);
                field.text = "";
                root._open = false;
            }
        }
    }
}
