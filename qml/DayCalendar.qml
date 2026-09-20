import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp
import "Overlap.js" as Overlap
import "Segments.js" as Seg

Item {
    id: root
    // The grid covers the whole day. It used to run from workdayStart to
    // workdayEnd — 9 to 19 by default — and anything outside that was laid out
    // off-grid: an 07:00 standup or a 21:00 call was counted in the "N events"
    // header and drawn nowhere the user could reach it.
    //
    // Working hours are still marked; they just tint the background now
    // instead of deciding what exists.
    readonly property int hoursStart: 0
    readonly property int hoursEnd:   24
    readonly property int workStart:  AppController.workdayStart
    readonly property int workEnd:    AppController.workdayEnd
    readonly property real pxPerMin: Theme.hourH / 60.0

    // The occurrence, not just its id: a repeating event is stored once, so
    // every occurrence of a series carries the master's id and only the
    // occurrence map says which date was clicked.
    signal eventClicked(string id, var occurrence)
    signal taskClicked(string id)

    function snapHour(h)  {
        const step = Math.max(1, Theme.snapMinutes) / 60.0;
        return Math.round(h / step) * step;
    }
    function yToHour(y)   { return root.hoursStart + y / Theme.hourH; }
    function clampHour(h) { return Math.max(root.hoursStart, Math.min(root.hoursEnd, h)); }

    property date now: new Date()
    Timer { interval: 60000; repeat: true; running: true; onTriggered: root.now = new Date() }

    // The events this day can show, which is not the same as the rows in the
    // model: a repeating event is stored once and expanded here, and an
    // occurrence someone moved is an override standing in for it. Asking for a
    // day either side too, because a timed event that crosses midnight reaches
    // in from the day before.
    property var _spans: []
    function _recomputeSpans() {
        const d = AppController.selectedDate;
        if (!d || !d.getFullYear) { _spans = []; return; }
        const from = new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1);
        const to = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1);
        _spans = AppController.eventOccurrences(from, to);
    }
    function _allSpans() { return root._spans; }

    // Reactive event count for the selected day; refreshed on every
    // events-model mutation so the "N events" header stays in sync.
    property int _eventsToday: 0
    function _recountEventsToday() {
        const d = AppController.selectedDate;
        if (!d || !d.getFullYear) { _eventsToday = 0; return; }
        const all = root._allSpans();
        let n = 0;
        for (let i = 0; i < all.length; i++) if (Seg.covers(all[i], d)) n++;
        _eventsToday = n;
    }
    // ── Overlap layout ────────────────────────────────────────────────
    // Map of event id → { col, cols } describing which column an event sits in
    // and how many columns its overlap cluster spans. Events that share a time
    // window are packed side-by-side (2 overlapping → 50% width each, 3 → 33%,
    // …) instead of stacking on top of each other. Recomputed on every model
    // mutation and day change.
    property var _overlap: ({})
    function _recomputeOverlaps() {
        // Timed pieces only: an all-day event has no hours to pack and would
        // squeeze every real meeting on the day into a sliver.
        _overlap = Overlap.compute(Seg.timedOn(root._allSpans(), AppController.selectedDate));
    }

    // All-day events covering the selected day, longest first. Bound from a
    // handler, never from a binding on a property this function also writes.
    property var _stripEvents: []
    function _recomputeStrip() {
        _stripEvents = Seg.stripOn(root._allSpans(), AppController.selectedDate);
    }

    // ── Task blocks vs. their meeting events ──────────────────────────
    // A "sync" capture creates both a task (with a scheduled time, HEAP-115)
    // and a meeting event linked back to it via taskId. The event is the
    // richer representation (attendees, duration), so the task's own block is
    // suppressed on any day where a linked event already stands in for it —
    // otherwise the same "синк с @hb" draws twice. Keyed by task id, recomputed
    // with the overlaps on every events-model or day change.
    property var _linkedTaskIds: ({})
    function _recomputeLinkedTasks() {
        const d = AppController.selectedDate;
        const all = root._allSpans();
        const map = {};
        for (let i = 0; i < all.length; i++) {
            if (!Seg.covers(all[i], d)) continue;
            const tid = String(all[i].taskId || "");
            if (tid.length > 0) map[tid] = true;
        }
        _linkedTaskIds = map;
    }
    function _recomputeDay() {
        _recomputeSpans();
        _recountEventsToday();
        _recomputeOverlaps();
        _recomputeStrip();
        _recomputeLinkedTasks();
    }

    Connections {
        target: AppController.events
        function onRowsInserted() { root._recomputeDay() }
        function onRowsRemoved()  { root._recomputeDay() }
        function onDataChanged()  { root._recomputeDay() }
        function onModelReset()   { root._recomputeDay() }
    }
    Connections {
        target: AppController
        function onSelectedDateChanged() { root._recomputeDay() }
    }
    Component.onCompleted: root._recomputeDay()

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
                                return y + "-" + m + "-" + dd + " · " + I18n.events(root._eventsToday);
                            }
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // Elided: the hint is longer than the right-hand panel is
                    // wide, so it used to run off the edge mid-word.
                    Text {
                        text: I18n.t("day.dragHint")
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        HoverHandler { id: hintHover }
                        ToolTip.visible: hintHover.hovered && truncated
                        ToolTip.delay: 400
                        ToolTip.text: I18n.t("day.dragHint")
                    }
                }
            }

            // All-day events. They have no hours, so they cannot go on the
            // grid; a strip under the header is where every calendar puts
            // them, and it keeps them visible however far the grid is
            // scrolled.
            Rectangle {
                id: allDayStrip
                objectName: "allday-strip"
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? (root._stripEvents.length * 26 + 10) : 0
                visible: root._stripEvents.length > 0
                color: Theme.panel

                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 1; color: Theme.border
                }

                Column {
                    anchors.fill: parent
                    anchors.leftMargin: 14 + 44   // clear of the hour labels, so bars line up with the grid
                    anchors.rightMargin: 14
                    anchors.topMargin: 5
                    spacing: 2

                    Repeater {
                        model: root._stripEvents
                        Rectangle {
                            id: bar
                            required property var modelData
                            objectName: "allday-" + bar.modelData.id
                            width: parent.width
                            height: 24
                            radius: 4
                            color: Theme.withAlpha(Theme.eventColor(bar.modelData.type || "sync"), 0.16)

                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: 3; radius: 1
                                color: Theme.eventColor(bar.modelData.type || "sync")
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 8
                                spacing: 6
                                Text {
                                    text: bar.modelData.title || ""
                                    color: Theme.text
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                // Which day of the run this is, so a week-long
                                // trip reads as progress rather than as the
                                // same bar repeated.
                                Text {
                                    visible: Seg.multiDay(bar.modelData)
                                    text: (Seg.dayOffset(bar.modelData, AppController.selectedDate) + 1)
                                          + "/" + Seg.dayCount(bar.modelData)
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                            }

                            TapHandler { onTapped: root.eventClicked(bar.modelData.id, bar.modelData) }
                        }
                    }
                }
            }

            ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                // Open on the part of the day the user is in. A grid that now
                // starts at midnight would otherwise open on eight empty
                // hours, which is worse than the clipping it replaced.
                //
                // Today scrolls to an hour before now; another day to the
                // start of the working day.
                function scrollToRelevantHour() {
                    const today = AppController.selectedDate
                        && AppController.selectedDate.getFullYear
                        && AppController.selectedDate.getFullYear() === root.now.getFullYear()
                        && AppController.selectedDate.getMonth() === root.now.getMonth()
                        && AppController.selectedDate.getDate() === root.now.getDate();
                    const hour = today
                        ? Math.max(0, root.now.getHours() - 1)
                        : root.workStart;
                    const maxY = Math.max(0, grid.implicitHeight - scroll.availableHeight);
                    ScrollBar.vertical.position = maxY > 0
                        ? Math.min(1, (hour * Theme.hourH) / grid.implicitHeight)
                        : 0;
                }
                Component.onCompleted: Qt.callLater(scrollToRelevantHour)
                Connections {
                    target: AppController
                    function onSelectedDateChanged() { Qt.callLater(scroll.scrollToRelevantHour); }
                }

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

                            // Outside the working day. Dimmed, not hidden:
                            // the hour is still there to drop a meeting on.
                            Rectangle {
                                anchors.fill: parent
                                visible: parent.index < root.workStart || parent.index >= root.workEnd
                                color: Theme.bg2
                                opacity: 0.55
                            }
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: 1; color: Theme.border
                            }
                            Text {
                                x: 0; y: 2
                                width: grid.labelW - 8
                                horizontalAlignment: Text.AlignRight
                                text: Theme.fmtHour(root.hoursStart + parent.index)
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
                        // preventStealing keeps the surrounding ScrollView's
                        // Flickable from hijacking the vertical drag — without
                        // it the drag-to-create only ever fires onPressed and
                        // onReleased (no positionChanged), so we'd fall back to
                        // the single-click 1-hour event branch.
                        MouseArea {
                            id: createArea
                            anchors.fill: parent
                            z: 1
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
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
                                if (!dragging || (endH - startH) < Theme.minEventHours) {
                                    // Legacy single-click → 1-hour event at clicked hour.
                                    const h = Math.floor(root.yToHour(pressY));
                                    const draft = AppController.newEventDraft(h, AppController.selectedDate);
                                    AppController.saveEvent(draft);
                                } else {
                                    const draft = AppController.newEventDraft(startH, AppController.selectedDate);
                                    draft.end = Math.min(endH, 24);
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
                                    return Theme.fmtHour(a) + " – " + Theme.fmtHour(b);
                                }
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }
                        }

                        // Layer 3: event rectangles (declared after createArea → on top).
                        Repeater {
                            // The expansion, not the model: a repeating event
                            // is one row and many blocks.
                            model: root._spans
                            Rectangle {
                                id: evRect
                                required property var modelData
                                objectName: "event-" + evRect.id
                                // Named individually so the rest of the
                                // delegate reads the same as when this was
                                // bound to model roles.
                                readonly property string id: evRect.modelData.id
                                readonly property string title: evRect.modelData.title || ""
                                readonly property string type: evRect.modelData.type || ""
                                readonly property real start: evRect.modelData.start
                                readonly property real end: evRect.modelData.end
                                readonly property string attendees: evRect.modelData.attendees || ""
                                readonly property var date: evRect.modelData.date
                                readonly property string taskId: evRect.modelData.taskId || ""
                                readonly property string profileId: evRect.modelData.profileId || ""
                                readonly property string context: evRect.modelData.context || ""
                                readonly property bool allDay: !!evRect.modelData.allDay
                                readonly property var endDate: evRect.modelData.endDate
                                // Set on anything the expansion generated, so
                                // an edit can ask "this one, or all of them?"
                                readonly property string masterId: evRect.modelData.masterId || ""
                                readonly property var occurrenceDate: evRect.modelData.occurrenceDate
                                readonly property bool repeating: evRect.masterId.length > 0

                                // The piece of this event that lands on the
                                // selected day. An event may now run past
                                // midnight, so the block draws its segment
                                // rather than the event's own hours — 22:00 to
                                // 02:00 is one event and two blocks.
                                readonly property var seg: Seg.segmentOn(
                                    { id: evRect.id, date: evRect.date, endDate: evRect.endDate,
                                      start: evRect.start, end: evRect.end, allDay: evRect.allDay },
                                    AppController.selectedDate)
                                // A piece that carries neither the event's
                                // start nor its end has no edge to drag.
                                readonly property bool wholeEvent: evRect.seg !== null && evRect.seg.first && evRect.seg.last

                                // Transient drag/resize state.
                                property real dragDy: 0           // pixels while move-dragging
                                property real pendingStartH: NaN  // hour while top-resizing
                                property real pendingEndH:   NaN  // hour while bottom-resizing

                                readonly property real effStart: !isNaN(pendingStartH) ? pendingStartH : (evRect.seg ? evRect.seg.start : evRect.start)
                                readonly property real effEnd:   !isNaN(pendingEndH)   ? pendingEndH   : (evRect.seg ? evRect.seg.end   : evRect.end)

                                // Resolve once per event change so the dot reflects rename / recolor.
                                readonly property var profileInfo: profileId.length > 0
                                    ? AppController.profileById(profileId)
                                    : null

                                // Side-by-side overlap slot (see root._overlap).
                                readonly property var slot: root._overlap[id] || ({ col: 0, cols: 1 })
                                readonly property real colGap: 3
                                readonly property real colW: parent.width / Math.max(1, slot.cols)

                                // All-day events live in the strip above; the
                                // grid draws only what has hours.
                                visible: evRect.seg !== null && !evRect.allDay
                                x: slot.col * colW
                                y: (effStart - root.hoursStart) * Theme.hourH + dragDy
                                width: Math.max(20, colW - colGap)
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
                                    RowLayout {
                                        width: parent.width
                                        spacing: 6
                                        Text {
                                            visible: evRect.context.length > 0
                                            text: evRect.context
                                            color: Theme.textMuted
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: parent.width * 0.45
                                        }
                                        Rectangle {
                                            visible: evRect.context.length > 0
                                            Layout.preferredWidth: 6; Layout.preferredHeight: 6
                                            radius: 3
                                            color: evRect.profileInfo
                                                ? evRect.profileInfo.color
                                                : Theme.eventColor(evRect.type)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: evRect.title + (evRect.taskId ? "  " + evRect.taskId : "")
                                            color: Theme.text
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Text {
                                        text: Theme.fmtHour(evRect.effStart) + " – " + Theme.fmtHour(evRect.effEnd)
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
                                    preventStealing: true
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
                                        // grabY is moveArea-local; moveArea's origin sits topMargin
                                        // below the event top, while pt/baseY are eventsLayer-absolute.
                                        // Subtract the inset so a still pointer yields dy == 0 (else a
                                        // constant +6px bias trips didDrag and drops events late).
                                        const wantY = pt.y - grabY - moveArea.anchors.topMargin;
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
                                            root.eventClicked(evRect.id, evRect.modelData);
                                        }
                                        didDrag = false;
                                    }
                                    onCanceled: { evRect.dragDy = 0; didDrag = false; }
                                }

                                // Top resize handle. Hidden on a piece of a
                                // spanning event: its edge is on another day,
                                // and dragging it here would describe an hour
                                // range the event does not have.
                                MouseArea {
                                    id: topHandle
                                    enabled: evRect.wholeEvent
                                    visible: enabled
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                    height: 6
                                    cursorShape: Qt.SizeVerCursor
                                    preventStealing: true
                                    property bool resizing: false
                                    onPressed: { resizing = true; evRect.pendingStartH = evRect.start; }
                                    onPositionChanged: (mouse) => {
                                        if (!resizing) return;
                                        const pt = topHandle.mapToItem(eventsLayer, mouse.x, mouse.y);
                                        const h = root.snapHour(root.yToHour(pt.y));
                                        const clamped = Math.min(h, evRect.end - Theme.minEventHours);
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

                                // Bottom resize handle. Hidden for the same
                                // reason as the top one.
                                MouseArea {
                                    id: bottomHandle
                                    enabled: evRect.wholeEvent
                                    visible: enabled
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    height: 6
                                    cursorShape: Qt.SizeVerCursor
                                    preventStealing: true
                                    property bool resizing: false
                                    onPressed: { resizing = true; evRect.pendingEndH = evRect.end; }
                                    onPositionChanged: (mouse) => {
                                        if (!resizing) return;
                                        const pt = bottomHandle.mapToItem(eventsLayer, mouse.x, mouse.y);
                                        const h = root.snapHour(root.yToHour(pt.y));
                                        const clamped = Math.max(h, evRect.start + Theme.minEventHours);
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

                        // Layer 3b: tasks scheduled at a clock time (HEAP-115).
                        // Before this, the only way a task's parsed time reached
                        // the day view was a side focus-block event; now the
                        // task's own scheduledAt puts it here.
                        Repeater {
                            model: AppController.tasks
                            Rectangle {
                                id: taskBlock
                                required property string id
                                required property string title
                                objectName: "taskblock-" + id
                                required property var scheduledAt
                                required property bool hasTime
                                required property bool archived
                                required property string status

                                readonly property real startHour: hasTime && scheduledAt && scheduledAt.getHours
                                    ? scheduledAt.getHours() + scheduledAt.getMinutes() / 60.0
                                    : -1

                                visible: !archived && status !== "done" && startHour >= 0
                                         && root.isSameDay(scheduledAt, AppController.selectedDate)
                                         && !root._linkedTaskIds[id]
                                x: 0
                                y: (startHour - root.hoursStart) * Theme.hourH
                                width: Math.max(20, parent.width * 0.5 - 3)
                                height: Theme.hourH - 2
                                radius: 6
                                color: Theme.withAlpha(Theme.eventColor("focus"), openArea.containsMouse ? 0.18 : 0.10)
                                border.color: Theme.withAlpha(Theme.eventColor("focus"), openArea.containsMouse ? 0.9 : 0.5)
                                border.width: 1
                                z: 4

                                Text {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    text: "▸ " + taskBlock.title
                                    color: Theme.text
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }

                                // The block carried no MouseArea, so a click on it was
                                // swallowed and the task never opened. Clicks must not
                                // reach the create-an-event area underneath either.
                                MouseArea {
                                    id: openArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.taskClicked(taskBlock.id)
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

    // No-events hint for an empty day — faint, non-interactive so drag-to-create
    // on the grid underneath still works.
    Text {
        anchors.centerIn: parent
        width: parent.width - 48
        visible: root._eventsToday === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: I18n.t("day.noEvents")
        color: Theme.textDim
        font.pixelSize: 11
    }
}
