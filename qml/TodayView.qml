import QtQuick
import QtQuick.Layouts
import TodoCpp

// Today (heap 2, APP-258): the day the right panel used to hold, as a
// screen of its own. A small "Today" over the date, then the day.
Item {
    id: root
    objectName: "today-view"

    signal eventClicked(string id, var occurrence)
    signal createRequested(real startHour, real endHour, var day)
    signal taskClicked(string id)

    function focusView() { root.forceActiveFocus(); }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.sp2xl
        anchors.rightMargin: Theme.sp2xl
        anchors.topMargin: Theme.sp2xl
        spacing: Theme.spXs

        Text {
            objectName: "today-label"
            text: I18n.t("sidebar.today")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }
        Text {
            objectName: "today-date"
            text: {
                const s = I18n.fmtDate(AppController.today, "longWeekday");
                return s.charAt(0).toUpperCase() + s.slice(1);
            }
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fs2xl
            font.weight: Theme.fwHeading
            Accessible.role: Accessible.Heading
            Accessible.name: text
            Layout.bottomMargin: Theme.spXl
        }
        DayCalendar {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: Theme.px(720)
            onEventClicked: (id, occurrence) => root.eventClicked(id, occurrence)
            onCreateRequested: (startHour, endHour, day) => root.createRequested(startHour, endHour, day)
            onTaskClicked: (id) => root.taskClicked(id)
        }
    }
}
