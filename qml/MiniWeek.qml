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
        for (let i = 0; i < 7; i++) out.push(I18n.dayNameUpper(i));
        return out;
    }
    function eventCountFor(d) {
        let n = 0;
        for (let i = 0; i < AppController.events.rowCount(); i++) {
            const idx = AppController.events.index(i, 0);
            const ed = AppController.events.data(idx, /*DateRole*/ Qt.UserRole + 1 + 6);
            if (isSameDay(ed, d)) n++;
        }
        return n;
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
    }
    property int _eventsRev: 0
    function _bumpRev() { _eventsRev++ }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            spacing: 4
            Text {
                // Was pinned to ru_RU regardless of the app language, so an
                // English UI still read "сентябрь" — and next to MonthView,
                // which uses the system locale, the two calendars disagreed.
                text: I18n.monthName(root.refDate.getMonth())
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.capitalization: Font.MixedCase
            }
            Text {
                text: root.refDate.getFullYear()
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 11
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
                accent: true
                onClicked: AppController.selectedDate = AppController.today
            }
            NavButton {
                text: "›"
                tip: I18n.t("miniweek.nextWeek")
                onClicked: AppController.selectedDate = new Date(root.refDate.getFullYear(), root.refDate.getMonth(), root.refDate.getDate() + 7)
            }
        }

        RowLayout {
            spacing: 4
            Repeater {
                model: root._days
                Rectangle {
                    required property date modelData
                    required property int index
                    readonly property bool isToday: root.isSameDay(modelData, AppController.today)
                    readonly property bool isSelected: root.isSameDay(modelData, AppController.selectedDate)
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: 8
                    color: isSelected ? Theme.accentSoft : (dayMA.containsMouse ? Theme.panel2 : "transparent")
                    border.color: isSelected ? Theme.accent : "transparent"
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            text: root.dowLabelsByJsDow[parent.parent.modelData.getDay()]
                            color: Theme.textDim
                            font.pixelSize: 10
                            font.letterSpacing: 1
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.parent.width
                        }
                        Text {
                            text: parent.parent.modelData.getDate()
                            color: parent.parent.isToday ? Theme.accentStrong : Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 14
                            font.weight: Font.Medium
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
        property bool accent: false
        signal clicked()
        implicitWidth: 24; implicitHeight: 24
        radius: 5
        color: navMA.containsMouse ? Theme.panel2 : "transparent"
        Text {
            anchors.centerIn: parent
            text: nav.text
            color: nav.accent ? Theme.accentStrong : Theme.textMuted
            font.pixelSize: 13
        }
        MouseArea {
            id: navMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.clicked()
            ToolTip.visible: containsMouse && nav.tip.length > 0
            ToolTip.delay: 400
            ToolTip.text: nav.tip
        }
    }
}
