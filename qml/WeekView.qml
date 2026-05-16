import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Item {
    id: root

    property string searchText: ""
    property var prioritiesFilter: ({})

    signal taskClicked(string id)
    signal eventClicked(string id)
    signal dayClicked(date d)

    readonly property int hoursStart: AppController.workdayStart
    readonly property int hoursEnd:   AppController.workdayEnd
    readonly property int hourH: 38
    readonly property var dowLabels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    function isSameDay(a, b) {
        if (!a || !b || !a.getFullYear || !b.getFullYear) return false;
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function startOfWeek(d) {
        const dow = d.getDay();
        const offset = (dow === 0 ? -6 : 1 - dow);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset);
    }
    function fmtShort(d) {
        return AppController.shortDate(d);
    }
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

    property var weekStart: startOfWeek(AppController.selectedDate)
    Connections {
        target: AppController
        function onSelectedDateChanged() { root.weekStart = root.startOfWeek(AppController.selectedDate) }
    }

    function buildDays() {
        const start = weekStart;
        const days = [];
        const _t = root.taskRev; const _e = root.eventRev;
        for (let i = 0; i < 7; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            days.push({ date: d, tasks: [], events: [] });
        }
        const tm = AppController.tasks;
        for (let i = 0; i < tm.rowCount(); i++) {
            const idx = tm.index(i, 0);
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
            for (let k = 0; k < 7; k++) {
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
            };
            for (let k = 0; k < 7; k++) {
                if (root.isSameDay(days[k].date, e.date)) { days[k].events.push(e); break; }
            }
        }
        const priRank = { P0: 0, P1: 1, P2: 2, P3: 3 };
        for (let k = 0; k < 7; k++) {
            days[k].tasks.sort((a, b) => (priRank[a.priority] || 9) - (priRank[b.priority] || 9));
        }
        return days;
    }

    property var days: buildDays()
    onWeekStartChanged: days = buildDays()
    onTaskRevChanged: days = buildDays()
    onEventRevChanged: days = buildDays()
    onSearchTextChanged: days = buildDays()
    onPrioritiesFilterChanged: days = buildDays()

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
            readonly property int dayW: Math.max(120, (width - gutterW) / 7)
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
                                    text: root.dowLabels[headCol.index]
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
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 22
                                        radius: 4
                                        color: chipMA.containsMouse ? Theme.panel2 : Theme.panel3
                                        border.color: Theme.withAlpha(Theme.priorityColor(modelData.priority), 0.45)
                                        border.width: 1

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
                                            onClicked: root.taskClicked(modelData.id)
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
                                text: (root.hoursStart + index).toString().padStart(2, "0") + ":00"
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

                            // Events
                            Repeater {
                                model: dayCol.modelData.events
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property var ev: modelData
                                    x: 2
                                    y: (ev.start - root.hoursStart) * root.hourH
                                    width: parent.width - 4
                                    height: Math.max(18, (ev.end - ev.start) * root.hourH - 2)
                                    radius: 4
                                    color: Theme.withAlpha(Theme.eventColor(ev.type), 0.18)
                                    border.color: Theme.withAlpha(Theme.eventColor(ev.type), 0.55)
                                    border.width: 1
                                    Rectangle {
                                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                        width: 3
                                        color: Theme.eventColor(ev.type)
                                        radius: 1
                                    }
                                    Column {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8; anchors.rightMargin: 6; anchors.topMargin: 3
                                        spacing: 0
                                        clip: true
                                        Text {
                                            text: AppController.eventHourLabel(ev.start)
                                            color: Theme.textMuted
                                            font.family: Theme.fontMono
                                            font.pixelSize: 9
                                        }
                                        Text {
                                            width: parent.width
                                            text: ev.title
                                            color: Theme.text
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.eventClicked(ev.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
