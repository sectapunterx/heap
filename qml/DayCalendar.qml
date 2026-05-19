import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Item {
    id: root
    readonly property int hoursStart: AppController.workdayStart
    readonly property int hoursEnd:   AppController.workdayEnd
    readonly property real pxPerMin: Theme.hourH / 60.0

    signal eventClicked(string id)

    function snapHour(h)  { return Math.round(h * 4) / 4; }
    function yToHour(y)   { return root.hoursStart + y / Theme.hourH; }
    function clampHour(h) { return Math.max(root.hoursStart, Math.min(root.hoursEnd, h)); }

    property date now: new Date()
    Timer { interval: 60000; repeat: true; running: true; onTriggered: root.now = new Date() }

    // Reactive event count for the selected day; refreshed on every
    // events-model mutation so the "N events" header stays in sync.
    property int _eventsToday: 0
    function _recountEventsToday() {
        const d = AppController.selectedDate;
        if (!d || !d.getFullYear) { _eventsToday = 0; return; }
        let n = 0;
        for (let i = 0; i < AppController.events.rowCount(); i++) {
            const ed = AppController.events.data(AppController.events.index(i,0), Qt.UserRole + 7);
            if (root.isSameDay(ed, d)) n++;
        }
        _eventsToday = n;
    }
    Connections {
        target: AppController.events
        function onRowsInserted() { root._recountEventsToday() }
        function onRowsRemoved()  { root._recountEventsToday() }
        function onDataChanged()  { root._recountEventsToday() }
        function onModelReset()   { root._recountEventsToday() }
    }
    Connections {
        target: AppController
        function onSelectedDateChanged() { root._recountEventsToday() }
    }
    Component.onCompleted: _recountEventsToday()

    function isSameDay(a, b) {
        if (!a || !b || !a.getFullYear || !b.getFullYear) return false;
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                color: Theme.panel
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 1; color: Theme.border
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    Column {
                        Text {
                            text: AppController.humanDate(AppController.selectedDate)
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.capitalization: Font.MixedCase
                        }
                        Text {
                            text: {
                                const d = AppController.selectedDate;
                                if (!d || !d.getFullYear) return "";
                                const y = d.getFullYear();
                                const m = (d.getMonth()+1).toString().padStart(2,"0");
                                const dd = d.getDate().toString().padStart(2,"0");
                                const n = root._eventsToday;
                                return y + "-" + m + "-" + dd + " · " + n + " event" + (n === 1 ? "" : "s");
                            }
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Drag empty area → создать · drag task → запланировать"
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
            }

            ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                Item {
                    id: grid
                    width: scroll.availableWidth
                    implicitHeight: (root.hoursEnd - root.hoursStart) * Theme.hourH + 8

                    readonly property int labelW: 44
                    readonly property int marginX: 14

                    Repeater {
                        model: root.hoursEnd - root.hoursStart
                        Item {
                            required property int index
                            x: grid.marginX
                            y: index * Theme.hourH
                            width: grid.width - grid.marginX * 2
                            height: Theme.hourH

                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: 1; color: Theme.border
                            }
                            Text {
                                x: 0; y: 2
                                width: grid.labelW - 8
                                horizontalAlignment: Text.AlignRight
                                text: (root.hoursStart + parent.index).toString().padStart(2,"0") + ":00"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                            }
                            Rectangle {
                                x: grid.labelW; y: parent.height / 2
                                width: parent.width - grid.labelW
                                height: 1
                                color: Theme.border
                                opacity: 0.4
                            }
                        }
                    }

                    Item {
                        id: eventsLayer
                        x: grid.marginX + grid.labelW + 4
                        y: 0
                        width: grid.width - (grid.marginX * 2) - grid.labelW - 8
                        height: (root.hoursEnd - root.hoursStart) * Theme.hourH

                        // Layer 1: DropArea — accepts dragged TaskCards from Kanban.
                        DropArea {
                            id: dropZone
                            anchors.fill: parent
                            z: 0
                            property real hoverY: -1
                            property bool hoverActive: false

                            onEntered: (drag) => {
                                if (drag.source && drag.source.taskId && String(drag.source.taskId).length > 0) {
                                    hoverActive = true;
                                    hoverY = drag.y;
                                } else {
                                    hoverActive = false;
                                }
                            }
                            onPositionChanged: (drag) => {
                                if (hoverActive) hoverY = drag.y;
                            }
                            onExited: { hoverActive = false; hoverY = -1; }
                            onDropped: (drop) => {
                                hoverActive = false;
                                hoverY = -1;
                                const src = drop.source;
                                if (!src || !src.taskId || String(src.taskId).length === 0) return;
                                const h = root.snapHour(root.yToHour(drop.y));
                                AppController.scheduleTask(String(src.taskId), root.clampHour(h), AppController.selectedDate);
                                drop.acceptProposedAction();
                            }
                        }

                        // Drop indicator line (hovering task drag).
                        Rectangle {
                            visible: dropZone.hoverActive
                            x: -8
                            y: {
                                const snapped = root.snapHour(root.yToHour(dropZone.hoverY));
                                return (snapped - root.hoursStart) * Theme.hourH;
                            }
                            width: parent.width + 8
                            height: 2
                            color: Theme.accentStrong
                            z: 4
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: -4
                                width: 8; height: 8; radius: 4
                                color: Theme.accentStrong
                            }
                        }

                        // Layer 2: drag-to-create MouseArea covering empty area.
                        MouseArea {
                            id: createArea
                            anchors.fill: parent
                            z: 1
                            cursorShape: Qt.PointingHandCursor
                            property real pressY: -1
                            property real currentY: -1
                            property bool dragging: false

                            onPressed: (mouse) => {
                                pressY = mouse.y;
                                currentY = mouse.y;
                                dragging = false;
                            }
                            onPositionChanged: (mouse) => {
                                currentY = mouse.y;
                                if (!dragging && Math.abs(currentY - pressY) >= 5) dragging = true;
                            }
                            onReleased: (mouse) => {
                                if (pressY < 0) return;
                                const lo = Math.min(pressY, currentY);
                                const hi = Math.max(pressY, currentY);
                                const startH = root.snapHour(root.yToHour(lo));
                                const endH   = root.snapHour(root.yToHour(hi));
                                if (!dragging || (endH - startH) < 0.25) {
                                    // Legacy single-click → 1-hour event at clicked hour.
                                    const h = Math.floor(root.yToHour(pressY));
                                    const draft = AppController.newEventDraft(h, AppController.selectedDate);
                                    AppController.saveEvent(draft);
                                } else {
                                    const draft = AppController.newEventDraft(startH, AppController.selectedDate);
                                    draft.end = Math.min(endH, root.hoursEnd);
                                    AppController.saveEvent(draft);
                                }
                                pressY = -1; currentY = -1; dragging = false;
                            }
                            onCanceled: { pressY = -1; currentY = -1; dragging = false; }
                        }

                        // Ghost preview during drag-create.
                        Rectangle {
                            visible: createArea.dragging
                            x: 0
                            y: Math.min(createArea.pressY, createArea.currentY)
                            width: parent.width
                            height: Math.abs(createArea.currentY - createArea.pressY)
                            color: Theme.withAlpha(Theme.accent, 0.18)
                            border.color: Theme.accent
                            border.width: 1
                            radius: 6
                            z: 10
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    const a = root.snapHour(root.yToHour(Math.min(createArea.pressY, createArea.currentY)));
                                    const b = root.snapHour(root.yToHour(Math.max(createArea.pressY, createArea.currentY)));
                                    return AppController.eventHourLabel(a) + " – " + AppController.eventHourLabel(b);
                                }
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }
                        }

                        // Layer 3: event rectangles (declared after createArea → on top).
                        Repeater {
                            model: AppController.events
                            Rectangle {
                                id: evRect
                                required property string id
                                required property string title
                                required property string type
                                required property real start
                                required property real end
                                required property string attendees
                                required property var date
                                required property string taskId
                                required property string profileId

                                // Transient drag/resize state.
                                property real dragDy: 0           // pixels while move-dragging
                                property real pendingStartH: NaN  // hour while top-resizing
                                property real pendingEndH:   NaN  // hour while bottom-resizing

                                readonly property real effStart: !isNaN(pendingStartH) ? pendingStartH : start
                                readonly property real effEnd:   !isNaN(pendingEndH)   ? pendingEndH   : end

                                // Resolve once per event change so the dot reflects rename / recolor.
                                readonly property var profileInfo: profileId.length > 0
                                    ? AppController.profileById(profileId)
                                    : null

                                visible: root.isSameDay(date, AppController.selectedDate)
                                x: 0
                                y: (effStart - root.hoursStart) * Theme.hourH + dragDy
                                width: parent.width
                                height: Math.max(20, (effEnd - effStart) * Theme.hourH - 2)
                                radius: 6
                                color: Theme.withAlpha(Theme.eventColor(type), 0.16)
                                z: 5

                                Rectangle {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: 3
                                    color: Theme.eventColor(evRect.type)
                                    radius: 1
                                }

                                // Feature/profile color dot (top-right).
                                Rectangle {
                                    visible: evRect.profileInfo !== null
                                    anchors.top: parent.top; anchors.right: parent.right
                                    anchors.topMargin: 6; anchors.rightMargin: 6
                                    width: 8; height: 8; radius: 4
                                    color: evRect.profileInfo ? evRect.profileInfo.color : Theme.accent
                                    border.color: Theme.bg
                                    border.width: 1
                                }

                                Column {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 20
                                    anchors.topMargin: 6; anchors.bottomMargin: 6
                                    spacing: 2
                                    clip: true
                                    Text {
                                        width: parent.width
                                        text: evRect.title + (evRect.taskId ? "  " + evRect.taskId : "")
                                        color: Theme.text
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: AppController.eventHourLabel(evRect.effStart) + " – " + AppController.eventHourLabel(evRect.effEnd)
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        visible: evRect.attendees.length > 0 && evRect.height > 50
                                        text: "· " + evRect.attendees
                                        color: Theme.textMuted
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                    Text {
                                        visible: evRect.profileInfo !== null && evRect.height > 70
                                        text: evRect.profileInfo ? evRect.profileInfo.name : ""
                                        color: evRect.profileInfo ? evRect.profileInfo.color : Theme.textDim
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }

                                // Move-drag MouseArea (middle band of event).
                                MouseArea {
                                    id: moveArea
                                    anchors.fill: parent
                                    anchors.topMargin: 6
                                    anchors.bottomMargin: 6
                                    cursorShape: didDrag ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    property real grabY: 0
                                    property real baseY: 0
                                    property bool didDrag: false

                                    onPressed: (mouse) => {
                                        grabY = mouse.y;
                                        baseY = (evRect.start - root.hoursStart) * Theme.hourH;
                                        didDrag = false;
                                        evRect.dragDy = 0;
                                    }
                                    onPositionChanged: (mouse) => {
                                        const pt = moveArea.mapToItem(eventsLayer, mouse.x, mouse.y);
                                        const wantY = pt.y - grabY;
                                        const dy = wantY - baseY;
                                        if (!didDrag && Math.abs(dy) > 5) didDrag = true;
                                        if (didDrag) evRect.dragDy = dy;
                                    }
                                    onReleased: {
                                        if (didDrag) {
                                            const baseAbs = (evRect.start - root.hoursStart) * Theme.hourH;
                                            const newAbs = baseAbs + evRect.dragDy;
                                            const dur = evRect.end - evRect.start;
                                            let ns = root.snapHour(root.yToHour(newAbs));
                                            ns = Math.max(root.hoursStart, Math.min(ns, root.hoursEnd - dur));
                                            AppController.updateEvent(evRect.id, ns, ns + dur, AppController.selectedDate);
                                            evRect.dragDy = 0;
                                        } else {
                                            root.eventClicked(evRect.id);
                                        }
                                        didDrag = false;
                                    }
                                    onCanceled: { evRect.dragDy = 0; didDrag = false; }
                                }

                                // Top resize handle.
                                MouseArea {
                                    id: topHandle
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                    height: 6
                                    cursorShape: Qt.SizeVerCursor
                                    property bool resizing: false
                                    onPressed: { resizing = true; evRect.pendingStartH = evRect.start; }
                                    onPositionChanged: (mouse) => {
                                        if (!resizing) return;
                                        const pt = topHandle.mapToItem(eventsLayer, mouse.x, mouse.y);
                                        const h = root.snapHour(root.yToHour(pt.y));
                                        const clamped = Math.min(h, evRect.end - 0.25);
                                        evRect.pendingStartH = Math.max(root.hoursStart, clamped);
                                    }
                                    onReleased: {
                                        if (!resizing) return;
                                        resizing = false;
                                        const ns = evRect.pendingStartH;
                                        AppController.updateEvent(evRect.id, ns, evRect.end, AppController.selectedDate);
                                        evRect.pendingStartH = NaN;
                                    }
                                    onCanceled: { resizing = false; evRect.pendingStartH = NaN; }
                                }

                                // Bottom resize handle.
                                MouseArea {
                                    id: bottomHandle
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    height: 6
                                    cursorShape: Qt.SizeVerCursor
                                    property bool resizing: false
                                    onPressed: { resizing = true; evRect.pendingEndH = evRect.end; }
                                    onPositionChanged: (mouse) => {
                                        if (!resizing) return;
                                        const pt = bottomHandle.mapToItem(eventsLayer, mouse.x, mouse.y);
                                        const h = root.snapHour(root.yToHour(pt.y));
                                        const clamped = Math.max(h, evRect.start + 0.25);
                                        evRect.pendingEndH = Math.min(root.hoursEnd, clamped);
                                    }
                                    onReleased: {
                                        if (!resizing) return;
                                        resizing = false;
                                        const ne = evRect.pendingEndH;
                                        AppController.updateEvent(evRect.id, evRect.start, ne, AppController.selectedDate);
                                        evRect.pendingEndH = NaN;
                                    }
                                    onCanceled: { resizing = false; evRect.pendingEndH = NaN; }
                                }
                            }
                        }

                        // Now line
                        Rectangle {
                            visible: root.isSameDay(root.now, AppController.selectedDate)
                                     && (root.now.getHours() + root.now.getMinutes()/60) >= root.hoursStart
                                     && (root.now.getHours() + root.now.getMinutes()/60) <= root.hoursEnd
                            x: -8
                            width: parent.width + 8
                            y: ((root.now.getHours() + root.now.getMinutes()/60) - root.hoursStart) * Theme.hourH
                            height: 2
                            color: Theme.p0
                            z: 3
                            Rectangle {
                                x: -3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10; height: 10; radius: 5; color: Theme.p0
                            }
                        }
                    }
                }
            }
        }
    }
}
