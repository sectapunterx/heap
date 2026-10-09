pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The time machine (APP-162, X-Dlg-TimeMachine): the snapshots in
// <dataDir>/history, and a way back to any of them. First what would change,
// then the restore; the current state is saved as a snapshot before it.
//
//   Снимки · 14 за 2 недели │ Вчера, 18:40
//   Сегодня                 │ ежечасный · профиль Example
//     09:12 · ежечасный 15  │ Если восстановить, по сравнению с сейчас
//   Вчера                   │ Задачи     вернутся 1 удалённая (APP-099) …
//     18:40 · …        14   │ Изменения  5 задач — статусы и сроки как тогда
//                           │ [Открыть копией в новом профиле] [Показать файл]
//                           │                     [Восстановить эту версию…]
//
// Keyboard: the list has focus on open, Up/Down picks a moment, Tab walks the
// actions, Esc closes. A deleted task's id in the diff brings back that one
// task (undoable); restoring everything asks twice and snapshots first.
Popup {
    id: root
    objectName: "time-machine"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: 0
    width: Math.min(1100, (parent ? parent.width : 1100) - 2 * Theme.sp3xl)
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

    function _key(d) {
        const p2 = (n) => (n < 10 ? "0" : "") + n;
        return d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate());
    }
    // "today" | "yesterday" | "earlier" — the list's sections.
    function groupOf(iso) {
        const today = new Date();
        if (iso === root._key(today)) return "today";
        if (iso === root._key(new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1))) return "yesterday";
        return "earlier";
    }
    function reload() {
        const keep = root.current ? root.current.name : "";
        root.snapshots = AppController.listSnapshots().map(s => Object.assign({ grp: root.groupOf(s.day) }, s));
        let idx = root.snapshots.length > 0 ? 0 : -1;
        for (let i = 0; i < root.snapshots.length; i++)
            if (root.snapshots[i].name === keep) idx = i;
        snapList.currentIndex = idx;
        root.loadPreview();
    }
    function loadPreview() {
        root.preview = root.current ? AppController.previewSnapshot(root.current.name) : ({});
        restoreAllBtn.armed = false;
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
        const g = root.groupOf(iso);
        if (g === "today") return I18n.t("tm.today");
        if (g === "yesterday") return I18n.t("tm.yesterday");
        return I18n.fmtDate(new Date(iso + "T00:00:00"), "dayMonth");
    }
    // What kind of snapshot: the hourly one, or one taken before something.
    function kindText(tag) {
        if (!tag) return I18n.t("tm.kind.hourly");
        if (tag === "pre") return I18n.t("tm.tag.pre");
        return tag;
    }
    function rowText(s) {
        const lead = s.grp === "earlier" ? root.dayLabel(s.day) : s.time;
        return lead + " · " + root.kindText(s.tag);
    }
    function listHead() {
        const n = root.snapshots.length;
        if (n === 0) return I18n.t("tm.listHead.none");
        const a = new Date(root.snapshots[n - 1].day + "T00:00:00");
        const b = new Date(root.snapshots[0].day + "T00:00:00");
        const days = Math.max(1, Math.round((b - a) / 86400000) + 1);
        return I18n.t("tm.listHead").arg(n).arg(I18n.count(days, "tm.days"));
    }
    function profileLine() {
        const ps = root.preview.profiles || [];
        if (ps.length === 1) return I18n.t("tm.profileOne").arg(ps[0].name);
        return I18n.count(ps.length, "tm.profilesN");
    }

    // ── the diff, row by row ──
    readonly property var _missingTasks: (root.preview.missing || []).filter(m => m.kind === "task")
    readonly property var _totals: root.preview.totals || ({})
    function _esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
    function tasksText() {
        const parts = [];
        const back = root._missingTasks;
        if (back.length > 0) {
            const ids = back.slice(0, 5).map(m => "<a href=\"" + root._esc(m.id) + "\">" + root._esc(m.id) + "</a>").join(", ");
            parts.push(I18n.count(back.length, "tm.diff.tasksBack") + " (" + ids + (back.length > 5 ? ", …" : "") + ")");
        }
        const added = root._totals.tasksAdded || 0;
        if (added > 0) parts.push(I18n.count(added, "tm.diff.tasksGone"));
        return parts.length > 0 ? parts.join(", ") : I18n.t("tm.diff.same");
    }
    function changesText() {
        const n = root._totals.tasksChanged || 0;
        return n > 0 ? I18n.count(n, "tm.diff.changed") : I18n.t("tm.diff.same");
    }
    function notesText() {
        const t = root._totals;
        const parts = [];
        if ((t.notesRemoved || 0) > 0) parts.push(I18n.count(t.notesRemoved, "tm.diff.notesBack"));
        if ((t.notesAdded || 0) > 0) parts.push(I18n.count(t.notesAdded, "tm.diff.notesGone"));
        if ((t.notesChanged || 0) > 0) parts.push(I18n.count(t.notesChanged, "tm.diff.notesChanged"));
        return parts.length > 0 ? parts.join(", ") : I18n.t("tm.diff.same");
    }
    readonly property var diffRows: [
        { k: I18n.t("tm.diff.k.tasks"), v: root.tasksText(), links: true },
        { k: I18n.t("tm.diff.k.changes"), v: root.changesText(), links: false },
        { k: I18n.t("tm.diff.k.notes"), v: root.notesText(), links: false },
        { k: I18n.t("tm.diff.k.events"), v: I18n.t("tm.diff.events"), links: false },
        { k: I18n.t("tm.diff.k.settings"), v: I18n.t("tm.diff.settings"), links: false }
    ]
    // One deleted task back, from its id in the diff.
    function restoreTask(id) {
        if (!root.current) return;
        const m = root._missingTasks.filter(x => x.id === id)[0];
        if (!m) return;
        if (AppController.restoreSnapshotItem(root.current.name, "task", m.profileId, m.id))
            root.loadPreview();
    }
    // The snapshot's copy of a profile, as a new profile: the active one if it
    // was there, else the first.
    function openAsCopy(profileId) {
        if (!root.current) return;
        const ps = root.preview.profiles || [];
        let pid = profileId || "";
        if (!pid) {
            pid = ps.length > 0 ? ps[0].id : "";
            for (let i = 0; i < ps.length; i++) if (ps[i].id === AppController.activeProfileId) pid = ps[i].id;
        }
        if (pid.length === 0) return;
        AppController.restoreSnapshotProfile(root.current.name, pid);
        root.close();
    }

    // Arrowing through a month of snapshots must not inflate every one on the way.
    Timer {
        id: previewDebounce
        interval: 120
        onTriggered: root.loadPreview()
    }

    background: ModalSurface {}

    contentItem: RowLayout {
        spacing: 0

        // ── Left: the moments ──
        ColumnLayout {
            Layout.preferredWidth: 320
            Layout.maximumWidth: 320
            Layout.fillHeight: true
            Layout.margins: Theme.spLg
            spacing: Theme.spXs

            Text {
                objectName: "time-machine-head"
                Layout.leftMargin: Theme.spSm
                Layout.fillWidth: true
                text: root.listHead()
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
            Text {
                visible: root.snapshots.length === 0
                Layout.leftMargin: Theme.spSm
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
                Layout.preferredHeight: Math.min(contentHeight, 380)
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

                section.property: "grp"
                section.criteria: ViewSection.FullString
                section.delegate: Text {
                    required property string section
                    width: snapList.width
                    leftPadding: Theme.spSm
                    topPadding: Theme.spMd
                    bottomPadding: Theme.spXs
                    text: section === "today" ? I18n.t("tm.today") : section === "yesterday" ? I18n.t("tm.yesterday") : I18n.t("tm.earlier")
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                }

                delegate: Rectangle {
                    id: snapRow
                    required property var modelData
                    required property int index
                    readonly property bool on: snapList.currentIndex === snapRow.index
                    objectName: "time-machine-snap-" + index
                    width: snapList.width
                    implicitHeight: Theme.chipH + Theme.spXs
                    radius: Theme.radiusMd
                    color: snapRow.on ? Theme.panel3 : (snapMA.hovered ? Theme.panel2 : "transparent")
                    border.width: snapRow.on && snapList.activeFocus ? 1 : 0
                    border.color: Theme.focusRing
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spSm
                        anchors.rightMargin: Theme.spSm
                        spacing: Theme.spMd
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.rowText(snapRow.modelData)
                            color: snapRow.on ? Theme.text : Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsMd
                            font.weight: snapRow.on ? Theme.fwTitle : Theme.fwBody
                        }
                        Text {
                            text: I18n.count(snapRow.modelData.tasks, "tm.tasksN")
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsXs
                        }
                    }
                    ClickArea {
                        id: snapMA
                        label: root.rowText(snapRow.modelData)
                        showTip: false
                        activeFocusOnTab: false
                        onActivated: {
                            snapList.currentIndex = snapRow.index;
                            snapList.forceActiveFocus();
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
            // How long and how much history is kept, next to what it keeps.
            Text {
                id: keepText
                objectName: "time-machine-keep"
                Layout.leftMargin: Theme.spSm
                Layout.topMargin: Theme.spMd
                text: I18n.t("tm.keepLine").arg(I18n.t("tm.keep.days").arg(root.keepDays)).arg(I18n.t("tm.cap.mb").arg(root.capMb))
                color: keepMA.hovered ? Theme.text : Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                font.underline: keepMA.hovered
                ClickArea {
                    id: keepMA
                    label: keepText.text
                    onActivated: keepMenu.popup(keepText, 0, keepText.height)
                }
                AppMenu {
                    id: keepMenu
                    objectName: "time-machine-keep-menu"
                    Repeater {
                        model: [7, 30, 90]
                        delegate: AppMenuItem {
                            required property int modelData
                            objectName: "time-machine-days-" + modelData
                            text: I18n.t("tm.keep") + " " + I18n.t("tm.keep.days").arg(modelData)
                            marked: root.keepDays === modelData
                            onTriggered: root.setData("historyDays", modelData)
                        }
                    }
                    AppMenuSeparator {}
                    Repeater {
                        model: [100, 200, 500]
                        delegate: AppMenuItem {
                            required property int modelData
                            objectName: "time-machine-cap-" + modelData
                            text: I18n.t("tm.cap") + " " + I18n.t("tm.cap.mb").arg(modelData)
                            marked: root.capMb === modelData
                            onTriggered: root.setData("historyMaxMb", modelData)
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.border }

        // ── Right: what the chosen moment would change ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.margins: Theme.inset
            spacing: 0

            Text {
                visible: !root.current
                Layout.fillWidth: true
                text: I18n.t("tm.pick")
                color: Theme.textMuted
                font.pixelSize: Theme.fsSm
            }
            Text {
                visible: !!root.current && root.preview.ok === false
                Layout.fillWidth: true
                text: root.preview.error || ""
                color: Theme.warning
                font.pixelSize: Theme.fsSm
                wrapMode: Text.Wrap
            }

            Text {
                objectName: "time-machine-state-at"
                visible: !!root.current
                Layout.fillWidth: true
                text: root.current ? root.dayLabel(root.current.day) + ", " + root.current.time : ""
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsLg
                font.weight: Theme.fwHeading
            }
            Text {
                visible: !!root.current && root.preview.ok === true
                Layout.topMargin: Theme.spXs
                Layout.fillWidth: true
                text: root.current ? root.kindText(root.current.tag) + " · " + root.profileLine() : ""
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
            }
            Text {
                visible: !!root.current && root.preview.ok === true
                Layout.topMargin: Theme.spLg
                Layout.bottomMargin: Theme.spXs
                text: I18n.t("tm.diff.head")
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
            Repeater {
                model: !!root.current && root.preview.ok === true ? root.diffRows : []
                delegate: ColumnLayout {
                    id: diffRow
                    required property var modelData
                    required property int index
                    objectName: "time-machine-diff-" + index
                    Layout.fillWidth: true
                    spacing: 0
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumHeight: Theme.chipH + Theme.spXs
                        spacing: Theme.spMd
                        Text {
                            Layout.preferredWidth: Theme.px(90)
                            text: diffRow.modelData.k
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsMd
                        }
                        Text {
                            objectName: "time-machine-diff-value-" + diffRow.index
                            Layout.fillWidth: true
                            text: diffRow.modelData.v
                            textFormat: diffRow.modelData.links ? Text.StyledText : Text.PlainText
                            linkColor: Theme.text
                            color: Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsMd
                            wrapMode: Text.Wrap
                            onLinkActivated: (link) => root.restoreTask(link)
                            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        }
                    }
                }
            }

            RowLayout {
                visible: !!root.current && root.preview.ok === true
                Layout.topMargin: Theme.spLg
                Layout.fillWidth: true
                spacing: Theme.spMd
                PillButton {
                    id: copyBtn
                    objectName: "time-machine-copy"
                    text: I18n.t("tm.openCopy")
                    onClicked: (root.preview.profiles || []).length > 1 ? copyMenu.popup(copyBtn, 0, copyBtn.height) : root.openAsCopy("")
                    AppMenu {
                        id: copyMenu
                        Repeater {
                            model: root.preview.profiles || []
                            delegate: AppMenuItem {
                                required property var modelData
                                objectName: "time-machine-profile-copy-" + modelData.id
                                text: modelData.name
                                onTriggered: root.openAsCopy(modelData.id)
                            }
                        }
                    }
                }
                PillButton {
                    objectName: "time-machine-reveal"
                    text: I18n.t("tm.reveal")
                    onClicked: if (root.current) AppController.revealSnapshot(root.current.name)
                }
                Item { Layout.fillWidth: true }
                PillButton {
                    id: restoreAllBtn
                    objectName: "time-machine-restore-all"
                    property bool armed: false
                    primary: true
                    text: restoreAllBtn.armed ? I18n.t("tm.restoreAll.confirm") : I18n.t("tm.restoreAll")
                    onClicked: {
                        if (!root.current) return;
                        if (!restoreAllBtn.armed) {
                            restoreAllBtn.armed = true;
                            disarm.restart();
                            return;
                        }
                        restoreAllBtn.armed = false;
                        if (AppController.restoreSnapshot(root.current.name)) root.close();
                    }
                    Timer { id: disarm; interval: 3500; onTriggered: restoreAllBtn.armed = false }
                }
            }
            Text {
                visible: !!root.current && root.preview.ok === true
                Layout.topMargin: Theme.spLg
                Layout.fillWidth: true
                text: I18n.t("tm.restoreAll.hint")
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                wrapMode: Text.Wrap
            }
        }
    }
    onOpened: snapList.forceActiveFocus()
}
