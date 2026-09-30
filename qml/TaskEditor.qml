import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    // Esc and a click on the backdrop go through requestClose(), which asks
    // before throwing edits away (TASKS-9); Qt's own close-on-Escape would
    // drop them without a word.
    closePolicy: Popup.NoAutoClose
    padding: 0
    // Wide enough for a description to be read, wider still while it is
    // expanded for writing; never taller than the window, with the body
    // scrolling between a fixed header and footer.
    width: Math.min(descExpanded ? 880 : 640, _maxW)
    height: Math.min(implicitHeight, _maxH)
    readonly property real _maxW: (Overlay.overlay ? Overlay.overlay.width : 1200) - 48
    readonly property real _maxH: (Overlay.overlay ? Overlay.overlay.height : 900) - 48

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle {
        color: Theme.scrim
        TapHandler { onTapped: root.requestClose() }
    }

    property var draft: ({})
    // What the fields held when the editor opened; anything else is an edit.
    property string _baseline: ""
    // Why the last Save did not go through, shown above the footer.
    property string _error: ""
    readonly property bool _archived: !!(root.draft && root.draft.archived)
    property bool isNew: false
    // "edit" | "preview" for the description. Starts on edit — the editor is
    // where you go to change things.
    property string descMode: "edit"
    // Both kept across opens: whoever likes Details open, or writes long
    // descriptions, should not have to ask again for every task.
    property bool detailsOpen: false
    property bool descExpanded: false
    readonly property real _descMinH: 120
    readonly property real _descMaxH: descExpanded ? Math.max(280, _maxH - 360) : 280
    // A closed Details says what it holds.
    readonly property string _detailsSummary: {
        const parts = [];
        if (branchField.text.length) parts.push("⎇ " + branchField.text);
        if (recurBox.currentIndex > 0) parts.push("↻ " + recurBox.currentText);
        if (scheduledField.text.length) parts.push("▸ " + scheduledField.text);
        if (estimateField.text.length) parts.push(estimateField.text + " min");
        const labels = root.labelsFromText(labelsField.text);
        if (labels.length) parts.push(labels.join(", "));
        if (somedayBox.checked) parts.push(I18n.t("editor.someday"));
        return parts.join("  ·  ");
    }
    // Original id at the moment of opening the editor. Used so that even if
    // the user edits idField, AppController can find and rename the existing
    // row instead of inserting a duplicate.
    property string _originalId: ""

    // ── Mirrored tracker issue (HEAP-117) ──
    // Empty for a locally-created task, which is what the strip keys off.
    readonly property var _ticket: (root.draft && root.draft.ticket) ? root.draft.ticket : ({})
    readonly property bool _isTicket: !!(root._ticket.provider)
    readonly property var _badge: root._isTicket
        ? (AppController.providerBadges[root._ticket.provider] || ({}))
        : ({})
    // Only the fields the tracker actually filled in, as label/value pairs.
    readonly property var _ticketFacts: {
        if (!root._isTicket) return [];
        const t = root._ticket;
        const out = [];
        const add = (key, value) => {
            if (value !== undefined && value !== null && String(value).length > 0) {
                out.push({ label: I18n.t(key), value: String(value) });
            }
        };
        // No assignee: heap mirrors the issues assigned to you, so it would
        // only ever say your own name.
        add("ticket.author", t.author);
        add("ticket.type", t.issueType);
        add("ticket.milestone", t.milestone);
        // -1 means the provider never said, which is not the same as none.
        if ((t.commentCount || -1) >= 0) {
            out.push({ label: I18n.t("ticket.comments"), value: String(t.commentCount) });
        }
        const when = (d) => (d && d.getTime && !isNaN(d.getTime())) ? AppController.shortDate(d) : "";
        add("ticket.created", when(t.createdAt));
        add("ticket.updated", when(t.updatedAt));
        return out;
    }

    // A field both heap and the tracker changed since the last sync (audit
    // INT-4). Resolving it hides the panel for the rest of this dialog.
    property bool _conflictResolved: false
    readonly property bool _hasConflict: root._isTicket && !!root._ticket.conflict && !root._conflictResolved
    // The tracker's side of each conflicting field, as label/value pairs.
    readonly property var _conflictRows: {
        if (!root._hasConflict) return [];
        const t = root._ticket;
        const fields = t.conflicts || [];
        const out = [];
        for (let i = 0; i < fields.length; ++i) {
            const f = fields[i];
            if (f === "title") out.push({ label: I18n.t("ticket.conflict.title"), value: String(t.remoteTitle || "") });
            else if (f === "body") out.push({ label: I18n.t("ticket.conflict.body"), value: String(t.remoteBody || "") || "—" });
            else if (f === "priority") out.push({ label: I18n.t("ticket.conflict.priority"), value: String(t.remotePriority || "") });
        }
        return out;
    }
    // Put the tracker's values in the fields (so Save keeps them) and on the
    // stored card, in one undoable step.
    function _takeTrackerVersion() {
        const t = root._ticket;
        const fields = t.conflicts || [];
        if (fields.indexOf("title") >= 0 && String(t.remoteTitle || "").length > 0) titleField.text = t.remoteTitle;
        if (fields.indexOf("body") >= 0) descField.text = String(t.remoteBody || "");
        if (fields.indexOf("priority") >= 0 && String(t.remotePriority || "").length > 0)
            priBox.currentIndex = Math.max(0, ["P0", "P1", "P2", "P3"].indexOf(t.remotePriority));
        AppController.resolveTrackerConflict(root._originalId, true);
        root._conflictResolved = true;
    }

    // Comments, held only while this dialog is open (HEAP-117).
    property var _comments: []
    property string _commentsError: ""
    property bool _commentsRequested: false

    Connections {
        target: AppController

        function onTicketCommentsLoaded(taskId, comments, error) {
            // A reply for a ticket the user has since navigated away from.
            if (taskId !== (root._originalId || (root.draft.id || ""))) return;
            root._comments = comments;
            root._commentsError = error || "";
        }
    }

    function showFor(initialDraft) {
        // Never carry one ticket's comments over to the next.
        _comments = [];
        _commentsError = "";
        _commentsRequested = false;
        _conflictResolved = false;
        draft = initialDraft || {};
        isNew = !!draft._isNew;
        _originalId = isNew ? "" : (draft.id || "");
        // New tasks: leave idField empty with a TODO hint — real id is
        // assigned on save. Edit: pre-fill with existing id (editable).
        idField.text = isNew ? "" : (draft.id || "");
        titleField.text = draft.title || "";
        descField.text = draft.desc || "";
        statusBox.currentIndex = Math.max(0, statusList().indexOf(draft.status));
        priBox.currentIndex = Math.max(0, ["P0", "P1", "P2", "P3"].indexOf(draft.priority || "P2"));
        branchField.text = draft.branch || "";
        // Each datetime has its own clock flag (schema v10): a date-only
        // deadline next to a timed schedule stays date-only.
        deadlineField.text = formatWhen(draft.dueAt, draft.dueHasTime);
        scheduledField.text = formatWhen(draft.scheduledAt, draft.scheduledHasTime);
        labelsField.text = labelsToText(draft.labels);
        estimateField.text = draft.estimateMinutes > 0 ? String(draft.estimateMinutes) : "";
        somedayBox.checked = !!draft.someday;
        recurBox.setRecurrence(draft.recurrence || "");
        _error = "";
        discardPrompt.close();
        _baseline = _snapshot();
        open();
        // Keyboard-first: Ctrl+N and type. Nothing had focus, so whatever was
        // typed before reaching for the mouse went nowhere and the task was
        // saved without a title. Focus lands now, not after the enter
        // transition, so the first keystroke is not lost either. An existing
        // task opens with the caret at the end of its title.
        titleField.forceActiveFocus();
        if (isNew) titleField.selectAll();
        else titleField.cursorPosition = titleField.text.length;
        // Kick a one-shot PR/state refresh for this task's branch across all
        // watched repos. Result lands on TaskModel via repoStateUpdated and
        // chips on the underlying TaskCard update without re-opening.
        if (draft.id && !isNew) AppController.refreshGitForTaskBranch(draft.id);
    }

    // Everything the user can change, as one comparable string.
    function _snapshot() {
        return JSON.stringify([idField.text, titleField.text, descField.text, statusBox.currentIndex,
                               priBox.currentIndex, branchField.text, deadlineField.text, scheduledField.text,
                               labelsField.text, estimateField.text, somedayBox.checked, recurBox.currentIndex]);
    }
    function isDirty() {
        return root.opened && root._snapshot() !== root._baseline;
    }

    // Esc and the backdrop. Clean: close. Edited: ask, keyboard first —
    // Enter saves, D discards, Esc keeps editing.
    function requestClose() {
        if (discardPrompt.opened) return;
        if (!root.isDirty()) { root.close(); return; }
        discardPrompt.open();
    }

    function statusList() {
        const out = [];
        const sts = AppController.statuses;
        for (let i = 0; i < sts.length; i++) out.push(sts[i].id);
        return out;
    }

    function statusNames() {
        const out = [];
        const sts = AppController.statuses;
        for (let i = 0; i < sts.length; i++) out.push(sts[i].name);
        return out;
    }

    function formatDate(d) {
        if (!d || !d.getFullYear) return "";
        return d.getFullYear() + "-" + (d.getMonth() + 1).toString().padStart(2, "0") + "-" + d.getDate().toString().padStart(2, "0");
    }

    // Renders a stored datetime back into the field. The clock part is only
    // shown when the task actually carries one — a bare date must not come back
    // as "… 00:00" and turn itself into a timed task on the next save.
    function formatWhen(d, hasTime) {
        if (!d || !d.getFullYear || isNaN(d.getTime())) return "";
        const iso = formatDate(d);
        if (!hasTime) return iso;
        return iso + " " + String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
    }

    // "YYYY-MM-DD" or "YYYY-MM-DD HH:MM" — the shape formatWhen writes back into
    // the field, parsed without going through the natural-language parser.
    readonly property var _isoRe: /^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?$/

    function parseDate(s) {
        if (!s) return undefined;
        const r = AppController.parseDateTime(s, new Date());
        if (r && r.ok && r.start) return r.start;
        const m = root._isoRe.exec(s.trim());
        if (!m) return undefined;
        return new Date(parseInt(m[1]), parseInt(m[2]) - 1, parseInt(m[3]),
                        m[4] ? parseInt(m[4]) : 0, m[5] ? parseInt(m[5]) : 0);
    }

    // Does this field carry a clock time, as opposed to a bare date?
    function parseHasTime(s) {
        if (!s) return false;
        const r = AppController.parseDateTime(s, new Date());
        if (r && r.ok) return !!r.hasTime;
        const m = root._isoRe.exec(s.trim());
        return !!(m && m[4]);
    }

    function labelsToText(labels) {
        if (!labels || !labels.length) return "";
        const out = [];
        for (let i = 0; i < labels.length; ++i) out.push(labels[i].id);
        return out.join(", ");
    }

    // Tab on a markdown list line ("- a", "* [ ] b", "1. c") nests the item two
    // spaces deeper; Shift+Tab takes up to two back out. Returns false off a
    // list line, where Tab moves focus instead.
    readonly property var _listLineRe: /^(\s*)([-*+]|\d+[.)])\s/

    function indentListLine(field, outdent) {
        const text = field.text;
        const pos = field.cursorPosition;
        const start = text.lastIndexOf("\n", pos - 1) + 1;
        const endNl = text.indexOf("\n", pos);
        const line = text.substring(start, endNl < 0 ? text.length : endNl);
        const m = root._listLineRe.exec(line);
        if (!m) return false;
        if (outdent) {
            const n = Math.min(2, m[1].length);
            if (n > 0) {
                field.remove(start, start + n);
                field.cursorPosition = Math.max(start, pos - n);
            }
        } else {
            field.insert(start, "  ");
            field.cursorPosition = pos + 2;
        }
        return true;
    }

    function labelsFromText(s) {
        const out = [];
        const parts = (s || "").split(",");
        for (let i = 0; i < parts.length; ++i) {
            const id = parts[i].trim();
            if (id.length > 0) out.push(id);
        }
        return out;
    }

    property var _deadlinePreview: ({ok: false})

    function _refreshDeadlinePreview() {
        const s = deadlineField.text;
        if (!s) {
            _deadlinePreview = {ok: false};
            return;
        }
        _deadlinePreview = AppController.parseDateTime(s, new Date()) || {ok: false};
    }

    // Forwards to heap::text::extractMeta (C++, unit-tested).
    function _extractMeta(raw) {
        return AppController.extractTaskMeta(raw || "");
    }

    // Resolve @handles into display names via PersonModel. Unknown handles
    // are kept as "@handle" so context isn't silently dropped.
    function _resolvePeopleNames(handles) {
        if (!handles || handles.length === 0) return [];
        const out = [];
        const known = AppController.people;
        for (let i = 0; i < handles.length; ++i) {
            const h = handles[i];
            const p = AppController.personById(h);
            if (p && p.id) { out.push(p.name || p.id); continue; }
            // Fallback: case-insensitive scan over name's first token / id.
            let matched = false;
            for (let j = 0; j < known.rowCount(); ++j) {
                const idx = known.index(j, 0);
                const id  = String(known.data(idx, Qt.UserRole + 1) || "");
                const nm  = String(known.data(idx, Qt.UserRole + 2) || "");
                const firstWord = nm.split(/\s+/)[0] || "";
                if (id.toLowerCase() === h.toLowerCase()
                    || firstWord.toLowerCase() === h.toLowerCase()) {
                    out.push(nm || id);
                    matched = true;
                    break;
                }
            }
            if (!matched) out.push("@" + h);
        }
        return out;
    }

    // Forwards to heap::text::classifyKind (C++, unit-tested).
    function _classifyKind(text) {
        return AppController.classifyTaskKind(text || "");
    }

    // Shared by the Save button and the Ctrl+Return shortcut. Returns whether
    // the task was saved (and the editor closed).
    function _save() {
        if (!root._commit()) return false;
        root.close();
        return true;
    }

    // Validates and saves without closing. A refusal says why and keeps the
    // draft: an unreadable date used to be saved as no date, an empty title
    // did nothing at all.
    function _commit() {
        root._error = "";
        if (titleField.text.trim().length === 0) {
            root._error = I18n.t("editor.err.title");
            titleField.forceActiveFocus();
            return false;
        }
        if (deadlineField.text.trim().length > 0 && root.parseDate(deadlineField.text) === undefined) {
            root._error = I18n.t("editor.err.date").arg(deadlineField.text.trim());
            deadlineField.forceActiveFocus();
            return false;
        }
        if (scheduledField.text.trim().length > 0 && root.parseDate(scheduledField.text) === undefined) {
            root._error = I18n.t("editor.err.date").arg(scheduledField.text.trim());
            root.detailsOpen = true;
            scheduledField.forceActiveFocus();
            return false;
        }
        // New tasks: if user left idField blank, fall back to the
        // auto-generated id captured in the draft. Edit: take the
        // (possibly renamed) text from idField.
        // An emptied field on an existing task keeps its id: saving a task
        // under "" made it unreachable.
        let finalId = idField.text.trim();
        if (finalId.length === 0) {
            finalId = root.isNew ? (root.draft.id || "") : root._originalId;
        }
        // Extract @handle attendees and "// comment" tail. Handles
        // remain visible in the title — only the "//" tail is
        // peeled off into the description.
        const meta = root._extractMeta(titleField.text);
        const cleanedTitle = meta.title;
        const inlineDesc   = meta.desc;
        const handleNames  = root._resolvePeopleNames(meta.handles);

        // Due and scheduled are typed independently; a task with only
        // a due date is scheduled for that day, which is what the
        // single deadline field always meant.
        const dueAt = root.parseDate(deadlineField.text);
        const schedTyped = root.parseDate(scheduledField.text);
        const scheduledAt = schedTyped || dueAt;
        const dueHasTime = !!dueAt && root.parseHasTime(deadlineField.text);
        const scheduledHasTime = schedTyped ? root.parseHasTime(scheduledField.text) : dueHasTime;

        const d = {
            _isNew: root.isNew,
            // Pass the original id alongside the (possibly edited)
            // new id so saveTask can rename rather than insert a
            // duplicate row when the user changes the id field.
            _originalId: root._originalId,
            id: finalId,
            title: cleanedTitle,
            // Inline "//..." appends to the description field.
            desc: inlineDesc.length > 0
                  ? ((descField.text || "").trim().length > 0
                      ? descField.text.trim() + "\n" + inlineDesc
                      : inlineDesc)
                  : descField.text,
            priority: priBox.currentText,
            status: root.statusList()[statusBox.currentIndex],
            scheduledAt: scheduledAt,
            dueAt: dueAt,
            dueHasTime: dueHasTime,
            scheduledHasTime: scheduledHasTime,
            branch: branchField.text,
            recurrence: recurBox.value(),
            // Plain names; saveTask keeps each existing label's colour.
            labels: root.labelsFromText(labelsField.text),
            estimateMinutes: parseInt(estimateField.text || "0") || 0,
            someday: somedayBox.checked
        };
        // A task and the meeting it books are one undo step.
        AppController.beginUndoGroup(I18n.t("editor.undo.save").arg(finalId));
        try {
            return root._saveDraft(d, cleanedTitle, handleNames);
        } finally {
            AppController.endUndoGroup();
        }
    }

    function _saveDraft(d, cleanedTitle, handleNames) {
        // A refused save (id taken, review without a branch) keeps the editor
        // open on the draft; closing it threw the user's edits away. The
        // controller's toast says why.
        if (!AppController.saveTask(d)) {
            root._error = I18n.t("editor.err.refused");
            return false;
        }
        // The parsed clock time now lives on the task itself, so a
        // focus block is no longer needed to keep it. A "sync" still
        // means a meeting, and a meeting is a calendar event.
        if (root.isNew
            && root._deadlinePreview && root._deadlinePreview.ok
            && root._deadlinePreview.hasTime
            && root._deadlinePreview.start) {
            const kind = root._classifyKind(
                (titleField.text || "") + " "
              + (descField.text || "") + " "
              + (deadlineField.text || ""));
            const dt = root._deadlinePreview.start;
            if (kind === "sync") {
                const startHour = dt.getHours() + dt.getMinutes() / 60.0;
                // Honour parsed range "12:00-13:00", else 30m.
                let endHour = startHour + 0.5;
                const pe = root._deadlinePreview.end;
                if (pe && pe.getTime && pe.getTime() > 0) {
                    const eh = pe.getHours() + pe.getMinutes() / 60.0;
                    if (eh > startHour) endHour = eh;
                }
                const ev = AppController.newEventDraft(startHour, dt);
                ev.type      = "sync";
                ev.title     = (cleanedTitle || "").substring(0, 40);
                ev.end       = endHour;
                ev.taskId    = d.id;
                ev.date      = dt;
                ev.attendees = handleNames.join(", ");
                AppController.saveEvent(ev);
            }
            // The calendar stays on the day the user was looking at: jumping
            // it to the task's date on save was a surprise, not a feature.
        }
        return true;
    }

    anchors.centerIn: Overlay.overlay

    // Keyboard-first: Escape already closes, but there was no way to commit
    // without reaching for the mouse. Plain Enter belongs to the text fields
    // (and would fight the multi-line description), so Ctrl+Enter saves.
    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: root.opened && !discardPrompt.opened
        onActivated: root._save()
    }

    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    // What the dialog is for comes first — title, status, priority, when it
    // is due and what it says — then everything else behind "Details". It
    // used to be one 480px column of every field at once, with a 70px box for
    // the description, so a real ticket's text was read through a slot.
    contentItem: ColumnLayout {
        spacing: 0
        // Esc from any field bubbles up to here (text fields do not take it).
        Keys.onEscapePressed: (e) => { e.accepted = true; root.requestClose(); }

        // ── Header: what this is, and where it lives ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.topMargin: Theme.inset; Layout.bottomMargin: Theme.spXl
            spacing: Theme.spMd
            Text {
                text: root.isNew ? I18n.t("editor.new.task") : I18n.t("editor.edit.task")
                color: Theme.text
                font.pixelSize: Theme.fsLg
                font.weight: Font.DemiBold
            }
            Text {
                visible: !root.isNew
                // A mirrored issue is known by its tracker key, not the id the
                // merge invented for it (HEAP-117).
                text: root._isTicket ? (root._ticket.key || "") : idField.text
                textFormat: Text.PlainText
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsMd
                font.weight: Font.Medium
            }
            Item { Layout.fillWidth: true }
            PillButton {
                objectName: "te-ticket-open"
                visible: root._isTicket && String(root._ticket.url || "").length > 0
                text: "↗  " + I18n.t("ticket.open")
                onClicked: AppController.openTaskExternal(root._originalId || (root.draft.id || ""))
            }
        }

        ScrollView {
            id: bodyScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: bodyCol.implicitHeight
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: bodyCol
                width: bodyScroll.availableWidth
                spacing: Theme.spXl

                // ── Mirrored tracker issue: one line of whose it is (HEAP-117) ──
                // The rest of what the tracker says sits under Details.
                Rectangle {
                    objectName: "te-ticket-strip"
                    visible: root._isTicket
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    implicitHeight: stripCol.implicitHeight + 2 * Theme.spLg
                    radius: Theme.radius
                    color: Theme.withAlpha(Theme.panel2, 0.6)
                    border.color: Theme.border
                    border.width: 1

                    ColumnLayout {
                        id: stripCol
                        anchors.fill: parent
                        anchors.margins: Theme.spLg
                        spacing: Theme.spXs
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spSm
                            Text {
                                text: root._badge.icon || "◍"
                                textFormat: Text.PlainText
                                color: root._badge.color || Theme.textMuted
                                font.pixelSize: Theme.fsXs
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: (root._badge.name || root._ticket.provider || "")
                                      + (root._ticket.project ? " · " + root._ticket.project : "")
                                textFormat: Text.PlainText
                                color: Theme.textMuted
                                font.pixelSize: Theme.fsSm
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("ticket.overwriteHint")
                            textFormat: Text.PlainText
                            color: Theme.textDim
                            font.pixelSize: Theme.fsXs
                            wrapMode: Text.WordWrap
                        }
                        // Both sides changed a field since the last sync: show
                        // the tracker's version and let the user pick one.
                        ColumnLayout {
                            objectName: "te-ticket-conflict"
                            visible: root._hasConflict
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.spSm
                            spacing: Theme.spXs
                            Text {
                                Layout.fillWidth: true
                                text: I18n.t("ticket.conflict.head")
                                textFormat: Text.PlainText
                                color: Theme.warning
                                font.pixelSize: Theme.fsSm
                                font.weight: Font.DemiBold
                                wrapMode: Text.WordWrap
                            }
                            Repeater {
                                model: root._conflictRows
                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData.label + ": " + modelData.value
                                    textFormat: Text.PlainText
                                    color: Theme.text
                                    font.pixelSize: Theme.fsSm
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                }
                            }
                            RowLayout {
                                spacing: Theme.spSm
                                PillButton {
                                    objectName: "te-conflict-use-tracker"
                                    text: I18n.t("ticket.conflict.useTracker")
                                    onClicked: root._takeTrackerVersion()
                                }
                                PillButton {
                                    objectName: "te-conflict-keep-mine"
                                    text: I18n.t("ticket.conflict.keepMine")
                                    onClicked: {
                                        AppController.resolveTrackerConflict(root._originalId, false);
                                        root._conflictResolved = true;
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Title ──
                TextField {
                    id: titleField
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    placeholderText: I18n.t("editor.ph.titleShort")
                    font.pixelSize: Theme.fsLg
                    font.weight: Font.Medium
                    background: FieldBg {}
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                }

                // ── Status · priority · deadline: what a developer reads first ──
                GridLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    columns: 3
                    columnSpacing: Theme.spLg
                    rowSpacing: Theme.spXs
                    FieldLabel { text: I18n.t("editor.label.status").toUpperCase() }
                    FieldLabel { text: I18n.t("editor.label.priority").toUpperCase() }
                    FieldLabel { text: I18n.t("editor.label.deadline").toUpperCase() }
                    ComboBox {
                        id: statusBox
                        objectName: "te-status"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        // Never narrower than its longest column name: "In
                        // Progress" read "In Prog…" (UX-25).
                        Layout.minimumWidth: Math.min(240, statusMetrics.widest + 2 * Theme.spLg + 24)
                        FontMetrics { id: statusMetricsFont; font.pixelSize: Theme.fsMd }
                        QtObject {
                            id: statusMetrics
                            readonly property real widest: {
                                let w = 0;
                                const names = root.statusNames();
                                for (let i = 0; i < names.length; i++)
                                    w = Math.max(w, statusMetricsFont.advanceWidth(names[i]));
                                return Math.ceil(w);
                            }
                        }
                        model: root.statusNames()
                        background: FieldBg {}
                        contentItem: Text {
                            text: statusBox.displayText
                            color: Theme.text
                            font.pixelSize: Theme.fsMd
                            leftPadding: Theme.spLg
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                    ComboBox {
                        id: priBox
                        Layout.preferredWidth: 88
                        model: ["P0", "P1", "P2", "P3"]
                        background: FieldBg {}
                        contentItem: Text {
                            text: priBox.displayText
                            color: Theme.priorityColor(priBox.displayText)
                            font.pixelSize: Theme.fsMd
                            font.weight: Font.DemiBold
                            leftPadding: Theme.spLg
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        Layout.minimumWidth: 160
                        spacing: Theme.spSm
                        TextField {
                            id: deadlineField
                            Layout.fillWidth: true
                            placeholderText: I18n.t("editor.ph.deadline")
                            font.family: Theme.fontMono
                            background: Rectangle {
                                radius: Theme.radiusMd
                                color: Theme.panel2
                                border.color: deadlineField.text.length === 0
                                    ? Theme.border
                                    : (root._deadlinePreview && root._deadlinePreview.ok
                                        ? Theme.accent
                                        : Theme.danger)
                                border.width: 1
                            }
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                            onTextChanged: deadlinePreviewTimer.restart()
                            onEditingFinished: {
                                if (root._deadlinePreview && root._deadlinePreview.ok &&
                                    root._deadlinePreview.start) {
                                    text = root.formatWhen(root._deadlinePreview.start,
                                                           root._deadlinePreview.hasTime);
                                }
                            }
                            ToolTip.visible: hovered && text.length > 0 &&
                                root._deadlinePreview && !root._deadlinePreview.ok
                            ToolTip.text: I18n.t("editor.tip.unrecognized")
                        }
                        Timer {
                            id: deadlinePreviewTimer
                            interval: 80
                            repeat: false
                            onTriggered: root._refreshDeadlinePreview()
                        }
                        // Calendar picker — fills the deadline field with a chosen date.
                        Rectangle {
                            id: deadlineCalBtn
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: Theme.radiusMd
                            color: deadlineCalMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            Rectangle {   // mini calendar glyph
                                anchors.centerIn: parent
                                width: 15; height: 14; radius: Theme.radiusXs
                                color: "transparent"
                                border.color: Theme.textMuted; border.width: 1
                                Rectangle { width: parent.width; height: 3; color: Theme.textMuted; anchors.top: parent.top }
                            }
                            MouseArea {
                                id: deadlineCalMA
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const seed = (root._deadlinePreview && root._deadlinePreview.ok && root._deadlinePreview.start)
                                        ? root._deadlinePreview.start : null;
                                    deadlinePicker.openAt(seed, deadlineCalBtn);
                                }
                            }
                            DatePickerPopup {
                                id: deadlinePicker
                                y: parent.height + 4
                                onPicked: (value) => {
                                    deadlineField.text = root.formatDate(value);
                                    root._refreshDeadlinePreview();
                                }
                            }
                        }
                    }
                    Item { Layout.columnSpan: 2; implicitHeight: 1 }
                    // What the deadline field was read as.
                    Text {
                        id: chipLabel
                        visible: text.length > 0
                        Layout.fillWidth: true
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsXs
                        color: Theme.textMuted
                        text: {
                            if (!root._deadlinePreview || !root._deadlinePreview.ok ||
                                !root._deadlinePreview.start) return "";
                            const d = root._deadlinePreview.start;
                            const iso = d.getFullYear() + "-" +
                                String(d.getMonth() + 1).padStart(2, "0") + "-" +
                                String(d.getDate()).padStart(2, "0");
                            if (root._deadlinePreview.hasTime) {
                                const hh = String(d.getHours()).padStart(2, "0");
                                const mm = String(d.getMinutes()).padStart(2, "0");
                                return "↑ " + iso + " " + hh + ":" + mm;
                            }
                            return "↑ " + iso;
                        }
                    }
                }

                // ── Description ──
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    spacing: Theme.spSm
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spXs
                        FieldLabel { text: I18n.t("editor.label.desc").toUpperCase() }
                        Item { Layout.fillWidth: true }
                        // The description is markdown and always has been — it
                        // was just never rendered, so a template's checklist was
                        // inert text the user could not tick.
                        Repeater {
                            model: [ ({ id: "edit", label: I18n.t("notes.mode.edit") }),
                                     ({ id: "preview", label: I18n.t("notes.mode.preview") }) ]
                            delegate: SegChip {
                                required property var modelData
                                objectName: "desc-mode-" + modelData.id
                                text: modelData.label
                                active: root.descMode === modelData.id
                                onClicked: root.descMode = modelData.id
                            }
                        }
                        Rectangle { implicitWidth: 1; implicitHeight: 14; color: Theme.border; Layout.leftMargin: Theme.spXs; Layout.rightMargin: Theme.spXs }
                        SegChip {
                            objectName: "desc-expand"
                            text: root.descExpanded ? "⤡  " + I18n.t("editor.desc.collapse")
                                                    : "⤢  " + I18n.t("editor.desc.expand")
                            active: false
                            onClicked: root.descExpanded = !root.descExpanded
                        }
                    }
                    // Grows with the text, from a few lines up to a cap; past
                    // the cap it scrolls inside itself. Expand widens the dialog
                    // and lifts the cap for writing at length.
                    ScrollView {
                        id: descScroll
                        visible: root.descMode === "edit"
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(root._descMinH,
                                                         Math.min(root._descMaxH, descField.implicitHeight))
                        clip: true
                        TextArea {
                            id: descField
                            objectName: "te-desc"
                            placeholderText: I18n.t("editor.ph.desc")
                            wrapMode: TextEdit.Wrap
                            font.pixelSize: Theme.fsMd
                            topPadding: Theme.spLg; bottomPadding: Theme.spLg
                            leftPadding: Theme.spLg; rightPadding: Theme.spLg
                            background: FieldBg {}
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                            selectByMouse: true
                            // Tab leaves the description, so Details, Save and
                            // Delete can be reached from the keyboard; it used to
                            // type a tab character and trap focus here. On a
                            // list line Tab / Shift+Tab indent and outdent the
                            // item, and Ctrl+Tab always inserts indentation.
                            Keys.onPressed: (event) => {
                                if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) return;
                                const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
                                if (event.modifiers & Qt.ControlModifier) {
                                    descField.insert(descField.cursorPosition, "  ");
                                    event.accepted = true;
                                    return;
                                }
                                if (root.indentListLine(descField, back)) {
                                    event.accepted = true;
                                    return;
                                }
                                const next = descField.nextItemInFocusChain(!back);
                                if (next) next.forceActiveFocus(back ? Qt.BacktabFocusReason : Qt.TabFocusReason);
                                event.accepted = true;
                            }
                        }
                    }
                    // The checkbox write goes through the editor's own document,
                    // so ticking an item in the preview edits the text the Save
                    // button will store — and does it as one undo step.
                    Rectangle {
                        visible: root.descMode === "preview"
                        Layout.fillWidth: true
                        Layout.preferredHeight: descScroll.Layout.preferredHeight
                        radius: Theme.radiusMd
                        color: Theme.panel2
                        border.color: Theme.border
                        border.width: 1
                        MdView {
                            anchors.fill: parent
                            anchors.margins: Theme.spSm
                            document: descDocument
                            editorDocument: descField.textDocument
                        }
                    }
                }

                // ── Details: everything that is not needed to pick the task up ──
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    implicitHeight: 1
                    color: Theme.border
                }
                Item {
                    id: detailsToggle
                    objectName: "te-details-toggle"
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    implicitHeight: detailsRow.implicitHeight + Theme.spSm
                    // On the Tab path between the description and the footer.
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.t("editor.details")
                    Keys.onSpacePressed: root.detailsOpen = !root.detailsOpen
                    Keys.onReturnPressed: root.detailsOpen = !root.detailsOpen
                    Keys.onEnterPressed: root.detailsOpen = !root.detailsOpen
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -Theme.sp2xs
                        radius: Theme.radiusSm
                        color: "transparent"
                        visible: detailsToggle.activeFocus
                        border.color: Theme.focusRing
                        border.width: 2
                    }
                    RowLayout {
                        id: detailsRow
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spMd
                        Text {
                            text: (root.detailsOpen ? "▾  " : "▸  ") + I18n.t("editor.details")
                            color: detailsMA.containsMouse ? Theme.text : Theme.textMuted
                            font.pixelSize: Theme.fsMd
                            font.weight: Font.DemiBold
                        }
                        // What is filled in behind the fold, so a closed Details
                        // still says whether there is anything to look at.
                        Text {
                            visible: !root.detailsOpen
                            Layout.fillWidth: true
                            text: root._detailsSummary
                            color: Theme.textDim
                            font.pixelSize: Theme.fsSm
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: detailsMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.detailsOpen = !root.detailsOpen
                    }
                }

                GridLayout {
                    id: detailsGrid
                    visible: root.detailsOpen
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    columns: 2
                    columnSpacing: Theme.spLg
                    rowSpacing: Theme.spXs

                    FieldLabel { Layout.fillWidth: true; Layout.preferredWidth: 1; text: I18n.t("editor.label.ticketId").toUpperCase() }
                    FieldLabel { Layout.fillWidth: true; Layout.preferredWidth: 1; text: I18n.t("editor.label.branch").toUpperCase() }
                    TextField {
                        id: idField
                        objectName: "te-id"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        // New tasks: TODO placeholder — final id is generated on save.
                        // Edit: pre-filled with the current id (still editable).
                        placeholderText: root.isNew ? I18n.t("editor.ph.ticketId")
                                                    : I18n.t("editor.ph.ticketIdEdit")
                        font.family: Theme.fontMono
                        background: FieldBg {}
                        color: Theme.text
                        placeholderTextColor: Theme.textDim
                        // Auto-uppercase so a hand-typed id stays canonical (matches
                        // newTaskDraft) — but only while composing a NEW one. A synced
                        // ticket's id is lowercase by construction ("github-1234", from the
                        // provider id), and uppercasing it on open made a plain Save look
                        // like a rename to saveTask: the row was silently re-keyed to
                        // GITHUB-1234, and if that id was taken, the other task was lost.
                        onTextChanged: {
                            if (!root.isNew) return;
                            const up = text.toUpperCase();
                            if (up !== text) text = up;
                        }
                    }
                    TextField {
                        id: branchField
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        placeholderText: "fix/..."
                        font.family: Theme.fontMono
                        background: FieldBg {}
                        color: Theme.text
                        placeholderTextColor: Theme.textDim
                    }

                    FieldLabel { Layout.fillWidth: true; Layout.preferredWidth: 1; text: I18n.t("editor.label.scheduled").toUpperCase() }
                    FieldLabel { Layout.fillWidth: true; Layout.preferredWidth: 1; text: I18n.t("editor.label.recurrence").toUpperCase() }
                    TextField {
                        id: scheduledField
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        placeholderText: I18n.t("editor.ph.deadline")
                        font.family: Theme.fontMono
                        background: FieldBg {}
                        color: Theme.text
                        placeholderTextColor: Theme.textDim
                    }
                    ComboBox {
                        id: recurBox
                        objectName: "te-recurrence"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        readonly property var _base: ["", "every:day", "every:week", "every:weekday",
                                                      "every:mon", "every:tue", "every:wed", "every:thu", "every:fri",
                                                      "every:sat", "every:sun", "every:month"]
                        // A rule the list does not name ("every:month:15", from
                        // capture) is shown as itself, so saving the editor
                        // does not quietly turn it into "none".
                        property string _extra: ""
                        readonly property var _vals: _extra.length > 0 ? _base.concat([_extra]) : _base
                        function setRecurrence(r) {
                            _extra = (r.length > 0 && _base.indexOf(r) < 0) ? r : "";
                            currentIndex = Math.max(0, _vals.indexOf(r));
                        }
                        function value() { return _vals[currentIndex] || ""; }
                        function _label(r) {
                            const m = /^every:month:(\d+)$/.exec(r);
                            return m ? I18n.t("editor.recur.monthlyOn").arg(m[1]) : r;
                        }
                        model: [I18n.t("editor.recur.none"), I18n.t("editor.recur.daily"),
                                I18n.t("editor.recur.weekly"), I18n.t("editor.recur.weekdays"),
                                I18n.t("editor.recur.everyMon"), I18n.t("editor.recur.everyTue"),
                                I18n.t("editor.recur.everyWed"), I18n.t("editor.recur.everyThu"),
                                I18n.t("editor.recur.everyFri"), I18n.t("editor.recur.everySat"),
                                I18n.t("editor.recur.everySun"), I18n.t("editor.recur.monthly")]
                               .concat(_extra.length > 0 ? [_label(_extra)] : [])
                        background: FieldBg {}
                        contentItem: Text {
                            text: recurBox.displayText
                            color: Theme.text
                            font.pixelSize: Theme.fsMd
                            leftPadding: Theme.spLg
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    FieldLabel { Layout.fillWidth: true; Layout.preferredWidth: 1; text: I18n.t("editor.label.labels").toUpperCase() }
                    FieldLabel { Layout.fillWidth: true; Layout.preferredWidth: 1; text: I18n.t("editor.label.estimate").toUpperCase() }
                    TextField {
                        id: labelsField
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        placeholderText: "backlog, infra"
                        background: FieldBg {}
                        color: Theme.text
                        placeholderTextColor: Theme.textDim
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: Theme.spMd
                        TextField {
                            id: estimateField
                            Layout.fillWidth: true
                            placeholderText: "45"
                            font.family: Theme.fontMono
                            validator: IntValidator { bottom: 0; top: 100000 }
                            background: FieldBg {}
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                        }
                        // A toggle in the same pill style as every other button
                        // here; the stock CheckBox was a black square.
                        PillButton {
                            id: somedayBox
                            objectName: "te-someday"
                            checkable: true
                            selected: checked
                            text: (checked ? "☾  " : "☽  ") + I18n.t("editor.someday")
                            // Parking a task as "someday" files it under Backlog. Reflect
                            // that in the status box immediately; saveTask enforces it too.
                            onCheckedChanged: if (checked) {
                                const bi = root.statusList().indexOf("backlog");
                                if (bi >= 0) statusBox.currentIndex = bi;
                            }
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: I18n.t("editor.someday.hint")
                        }
                    }
                }

                // What the tracker says about the issue, and its comments.
                ColumnLayout {
                    visible: root.detailsOpen && root._isTicket
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    spacing: Theme.spSm
                    FieldLabel { text: I18n.t("editor.details.tracker").toUpperCase() }
                    // One "label value" pair per field the tracker actually gave.
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.sp2xl
                        Repeater {
                            model: root._ticketFacts
                            delegate: Row {
                                required property var modelData
                                spacing: Theme.spXs
                                Text {
                                    text: modelData.label
                                    textFormat: Text.PlainText
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fsSm
                                }
                                Text {
                                    text: modelData.value
                                    textFormat: Text.PlainText
                                    color: Theme.text
                                    font.pixelSize: Theme.fsSm
                                }
                            }
                        }
                    }
                    // Comments are read on demand and kept only while this
                    // dialog is open — heap stores none of them.
                    PillButton {
                        objectName: "te-ticket-load-comments"
                        visible: !root._commentsRequested
                        text: "❝  " + I18n.t("ticket.loadComments")
                        onClicked: {
                            root._commentsRequested = true;
                            AppController.fetchTicketComments(root._originalId || (root.draft.id || ""));
                        }
                    }
                    Text {
                        objectName: "te-ticket-comments-status"
                        visible: root._commentsRequested
                                 && (root._commentsError.length > 0 || root._comments.length === 0)
                        text: root._commentsError.length > 0 ? root._commentsError : I18n.t("ticket.noComments")
                        textFormat: Text.PlainText
                        color: Theme.textDim
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: root._comments
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.sp2xs
                            RowLayout {
                                spacing: Theme.spSm
                                Text {
                                    text: "@" + String(modelData.author || "")
                                          + (modelData.createdAt && modelData.createdAt.getTime
                                             && !isNaN(modelData.createdAt.getTime())
                                             ? " · " + AppController.shortDate(modelData.createdAt) : "")
                                    textFormat: Text.PlainText
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fsXs
                                }
                                // Every tracker's comments can be opened where
                                // they live; Jira and GitLab had no link at all.
                                Text {
                                    objectName: "te-comment-link"
                                    visible: String(modelData.url || "").length > 0
                                    text: "↗ " + I18n.t("ticket.openComment")
                                    color: commentLinkMA.containsMouse ? Theme.accent : Theme.accentStrong
                                    font.pixelSize: Theme.fsXs
                                    MouseArea {
                                        id: commentLinkMA
                                        anchors.fill: parent
                                        anchors.margins: -3
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const url = String(modelData.url || "");
                                            if (AppController.isSafeLink(url)) Qt.openUrlExternally(url);
                                        }
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: String(modelData.body || "")
                                // Written by whoever commented upstream.
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.pixelSize: Theme.fsSm
                                wrapMode: Text.WordWrap
                                maximumLineCount: 6
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Item { implicitHeight: 1 }
            }
        }

        // ── Footer: always on screen, however long the body gets ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }
        Text {
            objectName: "te-error"
            visible: root._error.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.topMargin: Theme.spMd
            text: root._error
            textFormat: Text.PlainText
            color: Theme.danger
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.topMargin: Theme.spXl; Layout.bottomMargin: Theme.spXl
            spacing: Theme.spMd
            PillButton {
                objectName: "te-delete"
                visible: !root.isNew
                text: I18n.t("common.delete")
                danger: true
                onClicked: {
                    // Delete the row that was opened, keyed by the stable
                    // open-time id — NOT the live idField, which the user may
                    // have edited (Save threads _originalId for the same reason).
                    AppController.deleteTask(root._originalId);
                    root.close();
                }
            }
            // Archive one task without leaving the editor for a menu. Pending
            // edits are saved first, so the archived task is the edited one.
            PillButton {
                objectName: "te-archive"
                visible: !root.isNew
                text: root._archived ? I18n.t("editor.btn.unarchive") : I18n.t("editor.btn.archive")
                onClicked: {
                    const wasArchived = root._archived;
                    if (root.isDirty() && !root._commit()) return;
                    const id = idField.text.trim().length > 0 ? idField.text.trim() : root._originalId;
                    AppController.setArchived(id, !wasArchived);
                    root.close();
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Ctrl+Enter"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
            }
            PillButton {
                text: I18n.t("common.cancel")
                onClicked: root.close()
            }
            PillButton {
                text: root.isNew ? I18n.t("editor.btn.create") : I18n.t("editor.btn.save")
                primary: true
                onClicked: root._save()
            }
        }
    }

    // ── Unsaved changes: save, discard or keep editing ──
    Popup {
        id: discardPrompt
        objectName: "te-discard-prompt"
        parent: root.contentItem
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        padding: Theme.inset
        width: Math.min(380, root.width - 2 * Theme.inset)
        background: Rectangle {
            radius: Theme.radiusXl
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }
        Overlay.modal: Rectangle { color: Theme.scrim }
        onOpened: promptBody.forceActiveFocus()
        function keep() { discardPrompt.close(); titleField.forceActiveFocus(); }
        function discard() { discardPrompt.close(); root.close(); }
        function save() { discardPrompt.close(); root._save(); }
        contentItem: ColumnLayout {
            id: promptBody
            spacing: Theme.spLg
            focus: true
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape || e.key === Qt.Key_K) { discardPrompt.keep(); e.accepted = true; }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_S) { discardPrompt.save(); e.accepted = true; }
                else if (e.key === Qt.Key_D) { discardPrompt.discard(); e.accepted = true; }
            }
            Text {
                Layout.fillWidth: true
                text: I18n.t("editor.dirty.title")
                color: Theme.text
                font.pixelSize: Theme.fsLg
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                text: I18n.t("editor.dirty.body")
                color: Theme.textMuted
                font.pixelSize: Theme.fsMd
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spMd
                PillButton {
                    objectName: "te-dirty-discard"
                    text: I18n.t("editor.dirty.discard") + "  D"
                    danger: true
                    onClicked: discardPrompt.discard()
                }
                Item { Layout.fillWidth: true }
                PillButton {
                    objectName: "te-dirty-keep"
                    text: I18n.t("editor.dirty.keep") + "  Esc"
                    onClicked: discardPrompt.keep()
                }
                PillButton {
                    objectName: "te-dirty-save"
                    text: I18n.t("editor.btn.save") + "  ↵"
                    primary: true
                    onClicked: discardPrompt.save()
                }
            }
        }
    }

    // A small toggle chip for the description's mode row.
    component SegChip: Rectangle {
        id: seg
        property string text
        property bool active: false
        signal clicked()
        radius: Theme.radiusPill
        color: active ? Theme.accentSoft : (segMA.containsMouse ? Theme.panel3 : "transparent")
        border.color: activeFocus ? Theme.focusRing : active ? Theme.withAlpha(Theme.accent, 0.5) : "transparent"
        border.width: activeFocus ? 2 : 1
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: seg.text
        Keys.onSpacePressed: seg.clicked()
        Keys.onReturnPressed: seg.clicked()
        implicitWidth: segT.implicitWidth + 16
        implicitHeight: segT.implicitHeight + 6
        Text {
            id: segT
            anchors.centerIn: parent
            text: seg.text
            color: seg.active ? Theme.accentStrong : (segMA.containsMouse ? Theme.text : Theme.textMuted)
            font.pixelSize: Theme.fsSm
        }
        MouseArea {
            id: segMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: seg.clicked()
        }
    }

    component FieldLabel: Text {
        color: Theme.textMuted
        font.pixelSize: Theme.fsXs
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        topPadding: Theme.sp2xs
    }
    component FieldBg: Rectangle {
        radius: Theme.radiusMd
        color: Theme.panel2
        border.color: Theme.border
        border.width: 1
    }
    // Parses the description for the preview. Same engine the notes editor
    // uses, so a checklist behaves the same in both places.
    MdDocument {
        id: descDocument
        text: descField.text
        allowRemoteImages: false
        palette: Theme.mdPalette
    }

}
