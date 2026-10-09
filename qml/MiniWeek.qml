import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    implicitHeight: col.implicitHeight + 24

    property date refDate: AppController.selectedDate

    function isoFor(d) {
        const y = d.getFullYear(); const m = (d.getMonth()+1).toString().padStart(2,"0"); const dd = d.getDate().toString().padStart(2,"0");
        return y + "-" + m + "-" + dd;
    }
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

    // Indexed by JS day-of-week (0=Sun..6=Sat), from the app language.
    readonly property var dowLabelsByJsDow: {
        const out = [];
        for (let i = 0; i < 7; i++) out.push(I18n.dayName(i));
        return out;
    }
    // How many occurrences touch `d`. The stored rows were counted before, so
    // a daily standup put a dot on its first day only and a multi-day trip on
    // the day it started.
    function eventCountFor(d) {
        const _r = root._eventsRev;
        if (!d || !d.getFullYear) return 0;
        const occ = AppController.eventOccurrences(d, d);
        return occ.length;
    }
    function dayList() {
        const start = startOfWeek(refDate);
        const out = [];
        for (let i = 0; i < 7; i++) out.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
        return out;
    }
    // Declarative — re-evaluates when refDate or Theme.weekStart change.
    readonly property var _days: dayList()
    Connections {
        target: AppController.events
        function onRowsInserted() { _bumpRev() }
        function onRowsRemoved()  { _bumpRev() }
        function onDataChanged()  { _bumpRev() }
        function onModelReset()   { _bumpRev() }
    }
    property int _eventsRev: 0
    function _bumpRev() { _eventsRev++ }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spXl
        spacing: Theme.spMd

        RowLayout {
            spacing: Theme.spXs
            Text {
                // Was pinned to ru_RU regardless of the app language, so an
                // English UI still read "сентябрь" — and next to MonthView,
                // which uses the system locale, the two calendars disagreed.
                text: I18n.monthName(root.refDate.getMonth())
                color: Theme.text
                font.pixelSize: Theme.fsMd
                font.weight: Theme.fwTitle
                font.capitalization: Font.MixedCase
            }
            Text {
                text: root.refDate.getFullYear()
                color: Theme.textDim
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsSm
            }
            Item { Layout.fillWidth: true }
            NavButton {
                text: "‹"
                tip: I18n.t("miniweek.prevWeek")
                onClicked: AppController.selectedDate = new Date(root.refDate.getFullYear(), root.refDate.getMonth(), root.refDate.getDate() - 7)
            }
            NavButton {
                text: "•"
                tip: I18n.t("common.today")
                shortcutId: "cal.today"
                accent: true
                onClicked: AppController.selectedDate = AppController.today
            }
            NavButton {
                text: "›"
                tip: I18n.t("miniweek.nextWeek")
                onClicked: AppController.selectedDate = new Date(root.refDate.getFullYear(), root.refDate.getMonth(), root.refDate.getDate() + 7)
            }
        }

        // One Tab stop for the whole strip: ←/→ move a day, PgUp/PgDn a week,
        // Home jumps to today. It was mouse-only.
        Item {
            id: daysBox
            objectName: "miniweek-days"
            Layout.fillWidth: true
            implicitHeight: daysRow.implicitHeight
            activeFocusOnTab: true
            Accessible.role: Accessible.List
            Accessible.name: AppController.humanDate(AppController.selectedDate)
            function shift(days) {
                const d = AppController.selectedDate;
                AppController.selectedDate = new Date(d.getFullYear(), d.getMonth(), d.getDate() + days);
            }
            Keys.onLeftPressed: shift(-1)
            Keys.onRightPressed: shift(1)
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_PageUp) { shift(-7); event.accepted = true; }
                else if (event.key === Qt.Key_PageDown) { shift(7); event.accepted = true; }
                else if (event.key === Qt.Key_Home) { AppController.selectedDate = AppController.today; event.accepted = true; }
            }
            FocusRing { radius: Theme.radius + 3 }
        RowLayout {
            id: daysRow
            anchors.fill: parent
            spacing: Theme.spXs
            Repeater {
                model: root._days
                Rectangle {
                    required property date modelData
                    required property int index
                    readonly property bool isToday: root.isSameDay(modelData, AppController.today)
                    readonly property bool isSelected: root.isSameDay(modelData, AppController.selectedDate)
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: Theme.radius
                    color: isSelected ? Theme.accentSoft : (dayMA.containsMouse ? Theme.panel2 : "transparent")
                    border.color: isSelected ? Theme.accent : "transparent"
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            text: root.dowLabelsByJsDow[parent.parent.modelData.getDay()]
                            color: Theme.textDim
                            font.pixelSize: Theme.fsSm
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.parent.width
                        }
                        Text {
                            text: parent.parent.modelData.getDate()
                            color: parent.parent.isToday ? Theme.accentStrong : Theme.text
                            font.family: Theme.fontUi
                            font.features: Theme.tabularNums
                            font.pixelSize: Theme.fsLg
                            font.weight: Theme.fwTitle
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.parent.width
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 4; height: 4; radius: 2
                            // _eventsRev has to be read inside the binding —
                            // declaring it as a property next to it (as before)
                            // creates no dependency, so the dot never refreshed
                            // when an event was added or removed.
                            visible: {
                                root._eventsRev;
                                return root.eventCountFor(parent.parent.modelData) > 0;
                            }
                            color: Theme.accent
                            opacity: 0.85
                        }
                    }

                    MouseArea {
                        id: dayMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AppController.selectedDate = parent.modelData
                    }
                }
            }
        }
        }
    }

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1; color: Theme.border
    }

    // Week nav. All three are 24x24 — "today" used to be 18px wide, the
    // smallest target in the app — and all three now say what they do.
    component NavButton: Rectangle {
        id: nav
        property string text: ""
        property string tip: ""
        // A catalogue shortcut the tooltip names, as bound now.
        property string shortcutId: ""
        readonly property string _keys: nav.shortcutId.length > 0 ? AppController.shortcutText(nav.shortcutId) : ""
        property bool accent: false
        signal clicked()
        implicitWidth: 24; implicitHeight: 24
        radius: Theme.radiusSm
        color: navMA.containsMouse ? Theme.panel2 : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: nav.tip
        Keys.onSpacePressed: nav.clicked()
        Keys.onReturnPressed: nav.clicked()
        Keys.onEnterPressed: nav.clicked()
        Accessible.onPressAction: nav.clicked()
        FocusRing {}
        Text {
            anchors.centerIn: parent
            text: nav.text
            color: nav.accent ? Theme.accentStrong : Theme.textMuted
            font.pixelSize: Theme.fsMd
        }
        MouseArea {
            id: navMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.clicked()
            ToolTip.visible: (containsMouse || nav.activeFocus) && nav.tip.length > 0
            ToolTip.delay: 400
            ToolTip.text: nav._keys.length > 0 ? nav.tip + "  " + nav._keys : nav.tip
        }
    }
}
