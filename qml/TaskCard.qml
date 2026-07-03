import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

Rectangle {
    id: card
    property var task           // QVariantMap-like with id,title,desc,priority,status,deadline,branch,archived,blockedStuck
    property string scheduled
    property string taskId: task ? task.id : ""
    readonly property bool _isStuck: card.task && card.task.blockedStuck === true
    readonly property bool _isArchived: card.task && card.task.archived === true
    // Selection state — re-evaluates via AppController.selectedTaskIdsChanged
    // (selectionCount is read in the binding so QML tracks the dependency).
    readonly property bool _selected: AppController.selectionCount >= 0
        && AppController.isTaskSelected(card.taskId)
    signal clicked()

    signal rangeSelectRequested(string anchorId)

    radius: 8
    color: _isArchived ? Theme.withAlpha(Theme.panel2, 0.55)
        : _selected ? Theme.withAlpha(Theme.accent, 0.10)
            : Theme.panel2
    border.color: dragArea.drag.active ? Theme.accent
        : _selected ? Theme.accent
                : _isStuck ? Theme.p0
                : hoverArea.containsMouse ? Theme.borderStrong
                : Theme.border
    border.width: dragArea.drag.active ? 2 : (_selected ? 2 : (_isStuck ? 2 : 1))
    opacity: dragArea.drag.active ? 0.92 : (_isArchived ? 0.7 : 1.0)
    scale: dragArea.drag.active ? 1.03 : 1.0
    transformOrigin: Item.Center
    z: dragArea.drag.active ? 1000 : 0
    Behavior on scale { NumberAnimation { duration: Theme.scaledMs(120); easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: Theme.scaledMs(120) } }

    implicitWidth: parent ? parent.width : 260
    implicitHeight: contentCol.implicitHeight + 20

    // Drag.active is automatically driven by MouseArea.drag.active
    Drag.active: dragArea.drag.active
    Drag.dragType: Drag.Internal
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: 20

    property real homeX: 0
    property real homeY: 0

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        RowLayout {
            spacing: 6
            Text {
                text: card.task ? card.task.id : ""
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.weight: Font.Medium
            }
            Rectangle {
                radius: 4
                color: Theme.withAlpha(Theme.priorityColor(card.task ? card.task.priority : "P3"), 0.12)
                implicitWidth: priT.implicitWidth + 10
                implicitHeight: priT.implicitHeight + 2
                Text {
                    id: priT
                    anchors.centerIn: parent
                    text: card.task ? card.task.priority : ""
                    color: Theme.priorityColor(card.task ? card.task.priority : "P3")
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                visible: card._isStuck
                radius: 4
                color: Theme.withAlpha(Theme.p0, 0.14)
                border.color: Theme.p0
                border.width: 1
                implicitWidth: stuckT.implicitWidth + 10
                implicitHeight: stuckT.implicitHeight + 2
                Text {
                    id: stuckT
                    anchors.centerIn: parent
                    text: "stuck"
                    color: Theme.p0
                    font.family: Theme.fontUi
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                }
            }
            Rectangle {
                visible: card._isArchived
                radius: 4
                color: Theme.withAlpha(Theme.textDim, 0.18)
                implicitWidth: archT.implicitWidth + 10
                implicitHeight: archT.implicitHeight + 2
                Text {
                    id: archT
                    anchors.centerIn: parent
                    text: "arch"
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                }
            }
            Text {
                visible: card.task && card.task.branch && String(card.task.branch).length > 0
                text: card.task && card.task.branch
                      ? "⎇ " + String(card.task.branch).split("/").pop().substring(0, 18)
                      : ""
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 10
                elide: Text.ElideRight
            }
            // ── Git live-status chips — fed by GitWatcher via TaskModel ──
            Rectangle {
                visible: card.task && (card.task.gitAhead || 0) > 0
                radius: 4
                color: Theme.withAlpha(Theme.accent, 0.14)
                border.color: Theme.accent
                border.width: 1
                implicitWidth: aheadT.implicitWidth + 10
                implicitHeight: aheadT.implicitHeight + 2
                Text {
                    id: aheadT
                    anchors.centerIn: parent
                    text: "↑" + (card.task ? (card.task.gitAhead || 0) : 0)
                    color: Theme.accentStrong
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }
            }
            Rectangle {
                visible: card.task && String(card.task.prState || "").length > 0
                radius: 4
                color: {
                    const s = card.task ? String(card.task.prState || "") : "";
                    if (s === "merged") return Theme.withAlpha(Theme.mFocus, 0.18);
                    if (s === "closed") return Theme.withAlpha(Theme.textDim, 0.18);
                    return Theme.withAlpha(Theme.p1, 0.18);
                }
                border.color: {
                    const s = card.task ? String(card.task.prState || "") : "";
                    if (s === "merged") return Theme.mFocus;
                    if (s === "closed") return Theme.textDim;
                    return Theme.p1;
                }
                border.width: 1
                implicitWidth: prT.implicitWidth + 10
                implicitHeight: prT.implicitHeight + 2
                Text {
                    id: prT
                    anchors.centerIn: parent
                    text: {
                        if (!card.task) return "";
                        const n = card.task.prNumber || 0;
                        const s = String(card.task.prState || "");
                        return (n > 0 ? "PR #" + n + " " : "PR ") + s;
                    }
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }
            }
            // Recent commits mentioning this task id — fed by GitWatcher git-log
            // parsing. Tooltip shows the most recent subject.
            Rectangle {
                id: commitChip
                visible: card.task && card.task.recentCommits && card.task.recentCommits.length > 0
                radius: 4
                color: Theme.withAlpha(Theme.textDim, 0.14)
                border.color: Theme.border
                border.width: 1
                implicitWidth: commitT.implicitWidth + 10
                implicitHeight: commitT.implicitHeight + 2
                Text {
                    id: commitT
                    anchors.centerIn: parent
                    text: "◇ " + (card.task && card.task.recentCommits ? card.task.recentCommits.length : 0)
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }
                QQC.ToolTip.visible: commitMA.containsMouse && commitChip.visible
                QQC.ToolTip.text: (card.task && card.task.recentCommits && card.task.recentCommits.length > 0)
                    ? (card.task.recentCommits[0].sha + "  " + card.task.recentCommits[0].subject)
                    : ""
                MouseArea {
                    id: commitMA
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: card.task ? card.task.title : ""
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            visible: card.task && card.task.desc && String(card.task.desc).length > 0
            text: card.task ? card.task.desc : ""
            color: Theme.textMuted
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        RowLayout {
            spacing: 8
            Text {
                property string dlText: {
                    if (!card.task || !card.task.deadline) return "";
                    const dl = card.task.deadline;
                    if (!dl.getTime) return "";
                    const t = AppController.today;
                    const ms = dl.getTime() - new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
                    const days = Math.round(ms / 86400000);
                    if (days < 0) return "⏱ " + (-days) + "d overdue";
                    if (days === 0) return "⏱ today";
                    if (days === 1) return "⏱ tomorrow";
                    return "⏱ " + days + "d";
                }
                visible: dlText.length > 0
                text: dlText
                color: {
                    if (!card.task || !card.task.deadline || !card.task.deadline.getTime) return Theme.textDim;
                    const dl = card.task.deadline;
                    const t = AppController.today;
                    const days = Math.round((dl.getTime() - new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime()) / 86400000);
                    if (days <= 0) return Theme.p0;
                    if (days <= 3) return Theme.p1;
                    return Theme.textDim;
                }
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                visible: card.scheduled && card.scheduled.length > 0
                radius: 4
                color: Theme.accentSoft
                implicitWidth: schedT.implicitWidth + 10
                implicitHeight: schedT.implicitHeight + 2
                Text {
                    id: schedT
                    anchors.centerIn: parent
                    text: "⏰ " + (card.scheduled || "")
                    color: Theme.accentStrong
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
            }
        }
    }

    // "+N" badge shown while dragging a selected card with siblings.
    Rectangle {
        visible: dragArea.drag.active && card._selected && AppController.selectionCount > 1
        anchors.top: parent.top; anchors.right: parent.right
        anchors.margins: -6
        z: 5
        width: bulkT.implicitWidth + 10
        height: 18
        radius: 9
        color: Theme.accent
        border.color: Theme.accentStrong
        border.width: 1
        Text {
            id: bulkT
            anchors.centerIn: parent
            text: "+" + (AppController.selectionCount - 1)
            color: "#06121a"
            font.family: Theme.fontMono
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        drag.target: card
        drag.threshold: 5
        cursorShape: dragArea.drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property bool didDrag: false
        onPressed: (mouse) => {
            card.homeX = card.x; card.homeY = card.y; didDrag = false;
            if (mouse.button === Qt.RightButton) taskMenu.popup();
        }
        onPositionChanged: if (drag.active) didDrag = true
        onReleased: (mouse) => {
            const wasDrag = didDrag;
            card.Drag.drop();
            card.x = card.homeX; card.y = card.homeY;
            didDrag = false;
            if (wasDrag || mouse.button !== Qt.LeftButton) return;

            const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
            const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
            if (ctrl) {
                AppController.toggleTaskSelection(card.taskId);
            } else if (shift) {
                card.rangeSelectRequested(card.taskId);
            } else {
                if (AppController.selectionCount > 0) AppController.clearSelection();
                card.clicked();
            }
        }
    }

    QQC.Menu {
        id: taskMenu
        QQC.MenuItem {
            enabled: false
            contentItem: Text {
                text: card.task ? (card.task.id + " · " + card.task.priority) : ""
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                leftPadding: 12
                rightPadding: 12
            }
        }
        QQC.MenuItem {
            text: "✎  " + I18n.t("taskcard.edit"); onTriggered: card.clicked()
        }
        QQC.MenuSeparator {}
        QQC.MenuItem {
            text: "⏰  " + I18n.t("taskcard.schedule")
            onTriggered: {
                if (!card.task) return;
                AppController.scheduleTask(card.task.id, 14, AppController.selectedDate);
            }
        }
        QQC.MenuItem {
            text: "⎘  " + I18n.t("taskcard.copyId")
            onTriggered: {
                if (card.task && card.task.id) AppController.copyToClipboard(card.task.id);
            }
        }
        QQC.MenuItem {
            text: "⎇  " + I18n.t("taskcard.copyBranch")
            enabled: card.task && card.task.branch && String(card.task.branch).length > 0
            onTriggered: {
                if (card.task && card.task.branch) AppController.copyToClipboard(card.task.branch);
            }
        }
        QQC.MenuItem {
            text: "⎇+  " + I18n.t("taskcard.createBranch")
            onTriggered: {
                if (card.task && card.task.id) AppController.createBranchForTask(card.task.id);
            }
        }
        QQC.MenuSeparator {}
        QQC.MenuItem {
            text: "×  " + I18n.t("common.delete"); onTriggered: AppController.deleteTask(card.taskId)
        }
    }
}
