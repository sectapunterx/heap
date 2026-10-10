// lowkey — a small themed calendar popup for picking a date (N/X-Dlg-Schedule).
//
// Reused by the task editor (deadline), the event editor (event/sync date),
// "go to date" and the schedule field. Its own grid, as many weeks as the month
// spans: "Октябрь 2026" on the left with ‹ › on the right, today underlined,
// the chosen day in an outlined box.
//
//   DatePickerPopup { id: dp; onPicked: (d) => field.text = fmt(d) }
//   dp.openAt(existingDateOrNull, anchorItem)
//
// `withTimes` (the schedule field's Tab picker, R3-068) adds the day's hours
// on the right — a meeting's hour says "занято" as a fact — and "без времени ·
// весь день"; it answers with pickedAt(value, timed) instead of picked.
//
// Keyboard-first: arrows move the day (a week up/down), PageUp/PageDown a
// month (Shift: a year), Home/End the month's ends, T today, Return picks,
// Esc closes, Delete clears when `clearable`. With times, Tab goes to the
// hours and back; ↑ ↓ there move the hour. `minimumDate`/`maximumDate`
// grey out and refuse what is outside them.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp

Popup {
    id: pop

    // The date the grid opens on / highlights. Emitted value on selection.
    property date selected: new Date()
    signal picked(date value)
    // Offered only where "no date" is a meaningful answer.
    property bool clearable: false
    signal cleared()
    // Invalid (the default) = unbounded.
    property date minimumDate: new Date(NaN)
    property date maximumDate: new Date(NaN)
    // The hours column; the answer is pickedAt.
    property bool withTimes: false
    // The chosen hour, -1 = no time ("без времени").
    property int hour: -1
    signal pickedAt(date value, bool timed)
    property bool _inTimes: false

    function _inRange(d) {
        if (!d || isNaN(d.getTime())) return false;
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const lo = pop.minimumDate, hi = pop.maximumDate;
        if (lo && !isNaN(lo.getTime()) && day < new Date(lo.getFullYear(), lo.getMonth(), lo.getDate()).getTime()) return false;
        if (hi && !isNaN(hi.getTime()) && day > new Date(hi.getFullYear(), hi.getMonth(), hi.getDate()).getTime()) return false;
        return true;
    }
    // Moves the highlighted day and keeps the grid on its month.
    function _moveTo(d) {
        if (!pop._inRange(d)) return;
        pop.selected = d;
        pop._month = d.getMonth();
        pop._year = d.getFullYear();
    }
    function _moveDays(n) {
        const s0 = pop.selected;
        pop._moveTo(new Date(s0.getFullYear(), s0.getMonth(), s0.getDate() + n));
    }
    function _moveMonths(n) {
        const s0 = pop.selected;
        const last = new Date(s0.getFullYear(), s0.getMonth() + n + 1, 0).getDate();
        pop._moveTo(new Date(s0.getFullYear(), s0.getMonth() + n, Math.min(s0.getDate(), last)));
    }
    function _pick(d) {
        if (!pop._inRange(d)) return;
        if (pop.withTimes) {
            const day = new Date(d.getFullYear(), d.getMonth(), d.getDate(), pop.hour >= 0 ? pop.hour : 0, 0, 0);
            pop.pickedAt(day, pop.hour >= 0);
        } else {
            pop.picked(d);
        }
        pop.close();
    }
    function _pickHour(h) {
        pop.hour = h;
        pop._pick(pop.selected);
    }

    // Visible month (0-11) + year — driven by the header nav.
    property int _month: selected.getMonth()
    property int _year: selected.getFullYear()

    // The app's own week start (Settings → Calendar), as a locale: every
    // calendar surface honours Theme.weekStart.
    readonly property var _gridLocale: Qt.locale(Theme.weekStart === "sun" ? "en_US" : "en_GB")
    readonly property int _firstDow: pop._gridLocale.firstDayOfWeek % 7
    // The first cell and how many weeks the month spans (no spare sixth row).
    readonly property date _gridStart: {
        const first = new Date(pop._year, pop._month, 1);
        const back = (first.getDay() - pop._firstDow + 7) % 7;
        return new Date(pop._year, pop._month, 1 - back);
    }
    readonly property int _weeks: {
        const first = new Date(pop._year, pop._month, 1);
        const back = (first.getDay() - pop._firstDow + 7) % 7;
        const days = new Date(pop._year, pop._month + 1, 0).getDate();
        return Math.ceil((back + days) / 7);
    }

    function _sameDay(a, b) {
        return a && b && a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function _step(delta) {
        let m = _month + delta, y = _year;
        if (m < 0) { m = 11; y--; } else if (m > 11) { m = 0; y++; }
        _month = m; _year = y;
    }

    // The hours of the chosen day: the work day, each { hour, busy }.
    readonly property var _hours: pop.withTimes && pop.opened ? pop.hoursOf(pop.selected) : []
    function hoursOf(d) {
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        const occ = AppController.eventOccurrences(day, day);
        const a = Math.max(0, AppController.workdayStart);
        const b = Math.max(a + 1, Math.min(24, AppController.workdayEnd));
        const out = [];
        for (let h = a; h < b; h++) {
            let busy = false;
            for (let i = 0; i < occ.length; i++)
                if (!occ[i].allDay && occ[i].start < h + 1 && occ[i].end > h) busy = true;
            out.push({ hour: h, busy: busy });
        }
        return out;
    }
    function _moveHour(n) {
        const hs = pop._hours;
        if (hs.length === 0) return;
        // -1 ("без времени") sits after the last hour.
        let i = pop.hour < 0 ? hs.length : hs.findIndex(x => x.hour === pop.hour);
        if (i < 0) i = 0;
        i = Math.max(0, Math.min(hs.length, i + n));
        pop.hour = i === hs.length ? -1 : hs[i].hour;
    }

    // Open the popup, seeding the grid from `d` (a JS Date; null → today) and
    // anchoring it under `anchor` when given. `timed`: `d` carries an hour.
    function openAt(d, anchor, timed) {
        selected = (d && !isNaN(d.getTime())) ? d : new Date();
        _month = selected.getMonth();
        _year = selected.getFullYear();
        hour = timed === true ? selected.getHours() : -1;
        _inTimes = false;
        if (anchor !== undefined && anchor !== null)
            parent = anchor;
        open();
        keyCatcher.forceActiveFocus();
    }

    modal: true
    dim: false
    focus: true
    padding: Theme.spLg
    background: PopupSurface {}

    contentItem: RowLayout {
        spacing: Theme.spLg

        ColumnLayout {
            spacing: Theme.spSm
            Layout.alignment: Qt.AlignTop

            // Takes the keys while the popup is open, so the arrows move the
            // day here instead of paging the calendar behind it.
            Item {
                id: keyCatcher
                focus: true
                // On the Tab path with the header and footer buttons, so Tab
                // comes back round to the grid instead of leaving it for good.
                activeFocusOnTab: !pop.withTimes
                Accessible.role: Accessible.Table
                Accessible.name: AppController.humanDate(pop.selected)
                Layout.preferredWidth: 0
                Layout.preferredHeight: 0
                Keys.onPressed: (e) => {
                    const shift = (e.modifiers & Qt.ShiftModifier) !== 0;
                    if (pop.withTimes && pop._inTimes) {
                        switch (e.key) {
                        case Qt.Key_Up: pop._moveHour(-1); break;
                        case Qt.Key_Down: pop._moveHour(1); break;
                        case Qt.Key_Tab:
                        case Qt.Key_Backtab:
                        case Qt.Key_Left: pop._inTimes = false; break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter: pop._pick(pop.selected); break;
                        case Qt.Key_Escape: pop.close(); break;
                        default: return;
                        }
                        e.accepted = true;
                        return;
                    }
                    switch (e.key) {
                    case Qt.Key_Left:  pop._moveDays(-1); break;
                    case Qt.Key_Right: pop._moveDays(1); break;
                    case Qt.Key_Up:    pop._moveDays(-7); break;
                    case Qt.Key_Down:  pop._moveDays(7); break;
                    case Qt.Key_PageUp:   pop._moveMonths(shift ? -12 : -1); break;
                    case Qt.Key_PageDown: pop._moveMonths(shift ? 12 : 1); break;
                    case Qt.Key_Home: {
                        const s0 = pop.selected;
                        pop._moveTo(new Date(s0.getFullYear(), s0.getMonth(), 1));
                        break;
                    }
                    case Qt.Key_End: {
                        const s0 = pop.selected;
                        pop._moveTo(new Date(s0.getFullYear(), s0.getMonth() + 1, 0));
                        break;
                    }
                    case Qt.Key_T: pop._moveTo(new Date()); break;
                    case Qt.Key_Tab:
                    case Qt.Key_Backtab:
                        if (!pop.withTimes) return;
                        pop._inTimes = true;
                        if (pop.hour < 0 && pop._hours.length > 0) pop.hour = pop._hours[0].hour;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter: pop._pick(pop.selected); break;
                    case Qt.Key_Delete:
                    case Qt.Key_Backspace:
                        if (!pop.clearable) return;
                        pop.cleared();
                        pop.close();
                        break;
                    case Qt.Key_Escape: pop.close(); break;
                    default: return;
                    }
                    e.accepted = true;
                }
            }

            // ── Header: Month YYYY ............ ‹ › ──────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spXs
                Text {
                    objectName: "date-picker-title"
                    Layout.fillWidth: true
                    // I18n, not Qt.formatDate: the month name follows the app
                    // language. Capitalised as a title ("Октябрь 2026").
                    text: {
                        const m = I18n.monthName(pop._month);
                        return m.charAt(0).toUpperCase() + m.slice(1) + " " + pop._year;
                    }
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
                    font.weight: Theme.fwHeading
                }
                Repeater {
                    model: [{ id: "prev", step: -1, icon: "chevron-left", key: "PgUp" },
                            { id: "next", step: 1, icon: "chevron-right", key: "PgDown" }]
                    delegate: Rectangle {
                        id: navBtn
                        required property var modelData
                        implicitWidth: Theme.chipH; implicitHeight: Theme.chipH
                        radius: Theme.radiusMd
                        color: navMA.hovered ? Theme.panel3 : "transparent"
                        Icon { anchors.centerIn: parent; name: navBtn.modelData.icon; color: Theme.textMuted }
                        ClickArea {
                            id: navMA
                            objectName: "date-picker-" + navBtn.modelData.id
                            label: I18n.t("month." + navBtn.modelData.id)
                            tip: I18n.t("month." + navBtn.modelData.id) + "  " + navBtn.modelData.key
                            onActivated: pop._step(navBtn.modelData.step)
                        }
                    }
                }
            }

            Row {
                Repeater {
                    model: 7
                    delegate: Text {
                        required property int index
                        width: Theme.px(40)
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.dayName((pop._firstDow + index) % 7)
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsXs
                    }
                }
            }

            Grid {
                id: grid
                objectName: "date-picker-grid"
                columns: 7
                Repeater {
                    model: pop._weeks * 7
                    delegate: Item {
                        id: cell
                        required property int index
                        readonly property date date: new Date(pop._gridStart.getFullYear(), pop._gridStart.getMonth(),
                                                              pop._gridStart.getDate() + cell.index)
                        readonly property bool inMonth: cell.date.getMonth() === pop._month
                        readonly property bool isSel: pop._sameDay(cell.date, pop.selected)
                        readonly property bool isToday: pop._sameDay(cell.date, new Date())
                        readonly property bool allowed: pop._inRange(cell.date)
                        width: Theme.px(40); height: Theme.px(32)
                        opacity: !cell.allowed ? 0.18 : 1
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Math.round(Theme.spXs / 2)
                            radius: Theme.radiusMd
                            color: dayMA.hovered && !cell.isSel ? Theme.panel3 : "transparent"
                            border.width: cell.isSel ? 1 : 0
                            border.color: pop._inTimes ? Theme.borderStrong : Theme.text
                        }
                        Text {
                            anchors.centerIn: parent
                            text: cell.date.getDate()
                            color: cell.inMonth ? Theme.text : Theme.textDim
                            opacity: cell.inMonth ? 1 : 0.6
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsSm
                            font.weight: cell.isSel ? Theme.fwTitle : Theme.fwBody
                        }
                        // Today: a short line under the number.
                        Rectangle {
                            visible: cell.isToday
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: parent.width - Theme.spMd
                            height: Theme.cursorBarH
                            radius: height / 2
                            color: Theme.signalNow
                        }
                        ClickArea {
                            id: dayMA
                            label: AppController.humanDate(cell.date)
                            enabled: cell.allowed
                            onActivated: pop._pick(cell.date)
                        }
                    }
                }
            }

            // ── Footer: Today (and Clear); not beside the hours ─────────
            RowLayout {
                visible: !pop.withTimes
                Layout.fillWidth: true
                spacing: Theme.spSm
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.chipH
                    radius: Theme.radiusMd
                    color: todayMA.hovered ? Theme.panel3 : Theme.panel2
                    border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: I18n.t("common.today"); color: Theme.text; font.family: Theme.fontUi; font.pixelSize: Theme.fsSm }
                    ClickArea {
                        id: todayMA
                        objectName: "date-picker-today"
                        label: I18n.t("common.today")
                        tip: I18n.t("common.today") + "  T"
                        onActivated: pop._pick(new Date())
                    }
                }
                Rectangle {
                    objectName: "date-picker-clear"
                    visible: pop.clearable
                    Layout.fillWidth: true
                    implicitHeight: Theme.chipH
                    radius: Theme.radiusMd
                    color: clearMA.hovered ? Theme.panel3 : Theme.panel2
                    border.color: Theme.border; border.width: 1
                    Text { anchors.centerIn: parent; text: I18n.t("datePicker.clear"); color: Theme.text; font.family: Theme.fontUi; font.pixelSize: Theme.fsSm }
                    ClickArea {
                        id: clearMA
                        label: I18n.t("datePicker.clear")
                        tip: I18n.t("datePicker.clear") + "  Del"
                        onActivated: { pop.cleared(); pop.close(); }
                    }
                }
            }
        }

        // ── The day's hours (withTimes) ─────────────────────────────────
        Rectangle {
            visible: pop.withTimes
            Layout.fillHeight: true
            implicitWidth: 1
            color: Theme.border
        }
        ColumnLayout {
            visible: pop.withTimes
            objectName: "date-picker-hours"
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Theme.px(150)
            Layout.preferredHeight: grid.height + Theme.chipH * 2
            spacing: Theme.spXs
            Text {
                objectName: "date-picker-hours-title"
                Layout.fillWidth: true
                text: I18n.fmtDate(pop.selected, "weekdayDay") + " · " + I18n.t("datePicker.free")
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                elide: Text.ElideRight
            }
            ListView {
                id: hourList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: pop._hours
                currentIndex: pop._hours.findIndex(x => x.hour === pop.hour)
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: slot
                    required property var modelData
                    readonly property bool on: pop.hour === slot.modelData.hour
                    objectName: "date-picker-hour-" + slot.modelData.hour
                    width: hourList.width
                    height: Theme.chipH
                    radius: Theme.radiusMd
                    color: slot.on ? Theme.panel3 : (slotMA.hovered ? Theme.panel2 : "transparent")
                    border.width: slot.on && pop._inTimes ? 1 : 0
                    border.color: Theme.borderStrong
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spSm
                        spacing: Theme.spSm
                        Text {
                            text: AppController.eventHourLabel(slot.modelData.hour)
                            color: slot.modelData.busy ? (Style.urgency ? Theme.info : Theme.textDim) : Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                            font.weight: slot.on ? Theme.fwHeading : Theme.fwBody
                        }
                        Text {
                            visible: slot.modelData.busy
                            text: I18n.t("datePicker.busy")
                            color: Style.urgency ? Theme.info : Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                        }
                    }
                    ClickArea {
                        id: slotMA
                        label: AppController.eventHourLabel(slot.modelData.hour)
                        onActivated: pop._pickHour(slot.modelData.hour)
                    }
                }
            }
            Text {
                id: noTime
                objectName: "date-picker-no-time"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spSm
                text: I18n.t("datePicker.noTime")
                color: pop.hour < 0 && pop._inTimes ? Theme.text : Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                font.weight: pop.hour < 0 && pop._inTimes ? Theme.fwTitle : Theme.fwBody
                ClickArea {
                    label: noTime.text
                    onActivated: pop._pickHour(-1)
                }
            }
        }
    }
}
