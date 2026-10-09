import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

// The calendar's range in the Tasks header (APP-264): ‹ 5 – 11 October ›
// for a week, the day or the month at the other zooms, and "Today" when the
// range has left it. [ / ] and 0 do the same from the keyboard.
Row {
    id: root
    objectName: "calendar-nav"

    // "day" | "week" | "month"
    property string zoom: "week"
    spacing: Theme.spSm

    function _startOfWeek(d: var): var {
        const dow = d.getDay();
        const offset = Theme.weekStart === "sun" ? -dow : (dow === 0 ? -6 : 1 - dow);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset);
    }
    function _same(a: var, b: var): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    readonly property date _sel: AppController.selectedDate
    readonly property string label: {
        const d = root._sel;
        if (root.zoom === "day") return I18n.fmtDate(d, "longWeekday");
        if (root.zoom === "month") {
            const m = I18n.monthName(d.getMonth());
            return m.charAt(0).toUpperCase() + m.slice(1) + " " + d.getFullYear();
        }
        const a = root._startOfWeek(d);
        const b = new Date(a.getFullYear(), a.getMonth(), a.getDate() + 6);
        if (a.getMonth() !== b.getMonth()) return I18n.fmtDate(a, "longDay") + " – " + I18n.fmtDate(b, "longDay");
        return I18n.lang === "ru" ? a.getDate() + " – " + I18n.fmtDate(b, "longDay")
                                  : I18n.fmtDate(a, "longDay") + " – " + b.getDate();
    }
    // Whether today is inside what is on screen.
    readonly property bool showsToday: {
        const t = AppController.today;
        const d = root._sel;
        if (root.zoom === "day") return root._same(d, t);
        if (root.zoom === "month") return d.getMonth() === t.getMonth() && d.getFullYear() === t.getFullYear();
        return root._same(root._startOfWeek(d), root._startOfWeek(t));
    }

    // One day, one week, or one month, keeping the day of the month where
    // the next month has it (31 Jan → 28 Feb).
    function step(dir) {
        const d = root._sel;
        if (root.zoom === "month") {
            const first = new Date(d.getFullYear(), d.getMonth() + dir, 1);
            const last = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
            AppController.selectedDate = new Date(first.getFullYear(), first.getMonth(), Math.min(d.getDate(), last));
            return;
        }
        const by = root.zoom === "day" ? 1 : 7;
        AppController.selectedDate = new Date(d.getFullYear(), d.getMonth(), d.getDate() + by * dir);
    }

    PillButton {
        objectName: "calendar-today"
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.showsToday
        text: I18n.t("common.today")
        ToolTip.visible: hovered
        ToolTip.delay: 500
        ToolTip.text: I18n.t("common.today") + "  0"
        onClicked: AppController.selectedDate = AppController.today
    }
    // ‹ › (DG-044): boxed in bold (H2-Calendar), bare in quiet (Q-Calendar).
    component NavArrow: Rectangle {
        id: arrow
        property int dir: -1
        property string zoom: "week"
        signal stepped(int dir)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.fills ? Theme.px(28) : Theme.px(18)
        height: Theme.px(28)
        radius: Theme.radiusMd
        color: Style.fills && arrowCA.hovered ? Theme.panel2 : "transparent"
        border.width: Style.fills ? 1 : 0
        border.color: Theme.buttonLine
        Icon {
            anchors.centerIn: parent
            name: arrow.dir < 0 ? "chevron-left" : "chevron-right"
            size: Theme.px(12)
            color: arrowCA.hovered ? Theme.text : (Style.fills ? Theme.textMuted : Theme.textDim)
        }
        ClickArea {
            id: arrowCA
            label: I18n.t((arrow.dir < 0 ? "calnav.prev." : "calnav.next.") + arrow.zoom)
            onActivated: arrow.stepped(arrow.dir)
        }
    }
    NavArrow {
        objectName: "calendar-prev"
        dir: -1
        zoom: root.zoom
        onStepped: (dir) => root.step(dir)
    }
    Text {
        objectName: "calendar-range"
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Style.fills ? Theme.text : Theme.textMuted
        font.family: Theme.fontUi
        font.features: Theme.tabularNums
        font.pixelSize: Theme.fsMd
        font.weight: Style.fills ? Theme.fwHeading : Theme.fwBody
    }
    NavArrow {
        objectName: "calendar-next"
        dir: 1
        zoom: root.zoom
        onStepped: (dir) => root.step(dir)
    }
}
