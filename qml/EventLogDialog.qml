pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The event log (APP-187, X-Dlg-Log-Import "Журнал"): what the toasts said
// this session, newest first, so a missed one can be read again. Tabs filter
// it — all / errors / sync / reminders. A row is time · source · text, and
// the action it allows on the right: "open" for an entry about tasks or a
// place, "undo" on the newest undoable step. ↑/↓ walk the list, Return runs
// the row's action, ←/→ switch tabs, Esc closes. AppController.eventLog
// keeps the last 100, this session only.
Popup {
    id: root
    objectName: "event-log"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: 0
    width: 640
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    readonly property var tabs: ["all", "errors", "sync", "reminders"]
    property string tab: "all"
    readonly property var allEntries: AppController.eventLog
    readonly property var entries: root.allEntries.filter(e => root.inTab(e, root.tab))
    readonly property int count: root.entries.length

    // An entry was picked; Main takes the person to what it is about.
    signal entryActivated(var entry)

    function showNow() {
        root.tab = "all";
        root.open();
    }
    function inTab(e, tab) {
        if (!e) return false;
        if (tab === "errors") return e.kind === "error" || e.kind === "warning";
        if (tab === "sync") return e.kind === "sync" || String(e.route || "").indexOf("settings:integrations") === 0;
        if (tab === "reminders") return e.kind === "reminder";
        return true;
    }
    // Where an entry came from, in a word.
    function sourceOf(e) {
        if (!e) return "";
        if (e.kind === "reminder") return I18n.t("eventLog.src.reminder");
        if (e.kind === "sync" || String(e.route || "").indexOf("settings:integrations") === 0) return I18n.t("eventLog.src.sync");
        if (e.kind === "undo" || (e.taskIds || []).length > 0) return I18n.t("eventLog.src.tasks");
        if (String(e.route || "").indexOf("settings:data") === 0) return I18n.t("eventLog.src.data");
        return "lowkey";
    }

    // Whether an entry leads anywhere.
    function hasTarget(entry) {
        return !!entry && ((entry.taskIds || []).length > 0 || String(entry.route || "").length > 0);
    }
    // The newest undoable step is the one Ctrl Z takes back.
    readonly property int _newestUndo: {
        const all = root.allEntries;
        for (let i = 0; i < all.length; i++) if (all[i].kind === "undo") return all[i].id;
        return -1;
    }
    // "open" | "undo" | ""
    function actionOf(entry) {
        if (!entry) return "";
        if (entry.kind === "undo" && entry.id === root._newestUndo && AppController.hasPendingUndo) return "undo";
        return root.hasTarget(entry) ? "open" : "";
    }
    function activate(index) {
        const e = root.entries[index];
        const a = root.actionOf(e);
        if (a === "undo") {
            AppController.undo();
            return;
        }
        if (a !== "open") return;
        root.close();
        root.entryActivated(e);
    }
    function stepTab(d) {
        const i = root.tabs.indexOf(root.tab);
        root.tab = root.tabs[(i + d + root.tabs.length) % root.tabs.length];
        list.currentIndex = 0;
    }

    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: 0

        // Журнал                     всё  ошибки  синк  напоминания
        RowLayout {
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.bottomMargin: Theme.spMd
            Layout.fillWidth: true
            spacing: Theme.spLg
            Text {
                Layout.fillWidth: true
                text: I18n.t("eventLog.title")
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsLg
                font.weight: Theme.fwHeading
            }
            Repeater {
                model: root.tabs
                delegate: Text {
                    id: tabText
                    required property string modelData
                    readonly property bool on: root.tab === tabText.modelData
                    objectName: "event-log-tab-" + modelData
                    text: I18n.t("eventLog.tab." + tabText.modelData)
                    color: tabText.on ? Theme.text : Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    bottomPadding: Theme.sp2xs
                    Rectangle {
                        visible: tabText.on
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: 2
                        color: Theme.accent
                    }
                    ClickArea {
                        label: tabText.text
                        role: Accessible.PageTab
                        onActivated: { root.tab = tabText.modelData; list.currentIndex = 0; }
                    }
                }
            }
        }

        Text {
            objectName: "event-log-empty"
            visible: root.count === 0
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.bottomMargin: Theme.inset
            Layout.fillWidth: true
            text: root.allEntries.length === 0 ? I18n.t("eventLog.empty") : I18n.t("eventLog.emptyTab")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            objectName: "event-log-list"
            visible: root.count > 0
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.bottomMargin: Theme.inset
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 420)
            clip: true
            focus: true
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            highlightMoveDuration: 0
            model: root.entries
            ScrollBar.vertical: ThinScrollBar {}
            Keys.onReturnPressed: root.activate(list.currentIndex)
            Keys.onEnterPressed: root.activate(list.currentIndex)
            Keys.onLeftPressed: root.stepTab(-1)
            Keys.onRightPressed: root.stepTab(1)

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: ListView.isCurrentItem && list.activeFocus
                readonly property string action: root.actionOf(row.modelData)
                objectName: "event-log-row-" + index
                width: ListView.view.width
                implicitHeight: Math.max(Theme.chipH + Theme.spSm, line.implicitHeight + Theme.spSm * 2)

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    color: row.current ? Theme.rowHighlight : "transparent"
                }
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    height: 1
                    color: Theme.border
                }
                RowLayout {
                    id: line
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spMd
                    Text {
                        Layout.preferredWidth: Theme.px(44)
                        text: I18n.fmtTime(row.modelData.at)
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsXs
                    }
                    // The source; a failed line carries a warning mark
                    // after it (N-Dlg-Log-Import, R4-065).
                    RowLayout {
                        Layout.preferredWidth: Theme.px(80)
                        Layout.maximumWidth: Theme.px(80)
                        spacing: Theme.spXs
                        Text {
                            Layout.fillWidth: !srcMark.visible
                            Layout.maximumWidth: Theme.px(80) - (srcMark.visible ? srcMark.width + Theme.spXs : 0)
                            text: root.sourceOf(row.modelData)
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsSm
                            elide: Text.ElideRight
                        }
                        Icon {
                            id: srcMark
                            objectName: "event-log-error-mark"
                            visible: row.modelData.kind === "error"
                            name: "warning"
                            size: Theme.px(11)
                            color: Theme.dangerInk
                        }
                        Item { Layout.fillWidth: srcMark.visible }
                    }
                    Text {
                        objectName: "event-log-message"
                        Layout.fillWidth: true
                        text: row.modelData.message + (row.modelData.count > 1 ? "  ×" + row.modelData.count : "")
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Text {
                        id: actionText
                        objectName: "event-log-action-" + row.index
                        visible: row.action.length > 0
                        text: row.action.length > 0 ? I18n.t("eventLog.action." + row.action) : ""
                        color: actionMA.hovered ? Theme.text : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                        font.underline: actionMA.hovered
                        ClickArea {
                            id: actionMA
                            objectName: "event-log-row-area-" + row.index
                            activeFocusOnTab: false
                            label: actionText.text + ": " + row.modelData.message
                            showTip: false
                            onActivated: root.activate(row.index)
                        }
                    }
                }
            }
        }
    }

    onOpened: {
        list.currentIndex = 0;
        list.forceActiveFocus();
    }
}
