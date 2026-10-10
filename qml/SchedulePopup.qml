// s / Shift S (APP-278): when the task gets done, or its deadline, typed in
// one small field — the quick input's own reading of dates ("пт 15:00",
// "завтра", "через 2 дня 10:30"; "нет" takes it off). The line under the
// field says what Enter would set, and a meeting at the same time is said
// as a fact, never as a refusal. Enter sets it (one undo step, as a drag
// does), Esc leaves everything as it was, Tab opens the calendar.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    objectName: "schedule-popup"
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Theme.spLg
    width: Theme.px(400)

    // The tasks it sets (the selection, or the one under the cursor).
    property var taskIds: []
    // "scheduled" (s) or "due" (Shift S).
    property string field: "scheduled"
    readonly property bool due: root.field === "due"
    readonly property var _task: root.taskIds.length > 0 ? AppController.taskById(root.taskIds[0]) : null
    // Tab: the calendar, for the mouse; the shell opens it and sets the date.
    signal pickDateRequested(date current, bool timed)

    function openFor(ids, field) {
        root.taskIds = ids;
        root.field = field;
        input.text = "";
        open();
        input.forceActiveFocus();
    }

    readonly property var _noWords: ["нет", "no", "none", "-", "—", "убрать", "clear"]
    function _valid(d) { return !!d && !!d.getTime && !isNaN(d.getTime()); }
    // { state: "empty" | "clear" | "unknown" | "ok", when, timed }
    function read(raw) {
        const s = String(raw || "").trim();
        if (s.length === 0) return { state: "empty" };
        if (root._noWords.indexOf(s.toLowerCase()) >= 0) return { state: "clear" };
        const p = AppController.captureParse("x " + s, new Date(), []);
        let when = root.due ? p.due : p.when;
        let timed = root.due ? p.dueHasTime : p.whenHasTime;
        if (!root._valid(when)) {
            when = root.due ? p.when : p.due;
            timed = root.due ? p.whenHasTime : p.dueHasTime;
        }
        if (!root._valid(when)) return { state: "unknown" };
        return { state: "ok", when: when, timed: timed === true };
    }
    readonly property var parsed: root.read(input.text)
    readonly property int _minutes: root.taskIds.length > 0 ? AppController.taskBlockMinutes(root.taskIds[0]) : 60

    // A meeting the block would sit on, as a fact.
    function _clash(when, minutes) {
        const day = new Date(when.getFullYear(), when.getMonth(), when.getDate());
        const a = when.getHours() + when.getMinutes() / 60;
        const b = a + minutes / 60;
        const occ = AppController.eventOccurrences(day, day);
        for (let i = 0; i < occ.length; i++) {
            const e = occ[i];
            if (e.allDay) continue;
            if (e.start < b && e.end > a) return String(e.title || "");
        }
        return "";
    }
    // The nearest free slot of the same length on the same day, from the
    // clashing time on in half hours (R3-067); null when the day has none.
    function nearestFree(when, minutes) {
        const day = new Date(when.getFullYear(), when.getMonth(), when.getDate());
        const stop = Math.min(24, Math.max(AppController.workdayEnd, when.getHours() + 1)) * 60;
        let m = Math.ceil((when.getHours() * 60 + when.getMinutes()) / 30) * 30;
        for (; m + minutes <= stop; m += 30) {
            const t = new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.floor(m / 60), m % 60);
            if (root._clash(t, minutes).length === 0) return t;
        }
        return null;
    }
    readonly property string _clashWith: root.parsed.state === "ok" && root.parsed.timed && !root.due
                                         ? root._clash(root.parsed.when, root._minutes) : ""
    readonly property var _free: root._clashWith.length > 0 ? root.nearestFree(root.parsed.when, root._minutes) : null
    function resultText() {
        const p = root.parsed;
        if (p.state === "empty") return root.due ? I18n.t("schedule.hint.due") : I18n.t("schedule.hint.when");
        if (p.state === "clear") return root.due ? I18n.t("schedule.clear.due") : I18n.t("schedule.clear.when");
        if (p.state === "unknown") return I18n.t("schedule.unknown");
        const day = I18n.fmtDate(p.when, "weekdayDay");
        if (root.due) {
            return I18n.t("schedule.due").arg(p.timed ? day + " · " + I18n.fmtTime(p.when) : day + ", " + I18n.t("schedule.noTime"));
        }
        if (!p.timed) return day + ", " + I18n.t("schedule.noTime");
        const end = new Date(p.when.getTime() + root._minutes * 60000);
        let out = day + " · " + I18n.fmtTime(p.when) + "–" + I18n.fmtTime(end)
            + " " + I18n.t("schedule.byEstimate").arg(I18n.fmtMinutes(root._minutes));
        if (root._clashWith.length > 0) out += " · " + I18n.t("schedule.clash").arg(root._clashWith);
        return out;
    }

    // Sets it, for every task; nothing is sent anywhere.
    function apply() {
        const p = root.parsed;
        if (p.state !== "ok" && p.state !== "clear") return false;
        for (let i = 0; i < root.taskIds.length; i++) {
            if (p.state === "clear") AppController.clearTaskDate(root.taskIds[i], root.field);
            else AppController.rescheduleTask(root.taskIds[i], root.field, p.when, p.timed);
        }
        root.close();
        return true;
    }
    // A date picked in the calendar, with its hour when one was picked.
    function applyDate(d, timed) {
        for (let i = 0; i < root.taskIds.length; i++)
            AppController.rescheduleTask(root.taskIds[i], root.field, d, timed === true);
        root.close();
    }
    // ↓ on a clash: the nearest free slot instead.
    function applyNearest() {
        if (!root._free) return false;
        for (let i = 0; i < root.taskIds.length; i++)
            AppController.rescheduleTask(root.taskIds[i], root.field, root._free, true);
        root.close();
        return true;
    }

    background: PopupSurface {}

    contentItem: ColumnLayout {
        spacing: Theme.spSm
        // The card it is opened from carries the title; a selection says
        // how many it sets.
        Text {
            visible: root.taskIds.length > 1
            Layout.fillWidth: true
            text: I18n.count(root.taskIds.length, "schedule.nTasks")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            elide: Text.ElideRight
        }
        Text {
            text: root.due ? I18n.t("schedule.label.due") : I18n.t("schedule.label.when")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
        }
        TextField {
            id: input
            objectName: "schedule-input"
            Layout.fillWidth: true
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: Theme.fwBody
            selectByMouse: true
            // Clearly outlined, focused or not (R3-071).
            background: Rectangle {
                radius: Theme.radiusMd
                color: "transparent"
                border.color: Theme.borderStrong
                border.width: 1
            }
            Accessible.name: root.due ? I18n.t("schedule.label.due") : I18n.t("schedule.label.when")
            onAccepted: root.apply()
            Keys.onTabPressed: (event) => {
                const ok = root.parsed.state === "ok";
                root.pickDateRequested(ok ? root.parsed.when : AppController.selectedDate, ok && root.parsed.timed);
                event.accepted = true;
            }
            Keys.onDownPressed: (event) => { event.accepted = root.applyNearest(); }
        }
        Text {
            objectName: "schedule-result"
            Layout.fillWidth: true
            text: root.resultText()
            wrapMode: Text.Wrap
            // Bold: an overlap in the "now" orange, a date it did not read in
            // red; quiet keeps them in text and grey (R3-069).
            color: root.parsed.state === "unknown" ? (Style.urgency ? Theme.danger : Theme.textMuted)
                 : root.parsed.state === "empty" ? Theme.textMuted
                 : root._clashWith.length > 0 ? (Style.urgency ? Theme.warning : Theme.text) : Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }
        Text {
            Layout.fillWidth: true
            text: root.parsed.state === "unknown" ? I18n.t("schedule.keys.unknown")
                : root._free ? I18n.t("schedule.keys.clash").arg(I18n.fmtTime(root._free))
                : root.due ? I18n.t("schedule.keys.due") : I18n.t("schedule.keys")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
            elide: Text.ElideRight
        }
    }
}
