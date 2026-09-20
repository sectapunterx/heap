// heap. — a small themed calendar popup for picking a single date.
//
// Reused by the task editor (deadline), the event editor (event/sync date) and
// the custom-range calendar view. Wraps Qt Quick Controls' MonthGrid but paints
// its own delegate so it matches the app palette.
//
//   DatePickerPopup { id: dp; onPicked: (d) => field.text = fmt(d) }
//   // open it anchored to a button:
//   dp.openAt(existingDateOrNull, anchorItem)

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp

Popup {
    id: pop

    // The date the grid opens on / highlights. Emitted value on selection.
    property date selected: new Date()
    signal picked(date value)

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
    }

    modal: true
    dim: true
    focus: true
    padding: 10
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
    background: Rectangle {
        color: Theme.panel
        border.color: Theme.border
        border.width: 1
        radius: 10
    }

    contentItem: ColumnLayout {
        spacing: 6

        // ── Header: ‹  Month YYYY  › ──────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                width: 24; height: 24; radius: 6
                color: prevMA.containsMouse ? Theme.panel3 : "transparent"
                Text { anchors.centerIn: parent; text: "‹"; color: Theme.text; font.pixelSize: 15 }
                MouseArea { id: prevMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pop._step(-1) }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                // I18n, not Qt.formatDate: the month name follows the app
                // language the same way MonthView's title does, rather than
                // whatever the host is set to.
                text: I18n.monthName(pop._month) + " " + pop._year
                color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold
            }
            Rectangle {
                width: 24; height: 24; radius: 6
                color: nextMA.containsMouse ? Theme.panel3 : "transparent"
                Text { anchors.centerIn: parent; text: "›"; color: Theme.text; font.pixelSize: 15 }
                MouseArea { id: nextMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pop._step(1) }
            }
        }

        DayOfWeekRow {
            Layout.fillWidth: true
            locale: pop._gridLocale
            delegate: Text {
                required property var model
                horizontalAlignment: Text.AlignHCenter
                // model.day is the JS day-of-week index the column stands for.
                text: I18n.dayName(model.day)
                color: Theme.textDim; font.pixelSize: 9; font.weight: Font.DemiBold
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
                width: 32; height: 26; radius: 6
                color: _isSel ? Theme.accent
                     : model.today ? Theme.accentSoft
                     : (dayMA.containsMouse ? Theme.panel3 : "transparent")
                opacity: _inMonth ? 1.0 : 0.32
                Text {
                    anchors.centerIn: parent
                    text: model.day
                    color: parent._isSel ? "#0b0b0f" : Theme.text
                    font.pixelSize: 11
                    font.weight: parent._isSel ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: dayMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { pop.picked(model.date); pop.close(); }
                }
            }
        }

        // ── Footer: Today ─────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 26
            radius: 6
            color: todayMA.containsMouse ? Theme.panel3 : Theme.panel2
            border.color: Theme.border; border.width: 1
            Text { anchors.centerIn: parent; text: I18n.t("common.today"); color: Theme.text; font.pixelSize: 11 }
            MouseArea {
                id: todayMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { pop.picked(new Date()); pop.close(); }
            }
        }
    }
}
