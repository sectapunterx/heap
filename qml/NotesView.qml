// Notes view — single per-profile markdown canvas with @mention / #ticket
// autocomplete. Mirrors the DocsView layout (header bar + scrollable body)
// and the docsState round-trip pattern.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import TodoCpp
import "Mention.js" as Mention

Item {
    id: root

    // ── View mode: "edit" | "split" | "preview" ──────────────────────
    // Persists via AppController.appSettingsJson under settings.notes.viewMode.
    property string viewMode: "edit"

    function _readViewMode() {
        const raw = AppController.appSettingsJson || "";
        if (!raw.length) return "edit";
        try {
            const s = JSON.parse(raw);
            const v = s && s.notes && s.notes.viewMode;
            if (v === "edit" || v === "split" || v === "preview") return v;
        } catch (e) {}
        return "edit";
    }
    function _writeViewMode(mode) {
        const raw = AppController.appSettingsJson || "";
        let s = {};
        if (raw.length) {
            try { s = JSON.parse(raw); } catch (e) { s = {}; }
        }
        s.notes = Object.assign({}, s.notes || {}, { viewMode: mode });
        AppController.appSettingsJson = JSON.stringify(s);
    }
    onViewModeChanged: if (_loadedOnce) _writeViewMode(viewMode)

    // Set by the command palette when a search hit lands in this note; the
    // caret goes to that line and the property is handed back for clearing.
    property int jumpToLine: -1
    signal jumpConsumed()
    onJumpToLineChanged: {
        if (jumpToLine < 0) return;
        _jumpToOffset(mdDocument.positionForLine(jumpToLine));
        jumpConsumed();
    }

    // ── State for autocomplete popup ─────────────────────────────────
    property string acTrigger: ""        // "@" or "#" or ""
    property int    acTriggerPos: -1     // index of trigger char in editor.text
    property string acFilter: ""
    property var    acMatches: []
    property int    acSelected: 0

    // ── Backlinks pane (HEAP-79) ─────────────────────────────────────
    // Recomputed live from the editor text (not the saved blob) so links show
    // up as you type. Empty (and uncomputed) while the pane is hidden.
    property bool showBacklinks: false
    property var  _backlinks: showBacklinks ? AppController.noteBacklinks(editor.text) : []

    // ── Scroll sync between the two panes ────────────────────────────
    // Which pane last moved under the reader's hand. The follower's own
    // movement re-enters here, so the leader is held for a moment to stop the
    // two from chasing each other.
    property string _syncOwner: ""
    Timer {
        id: syncRelease
        interval: 150
        onTriggered: root._syncOwner = ""
    }

    function _syncFrom(who) {
        if (root.viewMode !== "split") return;
        if (root._syncOwner !== "" && root._syncOwner !== who) return;
        root._syncOwner = who;
        syncRelease.restart();
        Qt.callLater(root._applySync, who);
    }

    function _applySync(who) {
        if (root.viewMode !== "split") return;
        if (who === "editor") {
            // Top visible line of the editor → the row that holds it.
            const line = editor.text.substring(0, editor.positionAt(0, notesScroll.contentY))
                               .split("\n").length - 1;
            const row = mdDocument.rowForLine(line);
            if (row >= 0) preview.positionViewAtIndex(row, ListView.Beginning);
        } else {
            const row = preview.indexAt(1, preview.contentY + 1);
            if (row < 0) return;
            const line = mdDocument.firstLineOfRow(row);
            if (line < 0) return;
            const rect = editor.positionToRectangle(mdDocument.positionForLine(line));
            notesScroll.contentY = Math.max(0, Math.min(rect.y,
                Math.max(0, notesScroll.contentHeight - notesScroll.height)));
        }
    }

    function _fuzzyScore(q, s) {
        if (q.length === 0) return 0;
        const ql = q.toLowerCase();
        const sl = s.toLowerCase();
        let i = 0, j = 0, score = 0, lastPos = -2;
        while (i < ql.length && j < sl.length) {
            if (ql[i] === sl[j]) {
                score += (lastPos + 1 === j ? 10 : 2);
                lastPos = j;
                i++;
            }
            j++;
        }
        if (i < ql.length) return -1;
        score -= lastPos * 0.05;
        // Clamp: a late single-char match must not go negative and be dropped by
        // the caller's `if (sc < 0) continue` as though the char were absent.
        return Math.max(0, score);
    }

    function _peopleEntries() {
        const out = [];
        const m = AppController.people;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            out.push({
                kind: "person",
                id:    m.data(idx, Qt.UserRole + 1),
                label: m.data(idx, Qt.UserRole + 2),
                sub:   m.data(idx, Qt.UserRole + 3) || "",
                color: m.data(idx, Qt.UserRole + 6)
            });
        }
        return out;
    }
    function _taskEntries() {
        const out = [];
        const m = AppController.tasks;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            out.push({
                kind: "task",
                id:    m.data(idx, Qt.UserRole + 1),
                label: m.data(idx, Qt.UserRole + 2),
                sub:   m.data(idx, Qt.UserRole + 4) || "",
                color: Theme.accent
            });
        }
        return out;
    }

    function _headingEntries() {
        const out = [];
        const hs = AppController.noteHeadings(editor.text);
        for (let i = 0; i < hs.length; i++) {
            out.push({ kind: "heading", id: "", label: hs[i], sub: "", color: Theme.accent });
        }
        return out;
    }

    function _rebuildMatches() {
        const source = acTrigger === "@"  ? _peopleEntries()
                     : acTrigger === "#"  ? _taskEntries()
                     : acTrigger === "[[" ? _headingEntries()
                     : [];
        const scored = [];
        for (let i = 0; i < source.length; i++) {
            const e = source[i];
            const hay = (acTrigger === "#") ? (e.id + " " + e.label) : e.label;
            const sc = _fuzzyScore(acFilter, hay);
            if (sc < 0) continue;
            scored.push({ entry: e, score: sc });
        }
        scored.sort(function (a, b) { return b.score - a.score; });
        acMatches = scored.slice(0, 8).map(function (x) { return x.entry; });
        acSelected = 0;
    }

    function _hideAutocomplete() {
        acTrigger = "";
        acTriggerPos = -1;
        acFilter = "";
        acMatches = [];
        acPopup.close();
    }

    function _isTriggerContextChar(ch) {
        // Allow @ / # only at word-boundaries (start of text, after whitespace
        // or after common separators).
        if (!ch) return true;
        return /[\s.,;:!?()\[\]{}]/.test(ch);
    }

    function _openAcPopup() {
        if (acMatches.length === 0) { acPopup.close(); return; }
        const cr = editor.cursorRectangle;
        const p  = editor.mapToItem(root, cr.x, cr.y + cr.height);
        acPopup.x = Math.min(p.x, root.width - acPopup.width - 8);
        acPopup.y = Math.max(0, Math.min(p.y + 4, root.height - acPopup.height - 8));
        if (!acPopup.opened) acPopup.open();
    }

    function _detectAutocomplete() {
        const pos = editor.cursorPosition;
        const txt = editor.text;
        if (pos <= 0) { _hideAutocomplete(); return; }

        // [[wiki-link]] trigger (HEAP-79) — filter may contain spaces, so scan
        // to the nearest "[[" on the current line rather than a single word.
        const lineStart = txt.lastIndexOf("\n", pos - 1) + 1;
        const before = txt.substring(lineStart, pos);
        const openIdx = before.lastIndexOf("[[");
        if (openIdx >= 0 && before.substring(openIdx + 2).indexOf("]]") < 0) {
            acTrigger    = "[[";
            acTriggerPos = lineStart + openIdx;   // index of the first '['
            acFilter     = before.substring(openIdx + 2);
            _rebuildMatches();
            _openAcPopup();
            return;
        }

        let i = pos - 1;
        while (i >= 0 && /[A-Za-z0-9_.\-]/.test(txt[i])) i--;
        if (i < 0) { _hideAutocomplete(); return; }
        const ch = txt[i];
        if (ch !== "@" && ch !== "#") { _hideAutocomplete(); return; }
        if (i > 0 && !_isTriggerContextChar(txt[i - 1])) {
            _hideAutocomplete();
            return;
        }
        acTrigger    = ch;
        acTriggerPos = i;
        acFilter     = txt.substring(i + 1, pos);
        _rebuildMatches();
        if (acMatches.length === 0) {
            acPopup.close();
            return;
        }
        const cr = editor.cursorRectangle;
        const p  = editor.mapToItem(root, cr.x, cr.y + cr.height);
        acPopup.x = Math.min(p.x, root.width - acPopup.width - 8);
        acPopup.y = Math.max(0, Math.min(p.y + 4, root.height - acPopup.height - 8));
        if (!acPopup.opened) acPopup.open();
    }

    function _slugifyName(s) { return (s || "").replace(/\s+/g, "_"); }

    function _commitAutocomplete() {
        if (acMatches.length === 0 || acSelected < 0 || acSelected >= acMatches.length) {
            _hideAutocomplete();
            return;
        }
        const e = acMatches[acSelected];
        const insert = (acTrigger === "@")  ? "@" + _slugifyName(e.label) + " "
                     : (acTrigger === "[[") ? "[[" + e.label + "]] "
                     : "#" + e.id + " ";
        const pos = editor.cursorPosition;
        // Replace the "@filter" / "#filter" span in place (remove + insert) so
        // the caret stays at the edit point instead of resetting to 0. (HEAP-65)
        Mention.commit(editor, acTriggerPos, pos, insert);
        _hideAutocomplete();
    }

    // Move the caret to `off` and scroll the editor so it is visible.
    function _jumpToOffset(off) {
        if (off < 0) return;
        if (root.viewMode === "preview") root.viewMode = "split";
        editor.forceActiveFocus();
        editor.cursorPosition = off;
        const cr = editor.positionToRectangle(off);
        const maxY = Math.max(0, notesScroll.contentHeight - notesScroll.height);
        notesScroll.contentY = Math.max(0, Math.min(cr.y - 40, maxY));
    }
    function _jumpToHeading(name) {
        _jumpToOffset(AppController.noteHeadingOffset(editor.text, name));
    }
    function _jumpToLine(lineNum) {
        const lines = editor.text.split("\n");
        let off = 0;
        for (let i = 0; i < lineNum - 1 && i < lines.length; i++) off += lines[i].length + 1;
        _jumpToOffset(off);
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: Theme.panel
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18; anchors.rightMargin: 18
                spacing: 14
                Rectangle { width: 4; height: 28; radius: 2; color: Theme.accent }
                ColumnLayout {
                    spacing: 1
                    Text {
                        text: I18n.t("notes.header")
                        color: Theme.text
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: {
                            const t = editor.text || "";
                            const lines = t.length === 0 ? 0 : t.split("\n").length;
                            const mentions = (t.match(/(^|[\s.,;:!?()\[\]{}])@[A-Za-z0-9_.\-]+/g) || []).length;
                            const tickets  = (t.match(/(^|[\s.,;:!?()\[\]{}])#[A-Z][A-Z0-9]*-\d+/g) || []).length;
                            const saved = root._savedAgo;
                            const parts = [I18n.t("notes.summary").arg(lines).arg(mentions).arg(tickets)];
                            if (saved.length > 0) parts.push(saved);
                            return parts.join(" · ");
                        }
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: editor.text.length > 0 && root.viewMode !== "preview"
                    text: I18n.t("notes.legend")
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }

                // ── Backlinks pane toggle (HEAP-79) ────────────────────
                Rectangle {
                    Layout.preferredHeight: 24
                    radius: 6
                    color: root.showBacklinks ? Theme.accent : (blToggleMA.containsMouse ? Theme.panel3 : Theme.panel2)
                    border.color: root.showBacklinks ? Theme.accent : Theme.border
                    border.width: 1
                    implicitWidth: blToggleTxt.implicitWidth + 20
                    Text {
                        id: blToggleTxt
                        anchors.centerIn: parent
                        text: I18n.t("notes.links")
                        color: root.showBacklinks ? "#06121a" : Theme.textMuted
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: blToggleMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showBacklinks = !root.showBacklinks
                    }
                }

                // ── Edit · Split · Preview toggle ──────────────────────
                // One frame around the group instead of a border per segment,
                // which doubled up into a 2px seam between them.
                Rectangle {
                    Layout.preferredWidth: 3 * 64 + 6
                    Layout.preferredHeight: 26
                    radius: 6
                    color: Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                    Row {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 0
                        Repeater {
                            model: [
                                { id: "edit",    label: I18n.t("notes.mode.edit") },
                                { id: "split",   label: I18n.t("notes.mode.split") },
                                { id: "preview", label: I18n.t("notes.mode.preview") }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool active: root.viewMode === modelData.id
                                width: 64
                                height: parent.height
                                radius: 4
                                color: active ? Theme.accent
                                     : (segMA.containsMouse ? Theme.panel3 : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: parent.active ? "#06121a" : Theme.text
                                    font.pixelSize: 11
                                    font.weight: parent.active ? Font.DemiBold : Font.Medium
                                }
                                MouseArea {
                                    id: segMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.viewMode = modelData.id
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Editor + preview body ─────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Editor pane — visible in edit + split modes.
            Flickable {
                id: notesScroll
                visible: root.viewMode === "edit" || root.viewMode === "split"
                // Scroll sync: the editor leads while the reader scrolls it.
                onContentYChanged: if (root.viewMode === "split") root._syncFrom("editor")
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: editor.implicitHeight + 48
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThinScrollBar {}

                NumberAnimation {
                    id: wheelAnim
                    target: notesScroll
                    property: "contentY"
                    duration: Theme.scaledMs(220)
                    easing.type: Easing.OutCubic
                }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const dy = event.angleDelta.y;
                        if (dy === 0) return;
                        const maxY = Math.max(0, notesScroll.contentHeight - notesScroll.height);
                        if (maxY <= 0) return;
                        const base = wheelAnim.running ? wheelAnim.to : notesScroll.contentY;
                        const newY = Math.max(0, Math.min(maxY, base - dy * 3));
                        if (newY === base) return;
                        wheelAnim.from = notesScroll.contentY;
                        wheelAnim.to = newY;
                        wheelAnim.restart();
                    }
                }

                TextArea {
                    id: editor
                    x: 24; y: 16
                    width: notesScroll.width - 48
                    // Always fill at least the visible viewport so the user can
                    // click anywhere on the canvas to start typing; grow with
                    // content otherwise.
                    height: Math.max(notesScroll.height - 32, implicitHeight + 16)
                    wrapMode: TextArea.Wrap
                    selectByMouse: true
                    placeholderText: I18n.t("notes.placeholderBody")
                    placeholderTextColor: Theme.textDim
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                    background: Item {}
                    onTextChanged: { root._scheduleSave(); root._detectAutocomplete(); }
                    onCursorPositionChanged: root._detectAutocomplete()
                    Keys.priority: Keys.BeforeItem

                    // Qt delivers shortcut events before key presses, so a
                    // global Ctrl+K would open the command palette and this
                    // field would never see the key. Claiming these while the
                    // editor has focus is what makes them editor-scoped: they
                    // still mean what they always did everywhere else.
                    Keys.onShortcutOverride: (event) => {
                        const mods = event.modifiers & ~Qt.KeypadModifier;
                        if (mods === Qt.ControlModifier) {
                            switch (event.key) {
                            case Qt.Key_B: case Qt.Key_I: case Qt.Key_E: case Qt.Key_K:
                                event.accepted = true;
                                return;
                            }
                        }
                        if (mods === (Qt.ControlModifier | Qt.ShiftModifier)) {
                            switch (event.key) {
                            case Qt.Key_X: case Qt.Key_H: case Qt.Key_L:
                                event.accepted = true;
                                return;
                            }
                        }
                    }

                    Keys.onPressed: (event) => {
                        // Autocomplete navigation (when popup is open) takes
                        // priority over markdown continuation.
                        if (acPopup.opened && acMatches.length > 0) {
                            if (event.key === Qt.Key_Down) {
                                root.acSelected = Math.min(root.acMatches.length - 1, root.acSelected + 1);
                                event.accepted = true; return;
                            }
                            if (event.key === Qt.Key_Up) {
                                root.acSelected = Math.max(0, root.acSelected - 1);
                                event.accepted = true; return;
                            }
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Tab) {
                                root._commitAutocomplete();
                                event.accepted = true; return;
                            }
                            if (event.key === Qt.Key_Escape) {
                                root._hideAutocomplete();
                                event.accepted = true; return;
                            }
                        }

                        // Slash-commands — /today, /tomorrow, /завтра, etc.
                        // Tab or Enter replaces "/<word>" with a parsed ISO
                        // date when the chrono parser recognises the word.
                        if (event.key === Qt.Key_Tab
                            || event.key === Qt.Key_Return
                            || event.key === Qt.Key_Enter)
                        {
                            const beforeCmd = editor.text.substring(0, editor.cursorPosition);
                            const slashM = beforeCmd.match(/\/([A-Za-zА-Яа-яЁё]+)$/);
                            if (slashM) {
                                const word = slashM[1];
                                const parsed = AppController.parseDateTime(word, new Date());
                                if (parsed && parsed.ok && parsed.start) {
                                    const d = parsed.start;
                                    const iso = d.getFullYear() + "-" +
                                                String(d.getMonth() + 1).padStart(2, "0") + "-" +
                                                String(d.getDate()).padStart(2, "0");
                                    const slashPos = editor.cursorPosition - (word.length + 1);
                                    editor.remove(slashPos, editor.cursorPosition);
                                    editor.insert(slashPos, iso);
                                    event.accepted = true;
                                    return;
                                }
                            }
                        }

                        // Everything below is markdown editing, which lives
                        // in C++ so it can be tested without driving the UI.
                        // See MdEditOps: each operation is one undo step.
                        const mods = event.modifiers & ~Qt.KeypadModifier;

                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (mods === Qt.ControlModifier) {
                                mdEditor.toggleTask();
                                event.accepted = true;
                                return;
                            }
                            if (mods === Qt.NoModifier && mdEditor.handleReturn()) {
                                event.accepted = true;
                                return;
                            }
                        }

                        if (event.key === Qt.Key_Tab && mods === Qt.NoModifier) {
                            mdEditor.indent();
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Backtab
                            || (event.key === Qt.Key_Tab && mods === Qt.ShiftModifier)) {
                            mdEditor.outdent();
                            event.accepted = true;
                            return;
                        }

                        // Formatting. These are editor-scoped: Ctrl+K is the
                        // command palette everywhere else in the app, and it
                        // stays that way outside this field.
                        if (mods === Qt.ControlModifier) {
                            switch (event.key) {
                            case Qt.Key_B: mdEditor.toggleBold();          event.accepted = true; return;
                            case Qt.Key_I: mdEditor.toggleItalic();        event.accepted = true; return;
                            case Qt.Key_E: mdEditor.toggleCode();          event.accepted = true; return;
                            case Qt.Key_K: mdEditor.insertLink("");        event.accepted = true; return;
                            }
                        }
                        if (mods === (Qt.ControlModifier | Qt.ShiftModifier)) {
                            switch (event.key) {
                            case Qt.Key_X: mdEditor.toggleStrikethrough(); event.accepted = true; return;
                            case Qt.Key_H: mdEditor.toggleHighlight();     event.accepted = true; return;
                            case Qt.Key_L: mdEditor.cycleHeading();        event.accepted = true; return;
                            }
                        }
                    }
                }
            }

            // Vertical divider — only in split mode.
            Rectangle {
                visible: root.viewMode === "split"
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: Theme.border
            }

            // Preview pane — visible in preview + split modes.
            //
            // Draws the parsed document row by row. It replaces a read-only
            // TextArea with textFormat: MarkdownText, which handed the whole
            // note to Qt and gave nothing back — no say in how an element
            // looked, and no way to ask which lines produced it.
            MdView {
                id: preview
                objectName: "notesPreview"
                visible: root.viewMode === "preview" || root.viewMode === "split"
                Layout.fillWidth: true
                Layout.fillHeight: true
                document: mdDocument
                editorDocument: editor.textDocument

                // The checkbox write already went through the editor's own
                // document; this only keeps the caret where it was.
                onTaskToggled: {
                    const caret = editor.cursorPosition;
                    editor.cursorPosition = caret;
                }

                // Clicking a rendered block puts the caret on the line that
                // produced it, and shows the editor if it was hidden.
                onSourceRequested: (line) => {
                    if (root.viewMode === "preview") root.viewMode = "split";
                    editor.forceActiveFocus();
                    editor.cursorPosition = mdDocument.positionForLine(line);
                }

                onInternalLinkActivated: (kind, target) => {
                    if (kind === "note") {
                        const off = AppController.noteHeadingOffset(editor.text, target);
                        if (off >= 0) root._jumpToOffset(off);
                    }
                    // Tickets, people, tags and footnote jumps are wired up
                    // with the editor work; ignoring them here is better than
                    // opening a heap:// URL in a browser.
                }

                Text {
                    anchors.centerIn: parent
                    visible: preview.count === 0
                    text: I18n.t("notes.preview.empty")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }

                // ── Scroll sync (split mode) ──────────────────────────
                // Both panes show the same document, so they should show the
                // same part of it. Whichever pane the reader is scrolling
                // leads; the other follows and its own movement is ignored
                // for a moment, or the two would push each other.
                onContentYChanged: if (root.viewMode === "split") root._syncFrom("preview")
            }

            // ── Backlinks pane (HEAP-79) ──────────────────────────────
            Rectangle {
                visible: root.showBacklinks
                Layout.preferredWidth: 240
                Layout.fillHeight: true
                color: Theme.panel
                Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left; width: 1; color: Theme.border }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    Text {
                        text: I18n.t("notes.backlinks")
                        color: Theme.text
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Text {
                        visible: root._backlinks.length === 0
                        text: I18n.t("notes.backlinks.empty")
                        color: Theme.textDim
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root._backlinks
                        spacing: 8
                        ScrollBar.vertical: ThinScrollBar {}
                        delegate: ColumnLayout {
                            required property var modelData
                            width: ListView.view.width
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    text: (modelData.resolved ? "⌗ " : "⚠ ") + modelData.target
                                    color: modelData.resolved ? Theme.mOneone : Theme.p1
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: modelData.resolved ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: if (modelData.resolved) root._jumpToHeading(modelData.target)
                                    }
                                }
                                Text {
                                    text: modelData.refs.length
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                }
                            }
                            Repeater {
                                model: modelData.refs
                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 10
                                    text: "└ " + modelData.text
                                    color: Theme.textMuted
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root._jumpToLine(modelData.line)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Ctrl+Shift+M — cycle edit → split → preview → edit.
    //
    // Was Ctrl+Shift+P, which is also profile.new in the global shortcut
    // catalog: both fired, and which one won depended on where focus was.
    Shortcut {
        sequence: "Ctrl+Shift+M"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: {
            if (root.viewMode === "edit")         root.viewMode = "split";
            else if (root.viewMode === "split")   root.viewMode = "preview";
            else                                   root.viewMode = "edit";
        }
    }

    // ── Markdown highlighter ─────────────────────────────────────
    // target is wired imperatively in Component.onCompleted so we hand the
    // highlighter a fully-initialised QQuickTextDocument (the declarative
    // binding sometimes fires before TextArea's textDocument is ready).
    MdHighlighter {
        id: highlighter
        headingScale: 1.45
        palette: ({
            text:          Theme.text,
            dim:           Theme.textMuted,
            accent:        Theme.accent,
            code:          Theme.p2,
            codeBg:        Theme.bg2,
            mention:       Theme.mStandup,
            ticket:        Theme.p2,
            tag:           Theme.mOneone,
            math:          Theme.mOneone,
            highlightBg:   Theme.accentSoft,
            keyword:       Theme.accentStrong,
            string:        Theme.stDone,
            number:        Theme.p2
        })
    }

    // ── Autocomplete popup ───────────────────────────────────────
    Popup {
        id: acPopup
        modal: false
        focus: false
        closePolicy: Popup.NoAutoClose
        padding: 0
        width: 320
        height: Math.min(8, Math.max(1, acMatches.length)) * 38 + 8

        background: Rectangle {
            radius: 8
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        contentItem: ListView {
            id: acList
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            interactive: false
            model: acMatches
            spacing: 0
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 36
                radius: 4
                color: index === root.acSelected ? Theme.panel2 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8; anchors.rightMargin: 8
                    spacing: 8

                    Rectangle {
                        visible: modelData.kind === "person"
                        width: 22; height: 22; radius: 11
                        color: modelData.color || Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: {
                                const parts = (modelData.label || "").split(/\s+/);
                                return (parts[0] ? parts[0][0] : "") + (parts[1] ? parts[1][0] : "");
                            }
                            color: "#06121a"
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        visible: modelData.kind === "task"
                        width: 50; height: 18; radius: 4
                        color: "transparent"
                        border.color: Theme.accent; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: modelData.id
                            color: Theme.accent
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        visible: modelData.kind === "heading"
                        width: 22; height: 18; radius: 4
                        color: "transparent"
                        border.color: "#b58ad7"; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "⌗"
                            color: "#b58ad7"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: modelData.label
                            color: Theme.text
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: (modelData.sub || "").length > 0
                            text: modelData.sub || ""
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.acSelected = index
                    onClicked: { root.acSelected = index; root._commitAutocomplete(); }
                }
            }
        }
    }

    // ── Persistence (mirror DocsView's _persisting / _reloading) ────
    property bool _loadedOnce: false
    property bool _persisting: false
    property bool _reloading:  false
    property string _savedAgo: ""

    Timer {
        id: persistTimer
        interval: 250
        repeat: false
        onTriggered: root._persistNow()
    }
    Timer {
        id: savedAgoTimer
        interval: 5000
        repeat: false
        onTriggered: root._savedAgo = ""
    }

    function _scheduleSave() {
        if (!_loadedOnce || _reloading) return;
        persistTimer.restart();
    }
    function _persistNow() {
        if (!_loadedOnce || _reloading) return;
        _persisting = true;
        AppController.notesState = editor.text;
        _persisting = false;
        _savedAgo = "saved";
        savedAgoTimer.restart();
    }
    function _loadFromController() {
        _reloading = true;
        editor.text = AppController.notesState || "";
        _reloading = false;
    }
    // Markdown editing, in C++ so the rules can be tested directly rather
    // than only by driving the UI.
    MarkdownEditorController {
        id: mdEditor
        target: editor.textDocument
        cursorPosition: editor.cursorPosition
        selectionStart: editor.selectionStart
        selectionEnd: editor.selectionEnd
        // Only the editor can move its own cursor, so the controller asks.
        onSelectionRequested: (start, end) => {
            if (start === end) editor.cursorPosition = start;
            else editor.select(start, end);
        }
    }

    // Parses once per change and serves every question about the document:
    // the rendered rows, the outline, and which row a line belongs to.
    MdDocument {
        id: mdDocument
        text: editor.text
        allowRemoteImages: false
        palette: ({
            "text": Theme.text,
            "dim": Theme.textDim,
            "link": Theme.accent,
            "code": Theme.text,
            "codeBackground": Theme.panel2,
            "highlightBackground": Theme.accentSoft,
            "mention": Theme.stProg,
            "ticket": Theme.accent,
            "tag": Theme.stReview,
            "math": Theme.p2
        })
    }

    Component.onCompleted: {
        highlighter.target = editor.textDocument;
        viewMode = _readViewMode();
        _loadFromController();
        _loadedOnce = true;
    }
    Connections {
        target: AppController
        function onNotesStateChanged() {
            if (!root._loadedOnce || root._persisting) return;
            root._loadFromController();
            root._hideAutocomplete();
        }
    }
}
