// heap. — a small themed calendar popup for picking a single date.
//
// Reused by the task editor (deadline), the event editor (event/sync date) and
// the custom-range calendar view. Wraps Qt Quick Controls' MonthGrid but paints
// its own delegate so it matches the app palette.
//
//   DatePickerPopup { id: dp; onPicked: (d) => field.text = fmt(d) }
//   // open it anchored to a button:
//   dp.openAt(existingDateOrNull, anchorItem)
//
// Keyboard-first: arrows move the day (a week up/down), PageUp/PageDown a
// month (Shift: a year), Home/End the month's ends, T today, Return picks,
// Esc closes, Delete clears when `clearable`. `minimumDate`/`maximumDate`
// grey out and refuse what is outside them.

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
        pop.picked(d);
        pop.close();
    }

    // Visible month (0-11) + year — driven by the header nav.
    property int _month: selected.getMonth()
    property int _year: selected.getFullYear()

    // MonthGrid orders its columns by the locale's firstDayOfWeek, so the app's
    // own Settings → Calendar week start has to be expressed as one. Every
    // other calendar surface honours Theme.weekStart; this popup used to follow
    // the host locale instead, so the same week could start on a different day
    // here than in the view it was opened from.
    readonly property var _gridLocale: Qt.locale(Theme.weekStart === "sun" ? "en_US" : "en_GB")

    function _sameDay(a, b) {
        return a && b && a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function _step(delta) {
        let m = _month + delta, y = _year;
        if (m < 0) { m = 11; y--; } else if (m > 11) { m = 0; y++; }
        _month = m; _year = y;
    }
    // Open the popup, seeding the grid from `d` (a JS Date; null → today) and
    // anchoring it under `anchor` when given.
    function openAt(d, anchor) {
        selected = (d && !isNaN(d.getTime())) ? d : new Date();
        _month = selected.getMonth();
        _year = selected.getFullYear();
        if (anchor !== undefined && anchor !== null)
            parent = anchor;
        open();
        keyCatcher.forceActiveFocus();
    }

    modal: true
    dim: true
    focus: true
    padding: Theme.spLg
    Overlay.modal: Rectangle { color: Theme.withAlpha(Theme.scrim, 0.35) }
    background: Rectangle {
        color: Theme.panel
        border.color: Theme.border
        border.width: 1
        radius: Theme.radiusLg
    }

    contentItem: ColumnLayout {
        spacing: Theme.spSm

        // Takes the keys while the popup is open, so the arrows move the
        // day here instead of paging the calendar behind it.
        Item {
            id: keyCatcher
            focus: true
            // On the Tab path with the header and footer buttons, so Tab
            // comes back round to the grid instead of leaving it for good.
            activeFocusOnTab: true
            Accessible.role: Accessible.Table
            Accessible.name: AppController.humanDate(pop.selected)
            Layout.preferredWidth: 0
            Layout.preferredHeight: 0
            Keys.onPressed: (e) => {
                const shift = (e.modifiers & Qt.ShiftModifier) !== 0;
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

        // ── Header: ‹  Month YYYY  › ──────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spSm
            Rectangle {
                width: 24; height: 24; radius: Theme.radiusMd
                color: prevMA.hovered ? Theme.panel3 : "transparent"
                Text { anchors.centerIn: parent; text: "‹"; color: Theme.text; font.pixelSize: Theme.fsLg }
                ClickArea {
                    id: prevMA
                    objectName: "date-picker-prev"
                    label: I18n.t("month.prev")
                    tip: I18n.t("month.prev") + "  PgUp"
                    onActivated: pop._step(-1)
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                // I18n, not Qt.formatDate: the month name follows the app
                // language the same way MonthView's title does, rather than
                // whatever the host is set to.
                text: I18n.monthName(pop._month) + " " + pop._year
                color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Font.DemiBold
            }
            Rectangle {
                width: 24; height: 24; radius: Theme.radiusMd
                color: nextMA.hovered ? Theme.panel3 : "transparent"
                Text { anchors.centerIn: parent; text: "›"; color: Theme.text; font.pixelSize: Theme.fsLg }
                ClickArea {
                    id: nextMA
                    objectName: "date-picker-next"
                    label: I18n.t("month.next")
                    tip: I18n.t("month.next") + "  PgDown"
                    onActivated: pop._step(1)
                }
            }
        }

        DayOfWeekRow {
            Layout.fillWidth: true
            locale: pop._gridLocale
            delegate: Text {
                horizontalAlignment: Text.AlignHCenter
                // model.day is the JS day-of-week index this column stands for.
                // Read as a context property rather than a `required property`:
                // declaring one in this inline delegate makes qmlcachegen 6.9.1
                // — the version CI builds with — segfault while AOT-compiling
                // every file that instantiates this popup.
                text: I18n.dayName(model.day)
                color: Theme.textDim; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold
            }
        }

        MonthGrid {
            id: grid
            Layout.preferredWidth: 232
            Layout.preferredHeight: 168
            locale: pop._gridLocale
            month: pop._month
            year: pop._year
            delegate: Rectangle {
                required property var model
                readonly property bool _inMonth: model.month === pop._month
                readonly property bool _isSel: pop._sameDay(model.date, pop.selected)
                readonly property bool _allowed: pop._inRange(model.date)
                width: 32; height: 26; radius: Theme.radiusMd
                color: _isSel ? Theme.accent
                     : model.today ? Theme.accentSoft
                     : (dayMA.containsMouse ? Theme.panel3 : "transparent")
                opacity: !_allowed ? 0.18 : (_inMonth ? 1.0 : 0.32)
                Text {
                    anchors.centerIn: parent
                    text: model.day
                    color: parent._isSel ? Theme.textOnAccent : Theme.text
                    font.pixelSize: Theme.fsSm
                    font.weight: parent._isSel ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: dayMA; anchors.fill: parent; hoverEnabled: true
                    cursorShape: parent._allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: pop._pick(model.date)
                }
            }
        }

        // ── Footer: Today (and Clear) ─────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spSm
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 26
            radius: Theme.radiusMd
            color: todayMA.hovered ? Theme.panel3 : Theme.panel2
            border.color: Theme.border; border.width: 1
            Text { anchors.centerIn: parent; text: I18n.t("common.today"); color: Theme.text; font.pixelSize: Theme.fsSm }
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
            implicitHeight: 26
            radius: Theme.radiusMd
            color: clearMA.hovered ? Theme.panel3 : Theme.panel2
            border.color: Theme.border; border.width: 1
            Text { anchors.centerIn: parent; text: I18n.t("datePicker.clear"); color: Theme.text; font.pixelSize: Theme.fsSm }
            ClickArea {
                id: clearMA
                label: I18n.t("datePicker.clear")
                tip: I18n.t("datePicker.clear") + "  Del"
                onActivated: { pop.cleared(); pop.close(); }
            }
        }
        }
    }
}
