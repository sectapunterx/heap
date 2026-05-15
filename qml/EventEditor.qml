import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    width: 460
    anchors.centerIn: Overlay.overlay

    property string eventId: ""

    function showForId(id) {
        eventId = id;
        const m = AppController.events;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            if (m.data(idx, Qt.UserRole + 1) === id) {
                titleField.text   = m.data(idx, Qt.UserRole + 2);
                typeBox.currentIndex = Math.max(0, ["standup","oneone","sync","focus"].indexOf(m.data(idx, Qt.UserRole + 3)));
                startField.text   = AppController.eventHourLabel(m.data(idx, Qt.UserRole + 4));
                endField.text     = AppController.eventHourLabel(m.data(idx, Qt.UserRole + 5));
                attField.text     = m.data(idx, Qt.UserRole + 6);
                break;
            }
        }
        open();
    }

    function parseHour(s) {
        const parts = (s || "").split(":");
        const h = parseInt(parts[0]); const m = parseInt(parts[1] || "0");
        if (isNaN(h)) return 0;
        return h + (isNaN(m) ? 0 : m / 60.0);
    }

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 12
        Item { Layout.preferredHeight: 4 }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: "Событие в календаре"
            color: Theme.text
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Text { Layout.leftMargin: 18; Layout.rightMargin: 18; text: "НАЗВАНИЕ"; color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        TextField {
            id: titleField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
        }

        GridLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            columns: 2; columnSpacing: 10; rowSpacing: 4

            Text { text: "ТИП"; color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
            Text { text: "УЧАСТНИКИ"; color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }

            ComboBox {
                id: typeBox
                Layout.fillWidth: true
                model: ["Daily standup", "1:1", "Team sync", "Focus time"]
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                contentItem: Text { text: typeBox.displayText; color: Theme.text; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
            }
            TextField {
                id: attField
                Layout.fillWidth: true
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
            }

            Text { text: "НАЧАЛО"; color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
            Text { text: "КОНЕЦ"; color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }

            TextField {
                id: startField
                Layout.fillWidth: true
                font.family: Theme.fontMono
                placeholderText: "10:00"
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
            }
            TextField {
                id: endField
                Layout.fillWidth: true
                font.family: Theme.fontMono
                placeholderText: "11:00"
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
            }
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.topMargin: 8; Layout.bottomMargin: 16
            spacing: 8
            PillButton { text: "Удалить"; danger: true; onClicked: { AppController.deleteEvent(root.eventId); root.close(); } }
            Item { Layout.fillWidth: true }
            PillButton { text: "Отмена"; onClicked: root.close() }
            PillButton {
                text: "Сохранить"; primary: true
                onClicked: {
                    const m = AppController.events;
                    let curDate = AppController.selectedDate;
                    let curTaskId = "";
                    for (let i = 0; i < m.rowCount(); i++) {
                        const idx = m.index(i,0);
                        if (m.data(idx, Qt.UserRole + 1) === root.eventId) {
                            curDate = m.data(idx, Qt.UserRole + 7);
                            curTaskId = m.data(idx, Qt.UserRole + 8);
                            break;
                        }
                    }
                    const d = {
                        id: root.eventId,
                        title: titleField.text,
                        type: ["standup","oneone","sync","focus"][typeBox.currentIndex],
                        start: root.parseHour(startField.text),
                        end: root.parseHour(endField.text),
                        attendees: attField.text,
                        date: curDate,
                        taskId: curTaskId
                    };
                    AppController.saveEvent(d);
                    root.close();
                }
            }
        }
    }
}
