pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The day's summary (APP-190, X-Dlg-Recap "Итог дня"), from the end-of-day
// check in Settings → Safety net, or from the palette at any time:
//
//   Итог дня · чт, 8 окт
//   Закрыто 2 · в таймере 4 ч 10 мин · переходит 2
//   Переходит на завтра — решите сами, или оставьте
//   Оформление заказа: таймаут 10 с · ждёт платёжки
//   [→ завтра] [→ ближайшее окно] [→ когда-нибудь] [снять дату]
//   Таймер «…» ещё идёт — остановить?
//
// Only facts. Nothing is moved, rescheduled or stopped on its own: a
// leftover has its buttons (APP-248) for the person to press or ignore, a
// running timer a link. A leftover's title opens it.
Popup {
    id: root
    objectName: "end-of-day"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: 0
    width: 428
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property var summary: ({ closed: [], carryOver: [], timers: [] })
    // Seconds on the timer today; read with the summary.
    property int trackedSeconds: 0
    readonly property var carryRows: root.summary.carryOver || []
    readonly property var timerRows: root.summary.timers || []
    readonly property int closedCount: (root.summary.closed || []).length
    readonly property bool empty: root.closedCount === 0 && root.carryRows.length === 0
                                  && root.timerRows.length === 0 && root.trackedSeconds <= 0

    signal taskActivated(string id)

    function _read() {
        root.summary = AppController.endOfDaySummary();
        root.trackedSeconds = AppController.trackedSecondsOn(root.summary.date || new Date());
    }
    // A leftover carried on by hand; the list is read again, so it leaves
    // once it has a new day.
    function carry(id, mode) {
        AppController.carryTasks([id], mode);
        root._read();
    }
    function showNow() {
        root._read();
        root.open();
    }

    // "Закрыто 2 · в таймере 4 ч 10 мин · переходит 2"
    function factsLine() {
        const parts = [I18n.t("eod.fact.closed").arg(root.closedCount)];
        if (root.trackedSeconds >= 60)
            parts.push(I18n.t("eod.fact.timer").arg(I18n.fmtMinutes(Math.round(root.trackedSeconds / 60))));
        parts.push(I18n.t("eod.fact.carry").arg(root.carryRows.length));
        return parts.join(" · ");
    }
    function _statusOf(id) {
        const t = AppController.taskById(id);
        if (!t || !t.id) return "";
        const sts = AppController.statuses;
        for (let i = 0; i < sts.length; i++)
            if (sts[i].id === t.status) return String(sts[i].name).toLowerCase();
        return "";
    }

    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: 0

        Text {
            objectName: "end-of-day-title"
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: I18n.t("eod.title").arg(I18n.fmtDate(root.summary.date || new Date(), "weekdayDay"))
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
        }
        Text {
            objectName: "end-of-day-facts"
            Layout.topMargin: Theme.spXs
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.bottomMargin: root.carryRows.length === 0 && root.timerRows.length === 0 ? Theme.inset : 0
            Layout.fillWidth: true
            text: root.empty ? I18n.t("eod.empty") : root.factsLine()
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }

        ColumnLayout {
            objectName: "end-of-day-carryOver"
            visible: root.carryRows.length > 0
            Layout.topMargin: Theme.spLg
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spSm
                text: I18n.t("eod.carryHint")
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
            Repeater {
                model: root.carryRows
                delegate: ColumnLayout {
                    id: taskRow
                    required property var modelData
                    objectName: "end-of-day-task-" + modelData.id
                    Layout.fillWidth: true
                    spacing: Theme.spSm
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                    Text {
                        id: titleText
                        Layout.fillWidth: true
                        readonly property string st: root._statusOf(taskRow.modelData.id)
                        text: taskRow.modelData.title + (titleText.st.length > 0 ? " · " + titleText.st : "")
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsMd
                        font.underline: taskMA.hovered
                        elide: Text.ElideRight
                        ClickArea {
                            id: taskMA
                            objectName: "end-of-day-task-area-" + taskRow.modelData.id
                            label: taskRow.modelData.id + " " + taskRow.modelData.title
                            showTip: false
                            onActivated: {
                                root.close();
                                root.taskActivated(taskRow.modelData.id);
                            }
                        }
                    }
                    // What to do with a leftover is the person's call
                    // (APP-248): each acts on this task only, with an undo
                    // toast; leaving it is fine too.
                    Flow {
                        objectName: "end-of-day-carry-" + taskRow.modelData.id
                        Layout.fillWidth: true
                        Layout.bottomMargin: Theme.spMd
                        spacing: Theme.spXs
                        Repeater {
                            model: ["tomorrow", "window", "someday", "clear"]
                            delegate: PillButton {
                                required property string modelData
                                objectName: "end-of-day-carry-" + modelData
                                text: I18n.t("carry.btn." + modelData)
                                onClicked: root.carry(taskRow.modelData.id, modelData)
                            }
                        }
                    }
                }
            }
        }

        // A running timer, as a question with its answer one click away.
        ColumnLayout {
            objectName: "end-of-day-timers"
            visible: root.timerRows.length > 0
            Layout.topMargin: Theme.spMd
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.bottomMargin: Theme.inset
            Layout.fillWidth: true
            spacing: Theme.spXs
            Repeater {
                model: root.timerRows
                delegate: Text {
                    id: timerLine
                    required property var modelData
                    objectName: "end-of-day-timer-" + modelData.id
                    Layout.fillWidth: true
                    text: I18n.t("eod.timerRunning").arg(timerLine.modelData.title)
                    textFormat: Text.PlainText
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    wrapMode: Text.Wrap
                    ClickArea {
                        objectName: "end-of-day-stop-" + timerLine.modelData.id
                        label: I18n.t("eod.stopTimer")
                        onActivated: {
                            AppController.stopTaskTimer(timerLine.modelData.id);
                            root._read();
                        }
                    }
                }
            }
        }
        Item {
            visible: root.carryRows.length > 0 && root.timerRows.length === 0
            Layout.preferredHeight: Theme.inset - Theme.spMd
        }
    }
}
