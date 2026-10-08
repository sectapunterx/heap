pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The Monday recap (WEAK PECAP): which tasks changed column last week,
// grouped by the move —
//
//   Backlog → In Progress
//     APP-12  Login rate limit
//     APP-14  CSV export
//
// It opens by itself once a week, when last week moved anything;
// settings.notifications.weeklyRecap = false turns that off. Which week was
// seen is kept in settings.notifications.recapSeenWeek, so a restart does not
// show it again. "Seen" means the dialog was on screen and closed (APP-211):
// heap runs for weeks, and a recap opened at midnight in a window hidden in
// the tray used to mark the week seen with nobody looking. Until then the
// board's recap button carries a dot. A task in the list opens in the editor.
Dialog {
    id: root
    objectName: "weekly-recap"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: Theme.inset
    width: 520
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
        root.open();
        return true;
    }

    // From the palette, the hotkey and the board's button: last week's recap
    // whether it is due or not, empty or not.
    function showNow() {
        root.recap = AppController.weeklyRecap();
        root.open();
    }

    // Closed = seen: the week the shown recap belongs to (its weekEnd is the
    // Monday of the week it was shown in).
    onAboutToHide: root._markSeen(root.recap.weekEnd ? new Date(root.recap.weekEnd + "T00:00:00") : new Date())

    function _range() {
        if (!root.recap.weekStart) return "";
        const a = new Date(root.recap.weekStart + "T00:00:00");
        const b = new Date(root.recap.weekEnd + "T00:00:00");
        b.setDate(b.getDate() - 1);
        return I18n.fmtDate(a, "dayMonth") + " – " + I18n.fmtDate(b, "dayMonth");
    }

    header: DialogHeader { text: I18n.t("recap.title").arg(root._range()) }
    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: Theme.spLg

        Text {
            Layout.fillWidth: true
            text: root.taskCount > 0 ? I18n.t("recap.summary").arg(root.taskCount)
                                     : I18n.t("recap.empty")
            color: Theme.textMuted
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(groupsCol.implicitHeight, 420)
            contentHeight: groupsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: groupsCol
                width: flick.width
                spacing: Theme.spLg

                Repeater {
                    model: root.groups
                    delegate: ColumnLayout {
                        id: grp
                        required property var modelData
                        objectName: "recap-group-" + modelData.from + "-" + modelData.to
                        Layout.fillWidth: true
                        spacing: Theme.spXs

                        RowLayout {
                            spacing: Theme.spSm
                            Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: grp.modelData.fromColor || Theme.textDim }
                            Text { text: grp.modelData.fromName; color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Theme.fwTitle }
                            Text { text: "→"; color: Theme.textDim; font.pixelSize: Theme.fsMd }
                            Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: grp.modelData.toColor || Theme.textDim }
                            Text { text: grp.modelData.toName; color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Theme.fwTitle }
                            Text { text: "· " + grp.modelData.tasks.length; color: Theme.textDim; font.pixelSize: Theme.fsSm }
                        }

                        Repeater {
                            model: grp.modelData.tasks
                            delegate: Rectangle {
                                id: taskRow
                                required property var modelData
                                objectName: "recap-task-" + modelData.id
                                Layout.fillWidth: true
                                implicitHeight: taskLine.implicitHeight + Theme.spSm * 2
                                radius: Theme.radiusMd
                                color: taskMA.hovered ? Theme.panel3 : "transparent"
                                RowLayout {
                                    id: taskLine
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spXl
                                    anchors.rightMargin: Theme.spMd
                                    spacing: Theme.spMd
                                    Text {
                                        // A fixed column, so the titles line up.
                                        Layout.preferredWidth: 72
                                        elide: Text.ElideRight
                                        text: taskRow.modelData.id
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fsXs
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: taskRow.modelData.title
                                        color: Theme.text
                                        font.pixelSize: Theme.fsSm
                                        elide: Text.ElideRight
                                    }
                                }
                                ClickArea {
                                    id: taskMA
                                    objectName: "recap-task-area-" + taskRow.modelData.id
                                    label: taskRow.modelData.id + " " + taskRow.modelData.title
                                    showTip: false
                                    onActivated: {
                                        root.close();
                                        root.taskActivated(taskRow.modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    footer: DialogFooter {
        PillButton {
            objectName: "weekly-recap-standup"
            visible: !!(AppController.safety && AppController.safety.standupDraft)
            text: I18n.t("standup.open")
            onClicked: {
                root.close();
                root.standupDraftRequested();
            }
        }
        PillButton {
            id: closeBtn
            objectName: "weekly-recap-close"
            text: I18n.t("common.close")
            primary: true
            onClicked: root.close()
        }
    }
    onOpened: closeBtn.forceActiveFocus()
}
