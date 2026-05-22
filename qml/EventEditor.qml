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
                contextField.text = m.data(idx, Qt.UserRole + 10) || "";
                break;
            }
        }
        open();
    }

    function parseHour(s) {
        if (!s) return 0;
        const r = AppController.parseDateTime(s, new Date());
        if (r && r.ok && r.hasTime && r.start) {
            return r.start.getHours() + r.start.getMinutes() / 60.0;
        }
        const parts = s.split(":");
        const h = parseInt(parts[0]); const m = parseInt(parts[1] || "0");
        if (isNaN(h)) return 0;
        return h + (isNaN(m) ? 0 : m / 60.0);
    }

    // If `s` resolves to a range expression (e.g. "14-15", "с 14 до 15"), return
    // [startHour, endHour]. Otherwise null.
    function parseHourRange(s) {
        if (!s) return null;
        const r = AppController.parseDateTime(s, new Date());
        if (r && r.ok && r.hasTime && r.start && r.end && r.end.getTime() > 0) {
            return [r.start.getHours() + r.start.getMinutes() / 60.0,
                    r.end.getHours()   + r.end.getMinutes()   / 60.0];
        }
        return null;
    }

    function _formatHour(h) {
        const hh = Math.floor(h);
        const mm = Math.round((h - hh) * 60);
        return String(hh).padStart(2, "0") + ":" + String(mm).padStart(2, "0");
    }

    function _maybeExpandRange(field, otherField) {
        const r = root.parseHourRange(field.text);
        if (r && otherField) {
            field.text = root._formatHour(r[0]);
            otherField.text = root._formatHour(r[1]);
        }
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
            text: I18n.t("editor.label.eventTitle")
            color: Theme.text
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18; text: I18n.t("common.title").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
        }
        TextField {
            id: titleField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
        }

        GridLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            columns: 2; columnSpacing: 10; rowSpacing: 4

            Text {
                text: I18n.t("editor.label.eventType").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            Text {
                text: I18n.t("editor.label.attendees").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }

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

            Text {
                text: I18n.t("editor.label.start").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            Text {
                text: I18n.t("editor.label.end").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }

            TextField {
                id: startField
                Layout.fillWidth: true
                font.family: Theme.fontMono
                placeholderText: I18n.t("editor.ph.timeRange")
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
                onEditingFinished: root._maybeExpandRange(startField, endField)
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

        // Free-form context label — rendered before the event title in the
        // calendar so the same profile can mean different things per event
        // (sprint name, feature, on-call rotation, …).
        ColumnLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            spacing: 4
            Text {
                text: I18n.t("editor.label.context").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            TextField {
                id: contextField
                Layout.fillWidth: true
                placeholderText: "LTE handover · sprint-12 · on-call …"
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
                placeholderTextColor: Theme.textDim
                selectByMouse: true
            }
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.topMargin: 8; Layout.bottomMargin: 16
            spacing: 8
            PillButton {
                text: I18n.t("common.delete"); danger: true; onClicked: { AppController.deleteEvent(root.eventId); root.close(); }
            }
            Item { Layout.fillWidth: true }
            PillButton {
                text: I18n.t("common.cancel"); onClicked: root.close()
            }
            PillButton {
                text: I18n.t("editor.btn.save"); primary: true
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
                        context: contextField.text
                    };
                    AppController.saveEvent(d);
                    root.close();
                }
            }
        }
    }
}
