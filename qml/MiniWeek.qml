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
        const offset = (dow === 0 ? -6 : 1 - dow);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset);
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
    property var _days: dayList()
    onRefDateChanged: _days = dayList()
    Connections {
        target: AppController.events
        function onRowsInserted() { _days = dayList(); _bumpRev() }
        function onRowsRemoved()  { _days = dayList(); _bumpRev() }
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
                text: {
                    const ru = Qt.locale("ru_RU");
                    return ru.standaloneMonthName(root.refDate.getMonth(), Locale.LongFormat);
                }
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
            ToolButton {
                text: "‹"
                onClicked: AppController.selectedDate = new Date(root.refDate.getFullYear(), root.refDate.getMonth(), root.refDate.getDate() - 7)
                background: Rectangle { color: parent.hovered ? Theme.panel2 : "transparent"; radius: 5 }
                contentItem: Text { text: parent.text; color: Theme.textMuted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                implicitWidth: 24; implicitHeight: 24
            }
            ToolButton {
                text: "•"
                onClicked: AppController.selectedDate = AppController.today
                background: Rectangle { color: parent.hovered ? Theme.panel2 : "transparent"; radius: 5 }
                contentItem: Text { text: parent.text; color: Theme.accentStrong; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                implicitWidth: 18; implicitHeight: 24
            }
            ToolButton {
                text: "›"
                onClicked: AppController.selectedDate = new Date(root.refDate.getFullYear(), root.refDate.getMonth(), root.refDate.getDate() + 7)
                background: Rectangle { color: parent.hovered ? Theme.panel2 : "transparent"; radius: 5 }
                contentItem: Text { text: parent.text; color: Theme.textMuted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                implicitWidth: 24; implicitHeight: 24
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

                    readonly property var dowLabels: ["MO","TU","WE","TH","FR","SA","SU"]

                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            text: parent.parent.dowLabels[parent.parent.index]
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
                            property int _rev: root._eventsRev
                            visible: root.eventCountFor(parent.parent.modelData) > 0
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
}
