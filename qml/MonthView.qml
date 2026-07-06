// heap. — month / custom-range calendar.
//
// A companion to WeekView: instead of an hour grid it lays out whole days as a
// 7-column calendar. Two modes:
//   • "month"  — the 6-week grid of the month containing selectedDate.
//   • "weeks"  — a custom span of N weeks starting at selectedDate's week.
// Each day cell shows its task deadlines + events as compact chips. Clicking a
// day selects it; clicking a chip opens the task / event editor.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Item {
    id: root

    // Wired by Main.qml (mirrors WeekView).
    property string searchText: ""
    property var prioritiesFilter: ({})
    property bool showArchived: false
    signal taskClicked(string id)
    signal eventClicked(string id)

    // View state.
    property string mode: "month"   // "month" | "weeks"
    property int weeksCount: 2       // used in "weeks" mode (1..8)

    // ── Helpers ──────────────────────────────────────────────────────
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
    function priColor(p) {
        return p === "P0" ? Theme.p0 : p === "P1" ? Theme.p1 : p === "P2" ? Theme.p2 : Theme.p3;
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

    // Anchor month + visible range. Declarative: recompute on selectedDate /
    // mode / weeksCount / Theme.weekStart changes.
    readonly property date anchorDate: AppController.selectedDate
    readonly property int rows: mode === "month" ? 6 : Math.max(1, Math.min(8, weeksCount))
    readonly property date gridStart: {
        if (mode === "month")
            return startOfWeek(new Date(anchorDate.getFullYear(), anchorDate.getMonth(), 1));
        return startOfWeek(anchorDate);
    }
    readonly property int anchorMonth: anchorDate.getMonth()

    function buildCells() {
        const _t = root.taskRev; const _e = root.eventRev;   // track for reactivity
        const start = gridStart;
        const n = rows * 7;
        const cells = [];
        for (let i = 0; i < n; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            cells.push({ date: d, tasks: [], events: [] });
        }
        const tm = AppController.tasks;
        for (let i = 0; i < tm.rowCount(); i++) {
            const idx = tm.index(i, 0);
            if (tm.data(idx, Qt.UserRole + 9) && !root.showArchived) continue;  // archived
            const t = {
                id:       tm.data(idx, Qt.UserRole + 1),
                title:    tm.data(idx, Qt.UserRole + 2),
                desc:     tm.data(idx, Qt.UserRole + 3),
                priority: tm.data(idx, Qt.UserRole + 4),
                status:   tm.data(idx, Qt.UserRole + 5),
                deadline: tm.data(idx, Qt.UserRole + 6),
            };
            if (!t.deadline || !t.deadline.getTime) continue;
            if (!root.passesFilter(t)) continue;
            for (let k = 0; k < cells.length; k++)
                if (root.isSameDay(cells[k].date, t.deadline)) { cells[k].tasks.push(t); break; }
        }
        const em = AppController.events;
        for (let i = 0; i < em.rowCount(); i++) {
            const idx = em.index(i, 0);
            const e = {
                id:    em.data(idx, Qt.UserRole + 1),
                title: em.data(idx, Qt.UserRole + 2),
                type:  em.data(idx, Qt.UserRole + 3),
                date:  em.data(idx, Qt.UserRole + 7),
            };
            for (let k = 0; k < cells.length; k++)
                if (root.isSameDay(cells[k].date, e.date)) { cells[k].events.push(e); break; }
        }
        const priRank = { P0: 0, P1: 1, P2: 2, P3: 3 };
        for (let k = 0; k < cells.length; k++)
            cells[k].tasks.sort((a, b) => (priRank[a.priority] || 9) - (priRank[b.priority] || 9));
        return cells;
    }
    readonly property var cells: buildCells()

    function step(dir) {
        const d = AppController.selectedDate;
        if (mode === "month")
            AppController.selectedDate = new Date(d.getFullYear(), d.getMonth() + dir, Math.min(d.getDate(), 28));
        else
            AppController.selectedDate = new Date(d.getFullYear(), d.getMonth(), d.getDate() + dir * rows * 7);
    }
    function rangeTitle() {
        if (mode === "month")
            return Qt.formatDate(anchorDate, "MMMM yyyy");
        const end = new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + rows * 7 - 1);
        return Qt.formatDate(gridStart, "d MMM") + " – " + Qt.formatDate(end, "d MMM yyyy");
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ── Header ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // prev / next
            Repeater {
                model: [{ g: "‹", d: -1 }, { g: "›", d: 1 }]
                delegate: Rectangle {
                    required property var modelData
                    width: 28; height: 28; radius: 6
                    color: navMA.containsMouse ? Theme.panel3 : Theme.panel2
                    border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: parent.modelData.g; color: Theme.text; font.pixelSize: 15 }
                    MouseArea { id: navMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.step(parent.modelData.d) }
                }
            }

            Text {
                text: root.rangeTitle()
                color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold
                Layout.preferredWidth: 240
            }

            Item { Layout.fillWidth: true }

            // Mode toggle: Month | Weeks
            Row {
                spacing: 0
                Repeater {
                    model: [{ id: "month", label: I18n.t("cal.month") }, { id: "weeks", label: I18n.t("cal.weeks") }]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: root.mode === modelData.id
                        width: 76; height: 28
                        radius: 6
                        color: sel ? Theme.accent : (modeMA.containsMouse ? Theme.panel3 : Theme.panel2)
                        border.color: Theme.border; border.width: 1
                        Text { anchors.centerIn: parent; text: parent.modelData.label; color: parent.sel ? "#0b0b0f" : Theme.text; font.pixelSize: 11; font.weight: parent.sel ? Font.DemiBold : Font.Normal }
                        MouseArea { id: modeMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mode = parent.modelData.id }
                    }
                }
            }

            // Weeks stepper (custom range) — only in "weeks" mode.
            Row {
                spacing: 4
                visible: root.mode === "weeks"
                Rectangle {
                    width: 24; height: 28; radius: 6; color: decMA.containsMouse ? Theme.panel3 : Theme.panel2; border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: "−"; color: Theme.text; font.pixelSize: 14 }
                    MouseArea { id: decMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.weeksCount = Math.max(1, root.weeksCount - 1) }
                }
                Rectangle {
                    width: 52; height: 28; radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: root.weeksCount + " " + I18n.t("cal.wk"); color: Theme.text; font.pixelSize: 11; font.family: Theme.fontMono }
                }
                Rectangle {
                    width: 24; height: 28; radius: 6; color: incMA.containsMouse ? Theme.panel3 : Theme.panel2; border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: "+"; color: Theme.text; font.pixelSize: 14 }
                    MouseArea { id: incMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.weeksCount = Math.min(8, root.weeksCount + 1) }
                }
            }

            Rectangle {
                width: 60; height: 28; radius: 6
                color: todayMA.containsMouse ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                Text { anchors.centerIn: parent; text: I18n.t("common.today"); color: Theme.text; font.pixelSize: 11 }
                MouseArea { id: todayMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AppController.selectedDate = new Date() }
            }
        }

        // ── Weekday header ────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: 7
                delegate: Text {
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(new Date(root.gridStart.getFullYear(), root.gridStart.getMonth(), root.gridStart.getDate() + index), "ddd")
                    color: Theme.textDim; font.pixelSize: 10; font.weight: Font.DemiBold
                }
            }
        }

        // ── Day grid ──────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rowSpacing: 6
            columnSpacing: 6
            Repeater {
                model: root.cells
                delegate: Rectangle {
                    required property var modelData
                    // Named alias so the nested chip Repeaters (whose own
                    // `modelData` is their int index) can still read the cell.
                    readonly property var cell: modelData
                    readonly property bool _inMonth: root.mode !== "month" || modelData.date.getMonth() === root.anchorMonth
                    readonly property bool _today: root.isSameDay(modelData.date, new Date())
                    readonly property bool _sel: root.isSameDay(modelData.date, AppController.selectedDate)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: _inMonth ? Theme.panel : Theme.panel2
                    opacity: _inMonth ? 1.0 : 0.55
                    border.color: _sel ? Theme.accent : (_today ? Theme.accentStrong : Theme.border)
                    border.width: _sel || _today ? 2 : 1

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AppController.selectedDate = modelData.date
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 3

                        // Day number.
                        Text {
                            text: cell.date.getDate()
                            color: _today ? Theme.accent : Theme.text
                            font.pixelSize: 11
                            font.weight: _today ? Font.DemiBold : Font.Normal
                        }

                        // Chips — first few tasks, then events, then overflow.
                        Repeater {
                            model: Math.min(3, cell.tasks.length)
                            delegate: Rectangle {
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 15
                                radius: 3
                                color: Theme.withAlpha(root.priColor(cell.tasks[index].priority), 0.22)
                                Row {
                                    anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4; spacing: 4
                                    Rectangle { width: 4; height: 4; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: root.priColor(cell.tasks[index].priority) }
                                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 8; elide: Text.ElideRight; text: cell.tasks[index].title; color: Theme.text; font.pixelSize: 9 }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.taskClicked(cell.tasks[index].id) }
                            }
                        }
                        Repeater {
                            model: Math.min(2, cell.events.length)
                            delegate: Rectangle {
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 15
                                radius: 3
                                color: Theme.accentSoft
                                Row {
                                    anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4; spacing: 4
                                    Rectangle { width: 4; height: 4; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 8; elide: Text.ElideRight; text: cell.events[index].title; color: Theme.text; font.pixelSize: 9 }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.eventClicked(cell.events[index].id) }
                            }
                        }
                        Text {
                            readonly property int _extra: Math.max(0, cell.tasks.length - 3) + Math.max(0, cell.events.length - 2)
                            visible: _extra > 0
                            text: "+" + _extra
                            color: Theme.textDim; font.pixelSize: 9
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
}
