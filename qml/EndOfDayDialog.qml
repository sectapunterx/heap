pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The day's summary (APP-190), from the end-of-day check in Settings → Safety
// net, or from the palette at any time:
//
//   Closed today              3
//     APP-12  Login rate limit
//   Carries over to tomorrow  2
//     APP-14  CSV export
//   Timers running            1
//     APP-15  Cache tuning           since 14:00
//
// Nothing is moved, rescheduled or stopped on its own. A leftover has its
// buttons — tomorrow, the next free window, someday, no date (APP-248) — for
// the person to press or ignore. A task in the list opens in the editor.
Dialog {
    id: root
    objectName: "end-of-day"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: Theme.inset
    width: 520
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property var summary: ({ closed: [], carryOver: [], timers: [] })
    readonly property var sections: [
        { key: "closed",    title: I18n.t("eod.closed"),    rows: root.summary.closed || [] },
        { key: "carryOver", title: I18n.t("eod.carryOver"), rows: root.summary.carryOver || [] },
        { key: "timers",    title: I18n.t("eod.timers"),    rows: root.summary.timers || [] }
    ]
    readonly property bool empty: root.sections.every(s => s.rows.length === 0)

    signal taskActivated(string id)

    // A leftover carried on by hand; the list is read again, so it leaves
    // the "carries over" section once it has a new day.
    function carry(id, mode) {
        AppController.carryTasks([id], mode);
        root.summary = AppController.endOfDaySummary();
    }

    function showNow() {
        root.summary = AppController.endOfDaySummary();
        root.open();
    }

    header: DialogHeader {
        text: I18n.t("eod.title").arg(I18n.fmtDate(root.summary.date || new Date(), "weekdayDay"))
    }
    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: Theme.spLg

        Text {
            objectName: "end-of-day-empty"
            visible: root.empty
            Layout.fillWidth: true
            text: I18n.t("eod.empty")
            color: Theme.textMuted
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }

        Flickable {
            id: flick
            visible: !root.empty
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(sectionsCol.implicitHeight, 420)
            contentHeight: sectionsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: sectionsCol
                width: flick.width
                spacing: Theme.spLg

                Repeater {
                    model: root.sections
                    delegate: ColumnLayout {
                        id: sec
                        required property var modelData
                        objectName: "end-of-day-" + modelData.key
                        visible: modelData.rows.length > 0
                        Layout.fillWidth: true
                        spacing: Theme.spXs

                        RowLayout {
                            spacing: Theme.spSm
                            Text { text: sec.modelData.title; color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Theme.fwTitle }
                            Text {
                                text: sec.modelData.rows.length
                                color: Theme.textDim
                                font.pixelSize: Theme.fsSm
                                font.features: Theme.tabularNums
                            }
                        }
                        Text {
                            visible: sec.modelData.key === "carryOver"
                            text: I18n.t("eod.carryHint")
                            color: Theme.textDim
                            font.pixelSize: Theme.fsXs
                        }

                        Repeater {
                            model: sec.modelData.rows
                            delegate: Rectangle {
                                id: taskRow
                                required property var modelData
                                objectName: "end-of-day-task-" + modelData.id
                                Layout.fillWidth: true
                                readonly property bool carry: sec.modelData.key === "carryOver"
                                implicitHeight: taskLine.implicitHeight + Theme.spSm * 2
                                                + (taskRow.carry ? carryRow.implicitHeight + Theme.spXs : 0)
                                radius: Theme.radiusMd
                                color: taskMA.hovered ? Theme.panel3 : "transparent"
                                RowLayout {
                                    id: taskLine
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: Theme.spSm
                                    anchors.leftMargin: Theme.spXl
                                    anchors.rightMargin: Theme.spMd
                                    spacing: Theme.spMd
                                    Text {
                                        // A fixed column, so the titles line up.
                                        Layout.preferredWidth: 72
                                        elide: Text.ElideRight
                                        text: taskRow.modelData.id
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fsXs
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: taskRow.modelData.title
                                        textFormat: Text.PlainText
                                        color: Theme.text
                                        font.pixelSize: Theme.fsSm
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: !!taskRow.modelData.since
                                        text: taskRow.modelData.since ? I18n.t("eod.since").arg(I18n.fmtTime(taskRow.modelData.since)) : ""
                                        color: Theme.textDim
                                        font.pixelSize: Theme.fsXs
                                        font.features: Theme.tabularNums
                                    }
                                }
                                // What to do with a leftover is the person's call
                                // (APP-248): each button acts on this task only,
                                // with an undo toast; leaving it is fine too.
                                Flow {
                                    id: carryRow
                                    objectName: "end-of-day-carry-" + taskRow.modelData.id
                                    visible: taskRow.carry
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: taskLine.bottom
                                    anchors.topMargin: Theme.spXs
                                    anchors.leftMargin: Theme.spXl
                                    spacing: Theme.spXs
                                    z: 2
                                    Repeater {
                                        model: taskRow.carry ? ["tomorrow", "window", "someday", "clear"] : []
                                        delegate: PillButton {
                                            required property string modelData
                                            objectName: "end-of-day-carry-" + modelData
                                            text: I18n.t("carry.btn." + modelData)
                                            onClicked: root.carry(taskRow.modelData.id, modelData)
                                        }
                                    }
                                }
                                ClickArea {
                                    id: taskMA
                                    // Over the line, not the carry buttons under it.
                                    anchors.fill: undefined
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: taskLine.implicitHeight + Theme.spSm * 2
                                    objectName: "end-of-day-task-area-" + taskRow.modelData.id
                                    label: taskRow.modelData.id + " " + taskRow.modelData.title
                                    showTip: false
                                    onActivated: {
                                        root.close();
                                        root.taskActivated(taskRow.modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    footer: DialogFooter {
        PillButton {
            id: closeBtn
            objectName: "end-of-day-close"
            text: I18n.t("common.close")
            primary: true
            onClicked: root.close()
        }
    }
    onOpened: closeBtn.forceActiveFocus()
}
