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
        || !!(host.carryList && host.carryList.visible)

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
        host.menu.editKey = host.boardKeys ? "board.open" : "";
        host.menu.archiveKey = host.boardKeys && !host._isArchived ? "board.archive" : "";
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
    property var carryList: null
    function carryMenu() {
        if (!host.carryList) {
            host.carryList = carryMenuComponent.createObject(host.anchorItem || host);
            host.carryList.back.connect(() => host.backToMenu("carry"));
        }
        return host.carryList;
    }
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
        const sub = which === "status" ? host.statusMenu()
                  : which === "carry" ? host.carryMenu() : host.priorityMenu();
        sub.popup(host.anchorItem, Theme.spLg, Math.min(host.anchorItem ? host.anchorItem.height : 0, 28));
        let cur = -1;
        if (which === "carry")
            cur = 0;
        else if (host._t && which === "status")
            cur = AppController.statuses.findIndex(st => st.id === host._t.status);
        else if (host._t)
            cur = ["P0", "P1", "P2", "P3"].indexOf(host._t.priority);
        sub.currentIndex = Math.max(0, cur);
    }
    // Left in a list: the card menu again, on the row the list came from.
    function backToMenu(which) {
        host.openMenu();
        const name = which === "status" ? "tc-menu-status"
                   : which === "carry" ? "tc-menu-carry" : "tc-menu-priority";
        for (let i = 0; i < host.menu.count; i++) {
            const it = host.menu.itemAt(i);
            if (it && it.objectName === name) { host.menu.currentIndex = i; break; }
        }
    }
    function releaseMenu() {
        for (const k of ["menu", "statusList", "priorityList", "carryList"]) {
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
        AppMenuItem {
            enabled: false
            contentItem: Text {
                text: host._t ? (host._t.id + " · " + host._t.title) : ""
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
                font.weight: Theme.fwTitle
                leftPadding: Theme.spXl
                rightPadding: Theme.spXl
            }
        }
        AppMenuItem {
            objectName: "tc-menu-edit"
            text: I18n.t("taskmenu.open"); onTriggered: host.openRequested()
            shortcutId: taskMenu.editKey
        }
        // Done in one action (APP-268); on a done task it puts it back. A
        // tracker card with writes off is done here only, and says so.
        AppMenuItem {
            objectName: "tc-menu-done"
            text: host._isDone ? I18n.t("taskmenu.reopen") : I18n.t("taskmenu.done")
            shortcutId: "task.done"
            note: host._isTicket && !host._writeOn && !host._isDone ? I18n.t("taskmenu.localOnly") : ""
            onTriggered: Qt.callLater(host.markDone)
        }
        AppMenuSeparator {}
        AppMenuItem {
            objectName: "tc-menu-schedule"
            text: I18n.t("taskmenu.schedule")
            enabled: !host._isDone
            note: host._isDone ? I18n.t("taskmenu.why.done") : ""
            // The next free slot of the selected day, at the block's real
            // length (the estimate, else the focus-block setting).
            onTriggered: if (host._t) AppController.scheduleTaskAtNextFreeSlot(host._t.id, AppController.selectedDate)
        }
        // Carrying it on by hand (APP-248): only "when" moves, never the
        // deadline, and only on this click.
        AppMenuItem {
            objectName: "tc-menu-carry"
            text: I18n.t("carry.menu"); opensList: true
            enabled: !host._isDone
            onTriggered: taskMenu._openNext = "carry"
        }
        AppMenuItem {
            objectName: "tc-menu-due"
            text: host._isTicket ? I18n.t("taskmenu.myDue") : I18n.t("taskmenu.due")
            onTriggered: host.openRequested()
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
            objectName: "tc-menu-priority"
            text: host._isTicket ? I18n.t("taskmenu.myPriority") : I18n.t("taskmenu.priority"); opensList: true
            onTriggered: taskMenu._openNext = "priority"
        }
        AppMenuItem {
            objectName: "tc-menu-status"
            text: I18n.t("taskmenu.move"); opensList: true
            onTriggered: taskMenu._openNext = "status"
        }
        AppMenuItem {
            objectName: "tc-menu-timer"
            text: host._t && host._t.isTiming ? I18n.t("taskcard.stopTimer") : I18n.t("taskcard.startTimer")
            onTriggered: {
                if (!host._t) return;
                if (host._t.isTiming) AppController.stopTaskTimer(host._t.id);
                else AppController.startTaskTimer(host._t.id);
            }
        }
        AppMenuSeparator { objectName: "tc-menu-ticketSep"; visible: host._isTicket }
        AppMenuItem {
            objectName: "tc-menu-open"
            visible: host._isTicket && String(host._ticket.url || "").length > 0
            height: visible ? implicitHeight : 0
            shortcutId: "task.openExternal"
            text: I18n.t("taskcard.openIn").arg(host._badge.name || host._ticket.provider || "")
            onTriggered: AppController.openTaskExternal(host.taskId)
        }
        AppMenuItem {
            objectName: "tc-menu-copylink"
            visible: host._isTicket && String(host._ticket.url || "").length > 0
            height: visible ? implicitHeight : 0
            text: I18n.t("taskcard.copyLink")
            onTriggered: AppController.copyToClipboard(String(host._ticket.url || ""))
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
        AppMenuSeparator {}
        AppMenuItem {
            objectName: "tc-menu-copyid"
            text: I18n.t("taskcard.copyId")
            onTriggered: if (host._t && host._t.id) AppController.copyToClipboard(host._t.id)
        }
        AppMenuItem {
            objectName: "tc-menu-branch"
            text: I18n.t("taskcard.createBranch")
            onTriggered: if (host._t && host._t.id) AppController.createBranchForTask(host._t.id)
        }
        AppMenuItem {
            objectName: "tc-menu-copybranch"
            readonly property bool _has: !!(host._t && host._t.branch && String(host._t.branch).length > 0)
            text: I18n.t("taskcard.copyBranch")
            enabled: _has
            note: _has ? "" : I18n.t("taskmenu.why.noBranch")
            onTriggered: if (_has) AppController.copyToClipboard(host._t.branch)
        }
        AppMenuSeparator {}
        AppMenuItem {
            objectName: "tc-menu-archive"
            text: host._isArchived ? I18n.t("taskcard.unarchive") : I18n.t("taskcard.archive")
            shortcutId: taskMenu.archiveKey
            onTriggered: AppController.setArchived(host.taskId, !host._isArchived)
        }
        // A tracker's task leaves lowkey, not the tracker: "Hide from lowkey".
        AppMenuItem {
            objectName: "tc-menu-delete"
            danger: true
            text: host._isTicket ? I18n.t("taskmenu.hide") : I18n.t("common.delete")
            shortcutId: "selection.deleteSel"
            onTriggered: AppController.deleteTask(host.taskId)
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
        Instantiator {
            model: AppController.statuses
            delegate: AppMenuItem {
                required property var modelData
                text: modelData.name
                marked: !!(host._t && host._t.status === modelData.id)
            }
            onObjectAdded: (index, object) => {
                statusMenu.insertItem(index, object);
                object["triggered"].connect(() => statusMenu.picked(object["modelData"].id));
            }
            onObjectRemoved: (index, object) => statusMenu.removeItem(object)
        }
    }
    }

    Component {
        id: carryMenuComponent
    AppMenu {
        id: carryMenu
        objectName: "tc-carry-menu"
        backOnLeft: true
        Instantiator {
            model: ["tomorrow", "window", "someday", "clear"]
            delegate: AppMenuItem {
                required property string modelData
                objectName: "tc-carry-" + modelData
                text: I18n.t("carry." + modelData)
                onTriggered: AppController.carryTasks([host.taskId], modelData)
            }
            onObjectAdded: (index, object) => carryMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => carryMenu.removeItem(object)
        }
    }
    }

    Component {
        id: priorityMenuComponent
    AppMenu {
        id: priorityMenu
        objectName: "tc-priority-menu"
        backOnLeft: true
        Instantiator {
            model: ["P0", "P1", "P2", "P3"]
            delegate: AppMenuItem {
                required property string modelData
                text: modelData
                marked: !!(host._t && host._t.priority === modelData)
                onTriggered: AppController.setTaskPriority(host.taskId, modelData)
            }
            onObjectAdded: (index, object) => priorityMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => priorityMenu.removeItem(object)
        }
    }
    }
}
