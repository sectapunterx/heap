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

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

    property string eventId: ""
    property string _profileId: ""    // tracks the event's feature attribution

    // ProfileBox model: "(без фичи)" + every existing profile.
    function _rebuildProfileBoxModel() {
        const list = AppController.profiles;
        const items = ["(без фичи)"];
        for (let i = 0; i < list.length; i++) items.push(list[i].name);
        profileBox.model = items;
    }
    function _profileIndexById(id) {
        if (!id || id.length === 0) return 0;
        const list = AppController.profiles;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return i + 1;
        return 0;
    }
    function _profileIdByIndex(idx) {
        if (idx <= 0) return "";
        const list = AppController.profiles;
        return (idx - 1 < list.length) ? list[idx - 1].id : "";
    }

    function showForId(id) {
        eventId = id;
        _rebuildProfileBoxModel();
        const m = AppController.events;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            if (m.data(idx, Qt.UserRole + 1) === id) {
                titleField.text   = m.data(idx, Qt.UserRole + 2);
                typeBox.currentIndex = Math.max(0, ["standup","oneone","sync","focus"].indexOf(m.data(idx, Qt.UserRole + 3)));
                startField.text   = AppController.eventHourLabel(m.data(idx, Qt.UserRole + 4));
                endField.text     = AppController.eventHourLabel(m.data(idx, Qt.UserRole + 5));
                attField.text     = m.data(idx, Qt.UserRole + 6);
                _profileId        = m.data(idx, Qt.UserRole + 9) || "";
                profileBox.currentIndex = _profileIndexById(_profileId);
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

        // Optional feature/profile attribution — controls which profile's
        // color dot the calendar paints next to this event.
        ColumnLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            spacing: 4
            Text { text: "ФИЧА (необязательно)"; color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
            ComboBox {
                id: profileBox
                Layout.fillWidth: true
                model: ["(без фичи)"]
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                contentItem: RowLayout {
                    spacing: 6
                    Rectangle {
                        Layout.leftMargin: 10
                        width: 8; height: 8; radius: 4
                        visible: profileBox.currentIndex > 0
                        color: {
                            const id = root._profileIdByIndex(profileBox.currentIndex);
                            const p = id ? AppController.profileById(id) : null;
                            return (p && p.color) ? p.color : Theme.accent;
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: profileBox.displayText
                        color: Theme.text
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: profileBox.currentIndex > 0 ? 0 : 10
                    }
                }
                onActivated: root._profileId = root._profileIdByIndex(currentIndex)
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
                        taskId: curTaskId,
                        profileId: root._profileId
                    };
                    AppController.saveEvent(d);
                    root.close();
                }
            }
        }
    }
}
