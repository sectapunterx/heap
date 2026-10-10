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
    // X-Oth-Capture: 600 px, hints only, no buttons (DG-130).
    width: Theme.px(600)
    // Standalone: hosted by CaptureWindow, a small window of its own that the
    // global hotkey brings up without the main window. The popup sits at the
    // top of that window so the mention dropdown has room below it.
    property bool standalone: false
    anchors.centerIn: root.standalone ? undefined : Overlay.overlay
    x: root.standalone ? Math.round((root.parent.width - root.width) / 2) : 0
    y: root.standalone ? Theme.sp2xl : 0

    Overlay.modal: ModalScrim {}

    // What was just created, for the confirmation the owner shows: a toast in
    // the app, an OS notification when captured from outside it. `taskId` is
    // the task behind it, if any, so clicking the notification can open it.
    signal captured(string title, string body, string taskId)
    // The "seen this before" hint under the field was clicked (APP-159).
    signal seenBeforeActivated(var hit)
    // Tab: the task document with what was typed (APP-266). Only in the app;
    // the standalone capture keeps Tab for moving on.
    signal openFullRequested(var draft)
    // "APP-101 is already there — open it?"
    signal openTaskRequested(string id)

    property var _preview: ({ok: false})
    // The parse of the current text (AppController.captureParse).
    property var _parsed: ({})
    // Recognised phrases taken back with a chip's ×: words again, for this
    // input only.
    property var _rejected: []
    // The column the task goes to (APP-266 chip "Column").
    property string _status: "todo"
    property string _openStatus: ""
    // "+" on a column: the input, already pointed at that column.
    function openIn(statusId) {
        root._openStatus = statusId || "";
        root.open();
    }
    // Several lines came in one paste: asked once, "N tasks or one?".
    property bool _pastedLines: false
    property bool _askLines: false
    property int _prevNewlines: 0
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
            // "@r.losev" for Роман Лосев: a login made of one person's name.
            const byLogin = matched ? "" : AppController.personIdForHandle(h);
            if (byLogin) out.push(AppController.personById(byLogin).name || byLogin);
            else if (!matched) out.push("@" + h);
        }
        return out;
    }

    function _refreshPreview() {
        const raw = inputField.text;
        const meta = _extractMeta(raw);
        _meta = meta;
        // When and the deadline apart (APP-245): "в пн, до пт" is two dates.
        const p = AppController.captureParse(raw, new Date(), root._rejected);
        root._parsed = p;
        const when = p.when && p.when.getTime && !isNaN(p.when.getTime()) ? p.when : null;
        const due = p.due && p.due.getTime && !isNaN(p.due.getTime()) ? p.due : null;
        _preview = {
            ok: when !== null || due !== null,
            // The meeting / focus block goes at "when"; a deadline alone books nothing.
            start: when, hasTime: when !== null && p.whenHasTime,
            end: p.whenEnd,
            due: due, dueHasTime: due !== null && p.dueHasTime,
            whenPast: !!p.whenPast, duePast: !!p.duePast,
            estimate: p.estimateMinutes
        };
        _title = p.title;
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
            let matched = false;
            for (let j = 0; j < known.rowCount(); ++j) {
                const idx = known.index(j, 0);
                const id  = String(known.data(idx, Qt.UserRole + 1) || "");
                const nm  = String(known.data(idx, Qt.UserRole + 2) || "");
                const firstWord = nm.split(/\s+/)[0] || "";
                if (id.toLowerCase() === h.toLowerCase()
                    || firstWord.toLowerCase() === h.toLowerCase()) {
                    out.push(id);
                    matched = true;
                    break;
                }
            }
            // "@r.losev" for Роман Лосев: a login made of one person's name.
            const byLogin = matched ? "" : AppController.personIdForHandle(h);
            if (byLogin) out.push(byLogin);
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
        let out = rel ? I18n.t(rel) + ", " + I18n.fmtDate(d, "weekdayDay")
                      : I18n.fmtDate(d, "longWeekday");
        if (hasTime) out += ", " + I18n.fmtTime(d);
        return out;
    }
    // A chip's date as the sheet writes it: "пт, 9 окт · 11:00" (R3-098);
    // the toast keeps the relative word.
    function _chipWhen(d, hasTime) {
        let out = I18n.fmtDate(d, "weekdayDay");
        if (hasTime) out += " · " + I18n.fmtTime(d);
        return out;
    }
    // "из ветки fix/APP-105 — связать?" (R3-097): the checked-out branch,
    // offered as the new task's branch; a click takes it, a second drops it.
    property bool linkBranch: false
    readonly property string _branch: AppController.focusedBranch
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
        const plan = Object.assign({}, draft);  // when: plan.scheduledAt
        let title;
        if (kind === "meeting") {
            title = I18n.t("quick.done.meeting." + ev.type);
            lines.push(root._cap(root._when(plan.scheduledAt, false)) + ", "
                       + AppController.eventHourLabel(ev.start) + "–" + AppController.eventHourLabel(ev.end));
            if (ev.attendees) lines.push(I18n.t("quick.done.with").arg(ev.attendees));
        } else if (kind === "focus") {
            title = I18n.t("quick.done.focus");
            lines.push(root._cap(root._when(plan.scheduledAt, true)));
        } else {
            title = I18n.t("quick.done.task").arg(root._statusName(draft.status));
            // When and the deadline, each named (APP-245).
            if (plan.scheduledAt && plan.scheduledAt.getTime && !isNaN(plan.scheduledAt.getTime()))
                lines.push(I18n.t("quick.done.when").arg(root._when(plan.scheduledAt, plan.scheduledHasTime)));
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

    // Ctrl+Enter adds and closes; Ctrl+Shift+Enter adds and stays open for
    // the next one. Enter and Shift+Enter start a new line (APP-209): the
    // lines after the first are the task's description.
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
        // Several pasted lines: one question, then the answer decides.
        if (root._pastedLines && root._lineCount() > 1) {
            root._askLines = true;
            return;
        }
        if (inputField.text.trim().length === 0) return;
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
        const draft = AppController.quickTaskDraft(inputField.text, new Date(), root._rejected);
        draft.status = root._status;
        if (root.linkBranch && root._branch.length > 0) draft.branch = root._branch;
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

        // A calendar meeting only when asked for, with the box "Also a
        // meeting" (APP-266): the time is already on the task itself and
        // shows on the day; the words "созвон"/"sync" no longer book one.
        const noTime = !(_preview && _preview.start && _preview.hasTime);
        const kind = kindEarly;
        if (noTime || !meetingBox.checked) {
            root._finish(root._summary("task", draft, null));
            return;
        }

        const d         = _preview.start;
        const startHour = d.getHours() + d.getMinutes() / 60.0;
        {
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
        }
    }

    // ── several lines ──
    function _lineCount() {
        return inputField.text.split("\n").filter(l => l.trim().length > 0).length;
    }
    // "N tasks": each line its own task, read the same way.
    function _submitEachLine() {
        const lines = inputField.text.split("\n").filter(l => l.trim().length > 0);
        AppController.beginUndoGroup(I18n.t("capture.undo.many").arg(lines.length));
        let last = "";
        try {
            for (const line of lines) {
                const d = AppController.quickTaskDraft(line, new Date());
                if (String(d.title).length === 0) continue;
                d.status = root._status;
                AppController.saveTask(d);
                last = d.id;
            }
        } finally {
            AppController.endUndoGroup();
        }
        root._pastedLines = false;
        root._askLines = false;
        root._finish({ title: I18n.t("capture.done.many").arg(lines.length), body: "", taskId: last });
    }
    // "One with a description": the first line is the task, the rest its text.
    function _submitAsOne() {
        root._pastedLines = false;
        root._askLines = false;
        root._submit();
    }

    // One line for the toast (APP-266): "Created APP-12 · tomorrow 15:00 · To Do".
    function headline(taskId) {
        const t = AppController.taskById(taskId);
        if (!t || !t.id) return "";
        const parts = [t.id];
        const sch = t.scheduledAt, due = t.dueAt;
        if (sch && sch.getTime && !isNaN(sch.getTime())) parts.push(root._when(sch, t.scheduledHasTime));
        else if (due && due.getTime && !isNaN(due.getTime())) parts.push(I18n.t("capture.due") + " " + root._when(due, t.dueHasTime));
        parts.push(root._statusName(t.status));
        return I18n.t("capture.done").arg(parts.join(" · "));
    }
    // A chip's ×: its words go back into the title, for this input only.
    function rejectSpan(kind) {
        const spans = (root._parsed && root._parsed.spans) || [];
        for (let i = 0; i < spans.length; i++) {
            if (spans[i].kind !== kind) continue;
            root._rejected = root._rejected.concat([spans[i].text]);
            break;
        }
        root._refreshPreview();
        inputField.forceActiveFocus();
    }

    // Opt-in timing (HEAP_PERF_LOG=1 / --perf-log): hotkey or open() to the
    // first frame that shows the popup. Logs only; a no-op otherwise.
    onAboutToShow: AppController.perfMarkShown("capture", contentItem)
    // The command line's "nothing found · create «…»" (APP-267): the input
    // opens with those words in it.
    property string _openText: ""
    function openWithText(text) {
        root._openText = text || "";
        root.open();
    }
    onOpened: {
        inputField.text = "";
        _preview = {ok: false};
        _parsed = ({});
        _rejected = [];
        _status = _openStatus.length > 0 ? _openStatus : "todo";
        _openStatus = "";
        _pastedLines = false;
        _askLines = false;
        _prevNewlines = 0;
        meetingBox.checked = false;
        _title = "";
        _hint = "";
        _lastAdded = "";
        keepOpen = false;
        linkBranch = false;
        at.dismiss();
        if (_openText.length > 0) {
            inputField.text = _openText;
            inputField.cursorPosition = inputField.length;
        }
        _openText = "";
        inputField.forceActiveFocus();
    }

    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: Theme.spLg
        Item {
            Layout.preferredHeight: 6
        }

        // "lowkey · new task", the profile it goes to on the right.
        RowLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            spacing: Theme.spMd
            // The wordmark before the label, as on the quick note (R3-096).
            Item {
                Layout.preferredWidth: qcLogo.implicitWidth
                Layout.preferredHeight: qcLogo.height
                BrandLogo {
                    id: qcLogo
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "wordmark"
                    theme: Theme.dark ? "dark" : "light"
                    height: Theme.fsSm
                }
            }
            Text {
                text: I18n.t("capture.title")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                font.weight: Theme.fwTitle
            }
            Item { Layout.fillWidth: true }
            // "в Example ▾": the profile the task goes to; the menu opens
            // another one (the task lands in the profile the app is in).
            Item {
                objectName: "qc-profile"
                implicitWidth: profRow.implicitWidth
                implicitHeight: profRow.implicitHeight
                Layout.maximumWidth: Theme.px(220)
                Row {
                    id: profRow
                    spacing: Theme.spXs
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.t("capture.inProfile").arg(AppController.profileById(AppController.activeProfileId).name || "")
                        color: profCA.hovered ? Theme.text : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, Theme.px(200))
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-down"
                        size: Theme.iconSize - 4
                        color: profCA.hovered ? Theme.text : Theme.textMuted
                    }
                }
                ClickArea {
                    id: profCA
                    label: I18n.t("capture.inProfile").arg(AppController.profileById(AppController.activeProfileId).name || "")
                    enabled: AppController.profiles.length > 1
                    onActivated: profileMenu.popup(profRow, 0, profRow.height + Theme.spXs)
                }
                AppMenu {
                    id: profileMenu
                    Instantiator {
                        model: AppController.profiles
                        delegate: AppMenuItem {
                            id: profItem
                            required property var modelData
                            text: profItem.modelData.name
                            marked: profItem.modelData.id === AppController.activeProfileId
                            onTriggered: {
                                AppController.activeProfileId = profItem.modelData.id;
                                Qt.callLater(() => inputField.forceActiveFocus());
                            }
                        }
                        onObjectAdded: (idx, obj) => profileMenu.insertItem(idx, obj)
                        onObjectRemoved: (idx, obj) => profileMenu.removeItem(obj)
                    }
                }
            }
        }

        // A few lines tall at most; a longer text scrolls.
        ScrollView {
            id: inputScroll
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            Layout.preferredHeight: Math.min(inputField.implicitHeight, Theme.rowH * 4)
            clip: true

            TextArea {
                id: inputField
                ContextMenu.menu: TextEditMenu { editor: inputField }
                objectName: "qc-input"
                placeholderText: I18n.t("quick.fieldPh")
                // 16px medium (N/X-Oth-Capture, R3-098).
                font.pixelSize: Theme.typeStep(2)
                font.weight: Theme.fwTitle
                wrapMode: TextEdit.Wrap
                // A line under the text, not a box (X-Oth-Capture).
                leftPadding: Theme.sp2xs
                rightPadding: Theme.sp2xs
                topPadding: Theme.spXs
                bottomPadding: Theme.spMd
                background: Item {
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: 1
                        color: inputField.activeFocus ? Theme.borderStrong : Theme.border
                    }
                }
                color: Theme.text
                placeholderTextColor: Theme.textDim
                selectByMouse: true
                onTextChanged: {
                    // A paste that brought line breaks with it (typed ones come
                    // one at a time, with Shift+Enter).
                    const n = (inputField.text.match(/\n/g) || []).length;
                    if (n > root._prevNewlines + 0 && n - root._prevNewlines >= 1 && !inputField._typedNewLine)
                        root._pastedLines = true;
                    if (n === 0) root._pastedLines = false;
                    root._prevNewlines = n;
                    inputField._typedNewLine = false;
                    root._askLines = false;
                    previewTimer.restart(); at.refresh(); root._hint = "";
                }
                property bool _typedNewLine: false
                // The recognised parts in colour, right in the line (APP-266).
                SpanHighlighter {
                    target: inputField.textDocument
                    spans: (root._parsed && root._parsed.marks) || []
                    // Every recognised word in the accent, as the sheet
                    // draws "завтра 11:00 p1" (R3-098).
                    colors: ({ when: Theme.accentStrong, due: Theme.accentStrong, estimate: Theme.accentStrong,
                               priority: Theme.accentStrong, label: Theme.textMuted })
                }
                onCursorPositionChanged: at.refresh()

                // Enter and Shift+Enter both write a plain "\n" (Shift+Enter
                // in a text area is otherwise a Unicode line separator).
                function newLine() {
                    inputField._typedNewLine = true;
                    if (inputField.selectedText.length > 0)
                        inputField.remove(inputField.selectionStart, inputField.selectionEnd);
                    inputField.insert(inputField.cursorPosition, "\n");
                }

                Keys.onPressed: (e) => {
                    const enter = e.key === Qt.Key_Return || e.key === Qt.Key_Enter;
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
                        // Tab takes the highlighted suggestion and stays in the field.
                        if (e.key === Qt.Key_Tab && at.accept()) {
                            e.accepted = true;
                            return;
                        }
                        // Plain Enter takes a suggestion only once the arrows
                        // have picked one: "#backend" is a label and "@maria" a
                        // person as typed, and Enter used to rewrite them into
                        // whichever task or id came first in the list (#TASK-2700).
                        if (enter && !(e.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) && at.navigated) {
                            at.accept();
                            e.accepted = true;
                            return;
                        }
                        if (e.key === Qt.Key_Escape) {
                            at.dismiss();
                            e.accepted = true;
                            return;
                        }
                    }
                    // Enter creates, Shift+Enter starts a new line (APP-266);
                    // Ctrl+Shift+Enter creates and stays open for the next.
                    if (enter) {
                        e.accepted = true;
                        const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                        const shift = (e.modifiers & Qt.ShiftModifier) !== 0;
                        if (shift && !ctrl) {
                            inputField.newLine();
                            return;
                        }
                        at.dismiss();
                        root._submitFromKey(ctrl && shift);
                        return;
                    }
                    // Tab: the task document with what was typed; outside the
                    // app it leaves the field, as from a one-line one.
                    if (e.key === Qt.Key_Tab && !root.standalone && inputField.text.trim().length > 0) {
                        e.accepted = true;
                        root._refreshPreview();
                        const draft = AppController.quickTaskDraft(inputField.text, new Date(), root._rejected);
                        draft.status = root._status;
                        root.close();
                        root.openFullRequested(draft);
                        return;
                    }
                    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                        const next = inputField.nextItemInFocusChain(e.key === Qt.Key_Tab);
                        if (next) next.forceActiveFocus(e.key === Qt.Key_Tab ? Qt.TabFocusReason : Qt.BacktabFocusReason);
                        e.accepted = true;
                    }
                }
            }
        }

        // A pasted error this workspace has met before (APP-159).
        SeenBeforeHint {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            text: inputField.text
            onActivated: (hit) => root.seenBeforeActivated(hit)
        }

        Timer {
            id: previewTimer
            interval: 80
            repeat: false
            onTriggered: root._refreshPreview()
        }

        // What was read, as chips (APP-266): when / due / estimate take
        // their words back with ×; priority and labels say what they set;
        // the column is picked here.
        Flow {
            objectName: "qc-chips"
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            spacing: Theme.spSm
            PropertyChip {
                outlined: true
                objectName: "qc-when"
                removeOnHover: true
                visible: !!(root._preview && root._preview.start)
                small: false
                removable: true
                key: I18n.t("capture.when")
                value: visible ? root._chipWhen(root._preview.start, root._preview.hasTime)
                                 + (root._preview.whenPast ? " · " + I18n.t("capture.past") : "") : ""
                valueColor: visible && root._preview.whenPast ? Theme.textDim : Theme.text
                onRemoved: root.rejectSpan("when")
            }
            PropertyChip {
                outlined: true
                objectName: "qc-due"
                removeOnHover: true
                visible: !!(root._preview && root._preview.due)
                small: false
                removable: true
                key: I18n.t("capture.due")
                value: visible ? root._chipWhen(root._preview.due, root._preview.dueHasTime)
                                 + (root._preview.duePast ? " · " + I18n.t("capture.past") : "") : ""
                valueColor: visible && root._preview.duePast ? Theme.textDim : Theme.text
                onRemoved: root.rejectSpan("due")
            }
            PropertyChip {
                outlined: true
                objectName: "qc-estimate"
                removeOnHover: true
                visible: !!(root._preview && root._preview.estimate > 0)
                small: false
                removable: true
                key: I18n.t("capture.estimate")
                value: visible ? I18n.fmtMinutes(root._preview.estimate) : ""
                onRemoved: root.rejectSpan("estimate")
            }
            PropertyChip {
                outlined: true
                objectName: "qc-priority"
                visible: !!(root._parsed && root._parsed.priority)
                small: false
                key: I18n.t("capture.priority")
                value: visible ? root._parsed.priority : ""
                // Plain, as the sheet writes "приоритет P1" (R3-098).
                valueColor: Theme.text
            }
            Repeater {
                model: (root._parsed && root._parsed.labels) || []
                delegate: PropertyChip {
                    required property var modelData
                    outlined: true
                    small: false
                    key: I18n.t("capture.label")
                    value: "#" + modelData
                }
            }
            // A meeting in the calendar only on purpose (APP-266): a chip
            // that says "нет" until clicked (DG-130; the sheet has no switch).
            PropertyChip {
                id: meetingBox
                outlined: true
                objectName: "qc-meeting"
                property bool checked: false
                visible: !!(root._preview && root._preview.start && root._preview.hasTime)
                small: false
                key: I18n.t("capture.meetingKey")
                value: meetingBox.checked ? I18n.t("capture.meetingYes") : I18n.t("capture.meetingNo")
                valueColor: meetingBox.checked ? Theme.text : Theme.textMuted
                onClicked: meetingBox.checked = !meetingBox.checked
            }
            PropertyChip {
                id: columnChip
                outlined: true
                objectName: "qc-column"
                small: false
                key: I18n.t("capture.column")
                value: root._statusName(root._status)
                onClicked: columnMenu.popup(columnChip, 0, columnChip.height + Theme.spXs)
                AppMenu {
                    id: columnMenu
                    Instantiator {
                        model: AppController.statuses
                        delegate: AppMenuItem {
                            id: colRow
                            required property var modelData
                            text: colRow.modelData.name
                            marked: colRow.modelData.id === root._status
                            onTriggered: root._status = colRow.modelData.id
                        }
                        onObjectAdded: (idx, obj) => columnMenu.insertItem(idx, obj)
                        onObjectRemoved: (idx, obj) => columnMenu.removeItem(obj)
                    }
                }
            }
        }

        // A key another task holds stays in the title; offer that task.
        Text {
            objectName: "qc-ticket-taken"
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            visible: !!(root._parsed && root._parsed.ticketTaken)
            text: visible ? I18n.t("capture.ticketTaken").arg(root._parsed.ticketKey) : ""
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            font.underline: ticketCA.hovered
            ClickArea {
                id: ticketCA
                label: parent.text
                onActivated: {
                    const id = root._parsed.ticketKey;
                    root.close();
                    root.openTaskRequested(id);
                }
            }
        }

        // Several lines pasted: one question.
        RowLayout {
            objectName: "qc-lines-ask"
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            visible: root._askLines
            spacing: Theme.spMd
            Text {
                Layout.fillWidth: true
                text: I18n.t("capture.lines.ask").arg(root._lineCount())
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                wrapMode: Text.WordWrap
            }
            PillButton {
                objectName: "qc-lines-many"
                text: I18n.t("capture.lines.many").arg(root._lineCount())
                onClicked: root._submitEachLine()
            }
            PillButton {
                objectName: "qc-lines-one"
                text: I18n.t("capture.lines.one")
                onClicked: root._submitAsOne()
            }
        }

        // Why Ctrl+Enter did nothing, or what the last Ctrl+Shift+Enter added.
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
            // The keys as separate items, spaced (R3-099).
            Flow {
                objectName: "qc-keys-hint"
                Layout.fillWidth: true
                spacing: Theme.sp2xl
                Repeater {
                    model: I18n.t("capture.hints").split(" · ")
                    delegate: Text {
                        required property string modelData
                        text: modelData
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.features: Theme.tabularNums
                        font.pixelSize: Theme.fsXs
                    }
                }
            }
            Text {
                objectName: "qc-branch"
                visible: root._branch.length > 0
                text: root.linkBranch ? I18n.t("capture.branch.linked").arg(root._branch)
                                      : I18n.t("capture.branch.offer").arg(root._branch)
                textFormat: Text.PlainText
                color: branchCA.hovered || root.linkBranch ? Theme.text : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                font.underline: branchCA.hovered
                ClickArea {
                    id: branchCA
                    label: parent.text
                    checkable: true
                    checked: root.linkBranch
                    onActivated: root.linkBranch = !root.linkBranch
                }
            }
        }
    }

    MentionAutocomplete {
        id: at
        target: inputField
    }
}
