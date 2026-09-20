import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 460
    anchors.centerIn: Overlay.overlay

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

    property string eventId: ""
    // The day this event falls on — editable via the calendar picker below.
    property var pickedDate: AppController.selectedDate
    // The last day it covers. Equal to pickedDate for an ordinary event, which
    // is what saveEvent() stores as "no end date at all".
    property var pickedEndDate: AppController.selectedDate
    property bool allDay: false

    // Recurrence. `masterId` is set on anything the expansion generated, which
    // is what makes an edit a question — this occurrence, this and everything
    // after, or the whole series.
    property string masterId: ""
    property var originalDate: undefined
    readonly property bool repeating: root.masterId.length > 0 || repeatBox.currentIndex > 0

    // The rules offered in the menu. Anything heap did not write — an .ics
    // import with a rule it does not model — lands on "custom", which is shown
    // and kept but not editable here.
    readonly property var repeatRules: ["", "FREQ=DAILY", "FREQ=WEEKLY", "FREQ=WEEKLY;INTERVAL=2", "FREQ=MONTHLY", "FREQ=YEARLY"]
    property string customRule: ""

    function _repeatIndexFor(rule) {
        if (!rule) return 0;
        const i = root.repeatRules.indexOf(rule);
        return i >= 0 ? i : root.repeatRules.length;   // "custom"
    }
    function _ruleFromBox() {
        return repeatBox.currentIndex < root.repeatRules.length
            ? root.repeatRules[repeatBox.currentIndex]
            : root.customRule;
    }

    // Open on a draft that has not been saved yet — a click on an empty slot
    // in the calendar. Saving is what brings the event into existence, so
    // cancelling leaves nothing behind.
    function showForDraft(draft) {
        eventId = draft.id;
        titleField.text = draft.title || "";
        typeBox.currentIndex = Math.max(0, ["standup", "oneone", "sync", "focus"].indexOf(draft.type));
        startField.text = AppController.eventHourLabel(draft.start);
        endField.text = AppController.eventHourLabel(draft.end);
        attField.text = draft.attendees || "";
        root.pickedDate = draft.date;
        root.pickedEndDate = draft.endDate && draft.endDate.getFullYear ? draft.endDate : draft.date;
        root.allDay = !!draft.allDay;
        root.masterId = draft.masterId || "";
        root.originalDate = draft.originalDate;
        root.customRule = draft.rrule || "";
        repeatBox.currentIndex = root._repeatIndexFor(draft.rrule || "");
        contextField.text = draft.context || "";
        open();
        titleField.forceActiveFocus();
        titleField.selectAll();
    }

    // Open on one occurrence of a series. `occ` is a map from
    // AppController.eventOccurrences — it carries the occurrence's own date
    // plus the master it came from.
    function showForOccurrence(occ) {
        eventId = occ.id;
        titleField.text = occ.title || "";
        typeBox.currentIndex = Math.max(0, ["standup", "oneone", "sync", "focus"].indexOf(occ.type));
        startField.text = AppController.eventHourLabel(occ.start);
        endField.text = AppController.eventHourLabel(occ.end);
        attField.text = occ.attendees || "";
        root.pickedDate = occ.date;
        root.pickedEndDate = occ.endDate && occ.endDate.getFullYear ? occ.endDate : occ.date;
        root.allDay = !!occ.allDay;
        root.masterId = occ.masterId || "";
        root.originalDate = occ.occurrenceDate || occ.originalDate;
        contextField.text = occ.context || "";

        // The rule lives on the master, never on a generated instance.
        const master = root.masterId.length > 0 ? AppController.eventSeriesMaster(root.masterId) : null;
        const rule = (master && master.rrule) ? master.rrule : (occ.rrule || "");
        root.customRule = rule;
        repeatBox.currentIndex = root._repeatIndexFor(rule);
        open();
    }

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
                root.pickedDate    = m.data(idx, Qt.UserRole + 7);
                root.allDay        = Boolean(m.data(idx, Qt.UserRole + 11));
                // EndDateRole always reports a usable date: a single-day event
                // reports its own day.
                root.pickedEndDate = m.data(idx, Qt.UserRole + 12);
                root.masterId      = String(m.data(idx, Qt.UserRole + 14) || "");
                root.originalDate  = undefined;
                root.customRule    = String(m.data(idx, Qt.UserRole + 13) || "");
                repeatBox.currentIndex = root._repeatIndexFor(root.customRule);
                contextField.text  = m.data(idx, Qt.UserRole + 10) || "";
                break;
            }
        }
        open();
    }

    // Free-typed time → hours since midnight, always inside the day. "99:00"
    // and "-3" are things a text field accepts; the saved range is clamped in
    // C++ too (heap::cal::clampHours), but an out-of-range value must not be
    // what the editor shows back either.
    function parseHour(s) {
        if (!s) return 0;
        const r = AppController.parseDateTime(s, new Date());
        if (r && r.ok && r.hasTime && r.start) {
            return r.start.getHours() + r.start.getMinutes() / 60.0;
        }
        const parts = s.split(":");
        const h = parseInt(parts[0]); const m = parseInt(parts[1] || "0");
        if (isNaN(h)) return 0;
        return Math.max(0, Math.min(24, h + (isNaN(m) ? 0 : m / 60.0)));
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

    // How many days the event covers beyond its first, from the two pickers.
    function _spanDays() {
        const a = root.pickedDate, b = root.pickedEndDate;
        if (!a || !a.getFullYear || !b || !b.getFullYear) return 0;
        const d = Math.round((Date.UTC(b.getFullYear(), b.getMonth(), b.getDate())
                            - Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) / 86400000);
        return Math.max(0, d);
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

    // The three answers a calendar asks for when a repeating event is touched.
    // Asked only when there is a series to disturb: an ordinary event saves
    // straight through, and so does one that is only now being given a rule.
    function _commit(scope) {
        AppController.saveOccurrence(root._draft(), scope);
        root.close();
    }

    function _commitDelete(scope) {
        AppController.deleteOccurrence(root.masterId, root.originalDate, scope);
        root.close();
    }

    function _draft() {
        const m = AppController.events;
        let curTaskId = "";
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            if (m.data(idx, Qt.UserRole + 1) === root.eventId) {
                curTaskId = m.data(idx, Qt.UserRole + 8);
                break;
            }
        }
        return {
            id: root.eventId,
            title: titleField.text,
            type: ["standup", "oneone", "sync", "focus"][typeBox.currentIndex],
            start: root.parseHour(startField.text),
            end: root.parseHour(endField.text),
            attendees: attField.text,
            date: root.pickedDate,
            endDate: root.pickedEndDate,
            allDay: root.allDay,
            rrule: root._ruleFromBox(),
            masterId: root.masterId,
            originalDate: root.originalDate,
            taskId: curTaskId,
            context: contextField.text
        };
    }

    // Shared by the Save button and the Ctrl+Return shortcut.
    function _save() {
        if (root.masterId.length > 0 && root.originalDate) {
            scopePrompt.ask(false);
            return;
        }
        AppController.saveEvent(root._draft());
        root.close();
    }

    function _delete() {
        if (root.masterId.length > 0 && root.originalDate) {
            scopePrompt.ask(true);
            return;
        }
        AppController.deleteEvent(root.eventId);
        root.close();
    }

    // Keyboard-first — see TaskEditor.
    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: root.opened
        onActivated: root._save()
    }

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    // "This event, this and following, or all events?" — asked whenever an
    // occurrence of a series is saved or deleted, because every wrong answer
    // is a quiet data loss.
    Dialog {
        id: scopePrompt
        objectName: "series-scope"
        property bool deleting: false
        modal: true
        anchors.centerIn: Overlay.overlay
        parent: Overlay.overlay
        padding: 18
        // Explicit, because the contentItem wraps: without a width of its own
        // it sizes from the dialog, which is sizing from it.
        width: 420
        title: scopePrompt.deleting ? I18n.t("repeat.scope.deleteTitle") : I18n.t("repeat.scope.saveTitle")

        function ask(isDelete) {
            scopePrompt.deleting = isDelete;
            scopePrompt.open();
        }

        background: Rectangle {
            radius: 12
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        contentItem: Text {
            text: I18n.t("repeat.scope.body")
            color: Theme.textMuted
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        footer: RowLayout {
            spacing: 8
            Layout.margins: 14
            Item { Layout.fillWidth: true }
            PillButton {
                objectName: "series-scope-this"
                text: I18n.t("repeat.scope.this")
                onClicked: {
                    scopePrompt.close();
                    if (scopePrompt.deleting) root._commitDelete("this"); else root._commit("this");
                }
            }
            PillButton {
                objectName: "series-scope-following"
                text: I18n.t("repeat.scope.following")
                onClicked: {
                    scopePrompt.close();
                    if (scopePrompt.deleting) root._commitDelete("following"); else root._commit("following");
                }
            }
            PillButton {
                objectName: "series-scope-all"
                text: I18n.t("repeat.scope.all")
                primary: true
                onClicked: {
                    scopePrompt.close();
                    if (scopePrompt.deleting) root._commitDelete("all"); else root._commit("all");
                }
            }
        }
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
                model: [I18n.t("event.type.standup"), I18n.t("event.type.oneone"),
                        I18n.t("event.type.sync"), I18n.t("event.type.focus")]
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                contentItem: Text { text: typeBox.displayText; color: Theme.text; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
            }
            TextField {
                id: attField
                Layout.fillWidth: true
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
            }

            // All-day: the hours below have nothing to describe, so they go
            // away rather than sit there accepting input that is discarded.
            Item {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                implicitHeight: allDayRow.implicitHeight
                RowLayout {
                    id: allDayRow
                    anchors.left: parent.left; anchors.right: parent.right
                    spacing: 8
                    Switch {
                        id: allDaySwitch
                        objectName: "event-allday"
                        checked: root.allDay
                        onToggled: root.allDay = checked
                    }
                    Text {
                        text: I18n.t("editor.label.allDay")
                        color: Theme.text
                        font.pixelSize: 12
                        Layout.fillWidth: true
                    }
                }
            }

            Text {
                Layout.columnSpan: 2
                text: I18n.t("editor.label.repeat").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            ComboBox {
                id: repeatBox
                objectName: "event-repeat"
                Layout.columnSpan: 2
                Layout.fillWidth: true
                // One entry past the known rules for anything heap did not
                // write — an imported rule is kept rather than silently
                // rewritten into something simpler.
                model: [I18n.t("repeat.never"), I18n.t("repeat.daily"), I18n.t("repeat.weekly"),
                        I18n.t("repeat.biweekly"), I18n.t("repeat.monthly"), I18n.t("repeat.yearly"),
                        I18n.t("repeat.custom")]
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                contentItem: Text { text: repeatBox.displayText; color: Theme.text; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
            }

            Text {
                visible: !root.allDay
                text: I18n.t("editor.label.start").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            Text {
                visible: !root.allDay
                text: I18n.t("editor.label.end").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }

            TextField {
                id: startField
                visible: !root.allDay
                Layout.fillWidth: true
                font.family: Theme.fontMono
                placeholderText: I18n.t("editor.ph.timeRange")
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
                onEditingFinished: root._maybeExpandRange(startField, endField)
            }
            TextField {
                id: endField
                visible: !root.allDay
                Layout.fillWidth: true
                font.family: Theme.fontMono
                placeholderText: "11:00"
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
            }

            // DATE — the day this event lands on, and the last day it covers.
            Text {
                text: I18n.t("editor.label.date").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            Text {
                text: I18n.t("editor.label.endDate").toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1
            }
            Rectangle {
                id: dateBtn
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 6
                color: dateMA.containsMouse ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: root.pickedDate.toLocaleDateString(I18n.locale, "ddd, d MMM yyyy")
                        color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 12
                    }
                    Rectangle {   // mini calendar glyph
                        width: 15; height: 14; radius: 2; color: "transparent"
                        border.color: Theme.textMuted; border.width: 1
                        Rectangle { width: parent.width; height: 3; color: Theme.textMuted; anchors.top: parent.top }
                    }
                }
                MouseArea {
                    id: dateMA
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: eventDatePicker.openAt(root.pickedDate, dateBtn)
                }
                DatePickerPopup {
                    id: eventDatePicker
                    y: parent.height + 4
                    onPicked: (value) => {
                        // Moving the start moves the whole event and keeps its
                        // length: dragging a three-day trip forward a week
                        // should not turn it into a ten-day one.
                        const span = root._spanDays();
                        root.pickedDate = value;
                        const shifted = new Date(value.getFullYear(), value.getMonth(), value.getDate());
                        shifted.setDate(shifted.getDate() + span);
                        root.pickedEndDate = shifted;
                    }
                }
            }

            Rectangle {
                id: endDateBtn
                objectName: "event-enddate"
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 6
                color: endDateMA.containsMouse ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: root.pickedEndDate && root.pickedEndDate.getFullYear
                            ? root.pickedEndDate.toLocaleDateString(I18n.locale, "ddd, d MMM yyyy")
                            : ""
                        color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 12
                    }
                    Rectangle {
                        width: 15; height: 14; radius: 2; color: "transparent"
                        border.color: Theme.textMuted; border.width: 1
                        Rectangle { width: parent.width; height: 3; color: Theme.textMuted; anchors.top: parent.top }
                    }
                }
                MouseArea {
                    id: endDateMA
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: endDatePicker.openAt(root.pickedEndDate, endDateBtn)
                }
                DatePickerPopup {
                    id: endDatePicker
                    y: parent.height + 4
                    // An end before the start is meaningless; normalizeSpan
                    // would swap them, which reads as the picker ignoring the
                    // click.
                    onPicked: (value) => root.pickedEndDate = (value < root.pickedDate) ? root.pickedDate : value
                }
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
                text: I18n.t("common.delete"); danger: true; onClicked: root._delete()
            }
            Item { Layout.fillWidth: true }
            PillButton {
                text: I18n.t("common.cancel"); onClicked: root.close()
            }
            PillButton {
                text: I18n.t("editor.btn.save"); primary: true
                onClicked: root._save()
            }
        }
    }
}
