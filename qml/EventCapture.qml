pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp
import "EventRule.js" as EventRule

// A new meeting from one line (X-Dlg-Event, DG-120): "Ретро спринта пт 16:00
// на 1 ч каждые 2 недели". The same reading as the quick input; what it
// understood shows as chips under the line — when, repeat. Enter makes the
// meeting and opens it in the panel, Esc leaves nothing behind.
//
// Ctrl Alt E opens it on the next free hour; a click or a drag on the
// calendar opens it on that slot, which the line can still override.
Popup {
    id: root
    objectName: "event-capture"
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 460
    anchors.centerIn: Overlay.overlay
    Overlay.modal: ModalScrim {}

    // The meeting was made: Main opens it.
    signal created(string id)

    // The slot it was opened on: { date, start, end } (hours).
    property var slot: ({ date: new Date(), start: 9, end: 10 })
    readonly property var parsed: root.read(input.text)
    // The recognised words as offsets into the line, for the tint.
    readonly property var marks: root.markWords(input.text, root.parsed.words)

    function openAt(draft) {
        const d = draft || {};
        const day = d.date && d.date.getFullYear ? d.date : AppController.selectedDate;
        let start = d.start !== undefined ? Number(d.start) : AppController.nextFreeSlot(day, 1);
        // Late in the evening the free-slot search falls back to 23:00, a
        // slot already begun (IDIOT-CAL-8): from now, rounded up, instead;
        // the end may run into the next day.
        const now = new Date();
        if (d.start === undefined && day.toDateString() === now.toDateString()) {
            const step = Math.max(1, Theme.snapMinutes) / 60;
            start = Math.max(start, Math.ceil((now.getHours() + now.getMinutes() / 60) / step) * step);
        }
        const end = d.end !== undefined && Number(d.end) > start ? Number(d.end) : start + 1;
        root.slot = { date: day, start: start, end: end };
        input.text = "";
        root.open();
        input.forceActiveFocus();
    }

    function _valid(d) { return !!d && !!d.getTime && !isNaN(d.getTime()); }
    function _hours(d) { return d.getHours() + d.getMinutes() / 60; }
    // The line → { title, date, start, end, rule }.
    function read(raw) {
        const x = EventRule.extract(raw);
        // Read against the slot's day: a bare "14:00" stays on it.
        const sd = root.slot.date;
        const ref = new Date(sd.getFullYear(), sd.getMonth(), sd.getDate(), 0, 0, 1);
        const p = String(x.text).length > 0 ? AppController.captureParse(x.text, ref, []) : ({});
        const out = {
            title: String(p.title || x.text || "").trim(),
            date: root.slot.date,
            start: root.slot.start,
            end: root.slot.end,
            rule: x.rule || EventRule.fromChrono(p.recurrence),
            fromLine: false,
            words: [x.ruleText, x.lengthText].concat((p.spans || []).map(sp => String(sp.text)))
        };
        if (root._valid(p.when)) {
            out.date = new Date(p.when.getFullYear(), p.when.getMonth(), p.when.getDate());
            out.fromLine = true;
            if (p.whenHasTime) {
                const len = root.slot.end - root.slot.start;
                out.start = root._hours(p.when);
                out.end = out.start + len;
                if (root._valid(p.whenEnd)) {
                    // An end at or before the start is the next morning
                    // (IDIOT-CAL-11): "22:00-01:00" lost its end for an hour.
                    let e = root._hours(p.whenEnd);
                    const nextDay = p.whenEnd.getDate() !== p.when.getDate() || e <= out.start;
                    if (nextDay && e > 0) e += 24;
                    else if (e === 0) e = 24;
                    out.end = e;
                }
            }
        }
        if (x.minutes > 0) out.end = out.start + x.minutes / 60;
        // Past midnight the meeting ends on the next day, as the editor stores
        // it, instead of being cut at 24:00 (IDIOT-CAL-11).
        if (out.end > 24) {
            out.end = Math.min(out.end - 24, out.start);
            out.endDate = new Date(out.date.getFullYear(), out.date.getMonth(), out.date.getDate() + 1);
        }
        return out;
    }
    function markWords(raw, ws0) {
        const low = String(raw || "").toLowerCase();
        const out = [];
        const ws = ws0 || [];
        for (let i = 0; i < ws.length; i++) {
            const w = String(ws[i] || "").toLowerCase();
            if (w.length === 0) continue;
            const at = low.indexOf(w);
            if (at >= 0) out.push({ start: at, end: at + w.length, kind: i === 0 ? "repeat" : (i === 1 ? "length" : "when") });
        }
        return out;
    }
    function whenText(r) {
        return I18n.fmtDate(r.date, "weekdayDay") + " · " + AppController.eventHourLabel(r.start)
               + "–" + (r.endDate ? I18n.fmtDate(r.endDate, "weekdayDay") + " · " : "") + AppController.eventHourLabel(r.end);
    }

    function submit() {
        const r = root.parsed;
        if (r.title.length === 0) return;
        const d = AppController.newEventDraft(r.start, r.date);
        d.title = r.title;
        d.type = "none";
        d.start = r.start;
        d.end = r.end;
        d.date = r.date;
        d.endDate = r.endDate || r.date;
        d.rrule = r.rule;
        AppController.saveEvent(d);
        root.close();
        root.created(d.id);
    }

    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: 0
        // A one-line text area, not a field: only a text document can colour
        // the words it understood (R3-064, X-Dlg-Event).
        TextArea {
            id: input
            objectName: "event-capture-input"
            Layout.fillWidth: true
            Layout.topMargin: Theme.spLg
            Layout.leftMargin: Theme.spLg; Layout.rightMargin: Theme.spLg
            leftPadding: 0; rightPadding: 0
            topPadding: Theme.spSm; bottomPadding: Theme.spMd
            placeholderText: I18n.t("event.capture.ph")
            color: Theme.text
            placeholderTextColor: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwBody
            wrapMode: TextEdit.NoWrap
            textFormat: TextEdit.PlainText
            selectByMouse: true
            Accessible.name: I18n.t("event.capture.ph")
            background: Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1
                color: Theme.borderStrong
            }
            ContextMenu.menu: TextEditMenu { editor: input }
            Keys.onReturnPressed: (event) => { event.accepted = true; root.submit(); }
            Keys.onEnterPressed: (event) => { event.accepted = true; root.submit(); }
            // A paste keeps to one line.
            onTextChanged: if (input.text.indexOf("\n") >= 0) input.text = input.text.replace(/\n+/g, " ")
            SpanHighlighter {
                target: input.textDocument
                spans: root.marks
                colors: ({ when: Theme.info, repeat: Theme.info, length: Theme.info })
            }
        }
        Flow {
            Layout.fillWidth: true
            Layout.margins: Theme.spLg
            Layout.topMargin: Theme.spMd
            spacing: Theme.spSm
            component Chip: Rectangle {
                id: chip
                property string label: ""
                property string value: ""
                implicitWidth: chipRow.implicitWidth + 2 * Theme.spMd
                implicitHeight: Theme.chipH
                radius: Theme.radiusMd
                color: "transparent"
                border.width: 1
                border.color: Theme.border
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Theme.spSm
                    Text { text: chip.label; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: Theme.fsSm }
                    Text { text: chip.value; color: Theme.text; font.family: Theme.fontUi; font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle }
                }
            }
            Chip {
                objectName: "event-capture-when"
                label: I18n.t("event.capture.when")
                value: root.whenText(root.parsed)
            }
            Chip {
                objectName: "event-capture-repeat"
                visible: root.parsed.rule.length > 0
                label: I18n.t("event.capture.repeat")
                value: EventRule.describe(root.parsed.rule, root.parsed.date, I18n)
            }
        }
    }
}
