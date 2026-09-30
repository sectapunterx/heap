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
import "Segments.js" as Seg
import "Search.js" as Search

Item {
    id: root

    // Wired by Main.qml (mirrors WeekView).
    property string searchText: ""
    property var prioritiesFilter: ({})
    property bool showArchived: false
    signal taskClicked(string id)
    // The occurrence, not just its id: a repeating event is stored once, so
    // every occurrence of a series carries the master's id and only the
    // occurrence map says which date was clicked.
    signal eventClicked(string id, var occurrence)

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
        // Clauses filter structurally, leftover words stay a substring test.
        if (!Search.accepts(AppController, root.searchText, root.taskRev + ":" + AppController.today, t)) return false;
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
        // C++ hands over only the tasks due or scheduled inside the grid, with
        // their cell already worked out: reading nine roles of every task and
        // scanning 42 cells per task is what made opening Month take seconds
        // on a large profile. A task planned for a day (scheduledAt) shows on
        // it too, not only one with a deadline there.
        const last = cells[n - 1].date;
        const list = AppController.calendarTasks(start, last, root.showArchived);
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            if (!root.passesFilter(t)) continue;
            if (t.dueDay >= 0 && t.dueDay < n) cells[t.dueDay].tasks.push(t);
            if (t.schedDay >= 0 && t.schedDay < n && t.schedDay !== t.dueDay)
                cells[t.schedDay].tasks.push(Object.assign({ scheduled: true }, t));
        }
        // The expansion, not the rows: a repeating event is stored once, and
        // a month is the view most likely to be showing a whole series at
        // once. A multi-day event is listed on every day it covers, which is
        // what a month grid is for — found by arithmetic, not by testing every
        // occurrence against every cell.
        const occ = AppController.eventOccurrences(cells[0].date, last);
        const first = Date.UTC(start.getFullYear(), start.getMonth(), start.getDate());
        const dayOf = (d) => Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - first) / 86400000);
        for (let i = 0; i < occ.length; i++) {
            const e = occ[i];
            if (!e.date || !e.date.getFullYear) continue;
            const a = Math.max(0, dayOf(e.date));
            const endD = (e.endDate && e.endDate.getFullYear) ? e.endDate : e.date;
            const b = Math.min(n - 1, dayOf(endD));
            for (let k = a; k <= b; k++) cells[k].events.push(e);
        }
        const priRank = { P0: 0, P1: 1, P2: 2, P3: 3 };
        // Events in time order, all-day first: the 16:00 meeting used to be
        // the one shown and the 09:00 and 12:00 ones hidden behind "+2".
        const evKey = (e) => e.allDay ? -1 : e.start;
        for (let k = 0; k < cells.length; k++) {
            cells[k].tasks.sort((a, b) => (priRank[a.priority] ?? 9) - (priRank[b.priority] ?? 9));
            cells[k].events.sort((a, b) => evKey(a) - evKey(b));
        }
        return cells;
    }
    readonly property var cells: buildCells()

    // Day-of-month held across a month step, clamped to the target month's own
    // length. A flat clamp to 28 was safe against JS Date overflow (Feb 31
    // rolls into March) but lossy in one direction only: stepping off the 31st
    // landed on the 28th and every step after that stayed there, so a month of
    // paging left the selection three days adrift.
    function _sameDayNextMonth(d, dir, day) {
        const y = d.getFullYear();
        const m = d.getMonth() + dir;
        const lastDay = new Date(y, m + 1, 0).getDate();   // day 0 = last of month m
        return new Date(y, m, Math.min(day, lastDay));
    }

    // The day of the month paging keeps to. Stepping from the 31st lands on
    // Feb 28 and then must go back to the 31st in March, not stay on the 28th
    // — it is remembered until the selection is moved some other way.
    property int _stickyDay: 0
    property var _steppedTo: null
    function step(dir) {
        const d = AppController.selectedDate;
        if (mode === "month") {
            const kept = root._steppedTo && root.isSameDay(root._steppedTo, d) && root._stickyDay > 0;
            const day = kept ? root._stickyDay : d.getDate();
            root._stickyDay = day;
            const next = _sameDayNextMonth(d, dir, day);
            root._steppedTo = next;
            AppController.selectedDate = next;
        } else {
            AppController.selectedDate = new Date(d.getFullYear(), d.getMonth(), d.getDate() + dir * rows * 7);
        }
    }
    // What ‹ › say they do: a month, or the run of weeks on screen.
    function navLabel(dir) {
        if (root.mode === "month") return I18n.t(dir < 0 ? "month.prev" : "month.next");
        return I18n.t(dir < 0 ? "month.prevWeeks" : "month.nextWeeks");
    }
    function rangeTitle() {
        if (mode === "month")
            return I18n.monthName(anchorDate.getMonth()) + " " + anchorDate.getFullYear();
        const end = new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + rows * 7 - 1);
        return gridStart.toLocaleDateString(I18n.locale, "d MMM")
             + " – " + end.toLocaleDateString(I18n.locale, "d MMM yyyy");
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.sp2xl
        spacing: Theme.spLg

        // ── Header ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spMd

            // prev / next
            Repeater {
                model: [{ g: "‹", d: -1, k: "cal.prev" }, { g: "›", d: 1, k: "cal.next" }]
                delegate: Rectangle {
                    id: navBtn
                    required property var modelData
                    objectName: navBtn.modelData.d < 0 ? "month-prev" : "month-next"
                    width: 28; height: 28; radius: Theme.radiusMd
                    color: navMA.hovered ? Theme.panel3 : Theme.panel2
                    border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: navBtn.modelData.g; color: Theme.text; font.pixelSize: Theme.fsLg }
                    ClickArea {
                        id: navMA
                        label: root.navLabel(navBtn.modelData.d)
                        shortcutId: navBtn.modelData.k
                        onActivated: root.step(navBtn.modelData.d)
                    }
                }
            }

            Text {
                text: root.rangeTitle()
                color: Theme.text; font.pixelSize: Theme.fsLg; font.weight: Font.DemiBold
                Layout.preferredWidth: 240
            }

            Item { Layout.fillWidth: true }

            // Mode toggle: Month | Weeks
            Row {
                spacing: 0
                Repeater {
                    model: [{ id: "month", label: I18n.t("cal.month") }, { id: "weeks", label: I18n.t("cal.weeks") }]
                    delegate: Rectangle {
                        id: modeBtn
                        required property var modelData
                        objectName: "month-mode-" + modelData.id
                        readonly property bool sel: root.mode === modelData.id
                        width: 76; height: 28
                        radius: Theme.radiusMd
                        // A selected segment is tinted, not filled: a filled
                        // accent is the screen's one action ("+ Task").
                        color: sel ? Theme.accentSoft : (modeMA.hovered ? Theme.panel3 : Theme.panel2)
                        border.color: sel ? Theme.withAlpha(Theme.accent, 0.5) : Theme.border; border.width: 1
                        Text { anchors.centerIn: parent; text: parent.modelData.label; color: parent.sel ? Theme.accentStrong : Theme.text; font.pixelSize: Theme.fsSm; font.weight: parent.sel ? Font.DemiBold : Font.Normal }
                        ClickArea {
                            id: modeMA
                            label: modeBtn.modelData.label
                            showTip: false
                            role: Accessible.RadioButton
                            checkable: true
                            checked: modeBtn.sel
                            onActivated: root.mode = modeBtn.modelData.id
                        }
                    }
                }
            }

            // Weeks stepper (custom range) — only in "weeks" mode.
            Row {
                spacing: Theme.spXs
                visible: root.mode === "weeks"
                Rectangle {
                    width: 24; height: 28; radius: Theme.radiusMd; color: decMA.hovered ? Theme.panel3 : Theme.panel2; border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: "−"; color: Theme.text; font.pixelSize: Theme.fsLg }
                    ClickArea { id: decMA; objectName: "month-fewer-weeks"; label: I18n.t("month.fewerWeeks"); onActivated: root.weeksCount = Math.max(1, root.weeksCount - 1) }
                }
                Rectangle {
                    width: 52; height: 28; radius: Theme.radiusMd; color: Theme.panel2; border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: root.weeksCount + " " + I18n.t("cal.wk"); color: Theme.text; font.pixelSize: Theme.fsSm; font.family: Theme.fontMono }
                }
                Rectangle {
                    width: 24; height: 28; radius: Theme.radiusMd; color: incMA.hovered ? Theme.panel3 : Theme.panel2; border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: "+"; color: Theme.text; font.pixelSize: Theme.fsLg }
                    ClickArea { id: incMA; objectName: "month-more-weeks"; label: I18n.t("month.moreWeeks"); onActivated: root.weeksCount = Math.min(8, root.weeksCount + 1) }
                }
            }

            Rectangle {
                width: 60; height: 28; radius: Theme.radiusMd
                color: todayMA.hovered ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                Text { anchors.centerIn: parent; text: I18n.t("common.today"); color: Theme.text; font.pixelSize: Theme.fsSm }
                // AppController.today, like every other "today" in the app —
                // a raw new Date() carries a time-of-day with it.
                ClickArea {
                    id: todayMA
                    objectName: "month-today"
                    label: I18n.t("common.today")
                    shortcutId: "cal.today"
                    onActivated: AppController.selectedDate = AppController.today
                }
            }
        }

        // ── Weekday header ────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spSm
            Repeater {
                model: 7
                delegate: Text {
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    // App language, not the system locale: MonthView used to say
                    // "Mon" while the MiniWeek right next to it said "ПН".
                    text: I18n.dayName(new Date(root.gridStart.getFullYear(),
                                                root.gridStart.getMonth(),
                                                root.gridStart.getDate() + index).getDay())
                    color: Theme.textDim; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold
                }
            }
        }

        // ── Day grid ──────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rowSpacing: Theme.spSm
            columnSpacing: Theme.spSm
            Repeater {
                model: root.cells
                delegate: Rectangle {
                    id: dayCell
                    required property var modelData
                    // Named alias so the nested chip Repeaters (whose own
                    // `modelData` is their int index) can still read the cell.
                    readonly property var cell: modelData
                    readonly property bool _inMonth: root.mode !== "month" || modelData.date.getMonth() === root.anchorMonth
                    readonly property bool _today: root.isSameDay(modelData.date, AppController.today)
                    readonly property bool _sel: root.isSameDay(modelData.date, AppController.selectedDate)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radius
                    color: _inMonth ? Theme.panel : Theme.panel2
                    opacity: _inMonth ? 1.0 : 0.55
                    border.color: _sel ? Theme.accent : (_today ? Theme.accentStrong : Theme.border)
                    border.width: _sel || _today ? 2 : 1
                    // A busy day is clipped to its cell instead of drawing
                    // over the row below.
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AppController.selectedDate = modelData.date
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spXs
                        spacing: Theme.sp2xs

                        // Day number.
                        Text {
                            text: cell.date.getDate()
                            color: _today ? Theme.accentStrong : Theme.text
                            font.pixelSize: Theme.fsSm
                            font.weight: _today ? Font.DemiBold : Font.Normal
                        }

                        // Chips — first few tasks, then events, then overflow.
                        // 20px, like the week's chips: at 15px a row of them
                        // was the hardest target in the app to hit (design
                        // audit DES-17).
                        Repeater {
                            model: Math.min(3, cell.tasks.length)
                            delegate: Rectangle {
                                id: taskChip
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 20
                                radius: Theme.radiusXs
                                color: Theme.withAlpha(root.priColor(cell.tasks[index].priority), 0.22)
                                Row {
                                    anchors.fill: parent; anchors.leftMargin: Theme.spXs; anchors.rightMargin: Theme.spXs; spacing: Theme.spXs
                                    Rectangle { width: 4; height: 4; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: root.priColor(cell.tasks[index].priority) }
                                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 8; elide: Text.ElideRight; text: (cell.tasks[index].scheduled ? "◷ " : "") + cell.tasks[index].title; color: Theme.text; font.pixelSize: Theme.fsXs }
                                }
                                ClickArea {
                                    label: dayCell.cell.tasks[taskChip.index].title
                                    showTip: false
                                    onActivated: root.taskClicked(dayCell.cell.tasks[taskChip.index].id)
                                }
                            }
                        }
                        Repeater {
                            model: Math.min(2, cell.events.length)
                            delegate: Rectangle {
                                id: eventChip
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 20
                                radius: Theme.radiusXs
                                color: Theme.accentSoft
                                Row {
                                    anchors.fill: parent; anchors.leftMargin: Theme.spXs; anchors.rightMargin: Theme.spXs; spacing: Theme.spXs
                                    Rectangle { width: 4; height: 4; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter; width: parent.width - 8; elide: Text.ElideRight
                                        // The time first: a month cell is read as "what is when".
                                        text: (cell.events[index].allDay ? "" : Theme.fmtHour(cell.events[index].start) + " ") + cell.events[index].title
                                        color: Theme.text; font.pixelSize: Theme.fsXs
                                    }
                                }
                                ClickArea {
                                    label: dayCell.cell.events[eventChip.index].title
                                    showTip: false
                                    onActivated: root.eventClicked(dayCell.cell.events[eventChip.index].id, dayCell.cell.events[eventChip.index])
                                }
                            }
                        }
                        // The overflow count was dead text — the only way to
                        // reach what a cell hid was to guess. It selects the
                        // day, same as WeekView's.
                        Text {
                            id: moreText
                            readonly property int _extra: Math.max(0, cell.tasks.length - 3) + Math.max(0, cell.events.length - 2)
                            visible: _extra > 0
                            text: "+" + _extra
                            color: moreMA.hovered ? Theme.accentStrong : Theme.textDim
                            font.pixelSize: Theme.fsXs
                            ClickArea {
                                id: moreMA
                                label: I18n.t("cal.moreOnDay").arg(moreText._extra)
                                onActivated: AppController.selectedDate = dayCell.cell.date
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
}
