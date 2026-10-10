pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// A field changed both here and in the tracker since the last sync (APP-163),
// drawn as X/N-Dlg-Conflict (R2-032): one table, a row per field, "Yours" and
// "In <tracker>" side by side, the picked version outlined. lowkey never picks
// a side on its own: every row starts on the local value, and nothing happens
// until "Apply choice" (or "All mine" / "All from <tracker>"). "Later" leaves
// the card flagged. Keeping my status sends it only where writes are on
// (Settings → Trackers); taking the tracker's title or description keeps
// mine in the task's notes. One undo step.
//
//   SyncConflictDialog { id: conflictDlg }
//   conflictDlg.showFor(task)   // task: the card's task map, with `ticket`
Popup {
    id: root
    objectName: "sync-conflict"
    modal: true
    focus: true
    padding: 0
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    width: Math.min(680, (parent ? parent.width : 680) - 2 * Theme.sp2xl)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: ModalScrim {}
    background: ModalSurface {}

    property var task: ({})
    readonly property var _ticket: (root.task && root.task.ticket) ? root.task.ticket : ({})
    readonly property string _tracker: {
        const b = AppController.providerBadges[root._ticket.provider || ""] || ({});
        return b.name || root._ticket.provider || "";
    }
    // field → "mine" | "theirs"; every row starts on the local value.
    property var picks: ({})

    function showFor(t) {
        root.task = t || ({});
        root.picks = ({});
        root.open();
    }
    function pickOf(field) { return root.picks[field] === "theirs" ? "theirs" : "mine"; }
    function setPick(field, side) {
        const p = Object.assign({}, root.picks);
        p[field] = side;
        root.picks = p;
    }

    function statusName(id) {
        const list = AppController.statuses;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i].name;
        return id || "—";
    }
    // "today 14:58", "yesterday 18:40", or a date with the time.
    function when(d) {
        if (!d || !d.getTime || isNaN(d.getTime())) return "";
        const today = AppController.today;
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        const ref = new Date(today.getFullYear(), today.getMonth(), today.getDate());
        const diff = Math.round((ref - day) / 86400000);
        const time = I18n.fmtTime(d);
        if (diff === 0) return I18n.t("conflict.today").arg(time);
        if (diff === 1) return I18n.t("conflict.yesterday").arg(time);
        return I18n.fmtDateTime(d, "dayMonth");
    }
    readonly property string subtitle: {
        if (!root.opened && !root.visible) return "";
        const theirs = root.when(root._ticket.updatedAt);
        const iso = root.task && root.task.id ? AppController.lastLocalEditAt(root.task.id) : "";
        const mine = iso.length > 0 ? root.when(new Date(iso)) : "";
        if (mine.length > 0 && theirs.length > 0)
            return I18n.t("conflict.when").arg(mine).arg(root._tracker).arg(theirs);
        if (theirs.length > 0) return I18n.t("conflict.whenTheirs").arg(root._tracker).arg(theirs);
        return I18n.t("conflict.pick");
    }
    // What the choice never touches: the person's own layer.
    readonly property string unchanged: {
        const t = root.task || ({});
        const parts = [I18n.t("conflict.unchanged.notes")];
        const due = t.dueAt;
        if (due && due.getTime && !isNaN(due.getTime()))
            parts.push(I18n.t("conflict.unchanged.due").arg(I18n.fmtDate(due, "weekdayDay")));
        const labels = (t.labels || []).map(l => l.id || l.name || String(l)).filter(s => s.length > 0);
        if (labels.length > 0) parts.push(I18n.t("conflict.unchanged.labels").arg(labels.join(", ")));
        parts.push(I18n.t("conflict.unchanged.links"));
        return I18n.t("conflict.unchanged").arg(parts.join(", "));
    }

    // One row per conflicting field: what lowkey has, what the tracker has.
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
                           mine: String(t.priority || "") || "—", theirs: String(k.remotePriority || "") || "—" });
            else if (f === "status")
                out.push({ field: f, label: I18n.t("ticket.conflict.status"),
                           mine: root.statusName(t.status), theirs: root.statusName(k.remoteColumn),
                           mineCat: AppController.statusCategory(t.status || ""),
                           theirsCat: AppController.statusCategory(k.remoteColumn || "") });
        }
        return out;
    }
    // Resolved everything: nothing left to show.
    onRowsChanged: if (root.opened && root.rows.length === 0) root.close()

    function apply(mode) {
        if (!root.task || !root.task.id) return;
        const mine = [], theirs = [];
        for (const r of root.rows) {
            const side = mode === "mine" ? "mine" : mode === "theirs" ? "theirs" : root.pickOf(r.field);
            (side === "theirs" ? theirs : mine).push(r.field);
        }
        const id = root.task.id;
        root.close();
        AppController.resolveTrackerConflictChoices(id, mine, theirs);
    }

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

    property int _row: 0
    // The cursor ring shows once the keyboard picks, not on open.
    property bool _keys: false
    onOpened: { root._row = 0; root._keys = false; body.forceActiveFocus(); }

    contentItem: FocusScope {
        id: body
        implicitHeight: col.implicitHeight
        Keys.onUpPressed: { root._keys = true; root._row = Math.max(0, root._row - 1); }
        Keys.onDownPressed: { root._keys = true; root._row = Math.min(root.rows.length - 1, root._row + 1); }
        Keys.onLeftPressed: { root._keys = true; if (root.rows.length > 0) root.setPick(root.rows[root._row].field, "mine"); }
        Keys.onRightPressed: { root._keys = true; if (root.rows.length > 0) root.setPick(root.rows[root._row].field, "theirs"); }
        Keys.onReturnPressed: root.apply("pick")
        Keys.onEnterPressed: root.apply("pick")

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            Text {
                objectName: "sync-conflict-title"
                Layout.fillWidth: true
                Layout.topMargin: Theme.inset
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                text: I18n.t("conflict.title").arg(root._ticket.key || (root.task ? root.task.id || "" : "")).arg(root._tracker)
                textFormat: Text.PlainText
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsLg
                font.weight: Theme.fwHeading
                wrapMode: Text.Wrap
            }
            Text {
                objectName: "sync-conflict-sub"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spXs
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                text: root.subtitle
                textFormat: Text.PlainText
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                wrapMode: Text.Wrap
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spLg
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                implicitHeight: 1
                color: Theme.border
            }

            // Column heads: the field, then the two sides.
            Item {
                id: grid
                Layout.fillWidth: true
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                implicitHeight: headRow.implicitHeight + Theme.spMd
                readonly property real labelW: Math.round(width * 0.16)
                readonly property real cellW: Math.floor((width - labelW) / 2)
                Row {
                    id: headRow
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spXs
                    Item { width: grid.labelW; height: 1 }
                    Text {
                        width: grid.cellW
                        leftPadding: Theme.spMd
                        text: I18n.t("conflict.mine")
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsXs
                    }
                    Text {
                        width: grid.cellW
                        leftPadding: Theme.spMd
                        text: I18n.t("conflict.theirs").arg(root._tracker)
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsXs
                    }
                }
            }
            Repeater {
                model: root.rows
                delegate: ColumnLayout {
                    id: row
                    required property var modelData
                    required property int index
                    objectName: "sync-conflict-row-" + row.modelData.field
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    spacing: 0
                    readonly property string pick: root.picks && root.pickOf(row.modelData.field)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Theme.border
                    }
                    Row {
                        Layout.fillWidth: true
                        Text {
                            width: grid.labelW
                            height: mineCell.height
                            verticalAlignment: Text.AlignVCenter
                            text: row.modelData.label
                            textFormat: Text.PlainText
                            color: Theme.textDim
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsMd
                            elide: Text.ElideRight
                        }
                        ConflictCell {
                            id: mineCell
                            objectName: "sync-conflict-mine-" + row.modelData.field
                            width: grid.cellW
                            text: row.modelData.mine
                            category: row.modelData.mineCat || ""
                            picked: row.pick === "mine"
                            cursor: body.activeFocus && root._keys && root._row === row.index && row.pick === "mine"
                            onChosen: { root._row = row.index; root.setPick(row.modelData.field, "mine"); }
                        }
                        ConflictCell {
                            objectName: "sync-conflict-theirs-" + row.modelData.field
                            width: grid.cellW
                            text: row.modelData.theirs
                            category: row.modelData.theirsCat || ""
                            picked: row.pick === "theirs"
                            cursor: body.activeFocus && root._keys && root._row === row.index && row.pick === "theirs"
                            onChosen: { root._row = row.index; root.setPick(row.modelData.field, "theirs"); }
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                implicitHeight: 1
                color: Theme.border
            }
            Text {
                objectName: "sync-conflict-unchanged"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spLg
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                text: root.unchanged
                textFormat: Text.PlainText
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spLg
                Layout.bottomMargin: Theme.inset
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                spacing: Theme.spMd
                PillButton {
                    objectName: "sync-conflict-later"
                    text: I18n.t("conflict.later")
                    onClicked: root.close()
                }
                Item { Layout.fillWidth: true }
                PillButton {
                    objectName: "sync-conflict-all-theirs"
                    text: I18n.t("conflict.allTheirs").arg(root._tracker)
                    onClicked: root.apply("theirs")
                }
                PillButton {
                    objectName: "sync-conflict-all-mine"
                    text: I18n.t("conflict.allMine")
                    onClicked: root.apply("mine")
                }
                PillButton {
                    objectName: "sync-conflict-apply"
                    text: I18n.t("conflict.apply")
                    primary: true
                    solid: Style.fills
                    keyHint: "↵"
                    onClicked: root.apply("pick")
                }
            }
        }
    }

    // One side of one field: plain when not picked, outlined and bright when
    // picked. A status shows its ring.
    component ConflictCell: Item {
        id: cell
        property string text: ""
        property string category: ""
        property bool picked: false
        property bool cursor: false
        signal chosen()
        implicitHeight: Math.max(Theme.chipH + Theme.spMd, cellText.implicitHeight + 2 * Theme.spMd)
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            radius: Theme.radiusMd
            // N/X-Dlg-Conflict: the picked side is an outline on the dialog,
            // no fill (R4-113).
            color: "transparent"
            border.width: cell.picked ? 1 : 0
            border.color: cell.cursor ? Theme.focusRing : Theme.buttonLinePrimary
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spMd
            anchors.rightMargin: Theme.spMd
            spacing: Theme.spSm
            StatusRing {
                visible: cell.category.length > 0
                category: cell.category
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                id: cellText
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: cell.text
                textFormat: Text.PlainText
                color: cell.picked ? Theme.text : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
        ClickArea {
            label: I18n.t("conflict.pickCell") + ": " + cell.text
            showTip: false
            onActivated: cell.chosen()
        }
    }
}
