pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The event log (APP-187): what the toasts said this session — syncs and the
// tickets they brought, refusals, errors, failed saves, actions that can be
// undone — newest first, so a missed one can be read again. An entry that is
// about tasks or a place opens it. ↑/↓ walk the list, Return opens, Esc
// closes. Read-only: AppController.eventLog keeps the last 100, this session
// only.
Dialog {
    id: root
    objectName: "event-log"
    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: Theme.inset
    width: 560
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    readonly property var entries: AppController.eventLog
    readonly property int count: root.entries.length

    // An entry was picked; Main takes the user to what it is about.
    signal entryActivated(var entry)

    function showNow() {
        root.open();
    }

    // Whether an entry leads anywhere.
    function hasTarget(entry) {
        return !!entry && ((entry.taskIds || []).length > 0 || String(entry.route || "").length > 0);
    }

    function activate(index) {
        const e = root.entries[index];
        if (!root.hasTarget(e)) return;
        root.close();
        root.entryActivated(e);
    }

    function _time(at) {
        if (!at || !at.getTime) return "";
        const p2 = (n) => (n < 10 ? "0" : "") + n;
        return p2(at.getHours()) + ":" + p2(at.getMinutes());
    }

    function _kindColor(kind) {
        if (kind === "error" || kind === "warning") return Theme.alertColor(kind);
        if (kind === "sync") return Theme.live;
        return Theme.textDim;
    }

    header: DialogHeader { text: I18n.t("eventLog.title") }
    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: Theme.spLg

        Text {
            Layout.fillWidth: true
            text: root.count > 0 ? I18n.t("eventLog.note") : I18n.t("eventLog.empty")
            color: Theme.textMuted
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            objectName: "event-log-list"
            visible: root.count > 0
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

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: ListView.isCurrentItem && list.activeFocus
                readonly property bool linked: root.hasTarget(row.modelData)
                objectName: "event-log-row-" + index
                width: ListView.view.width
                implicitHeight: line.implicitHeight + Theme.spSm * 2
                radius: Theme.radiusMd
                color: rowMA.hovered && row.linked ? Theme.panel3 : row.current ? Theme.rowHighlight : "transparent"
                border.width: row.current ? 1 : 0
                border.color: Theme.focusRing

                RowLayout {
                    id: line
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spMd
                    anchors.rightMargin: Theme.spMd
                    spacing: Theme.spMd
                    Text {
                        Layout.alignment: Qt.AlignTop
                        text: root._time(row.modelData.at)
                        color: Theme.textDim
                        font.pixelSize: Theme.fsXs
                        font.features: Theme.tabularNums
                        topPadding: 1
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: Theme.spXs
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: root._kindColor(row.modelData.kind)
                    }
                    Text {
                        objectName: "event-log-message"
                        Layout.fillWidth: true
                        text: row.modelData.message
                        textFormat: Text.PlainText
                        color: row.linked ? Theme.text : Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: row.modelData.count > 1
                        Layout.alignment: Qt.AlignTop
                        text: "×" + row.modelData.count
                        color: Theme.textDim
                        font.pixelSize: Theme.fsXs
                        font.features: Theme.tabularNums
                    }
                }
                ClickArea {
                    id: rowMA
                    objectName: "event-log-row-area-" + row.index
                    enabled: row.linked
                    activeFocusOnTab: false
                    label: row.modelData.message
                    showTip: false
                    onActivated: root.activate(row.index)
                }
            }
        }
    }

    footer: DialogFooter {
        PillButton {
            id: closeBtn
            objectName: "event-log-close"
            text: I18n.t("common.close")
            onClicked: root.close()
        }
    }
    onOpened: {
        list.currentIndex = 0;
        if (root.count > 0) list.forceActiveFocus();
        else closeBtn.forceActiveFocus();
    }
}
