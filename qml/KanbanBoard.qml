import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

Item {
    id: root
    property string searchText: ""
    property var prioritiesFilter: ({})
    property var scheduleMap: ({})
    property bool showArchived: false
    signal taskClicked(string id)
    signal createInStatus(string statusId)

    // Anchor for shift-click range selection. Reset when the selection
    // disappears so the next shift-click starts a fresh range.
    property string shiftAnchorId: ""
    Connections {
        target: AppController

        function onSelectedTaskIdsChanged() {
            if (AppController.selectionCount === 0) root.shiftAnchorId = "";
        }
    }

    // Walk every column's TaskCard repeater, collect ids of currently
    // visible cards (respects search/priority/archived filters), hand them
    // to AppController as the new selection set.
    function selectAllVisible() {
        AppController.setSelectedTaskIds(_flatVisibleIds());
    }

    // Flat ordered list of visible task ids across the entire board, column
    // by column in render order, top-to-bottom inside each column. Used by
    // selectAllVisible() and shift-range select.
    function _flatVisibleIds() {
        const out = [];
        for (let c = 0; c < colRepeater.count; c++) {
            const col = colRepeater.itemAt(c);
            if (!col || !col.taskRepeater) continue;
            const rep = col.taskRepeater;
            for (let i = 0; i < rep.count; i++) {
                const it = rep.itemAt(i);
                if (it && it.visible && it.taskId) out.push(it.taskId);
            }
        }
        return out;
    }

    // Shift-click range: spans the flat visible list (cross-column). First
    // shift-click sets the anchor; subsequent shift-click selects every
    // ticket between anchor and target inclusive.
    function _rangeSelect(targetId) {
        const ordered = _flatVisibleIds();
        if (ordered.length === 0) return;
        const haveAnchor = root.shiftAnchorId && ordered.indexOf(root.shiftAnchorId) >= 0;
        if (!haveAnchor) {
            root.shiftAnchorId = targetId;
            AppController.toggleTaskSelection(targetId);
            return;
        }
        const ai = ordered.indexOf(root.shiftAnchorId);
        const ti = ordered.indexOf(targetId);
        const lo = Math.min(ai, ti);
        const hi = Math.max(ai, ti);
        const merged = AppController.selectedTaskIds.slice();
        for (let i = lo; i <= hi; i++) {
            if (merged.indexOf(ordered[i]) < 0) merged.push(ordered[i]);
        }
        AppController.setSelectedTaskIds(merged);
    }

    function passesFilter(taskObj) {
        const q = (root.searchText || "").toLowerCase();
        if (q && q.length > 0) {
            const hay = ((taskObj.title || "") + " " + (taskObj.id || "") + " " + (taskObj.desc || "")).toLowerCase();
            if (hay.indexOf(q) < 0) return false;
        }
        let anyPri = false;
        for (const k in root.prioritiesFilter) if (root.prioritiesFilter[k]) { anyPri = true; break; }
        if (anyPri && !root.prioritiesFilter[taskObj.priority]) return false;
        return true;
    }

    function _scrollOuter(dy) {
        if (dy === 0) return;
        const maxX = Math.max(0, hscroll.contentWidth - hscroll.width);
        if (maxX <= 0) return;
        const base = outerAnim.running ? outerAnim.to : hscroll.contentX;
        const newX = Math.max(0, Math.min(maxX, base - dy));
        if (newX === base) return;
        outerAnim.from = hscroll.contentX;
        outerAnim.to = newX;
        outerAnim.restart();
    }

    NumberAnimation {
        id: outerAnim
        target: hscroll
        property: "contentX"
        duration: Theme.scaledMs(220)
        easing.type: Easing.OutCubic
    }

    Flickable {
        id: hscroll
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 12
        anchors.bottomMargin: 16
        contentWidth: rowL.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true
        // pressDelay: 0 — keep card-drag activation instant on press.
        // Horizontal flick by dragging empty board space is rarely used
        // on desktop (mouse wheel handles it via WheelHandler below).
        pressDelay: 0

        // Outer wheel: scroll the board horizontally with mouse-wheel.
        // Triggered when an inner WheelHandler sets event.accepted = false
        // (e.g. column at vertical-scroll edge or column header).
        // Handles wheel on column headers / gaps / "+ column" tile —
        // scrolls the board horizontally. Wheel inside a column body is
        // handled by the inner WheelHandler, which calls _scrollOuter()
        // when the column has no vertical overflow.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                root._scrollOuter(event.angleDelta.y || event.angleDelta.x);
            }
        }

        Row {
            id: rowL
            height: hscroll.height
            spacing: 12

            Repeater {
                id: colRepeater
                model: AppController.statuses

                Rectangle {
                    id: col
                    required property var modelData
                    required property int index
                    readonly property string statusId: modelData.id
                    readonly property string statusName: modelData.name
                    readonly property color statusColor: modelData.color
                    readonly property alias taskRepeater: colRep
                    property bool dragOver: false
                    property int visibleCount: 0
                    property bool renaming: false
                    readonly property bool isFirst: index === 0
                    readonly property bool isLast:  index === AppController.statuses.length - 1

                    width: 280
                    height: rowL.height
                    radius: Theme.radius
                    color: Theme.panel
                    border.color: dragOver ? Theme.accent : Theme.border
                    border.width: 1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            color: Theme.panel2
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 1; color: Theme.border
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 8
                                spacing: 8
                                Rectangle {
                                    width: 10; height: 10; radius: 3
                                    color: col.statusColor
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: colorPopup.openFor(col.statusId, col.statusColor, this)
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    Text {
                                        id: colName
                                        visible: !col.renaming
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: col.statusName.toUpperCase()
                                        color: Theme.textMuted
                                        font.family: Theme.fontUi
                                        font.pixelSize: 11
                                        font.letterSpacing: 1
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        visible: !col.renaming
                                        onDoubleClicked: { col.renaming = true; renameField.forceActiveFocus(); renameField.selectAll() }
                                        cursorShape: Qt.IBeamCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Double-click to rename"
                                        ToolTip.delay: 500
                                        hoverEnabled: true
                                    }
                                    TextField {
                                        id: renameField
                                        visible: col.renaming
                                        anchors.fill: parent
                                        text: col.statusName
                                        color: Theme.text
                                        background: Rectangle { radius: 4; color: Theme.panel; border.color: Theme.accent; border.width: 1 }
                                        font.family: Theme.fontUi
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        selectByMouse: true
                                        onAccepted: { AppController.renameStatus(col.statusId, text.trim()); col.renaming = false }
                                        onActiveFocusChanged: if (!activeFocus && col.renaming) { AppController.renameStatus(col.statusId, text.trim()); col.renaming = false }
                                        Keys.onEscapePressed: { col.renaming = false }
                                    }
                                }
                                Rectangle {
                                    radius: 999
                                    color: Theme.panel3
                                    implicitWidth: cntT.implicitWidth + 14
                                    implicitHeight: 18
                                    Text {
                                        id: cntT; anchors.centerIn: parent
                                        text: col.visibleCount
                                        color: Theme.textDim
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }
                                }

                                // Move-left / Move-right / Delete
                                HoverIcon {
                                    glyph: "‹"; tip: "Move left"
                                    visible: headHover.containsMouse && !col.isFirst
                                    onActivated: AppController.moveStatus(col.statusId, col.index - 1)
                                }
                                HoverIcon {
                                    glyph: "›"; tip: "Move right"
                                    visible: headHover.containsMouse && !col.isLast
                                    onActivated: AppController.moveStatus(col.statusId, col.index + 1)
                                }
                                HoverIcon {
                                    glyph: "×"; tip: I18n.t("kanban.deleteColumn")
                                    danger: true
                                    visible: headHover.containsMouse && AppController.statuses.length > 1
                                    onActivated: AppController.deleteStatus(col.statusId)
                                }

                                Rectangle {
                                    width: 22; height: 22; radius: 5
                                    color: addMA.containsMouse ? Theme.panel3 : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "+"
                                        color: addMA.containsMouse ? Theme.text : Theme.textDim
                                        font.pixelSize: 14
                                    }
                                    MouseArea {
                                        id: addMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.createInStatus(col.statusId)
                                    }
                                }
                            }
                            MouseArea {
                                id: headHover
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.RightButton
                                onClicked: (mouse) => { if (mouse.button === Qt.RightButton) colHeaderMenu.popup() }
                                z: -1
                            }

                            QQC.Menu {
                                id: colHeaderMenu
                                QQC.MenuItem { text: "Add task"; onTriggered: root.createInStatus(col.statusId) }
                                QQC.MenuItem { text: "Rename"; onTriggered: { col.renaming = true; renameField.forceActiveFocus(); renameField.selectAll() } }
                                QQC.MenuItem { text: "Change color…"; onTriggered: colorPopup.openFor(col.statusId, col.statusColor, col) }
                                QQC.MenuSeparator {}
                                QQC.MenuItem { text: "Move left";  enabled: !col.isFirst; onTriggered: AppController.moveStatus(col.statusId, col.index - 1) }
                                QQC.MenuItem { text: "Move right"; enabled: !col.isLast;  onTriggered: AppController.moveStatus(col.statusId, col.index + 1) }
                                QQC.MenuSeparator {}
                                QQC.MenuItem { text: "Delete column"; enabled: AppController.statuses.length > 1; onTriggered: AppController.deleteStatus(col.statusId) }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Flickable {
                                id: bodyFlick
                                anchors.fill: parent
                                anchors.margins: 8
                                contentHeight: bodyCol.implicitHeight
                                clip: true
                                flickableDirection: Flickable.VerticalFlick
                                // pressDelay: 0 — same rationale as the
                                // outer hscroll: instant drag on cards.
                                pressDelay: 0

                                // Wheel scrolls this column vertically. When the column
                                // has no overflow or is already at the top/bottom edge,
                                // event.accepted = false lets the outer board scroll
                                // horizontally instead.
                                NumberAnimation {
                                    id: bodyAnim
                                    target: bodyFlick
                                    property: "contentY"
                                    duration: Theme.scaledMs(220)
                                    easing.type: Easing.OutCubic
                                }

                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: (event) => {
                                        const dy = event.angleDelta.y;
                                        if (dy === 0) return;
                                        const maxY = Math.max(0, bodyFlick.contentHeight - bodyFlick.height);
                                        if (maxY > 0) {
                                            const base = bodyAnim.running ? bodyAnim.to : bodyFlick.contentY;
                                            const newY = Math.max(0, Math.min(maxY, base - dy));
                                            if (newY !== base) {
                                                bodyAnim.from = bodyFlick.contentY;
                                                bodyAnim.to = newY;
                                                bodyAnim.restart();
                                                return;
                                            }
                                        }
                                        // No overflow or already at edge → pass through.
                                        root._scrollOuter(dy);
                                    }
                                }

                                Column {
                                    id: bodyCol
                                    width: bodyFlick.width
                                    spacing: 8

                                    Repeater {
                                        id: colRep
                                        model: AppController.tasks

                                        TaskCard {
                                            id: tc
                                            required property string id
                                            required property string title
                                            required property string desc
                                            required property string priority
                                            required property string status
                                            required property var deadline
                                            required property string branch
                                            required property bool archived
                                            required property bool blockedStuck
                                            required property string prState
                                            required property int    prNumber
                                            required property string prUrl
                                            required property int    gitAhead
                                            required property int    gitBehind
                                            width: bodyCol.width

                                            readonly property var taskData: ({
                                                id: tc.id, title: tc.title, desc: tc.desc,
                                                priority: tc.priority, status: tc.status,
                                                deadline: tc.deadline, branch: tc.branch,
                                                archived: tc.archived, blockedStuck: tc.blockedStuck,
                                                prState: tc.prState, prNumber: tc.prNumber, prUrl: tc.prUrl,
                                                gitAhead: tc.gitAhead, gitBehind: tc.gitBehind
                                            })
                                            task: taskData
                                            scheduled: root.scheduleMap[tc.id] || ""
                                            visible: tc.status === col.statusId
                                                  && (root.showArchived || !tc.archived)
                                                  && root.passesFilter(taskData)
                                            onClicked: root.taskClicked(tc.id)
                                            onRangeSelectRequested: (anchorId) => root._rangeSelect(anchorId)

                                            onVisibleChanged: col.recountSoon()
                                            Component.onCompleted: col.recountSoon()
                                            Component.onDestruction: col.recountSoon()
                                        }
                                    }

                                    Text {
                                        visible: col.visibleCount === 0
                                        width: bodyCol.width
                                        topPadding: 12
                                        text: I18n.t("kanban.empty")
                                        color: Theme.textDim
                                        font.italic: true
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: col.dragOver = true
                                onExited: col.dragOver = false
                                onDropped: (drop) => {
                                    col.dragOver = false;
                                    const src = drop.source;
                                    if (!src || !src.taskId) return;
                                    if (AppController.isTaskSelected(src.taskId)
                                        && AppController.selectionCount > 1) {
                                        AppController.moveSelectedTasksToStatus(col.statusId);
                                    } else {
                                        AppController.moveTask(src.taskId, col.statusId);
                                    }
                                    drop.accept(Qt.MoveAction);
                                }
                            }

                            // Right-click on empty body → Add task
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onClicked: (mouse) => { if (mouse.button === Qt.RightButton) bodyMenu.popup() }
                                z: -2
                            }
                            QQC.Menu {
                                id: bodyMenu
                                QQC.MenuItem { text: "Add task"; onTriggered: root.createInStatus(col.statusId) }
                            }
                        }
                    }

                    function recountSoon() { recountTimer.restart() }
                    Timer {
                        id: recountTimer
                        interval: 0
                        repeat: false
                        onTriggered: {
                            let n = 0;
                            for (let i = 0; i < colRep.count; i++) {
                                const it = colRep.itemAt(i);
                                if (it && it.visible) n++;
                            }
                            col.visibleCount = n;
                        }
                    }

                    Connections {
                        target: root
                        function onSearchTextChanged() { col.recountSoon() }
                        function onPrioritiesFilterChanged() { col.recountSoon() }
                    }
                }
            }

            // "+ Add column" tile at the end of the row
            Rectangle {
                width: 200
                height: rowL.height
                radius: Theme.radius
                color: addColMA.containsMouse ? Theme.panel2 : "transparent"
                border.color: Theme.border
                border.width: 1

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "+"
                        color: addColMA.containsMouse ? Theme.text : Theme.textDim
                        font.pixelSize: 20
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.t("kanban.newColumn")
                        color: addColMA.containsMouse ? Theme.text : Theme.textDim
                        font.pixelSize: 12
                    }
                }
                MouseArea {
                    id: addColMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: addColumnPopup.open()
                }
            }
        }
    }

    // ── Popups ──────────────────────────────────────────────────────────────

    Popup {
        id: addColumnPopup
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        padding: 0
        width: 360
        anchors.centerIn: Overlay.overlay
        background: Rectangle { radius: 12; color: Theme.panel; border.color: Theme.borderStrong; border.width: 1 }

        // Dimmed backdrop so the board stays visible behind the dialog.
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

        readonly property var palette: [
            "#5cc2dd", "#8a8e98", "#9aa3b4", "#5aa9e6", "#dcb86b",
            "#e6624c", "#c07acf", "#6ec18a", "#6cc4b8", "#7da8d9"
        ]
        property color picked: palette[0]

        function reset() { nameField.text = ""; picked = palette[0] }
        onOpened: { reset(); nameField.forceActiveFocus() }

        contentItem: ColumnLayout {
            spacing: 10
            Item { Layout.preferredHeight: 4 }
            Text {
                Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("kanban.newColumn"); color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("kanban.colName").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            TextField {
                id: nameField
                Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
                placeholderText: "Review · QA · Stalled…"
                color: Theme.text
                placeholderTextColor: Theme.textDim
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                onAccepted: saveBtn.activate()
            }
            Text {
                Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("common.color").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            Row {
                Layout.leftMargin: 18; Layout.rightMargin: 18
                spacing: 6
                Repeater {
                    model: addColumnPopup.palette
                    delegate: Rectangle {
                        required property string modelData
                        width: 24; height: 24; radius: 12
                        color: modelData
                        border.color: String(addColumnPopup.picked).toLowerCase() === modelData.toLowerCase() ? Theme.text : Theme.border
                        border.width: 2
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                   onClicked: addColumnPopup.picked = modelData }
                    }
                }
            }
            RowLayout {
                Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 16; Layout.topMargin: 8
                Item { Layout.fillWidth: true }
                PillButton {
                    text: I18n.t("common.cancel"); onClicked: addColumnPopup.close()
                }
                PillButton {
                    id: saveBtn
                    text: I18n.t("kanban.create"); primary: true
                    function activate() {
                        const n = nameField.text.trim();
                        if (n.length === 0) return;
                        AppController.addStatus(n, String(addColumnPopup.picked));
                        addColumnPopup.close();
                    }
                    onClicked: activate()
                }
            }
        }
    }

    Popup {
        id: colorPopup
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        padding: 8
        background: Rectangle { radius: 10; color: Theme.panel; border.color: Theme.borderStrong; border.width: 1 }
        property string forStatusId: ""

        readonly property var palette: addColumnPopup.palette

        function openFor(id, currentColor, anchorItem) {
            forStatusId = id;
            if (anchorItem) {
                const p = anchorItem.mapToItem(root, anchorItem.width / 2, anchorItem.height);
                x = Math.max(8, p.x - 90);
                y = p.y + 6;
            }
            open();
        }

        contentItem: Grid {
            columns: 5
            spacing: 6
            Repeater {
                model: colorPopup.palette
                delegate: Rectangle {
                    required property string modelData
                    width: 22; height: 22; radius: 11
                    color: modelData
                    border.color: Theme.border
                    border.width: 1
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            AppController.setStatusColor(colorPopup.forStatusId, modelData);
                            colorPopup.close();
                        }
                    }
                }
            }
        }
    }

    // ── Inline components ───────────────────────────────────────────────────

    component HoverIcon: Rectangle {
        property string glyph: ""
        property string tip: ""
        property bool danger: false
        signal activated()
        Layout.preferredWidth: 20
        Layout.preferredHeight: 20
        radius: 4
        color: hoverIconMA.containsMouse ? (danger ? Theme.withAlpha(Theme.p0, 0.16) : Theme.panel3)
                                         : "transparent"
        border.color: hoverIconMA.containsMouse ? (danger ? Theme.p0 : Theme.border) : "transparent"
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: hoverIconMA.containsMouse ? (parent.danger ? Theme.p0 : Theme.text) : Theme.textMuted
            font.pixelSize: parent.glyph === "×" ? 13 : 12
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: hoverIconMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
            ToolTip.visible: containsMouse && parent.tip.length > 0
            ToolTip.text: parent.tip
            ToolTip.delay: 400
        }
    }

    // ── Board-level empty state ──
    // Shown when the profile has no tasks at all (e.g. right after "Start
    // fresh"). Non-interactive so the column "+" affordances stay reachable.
    property int _boardTotal: AppController.tasks.rowCount()
    Connections {
        target: AppController.tasks
        function onModelReset()   { root._boardTotal = AppController.tasks.rowCount() }
        function onRowsInserted() { root._boardTotal = AppController.tasks.rowCount() }
        function onRowsRemoved()  { root._boardTotal = AppController.tasks.rowCount() }
    }
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 360)
        spacing: 8
        visible: root._boardTotal === 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.t("board.empty.title")
            color: Theme.text
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: I18n.t("board.empty.hint")
            color: Theme.textMuted
            font.pixelSize: 12
        }
    }
}
