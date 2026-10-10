pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// The task as a document (heap 2, APP-265; sheets H2-Task / Q-Task), in
// place of the modal editor. Opens as a panel on the right of the view (the
// sheets' "панель справа", the same as a meeting's); Enter or the expand
// icon makes it replace the whole content area, header included, with the
// breadcrumb "Задачи / В работе / APP-101" on top (DG-060). Esc goes back to
// the same task in the view. The title is a heading, the properties a row of
// chips, the body markdown edited where it is drawn, with the plan (my
// checklist) under it. Everything saves itself; Ctrl+Z undoes. The meta
// column: Код, Упоминается в, Время, История and Готово (d).
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

    // The quiet look (Q-Task): outline lowercase chips, plain meta lines, a
    // small outline Готово under История (DG-065).
    readonly property bool _quiet: !Style.fills

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
    Connections {
        target: AppController
        function onTaskHistoryChanged(taskId) { if (taskId === root.taskId) root._rev++; }
    }
    readonly property var task: root._rev >= 0 && root.taskId.length > 0 ? AppController.taskById(root.taskId) : ({})
    readonly property bool _exists: !!(root.task && root.task.id)
    readonly property var _ticket: root._exists && root.task.ticket ? root.task.ticket : ({})
    readonly property bool _isTicket: !!root._ticket.provider
    readonly property var _badge: root._isTicket ? (AppController.providerBadges[root._ticket.provider] || ({})) : ({})

    // ── opening and closing ──
    function open(id, intoTitle) {
        if (root.opened && id !== root.taskId) root.flush();
        root._loadedId = "";
        root._profileId = AppController.activeProfileId;
        root.taskId = id;
        root._load();
        if (intoTitle === true) root.focusTitle();
        else root.takeFocus();
    }
    // Where the keyboard goes in the document: a task with no title yet into
    // its title; any other onto the document, where its keys work at once —
    // d is Done, / the insert menu, i the title, Esc back. Opened into the
    // title, "/" from the hint and "d" from the button were typed into it
    // (IDIOT-DOC-10, the owner's "/" report).
    function takeFocus() {
        if (String(titleField.text).trim().length === 0) root.focusTitle();
        else root.focusDocument();
    }
    // The document itself, not whatever field inside it had focus last: a
    // FocusScope hands the keyboard back to that child, a hidden chip field
    // included (IDIOT-DOC-6). The sink sits in the scope; the keys it takes
    // travel up to the document's own handlers.
    function focusDocument() {
        docFocus.forceActiveFocus();
    }
    Item {
        id: docFocus
        objectName: "task-doc-focus"
        width: 0
        height: 0
    }
    function focusTitle() {
        titleField.forceActiveFocus();
        titleField.cursorPosition = titleField.length;
    }
    // "/" on the document: a new line at the end and the insert menu on it,
    // as the hint under the text says.
    function slashInsert() {
        if (root._isTicket && body.readOnly) return;
        body.appendBlock();
        Qt.callLater(body.openSlashMenu);
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
        if (root._draft) root._draft.flush();
        body.flush();
        saveTimer.stop();
        if (root._dirtyTitle || root._dirtyBody) root._save();
    }
    // The plan (my checklist) and the links, asked for from "+ свойство".
    function startPlan() { if (root._plan) root._plan.startAdding(); }
    function startLink(kind) { relations.startAdding(kind); }

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
    function _load() {
        if (!root._exists) return;
        root._loading = true;
        titleField.text = root.task.title;
        body.load(root._isTicket ? AppController.taskLocalNotes(root.taskId) : String(root.task.desc || ""));
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
        if (!body.editing && !root._dirtyBody && body.source.text !== fresh) {
            root._loading = true; body.load(fresh); root._loading = false;
        }
        root._changedUnder = body.editing && body.source.text !== fresh && !root._dirtyBody;
    }
    property bool _changedUnder: false
    property real _doneClickAt: 0
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
            // One line, and not a pasted page (IDIOT-DOC-14): line breaks
            // become spaces, the title stops at 500 characters.
            const title = root._cleanTitle(titleField.text);
            if (root._dirtyTitle && title.length > 0) d.title = title;
            if (root._dirtyBody) d.desc = body.source.text;
            if (AppController.saveTask(d)) {
                root._dirtyTitle = false;
                root._dirtyBody = false;
            }
        }
    }
    Timer { id: saveTimer; interval: 600; onTriggered: root._save() }
    function _cleanTitle(t) { return String(t || "").replace(/\s*\n\s*/g, " ").trim().substring(0, 500); }
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
    }
    function _statusName(id) {
        const sts = AppController.statuses;
        for (let i = 0; i < sts.length; i++) if (sts[i].id === id) return sts[i].name;
        return id;
    }
    // "Статус" in bold, "статус" in quiet (the sheets' chip keys).
    function _key(s) {
        const t = String(s || "");
        if (t.length === 0) return t;
        return root._quiet ? t.toLowerCase() : t.charAt(0).toUpperCase() + t.slice(1);
    }
    function _valid(d) { return !!(d && d.getTime && !isNaN(d.getTime())); }
    function _dayDiff(d) {
        const a = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        const n = new Date();
        const b = new Date(n.getFullYear(), n.getMonth(), n.getDate());
        return Math.round((a - b) / 86400000);
    }
    // "сегодня", "завтра", "вчера", else "9 окт".
    function _relDay(d) {
        const k = root._dayDiff(d);
        if (k === 0) return I18n.t("common.today").toLowerCase();
        if (k === 1) return I18n.t("common.tomorrow").toLowerCase();
        if (k === -1) return I18n.t("common.yesterday").toLowerCase();
        return I18n.fmtDate(d, "dayMonth");
    }
    // "сегодня 17:00–18:30" (the estimate gives the end), "завтра".
    function _when(d, hasTime, minutes) {
        if (!root._valid(d)) return "";
        if (!hasTime) return root._relDay(d);
        let s = root._relDay(d) + " " + I18n.fmtTime(d);
        if (minutes > 0) s += "–" + I18n.fmtTime(new Date(d.getTime() + minutes * 60000));
        return s;
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
    // A single-letter key reads as the keymap writes it ("d", "t").
    function _keyOf(id) {
        const k = AppController.shortcutText(id);
        return k.length === 1 ? k.toLowerCase() : k;
    }
    readonly property bool _done: AppController.statusCategory(root.task.status || "") === "done"

    // ── history (DG-061): the three newest facts, said shortly ──
    readonly property var _history: root._rev >= 0 && root._exists ? AppController.taskHistory(root.taskId) : []
    function _histWhen(at, withTime) {
        const d = new Date(at);
        if (!root._valid(d)) return "";
        const day = root._relDay(d);
        return withTime && root._dayDiff(d) === 0 ? day + " " + I18n.fmtTime(d) : day;
    }
    function _isoDay(s) {
        const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(s || ""));
        return m ? I18n.fmtDate(new Date(+m[1], +m[2] - 1, +m[3]), "dayMonth") : String(s || "—");
    }
    function _histText(e) {
        const from = root._badge.name || root._ticket.provider || "";
        switch (e.kind) {
        case "created":
            if (e.sync && from.length > 0) return I18n.t(root._quiet ? "taskdoc.hist.fromQuiet" : "taskdoc.hist.createdFrom").arg(from);
            return I18n.t("taskdoc.hist.created");
        case "status":
            return root._quiet ? root._statusName(e.to).toLowerCase() : "→ " + root._statusName(e.to);
        case "pushed": return I18n.t("taskdoc.hist.pushed").arg(root._statusName(e.to));
        case "due": return I18n.t("taskdoc.hist.due").arg(String(e.to || "").length > 0 ? root._isoDay(e.to) : "—");
        case "scheduled": return I18n.t("taskdoc.hist.scheduled").arg(String(e.to || "").length > 0 ? root._isoDay(e.to) : "—");
        case "priority": return I18n.t("taskdoc.hist.priority").arg(String(e.to || "—"));
        case "title": return I18n.t("taskdoc.hist.title");
        }
        return String(e.kind);
    }
    readonly property var _historyRows: {
        const out = [];
        const h = root._history || [];
        for (let i = 0; i < h.length && out.length < 3; i++)
            out.push(root._histWhen(h[i].at, !root._quiet && h[i].kind === "status") + " · " + root._histText(h[i]));
        // Nothing recorded yet: the last column change, which is known.
        if (out.length === 0 && root._valid(root.task.statusChangedAt))
            out.push(root._histWhen(root.task.statusChangedAt, !root._quiet) + " · "
                     + (root._quiet ? root._statusName(root.task.status || "").toLowerCase() : "→ " + root._statusName(root.task.status || "")));
        return out;
    }

    // ── code (DG-061): branch, PR + CI, tracker ──
    readonly property int _prNumber: root._exists ? (root.task.prNumber || 0) : 0
    readonly property string _prChecks: root._exists ? String(root.task.prChecks || "") : ""
    readonly property string _trackerLabel: root._isTicket
        ? ((root._badge.name || root._ticket.provider || "") + " " + (root.task.externalKey || "")).trim() : ""

    // The plan and the comment draft live in the body's tail (see below).
    readonly property Item _tail: body.tailItem
    readonly property var _plan: root._tail ? (root._tail as DocTail).plan : null
    readonly property var _draft: root._tail ? (root._tail as DocTail).draft : null

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

    // The sheets' column: 780 px of text (760 quiet), then the meta column.
    readonly property int _docMax: root._quiet ? Theme.px(760) : Theme.px(780)
    readonly property int _padX: root._quiet ? Theme.px(48) : Theme.px(40)

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── the document ──
        ColumnLayout {
            Layout.fillWidth: true
            // The sheet's 780 includes its padding.
            Layout.maximumWidth: root.full ? root._docMax - 2 * root._padX : -1
            Layout.fillHeight: true
            Layout.leftMargin: root._padX
            Layout.rightMargin: root._padX
            Layout.topMargin: root._quiet ? Theme.px(40) : Theme.px(22)
            spacing: 0

            // Задачи / В работе / APP-101          Сохранено  Esc назад  ⤢
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.px(26)
                Layout.preferredHeight: Theme.chipHSmall
                spacing: Theme.spMd
                Text {
                    objectName: "task-doc-crumbs-root"
                    text: I18n.t("sidebar.tasks")
                    color: crumbCA.hovered ? Theme.text : (root._quiet ? Theme.textMuted : Theme.text)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    ClickArea { id: crumbCA; label: parent.text; onActivated: root.close() }
                }
                Text {
                    objectName: "task-doc-crumbs"
                    text: "/" + (root._quiet ? "" : "  " + root._statusName(root.task.status || "") + "   /")
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
                // Saved, or saving while the typing settles.
                Text {
                    objectName: "task-doc-saved"
                    readonly property bool pending: saveTimer.running || root._dirtyTitle || root._dirtyBody
                    text: pending ? I18n.t("taskdoc.saving") : (root._quiet ? I18n.t("taskdoc.saved").toLowerCase() : I18n.t("taskdoc.saved"))
                    color: pending || root._quiet ? Theme.textMuted : Theme.success
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
                Row {
                    visible: Style.keyHints
                    spacing: Theme.spXs
                    Text {
                        anchors.baseline: backText.baseline
                        text: "Esc"
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsSm
                        font.weight: Theme.fwHeading
                    }
                    Text {
                        id: backText
                        text: I18n.t("taskdoc.back")
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                    }
                }
                // Panel ↔ the whole content area (Enter).
                Item {
                    objectName: "task-doc-full"
                    implicitWidth: Theme.chipHSmall; implicitHeight: Theme.chipHSmall
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSm
                        color: fullCA.hovered ? Theme.panel2 : "transparent"
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: root.full ? "collapse" : "expand"
                        color: fullCA.hovered ? Theme.text : Theme.textMuted
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
                Layout.bottomMargin: Theme.spMd
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
                Layout.bottomMargin: root._quiet ? Theme.px(14) : Theme.px(16)
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                selectByMouse: true
                color: Theme.text
                font.family: Theme.fontUi
                // 32 px bold, 28 px quiet (H2-Task / Q-Task).
                font.pixelSize: Theme.typeStep(root._quiet ? 7 : 8)
                font.weight: root._quiet ? Theme.fwTitle : Theme.fwHeading
                padding: 0
                // Basic binds its own side padding; the title shares the
                // chips' left edge (R3-037).
                leftPadding: 0
                rightPadding: 0
                background: Item {}
                placeholderText: I18n.t("taskdoc.titlePh")
                placeholderTextColor: Theme.textDim
                onTextChanged: if (!root._loading) { root._dirtyTitle = true; saveTimer.restart(); }
                Keys.onReturnPressed: (e) => { body.focusEditor(); e.accepted = true; }
                Keys.onEnterPressed: (e) => { body.focusEditor(); e.accepted = true; }
                // Tab moves on, as in any form; it typed a tab into the
                // title (IDIOT-DOC-13).
                Keys.onTabPressed: (e) => { titleField.nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason); e.accepted = true; }
                Keys.onBacktabPressed: (e) => { titleField.nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason); e.accepted = true; }
                Keys.onEscapePressed: root.close()
                Keys.onDownPressed: (e) => {
                    if (titleField.text.indexOf("\n", titleField.cursorPosition) < 0
                        && titleField.positionAt(titleField.cursorRectangle.x, titleField.cursorRectangle.y + titleField.cursorRectangle.height + 4) >= titleField.length) {
                        body.focusEditor();
                        e.accepted = true;
                    } else e.accepted = false;
                }
            }

            // Статус · Приоритет · Когда · Срок · Метки · … · + свойство
            Flow {
                id: chips
                objectName: "task-doc-chips"
                Layout.fillWidth: true
                Layout.bottomMargin: root._quiet ? Theme.px(30) : Theme.px(26)
                spacing: Theme.spSm

                PropertyChip {
                    id: statusChip
                    objectName: "task-doc-status"
                    key: root._key(I18n.t("taskdoc.prop.status"))
                    value: root._quiet ? root._statusName(root.task.status || "").toLowerCase() : root._statusName(root.task.status || "")
                    ring: AppController.statusCategory(root.task.status || "")
                    onClicked: statusMenu.popup(statusChip, 0, statusChip.height + Theme.spXs)
                }
                PropertyChip {
                    id: priorityChip
                    objectName: "task-doc-priority"
                    key: root._key(root._isTicket ? I18n.t("taskmenu.myPriority") : I18n.t("taskdoc.prop.priority"))
                    value: root.task.priority || ""
                    valueColor: Style.urgency ? Theme.priorityInk(root.task.priority || "P2") : Theme.text
                    onClicked: priorityMenu.popup(priorityChip, 0, priorityChip.height + Theme.spXs)
                }
                DateChip {
                    objectName: "task-doc-scheduled"
                    field: "scheduled"
                    visible: root._visible("scheduled")
                    key: root._key(I18n.t("capture.when"))
                    value: root._when(root.task.scheduledAt, root.task.scheduledHasTime, root.task.estimateMinutes || 0)
                }
                DateChip {
                    objectName: "task-doc-due"
                    field: "due"
                    visible: root._visible("due")
                    key: root._key(root._isTicket ? I18n.t("taskmenu.myDue").replace("…", "") : I18n.t("capture.due"))
                    value: root._when(root.task.dueAt, root.task.dueHasTime, 0)
                        // A deadline before the plan: a grey note, not an error.
                        + (root._valid(root.task.dueAt) && root._valid(root.task.scheduledAt)
                           && root.task.dueAt < root.task.scheduledAt ? " · " + I18n.t("taskdoc.dueBeforePlan") : "")
                    // Due today or tomorrow: the "soon" signal (bold only).
                    valueColor: root._valid(root.task.dueAt) && !root._done && root._dayDiff(root.task.dueAt) <= 1
                                ? (root._dayDiff(root.task.dueAt) < 0 ? Theme.signalUrgent : Theme.signalNow) : Theme.text
                }
                TextChip {
                    objectName: "task-doc-labels"
                    visible: root._visible("labels")
                    key: root._key(I18n.t("taskdoc.prop.labels"))
                    value: (root.task.labels || []).map(l => l.id).join(" ")
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
                    key: root._key(I18n.t("local.tags.key"))
                    value: root._localTags.map(l => "#" + l.id).join(" ")
                    onClicked: { root._tagsEditing = true; tagsEditor.open(); }
                }
                PropertyChip {
                    id: recurChip
                    objectName: "task-doc-recurrence"
                    visible: root._visible("recurrence")
                    key: root._key(I18n.t("taskdoc.prop.repeat"))
                    value: String(root.task.recurrence || "").length > 0 ? I18n.t("taskdoc.repeat." + String(root.task.recurrence).replace("every:", "").split(":")[0]) : ""
                    onClicked: recurMenu.popup(recurChip, 0, recurChip.height + Theme.spXs)
                }
                TextChip {
                    objectName: "task-doc-estimate"
                    visible: root._visible("estimate")
                    key: root._key(I18n.t("capture.estimate"))
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
                Layout.bottomMargin: Theme.spLg
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
                            bits.push(root._valid(tv.trackerDueAt) ? I18n.t("local.tracker.due").arg(root._when(tv.trackerDueAt, tv.trackerDueHasTime, 0))
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
                Layout.bottomMargin: Theme.spLg
                visible: root._tagsEditing
                taskId: root.taskId
                rev: root._rev
                tags: root._localTags
                onDone: root._tagsEditing = false
            }

            // The tracker's text, read-only, above my notes (APP-237).
            ColumnLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spLg
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

            // The body, then my plan under it and the slash hint (DG-062),
            // all in one scroll.
            MdBlockEditor {
                id: body
                objectName: "task-doc-body"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: -Theme.px(24)
                Layout.rightMargin: -Theme.px(24)
                placeholder: I18n.t("taskdoc.bodyPh")
                menuTitle: I18n.t("textmenu.title.taskBody")
                paragraphLineHeight: 1.65
                wholeDocument: true
                onEdited: if (!root._loading) { root._dirtyBody = true; saveTimer.restart(); }
                onEscaped: root.close()
                onInternalLinkActivated: (kind, target) => root.internalLinkActivated(kind, target)
                tail: Component { DocTail {} }
            }

            // Done, under the text while the meta column is folded away.
            DoneButton {
                objectName: "task-doc-done-bottom"
                visible: !sideCol.visible
                Layout.bottomMargin: Theme.sp2xl
                Layout.fillWidth: !root._quiet
            }
        }

        // ── the meta column: code, mentions, time, history, Done ──
        Rectangle {
            id: sideCol
            objectName: "task-doc-side"
            Layout.fillHeight: true
            Layout.preferredWidth: root._quiet ? Theme.px(280) : Theme.px(300)
            visible: root.width >= Theme.px(820)
            color: Theme.bg
            Rectangle {
                visible: !root._quiet
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: 1
                color: Theme.border
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: root._quiet ? Theme.spSm : Theme.sp3xl
                anchors.rightMargin: root._quiet ? Theme.px(28) : Theme.sp3xl
                anchors.bottomMargin: Theme.sp3xl
                anchors.topMargin: root._quiet ? Theme.px(96) : Theme.px(64)
                spacing: root._quiet ? Theme.sp3xl : Theme.px(26)

                // Код: hidden whole when there is nothing to say.
                ColumnLayout {
                    objectName: "task-doc-code"
                    // A layout in a layout fills by default; these sit at their
                    // own height so the column reads top-down (R2-013).
                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    visible: String(root.task.branch || "").length > 0 || root._isTicket || root._prNumber > 0
                    spacing: root._quiet ? Theme.spXs : Theme.spMd
                    MetaHead { text: I18n.t("taskdoc.code") }
                    SideRow {
                        objectName: "task-doc-branch"
                        visible: String(root.task.branch || "").length > 0
                        label: I18n.t("taskdoc.branch")
                        value: String(root.task.branch || "")
                        mono: true
                    }
                    // PR #482  CI ✓ (bold) / "PR #482 · CI прошёл" (quiet).
                    SideRow {
                        id: prRow
                        objectName: "task-doc-pr"
                        visible: root._prNumber > 0
                        label: I18n.t("taskdoc.pr")
                        value: root._quiet ? "PR #" + root._prNumber
                                             + (root._prChecks.length > 0 ? " · " + I18n.t("taskdoc.ci." + root._prChecks) : "")
                                           : "#" + root._prNumber
                        link: root._quiet ? "" : String(root.task.prUrl || "")
                        Row {
                            visible: !root._quiet && root._prChecks.length > 0
                            spacing: Theme.sp2xs
                            readonly property color ink: root._prChecks === "passing" ? Theme.success
                                                       : root._prChecks === "failing" ? Theme.danger : Theme.textMuted
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "CI"
                                color: parent.ink
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsSm
                            }
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: root._prChecks === "passing" ? "check" : root._prChecks === "failing" ? "close" : "timer"
                                size: Theme.iconSize - 2
                                color: parent.ink
                            }
                        }
                    }
                    SideRow {
                        objectName: "task-doc-tracker"
                        visible: root._isTicket
                        label: I18n.t("taskdoc.tracker")
                        value: root._trackerLabel
                        link: String(root.task.externalUrl || "")
                        arrow: !root._quiet
                    }
                }

                // Упоминается в: notes that name the task.
                ColumnLayout {
                    objectName: "task-doc-mentions"
                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    readonly property var notes: root._rev >= 0 ? AppController.notesMentioningTask(root.taskId) : []
                    visible: notes.length > 0
                    spacing: root._quiet ? Theme.spXs : Theme.spMd
                    MetaHead { text: I18n.t("taskdoc.mentioned") }
                    Repeater {
                        model: parent.notes
                        delegate: ColumnLayout {
                            id: mention
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: mention.modelData.title
                                elide: Text.ElideRight
                                color: noteCA.hovered ? Theme.text : (root._quiet ? Theme.textMuted : Theme.text)
                                font.family: Theme.fontUi
                                font.pixelSize: root._quiet ? Theme.fsMd : Theme.fsMd
                                font.weight: root._quiet ? Theme.fwBody : Theme.fwTitle
                                ClickArea {
                                    id: noteCA
                                    label: mention.modelData.title
                                    onActivated: root.internalLinkActivated("note", mention.modelData.title)
                                }
                            }
                            Text {
                                visible: !root._quiet
                                text: I18n.t("taskdoc.noteOn").arg(root._valid(mention.modelData.updated) ? root._relDay(mention.modelData.updated)
                                                                                                        : I18n.fmtDate(mention.modelData.updated, "dayMonth"))
                                color: Theme.textMuted
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsSm
                            }
                        }
                    }
                }

                // Links drawn by hand (APP-240): only while there are any.
                TaskRelations {
                    id: relations
                    Layout.fillWidth: true
                    taskId: root.taskId
                    rev: root._rev
                    onOpenTask: (id) => root.openOther(id)
                }

                // Время: the live timer, Пауза t, all of it against the estimate.
                ColumnLayout {
                    id: timeBox
                    objectName: "task-doc-time"
                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    spacing: root._quiet ? Theme.spXs : Theme.spMd
                    property int _tick: 0
                    Timer { interval: 1000; repeat: true; running: !!root.task.isTiming && root.opened; onTriggered: timeBox._tick++ }
                    readonly property string clock: {
                        const s = timeBox._tick >= 0 && root.task.isTiming ? AppController.elapsedSecondsFor(root.taskId) : 0;
                        const m = Math.floor(s / 60);
                        return Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0");
                    }
                    // Everything tracked, the running session included.
                    readonly property int totalMin: Math.round(((timeBox._tick >= 0 ? root.task.trackedSeconds || 0 : 0)
                                                               + (root.task.isTiming ? AppController.elapsedSecondsFor(root.taskId) : 0)) / 60)
                    MetaHead { text: I18n.t("taskdoc.time") }
                    RowLayout {
                        visible: !root._quiet
                        spacing: Theme.spLg
                        Text {
                            objectName: "task-doc-timer"
                            visible: !!root.task.isTiming
                            text: timeBox.clock
                            color: Theme.signalNow
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.typeStep(3)
                        }
                        PillButton {
                            objectName: "task-doc-timer-toggle"
                            text: root.task.isTiming ? I18n.t("taskdoc.pause") : I18n.t("taskcard.startTimer")
                            keyHint: root._keyOf("task.timer")
                            small: true
                            onClicked: root.task.isTiming ? AppController.stopTaskTimer(root.taskId) : AppController.startTaskTimer(root.taskId)
                        }
                    }
                    // "всего 3 ч 10 мин из оценки 4 ч" (bold);
                    // "0:42 сейчас · всего 3 ч 10 мин" (quiet).
                    Text {
                        objectName: "task-doc-time-line"
                        Layout.fillWidth: true
                        visible: text.length > 0
                        wrapMode: Text.WordWrap
                        text: {
                            const bits = [];
                            if (root._quiet && root.task.isTiming) bits.push(I18n.t("taskdoc.timerNow").arg(timeBox.clock));
                            if (timeBox.totalMin > 0 || (!root._quiet && root.task.estimateMinutes > 0))
                                bits.push(I18n.t("taskdoc.tracked").arg(I18n.fmtMinutes(timeBox.totalMin))
                                          + (!root._quiet && root.task.estimateMinutes > 0
                                             ? " " + I18n.t("taskdoc.ofEstimate").arg(I18n.fmtMinutes(root.task.estimateMinutes)) : ""));
                            return bits.join(" · ");
                        }
                        color: root._quiet ? Theme.textMuted : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: root._quiet ? Theme.fsMd : Theme.fsSm
                    }
                    // Quiet: start / pause is a text link.
                    Text {
                        objectName: "task-doc-timer-link"
                        visible: root._quiet
                        text: root.task.isTiming ? I18n.t("taskdoc.pause").toLowerCase() : I18n.t("taskcard.startTimer").toLowerCase()
                        color: timerCA.hovered ? Theme.text : Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                        font.underline: timerCA.hovered
                        ClickArea {
                            id: timerCA
                            label: parent.text
                            onActivated: root.task.isTiming ? AppController.stopTaskTimer(root.taskId) : AppController.startTaskTimer(root.taskId)
                        }
                    }
                    // Session by session (APP-251), folded.
                    TaskSessions {
                        Layout.fillWidth: true
                        taskId: root.taskId
                        rev: root._rev
                    }
                }

                // История: the newest facts.
                ColumnLayout {
                    objectName: "task-doc-history"
                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    visible: root._historyRows.length > 0
                    spacing: Theme.spXs
                    MetaHead { text: I18n.t("taskdoc.history") }
                    Repeater {
                        model: root._historyRows
                        delegate: Text {
                            required property string modelData
                            Layout.fillWidth: true
                            text: modelData
                            elide: Text.ElideRight
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsSm
                        }
                    }
                }

                // Quiet: a small outline Готово right under История (DG-065).
                DoneButton {
                    objectName: "task-doc-done"
                    visible: root._quiet
                }

                Item { Layout.fillHeight: true }

                // Bold: Готово d, the main action, at the bottom.
                DoneButton {
                    objectName: "task-doc-done-bold"
                    visible: !root._quiet
                    Layout.fillWidth: true
                }
            }
        }

        // In the whole content area the text and its meta column keep the
        // sheet's widths, the rest stays empty.
        Item {
            visible: root.full
            Layout.fillWidth: true
            Layout.fillHeight: true
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
    // + свойство: the empty properties, then the local layer's extras that
    // the sheets give no place at rest (DG-061): the plan and a link.
    AppMenu {
        id: addMenu
        objectName: "task-doc-add-menu"
        Instantiator {
            model: ["scheduled", "due", "labels", "tags", "recurrence", "estimate", "plan", "link"]
            delegate: AppMenuItem {
                required property string modelData
                visible: modelData === "plan" ? !(root._plan && root._plan.visible)
                       : modelData === "link" ? true : !root._visible(modelData)
                height: visible ? implicitHeight : 0
                text: I18n.t("taskdoc.add." + modelData)
                onTriggered: {
                    if (modelData === "plan") { root.startPlan(); return; }
                    if (modelData === "link") { root.startLink("related"); return; }
                    root._shown = root._shown.concat([modelData]);
                    if (modelData === "tags") { root._tagsEditing = true; Qt.callLater(tagsEditor.open); }
                }
            }
            onObjectAdded: (i, o) => addMenu.insertItem(i, o)
            onObjectRemoved: (i, o) => addMenu.removeItem(o)
        }
    }

    // What goes under the body, inside its scroll: my plan, the slash hint,
    // and on a tracker card the answer I am writing (APP-241).
    component DocTail: ColumnLayout {
        id: tail
        readonly property alias plan: checklist
        readonly property alias draft: commentDraft
        // In line with the body's blocks.
        x: 0
        spacing: Theme.spLg
        TaskLocalChecklist {
            id: checklist
            Layout.fillWidth: true
            taskId: root.taskId
            rev: root._rev
            onOpenTask: (id) => root.openOther(id)
        }
        // "Пишите прямо здесь. / — вставить чек-лист, код, ссылку на задачу."
        Text {
            objectName: "task-doc-slash-hint"
            Layout.fillWidth: true
            Layout.topMargin: Theme.spXs
            visible: !root._quiet && body.text.trim().length > 0
            text: I18n.t("taskdoc.hint.write") + " <b><font face=\"" + Theme.fontMono + "\" color=\"" + Theme.text + "\">/</font></b> "
                  + I18n.t("taskdoc.hint.slash")
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsLg
            // The hint is where the text goes on: a click there types at
            // the end, and "/" opens the insert menu.
            ClickArea {
                objectName: "task-doc-slash-hint-click"
                label: I18n.t("taskdoc.hint.write")
                showTip: false
                cursorShape: Qt.IBeamCursor
                onActivated: body.appendBlock()
            }
        }
        TaskCommentDraft {
            id: commentDraft
            Layout.fillWidth: true
            visible: root._isTicket
            taskId: root._isTicket ? root.taskId : ""
            rev: root._rev
            trackerName: root._badge.name || root._ticket.provider || ""
        }
    }

    // Готово d: filled neutral in bold (H2-Task), a small outline in quiet.
    component DoneButton: PillButton {
        text: root._done ? I18n.t("taskmenu.reopen") : I18n.t("taskmenu.done")
        shortcutId: "task.done"
        keyHint: root._quiet ? "" : root._keyOf("task.done")
        solid: !root._quiet
        // A double click is one Done, not Done and back (IDIOT-DOC-20).
        onClicked: {
            const now = Date.now();
            if (now - root._doneClickAt < 500) return;
            root._doneClickAt = now;
            AppController.toggleDone([root.taskId]);
        }
    }
    // A section head of the meta column: 12 px, muted.
    component MetaHead: Text {
        Layout.fillWidth: true
        Layout.bottomMargin: Theme.sp2xs
        color: root._quiet ? Theme.textDim : Theme.textMuted
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsSm
        font.weight: root._quiet ? Theme.fwBody : Theme.fwHeading
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
            onAccepted: { tc._editing = false; tc.committed(tcField.text); root.focusDocument(); }
            onActiveFocusChanged: if (!activeFocus && tc._editing) { tc._editing = false; tc.committed(tcField.text); }
            // Hidden, the field kept the keyboard: what was typed went
            // nowhere and Esc no longer closed the document (IDIOT-DOC-6).
            Keys.onEscapePressed: (e) => { tc._editing = false; root.focusDocument(); e.accepted = true; }
            Keys.onReturnPressed: (e) => { tcField.accepted(); e.accepted = true; }
            Keys.onEnterPressed: (e) => { tcField.accepted(); e.accepted = true; }
        }
    }
    // A date chip: typed words ("завтра 15:00", "пт"), read like the input.
    component DateChip: TextChip {
        property string field: ""
        onCommitted: (text) => root._applyDate(field, text)
    }
    // "Ветка  fix/login-throttle" (bold: a label column; quiet: the value
    // alone, as Q-Task writes it).
    component SideRow: RowLayout {
        id: sr
        property string label: ""
        property string value: ""
        property string link: ""
        property bool mono: false
        property bool arrow: false
        default property alias extra: tailRow.data
        Layout.fillWidth: true
        spacing: Theme.spMd
        Text {
            visible: !root._quiet
            text: sr.label
            Layout.preferredWidth: Theme.px(52)
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
        }
        Row {
            id: tailRow
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.px(40)
            spacing: Theme.spSm
            Text {
                id: valueText
                width: Math.min(implicitWidth, tailRow.width - (arrowIcon.visible ? arrowIcon.width + tailRow.spacing : 0))
                text: sr.value
                elide: Text.ElideRight
                color: root._quiet ? Theme.textMuted : Theme.text
                font.family: sr.mono ? Theme.fontMono : Theme.fontUi
                font.pixelSize: sr.mono ? Theme.fsSm : (root._quiet ? Theme.fsMd : Theme.fsSm)
                font.underline: sr.link.length > 0 && (root._quiet || !sr.mono)
                ClickArea {
                    enabled: sr.link.length > 0
                    label: sr.value
                    onActivated: Qt.openUrlExternally(sr.link)
                }
            }
            Icon {
                id: arrowIcon
                visible: sr.arrow
                anchors.verticalCenter: valueText.verticalCenter
                name: "arrow-out"
                size: Theme.iconSize - 2
                color: Theme.textMuted
            }
        }
    }
}
