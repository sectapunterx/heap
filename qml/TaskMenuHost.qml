pragma ComponentBehavior: Bound
import QtQuick
import TodoCpp

// The task's menu, the same in every view (APP-268): the board's cards, the
// list, the calendar, Today. Built on first use and parented to the item it
// opens at, with its status and priority lists. Rows per the heap 2 sheet
// X-Menus-Task, each with its key (keymap.md); a row that cannot run says why.
Item {
    id: host
    visible: false

    property string taskId: ""
    // The task's map as the views have it; read from AppController when unset.
    property var task: null
    // Where the menu opens from the keyboard, and whose child it is.
    property Item anchorItem: null
    // On the board Return / E act on the card under the cursor.
    property bool boardKeys: false

    signal openRequested()
    signal statusPicked(string statusId)

    readonly property var _t: host.task ? host.task : (host.taskId ? AppController.taskById(host.taskId) : null)
    readonly property bool _isArchived: !!(host._t && host._t.archived === true)
    readonly property var _ticket: (host._t && host._t.ticket) ? host._t.ticket : ({})
    readonly property bool _isTicket: !!(host._ticket.provider)
    readonly property var _badge: host._isTicket
        ? (AppController.providerBadges[host._ticket.provider] || ({}))
        : ({})
    readonly property bool _writeOn: host._isTicket
        && AppController.trackerWriteProviders.indexOf(host._ticket.provider) >= 0
    readonly property bool _isDone: !!(host._t && AppController.statusCategory(host._t.status) === "done")

    readonly property bool menuOpen: !!(host.menu && host.menu.visible)
        || !!(host.statusList && host.statusList.visible)
        || !!(host.priorityList && host.priorityList.visible)

    // From the keyboard: at the item, on its first action.
    function openMenu() {
        const m = host.contextMenu();
        m.popup(host.anchorItem, Theme.spLg, Math.min(host.anchorItem ? host.anchorItem.height : 0, 28));
        m.currentIndex = 1;
    }
    // At the pointer.
    function popup() { host.contextMenu().popup(); }
    // "Done" / back, one action with its toast (APP-268).
    function markDone() { AppController.toggleDone([host.taskId]); }

    // The context menu is built on the first right-click, not with the card:
    // thirteen menu items per card were most of what a card cost, and the
    // board, the timeline and the archive build a card for every row they
    // show. contextMenu() makes it (once per card), releaseMenu() lets it go —
    // a recycled list delegate calls that when it is pooled.
    property var menu: null
    function contextMenu() {
        if (!host.menu) {
            host.menu = taskMenuComponent.createObject(host.anchorItem || host);
            host.menu.subMenuRequested.connect(host.openSubMenu);
            host.menu.pushActionRequested.connect(host.runPushAction);
        }
        // The keys its rows show (APP-166), as they stand when it opens.
        host.menu.editKey = "board.open";
        host.menu.archiveKey = !host._isArchived ? "board.archive" : "";
        host.menu.canSendPush = host._isTicket && !!host._ticket.unsynced && !host._ticket.gone;
        host.menu.canDropPush = host._isTicket && !!host._ticket.unsynced;
        return host.menu;
    }
    function runPushAction(send) {
        if (send) AppController.retryTrackerPush(host.taskId);
        else AppController.discardTrackerPush(host.taskId);
    }
    // The status and priority lists are built the same way, on first use.
    property var statusList: null
    property var priorityList: null
    function statusMenu() {
        if (!host.statusList) {
            host.statusList = statusMenuComponent.createObject(host.anchorItem || host);
            host.statusList.back.connect(() => host.backToMenu("status"));
            host.statusList.picked.connect(sid => {
                host.statusPicked(sid);
                AppController.moveTaskTo(host.taskId, sid, "");
            });
        }
        return host.statusList;
    }
    function priorityMenu() {
        if (!host.priorityList) {
            host.priorityList = priorityMenuComponent.createObject(host.anchorItem || host);
            host.priorityList.back.connect(() => host.backToMenu("priority"));
        }
        return host.priorityList;
    }
    // The status or priority list at the card, on the task's current value,
    // so an Enter straight away changes nothing.
    function openSubMenu(which) {
        const sub = which === "status" ? host.statusMenu() : host.priorityMenu();
        sub.popup(host.anchorItem, Theme.spLg, Math.min(host.anchorItem ? host.anchorItem.height : 0, 28));
        let cur = -1;
        if (host._t && which === "status") {
            // The rows are reordered (Done last, a separator before it), so
            // find the current column's row by its id.
            for (let i = 0; i < sub.count; i++) {
                const it = sub.itemAt(i);
                if (it && it.modelData && it.modelData.id === host._t.status) { cur = i; break; }
            }
            sub.currentIndex = cur >= 0 ? cur : 1;
            return;
        }
        if (host._t)
            cur = ["P0", "P1", "P2", "P3"].indexOf(host._t.priority);
        // Row 0 is "‹ back".
        sub.currentIndex = Math.max(0, cur) + 1;
    }
    // Left in a list: the card menu again, on the row the list came from.
    function backToMenu(which) {
        host.openMenu();
        const name = which === "status" ? "tc-menu-status" : "tc-menu-priority";
        for (let i = 0; i < host.menu.count; i++) {
            const it = host.menu.itemAt(i);
            if (it && it.objectName === name) { host.menu.currentIndex = i; break; }
        }
    }
    function releaseMenu() {
        for (const k of ["menu", "statusList", "priorityList"]) {
            if (!host[k]) continue;
            host[k].destroy();
            host[k] = null;
        }
    }
    Component {
        id: taskMenuComponent
    AppMenu {
        id: taskMenu
        objectName: "tc-menu"
        // Set by contextMenu(): the catalogue ids of Return and E on the board.
        property string editKey: ""
        property string archiveKey: ""
        // A move that never reached the tracker (APP-243): send or drop it.
        // Set by contextMenu(), like the keys above.
        property bool canSendPush: false
        property bool canDropPush: false
        signal pushActionRequested(bool send)
        // The context line (X-Menus-Task): the key and the title.
        AppMenuHeader {
            text: host._t ? ((host._isTicket && host._ticket.key ? host._ticket.key : host._t.id) + " · " + host._t.title) : ""
        }
        AppMenuItem {
            objectName: "tc-menu-edit"
            text: I18n.t("taskmenu.open"); onTriggered: host.openRequested()
            // Return as the sheets write it: ↵.
            keyText: taskMenu.editKey.length > 0 && AppController.shortcuts.length >= 0
                ? AppController.shortcutText(taskMenu.editKey).replace(/^(Return|Enter)$/, "↵") : ""
        }
        // A tracker's task: "Открыть в GitHub" right under "Открыть"
        // (X-Menus-Task, R3-046).
        AppMenuItem {
            objectName: "tc-menu-open"
            visible: host._isTicket && String(host._ticket.url || "").length > 0
            height: visible ? implicitHeight : 0
            shortcutId: "task.openExternal"
            text: I18n.t("taskcard.openIn").arg(host._badge.name || host._ticket.provider || "")
            onTriggered: AppController.openTaskExternal(host.taskId)
        }
        // Done in one action (APP-268); on a done task it puts it back. A
        // tracker card with writes off is done here only, and says so.
        AppMenuItem {
            objectName: "tc-menu-done"
            text: host._isDone ? I18n.t("taskmenu.reopen") : I18n.t("taskmenu.done")
            shortcutId: "task.done"
            note: host._isTicket && !host._writeOn && !host._isDone ? I18n.t("taskmenu.localOnly") : ""
            noteTip: note.length > 0 ? I18n.t("taskmenu.localOnly.tip") : ""
            onTriggered: Qt.callLater(host.markDone)
        }
        AppMenuSeparator {}
        // A tracker's task: "Мой приоритет ›, Мой срок…, Запланировать…"
        // in that order (X-Menus-Task); a task of lowkey's own starts with
        // "Запланировать…". The rows trade places by name, so whichever is
        // shown answers to the one objectName.
        AppMenuItem {
            objectName: host._isTicket ? "tc-menu-priority" : "tc-menu-priority-ticket"
            visible: host._isTicket
            height: visible ? implicitHeight : 0
            text: I18n.t("taskmenu.myPriority"); opensList: true
            onTriggered: taskMenu._openNext = "priority"
        }
        AppMenuItem {
            objectName: host._isTicket ? "tc-menu-schedule-own" : "tc-menu-schedule"
            visible: !host._isTicket
            height: visible ? implicitHeight : 0
            shortcutId: "task.schedule"
            text: I18n.t("taskmenu.schedule")
            enabled: !host._isDone
            note: host._isDone ? I18n.t("taskmenu.why.done") : ""
            // The next free slot of the selected day, at the block's real
            // length (the estimate, else the focus-block setting).
            onTriggered: if (host._t) AppController.scheduleTaskAtNextFreeSlot(host._t.id, AppController.selectedDate)
        }
        AppMenuItem {
            objectName: "tc-menu-due"
            shortcutId: "task.due"
            text: host._isTicket ? I18n.t("taskmenu.myDue") : I18n.t("taskmenu.due")
            onTriggered: host.openRequested()
        }
        AppMenuItem {
            objectName: host._isTicket ? "tc-menu-schedule" : "tc-menu-schedule-ticket"
            visible: host._isTicket
            height: visible ? implicitHeight : 0
            shortcutId: "task.schedule"
            text: I18n.t("taskmenu.schedule")
            enabled: !host._isDone
            note: host._isDone ? I18n.t("taskmenu.why.done") : ""
            onTriggered: if (host._t) AppController.scheduleTaskAtNextFreeSlot(host._t.id, AppController.selectedDate)
        }
        // Status and priority without opening the editor (UX-26). Each opens
        // its own list at the item, so the keyboard can walk it too.
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
            objectName: host._isTicket ? "tc-menu-priority-own" : "tc-menu-priority"
            visible: !host._isTicket
            height: visible ? implicitHeight : 0
            text: I18n.t("taskmenu.priority"); opensList: true
            onTriggered: taskMenu._openNext = "priority"
        }
        // A tracker's column follows the tracker; its sheet has no move or
        // timer rows (the board's drag and the t key still do both).
        AppMenuItem {
            objectName: "tc-menu-status"
            visible: !host._isTicket
            height: visible ? implicitHeight : 0
            text: I18n.t("taskmenu.move"); opensList: true
            onTriggered: taskMenu._openNext = "status"
        }
        AppMenuItem {
            objectName: "tc-menu-timer"
            visible: !host._isTicket
            height: visible ? implicitHeight : 0
            shortcutId: "task.timer"
            text: host._t && host._t.isTiming ? I18n.t("taskcard.stopTimer") : I18n.t("taskcard.startTimer")
            onTriggered: {
                if (!host._t) return;
                if (host._t.isTiming) AppController.stopTaskTimer(host._t.id);
                else AppController.startTaskTimer(host._t.id);
            }
        }
        AppMenuSeparator { objectName: "tc-menu-ticketSep"; visible: host._isTicket }
        AppMenuItem {
            objectName: "tc-menu-copylink"
            visible: host._isTicket && String(host._ticket.url || "").length > 0
            height: visible ? implicitHeight : 0
            shortcutId: "task.copyLink"
            text: I18n.t("taskcard.copyLink")
            onTriggered: AppController.copyToClipboard(String(host._ticket.url || ""))
        }
        // "Обновить из GitHub": the tracker's copy now, not at the next sync.
        AppMenuItem {
            objectName: "tc-menu-refresh"
            visible: host._isTicket
            height: visible ? implicitHeight : 0
            text: I18n.t("taskmenu.refreshFrom").arg(host._badge.name || host._ticket.provider || "")
            onTriggered: AppController.syncProvider(String(host._ticket.provider || ""))
        }
        // A move that never reached the tracker: send it (after lowkey checks
        // the issue) or drop it and keep the column here only (APP-243).
        AppMenuItem {
            objectName: "tc-menu-send-push"
            visible: taskMenu.canSendPush
            height: visible ? implicitHeight : 0
            text: I18n.t("taskcard.sendPush")
            onTriggered: taskMenu.pushActionRequested(true)
        }
        AppMenuItem {
            objectName: "tc-menu-discard-push"
            visible: taskMenu.canDropPush
            height: visible ? implicitHeight : 0
            text: I18n.t("taskcard.discardPush")
            onTriggered: taskMenu.pushActionRequested(false)
        }
        AppMenuSeparator { visible: !host._isTicket }
        AppMenuItem {
            objectName: "tc-menu-copyid"
            visible: !host._isTicket
            height: visible ? implicitHeight : 0
            shortcutId: "task.copyId"
            text: I18n.t("taskcard.copyId")
            onTriggered: if (host._t && host._t.id) AppController.copyToClipboard(host._t.id)
        }
        AppMenuItem {
            objectName: "tc-menu-branch"
            visible: !host._isTicket
            height: visible ? implicitHeight : 0
            shortcutId: "task.createBranch"
            text: I18n.t("taskmenu.createBranch")
            onTriggered: if (host._t && host._t.id) AppController.createBranchForTask(host._t.id)
        }
        AppMenuItem {
            objectName: "tc-menu-copybranch"
            visible: !host._isTicket
            height: visible ? implicitHeight : 0
            readonly property bool _has: !!(host._t && host._t.branch && String(host._t.branch).length > 0)
            shortcutId: _has ? "task.copyBranch" : ""
            text: I18n.t("taskcard.copyBranch")
            enabled: _has
            note: _has ? "" : I18n.t("taskmenu.why.noBranch")
            onTriggered: if (_has) AppController.copyToClipboard(host._t.branch)
        }
        AppMenuSeparator {}
        AppMenuItem {
            objectName: "tc-menu-archive"
            visible: !host._isTicket
            height: visible ? implicitHeight : 0
            text: host._isArchived ? I18n.t("taskcard.unarchive") : I18n.t("taskcard.archive")
            shortcutId: taskMenu.archiveKey
            onTriggered: AppController.setArchived(host.taskId, !host._isArchived)
        }
        // A tracker's task leaves lowkey, not the tracker: "Hide from lowkey".
        AppMenuItem {
            objectName: "tc-menu-delete"
            danger: true
            text: host._isTicket ? I18n.t("taskmenu.hide") : I18n.t("common.delete")
            shortcutId: host._isTicket ? "" : "selection.deleteSel"
            onTriggered: AppController.deleteTask(host.taskId)
        }
        // Says why a tracker's task has no delete: lowkey never deletes in
        // the tracker (X-Menus-Task, R3-046).
        AppMenuItem {
            objectName: "tc-menu-delete-off"
            visible: host._isTicket
            height: visible ? implicitHeight : 0
            enabled: false
            text: I18n.t("common.delete")
            note: I18n.t("taskmenu.why.trackerDelete")
        }
    }
    }

    Component {
        id: statusMenuComponent
    AppMenu {
        id: statusMenu
        objectName: "tc-status-menu"
        backOnLeft: true
        // A row was picked; statusMenu() moves the task.
        signal picked(string statusId)
        // "‹ Column": back to the task's menu, like ← and Esc (APP-279).
        AppMenuItem {
            objectName: "tc-status-back"
            isBack: true
            text: "‹ " + I18n.t("taskmenu.column")
            onTriggered: statusMenu.goBack()
        }
        // The columns in order, the Done-stage ones last after a separator,
        // "Готово" with its key d (X-Menus-Task, R3-044). No number keys are
        // drawn; a digit still picks a column while the list is open.
        readonly property var _ordered: {
            const all = AppController.statuses || [];
            const open = all.filter(st => AppController.statusCategory(st.id) !== "done");
            const done = all.filter(st => AppController.statusCategory(st.id) === "done");
            return open.concat(done);
        }
        readonly property int _firstDone: {
            for (let i = 0; i < statusMenu._ordered.length; i++)
                if (AppController.statusCategory(statusMenu._ordered[i].id) === "done") return i;
            return -1;
        }
        property var _sep: null
        Component { id: statusSepComponent; AppMenuSeparator { objectName: "tc-status-doneSep" } }
        Instantiator {
            model: statusMenu._ordered
            delegate: AppMenuItem {
                required property var modelData
                required property int index
                readonly property bool isDoneStage: index === statusMenu._firstDone
                text: modelData.name
                // The current one says "сейчас", no check (X-Menus-Task).
                note: !!(host._t && host._t.status === modelData.id) ? I18n.t("taskmenu.now") : ""
                // A column by its number while the list is open.
                number: index < 9 ? index + 1 : 0
                shortcutId: isDoneStage ? "task.done" : ""
            }
            onObjectAdded: (index, object) => {
                const fd = statusMenu._firstDone;
                if (fd >= 0 && index >= fd) {
                    if (index === fd) {
                        if (!statusMenu._sep) statusMenu._sep = statusSepComponent.createObject(statusMenu);
                        statusMenu.insertItem(index + 1, statusMenu._sep);
                    }
                    statusMenu.insertItem(index + 2, object);
                } else {
                    statusMenu.insertItem(index + 1, object);
                }
                object["triggered"].connect(() => statusMenu.picked(object["modelData"].id));
            }
            onObjectRemoved: (index, object) => {
                statusMenu.removeItem(object);
                if (statusMenu._sep && index === 0) {
                    statusMenu.removeItem(statusMenu._sep);
                    statusMenu._sep.destroy();
                    statusMenu._sep = null;
                }
            }
        }
    }
    }

    Component {
        id: priorityMenuComponent
    AppMenu {
        id: priorityMenu
        objectName: "tc-priority-menu"
        backOnLeft: true
        AppMenuItem {
            objectName: "tc-priority-back"
            isBack: true
            text: "‹ " + (host._isTicket ? I18n.t("taskmenu.myPriority") : I18n.t("taskmenu.priority"))
            onTriggered: priorityMenu.goBack()
        }
        Instantiator {
            model: ["P0", "P1", "P2", "P3"]
            delegate: AppMenuItem {
                required property string modelData
                required property int index
                text: modelData === "P0" ? "P0 · " + I18n.t("taskmenu.urgent") : modelData
                // Bold paints P0 red 600 and P1 amber (N-Menus-Task, R3-043).
                labelColor: Style.urgency && (modelData === "P0" || modelData === "P1") ? Theme.priorityInk(modelData) : "transparent"
                labelWeight: Style.urgency && modelData === "P0" ? Theme.fwHeading : Theme.fwBody
                note: !!(host._t && host._t.priority === modelData) ? I18n.t("taskmenu.now") : ""
                // 1–4, the same keys as on the cursor (keymap.md).
                shortcutId: "task.priority" + index
                number: index + 1
                onTriggered: AppController.setTaskPriority(host.taskId, modelData)
            }
            onObjectAdded: (index, object) => priorityMenu.insertItem(index + 1, object)
            onObjectRemoved: (index, object) => priorityMenu.removeItem(object)
        }
    }
    }
}
