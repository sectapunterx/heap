import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp
import "PlainText.js" as MdPlain

Rectangle {
    id: card
    objectName: "tc-card"
    property var task         // QVariantMap-like with id,title,desc,priority,status,deadline,branch,archived,blockedStuck
    property string scheduled
    property string taskId: task ? task.id : ""
    readonly property bool _isStuck: !!(card.task && card.task.blockedStuck === true)
    readonly property bool _isArchived: !!(card.task && card.task.archived === true)
    // Selection state — re-evaluates via AppController.selectedTaskIdsChanged
    // (selectionCount is read in the binding so QML tracks the dependency).
    // The keyboard cursor is on this card. Distinct from selection: the cursor
    // is where the next key acts, a selection is what a bulk action acts on,
    // and a card can be either, both or neither.
    property bool cursored: false
    readonly property bool _selected: AppController.selectionCount >= 0
        && AppController.isTaskSelected(card.taskId)
    // Ticket identity (HEAP-117). `ticket` is empty for a locally-created task,
    // which is what every ticket-only chip below keys off.
    readonly property var _ticket: (card.task && card.task.ticket) ? card.task.ticket : ({})
    readonly property bool _isTicket: !!(card._ticket.provider)
    readonly property var _badge: card._isTicket
        ? (AppController.providerBadges[card._ticket.provider] || ({}))
        : ({})
    // Read by the views so a bare "O" can open whichever card is under the
    // cursor when nothing is selected.
    readonly property bool hovered: hoverArea.containsMouse
    // Any of the card's menus is up. The board holds its arrow/letter keys
    // back while one is, or Down moved the board cursor under the menu.
    // `visible`, not `opened`: opened only turns true once the fade-in ends,
    // and a key pressed during it would still reach the board.
    readonly property bool menuOpen: !!(card._menu && card._menu.visible)
        || !!(card._statusMenu && card._statusMenu.visible)
        || !!(card._priorityMenu && card._priorityMenu.visible)
    readonly property bool _done: !!(card.task && card.task.status === "done")
    signal clicked()

    // Open the card's menu from the keyboard (board key M, or the Menu key),
    // anchored on the card rather than on a pointer that may be elsewhere.
    function openMenu() {
        const menu = card.contextMenu();
        menu.popup(card, Theme.spLg, Math.min(card.height, 28));
        menu.currentIndex = 1;
    }
    Keys.onMenuPressed: card.openMenu()

    // When the work is planned, for a task that has a scheduledAt of its own
    // worth showing: no deadline, a different day, or a clock time. Before,
    // a task with only a schedule looked undated (TASKS-12).
    function _schedLabel() {
        if (card.scheduled && card.scheduled.length > 0) return card.scheduled;
        const t = card.task;
        if (!t || !t.scheduledAt || !t.scheduledAt.getTime || isNaN(t.scheduledAt.getTime())) return "";
        const s = t.scheduledAt;
        const dl = t.deadline;
        const sameDay = dl && dl.getTime && !isNaN(dl.getTime())
            && dl.getFullYear() === s.getFullYear() && dl.getMonth() === s.getMonth() && dl.getDate() === s.getDate();
        if (sameDay && !t.scheduledHasTime) return "";
        const today = AppController.today;
        const days = Math.round((new Date(s.getFullYear(), s.getMonth(), s.getDate()).getTime()
            - new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()) / 86400000);
        let day = days === 0 ? I18n.t("task.due.today")
                : days === 1 ? I18n.t("task.due.tomorrow")
                : AppController.shortDate(s);
        if (t.scheduledHasTime)
            day += " " + String(s.getHours()).padStart(2, "0") + ":" + String(s.getMinutes()).padStart(2, "0");
        return day;
    }

    signal rangeSelectRequested(string anchorId)

    // Time tracking (HEAP-78): tick once a second while this task's timer runs
    // so the elapsed chip stays live; _timerTick is read in the chip binding.
    property int _timerTick: 0
    Timer {
        interval: 1000; repeat: true
        running: !!(card.task && card.task.isTiming === true)
        onTriggered: card._timerTick++
    }
    function _fmtElapsed(s) {
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
        if (h > 0) return h + "h " + m + "m";
        if (m > 0) return m + "m " + sec + "s";
        return sec + "s";
    }
    function _recurLabel(r) {
        switch (r) {
            case "every:day":     return "daily";
            case "every:week":    return "weekly";
            case "every:weekday": return "weekdays";
            case "every:mon":     return "Mondays";
            case "every:tue":     return "Tuesdays";
            case "every:wed":     return "Wednesdays";
            case "every:thu":     return "Thursdays";
            case "every:fri":     return "Fridays";
            case "every:sat":     return "Saturdays";
            case "every:sun":     return "Sundays";
            case "every:month":   return "monthly";
        }
        const monthly = /^every:month:(\d+)$/.exec(String(r || ""));
        if (monthly) return "monthly · " + monthly[1];
        return r ? String(r).replace("every:", "") : "";
    }

    radius: Theme.radius
    color: _isArchived ? Theme.withAlpha(Theme.panel2, 0.55)
        : _selected ? Theme.withAlpha(Theme.accent, 0.10)
            : Theme.panel2
    border.color: dragArea.drag.active ? Theme.accent
        : activeFocus ? Theme.accentStrong
        : _selected ? Theme.accent
                : cursored ? Theme.accentStrong
                : _isStuck ? Theme.danger
                : hoverArea.containsMouse ? Theme.borderStrong
                : Theme.border
    border.width: dragArea.drag.active ? 2 : (_selected || cursored || activeFocus ? 2 : (_isStuck ? 2 : 1))
    opacity: dragArea.drag.active ? 0.92 : (_isArchived ? 0.7 : 1.0)
    scale: dragArea.drag.active ? 1.03 : 1.0
    transformOrigin: Item.Center
    z: dragArea.drag.active ? 1000 : 0
    Behavior on scale { NumberAnimation { duration: Theme.scaledMs(120); easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: Theme.scaledMs(120) } }

    implicitWidth: parent ? parent.width : 260
    implicitHeight: contentCol.implicitHeight + 2 * Theme.spLg

    // A card is a button to assistive tech and to the Tab key.
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: card.task ? ((card._isTicket ? (card._ticket.key || "") : card.task.id) + " " + card.task.title) : ""
    Accessible.onPressAction: card.clicked()
    Keys.onReturnPressed: card.clicked()
    Keys.onEnterPressed: card.clicked()

    // Drag.active is automatically driven by MouseArea.drag.active
    Drag.active: dragArea.drag.active
    Drag.dragType: Drag.Internal
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: 20

    property real homeX: 0
    property real homeY: 0
    // Where the card goes while it is dragged: an item above everything it
    // can be dropped on. Without one it drags inside its own parent, which
    // clips it and draws it under later siblings.
    property Item dragLayer: null
    // Reparented by hand rather than with a State + ParentChange: undoing a
    // ParentChange also restores the card's stacking order against the
    // sibling it was lifted from, and in a list that recycles its delegates
    // that sibling may since have gone back to the pool — Qt warned on every
    // drop into another column.
    readonly property bool _lifted: dragArea.drag.active && card.dragLayer !== null
    property Item _homeParent: null
    on_LiftedChanged: {
        if (card._lifted) {
            const p = card.mapToItem(card.dragLayer, 0, 0);
            card._homeParent = card.parent;
            card.parent = card.dragLayer;
            card.x = p.x;
            card.y = p.y;
        } else if (card._homeParent) {
            card.parent = card._homeParent;
            card._homeParent = null;
            // Back in the list: the list owns x/y, so put the card where it
            // was pressed rather than where the drag left it.
            card.x = card.homeX;
            card.y = card.homeY;
        }
    }

    // What sits on a card, top to bottom: who it is (key, priority, and any
    // alert that needs the user), the title, how far along it is, the
    // description, then one quiet line of facts. Only alerts and urgent dates
    // get a box or a colour; everything else is dim text, so a synced ticket
    // with a dozen facts still reads title-first.
    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: Theme.spLg
        spacing: Theme.spSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spSm
            // Provider badge: which tracker this card mirrors (HEAP-117). The
            // provider's own colour is on the glyph only.
            Text {
                objectName: "tc-badge"
                visible: card._isTicket
                text: card._badge.icon || "◍"
                textFormat: Text.PlainText
                color: card._badge.color || Theme.textMuted
                font.pixelSize: Theme.fsXs
                font.weight: Font.DemiBold
                QQC.ToolTip.visible: badgeHover.hovered
                QQC.ToolTip.text: (card._badge.name || card._ticket.provider || "")
                    + (card._ticket.project ? " · " + card._ticket.project : "")
                HoverHandler { id: badgeHover }
            }
            Text {
                objectName: "tc-key"
                // A mirrored issue is known by its tracker key, not by the
                // synthetic heap id ("github-68") the merge invented for it.
                text: card._isTicket ? (card._ticket.key || "") : (card.task ? card.task.id : "")
                textFormat: Text.PlainText
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
                font.weight: Font.Medium
            }
            // P0 and P1 are the priorities worth a glance, so they get the
            // coloured chip; P2 and P3 are plain dim text.
            Rectangle {
                id: priChip
                objectName: "tc-priority"
                readonly property string pri: card.task ? String(card.task.priority || "") : ""
                readonly property bool loud: pri === "P0" || pri === "P1"
                visible: pri.length > 0
                radius: Theme.radiusSm
                color: loud ? Theme.withAlpha(Theme.priorityColor(pri), 0.14) : "transparent"
                implicitWidth: priT.implicitWidth + (loud ? 10 : 0)
                implicitHeight: priT.implicitHeight + 2
                Text {
                    id: priT
                    anchors.centerIn: parent
                    text: priChip.pri
                    color: priChip.loud ? Theme.priorityColor(priChip.pri) : Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                    font.weight: priChip.loud ? Font.DemiBold : Font.Normal
                }
            }
            // The tracker refused the last status change, or the issue is no
            // longer in the tracker. Either way the card is out of step with it.
            Rectangle {
                objectName: "tc-sync-state"
                visible: card._isTicket && (!!card._ticket.unsynced || !!card._ticket.gone)
                radius: Theme.radiusSm
                color: Theme.withAlpha(Theme.warning, 0.14)
                implicitWidth: syncStateT.implicitWidth + 10
                implicitHeight: syncStateT.implicitHeight + 2
                Text {
                    id: syncStateT
                    anchors.centerIn: parent
                    text: card._ticket.gone ? I18n.t("taskcard.gone") : I18n.t("taskcard.unsynced")
                    textFormat: Text.PlainText
                    color: Theme.warning
                    font.pixelSize: Theme.fsXs
                    font.weight: Font.DemiBold
                }
                QQC.ToolTip.visible: syncStateHover.hovered
                QQC.ToolTip.text: card._ticket.gone ? I18n.t("taskcard.gone.tip")
                                  : (card._ticket.queued ? I18n.t("taskcard.queued.tip") : I18n.t("taskcard.unsynced.tip"))
                HoverHandler { id: syncStateHover }
                // The retry had no keyboard path: the card menu does not
                // offer it (design audit DES-19). The HoverHandler above keeps
                // the tooltip, which also shows for a card that is gone.
                ClickArea {
                    objectName: "tc-retry-push"
                    enabled: !!card._ticket.unsynced && !card._ticket.gone
                    label: I18n.t("taskcard.retryPush")
                    showTip: false
                    onActivated: AppController.retryTrackerPush(card.task.id)
                }
            }
            // Both heap and the tracker changed the same field since the last
            // sync. The local value is kept; the editor offers the other one.
            Rectangle {
                objectName: "tc-conflict"
                visible: card._isTicket && !!card._ticket.conflict
                radius: Theme.radiusSm
                color: Theme.withAlpha(Theme.warning, 0.14)
                implicitWidth: conflictT.implicitWidth + 10
                implicitHeight: conflictT.implicitHeight + 2
                Text {
                    id: conflictT
                    anchors.centerIn: parent
                    text: I18n.t("taskcard.conflict")
                    textFormat: Text.PlainText
                    color: Theme.warning
                    font.pixelSize: Theme.fsXs
                    font.weight: Font.DemiBold
                }
                QQC.ToolTip.visible: conflictHover.hovered
                QQC.ToolTip.text: I18n.t("taskcard.conflict.tip")
                HoverHandler { id: conflictHover }
            }
            // Left behind by a filter change: still a live issue, just not one
            // this connection pulls any more. Quiet on purpose.
            Rectangle {
                objectName: "tc-out-of-scope"
                visible: card._isTicket && !!card._ticket.outOfScope && !card._ticket.gone
                radius: Theme.radiusSm
                color: Theme.panel2
                implicitWidth: scopeT.implicitWidth + 10
                implicitHeight: scopeT.implicitHeight + 2
                Text {
                    id: scopeT
                    anchors.centerIn: parent
                    text: I18n.t("taskcard.outOfScope")
                    textFormat: Text.PlainText
                    color: Theme.textDim
                    font.pixelSize: Theme.fsXs
                }
                QQC.ToolTip.visible: scopeHover.hovered
                QQC.ToolTip.text: I18n.t("taskcard.outOfScope.tip")
                HoverHandler { id: scopeHover }
            }
            Rectangle {
                objectName: "tc-stuck"
                visible: card._isStuck
                radius: Theme.radiusSm
                color: Theme.withAlpha(Theme.danger, 0.14)
                implicitWidth: stuckT.implicitWidth + 10
                implicitHeight: stuckT.implicitHeight + 2
                Text {
                    id: stuckT
                    anchors.centerIn: parent
                    text: I18n.t("task.chip.stuck")
                    color: Theme.danger
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                    font.weight: Font.DemiBold
                }
            }
            Text {
                visible: card._isArchived
                text: I18n.t("task.chip.arch")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
        }

        Text {
            Layout.fillWidth: true
            text: card.task ? card.task.title : ""
            // A mirrored title is written by whoever filed the issue. Text
            // defaults to AutoText, which would render HTML — and an <img> in
            // it fetches from the network on their say-so.
            textFormat: Text.PlainText
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: Font.Medium
            // Wrap, not WordWrap: a URL or a long identifier has no space to
            // break at and ran off the card (TASKS-27).
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
        }

        // Checklist progress. A template ships its steps as markdown task
        // items, and until now a card could not say how far along it was
        // without being opened.
        RowLayout {
            id: checklistRow
            readonly property var _cl: (card.task && card.task.checklist) ? card.task.checklist : ({})
            readonly property int _total: _cl.total || 0
            readonly property int _done: _cl.done || 0
            visible: _total > 0
            Layout.fillWidth: true
            spacing: Theme.spSm

            Text {
                objectName: "tc-checklist"
                text: checklistRow._done + "/" + checklistRow._total
                color: checklistRow._done === checklistRow._total ? Theme.success : Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
            }
            // A bar rather than only a number: the ratio is the thing being
            // read, and a number has to be compared against its own second
            // half to mean anything.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 3
                radius: Theme.radiusXs
                color: Theme.panel3
                Rectangle {
                    width: parent.width * (checklistRow._total > 0 ? checklistRow._done / checklistRow._total : 0)
                    height: parent.height
                    radius: parent.radius
                    color: checklistRow._done === checklistRow._total ? Theme.success : Theme.accent
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: card.task ? MdPlain.plain(card.task.desc) : ""
            textFormat: Text.PlainText
            color: Theme.textMuted
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // One line of facts. Flow, not a row: on a narrow column the line
        // wraps instead of pushing facts out past the card's edge.
        Flow {
            id: metaFlow
            Layout.fillWidth: true
            // From each fact's own condition, not from the children's
            // `visible`: that reads false while this row is hidden, so a card
            // given its task after creation never showed its facts.
            visible: dueT.dlText.length > 0 || schedT.label.length > 0 || prT.state.length > 0
                     || !!(card.task && (card.task.isTiming || (card.task.trackedSeconds || 0) > 0))
                     || !!(card.task && card.task.recurrence && String(card.task.recurrence).length > 0)
                     || (card._isTicket && (card._ticket.commentCount || 0) > 0) || labelRep.count > 0
                     || card._attachmentCount > 0
            spacing: Theme.spLg

            // How many files are attached. Opening them is the editor's job.
            Text {
                objectName: "tc-attachments"
                visible: card._attachmentCount > 0
                text: "📎 " + card._attachmentCount
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
                Accessible.name: I18n.t("att.card.count").arg(card._attachmentCount)
            }

            Text {
                id: dueT
                objectName: "tc-due"
                readonly property int days: {
                    if (!card.task || !card.task.deadline) return 99999;
                    const dl = card.task.deadline;
                    // An unset date arrives as an Invalid Date — truthy, but its
                    // time is NaN, which used to render as "NaNd".
                    if (!dl.getTime || isNaN(dl.getTime())) return 99999;
                    const t = AppController.today;
                    const ms = dl.getTime() - new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
                    return Math.round(ms / 86400000);
                }
                readonly property string dlText: {
                    if (days === 99999) return "";
                    // Finished or archived work is not overdue (PLAT-24).
                    if ((card._done || card._isArchived) && days < 0) return "";
                    // A task due at a clock time shows it; a bare date does not.
                    let clock = "";
                    // dueHasTime since schema v10; views that still hand over the
                    // old single flag keep working.
                    const timed = card.task.dueHasTime !== undefined ? card.task.dueHasTime : card.task.hasTime;
                    if (timed && card.task.dueAt && card.task.dueAt.getHours) {
                        clock = " " + String(card.task.dueAt.getHours()).padStart(2, "0")
                              + ":" + String(card.task.dueAt.getMinutes()).padStart(2, "0");
                    }
                    if (days < 0) return I18n.t("task.due.overdue").arg(-days) + clock;
                    if (days === 0) return I18n.t("task.due.today") + clock;
                    if (days === 1) return I18n.t("task.due.tomorrow") + clock;
                    return I18n.t("task.due.inDays").arg(days) + clock;
                }
                visible: dlText.length > 0
                text: "◷ " + dlText
                color: (card._done || card._isArchived) ? Theme.textDim
                     : days <= 0 ? Theme.danger : days <= 3 ? Theme.warning : Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
            }
            Text {
                id: schedT
                objectName: "tc-scheduled"
                readonly property string label: (AppController.today, I18n.lang, card._schedLabel())
                visible: label.length > 0
                text: "▸ " + label
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
            }
            // The pull request's state: open is info, merged is success, closed
            // is dim. The branch itself is the editor's business (Details); on
            // the card it was a second title nobody reads from across a board.
            Text {
                id: prT
                objectName: "tc-pr"
                readonly property string state: card.task ? String(card.task.prState || "") : ""
                visible: state.length > 0
                text: {
                    const n = card.task ? (card.task.prNumber || 0) : 0;
                    return (n > 0 ? "PR #" + n + " " : "PR ") + state;
                }
                textFormat: Text.PlainText
                color: state === "merged" ? Theme.success : state === "closed" ? Theme.textDim : Theme.info
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
                font.weight: Font.Medium
            }
            // Whose move it is on that PR (APP-156): read off the PR — a review
            // asked of me, red CI, an approval — and only ever shown, never
            // acted on. "Mine" gets the chip; "waiting" stays dim text.
            Rectangle {
                id: moveChip
                objectName: "tc-move"
                readonly property string move: card.task ? String(card.task.prMove || "") : ""
                readonly property string reason: card.task ? String(card.task.prMoveReason || "") : ""
                readonly property bool mine: move === "mine"
                visible: AppController.showWhoseMove && move.length > 0 && prT.state.length > 0
                radius: Theme.radiusSm
                color: mine ? Theme.withAlpha(Theme.accent, 0.14) : "transparent"
                implicitWidth: moveT.implicitWidth + (mine ? 10 : 0)
                implicitHeight: moveT.implicitHeight + 2
                Text {
                    id: moveT
                    objectName: "tc-move-text"
                    anchors.centerIn: parent
                    text: moveChip.mine ? I18n.t("taskcard.move.mine") : I18n.t("taskcard.move.theirs")
                    textFormat: Text.PlainText
                    color: moveChip.mine ? Theme.accentStrong : Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsXs
                    font.weight: moveChip.mine ? Font.DemiBold : Font.Normal
                }
                readonly property string tip: moveChip.reason.length > 0 ? I18n.t("taskcard.move." + moveChip.reason) : ""
                QQC.ToolTip.visible: moveHover.hovered && moveChip.tip.length > 0
                QQC.ToolTip.text: moveChip.tip
                HoverHandler { id: moveHover }
                Accessible.role: Accessible.StaticText
                Accessible.name: moveT.text + (moveChip.tip.length > 0 ? " — " + moveChip.tip : "")
            }
            // Time tracking — click to start/stop; live while running.
            Text {
                id: timerT
                objectName: "tc-timer"
                visible: !!(card.task && (card.task.isTiming || (card.task.trackedSeconds || 0) > 0))
                text: {
                    card._timerTick;  // re-evaluate each tick while running
                    if (!card.task) return "";
                    const s = card.task.isTiming ? AppController.elapsedSecondsFor(card.task.id)
                                                 : (card.task.trackedSeconds || 0);
                    return (card.task.isTiming ? "● " : "⧗ ") + card._fmtElapsed(s);
                }
                color: card.task && card.task.isTiming ? Theme.accentStrong : Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
                font.weight: card.task && card.task.isTiming ? Font.DemiBold : Font.Normal
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!card.task) return;
                        if (card.task.isTiming) AppController.stopTaskTimer(card.task.id);
                        else AppController.startTaskTimer(card.task.id);
                    }
                }
            }
            // Recurrence (HEAP-77).
            Text {
                id: recurT
                visible: !!(card.task && card.task.recurrence && String(card.task.recurrence).length > 0)
                text: "↻ " + card._recurLabel(card.task ? card.task.recurrence : "")
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
            }
            // Comment count. -1 means the provider never said, which is not the
            // same as "no comments" — the count stays away for both, but a zero
            // from a provider that does report is still worth nothing to show.
            Text {
                id: commentsT
                objectName: "tc-comments"
                visible: card._isTicket && (card._ticket.commentCount || 0) > 0
                text: "❝ " + (card._ticket.commentCount || 0)
                textFormat: Text.PlainText
                color: Theme.textDim
                font.pixelSize: Theme.fsXs
            }
            // Labels (HEAP-124): a dot in the colour the tracker gave it and
            // the name in muted text. Two fit; the rest are counted.
            Repeater {
                id: labelRep
                model: card.task && card.task.labels ? card.task.labels.slice(0, 2) : []
                delegate: Row {
                    required property var modelData
                    spacing: Theme.spXs
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3
                        color: modelData.color || Theme.textDim
                    }
                    Text {
                        text: modelData.id
                        textFormat: Text.PlainText
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsXs
                        width: Math.min(implicitWidth, card.width * 0.5)
                        elide: Text.ElideRight
                    }
                }
            }
            Text {
                readonly property int more: card.task && card.task.labels ? card.task.labels.length - 2 : 0
                visible: more > 0
                text: "+" + more
                color: Theme.textDim
                font.pixelSize: Theme.fsXs
                QQC.ToolTip.visible: moreHover.hovered
                QQC.ToolTip.text: card.task && card.task.labels
                    ? card.task.labels.slice(2).map(l => l.id).join(", ") : ""
                HoverHandler { id: moreHover }
            }
        }
    }

    // "+N" badge shown while dragging a selected card with siblings.
    Rectangle {
        visible: dragArea.drag.active && card._selected && AppController.selectionCount > 1
        anchors.top: parent.top; anchors.right: parent.right
        anchors.margins: -6
        z: 5
        width: bulkT.implicitWidth + 10
        height: 18
        radius: 9
        color: Theme.accent
        border.color: Theme.accentStrong
        border.width: 1
        Text {
            id: bulkT
            anchors.centerIn: parent
            text: "+" + (AppController.selectionCount - 1)
            color: Theme.textOnAccent
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsXs
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // Files dragged in from a file manager attach to this task — one undo
    // step for the whole drop. Only external drags carry text/uri-list, so a
    // card being moved around the board passes straight through.
    readonly property int _attachmentCount: card.task ? (card.task.attachmentCount || 0) : 0
    property bool _fileOver: false
    function attachDroppedFiles(urls) {
        if (!card.taskId || !urls || urls.length === 0) return 0;
        const list = [];
        for (let i = 0; i < urls.length; ++i) list.push(urls[i]);
        return AppController.attachFilesToTask(card.taskId, list);
    }
    DropArea {
        objectName: "tc-file-drop"
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: (drag) => { drag.accepted = drag.hasUrls; card._fileOver = drag.accepted; }
        onExited: card._fileOver = false
        onDropped: (drop) => {
            card._fileOver = false;
            if (drop.hasUrls && card.attachDroppedFiles(drop.urls) > 0) drop.accept(Qt.CopyAction);
        }
    }
    Rectangle {
        visible: card._fileOver
        anchors.fill: parent
        radius: Theme.radiusMd
        color: "transparent"
        border.color: Theme.accent
        border.width: 2
        z: 6
    }
    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        drag.target: card
        drag.threshold: 5
        cursorShape: dragArea.drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property bool didDrag: false
        onPressed: (mouse) => {
            card.homeX = card.x; card.homeY = card.y; didDrag = false;
            if (mouse.button === Qt.RightButton) card.contextMenu().popup();
        }
        onPositionChanged: if (drag.active) didDrag = true
        onReleased: (mouse) => {
            const wasDrag = didDrag;
            card.Drag.drop();
            card.x = card.homeX; card.y = card.homeY;
            didDrag = false;
            if (wasDrag || mouse.button !== Qt.LeftButton) return;

            const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
            const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
            if (ctrl) {
                AppController.toggleTaskSelection(card.taskId);
            } else if (shift) {
                card.rangeSelectRequested(card.taskId);
            } else {
                if (AppController.selectionCount > 0) AppController.clearSelection();
                card.clicked();
            }
        }
    }

    // The context menu is built on the first right-click, not with the card:
    // thirteen menu items per card were most of what a card cost, and the
    // board, the timeline and the archive build a card for every row they
    // show. contextMenu() makes it (once per card), releaseMenu() lets it go —
    // a recycled list delegate calls that when it is pooled.
    property var _menu: null
    function contextMenu() {
        if (!card._menu) {
            card._menu = taskMenuComponent.createObject(card);
            card._menu.subMenuRequested.connect(card.openSubMenu);
        }
        return card._menu;
    }
    // The status and priority lists are built the same way, on first use.
    property var _statusMenu: null
    property var _priorityMenu: null
    function statusMenu() {
        if (!card._statusMenu) card._statusMenu = statusMenuComponent.createObject(card);
        return card._statusMenu;
    }
    function priorityMenu() {
        if (!card._priorityMenu) card._priorityMenu = priorityMenuComponent.createObject(card);
        return card._priorityMenu;
    }
    // The status or priority list at the card, on the task's current value,
    // so an Enter straight away changes nothing.
    function openSubMenu(which) {
        const sub = which === "status" ? card.statusMenu() : card.priorityMenu();
        sub.popup(card, Theme.spLg, Math.min(card.height, 28));
        let cur = -1;
        if (card.task && which === "status")
            cur = AppController.statuses.findIndex(st => st.id === card.task.status);
        else if (card.task)
            cur = ["P0", "P1", "P2", "P3"].indexOf(card.task.priority);
        sub.currentIndex = Math.max(0, cur);
    }
    function releaseMenu() {
        for (const k of ["_menu", "_statusMenu", "_priorityMenu"]) {
            if (!card[k]) continue;
            card[k].destroy();
            card[k] = null;
        }
    }
    Component {
        id: taskMenuComponent
    AppMenu {
        id: taskMenu
        objectName: "tc-menu"
        AppMenuItem {
            enabled: false
            contentItem: Text {
                text: card.task ? (card.task.id + " · " + card.task.priority) : ""
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                leftPadding: Theme.spXl
                rightPadding: Theme.spXl
            }
        }
        AppMenuItem {
            glyph: "✎"; text: I18n.t("taskcard.edit"); onTriggered: card.clicked()
        }
        // Status and priority without opening the editor (UX-26). Each opens
        // its own list at the card, so the keyboard can walk it too.
        // The list opens once this menu has finished closing. Opened straight
        // from the row, it came up while this menu's close was still handing
        // focus back to the board: the board kept the keys, and the list sat
        // open without them until another popup's close gave it focus back and
        // a stray Enter picked P0 (PERA-1).
        property string _openNext: ""
        signal subMenuRequested(string which)
        onClosed: {
            const which = taskMenu._openNext;
            taskMenu._openNext = "";
            if (which) taskMenu.subMenuRequested(which);
        }
        AppMenuItem {
            objectName: "tc-menu-status"
            glyph: "⇥"; text: I18n.t("taskcard.setStatus") + "  ›"
            onTriggered: taskMenu._openNext = "status"
        }
        AppMenuItem {
            objectName: "tc-menu-priority"
            glyph: "!"; text: I18n.t("taskcard.setPriority") + "  ›"
            onTriggered: taskMenu._openNext = "priority"
        }
        AppMenuItem {
            objectName: "tc-menu-archive"
            glyph: card._isArchived ? "↺" : "▣"
            text: card._isArchived ? I18n.t("taskcard.unarchive") : I18n.t("taskcard.archive")
            onTriggered: AppController.setArchived(card.taskId, !card._isArchived)
        }
        AppMenuItem {
            glyph: card.task && card.task.isTiming ? "■" : "▸"
            text: card.task && card.task.isTiming ? I18n.t("taskcard.stopTimer") : I18n.t("taskcard.startTimer")
            onTriggered: {
                if (!card.task) return;
                if (card.task.isTiming) AppController.stopTaskTimer(card.task.id);
                else AppController.startTaskTimer(card.task.id);
            }
        }
        AppMenuSeparator { visible: card._isTicket }
        AppMenuItem {
            objectName: "tc-menu-open"
            visible: card._isTicket && String(card._ticket.url || "").length > 0
            height: visible ? implicitHeight : 0
            glyph: "↗"
            text: I18n.t("taskcard.openIn").arg(card._badge.name || card._ticket.provider || "")
            onTriggered: AppController.openTaskExternal(card.taskId)
        }
        AppMenuItem {
            objectName: "tc-menu-copylink"
            visible: card._isTicket && String(card._ticket.url || "").length > 0
            height: visible ? implicitHeight : 0
            glyph: "⎘"
            text: I18n.t("taskcard.copyLink")
            onTriggered: AppController.copyToClipboard(String(card._ticket.url || ""))
        }
        AppMenuSeparator {}
        AppMenuItem {
            glyph: "◷"
            text: I18n.t("taskcard.schedule")
            onTriggered: {
                if (!card.task) return;
                // 14:00 used to be hardcoded here, so every task scheduled from
                // the card landed on top of the last one — and on a time that
                // had already passed for most of the afternoon.
                // The gap is looked for with the block's real length (the
                // estimate, else the focus-block setting); it used to search
                // for an hour and then book ninety minutes over a meeting.
                AppController.scheduleTaskAtNextFreeSlot(card.task.id, AppController.selectedDate);
            }
        }
        AppMenuItem {
            glyph: "⎘"
            text: I18n.t("taskcard.copyId")
            onTriggered: {
                if (card.task && card.task.id) AppController.copyToClipboard(card.task.id);
            }
        }
        AppMenuItem {
            glyph: "⎇"
            text: I18n.t("taskcard.copyBranch")
            enabled: !!(card.task && card.task.branch && String(card.task.branch).length > 0)
            onTriggered: {
                if (card.task && card.task.branch) AppController.copyToClipboard(card.task.branch);
            }
        }
        AppMenuItem {
            glyph: "+"
            text: I18n.t("taskcard.createBranch")
            onTriggered: {
                if (card.task && card.task.id) AppController.createBranchForTask(card.task.id);
            }
        }
        AppMenuSeparator {}
        AppMenuItem {
            glyph: "×"; danger: true
            text: I18n.t("common.delete"); onTriggered: AppController.deleteTask(card.taskId)
        }
    }
    }

    Component {
        id: statusMenuComponent
    AppMenu {
        id: statusMenu
        objectName: "tc-status-menu"
        Instantiator {
            model: AppController.statuses
            delegate: AppMenuItem {
                required property var modelData
                text: modelData.name
                marked: !!(card.task && card.task.status === modelData.id)
                onTriggered: AppController.moveTaskTo(card.taskId, modelData.id, "")
            }
            onObjectAdded: (index, object) => statusMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => statusMenu.removeItem(object)
        }
    }
    }

    Component {
        id: priorityMenuComponent
    AppMenu {
        id: priorityMenu
        objectName: "tc-priority-menu"
        Instantiator {
            model: ["P0", "P1", "P2", "P3"]
            delegate: AppMenuItem {
                required property string modelData
                text: modelData
                marked: !!(card.task && card.task.priority === modelData)
                onTriggered: AppController.setTaskPriority(card.taskId, modelData)
            }
            onObjectAdded: (index, object) => priorityMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => priorityMenu.removeItem(object)
        }
    }
    }
}
