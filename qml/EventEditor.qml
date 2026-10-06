import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp
import "Attendees.js" as Attendees
import "PopupStack.js" as PopupStack

Popup {
    id: root
    modal: true
    focus: true
    // Unsaved edits are not thrown away by a stray click beside the popup:
    // with changes, a press outside or Esc asks first (see _requestClose).
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: 520
    anchors.centerIn: Overlay.overlay

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle {
        color: Theme.scrim
    }
    // A press beside the editor (APP-126); see PopupStack.js.
    Overlay.onPressed: if (PopupStack.isTopmost(root, Overlay.overlay)) root._requestClose()

    property string eventId: ""
    // A meeting from a calendar link (APP-118): that calendar owns it, so the
    // editor only shows it — no field takes input, Save and Delete are gone,
    // and its join link is one click away.
    readonly property string sourceCalendar: AppController.subscriptionNameOf(root.eventId.length > 0 ? root.eventId : root.masterId)
    readonly property bool readOnly: root.sourceCalendar.length > 0
    // The day this event falls on — editable via the calendar picker below.
    property var pickedDate: AppController.selectedDate
    // The last day it covers. Equal to pickedDate for an ordinary event, which
    // is what saveEvent() stores as "no end date at all".
    property var pickedEndDate: AppController.selectedDate
    property bool allDay: false

    // Event types, in menu order. "none" is the one-off meeting that fits no
    // routine — it is first so an unknown type (an import, a future id) reads
    // as untyped rather than as a standup.
    readonly property var types: ["none", "standup", "oneone", "sync", "focus"]
    function _typeIndex(t) {
        return Math.max(0, root.types.indexOf(t));
    }

    // Recurrence. `masterId` is set on anything the expansion generated, which
    // is what makes an edit a question — this occurrence, this and everything
    // after, or the whole series.
    property string masterId: ""
    property var originalDate: undefined
    readonly property bool repeating: root.masterId.length > 0 || repeatBox.currentIndex > 0

    // ── The repeat rule, as the editor builds it ─────────────────────────
    // The menu covers what people set by hand; the weekday picker, the end
    // (a date or a count) and "every weekday" complete it. A rule heap cannot
    // show that way — an import with BYSETPOS, say — is "Custom" and edited
    // as text, so nothing is silently rewritten into something simpler.
    readonly property var repeatKinds: ["never", "daily", "weekdays", "weekly", "biweekly", "monthly", "yearly", "custom"]
    readonly property var dayTokens: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    property var repeatDays: []          // Qt weekday numbers, for weekly kinds
    property string endKind: "never"     // never | until | count
    property var untilDate: undefined
    property int repeatCount: 10
    property string customRule: ""

    function _kindIndex(k) { return Math.max(0, root.repeatKinds.indexOf(k)); }
    function _kind() { return root.repeatKinds[repeatBox.currentIndex] || "never"; }
    function _weekdayOf(d) { const w = d.getDay(); return w === 0 ? 7 : w; }

    // RRULE text → editor state. Returns false for a rule the controls cannot
    // represent (it is then kept as custom text).
    function _loadRule(rule) {
        root._openedRule = rule || "";
        root.customRule = rule || "";
        root.repeatDays = [];
        root.endKind = "never";
        root.untilDate = undefined;
        root.repeatCount = 10;
        if (!rule) { repeatBox.currentIndex = 0; return true; }
        const parts = {};
        const chunks = String(rule).toUpperCase().split(";");
        for (let i = 0; i < chunks.length; i++) {
            const eq = chunks[i].indexOf("=");
            if (eq > 0) parts[chunks[i].slice(0, eq)] = chunks[i].slice(eq + 1);
        }
        const known = { FREQ: 1, INTERVAL: 1, BYDAY: 1, COUNT: 1, UNTIL: 1 };
        for (const k in parts) if (!known[k]) { repeatBox.currentIndex = root._kindIndex("custom"); return false; }
        const interval = parts.INTERVAL ? parseInt(parts.INTERVAL) : 1;
        const days = [];
        if (parts.BYDAY) {
            const toks = parts.BYDAY.split(",");
            for (let i = 0; i < toks.length; i++) {
                const n = root.dayTokens.indexOf(toks[i]);
                if (n < 0) { repeatBox.currentIndex = root._kindIndex("custom"); return false; }
                days.push(n + 1);
            }
        }
        if (parts.COUNT) { root.endKind = "count"; root.repeatCount = parseInt(parts.COUNT); }
        if (parts.UNTIL) {
            const u = parts.UNTIL;
            root.endKind = "until";
            root.untilDate = new Date(parseInt(u.slice(0, 4)), parseInt(u.slice(4, 6)) - 1, parseInt(u.slice(6, 8)));
        }
        let kind = "custom";
        const f = parts.FREQ;
        const isWeekdays = days.length === 5 && days.join(",") === "1,2,3,4,5";
        if (f === "DAILY" && interval === 1 && days.length === 0) kind = "daily";
        else if ((f === "DAILY" || f === "WEEKLY") && interval === 1 && isWeekdays) kind = "weekdays";
        else if (f === "WEEKLY" && interval === 1) kind = "weekly";
        else if (f === "WEEKLY" && interval === 2) kind = "biweekly";
        else if (f === "MONTHLY" && interval === 1 && days.length === 0) kind = "monthly";
        else if (f === "YEARLY" && interval === 1 && days.length === 0) kind = "yearly";
        root.repeatDays = (kind === "weekly" || kind === "biweekly") ? days : [];
        repeatBox.currentIndex = root._kindIndex(kind);
        return kind !== "custom";
    }

    // Editor state → RRULE text ("" = does not repeat).
    function _ruleFromBox() {
        const kind = root._kind();
        if (kind === "never") return "";
        if (kind === "custom") return root.customRule.trim().replace(/^RRULE:/i, "");
        let r = "";
        if (kind === "daily") r = "FREQ=DAILY";
        else if (kind === "weekdays") r = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR";
        else if (kind === "monthly") r = "FREQ=MONTHLY";
        else if (kind === "yearly") r = "FREQ=YEARLY";
        else {
            r = kind === "biweekly" ? "FREQ=WEEKLY;INTERVAL=2" : "FREQ=WEEKLY";
            const days = root.repeatDays.slice().sort();
            // The start's own weekday is what an empty BYDAY means; naming it
            // alone is redundant, naming more is the point.
            const own = root.pickedDate && root.pickedDate.getDay ? root._weekdayOf(root.pickedDate) : 0;
            if (days.length > 1 || (days.length === 1 && days[0] !== own))
                r += ";BYDAY=" + days.map(d => root.dayTokens[d - 1]).join(",");
        }
        if (root.endKind === "count" && root.repeatCount > 0) r += ";COUNT=" + root.repeatCount;
        if (root.endKind === "until" && root.untilDate && root.untilDate.getFullYear)
            r += ";UNTIL=" + Qt.formatDate(root.untilDate, "yyyyMMdd");
        return r;
    }
    // The rule as it was opened, and the repeat controls' state at that
    // moment. Rebuilt from the controls, an imported "FREQ=WEEKLY;BYDAY=MO"
    // comes back as "FREQ=WEEKLY" and an exact UNTIL loses its time; a save
    // that never touched the controls hands back the rule it was given.
    property string _openedRule: ""
    property string _openedRuleState: ""
    function _ruleState() {
        return JSON.stringify({
            kind: repeatBox.currentIndex, days: root.repeatDays.slice().sort(), endKind: root.endKind,
            until: root.untilDate && root.untilDate.getFullYear ? Qt.formatDate(root.untilDate, "yyyyMMdd") : "",
            count: root.repeatCount, custom: root.customRule
        });
    }
    function _ruleToSave() {
        return root._ruleState() === root._openedRuleState ? root._openedRule : root._ruleFromBox();
    }
    function _toggleDay(d) {
        const days = root.repeatDays.slice();
        const i = days.indexOf(d);
        if (i >= 0) days.splice(i, 1); else days.push(d);
        root.repeatDays = days;
    }

    // ── Reminder ─────────────────────────────────────────────────────────
    // -1 = the notifications setting, -2 = none, else minutes before.
    readonly property var reminderChoices: [-1, -2, 0, 5, 10, 15, 30, 60]
    readonly property int defaultLead: {
        try {
            const s = JSON.parse(AppController.appSettingsJson || "{}");
            const n = s.notifications && s.notifications.meetingLead;
            return (n === undefined || n === null) ? 5 : Number(n);
        } catch (e) { return 5; }
    }
    function _reminderLabel(v) {
        if (v === -1) return I18n.t("reminder.default").arg(root.defaultLead);
        if (v === -2) return I18n.t("reminder.none");
        if (v === 0) return I18n.t("reminder.atStart");
        return I18n.t("reminder.before").arg(v);
    }
    function _reminderIndex(v) {
        const i = root.reminderChoices.indexOf(v === undefined || v === null ? -1 : Number(v));
        return i >= 0 ? i : 0;
    }

    // What the fields held when the editor opened, to know whether closing
    // loses anything.
    property string _openedAs: ""
    readonly property bool _dirty: root.opened && root._openedAs.length > 0 && JSON.stringify(root._draftFields()) !== root._openedAs
    property bool _confirmDiscard: false
    property string _error: ""

    function _loadCommon(src) {
        titleField.text = src.title || "";
        typeBox.currentIndex = root._typeIndex(src.type);
        startField.text = AppController.eventHourLabel(src.start);
        endField.text = AppController.eventHourLabel(src.end);
        attField.text = src.attendees || "";
        root.pickedDate = src.date;
        root.pickedEndDate = src.endDate && src.endDate.getFullYear ? src.endDate : src.date;
        root.allDay = !!src.allDay;
        contextField.text = src.context || "";
        locationField.text = src.location || "";
        linkField.text = src.url || "";
        notesField.text = src.notes || "";
        reminderBox.currentIndex = root._reminderIndex(src.reminderMinutes);
    }
    function _opened() {
        root._error = "";
        root._confirmDiscard = false;
        open();
        root._openedAs = JSON.stringify(root._draftFields());
        root._openedRuleState = root._ruleState();
        titleField.forceActiveFocus();
        titleField.selectAll();
    }

    // Open on a draft that has not been saved yet — a click on an empty slot
    // in the calendar. Saving is what brings the event into existence, so
    // cancelling leaves nothing behind.
    function showForDraft(draft) {
        eventId = draft.id;
        root._loadCommon(draft);
        root.masterId = draft.masterId || "";
        root.originalDate = draft.originalDate;
        root._loadRule(draft.rrule || "");
        root._opened();
    }

    // Open on one occurrence of a series. `occ` is a map from
    // AppController.eventOccurrences — it carries the occurrence's own date
    // plus the master it came from.
    function showForOccurrence(occ) {
        eventId = occ.id;
        root._loadCommon(occ);
        root.masterId = occ.masterId || "";
        root.originalDate = occ.occurrenceDate || occ.originalDate;

        // The rule lives on the master, never on a generated instance.
        const master = root.masterId.length > 0 ? AppController.eventSeriesMaster(root.masterId) : null;
        const rule = (master && master.rrule) ? master.rrule : (occ.rrule || "");
        root._loadRule(rule);
        root._opened();
    }

    function showForId(id) {
        const ev = AppController.eventById(id);
        if (!ev || !ev.id) return;
        eventId = id;
        root._loadCommon(ev);
        root.masterId = String(ev.masterId || "");
        root.originalDate = undefined;
        root._loadRule(String(ev.rrule || ""));
        root._opened();
    }

    // Free-typed time → hours since midnight, or NaN when it is not a time.
    // "930" and "9.30" are 09:30 (they used to read as 24:00 and 09:00), "9"
    // is 09:00, and an hour past 24 is clamped to the end of the day.
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
        if (r && r.ok && r.hasTime && r.start) {
            return r.start.getHours() + r.start.getMinutes() / 60.0;
        }
        return NaN;
    }
    function _hm(h, m) {
        if (isNaN(h) || isNaN(m) || m > 59) return NaN;
        return Math.max(0, Math.min(24, h + m / 60.0));
    }
    // The end field: midnight on the event's own day is its end, 24:00 —
    // "12:00am" (how 12h shows that end) and "00:00" read as 0, which is
    // before any start, and the event could not be saved (TIME-22).
    function parseEndStrict(s) {
        const e = root.parseHourStrict(s);
        return (e === 0 && root._spanDays() === 0) ? 24 : e;
    }
    // The lenient form the rest of the editor used to use: 0 for anything
    // that is not a time.
    function parseHour(s) {
        const h = root.parseHourStrict(s);
        return isNaN(h) ? 0 : h;
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

    // What the fields say, for the dirty check (no ids, which do not change).
    function _draftFields() {
        return {
            title: titleField.text, type: typeBox.currentIndex, start: startField.text, end: endField.text,
            attendees: attField.text, date: root.pickedDate ? String(root.pickedDate) : "",
            endDate: root.pickedEndDate ? String(root.pickedEndDate) : "", allDay: root.allDay,
            rule: root._ruleFromBox(), context: contextField.text, location: locationField.text,
            url: linkField.text, notes: notesField.text, reminder: reminderBox.currentIndex
        };
    }

    // The three answers a calendar asks for when a repeating event is touched.
    // Asked only when there is a series to disturb: an ordinary event saves
    // straight through, and so does one that is only now being given a rule.
    function _commit(scope) {
        AppController.saveOccurrence(root._draft(), scope);
        root._openedAs = "";
        root.close();
    }

    function _commitDelete(scope) {
        AppController.deleteOccurrence(root.masterId, root.originalDate, scope);
        root._openedAs = "";
        root.close();
    }

    // "Oleg, Viktor, " → "Oleg, Viktor": a pick leaves a trailing separator
    // for the next name, which is not part of the list.
    function _cleanAttendees(s) {
        return String(s || "").split(",").map(x => x.trim()).filter(x => x.length > 0).join(", ");
    }

    function _draft() {
        const stored = AppController.eventById(root.eventId);
        return {
            id: root.eventId,
            title: titleField.text.trim(),
            type: root.types[typeBox.currentIndex],
            start: root.parseHour(startField.text),
            end: isNaN(root.parseEndStrict(endField.text)) ? 0 : root.parseEndStrict(endField.text),
            attendees: root._cleanAttendees(attField.text),
            date: root.pickedDate,
            endDate: root.pickedEndDate,
            allDay: root.allDay,
            rrule: root._ruleToSave(),
            masterId: root.masterId,
            originalDate: root.originalDate,
            taskId: (stored && stored.taskId) ? stored.taskId : "",
            context: contextField.text,
            location: locationField.text.trim(),
            url: linkField.text.trim(),
            notes: notesField.text,
            reminderMinutes: root.reminderChoices[reminderBox.currentIndex]
        };
    }

    // What would be saved, checked first: an empty title, a time that is not
    // one, an end before the start, a rule heap cannot read.
    function _validate() {
        if (titleField.text.trim().length === 0) {
            titleField.forceActiveFocus();
            return I18n.t("editor.err.title");
        }
        if (!root.allDay) {
            const s = root.parseHourStrict(startField.text);
            const e = root.parseEndStrict(endField.text);
            if (isNaN(s)) { startField.forceActiveFocus(); return I18n.t("editor.err.time").arg(startField.text); }
            if (isNaN(e)) { endField.forceActiveFocus(); return I18n.t("editor.err.time").arg(endField.text); }
            // An end at or before the start on the same day used to save as
            // a 23-hour event; an overnight one says so with its end date.
            if (root._spanDays() === 0 && e <= s) { endField.forceActiveFocus(); return I18n.t("editor.err.endBeforeStart"); }
        }
        if (root._kind() === "custom" && root.customRule.trim().length > 0
                && !AppController.isValidRRule(root._ruleFromBox()))
            return I18n.t("editor.err.rule");
        return "";
    }

    // Shared by the Save button and the Ctrl+Return shortcut.
    function _save() {
        if (root.readOnly) { root._openedAs = ""; root.close(); return; }
        root._error = root._validate();
        if (root._error.length > 0) return;
        if (root.masterId.length > 0 && root.originalDate) {
            scopePrompt.ask("save", (scope) => root._commit(scope), null);
            return;
        }
        AppController.saveEvent(root._draft());
        root._openedAs = "";
        root.close();
    }

    function _delete() {
        if (root.readOnly) return;
        if (root.masterId.length > 0 && root.originalDate) {
            scopePrompt.ask("delete", (scope) => root._commitDelete(scope), null);
            return;
        }
        AppController.deleteEvent(root.eventId);
        root._openedAs = "";
        root.close();
    }

    // Esc or a press outside: closes at once when nothing changed, and asks
    // once when something did — a second Esc discards.
    function _requestClose() {
        if (!root._dirty || root._confirmDiscard) {
            root._openedAs = "";
            root.close();
            return;
        }
        root._confirmDiscard = true;
    }

    // Keyboard-first — see TaskEditor.
    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: root.opened && !scopePrompt.opened
        onActivated: root._save()
    }
    Shortcut {
        sequence: "Esc"
        // A picker or the scope question closes itself first.
        enabled: root.opened && !scopePrompt.opened && !eventDatePicker.opened && !endDatePicker.opened
                 && !untilPicker.opened
        onActivated: attSuggest.isOpen ? attSuggest.dismiss() : root._requestClose()
    }

    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    // "This event, this and following, or all events?" — asked whenever an
    // occurrence of a series is saved or deleted, because every wrong answer
    // is a quiet data loss. "This event" is the default.
    SeriesScopeDialog { id: scopePrompt }

    component FieldLabel: Text {
        color: Theme.textMuted
        font.pixelSize: Theme.fsXs
        font.weight: Font.DemiBold
        font.letterSpacing: 1
    }
    component Field: TextField {
        id: fieldRoot
        ContextMenu.menu: TextEditMenu { editor: fieldRoot }
        background: FieldFrame {}
        color: Theme.text
        placeholderTextColor: Theme.textDim
        selectByMouse: true
    }

    contentItem: ColumnLayout {
        spacing: Theme.spLg
        Item { Layout.preferredHeight: 4 }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("editor.label.eventTitle")
            color: Theme.text
            font.pixelSize: Theme.fsLg
            font.weight: Font.DemiBold
        }

        Rectangle {
            objectName: "event-readonly-banner"
            visible: root.readOnly
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            implicitHeight: bannerRow.implicitHeight + Theme.spMd * 2
            radius: Theme.radiusMd
            color: Theme.accentSoft
            border.color: Theme.border
            RowLayout {
                id: bannerRow
                anchors.fill: parent
                anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spLg
                spacing: Theme.spMd
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("event.fromCalendar").arg(root.sourceCalendar)
                    color: Theme.text
                    font.pixelSize: Theme.fsSm
                    wrapMode: Text.Wrap
                }
                PillButton {
                    objectName: "event-join"
                    visible: linkField.text.length > 0
                    text: I18n.t("event.join")
                    primary: true
                    onClicked: Qt.openUrlExternally(linkField.text)
                }
            }
        }

        FieldLabel {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; text: I18n.t("common.title").toUpperCase()
        }
        Field {
            id: titleField
            objectName: "event-title"
            enabled: !root.readOnly
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
        }

        GridLayout {
            enabled: !root.readOnly
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            columns: 2; columnSpacing: Theme.spLg; rowSpacing: Theme.spXs

            FieldLabel { text: I18n.t("editor.label.eventType").toUpperCase() }
            FieldLabel { text: I18n.t("editor.label.attendees").toUpperCase() }

            AppComboBox {
                id: typeBox
                Layout.fillWidth: true
                model: root.types.map(t => I18n.t("event.type." + t))
            }
            Field {
                id: attField
                objectName: "event-attendees"
                Layout.fillWidth: true
                placeholderText: I18n.t("event.ph.attendees")
                onTextChanged: if (attField.activeFocus) attSuggest.refresh()
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
                    } else if (e.key === Qt.Key_Escape) { attSuggest.dismiss(); e.accepted = true; }
                }

                // Contacts and People offered for the name under the caret.
                Popup {
                    id: attSuggest
                    objectName: "event-attendee-suggest"
                    property var items: []
                    property int sel: 0
                    readonly property bool isOpen: attSuggest.visible && attSuggest.items.length > 0
                    y: attField.height + 2
                    width: Math.max(attField.width, 240)
                    height: Math.min(attSuggest.items.length, 6) * 30 + 4
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
                    function move(d) {
                        attSuggest.sel = Math.max(0, Math.min(attSuggest.items.length - 1, attSuggest.sel + d));
                    }
                    function accept() {
                        if (!attSuggest.isOpen) return;
                        const tok = Attendees.tokenAt(attField.text, attField.cursorPosition);
                        const r = Attendees.apply(attField.text, tok, String(attSuggest.items[attSuggest.sel].name).trim());
                        attField.text = r.text;
                        attField.cursorPosition = r.caret;
                        dismiss();
                    }

                    background: Rectangle {
                        radius: Theme.radiusMd; color: Theme.panel2
                        border.color: Theme.borderStrong; border.width: 1
                    }
                    contentItem: ListView {
                        clip: true
                        interactive: false
                        model: attSuggest.items
                        delegate: Rectangle {
                            id: sugRow
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 30
                            radius: Theme.radiusSm
                            color: sugRow.index === attSuggest.sel ? Theme.withAlpha(Theme.accent, 0.18)
                                 : (sugMA.containsMouse ? Theme.withAlpha(Theme.accent, 0.08) : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                                spacing: Theme.spMd
                                Rectangle {
                                    implicitWidth: 8; implicitHeight: 8; radius: Theme.radiusXs
                                    color: sugRow.modelData.color || Theme.textMuted
                                }
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
                            MouseArea {
                                id: sugMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    attSuggest.sel = sugRow.index;
                                    attSuggest.accept();
                                    attField.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
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
                    spacing: Theme.spMd
                    // Themed (design audit DES-20): the stock Basic track was
                    // 1.09:1 against the popup.
                    Switch {
                        id: allDaySwitch
                        objectName: "event-allday"
                        checked: root.allDay
                        onToggled: root.allDay = checked
                        Accessible.name: I18n.t("editor.label.allDay")
                        indicator: Rectangle {
                            objectName: "event-allday-track"
                            implicitWidth: 36
                            implicitHeight: 20
                            x: allDaySwitch.leftPadding
                            y: (allDaySwitch.height - height) / 2
                            radius: height / 2
                            color: allDaySwitch.checked ? Theme.accent : Theme.panel3
                            border.color: allDaySwitch.checked ? Theme.accent : Theme.fieldBorder
                            border.width: 1
                            Rectangle {
                                objectName: "event-allday-knob"
                                width: 16; height: 16; radius: 8
                                x: allDaySwitch.checked ? parent.width - width - 2 : 2
                                y: 2
                                color: Theme.knob
                                border.color: Theme.fieldBorder
                                border.width: 1
                                Behavior on x { NumberAnimation { duration: Theme.scaledMs(90) } }
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -3
                                radius: parent.radius + 3
                                color: "transparent"
                                border.color: Theme.focusRing
                                border.width: 2
                                visible: allDaySwitch.visualFocus
                            }
                        }
                    }
                    Text {
                        text: I18n.t("editor.label.allDay")
                        color: Theme.text
                        font.pixelSize: Theme.fsMd
                        Layout.fillWidth: true
                    }
                }
            }

            FieldLabel {
                visible: !root.allDay
                text: I18n.t("editor.label.start").toUpperCase()
            }
            FieldLabel {
                visible: !root.allDay
                text: I18n.t("editor.label.end").toUpperCase()
            }

            Field {
                id: startField
                objectName: "event-start"
                visible: !root.allDay
                Layout.fillWidth: true
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                placeholderText: I18n.t("editor.ph.timeRange")
                onEditingFinished: root._maybeExpandRange(startField, endField)
            }
            Field {
                id: endField
                objectName: "event-end"
                visible: !root.allDay
                Layout.fillWidth: true
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                placeholderText: "11:00"
            }

            // DATE — the day this event lands on, and the last day it covers.
            FieldLabel { text: I18n.t("editor.label.date").toUpperCase() }
            FieldLabel { text: I18n.t("editor.label.endDate").toUpperCase() }
            Rectangle {
                id: dateBtn
                Layout.fillWidth: true
                implicitHeight: 34
                radius: Theme.radiusMd
                color: dateMA.hovered ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spMd
                    spacing: Theme.spSm
                    Text {
                        Layout.fillWidth: true
                        text: root.pickedDate && root.pickedDate.toLocaleDateString ? root.pickedDate.toLocaleDateString(I18n.locale, "ddd, d MMM yyyy") : ""
                        color: Theme.text; font.family: Theme.fontUi; font.features: Theme.tabularNums; font.pixelSize: Theme.fsMd
                    }
                    Rectangle {   // mini calendar glyph
                        width: 15; height: 14; radius: Theme.radiusXs; color: "transparent"
                        border.color: Theme.textMuted; border.width: 1
                        Rectangle { width: parent.width; height: 3; color: Theme.textMuted; anchors.top: parent.top }
                    }
                }
                ClickArea {
                    id: dateMA
                    objectName: "event-date-pick"
                    label: I18n.t("editor.a11y.dateValue").arg(I18n.t("editor.label.date"))
                                                          .arg(root.pickedDate && root.pickedDate.toLocaleDateString
                                                               ? root.pickedDate.toLocaleDateString(I18n.locale, "d MMMM yyyy") : "")
                    tip: I18n.t("editor.a11y.pickDate")
                    onActivated: eventDatePicker.openAt(root.pickedDate, dateBtn)
                }
                DatePickerPopup {
                    id: eventDatePicker
                    objectName: "event-date-picker"
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
                radius: Theme.radiusMd
                color: endDateMA.hovered ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spMd
                    spacing: Theme.spSm
                    Text {
                        Layout.fillWidth: true
                        text: root.pickedEndDate && root.pickedEndDate.getFullYear
                            ? root.pickedEndDate.toLocaleDateString(I18n.locale, "ddd, d MMM yyyy")
                            : ""
                        color: Theme.text; font.family: Theme.fontUi; font.features: Theme.tabularNums; font.pixelSize: Theme.fsMd
                    }
                    Rectangle {
                        width: 15; height: 14; radius: Theme.radiusXs; color: "transparent"
                        border.color: Theme.textMuted; border.width: 1
                        Rectangle { width: parent.width; height: 3; color: Theme.textMuted; anchors.top: parent.top }
                    }
                }
                ClickArea {
                    id: endDateMA
                    label: I18n.t("editor.a11y.dateValue").arg(I18n.t("editor.label.endDate"))
                                                          .arg(root.pickedEndDate && root.pickedEndDate.getFullYear
                                                               ? root.pickedEndDate.toLocaleDateString(I18n.locale, "d MMMM yyyy") : "")
                    tip: I18n.t("editor.a11y.pickDate")
                    onActivated: endDatePicker.openAt(root.pickedEndDate, endDateBtn)
                }
                DatePickerPopup {
                    id: endDatePicker
                    y: parent.height + 4
                    // An end before the start is meaningless: the picker
                    // refuses it rather than seeming to ignore the click.
                    minimumDate: root.pickedDate
                    onPicked: (value) => root.pickedEndDate = (value < root.pickedDate) ? root.pickedDate : value
                }
            }

            // REPEAT — the rule, its days and its end.
            FieldLabel { text: I18n.t("editor.label.repeat").toUpperCase() }
            FieldLabel {
                visible: root._kind() !== "never" && root._kind() !== "custom"
                text: I18n.t("repeat.ends").toUpperCase()
            }
            AppComboBox {
                id: repeatBox
                objectName: "event-repeat"
                Layout.fillWidth: true
                Layout.columnSpan: (root._kind() === "never" || root._kind() === "custom") ? 2 : 1
                model: [I18n.t("repeat.never"), I18n.t("repeat.daily"), I18n.t("repeat.weekdays"), I18n.t("repeat.weekly"),
                        I18n.t("repeat.biweekly"), I18n.t("repeat.monthly"), I18n.t("repeat.yearly"),
                        I18n.t("repeat.custom")]
                onActivated: {
                    // A weekly rule starts from the event's own weekday.
                    if ((root._kind() === "weekly" || root._kind() === "biweekly") && root.repeatDays.length === 0
                            && root.pickedDate && root.pickedDate.getDay)
                        root.repeatDays = [root._weekdayOf(root.pickedDate)];
                    if (root._kind() === "custom" && root.customRule.length === 0)
                        root.customRule = "FREQ=WEEKLY";
                }
            }
            RowLayout {
                visible: root._kind() !== "never" && root._kind() !== "custom"
                Layout.fillWidth: true
                spacing: Theme.spSm
                AppComboBox {
                    id: endBox
                    objectName: "event-repeat-end"
                    Layout.fillWidth: true
                    model: [I18n.t("repeat.ends.never"), I18n.t("repeat.ends.on"), I18n.t("repeat.ends.after")]
                    currentIndex: root.endKind === "until" ? 1 : root.endKind === "count" ? 2 : 0
                    onActivated: (i) => {
                        root.endKind = i === 1 ? "until" : i === 2 ? "count" : "never";
                        if (i === 1 && !(root.untilDate && root.untilDate.getFullYear)) {
                            const d = root.pickedDate;
                            root.untilDate = new Date(d.getFullYear(), d.getMonth() + 1, d.getDate());
                        }
                    }
                }
                Field {
                    id: countField
                    objectName: "event-repeat-count"
                    visible: root.endKind === "count"
                    Layout.preferredWidth: 56
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    text: String(root.repeatCount)
                    validator: IntValidator { bottom: 1; top: 999 }
                    onTextEdited: root.repeatCount = Math.max(1, parseInt(countField.text) || 1)
                }
                Rectangle {
                    id: untilBtn
                    visible: root.endKind === "until"
                    Layout.preferredWidth: 110
                    implicitHeight: 34
                    radius: Theme.radiusMd
                    color: untilMA.hovered ? Theme.panel3 : Theme.panel2
                    border.color: Theme.border; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: root.untilDate && root.untilDate.getFullYear ? root.untilDate.toLocaleDateString(I18n.locale, "d MMM yyyy") : ""
                        color: Theme.text; font.family: Theme.fontUi; font.features: Theme.tabularNums; font.pixelSize: Theme.fsSm
                    }
                    ClickArea {
                        id: untilMA
                        objectName: "event-until-pick"
                        label: I18n.t("editor.a11y.dateValue").arg(I18n.t("repeat.ends"))
                                                              .arg(root.untilDate && root.untilDate.getFullYear
                                                                   ? root.untilDate.toLocaleDateString(I18n.locale, "d MMMM yyyy") : "")
                        tip: I18n.t("editor.a11y.pickDate")
                        onActivated: untilPicker.openAt(root.untilDate, untilBtn)
                    }
                    DatePickerPopup {
                        id: untilPicker
                        y: parent.height + 4
                        minimumDate: root.pickedDate
                        onPicked: (value) => root.untilDate = value
                    }
                }
            }

            // The days of a weekly rule.
            Row {
                objectName: "event-repeat-days"
                visible: root._kind() === "weekly" || root._kind() === "biweekly"
                Layout.columnSpan: 2
                spacing: Theme.spXs
                Repeater {
                    model: 7
                    delegate: Rectangle {
                        id: dayChip
                        required property int index
                        readonly property int day: dayChip.index + 1
                        readonly property bool on: root.repeatDays.indexOf(dayChip.day) >= 0
                        objectName: "event-repeat-day-" + dayChip.day
                        width: 36; height: 26; radius: Theme.radiusMd
                        color: dayChip.on ? Theme.accentSoft : (chipMA.containsMouse ? Theme.panel3 : Theme.panel2)
                        border.color: dayChip.on ? Theme.accent : Theme.border; border.width: 1
                        // A toggle the keyboard can reach and a screen reader
                        // can read as one (design audit DES-3): Tab to it,
                        // Space or Enter flips the day.
                        activeFocusOnTab: true
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: I18n.dayName(dayChip.day % 7)
                        Accessible.checkable: true
                        Accessible.checked: dayChip.on
                        function toggle() { root._toggleDay(dayChip.day); }
                        Accessible.onToggleAction: dayChip.toggle()
                        Accessible.onPressAction: dayChip.toggle()
                        Keys.onSpacePressed: dayChip.toggle()
                        Keys.onReturnPressed: dayChip.toggle()
                        Keys.onEnterPressed: dayChip.toggle()
                        Text {
                            anchors.centerIn: parent
                            text: I18n.dayName(dayChip.day % 7)
                            color: dayChip.on ? Theme.accentStrong : Theme.text
                            font.pixelSize: Theme.fsXs
                        }
                        MouseArea { id: chipMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dayChip.toggle() }
                        FocusRing {}
                    }
                }
            }

            // A rule the controls cannot show, edited as what it is.
            Field {
                id: customField
                objectName: "event-repeat-custom"
                visible: root._kind() === "custom"
                Layout.columnSpan: 2
                Layout.fillWidth: true
                font.family: Theme.fontMono
                placeholderText: I18n.t("repeat.custom.ph")
                text: root.customRule
                onTextEdited: root.customRule = customField.text
            }

            // WHERE / LINK
            FieldLabel { text: I18n.t("editor.label.location").toUpperCase() }
            FieldLabel { text: I18n.t("editor.label.link").toUpperCase() }
            Field {
                id: locationField
                objectName: "event-location"
                Layout.fillWidth: true
                placeholderText: I18n.t("event.ph.location")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spXs
                Field {
                    id: linkField
                    objectName: "event-link"
                    Layout.fillWidth: true
                    placeholderText: I18n.t("event.ph.link")
                }
                PillButton {
                    objectName: "event-link-open"
                    visible: /^https?:\/\//i.test(linkField.text.trim())
                    text: "↗"
                    Accessible.name: I18n.t("event.a11y.openLink")
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: I18n.t("event.a11y.openLink")
                    onClicked: Qt.openUrlExternally(linkField.text.trim())
                }
            }

            // CONTEXT / REMINDER
            FieldLabel { text: I18n.t("editor.label.context").toUpperCase() }
            FieldLabel { text: I18n.t("editor.label.reminder").toUpperCase() }
            // Free-form context label — rendered before the event title in the
            // calendar so the same profile can mean different things per event
            // (sprint name, feature, on-call rotation, …).
            Field {
                id: contextField
                Layout.fillWidth: true
                placeholderText: I18n.t("event.ph.context")
            }
            AppComboBox {
                id: reminderBox
                objectName: "event-reminder"
                Layout.fillWidth: true
                model: root.reminderChoices.map(v => root._reminderLabel(v))
            }
        }

        ColumnLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            spacing: Theme.spXs
            FieldLabel { text: I18n.t("editor.label.notes").toUpperCase() }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                TextArea {
                    id: notesField
                    ContextMenu.menu: TextEditMenu { editor: notesField }
                    objectName: "event-notes"
                    readOnly: root.readOnly
                    placeholderText: I18n.t("event.ph.notes")
                    placeholderTextColor: Theme.textDim
                    color: Theme.text
                    wrapMode: TextArea.Wrap
                    selectByMouse: true
                    background: FieldFrame {}
                }
            }
        }

        // What is wrong with the draft, or that closing would lose edits.
        Text {
            objectName: "event-editor-message"
            visible: text.length > 0
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root._error.length > 0 ? root._error : (root._confirmDiscard ? I18n.t("editor.unsaved") : "")
            color: root._error.length > 0 ? Theme.danger : Theme.textMuted
            font.pixelSize: Theme.fsSm
        }

        RowLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.topMargin: Theme.spSm; Layout.bottomMargin: Theme.sp2xl
            spacing: Theme.spMd
            PillButton {
                visible: !root.readOnly
                text: I18n.t("common.delete"); danger: true; onClicked: root._delete()
            }
            Item { Layout.fillWidth: true }
            PillButton {
                text: root.readOnly ? I18n.t("common.close") : I18n.t("common.cancel")
                onClicked: { root._openedAs = ""; root.close(); }
            }
            PillButton {
                visible: !root.readOnly
                text: I18n.t("editor.btn.save"); primary: true
                onClicked: root._save()
            }
        }
    }
}
