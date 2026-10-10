pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The weekly recap (X-Dlg-Recap, DG-123): one week's facts — what closed,
// per day as bars, the meetings' hours — the closed list a click from each
// task, "Copy Markdown" and "Next week →". Opened by hand it shows the
// current week; [ and ] step back and forth.
//
// The Monday check still reads last week's column moves (WEAK PECAP): it
// opens by itself once a week, when last week moved anything;
// settings.notifications.weeklyRecap = false turns that off. Which week was
// seen is kept in settings.notifications.recapSeenWeek, so a restart does not
// show it again. "Seen" means the dialog was on screen and closed (APP-211):
// heap runs for weeks, and a recap opened at midnight in a window hidden in
// the tray used to mark the week seen with nobody looking. Until then the
// board's recap button carries a dot. A task in the list opens in the editor.
Popup {
    id: root
    objectName: "weekly-recap"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: 0
    width: 428
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property var recap: ({ weekStart: "", weekEnd: "", groups: [] })
    readonly property var groups: root.recap.groups || []
    readonly property int taskCount: {
        let n = 0;
        for (const g of root.groups) n += g.tasks.length;
        return n;
    }

    signal taskActivated(string id)
    // "Standup draft" in the footer (APP-170), when that is switched on.
    signal standupDraftRequested()

    // The Monday of the week `d` falls in, as "yyyy-MM-dd": the key a week is
    // remembered by.
    function weekKey(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        m.setDate(m.getDate() - ((m.getDay() + 6) % 7));
        const p2 = (n) => (n < 10 ? "0" : "") + n;
        return m.getFullYear() + "-" + p2(m.getMonth() + 1) + "-" + p2(m.getDate());
    }

    function _settings() {
        try { return JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { return {}; }
    }

    // The week whose recap was last seen, and whether the recap opens by
    // itself at all. Bound to the settings, so the board's dot follows.
    readonly property var _notif: root._settings().notifications || ({})
    readonly property string seenWeek: root._notif.recapSeenWeek || ""
    readonly property bool autoShow: root._notif.weeklyRecap !== false
    // Whether last week moved anything. Read again when the day turns or the
    // profile changes (the log is per profile).
    readonly property bool hasContent: (AppController.today, AppController.activeProfileId,
                                        root._hasGroups(AppController.weeklyRecap()))
    // This week's recap has something in it and was not seen yet: the dot on
    // the board's button. Nothing to read is nothing to flag, and with the
    // recap switched off there is no dot either.
    readonly property bool unseen: root.autoShow
        && (AppController.today, root.isUnseen(new Date(), root.seenWeek, root.hasContent))

    function _hasGroups(recap: var): bool {
        return !!recap && (recap["groups"] || []).length > 0;
    }

    // Pure rules (APP-211), testable without a clock: callers pass `now`.
    //
    // The recap of the week `now` falls in has something in it and nobody
    // has seen it.
    function isUnseen(now, seenWeek: string, hasContent: bool): bool {
        return hasContent && seenWeek !== root.weekKey(now);
    }
    // Whether to open the recap by itself right now: it is unseen and the
    // person can actually see it — the window is on screen and in front, and
    // nothing else is open over it. Otherwise it waits for the next chance
    // (the window coming back, an overlay closing, the day turning).
    function shouldShowRecap(now, seenWeek: string, visible: bool, active: bool,
                             overlayOpen: bool, hasContent: bool): bool {
        return root.isUnseen(now, seenWeek, hasContent) && visible && active && !overlayOpen;
    }

    // Whether the recap is due on `today` at all, wherever the window is:
    // switched on, not yet seen this week, and last week moved something.
    function isDue(today, recap: var): bool {
        return root.autoShow && root.isUnseen(today, root.seenWeek, root._hasGroups(recap));
    }

    function _markSeen(today) {
        const key = root.weekKey(today);
        const s = root._settings();
        const n = Object.assign({}, s.notifications || {});
        if (n.recapSeenWeek === key) return;
        n.recapSeenWeek = key;
        s.notifications = n;
        AppController.appSettingsJson = JSON.stringify(s);
    }

    // Opens the recap if it is due and can be seen. Called at startup, when
    // the day turns, when the window comes to the front and when an overlay
    // closes. Nothing is marked until the dialog is closed.
    function showIfDue(visible: bool, active: bool, overlayOpen: bool): bool {
        if (root.opened || !root.autoShow) return false;
        const now = new Date();
        // The cheap checks first: this runs on every activation.
        if (!root.shouldShowRecap(now, root.seenWeek, visible, active, overlayOpen, true)) return false;
        const r = AppController.weeklyRecap();
        if (!root.shouldShowRecap(now, root.seenWeek, visible, active, overlayOpen, root._hasGroups(r))) return false;
        root.recap = r;
        root._autoOpened = true;
        root.open();
        return true;
    }

    // From the palette, the hotkey and the board's button: the current week,
    // whether the recap is due or not, empty or not.
    function showNow() {
        root.recap = AppController.weeklyRecap();
        root.open();
    }

    // Closed = seen: the week the shown recap belongs to (its weekEnd is the
    // Monday of the week it was shown in).
    onAboutToHide: root._markSeen(root.recap.weekEnd ? new Date(root.recap.weekEnd + "T00:00:00") : new Date())

    // ── What it shows (DG-123): the facts of one week ──
    // A day in the week on screen; [ and ] step through weeks.
    property var weekDay: new Date()
    property var facts: ({ closed: [], perDay: [0, 0, 0, 0, 0, 0, 0] })
    readonly property var closedRows: root.facts.closed || []
    property int meetingMinutes: 0

    function _load(day) {
        root.weekDay = day;
        root.facts = AppController.weekFacts(day);
        const a = root.facts.weekStart, b = root.facts.weekEnd;
        let m = 0;
        if (a && b) {
            const occ = AppController.eventOccurrences(a, b);
            for (let i = 0; i < occ.length; i++)
                if (!occ[i].allDay) m += Math.max(0, (Number(occ[i].end) - Number(occ[i].start)) * 60);
        }
        root.meetingMinutes = Math.round(m);
    }
    function stepWeek(n) {
        const d = new Date(root.weekDay.getFullYear(), root.weekDay.getMonth(), root.weekDay.getDate() + 7 * n);
        root._load(d);
    }
    onAboutToShow: root._load(root._autoOpened ? new Date(new Date().getTime() - 7 * 86400000) : new Date())
    property bool _autoOpened: false
    onClosed: root._autoOpened = false

    // "5 – 11 октября", "28 сентября – 4 октября".
    function rangeText() {
        const a = root.facts.weekStart, b = root.facts.weekEnd;
        if (!a || !a.getTime || !b || !b.getTime) return "";
        const ma = I18n.locale.monthName(a.getMonth(), Locale.LongFormat);
        const mb = I18n.locale.monthName(b.getMonth(), Locale.LongFormat);
        if (I18n.lang === "ru")
            return a.getMonth() === b.getMonth() ? a.getDate() + " – " + b.getDate() + " " + mb
                                                 : a.getDate() + " " + ma + " – " + b.getDate() + " " + mb;
        return a.getMonth() === b.getMonth() ? ma + " " + a.getDate() + " – " + b.getDate()
                                             : ma + " " + a.getDate() + " – " + mb + " " + b.getDate();
    }
    function factsLine() {
        const parts = [I18n.count(root.closedRows.length, "recap.closedN")];
        if (root.meetingMinutes > 0)
            parts.push(I18n.t("recap.meetings").arg(I18n.fmtMinutes(root.meetingMinutes)));
        return parts.join(" · ");
    }
    // Monday..Friday, and a weekend day only when something closed on it.
    readonly property var dayRows: {
        const out = [];
        const per = root.facts.perDay || [];
        const a = root.facts.weekStart;
        for (let i = 0; i < 7; i++) {
            const n = Number(per[i] || 0);
            if (i >= 5 && n === 0) continue;
            out.push({ dow: (i + 1) % 7, n: n });
        }
        return out;
    }
    function markdown() {
        const lines = ["## " + I18n.t("recap.title").arg(root.rangeText()), "", root.factsLine(), ""];
        for (let i = 0; i < root.closedRows.length; i++)
            lines.push("- " + root.closedRows[i].id + " " + root.closedRows[i].title);
        return lines.join("\n") + "\n";
    }
    function copyMarkdown() {
        AppController.copyToClipboard(root.markdown());
        AppController.toast(I18n.t("recap.copied"));
    }
    // "Next week →": the calendar on the week after, to look at, not to plan
    // for the person.
    signal nextWeekRequested(var day)

    background: ModalSurface {}

    Shortcut { sequence: "["; enabled: root.opened; onActivated: root.stepWeek(-1) }
    Shortcut { sequence: "]"; enabled: root.opened; onActivated: root.stepWeek(1) }

    contentItem: ColumnLayout {
        spacing: 0

        Text {
            objectName: "recap-title"
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: I18n.t("recap.title").arg(root.rangeText())
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
        }
        Text {
            objectName: "recap-facts"
            Layout.topMargin: Theme.spXs
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: root.factsLine()
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }

        // One bar per day, as long as what closed on it.
        ColumnLayout {
            objectName: "recap-days"
            Layout.topMargin: Theme.spLg
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            spacing: Theme.spSm
            Repeater {
                model: root.dayRows
                delegate: RowLayout {
                    id: dayRow
                    required property var modelData
                    spacing: Theme.spMd
                    Text {
                        Layout.preferredWidth: Theme.px(24)
                        text: I18n.dayName(dayRow.modelData.dow)
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                    }
                    Rectangle {
                        objectName: "recap-bar"
                        implicitWidth: dayRow.modelData.n > 0 ? Theme.px(34) * Math.min(dayRow.modelData.n, 8) : 3
                        implicitHeight: Theme.spSm
                        radius: height / 2
                        color: Theme.borderStrong
                    }
                    Text {
                        text: I18n.t("recap.dayClosed").arg(dayRow.modelData.n)
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                    }
                }
            }
        }

        Text {
            visible: root.closedRows.length > 0
            Layout.topMargin: Theme.spLg
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("recap.closed")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
        }
        // The first few closed, each opening in one click; then "and N more".
        Repeater {
            model: root.closedRows.slice(0, 3)
            delegate: Text {
                id: taskRow
                required property var modelData
                objectName: "recap-task-" + modelData.id
                Layout.topMargin: Theme.spXs
                Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                Layout.fillWidth: true
                text: taskRow.modelData.id + " " + taskRow.modelData.title
                textFormat: Text.PlainText
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                font.underline: taskMA.hovered
                elide: Text.ElideRight
                ClickArea {
                    id: taskMA
                    objectName: "recap-task-area-" + taskRow.modelData.id
                    label: taskRow.text
                    showTip: false
                    onActivated: {
                        root.close();
                        root.taskActivated(taskRow.modelData.id);
                    }
                }
            }
        }
        Text {
            objectName: "recap-more"
            visible: root.closedRows.length > 3
            Layout.topMargin: Theme.spXs
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("recap.more").arg(root.closedRows.length - 3)
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }

        RowLayout {
            Layout.margins: Theme.inset
            Layout.fillWidth: true
            spacing: Theme.spMd
            PillButton {
                id: copyBtn
                objectName: "weekly-recap-copy"
                text: I18n.t("recap.copyMarkdown")
                onClicked: root.copyMarkdown()
            }
            PillButton {
                objectName: "weekly-recap-next"
                text: I18n.t("recap.nextWeek")
                onClicked: {
                    const d = new Date(root.weekDay.getFullYear(), root.weekDay.getMonth(), root.weekDay.getDate() + 7);
                    root.close();
                    root.nextWeekRequested(d);
                }
            }
            Item { Layout.fillWidth: true }
        }
    }
    onOpened: copyBtn.forceActiveFocus(Qt.TabFocusReason)
}
