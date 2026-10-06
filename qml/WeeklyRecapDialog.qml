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
// It opens by itself once a week, on the first launch (or the first midnight)
// of a new week, when last week moved anything; settings.notifications
// .weeklyRecap = false turns that off. Which week was shown is kept in
// settings.notifications.recapSeenWeek, so a restart does not show it again.
// A task in the list opens in the editor.
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

    // Whether the recap should open by itself on `today`: switched on, not yet
    // shown this week, and last week moved something.
    function isDue(today, recap: var) {
        const n = root._settings().notifications || {};
        if (n.weeklyRecap === false) return false;
        if (n.recapSeenWeek === root.weekKey(today)) return false;
        return !!recap && (recap["groups"] || []).length > 0;
    }

    function _markSeen(today) {
        const s = root._settings();
        const n = Object.assign({}, s.notifications || {});
        n.recapSeenWeek = root.weekKey(today);
        s.notifications = n;
        AppController.appSettingsJson = JSON.stringify(s);
    }

    // Opens the recap if it is due. Called at startup and when the day turns.
    function showIfDue() {
        const today = new Date();
        const r = AppController.weeklyRecap();
        if (!root.isDue(today, r)) return false;
        root.recap = r;
        root._markSeen(today);
        root.open();
        return true;
    }

    // From the palette: last week's recap whether it is due or not.
    function showNow() {
        root.recap = AppController.weeklyRecap();
        root.open();
    }

    function _range() {
        if (!root.recap.weekStart) return "";
        const a = new Date(root.recap.weekStart + "T00:00:00");
        const b = new Date(root.recap.weekEnd + "T00:00:00");
        b.setDate(b.getDate() - 1);
        const loc = Qt.locale(I18n.lang === "ru" ? "ru_RU" : "en_US");
        return a.toLocaleDateString(loc, "d MMM") + " – " + b.toLocaleDateString(loc, "d MMM");
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
