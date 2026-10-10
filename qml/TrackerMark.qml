import QtQuick
import QtQuick.Controls as QQC
import TodoCpp

// Out of step with the tracker, in the sheet's words (X/N-Err-Tracker,
// R2-034): "ждёт отправки статуса", "вне фильтра Jira — только у вас",
// "удалён в Jira · оставить у себя / убрать", "изменён и у вас, и в Jira ·
// решить". The actions are links in the line; nothing is sent from here
// unless writes are on. Shared by the board card and the list row (R3-144).
Text {
    id: markT

    // The task's id and its `ticket` map (from the model, or taskById()).
    property string taskId: ""
    property var ticket: ({})
    property string trackerName: ""
    property bool writeOn: false
    // "решить": the owner opens its conflict dialog.
    signal resolveRequested()

    readonly property bool isTicket: !!(markT.ticket && markT.ticket.provider)
    // syncState comes from the model; a hand-built task map (the archive,
    // tests, taskById) may only carry the older flags.
    readonly property string state: !markT.isTicket ? "synced"
        : (markT.ticket.syncState
           || (markT.ticket.gone ? "gone"
               : markT.ticket.unsynced ? (markT.ticket.queued ? "queued" : "error") : "synced"))
    // A move left over while the tracker's switch is off: it only goes out
    // when the user sends it (APP-243).
    readonly property bool unsent: !markT.writeOn && (state === "queued" || state === "error")
    readonly property bool gone: markT.isTicket && (state === "gone" || !!markT.ticket.gone)
    readonly property bool conflict: markT.isTicket && !!markT.ticket.conflict && !gone
    readonly property bool outOfScope: markT.isTicket && !!markT.ticket.outOfScope && !gone
    readonly property bool pending: markT.isTicket && !gone
        && (state === "pushing" || state === "queued" || state === "error")
    readonly property string tracker: markT.trackerName || (markT.isTicket ? markT.ticket.provider : "")
    function _a(href, label) { return "<a href=\"" + href + "\">" + label + "</a>"; }
    readonly property string words: {
        if (!markT.isTicket) return "";
        if (gone)
            return I18n.t("taskcard.mark.gone").arg(tracker) + " · "
                + _a("keep", I18n.t("taskcard.mark.keep")) + " / " + _a("remove", I18n.t("taskcard.mark.remove"));
        const parts = [];
        if (conflict)
            parts.push(I18n.t("taskcard.mark.conflict").arg(tracker) + " · " + _a("resolve", I18n.t("taskcard.mark.resolve")));
        if (pending) {
            if (state === "pushing") parts.push(I18n.t("taskcard.pushing"));
            else if (unsent) parts.push(I18n.t("taskcard.mark.unsent"));
            else if (state === "queued") parts.push(I18n.t("taskcard.mark.waiting"));
            else parts.push(I18n.t("taskcard.mark.refused") + " · " + _a("retry", I18n.t("taskcard.mark.retry")));
        }
        if (outOfScope) parts.push(I18n.t("taskcard.mark.outOfScope").arg(tracker));
        return parts.join(" · ");
    }
    readonly property string tip: gone ? I18n.t("taskcard.gone.tip")
        : conflict ? I18n.t("taskcard.conflict.tip")
        : state === "pushing" ? I18n.t("taskcard.pushing.tip")
        : unsent ? I18n.t("taskcard.unsent.tip")
            + (markT.ticket.syncError ? "\n" + I18n.t("taskcard.syncError").arg(markT.ticket.syncError) : "")
        : state === "queued" ? I18n.t("taskcard.queued.tip")
        : state === "error" ? I18n.t("taskcard.unsynced.tip")
            + (markT.ticket.syncError ? "\n" + I18n.t("taskcard.syncError").arg(markT.ticket.syncError) : "")
        : outOfScope ? I18n.t("taskcard.outOfScope.tip") + (markT.writeOn ? " " + I18n.t("taskcard.outOfScope.noSync") : "")
        : ""
    visible: words.length > 0
    text: words
    textFormat: Text.StyledText
    linkColor: Theme.textMuted
    color: Theme.textDim
    font.family: Theme.fontUi
    font.pixelSize: Theme.fsXs
    onLinkActivated: (link) => {
        if (markT.taskId.length === 0) return;
        if (link === "keep") AppController.keepGoneTicketLocally(markT.taskId);
        else if (link === "remove") AppController.setArchived(markT.taskId, true);
        else if (link === "resolve") markT.resolveRequested();
        else if (link === "retry") AppController.retryTrackerPush(markT.taskId);
    }
    HoverHandler {
        id: markHover
        cursorShape: markT.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    QQC.ToolTip.visible: markHover.hovered && markT.hoveredLink.length === 0 && markT.tip.length > 0
    QQC.ToolTip.delay: 600
    QQC.ToolTip.text: markT.tip
}
