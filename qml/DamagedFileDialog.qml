pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// At launch the data file did not parse (X/N-Err-Storage, R2-037). lowkey
// already set the damaged file aside and opened what it could — the newest
// backup, or an empty profile — and never deletes anything. This card says
// so and offers the time machine's newest snapshots: pick one and Restore
// (the state it replaces is snapshotted first, so a restore is undoable),
// or keep what is open now. Closing the card keeps what is open; every
// snapshot stays in the time machine (Ctrl K).
Popup {
    id: root
    objectName: "damaged-file"
    modal: true
    focus: true
    padding: 0
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    width: Math.min(456, (parent ? parent.width : 456) - 2 * Theme.sp2xl)
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: ModalScrim {}
    background: ModalSurface {}

    readonly property string state_: AppController.storageState
    readonly property bool recovered: state_ === "recovered"
    // Bound to the controller; a preview can set it by hand.
    property var args: AppController.storageArgs
    property var snapshots: []
    property int picked: 0

    // Snapshots this session took (of what opened after the damage) are not
    // offered: they hold nothing the person lost.
    readonly property double _startedAt: Date.now()
    function showIfNeeded() {
        if (root.state_ !== "damaged" && root.state_ !== "recovered") return;
        root.snapshots = AppController.listSnapshots()
            .filter(s => {
                // Snapshot names carry the minute only, hence the margin; an
                // empty one holds nothing to restore either.
                const t = new Date(s.at).getTime();
                const before = isNaN(t) || t < root._startedAt - 60000;
                return before && (Number(s.tasks) || 0) + (Number(s.notes) || 0) + (Number(s.docs) || 0) > 0;
            })
            .slice(0, 2);
        root.picked = 0;
        root.open();
    }
    function when(iso) {
        const d = new Date(iso);
        if (isNaN(d.getTime())) return "";
        const t = AppController.today;
        const diff = Math.round((new Date(t.getFullYear(), t.getMonth(), t.getDate())
                                 - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000);
        const time = I18n.fmtTime(d);
        if (diff === 0) return I18n.t("storage.when.today").arg(time);
        if (diff === 1) return I18n.t("storage.when.yesterday").arg(time);
        return I18n.fmtDateTime(d, "dayMonth");
    }
    // "18 230" / "18,230": a byte position read as a number.
    function groupDigits(n) {
        return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, I18n.lang === "ru" ? String.fromCharCode(160) : ",");
    }
    // The snapshots first, then what is open now.
    readonly property var options: {
        const out = [];
        for (let i = 0; i < root.snapshots.length; i++) {
            const s = root.snapshots[i];
            out.push({ kind: "snapshot", name: s.name,
                       label: I18n.t(i === 0 ? "storage.damaged.latest" : "storage.damaged.snapshot").arg(root.when(s.at)),
                       note: I18n.count(Number(s.tasks) || 0, "storage.damaged.tasks") });
        }
        out.push(root.recovered
                 ? { kind: "keep", name: "", label: I18n.t("storage.damaged.keepBackup").arg(root.args[0] || ""),
                     note: I18n.t("storage.damaged.keepBackupNote") }
                 : { kind: "keep", name: "", label: I18n.t("storage.damaged.empty"),
                     note: I18n.t("storage.damaged.emptyNote") });
        return out;
    }

    function restore() {
        const o = root.options[root.picked];
        root.close();
        if (o && o.kind === "snapshot") AppController.restoreSnapshot(o.name);
        AppController.dismissStorageNotice();
    }
    onClosed: if (AppController.storageState === "damaged" || AppController.storageState === "recovered")
                  AppController.dismissStorageNotice()
    onOpened: body.forceActiveFocus()

    contentItem: FocusScope {
        id: body
        implicitHeight: col.implicitHeight
        Keys.onUpPressed: root.picked = Math.max(0, root.picked - 1)
        Keys.onDownPressed: root.picked = Math.min(root.options.length - 1, root.picked + 1)
        Keys.onReturnPressed: root.restore()
        Keys.onEnterPressed: root.restore()

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0
            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.inset
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                text: I18n.t("storage.damaged.eyebrow")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
            Text {
                objectName: "damaged-file-title"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spMd
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                text: I18n.t("storage.damaged.title")
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsLg
                font.weight: Theme.fwHeading
            }
            Text {
                objectName: "damaged-file-fact"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spXs
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                // Where the file stops reading, then what was kept
                // (N/X-Err-Storage, R4-104); 13 px dim at 1.5 (R4-105).
                text: (AppController.storageDamagedAt >= 0
                       ? I18n.t("storage.damaged.at").arg(root.groupDigits(AppController.storageDamagedAt)) + " "
                       : "")
                      + (root.recovered ? I18n.t("storage.damaged.factBackup").arg(root.args[0] || "").arg(root.args[1] || "")
                                        : I18n.t("storage.damaged.fact").arg(root.args[0] || ""))
                textFormat: Text.PlainText
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                lineHeightMode: Text.FixedHeight
                lineHeight: Math.round(font.pixelSize * 1.5)
                wrapMode: Text.Wrap
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spLg
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                spacing: Theme.sp2xs
                Repeater {
                    model: root.options
                    delegate: Rectangle {
                        id: opt
                        required property var modelData
                        required property int index
                        objectName: "damaged-file-option-" + opt.index
                        readonly property bool on: root.picked === opt.index
                        Layout.fillWidth: true
                        implicitHeight: Theme.chipH + Theme.spSm
                        radius: Theme.radiusMd
                        color: opt.on && Style.fills ? Theme.withAlpha(Theme.text, 0.04) : "transparent"
                        border.width: opt.on ? 1 : 0
                        border.color: Theme.borderStrong
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spMd
                            anchors.rightMargin: Theme.spMd
                            spacing: Theme.spMd
                            Text {
                                Layout.fillWidth: true
                                text: opt.modelData.label
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsMd
                                font.weight: opt.on ? Theme.fwTitle : Theme.fwBody
                                elide: Text.ElideRight
                            }
                            Text {
                                text: opt.modelData.note
                                textFormat: Text.PlainText
                                color: Theme.textDim
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsSm
                            }
                        }
                        ClickArea {
                            label: opt.modelData.label
                            showTip: false
                            onActivated: root.picked = opt.index
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spLg
                Layout.bottomMargin: Theme.inset
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                spacing: Theme.spMd
                Item { Layout.fillWidth: true }
                PillButton {
                    objectName: "damaged-file-show"
                    text: I18n.t("storage.damaged.show")
                    onClicked: Qt.openUrlExternally("file:///" + AppController.dataDir)
                }
                PillButton {
                    objectName: "damaged-file-restore"
                    // "Restore" only when a snapshot is picked; keeping what is
                    // open restores nothing and says so (DATA-18).
                    text: (root.options[root.picked] || {}).kind === "snapshot"
                          ? I18n.t("storage.damaged.restore") : I18n.t("storage.damaged.continue")
                    primary: true
                    solid: Style.fills
                    onClicked: root.restore()
                }
            }
        }
    }
}
