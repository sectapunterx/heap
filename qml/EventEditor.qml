pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp
import "Attendees.js" as Attendees
import "EventRule.js" as EventRule

// A meeting (X-Dlg-Event, DG-120): the same panel on the right as the task
// document, saving on its own; Esc goes back.
//
//   ▢ встреча · повторяется                            сохранено
//   1:1 с Олегом
//   Когда         пт, 9 окт · 11:00–11:30
//   Повтор        каждую неделю по пятницам
//   Участники     Олег Т.
//   Звонок        zoom.us/j/8812… · подключиться
//   Напоминание   за 5 мин
//   Задача        + связать с задачей
//   Профиль       все профили
//   ┌ Повестка, ссылки… ┐
//   Удалить…                               изменения сохраняются сами
//
// A row's value is edited where it is drawn. "Когда" reads what is typed the
// way the quick input does ("пт 14:00", "завтра 10–11", "весь день").
// For a series, moving it, changing its rule or deleting asks "this one,
// this and following, or all" (SeriesScopeDialog); the words of a series —
// title, agenda, people, call, reminder — belong to the whole series.
// A meeting from a subscribed calendar is shown read-only, with its link.
FocusScope {
    id: root
    objectName: "event-panel"

    // ── what is open ──
    property string eventId: ""
    readonly property bool opened: root.eventId.length > 0
    visible: root.opened
    // Not saved yet (an old caller's draft): saving is what makes it.
    property bool _isDraft: false
    property string masterId: ""
    property var originalDate: undefined
    readonly property string sourceCalendar: root.opened
        ? AppController.subscriptionNameOf(root.eventId.length > 0 ? root.eventId : root.masterId) : ""
    readonly property bool readOnly: root.sourceCalendar.length > 0

    signal closed(string eventId)
    signal taskRequested(string taskId)

    // ── the meeting's fields ──
    property string type: "none"
    property var pickedDate: AppController.selectedDate
    property var pickedEndDate: AppController.selectedDate
    property real startHour: 9
    property real endHour: 10
    property bool allDay: false
    property string rule: ""
    property string taskId: ""
    property string profileId: ""
    property string context: ""
    property string location: ""
    property int reminderMinutes: -1
    property var _stored: ({})
    readonly property bool repeating: root.masterId.length > 0 || root.rule.length > 0
    // An occurrence the series generated (not a stored override of it).
    readonly property bool _generated: root.masterId.length > 0 && !!root.originalDate
                                       && !root._storedHere(root.eventId)

    function _storedHere(id) {
        const e = AppController.eventById(id);
        return !!e && String(e["id"] || "").length > 0;
    }
    readonly property var types: ["none", "standup", "oneone", "sync", "focus"]
    readonly property var repeatKinds: ["never", "daily", "weekdays", "weekly", "biweekly", "monthly", "yearly", "custom"]
    readonly property var reminderChoices: [-1, -2, 0, 5, 10, 15, 30, 60]
    readonly property int defaultLead: {
        try {
            const s = JSON.parse(AppController.appSettingsJson || "{}");
            const n = s.notifications && s.notifications.meetingLead;
            return (n === undefined || n === null) ? 5 : Number(n);
        } catch (e) { return 5; }
    }

    property bool _loading: false
    property bool _savedShown: true
    property string _error: ""
    property bool _customOpen: false

    // ── opening and closing ──
    function _load(src) {
        root._loading = true;
        root._stored = src;
        titleField.text = src.title || "";
        root.type = root.types.indexOf(src.type) >= 0 ? src.type : "none";
        root.pickedDate = src.date;
        root.pickedEndDate = src.endDate && src.endDate.getFullYear ? src.endDate : src.date;
        root.startHour = Number(src.start) || 0;
        root.endHour = Number(src.end) || 0;
        root.allDay = !!src.allDay;
        attField.text = src.attendees || "";
        callField.text = src.url || "";
        root.location = src.location || "";
        agenda.text = src.notes || "";
        root.taskId = src.taskId || "";
        root.profileId = src.profileId || "";
        root.context = src.context || "";
        root.reminderMinutes = src.reminderMinutes === undefined || src.reminderMinutes === null ? -1 : Number(src.reminderMinutes);
        root._error = "";
        root._customOpen = false;
        root._savedShown = true;
        root._loading = false;
    }
    function _opened() {
        root.forceActiveFocus();
        titleField.forceActiveFocus();
        if (root._isDraft) titleField.selectAll();
        else titleField.cursorPosition = titleField.length;
    }
    // Main's way back into the panel after a menu or a popup closes: the
    // title, where Esc closes the panel (IDIOT-DOC-7).
    function takeFocus() {
        titleField.forceActiveFocus();
    }
    function _switchTo() { if (root.opened) root.flush(); }

    // An old caller's draft: shown, and made on the first save.
    function showForDraft(draft) {
        root._switchTo();
        root._isDraft = true;
        root.masterId = draft.masterId || "";
        root.originalDate = draft.originalDate;
        root.rule = draft.rrule || "";
        root._load(draft);
        root.eventId = draft.id;
        root._opened();
    }
    // One occurrence of a series: `occ` from AppController.eventOccurrences.
    function showForOccurrence(occ) {
        root._switchTo();
        root._isDraft = false;
        root.masterId = occ.masterId || "";
        root.originalDate = occ.occurrenceDate || occ.originalDate;
        const master = root.masterId.length > 0 ? AppController.eventSeriesMaster(root.masterId) : null;
        root.rule = (master && master.rrule) ? master.rrule : (occ.rrule || "");
        root._load(occ);
        root.eventId = occ.id;
        root._opened();
    }
    function showForId(id) {
        const ev = AppController.eventById(id);
        if (!ev || !ev.id) return;
        root._switchTo();
        root._isDraft = false;
        root.masterId = String(ev.masterId || "");
        root.originalDate = ev.masterId ? ev.originalDate : undefined;
        root.rule = String(ev.rrule || "");
        root._load(ev);
        root.eventId = id;
        root._opened();
    }
    function close() {
        if (!root.opened) return;
        root.flush();
        const id = root.eventId;
        root.eventId = "";
        root._isDraft = false;
        attSuggest.dismiss();
        root.closed(id);
    }
    // What is typed goes in now (a switch, a close, a quit).
    function flush() {
        if (saveTimer.running) { saveTimer.stop(); root._save("text"); }
    }

    // ── reading what is typed ──
    // Free-typed time → hours since midnight, or NaN when it is not one.
    // "930" and "9.30" are 09:30, "9" is 09:00, past 24 is the day's end.
    function parseHourStrict(s) {
        const t = String(s || "").trim();
        if (t.length === 0) return NaN;
        let m = t.match(/^(\d{1,2})(\d{2})$/);
        if (m) return root._hm(parseInt(m[1]), parseInt(m[2]));
        m = t.match(/^(\d{1,2})[.,:](\d{2})$/);
        if (m) return root._hm(parseInt(m[1]), parseInt(m[2]));
        m = t.match(/^(\d{1,2})$/);
        if (m) return root._hm(parseInt(m[1]), 0);
        const r = AppController.parseDateTime(t, new Date());
        if (r && r.ok && r.hasTime && r.start) return r.start.getHours() + r.start.getMinutes() / 60.0;
        return NaN;
    }
    function _hm(h, m) {
        if (isNaN(h) || isNaN(m) || m > 59) return NaN;
        return Math.max(0, Math.min(24, h + m / 60.0));
    }
    // An end of 00:00 on the event's own day is its end, 24:00 (TIME-22).
    function parseEndStrict(s) {
        const e = root.parseHourStrict(s);
        return (e === 0 && root._spanDays() === 0) ? 24 : e;
    }
    function parseHour(s) {
        const h = root.parseHourStrict(s);
        return isNaN(h) ? 0 : h;
    }
    // "14-15", "с 14 до 15" → [start, end], else null.
    function parseHourRange(s) {
        if (!s) return null;
        const r = AppController.parseDateTime(s, new Date());
        if (r && r.ok && r.hasTime && r.start && r.end && r.end.getTime() > 0)
            return [r.start.getHours() + r.start.getMinutes() / 60.0, r.end.getHours() + r.end.getMinutes() / 60.0];
        return null;
    }
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

    // "пт, 9 окт · 11:00–11:30", "пт, 9 окт · весь день", "9 – 11 окт".
    function whenLabel() {
        if (!root.pickedDate || !root.pickedDate.getFullYear) return "";
        let s = I18n.fmtDate(root.pickedDate, "weekdayDay");
        if (root._spanDays() > 0) s += " – " + I18n.fmtDate(root.pickedEndDate, "weekdayDay");
        if (root.allDay) return s + " · " + I18n.t("event.allDay");
        return s + " · " + AppController.eventHourLabel(root.startHour) + "–" + AppController.eventHourLabel(root.endHour);
    }
    // What was typed into "Когда". Returns "" or why it was not understood.
    function applyWhen(text) {
        let t = String(text || "").trim();
        if (t.length === 0 || t === root.whenLabel()) return "";
        const allDayRe = /(весь день|целый день|all[- ]day)/i;
        const wantsAllDay = allDayRe.test(t);
        t = t.replace(allDayRe, " ").replace(/\s+/g, " ").trim();
        const len = root.endHour - root.startHour;
        let date = root.pickedDate, start = root.startHour, end = root.endHour, allDay = root.allDay;
        if (t.length > 0) {
            // A bare time or range stays on the meeting's own day.
            const ref = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 1);
            const r = AppController.parseDateTime(t, ref);
            if (!r || !r.ok || !r.start) return I18n.t("event.when.unknown");
            date = new Date(r.start.getFullYear(), r.start.getMonth(), r.start.getDate());
            if (r.hasTime) {
                allDay = false;
                start = r.start.getHours() + r.start.getMinutes() / 60;
                const e = r.end && r.end.getTime && r.end.getTime() > r.start.getTime()
                          ? r.end.getHours() + r.end.getMinutes() / 60 : start + Math.max(0.25, len);
                end = e <= start ? Math.min(24, start + Math.max(0.25, len)) : e;
            }
        }
        if (wantsAllDay) allDay = true;
        const span = root._spanDays();
        root.pickedDate = date;
        root.pickedEndDate = new Date(date.getFullYear(), date.getMonth(), date.getDate() + span);
        root.startHour = start;
        root.endHour = Math.min(24, end);
        root.allDay = allDay;
        root._save("time");
        return "";
    }

    function repeatKindOf(rule) {
        if (!rule) return "never";
        const p = EventRule.parts(rule);
        const n = p.INTERVAL ? parseInt(p.INTERVAL) : 1;
        if (p.COUNT || p.UNTIL || p.BYMONTHDAY || p.BYSETPOS) return "custom";
        if (p.FREQ === "DAILY" && n === 1 && !p.BYDAY) return "daily";
        if (p.FREQ === "WEEKLY" && n === 1 && p.BYDAY === "MO,TU,WE,TH,FR") return "weekdays";
        if (p.FREQ === "WEEKLY" && !p.BYDAY) return n === 1 ? "weekly" : n === 2 ? "biweekly" : "custom";
        if (p.FREQ === "MONTHLY" && n === 1 && !p.BYDAY) return "monthly";
        if (p.FREQ === "YEARLY" && n === 1 && !p.BYDAY) return "yearly";
        return "custom";
    }
    function ruleFor(kind) {
        switch (kind) {
        case "daily": return "FREQ=DAILY";
        case "weekdays": return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR";
        case "weekly": return "FREQ=WEEKLY";
        case "biweekly": return "FREQ=WEEKLY;INTERVAL=2";
        case "monthly": return "FREQ=MONTHLY";
        case "yearly": return "FREQ=YEARLY";
        }
        return "";
    }
    function setRepeat(kind) {
        if (kind === "custom") { root._customOpen = true; customField.text = root.rule; customField.forceActiveFocus(); return; }
        root._customOpen = false;
        const r = root.ruleFor(kind);
        if (r === root.rule) return;
        root.rule = r;
        root._save("rule");
    }
    function setCustomRule(text) {
        const r = String(text || "").trim().replace(/^RRULE:/i, "");
        if (r.length > 0 && !AppController.isValidRRule(r)) { root._error = I18n.t("editor.err.rule"); return; }
        root._error = "";
        root._customOpen = false;
        if (r === root.rule) return;
        root.rule = r;
        root._save("rule");
    }

    function reminderLabel(v) {
        if (v === -1) return I18n.t("event.reminder.default").arg(root.defaultLead);
        if (v === -2) return I18n.t("event.reminder.none");
        if (v === 0) return I18n.t("event.reminder.atStart");
        return I18n.t("event.reminder.before").arg(v);
    }
    function typeLabel(t) {
        return t === "none" || !t ? String(I18n.t("event.kind.meeting")).toLowerCase() : String(I18n.t("event.type." + t)).toLowerCase();
    }
    function profileName(id) {
        if (!id) return I18n.t("event.profile.all");
        const p = AppController.profileById(id);
        return p && p.name ? p.name : I18n.t("event.profile.all");
    }

    // ── saving ──
    function _cleanAttendees(s) {
        return String(s || "").split(",").map(x => x.trim()).filter(x => x.length > 0).join(", ");
    }
    function _draft() {
        return {
            id: root.eventId,
            title: titleField.text.trim().length > 0 ? titleField.text.trim() : String(root._stored.title || ""),
            type: root.type,
            start: root.startHour,
            end: root.endHour,
            attendees: root._cleanAttendees(attField.text),
            date: root.pickedDate,
            endDate: root.pickedEndDate,
            allDay: root.allDay,
            rrule: root.rule,
            masterId: root.masterId,
            originalDate: root.originalDate,
            taskId: root.taskId,
            profileId: root.profileId,
            context: root.context,
            location: root.location,
            url: callField.text.trim(),
            notes: agenda.text,
            reminderMinutes: root.reminderMinutes
        };
    }
    // `kind`: "text" (the words), "time" (when), "rule" (repeat).
    function _save(kind) {
        if (root._loading || root.readOnly || !root.opened) return;
        saveTimer.stop();
        const d = root._draft();
        if (d.title.length === 0) return;   // nothing is made without a name
        if (root._generated && (kind === "time" || kind === "rule")) {
            const fromText = root._scopeFact();
            scopePrompt.ask(kind === "rule" ? "save" : "move", (scope) => {
                AppController.saveOccurrence(d, scope);
                root._refind(d);
                root._markSaved();
            }, () => root._reload(), fromText);
            return;
        }
        if (root._generated) {
            // The words of a series are the series'.
            AppController.saveOccurrence(d, "all");
        } else if (root.masterId.length > 0 && root.originalDate) {
            AppController.saveOccurrence(d, "this");   // a stored override
        } else {
            AppController.saveEvent(d);
            root._isDraft = false;
        }
        root._markSaved();
    }
    function _markSaved() { root._savedShown = true; }
    // «1:1 с Олегом», пт 11:00 → пт 14:00
    function _scopeFact() {
        const s = root._stored;
        const before = s.date && s.date.getFullYear
            ? I18n.dayName(s.date.getDay()) + " " + AppController.eventHourLabel(Number(s.start) || 0) : "";
        const after = I18n.dayName(root.pickedDate.getDay()) + " " + AppController.eventHourLabel(root.startHour);
        return I18n.t("event.scope.fact").arg(titleField.text.trim()).arg(before).arg(after);
    }
    // After a scoped save the occurrence on screen may be a new override or
    // a new series: found again by its day, name and hour.
    function _refind(d) {
        const day = d.date;
        const occ = AppController.eventOccurrences(day, day);
        let best = null;
        for (let i = 0; i < occ.length; i++) {
            if (String(occ[i].title) !== d.title) continue;
            if (!best || Math.abs(Number(occ[i].start) - d.start) < Math.abs(Number(best.start) - d.start)) best = occ[i];
        }
        if (!best) return;
        root.eventId = best.id;
        root.masterId = best.masterId || "";
        root.originalDate = best.masterId ? (best.occurrenceDate || best.originalDate) : undefined;
        const master = root.masterId.length > 0 ? AppController.eventSeriesMaster(root.masterId) : null;
        root.rule = master && master.rrule ? master.rrule : String(best.rrule || "");
        root._stored = best;
    }
    // The scope question was cancelled: the fields go back to what is stored.
    function _reload() {
        const s = root._stored;
        root._loading = true;
        root.pickedDate = s.date;
        root.pickedEndDate = s.endDate && s.endDate.getFullYear ? s.endDate : s.date;
        root.startHour = Number(s.start) || 0;
        root.endHour = Number(s.end) || 0;
        root.allDay = !!s.allDay;
        const master = root.masterId.length > 0 ? AppController.eventSeriesMaster(root.masterId) : null;
        root.rule = master && master.rrule ? master.rrule : String(s.rrule || "");
        root._loading = false;
    }
    function _textEdited() {
        if (root._loading) return;
        root._savedShown = false;
        saveTimer.restart();
    }
    function deleteEvent() {
        if (root.readOnly || root._isDraft) { root.eventId = ""; root.closed(""); return; }
        if (root.masterId.length > 0 && root.originalDate) {
            scopePrompt.ask("delete", (scope) => {
                AppController.deleteOccurrence(root.masterId, root.originalDate, scope);
                const id = root.eventId;
                root.eventId = "";
                root.closed(id);
            }, null, "«" + titleField.text.trim() + "»");
            return;
        }
        const id = root.eventId;
        saveTimer.stop();
        AppController.deleteEvent(id);   // undoable, with its toast
        root.eventId = "";
        root.closed(id);
    }

    Timer { id: saveTimer; interval: 700; onTriggered: root._save("text") }
    Connections {
        target: Qt.application
        function onAboutToQuit() { root.flush(); }
    }
    Connections {
        target: AppController
        function onFlushEditorsRequested() { root.flush(); }
    }

    SeriesScopeDialog { id: scopePrompt }
    readonly property alias scopePrompt: scopePrompt

    Keys.onEscapePressed: (e) => {
        if (attSuggest.isOpen) { attSuggest.dismiss(); e.accepted = true; return; }
        root.close();
        e.accepted = true;
    }

    // ── drawing ──
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        Rectangle {
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            width: 1
            color: Theme.border
        }
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = false }

    component RowLabel: Text {
        Layout.preferredWidth: Theme.px(110)
        Layout.alignment: Qt.AlignVCenter
        color: Theme.textMuted
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsSm
    }
    component ValueField: TextField {
        id: vf
        Layout.fillWidth: true
        leftPadding: 0; rightPadding: 0; topPadding: Theme.spXs; bottomPadding: Theme.spXs
        color: Theme.text
        placeholderTextColor: Theme.textMuted
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsMd
        selectByMouse: true
        readOnly: root.readOnly
        background: Item {}
        ContextMenu.menu: TextEditMenu { editor: vf }
    }
    component ValueLink: Text {
        id: vl
        signal activated()
        property bool add: false
        Layout.fillWidth: true
        color: vl.add || linkCA.hovered ? (linkCA.hovered ? Theme.text : Theme.textMuted) : Theme.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsMd
        elide: Text.ElideRight
        ClickArea {
            id: linkCA
            enabled: !root.readOnly
            label: vl.text
            onActivated: vl.activated()
        }
    }
    component FieldRow: ColumnLayout {
        default property alias content: rowLine.data
        Layout.fillWidth: true
        spacing: 0
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
        RowLayout {
            id: rowLine
            Layout.fillWidth: true
            Layout.minimumHeight: Theme.chipH + Theme.spSm
            spacing: Theme.spLg
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: Theme.spXl + 1
        anchors.rightMargin: Theme.spXl
        contentHeight: col.implicitHeight + Theme.sp2xl
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            y: Theme.spXl
            spacing: 0

            // ▢ встреча · повторяется                       сохранено
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spMd
                spacing: Theme.spSm
                // Placeholder until the shared line icon (Icon.qml) lands.
                MeetingIcon { ink: Theme.textMuted }
                Text {
                    id: kindText
                    objectName: "event-kind"
                    text: root.typeLabel(root.type) + (root.repeating ? " · " + I18n.t("event.kind.repeats") : "")
                    color: kindCA.hovered ? Theme.text : Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    ClickArea {
                        id: kindCA
                        enabled: !root.readOnly
                        label: I18n.t("editor.label.eventType")
                        onActivated: typeMenu.popup(kindText, 0, kindText.height)
                    }
                    AppMenu {
                        id: typeMenu
                        Repeater {
                            model: root.types
                            delegate: AppMenuItem {
                                required property string modelData
                                text: root.typeLabel(modelData)
                                marked: root.type === modelData
                                onTriggered: { root.type = modelData; root._save("text"); }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    objectName: "event-saved"
                    text: root.readOnly ? I18n.t("event.readOnlyFrom").arg(root.sourceCalendar)
                        : root._savedShown ? I18n.t("event.saved") : ""
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    elide: Text.ElideRight
                    Layout.maximumWidth: Theme.px(220)
                }
            }

            TextField {
                id: titleField
                objectName: "event-title"
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spMd
                leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: Theme.spXs
                readOnly: root.readOnly
                color: Theme.text
                placeholderText: I18n.t("event.ph.title")
                placeholderTextColor: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fs2xl
                font.weight: Theme.fwScreenTitle
                selectByMouse: true
                background: Item {}
                Accessible.name: I18n.t("common.title")
                ContextMenu.menu: TextEditMenu { editor: titleField }
                onTextChanged: root._textEdited()
                onAccepted: whenField.forceActiveFocus()
            }

            FieldRow {
                RowLabel { text: I18n.t("event.row.when") }
                ValueField {
                    id: whenField
                    objectName: "event-when"
                    Binding on text { when: !whenField.activeFocus; value: root.whenLabel() }
                    Accessible.name: I18n.t("event.row.when")
                    onActiveFocusChanged: if (activeFocus) { whenField.text = root.whenLabel(); whenField.selectAll(); }
                    onAccepted: { root._error = root.applyWhen(whenField.text); if (root._error.length === 0) repeatLink.forceActiveFocus(); }
                    onEditingFinished: if (root._error.length === 0) root._error = root.applyWhen(whenField.text)
                }
            }
            FieldRow {
                RowLabel { text: I18n.t("event.row.repeat") }
                ValueLink {
                    id: repeatLink
                    objectName: "event-repeat"
                    activeFocusOnTab: true
                    text: EventRule.describe(root.rule, root.pickedDate, I18n)
                    onActivated: repeatMenu.popup(repeatLink, 0, repeatLink.height)
                    Keys.onReturnPressed: repeatMenu.popup(repeatLink, 0, repeatLink.height)
                    AppMenu {
                        id: repeatMenu
                        Repeater {
                            model: root.repeatKinds
                            delegate: AppMenuItem {
                                required property string modelData
                                text: I18n.t("repeat." + modelData)
                                marked: root.repeatKindOf(root.rule) === modelData
                                onTriggered: root.setRepeat(modelData)
                            }
                        }
                    }
                }
            }
            // A rule written by hand (an import's BYSETPOS, an end date, a count).
            ValueField {
                id: customField
                objectName: "event-rule-custom"
                visible: root._customOpen
                Layout.leftMargin: Theme.px(110) + Theme.spLg
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsSm
                placeholderText: I18n.t("repeat.custom.ph")
                onAccepted: root.setCustomRule(customField.text)
                Keys.onEscapePressed: (e) => { root._customOpen = false; e.accepted = true; }
            }
            FieldRow {
                RowLabel { text: I18n.t("event.row.people") }
                ValueField {
                    id: attField
                    objectName: "event-attendees"
                    placeholderText: I18n.t("event.ph.people")
                    onTextChanged: { if (attField.activeFocus) attSuggest.refresh(); root._textEdited(); }
                    onCursorPositionChanged: if (attField.activeFocus) attSuggest.refresh()
                    onActiveFocusChanged: attField.activeFocus ? attSuggest.refresh() : attSuggest.dismiss()
                    Keys.onPressed: (e) => {
                        if (!attSuggest.isOpen) return;
                        if (e.key === Qt.Key_Down) { attSuggest.move(+1); e.accepted = true; }
                        else if (e.key === Qt.Key_Up) { attSuggest.move(-1); e.accepted = true; }
                        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Tab)
                                 && !(e.modifiers & Qt.ControlModifier)) {
                            attSuggest.accept();
                            e.accepted = true;
                        }
                    }

                    // People offered for the name under the caret.
                    Popup {
                        id: attSuggest
                        objectName: "event-attendee-suggest"
                        property var items: []
                        property int sel: 0
                        readonly property bool isOpen: attSuggest.visible && attSuggest.items.length > 0
                        y: attField.height + 2
                        width: Math.max(attField.width, 240)
                        height: Math.min(attSuggest.items.length, 6) * Theme.rowH + 4
                        padding: Theme.sp2xs
                        focus: false
                        modal: false
                        closePolicy: Popup.NoAutoClose
                        visible: attSuggest.items.length > 0

                        function refresh() {
                            const tok = Attendees.tokenAt(attField.text, attField.cursorPosition);
                            attSuggest.items = Attendees.suggest(AppController.pingCandidates(), tok.query,
                                                                 Attendees.listed(attField.text, tok.start), 6,
                                                                 (q, n, h) => AppController.personMatchRank(q, n, h));
                            attSuggest.sel = 0;
                        }
                        function dismiss() { attSuggest.items = []; }
                        function move(d) { attSuggest.sel = Math.max(0, Math.min(attSuggest.items.length - 1, attSuggest.sel + d)); }
                        function accept() {
                            if (!attSuggest.isOpen) return;
                            const tok = Attendees.tokenAt(attField.text, attField.cursorPosition);
                            const r = Attendees.apply(attField.text, tok, String(attSuggest.items[attSuggest.sel].name).trim());
                            attField.text = r.text;
                            attField.cursorPosition = r.caret;
                            dismiss();
                        }

                        background: PopupSurface {}
                        contentItem: ListView {
                            clip: true
                            interactive: false
                            model: attSuggest.items
                            delegate: Rectangle {
                                id: sugRow
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: Theme.rowH
                                radius: Theme.radiusSm
                                color: sugRow.index === attSuggest.sel ? Theme.panel3 : (sugMA.hovered ? Theme.panel2 : "transparent")
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                                    spacing: Theme.spMd
                                    Text {
                                        text: sugRow.modelData.name
                                        color: Theme.text; font.pixelSize: Theme.fsSm
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        visible: (sugRow.modelData.role || "").length > 0
                                        text: sugRow.modelData.role || ""
                                        color: Theme.textMuted; font.pixelSize: Theme.fsXs
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 110
                                    }
                                }
                                ClickArea {
                                    id: sugMA
                                    label: sugRow.modelData.name
                                    showTip: false
                                    onActivated: {
                                        attSuggest.sel = sugRow.index;
                                        attSuggest.accept();
                                        attField.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }
                }
            }
            FieldRow {
                RowLabel { text: I18n.t("event.row.call") }
                ValueField {
                    id: callField
                    objectName: "event-call"
                    placeholderText: root.location.length > 0 ? root.location : I18n.t("event.ph.call")
                    onTextChanged: root._textEdited()
                }
                Text {
                    id: joinText
                    objectName: "event-join"
                    visible: callField.text.trim().length > 0
                    text: "· " + I18n.t("event.join").toLowerCase()
                    color: joinCA.hovered ? Theme.text : Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
                    font.underline: joinCA.hovered
                    ClickArea {
                        id: joinCA
                        label: I18n.t("event.join")
                        onActivated: {
                            const u = callField.text.trim();
                            Qt.openUrlExternally(/^[a-z]+:\/\//i.test(u) ? u : "https://" + u);
                        }
                    }
                }
            }
            FieldRow {
                RowLabel { text: I18n.t("event.row.reminder") }
                ValueLink {
                    id: reminderLink
                    objectName: "event-reminder"
                    activeFocusOnTab: true
                    text: root.reminderLabel(root.reminderMinutes)
                    onActivated: reminderMenu.popup(reminderLink, 0, reminderLink.height)
                    Keys.onReturnPressed: reminderMenu.popup(reminderLink, 0, reminderLink.height)
                    AppMenu {
                        id: reminderMenu
                        Repeater {
                            model: root.reminderChoices
                            delegate: AppMenuItem {
                                required property int modelData
                                text: root.reminderLabel(modelData)
                                marked: root.reminderMinutes === modelData
                                onTriggered: { root.reminderMinutes = modelData; root._save("text"); }
                            }
                        }
                    }
                }
            }
            FieldRow {
                RowLabel { text: I18n.t("event.row.task") }
                ValueLink {
                    id: taskLink
                    objectName: "event-task"
                    visible: !taskInput.visible
                    activeFocusOnTab: true
                    readonly property var task: root.taskId.length > 0 ? AppController.taskById(root.taskId) : ({})
                    add: root.taskId.length === 0
                    text: root.taskId.length === 0 ? "+ " + I18n.t("event.task.link")
                        : root.taskId + (taskLink.task && taskLink.task.title ? " " + taskLink.task.title : "")
                    onActivated: {
                        if (root.taskId.length === 0) { taskInput.visible = true; taskInput.forceActiveFocus(); }
                        else taskMenu.popup(taskLink, 0, taskLink.height);
                    }
                    AppMenu {
                        id: taskMenu
                        AppMenuItem { text: I18n.t("event.task.open"); onTriggered: root.taskRequested(root.taskId) }
                        AppMenuItem { text: I18n.t("event.task.unlink"); onTriggered: { root.taskId = ""; root._save("text"); } }
                    }
                }
                ValueField {
                    id: taskInput
                    objectName: "event-task-input"
                    visible: false
                    placeholderText: I18n.t("event.task.ph")
                    onAccepted: {
                        const id = taskInput.text.trim().toUpperCase();
                        const t = AppController.taskById(id);
                        if (!t || !t.id) { root._error = I18n.t("event.task.notFound").arg(taskInput.text.trim()); return; }
                        root._error = "";
                        root.taskId = t.id;
                        taskInput.text = "";
                        taskInput.visible = false;
                        root._save("text");
                    }
                    Keys.onEscapePressed: (e) => { taskInput.visible = false; e.accepted = true; }
                    onActiveFocusChanged: if (!activeFocus) taskInput.visible = false
                }
            }
            FieldRow {
                RowLabel { text: I18n.t("event.row.profile") }
                ValueLink {
                    id: profileLink
                    objectName: "event-profile"
                    activeFocusOnTab: true
                    text: root.profileName(root.profileId)
                    onActivated: profileMenu.popup(profileLink, 0, profileLink.height)
                    Keys.onReturnPressed: profileMenu.popup(profileLink, 0, profileLink.height)
                    AppMenu {
                        id: profileMenu
                        AppMenuItem {
                            text: I18n.t("event.profile.all")
                            marked: root.profileId.length === 0
                            onTriggered: { root.profileId = ""; root._save("text"); }
                        }
                        Repeater {
                            model: AppController.profiles
                            delegate: AppMenuItem {
                                required property var modelData
                                text: modelData.name
                                marked: root.profileId === modelData.id
                                onTriggered: { root.profileId = modelData.id; root._save("text"); }
                            }
                        }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }

            Text {
                objectName: "event-error"
                visible: root._error.length > 0
                Layout.fillWidth: true
                Layout.topMargin: Theme.spSm
                text: root._error
                color: Theme.warning
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                wrapMode: Text.Wrap
            }

            // The agenda: links, what to bring up. The meeting's notes.
            TextArea {
                id: agenda
                objectName: "event-agenda"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spLg
                Layout.minimumHeight: Theme.px(90)
                wrapMode: TextEdit.Wrap
                readOnly: root.readOnly
                placeholderText: I18n.t("event.ph.agenda")
                placeholderTextColor: Theme.textMuted
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                selectByMouse: true
                padding: Theme.spMd
                background: Rectangle {
                    radius: Theme.radiusMd
                    color: "transparent"
                    border.width: 1
                    border.color: agenda.activeFocus ? Theme.borderStrong : Theme.fieldBorder
                }
                ContextMenu.menu: TextEditMenu { editor: agenda }
                onTextChanged: root._textEdited()
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spLg
                spacing: Theme.spMd
                Text {
                    id: deleteText
                    objectName: "event-delete"
                    visible: !root.readOnly
                    text: I18n.t("event.delete")
                    color: Theme.dangerLink
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    font.underline: deleteCA.hovered
                    ClickArea { id: deleteCA; label: deleteText.text; onActivated: root.deleteEvent() }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.readOnly ? "" : I18n.t("event.autosave")
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
            }
        }
    }
}
