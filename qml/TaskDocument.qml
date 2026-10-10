pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// The task as a document (heap 2, APP-265), in place of the modal editor.
// Opens as a panel over the right of the view; Enter (or ⤢) makes it the
// whole width; Esc goes back to the same task in the view. The title is a
// heading, the properties a row of chips, the body markdown edited where it
// is drawn. Everything saves itself ("Saved"); Ctrl+Z undoes. Done (d) is
// the main action; Delete sits apart at the bottom.
FocusScope {
    id: root
    objectName: "task-doc"

    // The open task's id; empty = closed.
    property string taskId: ""
    property bool full: false
    readonly property bool opened: root.taskId.length > 0
    visible: root.opened

    // Where to put the keyboard when it closes (the view asks back).
    signal closed(string taskId)
    signal internalLinkActivated(string kind, string target)

    // The task as the model has it now. Re-read on every change to the
    // tasks, so a pull or an undo shows here at once.
    property int _rev: 0
    Connections {
        target: AppController.tasks
        function onDataChanged() { root._rev++; }
        function onRowsRemoved() { root._rev++; }
        function onRowsInserted() { root._rev++; }
        function onLayoutChanged() { root._rev++; }
        function onModelReset() { root._rev++; }
    }
    readonly property var task: root._rev >= 0 && root.taskId.length > 0 ? AppController.taskById(root.taskId) : ({})
    readonly property bool _exists: !!(root.task && root.task.id)
    readonly property var _ticket: root._exists && root.task.ticket ? root.task.ticket : ({})
    readonly property bool _isTicket: !!root._ticket.provider
    readonly property var _badge: root._isTicket ? (AppController.providerBadges[root._ticket.provider] || ({})) : ({})

    // ── opening and closing ──
    function open(id) {
        if (root.opened && id !== root.taskId) root.flush();
        root._loadedId = "";
        root._profileId = AppController.activeProfileId;
        root.taskId = id;
        root._load();
        root.forceActiveFocus();
        titleField.forceActiveFocus();
        titleField.cursorPosition = titleField.length;
    }
    // A linked card, or a checklist item that became one: opened here.
    function openOther(id) {
        if (id && id.length > 0 && AppController.taskById(id).id) root.open(id);
    }
    function close() {
        if (!root.opened) return;
        root.flush();
        const id = root.taskId;
        root.taskId = "";
        root.full = false;
        root.closed(id);
    }
    // Write what is typed now (before a switch, a quit, a close).
    function flush() {
        draft.flush();
        body.flush();
        saveTimer.stop();
        if (root._dirtyTitle || root._dirtyBody) root._save();
    }

    // A task deleted while open (another view, a pull): close, and say so.
    // Checked a moment later: a model mid-update can lack the row for an
    // instant (a reset), and that is not a deletion.
    on_ExistsChanged: if (root.opened && !root._exists && root._loadedId.length > 0) Qt.callLater(root._closeIfGone)
    function _closeIfGone() {
        if (!root.opened) return;
        const t = AppController.taskById(root.taskId);
        if (t && t.id) { root._rev++; return; }
        root.taskId = "";
        root.full = false;
        root.closed("");
    }

    // ── loading and saving ──
    property string _loadedId: ""
    // The profile the task was opened in.
    property string _profileId: ""
    property bool _loading: false
    property bool _dirtyTitle: false
    property bool _dirtyBody: false
    property bool _savedShown: false
    function _load() {
        if (!root._exists) return;
        root._loading = true;
        titleField.text = root.task.title;
        body.text = root._isTicket ? AppController.taskLocalNotes(root.taskId) : String(root.task.desc || "");
        root._loadedId = root.taskId;
        root._dirtyTitle = false;
        root._dirtyBody = false;
        root._loading = false;
    }
    // The model changed under us (a pull, an undo): take it in unless the
    // person is typing in that very field.
    on_RevChanged: {
        if (!root._exists || root._loadedId !== root.taskId) return;
        if (!titleField.activeFocus && !root._dirtyTitle && titleField.text !== root.task.title) {
            root._loading = true; titleField.text = root.task.title; root._loading = false;
        }
        const fresh = root._isTicket ? AppController.taskLocalNotes(root.taskId) : String(root.task.desc || "");
        if (!body.editing && !root._dirtyBody && body.text !== fresh) {
            root._loading = true; body.text = fresh; root._loading = false;
        }
        root._changedUnder = body.editing && body.source.text !== fresh && !root._dirtyBody;
    }
    property bool _changedUnder: false
    function _save() {
        if (!root._exists) return;
        saveTimer.stop();
        if (root._dirtyBody && root._isTicket) {
            AppController.setTaskLocalNotes(root.taskId, body.source.text);
            root._dirtyBody = false;
        }
        if (root._dirtyTitle || root._dirtyBody) {
            const d = Object.assign({}, root.task);
            d._originalId = root.taskId;
            if (root._dirtyTitle && titleField.text.trim().length > 0) d.title = titleField.text.trim();
            if (root._dirtyBody) d.desc = body.source.text;
            if (AppController.saveTask(d)) {
                root._dirtyTitle = false;
                root._dirtyBody = false;
            }
        }
        root._savedShown = true;
        savedFade.restart();
    }
    Timer { id: saveTimer; interval: 600; onTriggered: root._save() }
    Timer { id: savedFade; interval: 2500; onTriggered: root._savedShown = false }
    Connections {
        target: Qt.application
        function onAboutToQuit() { root.flush(); }
    }
    // Another profile is about to be opened: what is typed goes into this
    // one's task first (PRES-1), and the document closes with it.
    Connections {
        target: AppController
        function onFlushEditorsRequested() { root.flush(); }
        function onAboutToChangeActiveNote() { if (root.opened) root.flush(); }
        function onActiveProfileChanged() {
            if (!root.opened || root._profileId === AppController.activeProfileId) return;
            root.taskId = "";
            root.full = false;
            root.closed("");
        }
    }

    // ── fields ──
    function _setField(key, value) {
        const d = Object.assign({}, root.task);
        d._originalId = root.taskId;
        d[key] = value;
        AppController.saveTask(d);
        root._savedShown = true;
        savedFade.restart();
    }
    function _statusName(id) {
        const sts = AppController.statuses;
        for (let i = 0; i < sts.length; i++) if (sts[i].id === id) return sts[i].name;
        return id;
    }
    function _valid(d) { return !!(d && d.getTime && !isNaN(d.getTime())); }
    function _when(d, hasTime) {
        if (!root._valid(d)) return "";
        return hasTime ? I18n.fmtDateTime(d, "weekdayDay") : I18n.fmtDate(d, "weekdayDay");
    }
    // Which properties show as chips: a set one always, an empty one only
    // when asked for with "+ property".
    property var _shown: []
    function _has(key) {
        const t = root.task;
        if (!root._exists) return false;
        switch (key) {
        case "scheduled": return root._valid(t.scheduledAt);
        case "due": return root._valid(t.dueAt);
        case "labels": return (t.labels || []).length > 0;
        case "recurrence": return String(t.recurrence || "").length > 0;
        case "estimate": return t.estimateMinutes > 0;
        case "tags": return root._localTags.length > 0;
        }
        return true;
    }
    // My own layer (APP-238/239): both sides of priority and due, my tags.
    readonly property var _tv: root._rev >= 0 && root._exists ? AppController.trackerValues(root.taskId) : ({})
    readonly property bool _mine: root._isTicket && (String(root._tv.myPriority || "").length > 0 || root._valid(root._tv.myDueAt))
    readonly property var _localTags: root._exists && root.task.localTags ? root.task.localTags : []
    property bool _tagsEditing: false
    function _visible(key) { return root._has(key) || root._shown.indexOf(key) >= 0; }
    onTaskIdChanged: { root._shown = []; root._tagsEditing = false; }

    // A date typed into a chip ("tomorrow 15:00", "пт"): read like the input.
    function _applyDate(field, text) {
        const s = String(text || "").trim();
        if (s.length === 0) {
            root._setField(field === "scheduled" ? "scheduledAt" : "dueAt", null);
            return;
        }
        const r = AppController.parseDateTime(s, new Date());
        if (r && r.ok) AppController.rescheduleTask(root.taskId, field, r.start, r.hasTime);
    }

    Keys.onEscapePressed: root.close()
    Keys.onReturnPressed: (e) => {
        if (titleField.activeFocus || body.editing) { e.accepted = false; return; }
        root.full = !root.full;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        Rectangle {
            visible: !root.full
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            width: 1
            color: Theme.border
        }
    }
    // Clicks stay in the panel.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = false }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── the document ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.sp3xl
            Layout.rightMargin: Theme.sp3xl
            Layout.topMargin: Theme.spXl
            spacing: Theme.spLg

            // Tasks / In progress / APP-101          Saved   Esc back
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spSm
                Text {
                    objectName: "task-doc-crumbs"
                    text: I18n.t("sidebar.tasks") + "  /  " + root._statusName(root.task.status || "") + "  /  "
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
                Text {
                    text: root.taskId
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsSm
                }
                Item { Layout.fillWidth: true }
                Text {
                    objectName: "task-doc-saved"
                    visible: root._savedShown
                    text: I18n.t("taskdoc.saved")
                    color: Theme.success
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
                // Done, up here while the side column is folded away.
                PillButton {
                    objectName: "task-doc-done-head"
                    visible: !sideCol.visible
                    text: AppController.statusCategory(root.task.status || "") === "done" ? I18n.t("taskmenu.reopen") : I18n.t("taskmenu.done")
                    shortcutId: "task.done"
                    onClicked: AppController.toggleDone([root.taskId])
                }
                KeyHint { keys: "Esc"; always: true; color: Theme.text; font.weight: Theme.fwTitle }
                Text {
                    text: I18n.t("taskdoc.back")
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
                Rectangle {
                    objectName: "task-doc-full"
                    implicitWidth: Theme.chipHSmall; implicitHeight: Theme.chipHSmall
                    radius: Theme.radiusSm
                    color: fullCA.hovered ? Theme.panel2 : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: root.full ? "⤡" : "⤢"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsMd
                    }
                    ClickArea {
                        id: fullCA
                        label: root.full ? I18n.t("taskdoc.panel") : I18n.t("taskdoc.full")
                        onActivated: root.full = !root.full
                    }
                }
            }

            // A pull changed the text while you were in it: said quietly.
            Text {
                objectName: "task-doc-changed"
                Layout.fillWidth: true
                visible: root._changedUnder
                text: I18n.t("taskdoc.changedUnder")
                color: Theme.warning
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                wrapMode: Text.WordWrap
            }

            QQC.TextArea {
                id: titleField
                objectName: "task-doc-title"
                Layout.fillWidth: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                selectByMouse: true
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fs2xl
                font.weight: Theme.fwHeading
                padding: 0
                background: Item {}
                placeholderText: I18n.t("taskdoc.titlePh")
                placeholderTextColor: Theme.textDim
                onTextChanged: if (!root._loading) { root._dirtyTitle = true; saveTimer.restart(); }
                Keys.onReturnPressed: (e) => { body.focusEditor(); e.accepted = true; }
                Keys.onEnterPressed: (e) => { body.focusEditor(); e.accepted = true; }
                Keys.onEscapePressed: root.close()
                Keys.onDownPressed: (e) => {
                    if (titleField.text.indexOf("\n", titleField.cursorPosition) < 0
                        && titleField.positionAt(titleField.cursorRectangle.x, titleField.cursorRectangle.y + titleField.cursorRectangle.height + 4) >= titleField.length) {
                        body.focusEditor();
                        e.accepted = true;
                    } else e.accepted = false;
                }
            }

            // Status · Priority · When · Due · Labels · Repeat · Estimate · + property
            Flow {
                id: chips
                objectName: "task-doc-chips"
                Layout.fillWidth: true
                spacing: Theme.spSm

                PropertyChip {
                    id: statusChip
                    objectName: "task-doc-status"
                    key: I18n.t("taskdoc.prop.status")
                    value: root._statusName(root.task.status || "")
                    onClicked: statusMenu.popup(statusChip, 0, statusChip.height + Theme.spXs)
                }
                PropertyChip {
                    id: priorityChip
                    objectName: "task-doc-priority"
                    key: root._isTicket ? I18n.t("taskmenu.myPriority") : I18n.t("taskdoc.prop.priority")
                    value: root.task.priority || ""
                    valueColor: Theme.priorityInk(root.task.priority || "P2")
                    onClicked: priorityMenu.popup(priorityChip, 0, priorityChip.height + Theme.spXs)
                }
                DateChip {
                    objectName: "task-doc-scheduled"
                    field: "scheduled"
                    visible: root._visible("scheduled")
                    key: I18n.t("capture.when")
                    value: root._when(root.task.scheduledAt, root.task.scheduledHasTime)
                }
                DateChip {
                    objectName: "task-doc-due"
                    field: "due"
                    visible: root._visible("due")
                    key: root._isTicket ? I18n.t("taskmenu.myDue").replace("…", "") : I18n.t("capture.due")
                    value: root._when(root.task.dueAt, root.task.dueHasTime)
                        // A deadline before the plan: a grey note, not an error.
                        + (root._valid(root.task.dueAt) && root._valid(root.task.scheduledAt)
                           && root.task.dueAt < root.task.scheduledAt ? " · " + I18n.t("taskdoc.dueBeforePlan") : "")
                }
                TextChip {
                    objectName: "task-doc-labels"
                    visible: root._visible("labels")
                    key: I18n.t("capture.label")
                    value: (root.task.labels || []).map(l => "#" + l.id).join(" ")
                    onCommitted: (text) => {
                        const ids = String(text).split(/[\s,]+/).map(w => w.replace(/^#/, "")).filter(w => w.length > 0);
                        const prev = root.task.labels || [];
                        root._setField("labels", ids.map(id => {
                            const was = prev.find(l => l.id === id);
                            return { id: id, color: was ? was.color : "" };
                        }));
                    }
                }
                // My tags (APP-239): mine on any card, never the tracker's.
                PropertyChip {
                    id: tagsChip
                    objectName: "task-doc-tags"
                    visible: root._visible("tags")
                    key: I18n.t("local.tags.key")
                    value: root._localTags.map(l => "#" + l.id).join(" ")
                    onClicked: { root._tagsEditing = true; tagsEditor.open(); }
                }
                PropertyChip {
                    id: recurChip
                    objectName: "task-doc-recurrence"
                    visible: root._visible("recurrence")
                    key: I18n.t("taskdoc.prop.repeat")
                    value: String(root.task.recurrence || "").length > 0 ? I18n.t("taskdoc.repeat." + String(root.task.recurrence).replace("every:", "").split(":")[0]) : ""
                    onClicked: recurMenu.popup(recurChip, 0, recurChip.height + Theme.spXs)
                }
                TextChip {
                    objectName: "task-doc-estimate"
                    visible: root._visible("estimate")
                    key: I18n.t("capture.estimate")
                    value: root.task.estimateMinutes > 0 ? I18n.fmtMinutes(root.task.estimateMinutes) : ""
                    onCommitted: (text) => {
                        const t = String(text).trim();
                        const m = t.length === 0 ? 0
                                : /^\d+$/.test(t) ? parseInt(t)
                                : AppController.captureParse("x ~" + t.replace(/^~/, "")).estimateMinutes;
                        root._setField("estimateMinutes", m);
                    }
                }
                PropertyChip {
                    id: addChip
                    objectName: "task-doc-add"
                    add: true
                    visible: ["scheduled", "due", "labels", "tags", "recurrence", "estimate"].some(k => !root._visible(k))
                    value: I18n.t("taskdoc.addProp")
                    onClicked: addMenu.popup(addChip, 0, addChip.height + Theme.spXs)
                }
            }

            // Mine over the tracker's (APP-238): what the tracker says, said
            // quietly, and "changed in the tracker" when it moved since I
            // set mine — never overwriting mine. Reset is one action.
            RowLayout {
                objectName: "task-doc-tracker-values"
                Layout.fillWidth: true
                visible: root._mine
                spacing: Theme.spMd
                Text {
                    objectName: "task-doc-tracker-values-text"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: {
                        const tv = root._tv;
                        const bits = [];
                        if (String(tv.myPriority || "").length > 0) bits.push(String(tv.trackerPriority || "—"));
                        if (root._valid(tv.myDueAt))
                            bits.push(root._valid(tv.trackerDueAt) ? I18n.t("local.tracker.due").arg(root._when(tv.trackerDueAt, tv.trackerDueHasTime))
                                                                   : I18n.t("local.tracker.noDue"));
                        return I18n.t("local.tracker.says").arg(root._badge.name || root._ticket.provider || "").arg(bits.join(", "))
                            + (tv.priorityChanged || tv.dueChanged ? " · " + I18n.t("local.trackerChanged") : "");
                    }
                    color: root._tv.priorityChanged || root._tv.dueChanged ? Theme.signalNow : Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                }
                Text {
                    objectName: "task-doc-keep-mine"
                    visible: !!(root._tv.priorityChanged || root._tv.dueChanged)
                    text: I18n.t("local.tracker.keepMine")
                    color: keepCA.hovered ? Theme.text : Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                    ClickArea { id: keepCA; label: parent.text; onActivated: AppController.acknowledgeTrackerChange(root.taskId) }
                }
                Text {
                    objectName: "task-doc-reset-tracker"
                    text: I18n.t("local.tracker.reset")
                    color: resetCA.hovered ? Theme.text : Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                    ClickArea { id: resetCA; label: parent.text; onActivated: AppController.resetToTracker(root.taskId, "") }
                }
            }

            TaskLocalTags {
                id: tagsEditor
                Layout.fillWidth: true
                visible: root._tagsEditing
                taskId: root.taskId
                rev: root._rev
                tags: root._localTags
                onDone: root._tagsEditing = false
            }

            // The tracker's text, read-only, above my notes (APP-237).
            ColumnLayout {
                Layout.fillWidth: true
                visible: root._isTicket && String(root.task.desc || "").length > 0
                spacing: Theme.spXs
                Text {
                    text: I18n.t("taskdoc.fromTracker").arg(root._badge.name || root._ticket.provider || "")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                }
                Text {
                    objectName: "task-doc-tracker-body"
                    Layout.fillWidth: true
                    Layout.maximumHeight: Theme.px(220)
                    clip: true
                    text: String(root.task.desc || "")
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
                    onLinkActivated: (link) => Qt.openUrlExternally(link)
                }
            }
            // My notes on a tracker card: never sent, never pulled over.
            RowLayout {
                visible: root._isTicket
                spacing: Theme.spMd
                Text {
                    text: I18n.t("taskdoc.myNotes")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                }
                // A long notepad copied into Knowledge, naming the task.
                Text {
                    objectName: "task-doc-notes-to-note"
                    visible: body.text.trim().length > 0
                    text: I18n.t("local.notes.toNote")
                    color: toNoteCA.hovered ? Theme.text : Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                    ClickArea {
                        id: toNoteCA
                        label: parent.text
                        onActivated: {
                            root.flush();
                            const title = AppController.copyTaskNotesToNote(root.taskId);
                            if (title.length > 0) root.internalLinkActivated("note", title);
                        }
                    }
                }
            }

            MdBlockEditor {
                id: body
                objectName: "task-doc-body"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: -Theme.px(24)
                Layout.rightMargin: -Theme.px(24)
                placeholder: I18n.t("taskdoc.bodyPh")
                onEdited: if (!root._loading) { root._dirtyBody = true; saveTimer.restart(); }
                onEscaped: root.close()
                onInternalLinkActivated: (kind, target) => root.internalLinkActivated(kind, target)
            }

            // My plan for the task (APP-236): its own scroll when it is long,
            // so the text above keeps its room.
            QQC.ScrollView {
                id: planScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(checklist.implicitHeight, root.height * 0.4)
                contentWidth: availableWidth
                clip: true
                TaskLocalChecklist {
                    id: checklist
                    width: planScroll.availableWidth
                    taskId: root.taskId
                    rev: root._rev
                    onOpenTask: (id) => root.openOther(id)
                }
            }

            // The answer I am writing for the ticket (APP-241).
            TaskCommentDraft {
                id: draft
                Layout.fillWidth: true
                visible: root._isTicket
                taskId: root._isTicket ? root.taskId : ""
                rev: root._rev
                trackerName: root._badge.name || root._ticket.provider || ""
            }

            // Delete, apart from everything else.
            Text {
                objectName: "task-doc-delete"
                Layout.bottomMargin: Theme.spLg
                text: root._isTicket ? I18n.t("taskmenu.hide") : I18n.t("taskdoc.delete")
                color: delCA.hovered ? Theme.danger : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                ClickArea {
                    id: delCA
                    label: parent.text
                    onActivated: {
                        const id = root.taskId;
                        root.taskId = "";
                        root.full = false;
                        AppController.deleteTask(id);
                        root.closed("");
                    }
                }
            }
        }

        // ── the side: code, mentions, time, history, Done ──
        Rectangle {
            id: sideCol
            objectName: "task-doc-side"
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.px(300)
            visible: root.width >= Theme.px(820)
            color: Theme.bg
            Rectangle {
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: 1
                color: Theme.border
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.sp2xl
                anchors.topMargin: Theme.sp3xl
                spacing: Theme.spLg

                // Code: hidden whole when there is nothing to say.
                ColumnLayout {
                    objectName: "task-doc-code"
                    visible: String(root.task.branch || "").length > 0 || root._isTicket
                    spacing: Theme.spSm
                    SectionHeader { title: I18n.t("taskdoc.code") }
                    SideRow {
                        visible: String(root.task.branch || "").length > 0
                        label: I18n.t("taskdoc.branch")
                        value: String(root.task.branch || "")
                        mono: true
                    }
                    SideRow {
                        visible: root._isTicket
                        label: I18n.t("taskdoc.tracker")
                        value: (root._badge.name || root._ticket.provider || "") + " " + (root.task.externalKey || "") + " ↗"
                        link: String(root.task.externalUrl || "")
                    }
                }

                // Links drawn by hand: related, waits on, blocks (APP-240).
                TaskRelations {
                    Layout.fillWidth: true
                    taskId: root.taskId
                    rev: root._rev
                    onOpenTask: (id) => root.openOther(id)
                }

                // Mentioned in: notes that name the task.
                ColumnLayout {
                    objectName: "task-doc-mentions"
                    readonly property var notes: root._rev >= 0 ? AppController.notesMentioningTask(root.taskId) : []
                    visible: notes.length > 0
                    spacing: Theme.spSm
                    SectionHeader { title: I18n.t("taskdoc.mentioned") }
                    Repeater {
                        model: parent.notes
                        delegate: ColumnLayout {
                            id: mention
                            required property var modelData
                            spacing: 0
                            Text {
                                text: mention.modelData.title
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsSm
                                font.weight: Theme.fwTitle
                                ClickArea {
                                    label: mention.modelData.title
                                    onActivated: root.internalLinkActivated("note", mention.modelData.title)
                                }
                            }
                            Text {
                                text: I18n.t("taskdoc.noteOn").arg(I18n.fmtDate(mention.modelData.updated, "dayMonth"))
                                color: Theme.textDim
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsXs
                            }
                        }
                    }
                }

                // Time: the timer and what was tracked, against the estimate.
                ColumnLayout {
                    id: timeBox
                    objectName: "task-doc-time"
                    spacing: Theme.spSm
                    property int _tick: 0
                    Timer { interval: 1000; repeat: true; running: !!root.task.isTiming; onTriggered: timeBox._tick++ }
                    SectionHeader { title: I18n.t("taskdoc.time") }
                    RowLayout {
                        spacing: Theme.spMd
                        Text {
                            objectName: "task-doc-timer"
                            visible: !!root.task.isTiming
                            text: {
                                const s = timeBox._tick >= 0 ? AppController.elapsedSecondsFor(root.taskId) : 0;
                                const m = Math.floor(s / 60);
                                return Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0");
                            }
                            color: Theme.signalNow
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsLg
                        }
                        PillButton {
                            objectName: "task-doc-timer-toggle"
                            text: root.task.isTiming ? I18n.t("taskdoc.pause") : I18n.t("taskcard.startTimer")
                            onClicked: root.task.isTiming ? AppController.stopTaskTimer(root.taskId) : AppController.startTaskTimer(root.taskId)
                        }
                    }
                    Text {
                        visible: (root.task.trackedSeconds || 0) > 0 || root.task.estimateMinutes > 0
                        text: I18n.t("taskdoc.tracked").arg(I18n.fmtMinutes(Math.round((root.task.trackedSeconds || 0) / 60)))
                              + (root.task.estimateMinutes > 0 ? " " + I18n.t("taskdoc.ofEstimate").arg(I18n.fmtMinutes(root.task.estimateMinutes)) : "")
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsXs
                    }
                    // Session by session (APP-251).
                    TaskSessions {
                        Layout.fillWidth: true
                        taskId: root.taskId
                        rev: root._rev
                    }
                }

                // History: what is known — the last column change.
                ColumnLayout {
                    objectName: "task-doc-history"
                    visible: root._valid(root.task.statusChangedAt)
                    spacing: Theme.spSm
                    SectionHeader { title: I18n.t("taskdoc.history") }
                    Text {
                        text: root._valid(root.task.statusChangedAt)
                              ? I18n.fmtDateTime(root.task.statusChangedAt, "dayMonth") + " · → " + root._statusName(root.task.status || "") : ""
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsXs
                    }
                }

                Item { Layout.fillHeight: true }

                // Done (d): the main action.
                PillButton {
                    objectName: "task-doc-done"
                    Layout.fillWidth: true
                    primary: true
                    text: AppController.statusCategory(root.task.status || "") === "done" ? I18n.t("taskmenu.reopen") : I18n.t("taskmenu.done")
                    shortcutId: "task.done"
                    onClicked: AppController.toggleDone([root.taskId])
                }
            }
        }
    }

    // ── menus ──
    AppMenu {
        id: statusMenu
        Instantiator {
            model: AppController.statuses
            delegate: AppMenuItem {
                required property var modelData
                text: modelData.name
                marked: modelData.id === root.task.status
                note: modelData.id === root.task.status ? I18n.t("taskdoc.now") : ""
                onTriggered: AppController.moveTaskTo(root.taskId, modelData.id, "")
            }
            onObjectAdded: (i, o) => statusMenu.insertItem(i, o)
            onObjectRemoved: (i, o) => statusMenu.removeItem(o)
        }
    }
    AppMenu {
        id: priorityMenu
        Instantiator {
            model: ["P0", "P1", "P2", "P3"]
            delegate: AppMenuItem {
                required property string modelData
                text: modelData
                marked: modelData === root.task.priority
                onTriggered: AppController.setTaskPriority(root.taskId, modelData)
            }
            onObjectAdded: (i, o) => priorityMenu.insertItem(i, o)
            onObjectRemoved: (i, o) => priorityMenu.removeItem(o)
        }
    }
    AppMenu {
        id: recurMenu
        Instantiator {
            model: ["", "every:day", "every:weekday", "every:week", "every:month"]
            delegate: AppMenuItem {
                required property string modelData
                text: modelData === "" ? I18n.t("taskdoc.repeat.none") : I18n.t("taskdoc.repeat." + modelData.replace("every:", ""))
                marked: String(root.task.recurrence || "") === modelData
                onTriggered: root._setField("recurrence", modelData)
            }
            onObjectAdded: (i, o) => recurMenu.insertItem(i, o)
            onObjectRemoved: (i, o) => recurMenu.removeItem(o)
        }
    }
    AppMenu {
        id: addMenu
        objectName: "task-doc-add-menu"
        Instantiator {
            model: ["scheduled", "due", "labels", "tags", "recurrence", "estimate"]
            delegate: AppMenuItem {
                required property string modelData
                visible: !root._visible(modelData)
                height: visible ? implicitHeight : 0
                text: I18n.t("taskdoc.add." + modelData)
                onTriggered: {
                    root._shown = root._shown.concat([modelData]);
                    if (modelData === "tags") { root._tagsEditing = true; Qt.callLater(tagsEditor.open); }
                }
            }
            onObjectAdded: (i, o) => addMenu.insertItem(i, o)
            onObjectRemoved: (i, o) => addMenu.removeItem(o)
        }
    }

    // A chip whose value is typed: a click turns it into a field.
    component TextChip: PropertyChip {
        id: tc
        signal committed(string text)
        property bool _editing: false
        onClicked: { tc._editing = true; tcField.text = tc.value; tcField.forceActiveFocus(); tcField.selectAll(); }
        QQC.TextField {
            id: tcField
            visible: tc._editing
            anchors.fill: parent
            leftPadding: Theme.spMd
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            color: Theme.text
            background: Rectangle { radius: Theme.radiusMd; color: Theme.panel2; border.color: Theme.focusRing; border.width: 1 }
            onAccepted: { tc._editing = false; tc.committed(tcField.text); }
            onActiveFocusChanged: if (!activeFocus && tc._editing) { tc._editing = false; tc.committed(tcField.text); }
            Keys.onEscapePressed: tc._editing = false
        }
    }
    // A date chip: typed words ("завтра 15:00", "пт"), read like the input.
    component DateChip: TextChip {
        property string field: ""
        onCommitted: (text) => root._applyDate(field, text)
    }
    component SideRow: RowLayout {
        id: sr
        property string label: ""
        property string value: ""
        property string link: ""
        property bool mono: false
        spacing: Theme.spLg
        Text {
            text: sr.label
            Layout.preferredWidth: Theme.px(60)
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }
        Text {
            Layout.fillWidth: true
            text: sr.value
            elide: Text.ElideRight
            color: Theme.text
            font.family: sr.mono ? Theme.fontMono : Theme.fontUi
            font.pixelSize: Theme.fsSm
            font.underline: sr.link.length > 0
            ClickArea {
                enabled: sr.link.length > 0
                label: sr.value
                onActivated: Qt.openUrlExternally(sr.link)
            }
        }
    }
}
