import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    width: 480

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    property var draft: ({})
    property bool isNew: false
    // Original id at the moment of opening the editor. Used so that even if
    // the user edits idField, AppController can find and rename the existing
    // row instead of inserting a duplicate.
    property string _originalId: ""

    function showFor(initialDraft) {
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
        deadlineField.text = formatWhen(draft.dueAt, draft.hasTime);
        scheduledField.text = formatWhen(draft.scheduledAt, draft.hasTime);
        labelsField.text = labelsToText(draft.labels);
        estimateField.text = draft.estimateMinutes > 0 ? String(draft.estimateMinutes) : "";
        somedayBox.checked = !!draft.someday;
        recurBox.currentIndex = Math.max(0, recurBox._vals.indexOf(draft.recurrence || ""));
        open();
        // Kick a one-shot PR/state refresh for this task's branch across all
        // watched repos. Result lands on TaskModel via repoStateUpdated and
        // chips on the underlying TaskCard update without re-opening.
        if (draft.id && !isNew) AppController.refreshGitForTaskBranch(draft.id);
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

    anchors.centerIn: Overlay.overlay

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 12
        // padding via Item margins
        Item {
            Layout.preferredHeight: 4
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            spacing: 8
            Text {
                text: root.isNew ? I18n.t("editor.new.task") : I18n.t("editor.edit.task")
                color: Theme.text
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                visible: !root.isNew
                text: idField.text
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: 12
                font.weight: Font.Medium
            }
            Item {
                Layout.fillWidth: true
            }
        }

        FieldLabel {
            text: I18n.t("editor.label.ticketId").toUpperCase(); Layout.leftMargin: 18; Layout.rightMargin: 18
        }
        TextField {
            id: idField
            objectName: "te-id"
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            // New tasks: TODO placeholder — final id is generated on save.
            // Edit: pre-filled with the current id (still editable).
            placeholderText: root.isNew ? I18n.t("editor.ph.ticketId")
                                        : "LTE-XXXX"
            font.family: Theme.fontMono
            background: FieldBg {
            }
            color: Theme.text
            placeholderTextColor: Theme.textDim
            // Auto-uppercase so the id stays canonical (matches newTaskDraft).
            onTextChanged: {
                const up = text.toUpperCase();
                if (up !== text) text = up;
            }
        }

        FieldLabel {
            text: I18n.t("editor.label.title").toUpperCase(); Layout.leftMargin: 18; Layout.rightMargin: 18
        }
        TextField {
            id: titleField
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            placeholderText: I18n.t("editor.ph.titleShort")
            background: FieldBg {
            }
            color: Theme.text
            placeholderTextColor: Theme.textDim
        }

        FieldLabel {
            text: I18n.t("editor.label.desc").toUpperCase(); Layout.leftMargin: 18; Layout.rightMargin: 18
        }
        ScrollView {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            Layout.preferredHeight: 70
            TextArea {
                id: descField
                placeholderText: I18n.t("editor.ph.desc")
                wrapMode: TextEdit.Wrap
                background: FieldBg {
                }
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }
        }

        GridLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 4
            FieldLabel {
                text: I18n.t("editor.label.status").toUpperCase()
            }
            FieldLabel {
                text: I18n.t("editor.label.priority").toUpperCase()
            }
            ComboBox {
                id: statusBox
                objectName: "te-status"
                Layout.fillWidth: true
                model: root.statusNames()
                background: FieldBg {
                }
                contentItem: Text {
                    text: statusBox.displayText
                    color: Theme.text
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                }
            }
            ComboBox {
                id: priBox
                Layout.fillWidth: true
                model: ["P0", "P1", "P2", "P3"]
                background: FieldBg {
                }
                contentItem: Text {
                    text: priBox.displayText
                    color: Theme.text
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                }
            }
            FieldLabel {
                text: I18n.t("editor.label.deadline").toUpperCase()
            }
            FieldLabel {
                text: "BRANCH"
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                TextField {
                    id: deadlineField
                    Layout.fillWidth: true
                    placeholderText: I18n.t("editor.ph.deadline")
                    font.family: Theme.fontMono
                    background: Rectangle {
                        radius: 6
                        color: Theme.panel2
                        border.color: deadlineField.text.length === 0
                            ? Theme.border
                            : (root._deadlinePreview && root._deadlinePreview.ok
                                ? (Theme.accent || Theme.borderStrong)
                                : (Theme.danger || "#c0392b"))
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
                    radius: 6
                    color: deadlineCalMA.containsMouse ? Theme.panel3 : Theme.panel2
                    border.color: Theme.border; border.width: 1
                    Rectangle {   // mini calendar glyph
                        anchors.centerIn: parent
                        width: 15; height: 14; radius: 2
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
                Rectangle {
                    visible: root._deadlinePreview && root._deadlinePreview.ok
                    radius: 10
                    color: Theme.panel2
                    border.color: Theme.accent || Theme.borderStrong
                    border.width: 1
                    implicitHeight: chipLabel.implicitHeight + 6
                    implicitWidth: chipLabel.implicitWidth + 14
                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        font.pixelSize: 10
                        color: Theme.text
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
                                // ⏱ hint: a focus block will be created
                                return "↑ " + iso + " " + hh + ":" + mm + (root.isNew ? " ⏱" : "");
                            }
                            return "↑ " + iso;
                        }
                    }
                }
            }
            TextField {
                id: branchField
                Layout.fillWidth: true
                placeholderText: "fix/..."
                font.family: Theme.fontMono
                background: FieldBg {
                }
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }

            FieldLabel { text: "RECURRENCE" }
            FieldLabel { text: "" }
            ComboBox {
                id: recurBox
                objectName: "te-recurrence"
                Layout.fillWidth: true
                readonly property var _vals: ["", "every:day", "every:week", "every:weekday",
                                              "every:mon", "every:tue", "every:wed", "every:thu", "every:fri",
                                              "every:sat", "every:sun"]
                model: ["None", "Daily", "Weekly", "Weekdays",
                        "Every Mon", "Every Tue", "Every Wed", "Every Thu", "Every Fri",
                        "Every Sat", "Every Sun"]
                background: FieldBg {
                }
                contentItem: Text {
                    text: recurBox.displayText
                    color: Theme.text
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Item {}

            FieldLabel { text: "SCHEDULED" }
            FieldLabel { text: "ESTIMATE (MIN)" }
            TextField {
                id: scheduledField
                Layout.fillWidth: true
                placeholderText: I18n.t("editor.ph.deadline")
                font.family: Theme.fontMono
                background: FieldBg {}
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }
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

            FieldLabel { text: "LABELS" }
            FieldLabel { text: "" }
            TextField {
                id: labelsField
                Layout.fillWidth: true
                placeholderText: "backlog, infra"
                background: FieldBg {}
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }
            // Wrapper carries the hint across the whole cell so the meaning is
            // discoverable on hover, not just over the tiny box.
            Item {
                id: somedayWrap
                Layout.fillWidth: true
                implicitWidth: somedayBox.implicitWidth
                implicitHeight: somedayBox.implicitHeight

                CheckBox {
                    id: somedayBox
                    objectName: "te-someday"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Someday"
                    // Parking a task as "someday" files it under Backlog. Reflect
                    // that in the status box immediately; saveTask enforces it too.
                    onCheckedChanged: if (checked) {
                        const bi = root.statusList().indexOf("backlog");
                        if (bi >= 0) statusBox.currentIndex = bi;
                    }
                    contentItem: Text {
                        text: somedayBox.text
                        color: Theme.text
                        font.pixelSize: 12
                        leftPadding: somedayBox.indicator.width + 6
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                HoverHandler { id: somedayHover }
                ToolTip.visible: somedayHover.hovered
                ToolTip.delay: 400
                ToolTip.text: "Park as someday — files this task under Backlog until you pick it up."
            }
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.topMargin: 8; Layout.bottomMargin: 16
            spacing: 8
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
            Item {
                Layout.fillWidth: true
            }
            PillButton {
                text: I18n.t("common.cancel")
                onClicked: root.close()
            }
            PillButton {
                text: root.isNew ? I18n.t("editor.btn.create") : I18n.t("editor.btn.save")
                primary: true
                onClicked: {
                    // New tasks: if user left idField blank, fall back to the
                    // auto-generated id captured in the draft. Edit: take the
                    // (possibly renamed) text from idField.
                    let finalId = idField.text.trim();
                    if (finalId.length === 0 && root.isNew) {
                        finalId = root.draft.id || "";
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
                    const hasTime = root.parseHasTime(scheduledField.text)
                                 || root.parseHasTime(deadlineField.text);

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
                        hasTime: hasTime,
                        branch: branchField.text,
                        recurrence: recurBox._vals[recurBox.currentIndex] || "",
                        labels: root.labelsFromText(labelsField.text),
                        estimateMinutes: parseInt(estimateField.text || "0") || 0,
                        someday: somedayBox.checked
                    };
                    AppController.saveTask(d);
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
                        if (kind !== "ticket") AppController.selectedDate = dt;
                    }
                    root.close();
                }
            }
        }
    }

    component FieldLabel: Text {
        color: Theme.textMuted
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        topPadding: 2
    }
    component FieldBg: Rectangle {
        radius: 6
        color: Theme.panel2
        border.color: Theme.border
        border.width: 1
    }
}
