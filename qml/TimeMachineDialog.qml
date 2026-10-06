pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The time machine (APP-162): the hourly snapshots in <dataDir>/history, and a
// way back to any of them.
//
//   Today                 │ State at 14:00, 5 Oct
//     14:00  120 tasks    │ Tasks since then: 2 added, 1 deleted, 5 changed
//     13:00  119 tasks    │ Profiles      work · 118 tasks   [Restore as copy]
//   Yesterday             │ Deleted since then
//     23:00  …            │   Task  APP-12  Login rate limit   [Restore]
//                         │                       [Restore everything] [Close]
//
// Keyboard: the list has focus on open, Up/Down picks a moment, Tab walks the
// actions, Esc closes. Restoring one item is undoable (Ctrl+Z); restoring
// everything snapshots the current state first, so it shows up in this list.
Dialog {
    id: root
    objectName: "time-machine"
    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: Theme.inset
    width: Math.min(880, (parent ? parent.width : 880) - 2 * Theme.sp3xl)
    height: Math.min(600, (parent ? parent.height : 600) - 2 * Theme.sp3xl)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property var snapshots: []
    property var preview: ({})
    readonly property var current: snapList.currentIndex >= 0 && snapList.currentIndex < root.snapshots.length
                                   ? root.snapshots[snapList.currentIndex] : null

    readonly property var dataSettings: {
        try { return (JSON.parse(AppController.appSettingsJson || "{}") || {}).data || {}; } catch (e) { return {}; }
    }
    readonly property int keepDays: root.dataSettings.historyDays || 30
    readonly property int capMb: root.dataSettings.historyMaxMb || 200

    function showNow() {
        root.reload();
        root.open();
    }

    function reload() {
        const keep = root.current ? root.current.name : "";
        root.snapshots = AppController.listSnapshots();
        let idx = root.snapshots.length > 0 ? 0 : -1;
        for (let i = 0; i < root.snapshots.length; i++)
            if (root.snapshots[i].name === keep) idx = i;
        snapList.currentIndex = idx;
        root.loadPreview();
    }

    function loadPreview() {
        root.preview = root.current ? AppController.previewSnapshot(root.current.name) : ({});
    }

    function setData(key, value) {
        let s = {};
        try { s = JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { s = {}; }
        const d = Object.assign({}, s.data || {});
        d[key] = value;
        s.data = d;
        AppController.appSettingsJson = JSON.stringify(s);
    }

    function dayLabel(iso) {
        const today = new Date();
        const p2 = (n) => (n < 10 ? "0" : "") + n;
        const key = (d) => d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate());
        if (iso === key(today)) return I18n.t("tm.today");
        const y = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);
        if (iso === key(y)) return I18n.t("tm.yesterday");
        const loc = Qt.locale(I18n.lang === "ru" ? "ru_RU" : "en_US");
        return new Date(iso + "T00:00:00").toLocaleDateString(loc, "ddd, d MMM");
    }

    function kindLabel(kind) {
        return kind === "task" ? I18n.t("tm.kind.task") : kind === "doc" ? I18n.t("tm.kind.doc") : I18n.t("tm.kind.note");
    }

    function restoreItem(row) {
        if (!root.current) return;
        if (AppController.restoreSnapshotItem(root.current.name, row.kind, row.profileId, row.id))
            root.loadPreview();
    }

    // One task, note or page in the "deleted" / "changed" lists.
    component ItemRow: Rectangle {
        id: itemRow
        required property var modelData
        property string actionText: ""
        signal restore()
        Layout.fillWidth: true
        implicitHeight: itemLine.implicitHeight + Theme.spXs * 2
        radius: Theme.radiusMd
        color: "transparent"
        RowLayout {
            id: itemLine
            anchors.fill: parent
            anchors.leftMargin: Theme.spSm
            spacing: Theme.spMd
            Text {
                Layout.preferredWidth: 64
                elide: Text.ElideRight
                text: root.kindLabel(itemRow.modelData.kind)
                color: Theme.textDim
                font.pixelSize: Theme.fsXs
            }
            Text {
                visible: itemRow.modelData.kind === "task"
                text: itemRow.modelData.id
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: itemRow.modelData.title + "  · " + itemRow.modelData.profileName
                color: Theme.text
                font.pixelSize: Theme.fsSm
            }
            PillButton {
                text: itemRow.actionText
                enabled: itemRow.modelData.profileExists
                ToolTip.visible: !itemRow.modelData.profileExists && hovered
                ToolTip.text: I18n.t("tm.profileGone.tip")
                onClicked: itemRow.restore()
            }
        }
    }

    // Arrowing through a month of snapshots must not inflate every one on the way.
    Timer {
        id: previewDebounce
        interval: 120
        onTriggered: root.loadPreview()
    }

    header: DialogHeader { text: I18n.t("tm.title") }
    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: RowLayout {
        spacing: Theme.inset

        // ── Left: the moments ──
        ColumnLayout {
            Layout.preferredWidth: 260
            Layout.maximumWidth: 260
            Layout.fillHeight: true
            spacing: Theme.spSm

            Text {
                visible: root.snapshots.length === 0
                Layout.fillWidth: true
                text: I18n.t("tm.empty")
                color: Theme.textMuted
                font.pixelSize: Theme.fsSm
                wrapMode: Text.Wrap
            }

            ListView {
                id: snapList
                objectName: "time-machine-list"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                focus: true
                activeFocusOnTab: true
                keyNavigationEnabled: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.snapshots
                currentIndex: -1
                highlightMoveDuration: 0
                ScrollBar.vertical: ThinScrollBar {}
                onCurrentIndexChanged: previewDebounce.restart()
                Keys.onReturnPressed: root.loadPreview()

                section.property: "day"
                section.criteria: ViewSection.FullString
                section.delegate: Text {
                    required property string section
                    width: snapList.width
                    topPadding: Theme.spMd
                    bottomPadding: Theme.spXs
                    text: root.dayLabel(section)
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm
                    font.weight: Theme.fwTitle
                }

                delegate: Rectangle {
                    id: snapRow
                    required property var modelData
                    required property int index
                    objectName: "time-machine-snap-" + index
                    width: snapList.width
                    implicitHeight: snapLine.implicitHeight + Theme.spSm * 2
                    radius: Theme.radiusMd
                    color: snapList.currentIndex === index
                           ? (snapList.activeFocus ? Theme.accentSoft : Theme.panel3)
                           : (snapMA.hovered ? Theme.panel2 : "transparent")
                    RowLayout {
                        id: snapLine
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spMd
                        anchors.rightMargin: Theme.spMd
                        spacing: Theme.spMd
                        Text {
                            text: snapRow.modelData.time
                            color: Theme.text
                            font.family: Theme.fontUi
                            font.features: Theme.tabularNums
                            font.pixelSize: Theme.fsMd
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: snapRow.modelData.tag === "pre"
                                  ? I18n.t("tm.tag.pre")
                                  : I18n.t("tm.row.counts").arg(snapRow.modelData.tasks).arg(snapRow.modelData.notes + snapRow.modelData.docs)
                            color: snapRow.modelData.tag === "pre" ? Theme.warning : Theme.textMuted
                            font.pixelSize: Theme.fsSm
                        }
                    }
                    ClickArea {
                        id: snapMA
                        label: snapRow.modelData.time
                        showTip: false
                        activeFocusOnTab: false
                        onActivated: {
                            snapList.currentIndex = snapRow.index;
                            snapList.forceActiveFocus();
                        }
                    }
                }
            }

            // Retention, next to what it keeps.
            RowLayout {
                spacing: Theme.spSm
                Text { text: I18n.t("tm.keep"); color: Theme.textMuted; font.pixelSize: Theme.fsXs }
                Repeater {
                    model: [7, 30, 90]
                    delegate: PillButton {
                        required property int modelData
                        objectName: "time-machine-days-" + modelData
                        text: I18n.t("tm.keep.days").arg(modelData)
                        selected: root.keepDays === modelData
                        onClicked: root.setData("historyDays", modelData)
                    }
                }
            }
            RowLayout {
                spacing: Theme.spSm
                Text { text: I18n.t("tm.cap"); color: Theme.textMuted; font.pixelSize: Theme.fsXs }
                Repeater {
                    model: [100, 200, 500]
                    delegate: PillButton {
                        required property int modelData
                        objectName: "time-machine-cap-" + modelData
                        text: I18n.t("tm.cap.mb").arg(modelData)
                        selected: root.capMb === modelData
                        onClicked: root.setData("historyMaxMb", modelData)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 1
            color: Theme.border
        }

        // ── Right: that moment, next to now ──
        Flickable {
            id: detail
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: detailCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThinScrollBar {}

            ColumnLayout {
                id: detailCol
                width: detail.width
                spacing: Theme.spLg

                Text {
                    visible: !root.current
                    text: I18n.t("tm.pick")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fsMd
                }
                Text {
                    visible: !!root.current && root.preview.ok === false
                    Layout.fillWidth: true
                    text: root.preview.error || ""
                    color: Theme.danger
                    font.pixelSize: Theme.fsMd
                    wrapMode: Text.Wrap
                }

                ColumnLayout {
                    visible: !!root.current && root.preview.ok === true
                    Layout.fillWidth: true
                    spacing: Theme.spLg

                    Text {
                        objectName: "time-machine-state-at"
                        Layout.fillWidth: true
                        text: root.current
                              ? I18n.t("tm.stateAt").arg(root.current.time + ", " + root.dayLabel(root.current.day))
                              : ""
                        color: Theme.text
                        font.pixelSize: Theme.fsLg
                        font.weight: Theme.fwTitle
                        wrapMode: Text.Wrap
                    }
                    Text {
                        readonly property var t: root.preview.totals || ({})
                        objectName: "time-machine-since-tasks"
                        Layout.fillWidth: true
                        text: I18n.t("tm.since.tasks").arg(t.tasksAdded || 0).arg(t.tasksRemoved || 0).arg(t.tasksChanged || 0)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.Wrap
                    }
                    Text {
                        readonly property var t: root.preview.totals || ({})
                        Layout.fillWidth: true
                        text: I18n.t("tm.since.notes").arg(t.notesAdded || 0).arg(t.notesRemoved || 0).arg(t.notesChanged || 0)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.Wrap
                    }

                    // Profiles of that moment.
                    Text {
                        text: I18n.t("tm.profiles")
                        color: Theme.textDim
                        font.pixelSize: Theme.fsSm
                        font.weight: Theme.fwTitle
                    }
                    Repeater {
                        model: root.preview.profiles || []
                        delegate: RowLayout {
                            id: profRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.spMd
                            Rectangle {
                                implicitWidth: 8; implicitHeight: 8; radius: 4
                                color: profRow.modelData.color || Theme.textDim
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: profRow.modelData.name + (profRow.modelData.existsNow ? "" : "  · " + I18n.t("tm.profile.gone"))
                                    color: Theme.text
                                    font.pixelSize: Theme.fsMd
                                }
                                Text {
                                    text: I18n.t("tm.profile.counts").arg(profRow.modelData.tasks).arg(profRow.modelData.notes).arg(profRow.modelData.docs)
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fsXs
                                }
                            }
                            PillButton {
                                objectName: "time-machine-profile-copy-" + profRow.modelData.id
                                text: I18n.t("tm.profile.restoreCopy")
                                onClicked: {
                                    if (root.current)
                                        AppController.restoreSnapshotProfile(root.current.name, profRow.modelData.id);
                                }
                            }
                        }
                    }

                    // What was there and is not any more.
                    Text {
                        text: I18n.t("tm.missing")
                        color: Theme.textDim
                        font.pixelSize: Theme.fsSm
                        font.weight: Theme.fwTitle
                    }
                    Text {
                        visible: (root.preview.missing || []).length === 0
                        text: I18n.t("tm.missing.none")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                    }
                    Repeater {
                        model: root.preview.missing || []
                        delegate: ItemRow {
                            id: missingRow
                            objectName: "time-machine-missing-" + missingRow.modelData.id
                            actionText: I18n.t("tm.restoreItem")
                            onRestore: root.restoreItem(missingRow.modelData)
                        }
                    }

                    Text {
                        visible: (root.preview.changed || []).length > 0
                        text: I18n.t("tm.changed")
                        color: Theme.textDim
                        font.pixelSize: Theme.fsSm
                        font.weight: Theme.fwTitle
                    }
                    Repeater {
                        model: root.preview.changed || []
                        delegate: ItemRow {
                            id: changedRow
                            objectName: "time-machine-changed-" + changedRow.modelData.id
                            actionText: I18n.t("tm.restoreVersion")
                            onRestore: root.restoreItem(changedRow.modelData)
                        }
                    }
                }
            }
        }
    }

    footer: DialogFooter {
        Text {
            visible: !!root.current
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            text: I18n.t("tm.restoreAll.hint")
            color: Theme.textMuted
            font.pixelSize: Theme.fsXs
            wrapMode: Text.Wrap
        }
        // Two presses: the first arms, the second (within 3.5 s) restores.
        PillButton {
            id: restoreAllBtn
            objectName: "time-machine-restore-all"
            property bool armed: false
            enabled: !!root.current && root.preview.ok === true
            danger: restoreAllBtn.armed
            text: restoreAllBtn.armed ? I18n.t("tm.restoreAll.confirm") : I18n.t("tm.restoreAll")
            Timer { id: disarm; interval: 3500; onTriggered: restoreAllBtn.armed = false }
            onClicked: {
                if (!restoreAllBtn.armed) {
                    restoreAllBtn.armed = true;
                    disarm.restart();
                    return;
                }
                restoreAllBtn.armed = false;
                disarm.stop();
                if (AppController.restoreSnapshot(root.current.name))
                    root.close();
            }
        }
        PillButton {
            objectName: "time-machine-close"
            text: I18n.t("common.close")
            primary: true
            onClicked: root.close()
        }
    }

    onOpened: snapList.forceActiveFocus()
    onClosed: restoreAllBtn.armed = false
}
