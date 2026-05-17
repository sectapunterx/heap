import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Item {
    id: root
    readonly property int hoursStart: AppController.workdayStart
    readonly property int hoursEnd:   AppController.workdayEnd

    signal eventClicked(string id)

    property date now: new Date()
    Timer { interval: 60000; repeat: true; running: true; onTriggered: root.now = new Date() }

    // Reactive event count for the selected day; refreshed on every
    // events-model mutation so the "N events" header stays in sync.
    property int _eventsToday: 0
    function _recountEventsToday() {
        const d = AppController.selectedDate;
        if (!d || !d.getFullYear) { _eventsToday = 0; return; }
        let n = 0;
        for (let i = 0; i < AppController.events.rowCount(); i++) {
            const ed = AppController.events.data(AppController.events.index(i,0), Qt.UserRole + 7);
            if (root.isSameDay(ed, d)) n++;
        }
        _eventsToday = n;
    }
    Connections {
        target: AppController.events
        function onRowsInserted() { root._recountEventsToday() }
        function onRowsRemoved()  { root._recountEventsToday() }
        function onDataChanged()  { root._recountEventsToday() }
        function onModelReset()   { root._recountEventsToday() }
    }
    Connections {
        target: AppController
        function onSelectedDateChanged() { root._recountEventsToday() }
    }
    Component.onCompleted: _recountEventsToday()

    function isSameDay(a, b) {
        if (!a || !b || !a.getFullYear || !b.getFullYear) return false;
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                color: Theme.panel
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 1; color: Theme.border
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    Column {
                        Text {
                            text: AppController.humanDate(AppController.selectedDate)
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.capitalization: Font.MixedCase
                        }
                        Text {
                            text: {
                                const d = AppController.selectedDate;
                                if (!d || !d.getFullYear) return "";
                                const y = d.getFullYear();
                                const m = (d.getMonth()+1).toString().padStart(2,"0");
                                const dd = d.getDate().toString().padStart(2,"0");
                                const n = root._eventsToday;
                                return y + "-" + m + "-" + dd + " · " + n + " event" + (n === 1 ? "" : "s");
                            }
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Click empty slot → создать"
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
            }

            ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                Item {
                    id: grid
                    width: scroll.availableWidth
                    implicitHeight: (root.hoursEnd - root.hoursStart) * Theme.hourH + 8

                    readonly property int labelW: 44
                    readonly property int marginX: 14

                    Repeater {
                        model: root.hoursEnd - root.hoursStart
                        Item {
                            required property int index
                            x: grid.marginX
                            y: index * Theme.hourH
                            width: grid.width - grid.marginX * 2
                            height: Theme.hourH

                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: 1; color: Theme.border
                            }
                            Text {
                                x: 0; y: 2
                                width: grid.labelW - 8
                                horizontalAlignment: Text.AlignRight
                                text: (root.hoursStart + parent.index).toString().padStart(2,"0") + ":00"
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                            }
                            Rectangle {
                                x: grid.labelW; y: parent.height / 2
                                width: parent.width - grid.labelW
                                height: 1
                                color: Theme.border
                                opacity: 0.4
                            }
                            MouseArea {
                                x: grid.labelW; y: 0
                                width: parent.width - grid.labelW; height: parent.height
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const h = root.hoursStart + parent.index;
                                    const draft = AppController.newEventDraft(h, AppController.selectedDate);
                                    AppController.saveEvent(draft);
                                }
                            }
                        }
                    }

                    Item {
                        id: eventsLayer
                        x: grid.marginX + grid.labelW + 4
                        y: 0
                        width: grid.width - (grid.marginX * 2) - grid.labelW - 8
                        height: (root.hoursEnd - root.hoursStart) * Theme.hourH

                        Repeater {
                            model: AppController.events
                            Rectangle {
                                id: evRect
                                required property string id
                                required property string title
                                required property string type
                                required property real start
                                required property real end
                                required property string attendees
                                required property var date
                                required property string taskId
                                required property string profileId

                                // Resolve once per event change so the dot reflects rename / recolor.
                                readonly property var profileInfo: profileId.length > 0
                                    ? AppController.profileById(profileId)
                                    : null

                                visible: root.isSameDay(date, AppController.selectedDate)
                                x: 0
                                y: (start - root.hoursStart) * Theme.hourH
                                width: parent.width
                                height: Math.max(20, (end - start) * Theme.hourH - 2)
                                radius: 6
                                color: Theme.withAlpha(Theme.eventColor(type), 0.16)

                                Rectangle {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: 3
                                    color: Theme.eventColor(evRect.type)
                                    radius: 1
                                }

                                // Feature/profile color dot (top-right).
                                Rectangle {
                                    visible: evRect.profileInfo !== null
                                    anchors.top: parent.top; anchors.right: parent.right
                                    anchors.topMargin: 6; anchors.rightMargin: 6
                                    width: 8; height: 8; radius: 4
                                    color: evRect.profileInfo ? evRect.profileInfo.color : Theme.accent
                                    border.color: Theme.bg
                                    border.width: 1
                                }

                                Column {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 20
                                    anchors.topMargin: 6; anchors.bottomMargin: 6
                                    spacing: 2
                                    clip: true
                                    Text {
                                        width: parent.width
                                        text: evRect.title + (evRect.taskId ? "  " + evRect.taskId : "")
                                        color: Theme.text
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: AppController.eventHourLabel(evRect.start) + " – " + AppController.eventHourLabel(evRect.end)
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        visible: evRect.attendees.length > 0 && evRect.height > 50
                                        text: "· " + evRect.attendees
                                        color: Theme.textMuted
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                    Text {
                                        visible: evRect.profileInfo !== null && evRect.height > 70
                                        text: evRect.profileInfo ? evRect.profileInfo.name : ""
                                        color: evRect.profileInfo ? evRect.profileInfo.color : Theme.textDim
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.eventClicked(evRect.id)
                                }
                            }
                        }

                        // Now line
                        Rectangle {
                            visible: root.isSameDay(root.now, AppController.selectedDate)
                                     && (root.now.getHours() + root.now.getMinutes()/60) >= root.hoursStart
                                     && (root.now.getHours() + root.now.getMinutes()/60) <= root.hoursEnd
                            x: -8
                            width: parent.width + 8
                            y: ((root.now.getHours() + root.now.getMinutes()/60) - root.hoursStart) * Theme.hourH
                            height: 2
                            color: Theme.p0
                            z: 3
                            Rectangle {
                                x: -3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10; height: 10; radius: 5; color: Theme.p0
                            }
                        }
                    }
                }
            }
        }
    }
}
