import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp

Popup {
    id: root
    // Standalone it is the whole window — there is nothing behind it to
    // dim or block, so no scrim.
    modal: !root.standalone
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 560
    // Standalone: hosted by CaptureWindow, a small window of its own that the
    // global hotkey brings up without the main window. The popup sits at the
    // top of that window so the mention dropdown has room below it.
    property bool standalone: false
    anchors.centerIn: root.standalone ? undefined : Overlay.overlay
    x: root.standalone ? Math.round((root.parent.width - root.width) / 2) : 0
    y: root.standalone ? Theme.sp2xl : 0

    Overlay.modal: Rectangle {
        color: Theme.scrim
    }

    // What was just created, for the confirmation the owner shows: a toast in
    // the app, an OS notification when captured from outside it. `taskId` is
    // the task behind it, if any, so clicking the notification can open it.
    signal captured(string title, string body, string taskId)

    property var _preview: ({ok: false})
    property var _meta: ({title: "", desc: "", handles: [], ticketKey: "", priority: "", labels: []})
    property string _title: ""
    // Ctrl+Enter adds and stays open for the next item; this is what the
    // last one became, shown in place of a toast the popup would cover.
    property bool keepOpen: false
    property string _lastAdded: ""
    // Enter with nothing but a date ("tomorrow") used to do nothing at all.
    property string _hint: ""

    // Single source of truth lives in heap::text::extractMeta (C++) and is
    // unit-tested. QML just forwards.
    // A ticket key another task already holds cannot be the new task's id
    // (newQuickTaskDraft falls back to the prefix), so it stays in the title:
    // "APP-101 follow up with QA" used to lose its only link to the ticket
    // (TASKS-22, audit 2026-09-30).
    function _extractMeta(raw) {
        const meta = AppController.extractTaskMeta(raw || "");
        if (meta.ticketKey && AppController.taskById(meta.ticketKey).id)
            return AppController.extractTaskMeta(raw || "", true);
        return meta;
    }

    function _resolvePeopleNames(handles) {
        if (!handles || handles.length === 0) return [];
        const out = [];
        const known = AppController.people;
        for (let i = 0; i < handles.length; ++i) {
            const h = handles[i];
            const p = AppController.personById(h);
            if (p && p.id) { out.push(p.name || p.id); continue; }
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

    function _refreshPreview() {
        const raw = inputField.text;
        const meta = _extractMeta(raw);
        _meta = meta;
        const r = AppController.parseDateTime(meta.title, new Date());
        _preview = r || {ok: false};
        if (_preview.ok && _preview.consumed && _preview.consumed.length > 0) {
            const left  = meta.title.substr(0, _preview.startOffset).trim();
            const right = meta.title.substr(_preview.endOffset).trim();
            _title = (left + " " + right).replace(/\s+/g, " ").trim();
        } else {
            _title = meta.title.trim();
        }
    }

    // Detect intent from free-text. Returns "focus" | "sync" | "ticket" | "none".
    //  focus  → schedule a focus block in the calendar
    //  sync   → schedule a meeting-style event (with созвоны)
    //  ticket → task only, NO calendar entry
    //  none   → task only, no calendar entry (default — was "focus" before)
    // Forwards to heap::text::classifyKind (C++, unit-tested).
    function _classifyKind(text) {
        return AppController.classifyTaskKind(text || "");
    }

    // Resolve @handles to existing Person rows. Returns ids of matches only
    // (unknown handles are dropped — no task fallback for unresolved targets).
    function _resolvePeopleIds(handles) {
        if (!handles || handles.length === 0) return [];
        const out = [];
        const known = AppController.people;
        for (let i = 0; i < handles.length; ++i) {
            const h = handles[i];
            const p = AppController.personById(h);
            if (p && p.id) { out.push(p.id); continue; }
            for (let j = 0; j < known.rowCount(); ++j) {
                const idx = known.index(j, 0);
                const id  = String(known.data(idx, Qt.UserRole + 1) || "");
                const nm  = String(known.data(idx, Qt.UserRole + 2) || "");
                const firstWord = nm.split(/\s+/)[0] || "";
                if (id.toLowerCase() === h.toLowerCase()
                    || firstWord.toLowerCase() === h.toLowerCase()) {
                    out.push(id);
                    break;
                }
            }
        }
        return out;
    }

    // "Tomorrow, Thu 1 Oct, 15:00" — the day named the way people say it when
    // it is close, then the date so it can be checked at a glance.
    function _when(d, hasTime) {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        const diff = Math.round((day - today) / 86400000);
        const rel = ["quick.day.yesterday", "quick.day.today", "quick.day.tomorrow",
                     "quick.day.afterTomorrow"][diff + 1];
        let out = rel ? I18n.t(rel) + ", " + d.toLocaleDateString(I18n.locale, "ddd d MMM")
                      : d.toLocaleDateString(I18n.locale, "dddd, d MMMM");
        if (hasTime) out += ", " + d.toLocaleTimeString(I18n.locale, "HH:mm");
        return out;
    }
    function _cap(t) { return t.charAt(0).toUpperCase() + t.slice(1); }

    function _recurLabel(r) {
        const keys = {
            "every:day": "daily", "every:week": "weekly", "every:weekday": "weekdays",
            "every:mon": "everyMon", "every:tue": "everyTue", "every:wed": "everyWed",
            "every:thu": "everyThu", "every:fri": "everyFri", "every:sat": "everySat",
            "every:sun": "everySun", "every:month": "monthly"
        };
        const monthly = /^every:month:(\d+)$/.exec(String(r || ""));
        if (monthly) {
            const l = I18n.t("editor.recur.monthlyOn").arg(monthly[1]);
            return l.charAt(0).toLowerCase() + l.slice(1);
        }
        // Mid-sentence: "Повтор: по будням", not "Повтор: По будням".
        const label = keys[r] ? I18n.t("editor.recur." + keys[r]) : r;
        return label.charAt(0).toLowerCase() + label.slice(1);
    }

    function _statusName(id) {
        const sts = AppController.statuses;
        for (let i = 0; i < sts.length; ++i)
            if (sts[i].id === id) return sts[i].name;
        return id;
    }

    // The confirmation for what a capture made, written to be read in a
    // notification: the headline says what it is and where it went, the body
    // gives the title in quotes and then only the things that were set.
    //   kind  "task" | "focus" | "meeting" | "untimedMeeting"
    //   ev    the booked event, for a meeting
    function _summary(kind, draft, ev) {
        const lines = [I18n.t("quick.quote").arg(draft.title)];
        let title;
        if (kind === "meeting") {
            title = I18n.t("quick.done.meeting." + ev.type);
            lines.push(root._cap(root._when(draft.dueAt, false)) + ", "
                       + AppController.eventHourLabel(ev.start) + "–" + AppController.eventHourLabel(ev.end));
            if (ev.attendees) lines.push(I18n.t("quick.done.with").arg(ev.attendees));
        } else if (kind === "focus") {
            title = I18n.t("quick.done.focus");
            lines.push(root._cap(root._when(draft.dueAt, true)));
        } else {
            title = I18n.t("quick.done.task").arg(root._statusName(draft.status));
            if (draft.dueAt && draft.dueAt.getTime && !isNaN(draft.dueAt.getTime()))
                lines.push(I18n.t("quick.done.due").arg(root._when(draft.dueAt, draft.dueHasTime)));
            if (kind === "untimedMeeting") lines.push(I18n.t("quick.done.noTime"));
        }
        if (draft.recurrence)
            lines.push(I18n.t("quick.done.repeat").arg(root._recurLabel(draft.recurrence)));
        if (root._meta.priority)
            lines.push(I18n.t("quick.done.priority").arg(draft.priority));
        if (draft.labels && draft.labels.length > 0)
            lines.push(I18n.t("quick.done.labels").arg(draft.labels.join(", ")));
        if (root._meta.ticketKey && draft.id === root._meta.ticketKey)
            lines.push(I18n.t("quick.done.ticket").arg(draft.id));
        if (draft.desc) lines.push(I18n.t("quick.done.note").arg(draft.desc));
        if (kind === "meeting")
            lines.push(I18n.t("quick.done.alsoTask").arg(root._statusName(draft.status)));
        return { title: title, body: lines.join("\n"), taskId: draft.id };
    }

    function _finish(summary) {
        inputField.clear();
        root._hint = "";
        if (root.keepOpen) {
            root._lastAdded = summary ? summary.title + " — " + String(summary.body || "").split("\n")[0] : "";
            inputField.forceActiveFocus();
        } else {
            root.close();
        }
        if (summary) root.captured(summary.title, summary.body, summary.taskId || "");
    }

    // Enter adds and closes; Ctrl+Enter adds and stays open for the next one.
    function _submitFromKey(keep) {
        root.keepOpen = keep;
        root._submit();
    }

    function _submit() {
        // Recompute from the CURRENT text before reading anything. _meta/_title/
        // _preview are otherwise only refreshed on an 80ms debounce, so hitting
        // Enter right after typing (or after the mention popup rewrote the field)
        // submits stale values: the "// comment" tail is dropped, and the parsed
        // time/handles can lag a keystroke behind. Refreshing here makes submit a
        // pure function of what is on screen.
        _refreshPreview();
        if (_title.length === 0) {
            // Say why nothing happened: a date alone is not a task.
            root._hint = (_preview && _preview.ok) ? I18n.t("quick.hint.onlyDate") : "";
            return;
        }

        // ── Contact-ping path ──
        // "написать @viktor про релиз" routes to PeopleList (bottom-right),
        // not the Kanban. Each ping is a NEW Person row (duplicates are
        // allowed: different requests for the same contact are different
        // pings). Resolved handles inherit the existing person's name /
        // role / color; unresolved handles get a "@handle" placeholder.
        const kindEarly = _classifyKind(inputField.text);
        if (kindEarly === "contact" && _meta && _meta.handles
            && _meta.handles.length > 0)
        {
            // Question text = title with @handles stripped (verb stays so
            // the action reads naturally in the contact card).
            const question = String(_meta.title || "")
                .replace(/(^|[\s,;(])@[A-Za-zА-Яа-яЁё0-9_.\-]+/g, "$1")
                .replace(/\s+/g, " ").trim();
            const palette = Theme.swatches;
            const who = [];
            for (let i = 0; i < _meta.handles.length; ++i) {
                const h = _meta.handles[i];
                const existing = AppController.personById(h) || {};
                const draft = AppController.newPersonDraft();
                draft._isNew = true;
                draft.id     = "";   // savePerson re-slugs from the name
                draft.name   = existing.name && String(existing.name).length > 0
                                ? existing.name
                                : "@" + h;
                draft.role   = existing.role     || "";
                draft.color  = existing.color    || palette[i % palette.length];
                draft.question = question;
                draft.state  = "todo";
                AppController.savePerson(draft);
                who.push(draft.name);
            }
            root._finish({
                title: I18n.t("quick.done.ping").arg(who.join(", ")),
                body: question.length > 0 ? I18n.t("quick.quote").arg(question) : ""
            });
            return;
        }

        // QuickCapture tasks: the "To Do" column, with the id of the ticket the
        // text names ("LTE-2398 …") or the profile prefix.
        // Title, "// description", priority, #labels, the parsed date (clock
        // time included, HEAP-115) and recurrence (HEAP-77): built in C++, the
        // same draft `heap add` saves from the command line (APP-173).
        const draft = AppController.quickTaskDraft(inputField.text, new Date());
        // A meeting is a task and its calendar event: one undo step for both.
        AppController.beginUndoGroup(I18n.t("quick.undo").arg(draft.id));
        try {
            root._submitTask(draft, kindEarly);
        } finally {
            AppController.endUndoGroup();
        }
    }

    function _submitTask(draft, kindEarly) {
        AppController.saveTask(draft);

        // Calendar entry rules. A parsed time is already stored on the task and
        // shows up on the Day view, so only a meeting still needs an event:
        //  - "ticket"/"задача" → never schedule (pure todo item)
        //  - "focus"           → the task's own scheduled time is the block
        //  - "sync"/"созвон"   → meeting on calendar (right column with созвоны)
        //  - none of the above → no calendar entry even if a time was parsed
        const noTime = !(_preview && _preview.ok && _preview.hasTime && _preview.start);
        // Reuse the kind we already computed for the contact-ping check.
        const kind = kindEarly;
        if (noTime) {
            root._finish(root._summary(kind === "sync" ? "untimedMeeting" : "task", draft, null));
            return;
        }
        if (kind === "ticket") { root._finish(root._summary("task", draft, null)); return; }

        const d         = _preview.start;
        const startHour = d.getHours() + d.getMinutes() / 60.0;

        if (kind === "focus") {
            AppController.selectedDate = d;
            root._finish(root._summary("focus", draft, null));
            return;
        }
        if (kind === "sync") {
            // Honour parsed range "12:00-13:00", else default 30 min.
            let endHour = startHour + 0.5;
            const pe = _preview.end;
            if (pe && pe.getTime && pe.getTime() > 0) {
                const eh = pe.getHours() + pe.getMinutes() / 60.0;
                if (eh > startHour) endHour = eh;
            }
            const attendees = _resolvePeopleNames(_meta.handles).join(", ");
            const ev = AppController.newEventDraft(startHour, d);
            // Standup, 1:1, team sync — or, for a call or a meeting that is
            // none of those, an untyped one-off.
            ev.type      = AppController.meetingType(inputField.text);
            ev.title     = _title.substring(0, 40);
            ev.end       = endHour;
            ev.taskId    = draft.id;
            ev.date      = d;
            ev.attendees = attendees;
            // The "// comment" tail rides along onto the meeting itself, not
            // just the linked task — it lands in the event's free-form context
            // so the note shows up on the calendar block too.
            if (_meta && _meta.desc && _meta.desc.length > 0) {
                ev.context = _meta.desc;
            }
            AppController.saveEvent(ev);
            AppController.selectedDate = d;
            root._finish(root._summary("meeting", draft, ev));
            return;
        }
        // kind === "none" → task with deadline only, no calendar entry.

        root._finish(root._summary("task", draft, null));
    }

    // Opt-in timing (HEAP_PERF_LOG=1 / --perf-log): hotkey or open() to the
    // first frame that shows the popup. Logs only; a no-op otherwise.
    onAboutToShow: AppController.perfMarkShown("capture", contentItem)
    onOpened: {
        inputField.text = "";
        _preview = {ok: false};
        _title = "";
        _hint = "";
        _lastAdded = "";
        keepOpen = false;
        at.dismiss();
        inputField.forceActiveFocus();
    }

    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: Theme.spLg
        Item {
            Layout.preferredHeight: 6
        }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("quick.title")
            color: Theme.textMuted
            font.pixelSize: Theme.fsXs
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }

        TextField {
            id: inputField
            objectName: "qc-input"
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            placeholderText: I18n.t("quick.fieldPh")
            font.pixelSize: Theme.fsLg
            background: FieldFrame {}
            color: Theme.text
            placeholderTextColor: Theme.textDim
            onTextChanged: { previewTimer.restart(); at.refresh(); root._hint = ""; }
            onCursorPositionChanged: at.refresh()
            Keys.onPressed: (e) => {
                if (at.isOpen) {
                    if (e.key === Qt.Key_Down) {
                        at.moveSelection(+1);
                        e.accepted = true;
                        return;
                    }
                    if (e.key === Qt.Key_Up) {
                        at.moveSelection(-1);
                        e.accepted = true;
                        return;
                    }
                    if (e.key === Qt.Key_Tab
                        || (e.key === Qt.Key_Return && (e.modifiers & Qt.ShiftModifier))
                        || (e.key === Qt.Key_Enter && (e.modifiers & Qt.ShiftModifier))) {
                        // Tab or Shift+Enter → insert suggestion, stay in field.
                        if (at.accept()) {
                            e.accepted = true;
                            return;
                        }
                    }
                    if (e.key === Qt.Key_Escape) {
                        at.dismiss();
                        e.accepted = true; return;
                    }
                }
            }
            // Enter takes a suggestion only once the arrows have picked one:
            // "#backend" is a label and "@maria" a person as typed, and Enter
            // used to rewrite them into whichever task or id came first in the
            // list (#TASK-2700). Tab always takes the highlighted one.
            Keys.onReturnPressed: (e) => {
                if (at.isOpen && at.navigated) {
                    at.accept();
                    return;
                }
                at.dismiss();
                root._submitFromKey((e.modifiers & Qt.ControlModifier) !== 0);
            }
            Keys.onEnterPressed: (e) => {
                if (at.isOpen && at.navigated) {
                    at.accept();
                    return;
                }
                at.dismiss();
                root._submitFromKey((e.modifiers & Qt.ControlModifier) !== 0);
            }
        }

        Timer {
            id: previewTimer
            interval: 80
            repeat: false
            onTriggered: root._refreshPreview()
        }

        RowLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            spacing: Theme.spMd
            Text {
                visible: root._title.length > 0
                text: "" + root._title
                color: Theme.text
                font.pixelSize: Theme.fsMd
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Rectangle {
                visible: root._preview && root._preview.ok
                radius: Theme.radiusLg
                color: Theme.panel2
                border.color: Theme.accent
                border.width: 1
                implicitHeight: previewChip.implicitHeight + 6
                implicitWidth: previewChip.implicitWidth + 16
                Text {
                    id: previewChip
                    anchors.centerIn: parent
                    color: Theme.text
                    font.pixelSize: Theme.fsSm
                    text: {
                        if (!root._preview || !root._preview.ok) return "";
                        const d = root._preview.start;
                        if (!d) return "";
                        const iso = d.getFullYear() + "-" +
                            String(d.getMonth() + 1).padStart(2, "0") + "-" +
                            String(d.getDate()).padStart(2, "0");
                        if (root._preview.hasTime) {
                            const hh = String(d.getHours()).padStart(2, "0");
                            const mm = String(d.getMinutes()).padStart(2, "0");
                            return iso + " " + hh + ":" + mm;

                        }
                        return iso;
                    }
                }
            }
        }

        // Why Enter did nothing, or what the last Ctrl+Enter added.
        Text {
            objectName: "qc-hint"
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            visible: text.length > 0
            text: root._hint.length > 0 ? root._hint
                                        : (root._lastAdded.length > 0 ? "✓ " + root._lastAdded : "")
            textFormat: Text.PlainText
            color: root._hint.length > 0 ? Theme.warning : Theme.textMuted
            font.pixelSize: Theme.fsSm
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.bottomMargin: Theme.sp2xl
            spacing: Theme.spMd
            Text {
                text: I18n.t("quick.keysHint")
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
            }
            Item {
                Layout.fillWidth: true
            }
            PillButton {
                text: I18n.t("common.cancel")
                onClicked: root.close()
            }
            PillButton {
                text: I18n.t("editor.btn.create")
                primary: true
                enabled: root._title.length > 0
                onClicked: root._submit()
            }
        }
    }

    MentionAutocomplete {
        id: at
        target: inputField
    }
}
