pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// A field changed both here and in the tracker since the last sync (APP-163).
// heap keeps the local value and never picks a side on its own: this dialog
// shows both, field by field, and the user decides. "Keep mine" on a status
// sends it to the tracker; on a title, description or priority it only stops
// the flag (those are never pushed). "Take the tracker's" puts the tracker's
// value on the card. Each choice is one undo step.
//
//   SyncConflictDialog { id: conflictDlg }
//   conflictDlg.showFor(task)   // task: the card's task map, with `ticket`
Dialog {
    id: root
    objectName: "sync-conflict"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: Theme.inset
    width: 520
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property var task: ({})
    readonly property var _ticket: (root.task && root.task.ticket) ? root.task.ticket : ({})

    function showFor(t) {
        root.task = t || ({});
        root.open();
    }

    function statusName(id) {
        const list = AppController.statuses;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i].name;
        return id || "—";
    }

    // One row per conflicting field: what heap has, what the tracker has.
    readonly property var rows: {
        const t = root.task || ({});
        const k = root._ticket;
        const fields = k.conflicts || [];
        const out = [];
        for (let i = 0; i < fields.length; ++i) {
            const f = fields[i];
            if (f === "title")
                out.push({ field: f, label: I18n.t("ticket.conflict.title"),
                           mine: String(t.title || ""), theirs: String(k.remoteTitle || "") });
            else if (f === "body")
                out.push({ field: f, label: I18n.t("ticket.conflict.body"),
                           mine: String(t.desc || "") || "—", theirs: String(k.remoteBody || "") || "—" });
            else if (f === "priority")
                out.push({ field: f, label: I18n.t("ticket.conflict.priority"),
                           mine: String(t.priority || ""), theirs: String(k.remotePriority || "") });
            else if (f === "status")
                out.push({ field: f, label: I18n.t("ticket.conflict.status"),
                           mine: root.statusName(t.status),
                           theirs: root.statusName(k.remoteColumn)
                                   + (k.remoteStatus ? " (" + k.remoteStatus + ")" : "") });
        }
        return out;
    }
    // Resolved everything: nothing left to show.
    onRowsChanged: if (root.opened && root.rows.length === 0) root.close()

    // The task map is a snapshot; the dialog follows the live row.
    Connections {
        target: AppController
        function onTrackerConflictResolved(taskId) {
            if (!root.task || taskId !== root.task.id) return;
            const fresh = AppController.taskById(taskId);
            if (fresh && fresh.id) root.task = fresh;
            else root.close();
        }
    }

    title: I18n.t("sync.conflict.title").arg(root._ticket.key || (root.task ? root.task.id || "" : ""))
    header: DialogHeader { text: root.title }
    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: Theme.spLg
        Text {
            Layout.fillWidth: true
            text: I18n.t("sync.conflict.body")
            textFormat: Text.PlainText
            color: Theme.textMuted
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }
        Repeater {
            model: root.rows
            delegate: ColumnLayout {
                id: row
                required property var modelData
                objectName: "sync-conflict-row-" + row.modelData.field
                Layout.fillWidth: true
                spacing: Theme.spXs
                Text {
                    text: row.modelData.label
                    textFormat: Text.PlainText
                    color: Theme.text
                    font.pixelSize: Theme.fsSm
                    font.weight: Theme.fwTitle
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Theme.spLg
                    rowSpacing: Theme.spXs
                    Text {
                        text: I18n.t("sync.conflict.here")
                        color: Theme.textDim
                        font.pixelSize: Theme.fsXs
                    }
                    Text {
                        objectName: "sync-conflict-mine"
                        Layout.fillWidth: true
                        text: row.modelData.mine
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                    }
                    Text {
                        text: I18n.t("sync.conflict.tracker")
                        color: Theme.textDim
                        font.pixelSize: Theme.fsXs
                    }
                    Text {
                        objectName: "sync-conflict-theirs"
                        Layout.fillWidth: true
                        text: row.modelData.theirs
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                    }
                }
                RowLayout {
                    spacing: Theme.spSm
                    PillButton {
                        objectName: "sync-conflict-keep-" + row.modelData.field
                        text: row.modelData.field === "status" ? I18n.t("sync.conflict.keepAndSend")
                                                               : I18n.t("ticket.conflict.keepMine")
                        onClicked: AppController.resolveTrackerConflictField(root.task.id, row.modelData.field, false)
                    }
                    PillButton {
                        objectName: "sync-conflict-take-" + row.modelData.field
                        text: I18n.t("sync.conflict.takeTracker")
                        onClicked: AppController.resolveTrackerConflictField(root.task.id, row.modelData.field, true)
                    }
                }
            }
        }
    }

    footer: DialogFooter {
        Item { Layout.fillWidth: true }
        PillButton {
            objectName: "sync-conflict-close"
            text: I18n.t("common.close")
            onClicked: root.close()
        }
    }
}
