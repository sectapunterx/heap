pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// The timer's sessions (APP-251), under the document's Time: each run with
// its day and hours, editable when a timer was forgotten on or off, and a
// session added by hand. What was tracked before sessions existed is one line
// with no date. Facts only: no ratio, no advice, no worklog to a tracker.
ColumnLayout {
    id: root
    objectName: "task-doc-sessions"

    property string taskId: ""
    property int rev: 0

    readonly property var sessions: root.rev >= 0 && root.taskId.length > 0 ? AppController.taskSessions(root.taskId) : []
    property bool _open: false
    // The session being edited ("" = none, "new" = adding one).
    property string _editId: ""

    spacing: Theme.spXs

    function _hm(d) { return I18n.fmtTime(d); }
    function _span(s) {
        if (s.undated) return I18n.t("local.sessions.before");
        return I18n.fmtDate(s.start, "dayMonth") + " " + root._hm(s.start) + "–" + root._hm(s.end);
    }
    // "9:00-10:30" or "8 Oct 9:00-10:30", read like the input.
    function _apply(text, sessionId) {
        const m = String(text).trim().match(/^(.*?)\s*(\d{1,2}[:.]\d{2})\s*[-–]\s*(\d{1,2}[:.]\d{2})$/);
        if (!m) return false;
        let day = new Date();
        if (m[1].length > 0) {
            const r = AppController.parseDateTime(m[1], new Date());
            if (!r || !r.ok) return false;
            day = r.start;
        }
        const at = (hm) => {
            const p = hm.replace(".", ":").split(":");
            return new Date(day.getFullYear(), day.getMonth(), day.getDate(), parseInt(p[0]), parseInt(p[1]));
        };
        const start = at(m[2]);
        let end = at(m[3]);
        if (end <= start) end = new Date(end.getTime() + 86400000);  // over midnight
        return sessionId === "new" ? AppController.addTaskSession(root.taskId, start, end)
                                   : AppController.updateTaskSession(root.taskId, sessionId, start, end);
    }

    Text {
        objectName: "task-doc-sessions-toggle"
        visible: root.sessions.length > 0 || root._open
        text: (root._open ? "▾ " : "▸ ") + I18n.count(root.sessions.length, "local.sessions.count")
        color: togCA.hovered ? Theme.text : Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsXs
        ClickArea { id: togCA; label: parent.text; onActivated: root._open = !root._open }
    }

    Repeater {
        model: root._open ? root.sessions : []
        delegate: RowLayout {
            id: ses
            required property var modelData
            required property int index
            objectName: "task-doc-session-" + ses.index
            Layout.fillWidth: true
            spacing: Theme.spSm
            Text {
                visible: root._editId !== ses.modelData.id
                Layout.fillWidth: true
                text: root._span(ses.modelData)
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsXs
                ClickArea {
                    enabled: !ses.modelData.undated
                    label: parent.text
                    tip: I18n.t("local.sessions.editTip")
                    onActivated: root._editId = ses.modelData.id
                }
            }
            QQC.TextField {
                visible: root._editId === ses.modelData.id
                Layout.fillWidth: true
                text: ses.modelData.undated ? "" : I18n.fmtDate(ses.modelData.start, "dayMonth") + " " + root._hm(ses.modelData.start) + "-" + root._hm(ses.modelData.end)
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                color: Theme.text
                padding: 0
                leftPadding: Theme.spXs
                background: Rectangle { radius: Theme.radiusSm; color: Theme.panel2; border.width: 1; border.color: Theme.focusRing }
                onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                onAccepted: if (root._apply(text, ses.modelData.id)) root._editId = ""
                Keys.onEscapePressed: root._editId = ""
            }
            Text {
                text: I18n.fmtMinutes(Math.round(ses.modelData.seconds / 60))
                color: Theme.textDim
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsXs
            }
            Text {
                text: "×"
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
                ClickArea {
                    label: I18n.t("local.sessions.remove")
                    onActivated: AppController.removeTaskSession(root.taskId, ses.modelData.id)
                }
            }
        }
    }

    Text {
        objectName: "task-doc-session-add"
        visible: root._open && root._editId !== "new"
        text: "+ " + I18n.t("local.sessions.add")
        color: addCA.hovered ? Theme.text : Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsXs
        ClickArea { id: addCA; label: parent.text; onActivated: root._editId = "new" }
    }
    QQC.TextField {
        id: newField
        objectName: "task-doc-session-new"
        visible: root._editId === "new"
        Layout.fillWidth: true
        placeholderText: I18n.t("local.sessions.ph")
        placeholderTextColor: Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsXs
        color: Theme.text
        leftPadding: Theme.spXs
        background: Rectangle { radius: Theme.radiusSm; color: Theme.panel2; border.width: 1; border.color: Theme.focusRing }
        onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
        onAccepted: if (root._apply(text, "new")) root._editId = ""
        Keys.onEscapePressed: root._editId = ""
    }
}
