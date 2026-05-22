import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    width: 560
    anchors.centerIn: Overlay.overlay

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    property var _preview: ({ok: false})
    property var _meta: ({title: "", desc: "", handles: []})
    property string _title: ""

    // @autocomplete state — repopulated whenever the cursor sits inside an
    // "@token" being typed in inputField.
    property var _atSuggestions: []
    property int _atSelectedIdx: 0
    readonly property bool _atVisible: _atSuggestions && _atSuggestions.length > 0

    // Single source of truth lives in heap::text::extractMeta (C++) and is
    // unit-tested. QML just forwards.
    function _extractMeta(raw) {
        return AppController.extractTaskMeta(raw || "");
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

    // ── @autocomplete ──
    // Word characters that may appear inside a handle (Latin / Cyrillic /
    // digits / ".-_"). The leading "@" is matched separately.
    readonly property var _handleCharRe: /[A-Za-zА-Яа-яЁё0-9_.\-]/

    function _currentAtRange() {
        const text = inputField.text;
        const caret = inputField.cursorPosition;
        let start = caret;
        while (start > 0 && root._handleCharRe.test(text.charAt(start - 1)))
            --start;
        if (start === 0 || text.charAt(start - 1) !== "@") return null;
        // Check the char BEFORE "@" — must be start-of-string or whitespace
        // (otherwise we're inside an e-mail or some non-handle token).
        if (start >= 2) {
            const lead = text.charAt(start - 2);
            if (!/\s|[,;(]/.test(lead)) return null;
        }
        return { start: start - 1, end: caret, prefix: text.substring(start, caret) };
    }

    function _refreshAtSuggestions() {
        const r = _currentAtRange();
        if (!r) { _atSuggestions = []; return; }
        const q = (r.prefix || "").toLowerCase();
        const people = AppController.people;
        const out = [];
        for (let i = 0; i < people.rowCount(); ++i) {
            const idx  = people.index(i, 0);
            const id   = String(people.data(idx, Qt.UserRole + 1) || "");
            const name = String(people.data(idx, Qt.UserRole + 2) || "");
            if (q.length === 0
                || id.toLowerCase().indexOf(q) === 0
                || name.toLowerCase().indexOf(q) >= 0) {
                out.push({id: id, name: name});
            }
            if (out.length >= 8) break;
        }
        _atSuggestions = out;
        _atSelectedIdx = 0;
    }

    function _acceptAtSuggestion() {
        if (!_atVisible) return false;
        const r = _currentAtRange();
        if (!r) return false;
        const pick = _atSuggestions[_atSelectedIdx];
        const before = inputField.text.substring(0, r.start);
        const after  = inputField.text.substring(r.end);
        const insert = "@" + pick.id + " ";
        inputField.text = before + insert + after;
        inputField.cursorPosition = (before + insert).length;
        _atSuggestions = [];
        return true;
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

    function _submit() {
        if (_title.length === 0) return;

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
            const palette = [
                "#d97a6c", "#c87fc7", "#6cc4b8", "#7da8d9",
                "#dcc06a", "#7cc492", "#e69854", "#a4a4d6"
            ];
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
            }
            inputField.clear();
            root.close();
            return;
        }

        // QuickCapture tasks: placeholder "TODO-N" id, "To Do" column.
        // The user assigns the real ticket id later in TaskEditor.
        const draft = AppController.newQuickTaskDraft();
        draft._isNew = true;
        draft.title = _title;
        if (_meta && _meta.desc && _meta.desc.length > 0) {
            draft.desc = _meta.desc;
        }
        if (_preview && _preview.ok && _preview.start) {
            draft.deadline = _preview.start;
        }
        AppController.saveTask(draft);

        // Calendar entry rules:
        //  - "ticket"/"задача" → never schedule (pure todo item)
        //  - "focus"           → focus block (deep-work, left column on calendar)
        //  - "sync"/"созвон"   → meeting on calendar (right column with созвоны)
        //  - none of the above → no calendar entry even if a time was parsed
        const noTime = !(_preview && _preview.ok && _preview.hasTime && _preview.start);
        if (noTime) { inputField.clear(); root.close(); return; }

        // Reuse the kind we already computed for the contact-ping check.
        const kind = kindEarly;
        if (kind === "ticket") { inputField.clear(); root.close(); return; }

        const d         = _preview.start;
        const startHour = d.getHours() + d.getMinutes() / 60.0;

        if (kind === "focus") {
            AppController.scheduleTask(draft.id, startHour, d);
            AppController.selectedDate = d;
        } else if (kind === "sync") {
            // Honour parsed range "12:00-13:00", else default 30 min.
            let endHour = startHour + 0.5;
            const pe = _preview.end;
            if (pe && pe.getTime && pe.getTime() > 0) {
                const eh = pe.getHours() + pe.getMinutes() / 60.0;
                if (eh > startHour) endHour = eh;
            }
            const attendees = _resolvePeopleNames(_meta.handles).join(", ");
            const ev = AppController.newEventDraft(startHour, d);
            ev.type      = "sync";
            ev.title     = _title.substring(0, 40);
            ev.end       = endHour;
            ev.taskId    = draft.id;
            ev.date      = d;
            ev.attendees = attendees;
            AppController.saveEvent(ev);
            AppController.selectedDate = d;
        }
        // kind === "none" → task with deadline only, no calendar entry.

        inputField.clear();
        root.close();
    }

    onOpened: {
        inputField.text = "";
        _preview = {ok: false};
        _title = "";
        _atSuggestions = [];
        _atSelectedIdx = 0;
        inputField.forceActiveFocus();
    }

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 10
        Item {
            Layout.preferredHeight: 6
        }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: I18n.t("quick.title")
            color: Theme.textMuted
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }

        TextField {
            id: inputField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            placeholderText: I18n.t("quick.fieldPh")
            font.pixelSize: 14
            background: Rectangle {
                radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1
            }
            color: Theme.text
            placeholderTextColor: Theme.textDim
            onTextChanged: { previewTimer.restart(); root._refreshAtSuggestions(); }
            onCursorPositionChanged: root._refreshAtSuggestions()
            Keys.onPressed: (e) => {
                if (root._atVisible) {
                    if (e.key === Qt.Key_Down) {
                        root._atSelectedIdx = Math.min(
                            root._atSuggestions.length - 1,
                            root._atSelectedIdx + 1);
                        e.accepted = true; return;
                    }
                    if (e.key === Qt.Key_Up) {
                        root._atSelectedIdx = Math.max(0, root._atSelectedIdx - 1);
                        e.accepted = true; return;
                    }
                    if (e.key === Qt.Key_Tab
                        || (e.key === Qt.Key_Return && (e.modifiers & Qt.ShiftModifier))
                        || (e.key === Qt.Key_Enter && (e.modifiers & Qt.ShiftModifier))) {
                        // Tab or Shift+Enter → insert suggestion, stay in field.
                        if (root._acceptAtSuggestion()) { e.accepted = true; return; }
                    }
                    if (e.key === Qt.Key_Escape) {
                        root._atSuggestions = [];
                        e.accepted = true; return;
                    }
                }
            }
            Keys.onReturnPressed: {
                if (root._atVisible) { root._acceptAtSuggestion(); return; }
                root._submit();
            }
            Keys.onEnterPressed: {
                if (root._atVisible) { root._acceptAtSuggestion(); return; }
                root._submit();
            }
        }

        // Suggestion dropdown — only present while the cursor is inside an
        // "@token" with at least one matching person.
        Rectangle {
            visible: root._atVisible
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            Layout.preferredHeight: visible
                ? Math.min(root._atSuggestions.length, 6) * 26 + 2
                : 0
            radius: 6
            color: Theme.panel2
            border.color: Theme.border
            border.width: 1
            ListView {
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: root._atSuggestions
                interactive: false
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 26
                    color: index === root._atSelectedIdx
                        ? Theme.withAlpha(Theme.accent, 0.18)
                        : "transparent"
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        spacing: 8
                        Text {
                            text: "@" + modelData.id
                            color: Theme.accentStrong
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "· " + modelData.name
                            color: Theme.textMuted
                            font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root._atSelectedIdx = index;
                            root._acceptAtSuggestion();
                            inputField.forceActiveFocus();
                        }
                    }
                }
            }
        }

        Timer {
            id: previewTimer
            interval: 80
            repeat: false
            onTriggered: root._refreshPreview()
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            spacing: 8
            Text {
                visible: root._title.length > 0
                text: "" + root._title
                color: Theme.text
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Rectangle {
                visible: root._preview && root._preview.ok
                radius: 10
                color: Theme.panel2
                border.color: Theme.accent
                border.width: 1
                implicitHeight: previewChip.implicitHeight + 6
                implicitWidth: previewChip.implicitWidth + 16
                Text {
                    id: previewChip
                    anchors.centerIn: parent
                    color: Theme.text
                    font.pixelSize: 11
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

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 14
            spacing: 8
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
}
