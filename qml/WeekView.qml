import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Item {
    id: root

    property string searchText: ""
    property var prioritiesFilter: ({})
    property bool showArchived: false

    signal taskClicked(string id)
    signal eventClicked(string id)
    signal dayClicked(date d)

    // Shift-click anchor + day for range select. Shift across days falls back
    // to single-toggle since the visible-chip order isn't a single flat list.
    property string shiftAnchorId: ""
    property int    shiftAnchorDay: -1
    Connections {
        target: AppController

        function onSelectedTaskIdsChanged() {
            if (AppController.selectionCount === 0) {
                root.shiftAnchorId = "";
                root.shiftAnchorDay = -1;
            }
        }
    }

    function _renderedIdsForDay(dayIdx) {
        if (dayIdx < 0 || dayIdx >= days.length) return [];
        const list = days[dayIdx].tasks.slice(0, 4);
        const ids = [];
        for (let i = 0; i < list.length; i++) ids.push(list[i].id);
        return ids;
    }

    function _dayIndexOfTask(taskId) {
        for (let i = 0; i < days.length; i++) {
            const ids = _renderedIdsForDay(i);
            if (ids.indexOf(taskId) >= 0) return i;
        }
        return -1;
    }

    function selectAllVisible() {
        const ids = [];
        for (let i = 0; i < days.length; i++) {
            const part = _renderedIdsForDay(i);
            for (let j = 0; j < part.length; j++) ids.push(part[j]);
        }
        AppController.setSelectedTaskIds(ids);
    }

    function _rangeSelect(targetId) {
        const targetDay = _dayIndexOfTask(targetId);
        if (targetDay < 0) return;
        if (root.shiftAnchorId === "" || root.shiftAnchorDay !== targetDay
            || _renderedIdsForDay(targetDay).indexOf(root.shiftAnchorId) < 0) {
            root.shiftAnchorId = targetId;
            root.shiftAnchorDay = targetDay;
            AppController.toggleTaskSelection(targetId);
            return;
        }
        const ordered = _renderedIdsForDay(targetDay);
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

    readonly property int hoursStart: AppController.workdayStart
    readonly property int hoursEnd:   AppController.workdayEnd
    readonly property int hourH: 38
    // Indexed by JS day-of-week (0=Sun..6=Sat) so the label tracks the actual
    // date regardless of which day the week starts on.
    readonly property var dowLabelsByJsDow: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    function isSameDay(a, b) {
        if (!a || !b || !a.getFullYear || !b.getFullYear) return false;
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function startOfWeek(d) {
        const dow = d.getDay();
        const sundayFirst = Theme.weekStart === "sun";
        const offset = sundayFirst ? -dow : (dow === 0 ? -6 : 1 - dow);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset);
    }
    function fmtShort(d) {
        return AppController.shortDate(d);
    }
    function snapHour(h)  {
        const step = Math.max(1, Theme.snapMinutes) / 60.0;
        return Math.round(h / step) * step;
    }
    function yToHour(y)   { return root.hoursStart + y / root.hourH; }
    function clampHour(h) { return Math.max(root.hoursStart, Math.min(root.hoursEnd, h)); }
    function passesFilter(t) {
        if (t.status === "done") return false;
        const q = (root.searchText || "").toLowerCase();
        if (q && q.length > 0) {
            const hay = ((t.title || "") + " " + (t.id || "") + " " + (t.desc || "")).toLowerCase();
            if (hay.indexOf(q) < 0) return false;
        }
        let any = false;
        for (const k in root.prioritiesFilter) if (root.prioritiesFilter[k]) { any = true; break; }
        if (any && !root.prioritiesFilter[t.priority]) return false;
        return true;
    }

    property int taskRev: 0
    property int eventRev: 0
    Connections {
        target: AppController.tasks
        function onDataChanged()  { root.taskRev++ }
        function onRowsInserted() { root.taskRev++ }
        function onRowsRemoved()  { root.taskRev++ }
        function onModelReset()   { root.taskRev++ }
    }
    Connections {
        target: AppController.events
        function onDataChanged()  { root.eventRev++ }
        function onRowsInserted() { root.eventRev++ }
        function onRowsRemoved()  { root.eventRev++ }
        function onModelReset()   { root.eventRev++ }
    }

    // Declarative binding: re-evaluates on AppController.selectedDate and
    // Theme.weekStart changes — no manual Connections needed.
    property var weekStart: startOfWeek(AppController.selectedDate)

    function buildDays() {
        const start = weekStart;
        const days = [];
        const _t = root.taskRev; const _e = root.eventRev;
        const showWeekends = Theme.showWeekends;
        for (let i = 0; i < 7; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            if (!showWeekends && (d.getDay() === 0 || d.getDay() === 6)) continue;
            days.push({ date: d, tasks: [], events: [] });
        }
        const tm = AppController.tasks;
        for (let i = 0; i < tm.rowCount(); i++) {
            const idx = tm.index(i, 0);
            const archived = tm.data(idx, Qt.UserRole + 9);
            if (archived && !root.showArchived) continue;
            const t = {
                id:       tm.data(idx, Qt.UserRole + 1),
                title:    tm.data(idx, Qt.UserRole + 2),
                desc:     tm.data(idx, Qt.UserRole + 3),
                priority: tm.data(idx, Qt.UserRole + 4),
                status:   tm.data(idx, Qt.UserRole + 5),
                deadline: tm.data(idx, Qt.UserRole + 6),
                branch:   tm.data(idx, Qt.UserRole + 7),
            };
            if (!t.deadline || !t.deadline.getTime) continue;
            if (!root.passesFilter(t)) continue;
            for (let k = 0; k < days.length; k++) {
                if (root.isSameDay(days[k].date, t.deadline)) {
                    days[k].tasks.push(t);
                    break;
                }
            }
        }
        const em = AppController.events;
        for (let i = 0; i < em.rowCount(); i++) {
            const idx = em.index(i, 0);
            const e = {
                id:        em.data(idx, Qt.UserRole + 1),
                title:     em.data(idx, Qt.UserRole + 2),
                type:      em.data(idx, Qt.UserRole + 3),
                start:     em.data(idx, Qt.UserRole + 4),
                end:       em.data(idx, Qt.UserRole + 5),
                attendees: em.data(idx, Qt.UserRole + 6),
                date:      em.data(idx, Qt.UserRole + 7),
                context: em.data(idx, Qt.UserRole + 10) || "",
            };
            for (let k = 0; k < days.length; k++) {
                if (root.isSameDay(days[k].date, e.date)) { days[k].events.push(e); break; }
            }
        }
        const priRank = { P0: 0, P1: 1, P2: 2, P3: 3 };
        for (let k = 0; k < days.length; k++) {
            days[k].tasks.sort((a, b) => (priRank[a.priority] || 9) - (priRank[b.priority] || 9));
        }
        return days;
    }

    // Declarative: buildDays() reads weekStart, taskRev, eventRev, showArchived,
    // searchText, prioritiesFilter, and Theme.showWeekends — QML auto-tracks
    // those reads and re-evaluates this binding when any of them changes.
    readonly property var days: buildDays()

    // True when the visible week has neither task deadlines nor events, so the
    // grid would otherwise read as blank/broken.
    readonly property bool weekEmpty: {
        for (let i = 0; i < days.length; i++)
            if (days[i].tasks.length > 0 || days[i].events.length > 0) return false;
        return true;
    }

    // Flattened events with per-week day index so interactive drag/resize
    // can position them absolutely (and move across day columns).
    function buildFlatEvents() {
        const out = [];
        for (let i = 0; i < days.length; i++) {
            for (let j = 0; j < days[i].events.length; j++) {
                const e = days[i].events[j];
                out.push({
                    id: e.id, title: e.title, type: e.type,
                    start: e.start, end: e.end, attendees: e.attendees,
                    date: e.date, dayIndex: i, context: e.context || ""
                });
            }
        }
        return out;
    }
    readonly property var flatEvents: buildFlatEvents()

    function totalTasks() {
        let n = 0;
        for (let i = 0; i < days.length; i++) n += days[i].tasks.length;
        return n;
    }
    function totalEvents() {
        let n = 0;
        for (let i = 0; i < days.length; i++) n += days[i].events.length;
        return n;
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: Theme.panel
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: Theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 14
                spacing: 8

                PillButton {
                    text: "←"
                    onClicked: AppController.selectedDate = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() - 7)
                }
                ColumnLayout {
                    spacing: 1
                    Layout.alignment: Qt.AlignVCenter
                    RowLayout {
                        spacing: 10
                        Text {
                            text: "WEEK " + AppController.isoWeekNumber(weekStart)
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            font.letterSpacing: 1
                        }
                        Text {
                            text: AppController.shortDate(weekStart) + " — " + AppController.shortDate(new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + 6))
                            color: Theme.text
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.totalTasks() + " deadlines · " + root.totalEvents() + " events"
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
                PillButton {
                    text: "Today"
                    onClicked: AppController.selectedDate = AppController.today
                }
                PillButton {
                    text: "→"
                    onClicked: AppController.selectedDate = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + 7)
                }
            }
        }

        // 7-column grid
        Item {
            id: gridHost
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property int gutterW: 50
            readonly property int dayCount: Math.max(1, root.days.length)
            readonly property int dayW: Math.max(120, (width - gutterW) / dayCount)
            readonly property int dueRowH: 116

            // Sticky header band for the day-header + due-chips area
            Rectangle {
                id: headerBand
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: 60 + gridHost.dueRowH
                color: Theme.panel
                z: 2

                // gutter spacer
                Rectangle {
                    width: gridHost.gutterW; height: parent.height
                    color: Theme.panel
                    Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }
                }

                Repeater {
                    model: root.days
                    delegate: Item {
                        id: headCol
                        required property var modelData
                        required property int index
                        x: gridHost.gutterW + index * gridHost.dayW
                        y: 0
                        width: gridHost.dayW
                        height: headerBand.height
                        readonly property bool isToday: root.isSameDay(modelData.date, AppController.today)
                        readonly property bool isWeekend: index >= 5

                        Rectangle {
                            anchors.fill: parent
                            color: headCol.isToday ? Theme.accentSoft
                                 : headCol.isWeekend ? Theme.withAlpha(Theme.textDim, 0.04)
                                 : "transparent"
                            Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }
                            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }
                        }

                        // Day header
                        Item {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            height: 60
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AppController.selectedDate = headCol.modelData.date
                            }
                            RowLayout {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 6
                                Text {
                                    text: root.dowLabelsByJsDow[headCol.modelData.date.getDay()]
                                    color: headCol.isToday ? Theme.accentStrong : Theme.textMuted
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1
                                }
                                Rectangle {
                                    visible: headCol.isToday
                                    radius: 4
                                    color: Theme.accent
                                    implicitWidth: tBadge.implicitWidth + 8; implicitHeight: 16
                                    Text { id: tBadge; anchors.centerIn: parent; text: "TODAY"; color: "#06121a"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                                }
                            }
                            Text {
                                anchors.left: parent.left; anchors.bottom: parent.bottom
                                anchors.leftMargin: 10; anchors.bottomMargin: 6
                                text: headCol.modelData.date.getDate()
                                color: headCol.isToday ? Theme.accentStrong : Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                        }

                        // Due chips strip
                        Item {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.topMargin: 60
                            height: gridHost.dueRowH

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 4

                                Repeater {
                                    model: headCol.modelData.tasks.slice(0, 4)
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool _selected: AppController.selectionCount >= 0
                                            && AppController.isTaskSelected(modelData.id)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 22
                                        radius: 4
                                        color: _selected ? Theme.withAlpha(Theme.accent, 0.18)
                                            : chipMA.containsMouse ? Theme.panel2 : Theme.panel3
                                        border.color: _selected ? Theme.accent
                                            : Theme.withAlpha(Theme.priorityColor(modelData.priority), 0.45)
                                        border.width: _selected ? 2 : 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6; anchors.rightMargin: 6
                                            spacing: 4
                                            Text {
                                                text: modelData.id
                                                color: Theme.accentStrong
                                                font.family: Theme.fontMono
                                                font.pixelSize: 9
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                color: Theme.text
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                            }
                                            Rectangle {
                                                width: 6; height: 6; radius: 1
                                                color: Theme.priorityColor(modelData.priority)
                                            }
                                        }
                                        MouseArea {
                                            id: chipMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton
                                            onClicked: (mouse) => {
                                                const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                                                const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                                if (ctrl) {
                                                    AppController.toggleTaskSelection(modelData.id);
                                                } else if (shift) {
                                                    root._rangeSelect(modelData.id);
                                                } else {
                                                    if (AppController.selectionCount > 0) AppController.clearSelection();
                                                    root.taskClicked(modelData.id);
                                                }
                                            }
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: 400
                                            ToolTip.text: modelData.title
                                        }
                                    }
                                }
                                Text {
                                    visible: headCol.modelData.tasks.length > 4
                                    text: "+ " + (headCol.modelData.tasks.length - 4) + " more"
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                }
                                Text {
                                    visible: headCol.modelData.tasks.length === 0
                                    text: "·"
                                    color: Theme.textDim
                                    font.pixelSize: 14
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            // Scrollable hour grid
            ScrollView {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: headerBand.bottom; anchors.bottom: parent.bottom
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                Item {
                    id: gridContent
                    width: gridHost.width
                    height: (root.hoursEnd - root.hoursStart) * root.hourH + 4

                    // Hour-label gutter
                    Item {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: gridHost.gutterW

                        Repeater {
                            model: root.hoursEnd - root.hoursStart
                            Text {
                                required property int index
                                x: 0
                                y: index * root.hourH - 6
                                width: gridHost.gutterW - 8
                                horizontalAlignment: Text.AlignRight
                                text: Theme.fmtHour(root.hoursStart + index)
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                            }
                        }
                        Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }
                    }

                    // 7 day columns
                    Repeater {
                        model: root.days
                        delegate: Item {
                            id: dayCol
                            required property var modelData
                            required property int index
                            x: gridHost.gutterW + index * gridHost.dayW
                            y: 0
                            width: gridHost.dayW
                            height: (root.hoursEnd - root.hoursStart) * root.hourH
                            readonly property bool isToday: root.isSameDay(modelData.date, AppController.today)
                            readonly property bool isWeekend: index >= 5

                            Rectangle {
                                anchors.fill: parent
                                color: dayCol.isToday ? Theme.withAlpha(Theme.accent, 0.04)
                                     : dayCol.isWeekend ? Theme.withAlpha(Theme.textDim, 0.04)
                                     : "transparent"
                                Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }
                            }

                            // Hour separators
                            Repeater {
                                model: root.hoursEnd - root.hoursStart
                                Rectangle {
                                    required property int index
                                    anchors.left: parent.left; anchors.right: parent.right
                                    y: index * root.hourH
                                    height: 1
                                    color: Theme.border
                                    opacity: 0.5
                                }
                            }

                        }
                    }

                    // Flat interactive events layer — declared after the day
                    // columns so it sits on top, and uses absolute coords
                    // (dayIndex × dayW) to allow drag between columns.
                    Repeater {
                        model: root.flatEvents
                        delegate: Rectangle {
                            id: weEv
                            required property var modelData

                            property real dragDx: 0
                            property real dragDy: 0
                            property real pendingStartH: NaN
                            property real pendingEndH:   NaN

                            readonly property int effDayIndex: {
                                const raw = modelData.dayIndex + Math.round(dragDx / gridHost.dayW);
                                return Math.max(0, Math.min(root.days.length - 1, raw));
                            }
                            readonly property real effStart: !isNaN(pendingStartH) ? pendingStartH : modelData.start
                            readonly property real effEnd:   !isNaN(pendingEndH)   ? pendingEndH   : modelData.end

                            x: gridHost.gutterW + effDayIndex * gridHost.dayW + 2
                            y: (effStart - root.hoursStart) * root.hourH + dragDy
                            width: gridHost.dayW - 4
                            height: Math.max(18, (effEnd - effStart) * root.hourH - 2)
                            radius: 4
                            color: Theme.withAlpha(Theme.eventColor(modelData.type), 0.18)
                            border.color: Theme.withAlpha(Theme.eventColor(modelData.type), 0.55)
                            border.width: 1
                            z: 5

                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: 3
                                color: Theme.eventColor(weEv.modelData.type)
                                radius: 1
                            }
                            Column {
                                anchors.fill: parent
                                anchors.leftMargin: 8; anchors.rightMargin: 6; anchors.topMargin: 3
                                spacing: 0
                                clip: true
                                Text {
                                    text: Theme.fmtHour(weEv.effStart)
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                }
                                RowLayout {
                                    width: parent.width
                                    spacing: 4
                                    Text {
                                        visible: (weEv.modelData.context || "").length > 0
                                        text: weEv.modelData.context
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: parent.width * 0.5
                                    }
                                    Rectangle {
                                        visible: (weEv.modelData.context || "").length > 0
                                        Layout.preferredWidth: 5; Layout.preferredHeight: 5
                                        radius: 2.5
                                        color: Theme.eventColor(weEv.modelData.type)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: weEv.modelData.title
                                        color: Theme.text
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Move-drag — vertical = time, horizontal = day.
                            MouseArea {
                                id: weMove
                                anchors.fill: parent
                                anchors.topMargin: 6
                                anchors.bottomMargin: 6
                                cursorShape: didDrag ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                property real grabX: 0
                                property real grabY: 0
                                property real baseX: 0
                                property real baseY: 0
                                property bool didDrag: false

                                onPressed: (mouse) => {
                                    grabX = mouse.x; grabY = mouse.y;
                                    baseX = weEv.x; baseY = weEv.y;
                                    didDrag = false;
                                    weEv.dragDx = 0; weEv.dragDy = 0;
                                }
                                onPositionChanged: (mouse) => {
                                    const pt = weMove.mapToItem(gridContent, mouse.x, mouse.y);
                                    const wantX = pt.x - grabX;
                                    const wantY = pt.y - grabY;
                                    const dx = wantX - baseX;
                                    const dy = wantY - baseY;
                                    if (!didDrag && (Math.abs(dx) > 5 || Math.abs(dy) > 5)) didDrag = true;
                                    if (didDrag) {
                                        weEv.dragDx = dx;
                                        weEv.dragDy = dy;
                                    }
                                }
                                onReleased: {
                                    if (didDrag) {
                                        const dur = weEv.modelData.end - weEv.modelData.start;
                                        const newY = baseY + weEv.dragDy;
                                        let ns = root.snapHour(root.yToHour(newY));
                                        ns = Math.max(root.hoursStart, Math.min(ns, root.hoursEnd - dur));
                                        const newDate = root.days[weEv.effDayIndex].date;
                                        AppController.updateEvent(weEv.modelData.id, ns, ns + dur, newDate);
                                    } else {
                                        root.eventClicked(weEv.modelData.id);
                                    }
                                    weEv.dragDx = 0; weEv.dragDy = 0;
                                    didDrag = false;
                                }
                                onCanceled: { weEv.dragDx = 0; weEv.dragDy = 0; didDrag = false; }
                            }

                            // Top resize handle.
                            MouseArea {
                                id: weTop
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: 6
                                cursorShape: Qt.SizeVerCursor
                                property bool resizing: false
                                onPressed: { resizing = true; weEv.pendingStartH = weEv.modelData.start; }
                                onPositionChanged: (mouse) => {
                                    if (!resizing) return;
                                    const pt = weTop.mapToItem(gridContent, mouse.x, mouse.y);
                                    const h = root.snapHour(root.yToHour(pt.y));
                                    const clamped = Math.min(h, weEv.modelData.end - 0.25);
                                    weEv.pendingStartH = Math.max(root.hoursStart, clamped);
                                }
                                onReleased: {
                                    if (!resizing) return;
                                    resizing = false;
                                    const ns = weEv.pendingStartH;
                                    AppController.updateEvent(weEv.modelData.id, ns, weEv.modelData.end, weEv.modelData.date);
                                    weEv.pendingStartH = NaN;
                                }
                                onCanceled: { resizing = false; weEv.pendingStartH = NaN; }
                            }

                            // Bottom resize handle.
                            MouseArea {
                                id: weBot
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 6
                                cursorShape: Qt.SizeVerCursor
                                property bool resizing: false
                                onPressed: { resizing = true; weEv.pendingEndH = weEv.modelData.end; }
                                onPositionChanged: (mouse) => {
                                    if (!resizing) return;
                                    const pt = weBot.mapToItem(gridContent, mouse.x, mouse.y);
                                    const h = root.snapHour(root.yToHour(pt.y));
                                    const clamped = Math.max(h, weEv.modelData.start + 0.25);
                                    weEv.pendingEndH = Math.min(root.hoursEnd, clamped);
                                }
                                onReleased: {
                                    if (!resizing) return;
                                    resizing = false;
                                    const ne = weEv.pendingEndH;
                                    AppController.updateEvent(weEv.modelData.id, weEv.modelData.start, ne, weEv.modelData.date);
                                    weEv.pendingEndH = NaN;
                                }
                                onCanceled: { resizing = false; weEv.pendingEndH = NaN; }
                            }
                        }
                    }
                }
            }
        }
    }

    // Empty-week hint — shown only when the week has no tasks and no events, so
    // the grid does not read as blank. Non-interactive.
    Text {
        anchors.centerIn: parent
        width: parent.width - 64
        visible: root.weekEmpty
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: I18n.t("week.noEvents")
        color: Theme.textDim
        font.pixelSize: 12
    }
}
