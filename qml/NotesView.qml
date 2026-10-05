// Notes view — single per-profile markdown canvas with @mention / #ticket
// autocomplete. Mirrors the DocsView layout (header bar + scrollable body)
// and the docsState round-trip pattern.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Dialogs
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
    onJumpToLineChanged: _consumeJump()
    function _consumeJump() {
        if (jumpToLine < 0) return;
        _jumpToOffset(mdDocument.positionForLine(jumpToLine));
        // Later, not from inside the change handler: the caller clears the
        // line it bound this to, which re-entered the binding while it was
        // still being evaluated and logged a binding loop.
        Qt.callLater(root.jumpConsumed);
    }

    // ── State for autocomplete popup ─────────────────────────────────
    property string acTrigger: ""        // "@" or "#" or ""
    property int    acTriggerPos: -1     // index of trigger char in editor.text
    property string acFilter: ""
    property var    acMatches: []
    property int    acSelected: 0

    // ── Links pane (HEAP-79) ─────────────────────────────────────────
    // Two lists: the notes that link here (what "backlinks" means — it used to
    // show this note's own links under that name, and flag a link to an
    // existing note as broken because no heading here carried its name), and
    // this note's own links, each resolved against every note.
    //
    // Both are computed after typing pauses, not on every keystroke: over a
    // 3 MB note the live binding cost seconds per character. Empty (and
    // uncomputed) while the pane is hidden.
    property bool showBacklinks: false
    property var  _incoming: []
    property var  _outgoing: []
    function _refreshLinks() {
        if (!root.showBacklinks) { root._incoming = []; root._outgoing = []; return; }
        root._incoming = AppController.backlinksToNote(AppController.activeNoteId);
        root._outgoing = AppController.outgoingNoteLinks(editor.text);
    }
    onShowBacklinksChanged: _refreshLinks()
    Timer { id: linksTimer; interval: 400; onTriggered: root._refreshLinks() }

    // The header's counts, on the same pause.
    property var _stats: ({ lines: 0, mentions: 0, tickets: 0 })
    Timer {
        id: statsTimer
        interval: 300
        onTriggered: {
            root._stats = AppController.noteStats(editor.text);
            root._refreshAttachments();
        }
    }

    // ── Attachments ──────────────────────────────────────────────────
    // A note's files are the ones its text links ("attachments/<id>"), so the
    // chips are read from the text and removing one takes the link out.
    property var _noteAttachments: []
    function _refreshAttachments() {
        root._noteAttachments = editor.text.indexOf("attachments/") >= 0
            ? AppController.markdownAttachments(editor.text) : [];
    }
    // Puts markdown links to stored files at the caret, each in a paragraph of
    // its own so an image renders as an image. One edit: one Ctrl+Z.
    function insertAttachmentRefs(added) {
        if (!added || added.length === 0) return 0;
        const refs = added.map(a => a.ref).join("\n\n");
        editor.remove(editor.selectionStart, editor.selectionEnd);
        const pos = editor.cursorPosition;
        const text = editor.text;
        let before = "";
        if (pos > 0 && text.charAt(pos - 1) !== "\n") before = "\n\n";
        else if (pos > 1 && text.charAt(pos - 2) !== "\n") before = "\n";
        const after = (pos < text.length && text.charAt(pos) !== "\n") ? "\n\n" : "\n";
        editor.insert(pos, before + refs + after);
        editor.cursorPosition = pos + before.length + refs.length + after.length;
        root._refreshAttachments();
        return added.length;
    }
    function attachUrls(urls) {
        if (!urls || urls.length === 0) return 0;
        const list = [];
        for (let i = 0; i < urls.length; ++i) list.push(urls[i]);
        return root.insertAttachmentRefs(AppController.importAttachments(list, true));
    }
    // Ctrl+V with a file or a bare image on the clipboard.
    function pasteAttachment() {
        if (!AppController.clipboardHasAttachment()) return false;
        root.insertAttachmentRefs(AppController.importClipboardAttachments());
        return true;
    }
    // Takes every link to the file out of the note. The file stays in the
    // attachments folder (Settings → Data cleans up what nothing uses).
    function removeAttachmentRefs(attachmentId) {
        const needle = "attachments/" + attachmentId;
        const text = editor.text;
        const spans = [];
        let at = text.indexOf(needle);
        while (at >= 0) {
            const lineStart = text.lastIndexOf("\n", at - 1) + 1;
            const open = text.lastIndexOf("](", at);
            let first = open >= lineStart ? text.lastIndexOf("[", open) : -1;
            const close = text.indexOf(")", at);
            if (first < lineStart || close < 0) { at = text.indexOf(needle, at + needle.length); continue; }
            if (first > lineStart && text.charAt(first - 1) === "!") first--;
            let last = close + 1;
            if (text.charAt(last) === "\n") last++;
            spans.push([first, last]);
            at = text.indexOf(needle, last);
        }
        for (let i = spans.length - 1; i >= 0; --i) editor.remove(spans[i][0], spans[i][1]);
        root._refreshAttachments();
        return spans.length;
    }
    FileDialog {
        id: attachDialog
        fileMode: FileDialog.OpenFiles
        title: I18n.t("att.dialog.title")
        onAccepted: root.attachUrls(selectedFiles)
    }
    Shortcut {
        sequence: "Ctrl+Shift+A"
        enabled: editor.activeFocus
        onActivated: attachDialog.open()
    }
    // Files dropped anywhere on Notes are linked into the open note.
    DropArea {
        id: noteFileDrop
        objectName: "notes-file-drop"
        anchors.fill: parent
        z: 50
        keys: ["text/uri-list"]
        onEntered: (drag) => { drag.accepted = drag.hasUrls; }
        onDropped: (drop) => {
            if (drop.hasUrls && root.attachUrls(drop.urls) > 0) drop.accept(Qt.CopyAction);
        }
    }
    Rectangle {
        visible: noteFileDrop.containsDrag
        anchors.fill: parent
        z: 49
        color: "transparent"
        border.color: Theme.accent
        border.width: 2
    }

    // What the header calls the open note. m.data() is a call, not something
    // a binding can watch, so it is refreshed when the note or the list moves.
    property string _activeTitle: ""
    function _refreshTitle() {
        const m = AppController.notes;
        const row = m.indexOfId(AppController.activeNoteId);
        root._activeTitle = row >= 0 ? String(m.data(m.index(row, 0), m.roleOf("title")) || "") : "";
    }
    Connections {
        target: AppController.notes
        function onDataChanged() { root._refreshTitle() }
        function onModelReset() { root._refreshTitle() }
        function onRowsRemoved() { root._refreshTitle() }
    }

    // The list of notes beside the editor. "auto" shows it when there is room
    // for both; the toggle (and Ctrl+Alt+L) pins it open or shut. At 1440 px
    // with the right panel open it used to be hidden with no way back, which
    // left no way to reach another note at all.
    property string _listPref: "auto"
    readonly property bool _listShown: _listPref === "auto" ? root.width > 560 : _listPref === "shown"
    function toggleList() { root._listPref = root._listShown ? "hidden" : "shown"; }

    // Same lookup Main uses, so a rebinding in Settings → Hotkeys applies here.
    function _kbd(id) {
        const list = AppController.shortcuts;
        for (let i = 0; i < list.length; i++)
            if (list[i].id === id) return list[i].sequence;
        return "";
    }

    // The notes.* catalog actions, for the command palette: the same thing the
    // keys bound below do (SHELL-1). `cmd` is the id without "notes.".
    function runNotesCommand(cmd) {
        switch (cmd) {
        case "new":        root.newNoteAndEdit(); break;
        case "next":       notesList.step(1); break;
        case "prev":       notesList.step(-1); break;
        case "rename":     if (AppController.activeNoteId.length > 0) notesList.renameActive(); break;
        case "toggleList": root.toggleList(); break;
        default:           console.warn("notes: no command", cmd);
        }
    }

    // The keys that take focus out of the editor (SHELL-18). True when the
    // key was one of them and focus has moved.
    function _leaveEditorKey(field: Item, key: int, modifiers: int): bool {
        const mods = modifiers & ~Qt.KeypadModifier;
        if (key === Qt.Key_Escape && mods === Qt.NoModifier) {
            if (root._listShown) {
                notesList.focusList();
            } else {
                const prev = field.nextItemInFocusChain(false);
                if (prev) prev.forceActiveFocus(Qt.BacktabFocusReason);
            }
            return true;
        }
        const ctrlTab = (key === Qt.Key_Tab || key === Qt.Key_Backtab) && (mods & Qt.ControlModifier) !== 0;
        const f6 = key === Qt.Key_F6 && (mods & ~Qt.ShiftModifier) === Qt.NoModifier;
        if (!ctrlTab && !f6) return false;
        const back = key === Qt.Key_Backtab || (mods & Qt.ShiftModifier) !== 0;
        const next = field.nextItemInFocusChain(!back);
        if (next) next.forceActiveFocus(back ? Qt.BacktabFocusReason : Qt.TabFocusReason);
        return true;
    }

    function newNoteAndEdit() {
        root._flushPending();
        AppController.newNote();
        root._focusEditorAtEnd();
    }
    function _focusEditorAtEnd() {
        Qt.callLater(function () {
            if (root.viewMode === "preview") root.viewMode = "split";
            editor.forceActiveFocus();
            editor.cursorPosition = editor.length;
        });
    }
    // Ctrl+F in Notes filters the notes, not the task search in the top bar.
    function focusSearch() {
        if (!root._listShown) root._listPref = "shown";
        notesList.focusFilter();
    }

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

    // [[ offers the notes first — linking another note is what [[ is for now
    // that a profile has many — then this note's own headings. It offered
    // only the headings.
    function _headingEntries() {
        const out = [];
        const m = AppController.notes;
        const rTitle = m.roleOf("title"), rFolder = m.roleOf("folder"), rId = m.roleOf("id");
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            if (String(m.data(idx, rId)) === AppController.activeNoteId) continue;
            out.push({ kind: "note", id: "", label: String(m.data(idx, rTitle) || ""),
                       sub: String(m.data(idx, rFolder) || ""), color: Theme.accent });
        }
        // From the document's own outline, already parsed: asking for the
        // headings of editor.text parsed the whole note on every keystroke
        // typed inside [[ ]], 150 ms a key at 3 MB.
        // Fresh for an ordinary note; a huge one keeps its last parse.
        if (mdDocument.lastParseMs < 30) mdDocument.flush();
        const hs = mdDocument.outline;
        const seen = ({});
        for (let i = 0; i < hs.length; i++) {
            const h = hs[i].text;
            if (!h || seen[h]) continue;
            seen[h] = true;
            out.push({ kind: "heading", id: "", label: h, sub: "", color: Theme.accent });
        }
        return out;
    }

    // A character that can be part of an @name or #tag: letters of any
    // script, digits, and _ . - — the ASCII-only test made Cyrillic names
    // impossible to mention from the editor.
    function _isNameChar(ch) {
        if (!ch) return false;
        if (/[0-9_.\-]/.test(ch)) return true;
        return ch.toLowerCase() !== ch.toUpperCase();
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
        if (pos <= 0) { _hideAutocomplete(); return; }
        // Only the text just before the caret. Reading `editor.text` here
        // copied the whole note on every keystroke and every caret move.
        const base = Math.max(0, pos - 512);
        const txt = editor.getText(base, pos);
        const end = txt.length;

        // [[wiki-link]] trigger (HEAP-79) — filter may contain spaces, so scan
        // to the nearest "[[" on the current line rather than a single word.
        const lineStart = txt.lastIndexOf("\n", end - 1) + 1;
        const before = txt.substring(lineStart, end);
        const openIdx = before.lastIndexOf("[[");
        if (openIdx >= 0 && before.substring(openIdx + 2).indexOf("]]") < 0) {
            acTrigger    = "[[";
            acTriggerPos = base + lineStart + openIdx;   // index of the first '['
            acFilter     = before.substring(openIdx + 2);
            _rebuildMatches();
            _openAcPopup();
            return;
        }

        let i = end - 1;
        while (i >= 0 && end - i < 64 && root._isNameChar(txt[i])) i--;
        if (i < 0) { _hideAutocomplete(); return; }
        const ch = txt[i];
        if (ch !== "@" && ch !== "#") { _hideAutocomplete(); return; }
        if (i > 0 && !_isTriggerContextChar(txt[i - 1])) {
            _hideAutocomplete();
            return;
        }
        acTrigger    = ch;
        acTriggerPos = base + i;
        acFilter     = txt.substring(i + 1, end);
        _rebuildMatches();
        if (acMatches.length === 0) {
            acPopup.close();
            return;
        }
        _openAcPopup();
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

    // "/today", "/fri" typed as a word of its own becomes an ISO date. Only
    // as a word of its own: "http://x.com/now" and "src/mon/main.c" are a URL
    // and a path, and rewriting them on Enter mangled both.
    function _expandSlashDate() {
        const pos = editor.cursorPosition;
        const txt = editor.text;
        const lineStart = txt.lastIndexOf("\n", pos - 1) + 1;
        const m = txt.substring(lineStart, pos).match(/(^|[\s(\[{])\/([A-Za-zА-Яа-яЁё]+)$/);
        if (!m) return false;
        const word = m[2];
        const parsed = AppController.parseDateTime(word, new Date());
        if (!parsed || !parsed.ok || !parsed.start) return false;
        const d = parsed.start;
        const iso = d.getFullYear() + "-" +
                    String(d.getMonth() + 1).padStart(2, "0") + "-" +
                    String(d.getDate()).padStart(2, "0");
        const slashPos = pos - (word.length + 1);
        editor.remove(slashPos, pos);
        editor.insert(slashPos, iso);
        return true;
    }

    // Ctrl+Z / Ctrl+Shift+Z when the text field has nothing of its own left to
    // undo: hand the key to the app's undo, which holds note deletes and
    // imports. Returns true when it did.
    function _globalUndoFallback(field, event) {
        if (event.matches(StandardKey.Undo) && !field.canUndo && AppController.hasPendingUndo) {
            AppController.undo();
            event.accepted = true;
            return true;
        }
        if (event.matches(StandardKey.Redo) && !field.canRedo && AppController.canRedo) {
            AppController.redo();
            event.accepted = true;
            return true;
        }
        return false;
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
                anchors.leftMargin: Theme.inset; anchors.rightMargin: Theme.inset
                spacing: Theme.sp2xl
                Rectangle { width: 4; height: 28; radius: 2; color: Theme.accent }
                ColumnLayout {
                    spacing: 1
                    // Which note this is: the header used to say
                    // "Notes · scratchpad" whatever was open.
                    Text {
                        objectName: "notes-title"
                        text: root._activeTitle.length > 0 ? root._activeTitle : I18n.t("notes.header")
                        color: Theme.text
                        font.pixelSize: Theme.fsLg
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.maximumWidth: root.width * 0.4
                    }
                    Text {
                        text: {
                            const s = root._stats;
                            const saved = root._savedAgo;
                            const parts = [I18n.t("notes.summary").arg(s.lines).arg(s.mentions).arg(s.tickets)];
                            if (saved.length > 0) parts.push(saved);
                            return parts.join(" · ");
                        }
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsSm
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: editor.length > 0 && root.viewMode !== "preview" && root.width > 900
                    text: I18n.t("notes.legend")
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsSm
                }

                // ── Attach files (Ctrl+Shift+A in the editor) ──────────
                Rectangle {
                    id: attachBtn
                    objectName: "notes-attach"
                    Layout.preferredHeight: 24
                    radius: Theme.radiusMd
                    color: attachMA.containsMouse ? Theme.panel3 : Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                    implicitWidth: attachTxt.implicitWidth + 20
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.t("att.button")
                    Keys.onReturnPressed: attachDialog.open()
                    Keys.onEnterPressed: attachDialog.open()
                    Keys.onSpacePressed: attachDialog.open()
                    FocusRing {}
                    Text {
                        id: attachTxt
                        anchors.centerIn: parent
                        text: "📎"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                    }
                    MouseArea {
                        id: attachMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: attachDialog.open()
                    }
                    ToolTip.visible: attachMA.containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: I18n.t("att.button.tip.note")
                }

                // ── List toggle ────────────────────────────────────────
                Rectangle {
                    objectName: "notes-list-toggle"
                    Layout.preferredHeight: 24
                    radius: Theme.radiusMd
                    color: root._listShown ? Theme.accentSoft : (listToggleMA.hovered ? Theme.panel3 : Theme.panel2)
                    border.color: root._listShown ? Theme.accent : Theme.border
                    border.width: 1
                    implicitWidth: listToggleTxt.implicitWidth + 20
                    Text {
                        id: listToggleTxt
                        anchors.centerIn: parent
                        text: "☰"
                        color: root._listShown ? Theme.accentStrong : Theme.textMuted
                        font.pixelSize: Theme.fsSm
                    }
                    ClickArea {
                        id: listToggleMA
                        label: I18n.t("notes.toggleList")
                        role: Accessible.CheckBox
                        checkable: true
                        checked: root._listShown
                        onActivated: root.toggleList()
                    }
                }

                // ── Backlinks pane toggle (HEAP-79) ────────────────────
                Rectangle {
                    Layout.preferredHeight: 24
                    radius: Theme.radiusMd
                    color: root.showBacklinks ? Theme.accent : (blToggleMA.hovered ? Theme.panel3 : Theme.panel2)
                    border.color: root.showBacklinks ? Theme.accent : Theme.border
                    border.width: 1
                    implicitWidth: blToggleTxt.implicitWidth + 20
                    Text {
                        id: blToggleTxt
                        anchors.centerIn: parent
                        text: I18n.t("notes.links")
                        color: root.showBacklinks ? Theme.textOnAccent : Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        font.weight: Font.Medium
                    }
                    ClickArea {
                        id: blToggleMA
                        label: I18n.t("notes.links")
                        showTip: false
                        role: Accessible.CheckBox
                        checkable: true
                        checked: root.showBacklinks
                        onActivated: root.showBacklinks = !root.showBacklinks
                    }
                }

                // ── Edit · Split · Preview toggle ──────────────────────
                // One frame around the group instead of a border per segment,
                // which doubled up into a 2px seam between them.
                Rectangle {
                    Layout.preferredWidth: 3 * 64 + 6
                    Layout.preferredHeight: 26
                    radius: Theme.radiusMd
                    color: Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.sp2xs
                        spacing: 0
                        Repeater {
                            model: [
                                { id: "edit",    label: I18n.t("notes.mode.edit") },
                                { id: "split",   label: I18n.t("notes.mode.split") },
                                { id: "preview", label: I18n.t("notes.mode.preview") }
                            ]
                            delegate: Rectangle {
                                id: segBtn
                                required property var modelData
                                readonly property bool active: root.viewMode === modelData.id
                                width: 64
                                height: parent.height
                                radius: Theme.radiusSm
                                color: active ? Theme.accentSoft
                                     : (segMA.hovered ? Theme.panel3 : "transparent")
                                Text {
                                    id: segTxt
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: parent.active ? Theme.accentStrong : Theme.text
                                    font.pixelSize: Theme.fsSm
                                    font.weight: parent.active ? Font.DemiBold : Font.Medium
                                }
                                ClickArea {
                                    id: segMA
                                    label: segTxt.text
                                    showTip: false
                                    role: Accessible.RadioButton
                                    checkable: true
                                    checked: segBtn.active
                                    onActivated: root.viewMode = segBtn.modelData.id
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── The note's files ──────────────────────────────────────
        Rectangle {
            objectName: "notes-attachments"
            visible: root._noteAttachments.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: noteChips.implicitHeight + 2 * Theme.spSm
            color: Theme.panel
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }
            AttachmentChips {
                id: noteChips
                objectName: "notes-attachment-chips"
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.inset; anchors.rightMargin: Theme.inset
                model: root._noteAttachments
                onRemoveRequested: (attachmentId) => root.removeAttachmentRefs(attachmentId)
            }
        }

        // ── Editor + preview body ─────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Which notes there are, and which one is open. Folds away on a
            // narrow window, where the editor needs the width more.
            NotesListPane {
                id: notesList
                objectName: "notes-list-pane"
                visible: root._listShown
                Layout.preferredWidth: visible ? Math.min(240, root.width * 0.35) : 0
                Layout.fillHeight: true
                onNoteActivated: (id) => {
                    // Flush first: the editor debounces its saves, so the last
                    // keystrokes are still only in the text field here and
                    // switching would drop them.
                    root._flushPending();
                    AppController.activeNoteId = id;
                }
                // "+" makes a note to write in: the cursor goes there.
                onNoteCreated: (id) => root._focusEditorAtEnd()
            }

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
                    objectName: "notesEditor"
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
                    font.pixelSize: Theme.fsMd
                    background: Item {}
                    onTextChanged: {
                        root._scheduleSave();
                        root._detectAutocomplete();
                        statsTimer.restart();
                        if (root.showBacklinks) linksTimer.restart();
                    }
                    onCursorPositionChanged: root._detectAutocomplete()
                    Keys.priority: Keys.BeforeItem

                    // Qt delivers shortcut events before key presses, so a
                    // global Ctrl+K would open the command palette and this
                    // field would never see the key. Claiming these while the
                    // editor has focus is what makes them editor-scoped: they
                    // still mean what they always did everywhere else.
                    Keys.onShortcutOverride: (event) => {
                        if (mdEditor.claimsShortcut(event.key, event.modifiers)) event.accepted = true;
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

                        // Tab indents here, so it cannot also be the way out
                        // (SHELL-18). Esc steps out to the list of notes;
                        // Ctrl+Tab / Ctrl+Shift+Tab and F6 / Shift+F6 move on
                        // along the focus chain, as in any editor that keeps
                        // Tab for itself.
                        if (root._leaveEditorKey(editor, event.key, event.modifiers)) {
                            event.accepted = true;
                            return;
                        }

                        // A file or a bare image on the clipboard is attached
                        // and linked; anything else pastes as text.
                        if (event.matches(StandardKey.Paste) && root.pasteAttachment()) {
                            event.accepted = true;
                            return;
                        }

                        // Ctrl+Z with nothing left to undo in the text means the
                        // last thing done to the notes themselves — a delete, an
                        // import. The field is always focused here, so without
                        // this the app-wide undo was unreachable from Notes.
                        if (root._globalUndoFallback(editor, event)) return;

                        // Slash-commands — /today, /tomorrow, /завтра, etc.
                        // Tab or Enter replaces "/<word>" with a parsed ISO
                        // date when the chrono parser recognises the word.
                        if (event.key === Qt.Key_Tab
                            || event.key === Qt.Key_Return
                            || event.key === Qt.Key_Enter)
                        {
                            if (root._expandSlashDate() && event.key === Qt.Key_Tab) {
                                event.accepted = true;
                                return;
                            }
                            // Enter still ends the line after expanding: the
                            // reader pressed it to get a new one.
                        }

                        // Everything below is markdown editing, which lives
                        // in C++ so it can be tested without driving the UI,
                        // and is shared with the doc page editor. See
                        // MdEditOps: each operation is one undo step.
                        mdEditor.setSelection(editor.selectionStart, editor.selectionEnd);
                        if (mdEditor.handleKey(event.key, event.modifiers)) event.accepted = true;
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

                onInternalLinkActivated: (kind, target) => root._followLink(kind, target)

                Text {
                    anchors.centerIn: parent
                    visible: preview.count === 0
                    text: I18n.t("notes.preview.empty")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
                }

                // ── Scroll sync (split mode) ──────────────────────────
                // Both panes show the same document, so they should show the
                // same part of it. Whichever pane the reader is scrolling
                // leads; the other follows and its own movement is ignored
                // for a moment, or the two would push each other.
                onContentYChanged: if (root.viewMode === "split") root._syncFrom("preview")
            }

            // ── Links pane (HEAP-79) ──────────────────────────────────
            Rectangle {
                objectName: "notes-links-pane"
                visible: root.showBacklinks
                Layout.preferredWidth: 240
                Layout.fillHeight: true
                color: Theme.panel
                Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left; width: 1; color: Theme.border }
                Flickable {
                    anchors.fill: parent
                    anchors.margins: Theme.spXl
                    clip: true
                    contentHeight: linksCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ThinScrollBar {}
                    ColumnLayout {
                        id: linksCol
                        width: parent.width
                        spacing: Theme.spMd

                        // What else refers to this note.
                        Text {
                            text: I18n.t("notes.backlinks")
                            color: Theme.text
                            font.pixelSize: Theme.fsMd
                            font.weight: Font.DemiBold
                        }
                        Text {
                            visible: root._incoming.length === 0
                            text: I18n.t("notes.backlinks.empty")
                            color: Theme.textDim
                            font.pixelSize: Theme.fsSm
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Repeater {
                            model: root._incoming
                            delegate: ColumnLayout {
                                required property var modelData
                                objectName: "incoming-" + modelData.noteId
                                Layout.fillWidth: true
                                spacing: Theme.sp2xs
                                Text {
                                    id: incomingTxt
                                    Layout.fillWidth: true
                                    text: "← " + modelData.title
                                    color: Theme.mdTicket
                                    font.pixelSize: Theme.fsSm
                                    font.weight: Font.DemiBold
                                    font.underline: incomingMA.hovered
                                    elide: Text.ElideRight
                                    ClickArea {
                                        id: incomingMA
                                        label: incomingTxt.text
                                        showTip: false
                                        role: Accessible.Link
                                        onActivated: {
                                            root._flushPending();
                                            AppController.activeNoteId = modelData.noteId;
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Theme.spLg
                                    text: "└ " + modelData.text
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fsXs
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Item { Layout.preferredHeight: Theme.spMd }

                        // Where this note points.
                        Text {
                            text: I18n.t("notes.outgoing")
                            color: Theme.text
                            font.pixelSize: Theme.fsMd
                            font.weight: Font.DemiBold
                        }
                        Text {
                            visible: root._outgoing.length === 0
                            text: I18n.t("notes.outgoing.empty")
                            color: Theme.textDim
                            font.pixelSize: Theme.fsSm
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Repeater {
                            model: root._outgoing
                            delegate: ColumnLayout {
                                required property var modelData
                                objectName: "outgoing-" + modelData.target
                                Layout.fillWidth: true
                                spacing: Theme.sp2xs
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spSm
                                    Text {
                                        id: outgoingTxt
                                        text: (modelData.resolved ? "→ " : "△ ") + modelData.target
                                        color: modelData.resolved ? Theme.mdTicket : Theme.warning
                                        font.pixelSize: Theme.fsSm
                                        font.weight: Font.DemiBold
                                        font.underline: outgoingMA.hovered
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        ClickArea {
                                            id: outgoingMA
                                            label: outgoingTxt.text
                                            showTip: false
                                            role: Accessible.Link
                                            // Where a click in the preview would go: the
                                            // note, the heading, or the offer to write it.
                                            onActivated: root._followLink("note", modelData.target)
                                        }
                                    }
                                    Text {
                                        text: modelData.count !== undefined ? modelData.count : modelData.refs.length
                                        color: Theme.textDim
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fsXs
                                    }
                                }
                                Text {
                                    visible: !modelData.resolved
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Theme.spLg
                                    text: I18n.t("notes.outgoing.missing")
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fsXs
                                    elide: Text.ElideRight
                                }
                                Repeater {
                                    model: modelData.refs
                                    delegate: Text {
                                        id: refTxt
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.leftMargin: Theme.spLg
                                        text: "└ " + modelData.text
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fsXs
                                        font.underline: refMA.hovered
                                        elide: Text.ElideRight
                                        ClickArea {
                                            id: refMA
                                            label: refTxt.text
                                            showTip: false
                                            role: Accessible.Link
                                            onActivated: root._jumpToLine(refTxt.modelData.line)
                                        }
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

    // Notes navigation from the keyboard. step() existed and nothing was bound
    // to it; a new note needed the mouse. Rebindable in Settings → Hotkeys.
    Shortcut {
        sequence: root._kbd("notes.new")
        context: Qt.WindowShortcut
        enabled: root.visible && sequence.length > 0
        onActivated: root.newNoteAndEdit()
    }
    Shortcut {
        sequence: root._kbd("notes.next")
        context: Qt.WindowShortcut
        enabled: root.visible && sequence.length > 0
        onActivated: notesList.step(1)
    }
    Shortcut {
        sequence: root._kbd("notes.prev")
        context: Qt.WindowShortcut
        enabled: root.visible && sequence.length > 0
        onActivated: notesList.step(-1)
    }
    Shortcut {
        sequence: root._kbd("notes.rename")
        context: Qt.WindowShortcut
        enabled: root.visible && sequence.length > 0 && AppController.activeNoteId.length > 0
        onActivated: notesList.renameActive()
    }
    Shortcut {
        sequence: root._kbd("notes.toggleList")
        context: Qt.WindowShortcut
        enabled: root.visible && sequence.length > 0
        onActivated: root.toggleList()
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
            code:          Theme.code,
            codeBg:        Theme.codeBg,
            mention:       Theme.mention,
            ticket:        Theme.ticket,
            tag:           Theme.tag,
            math:          Theme.math,
            highlightBg:   Theme.highlightBg,
            keyword:       Theme.synKeyword,
            string:        Theme.synString,
            number:        Theme.synNumber
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
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        contentItem: ListView {
            id: acList
            anchors.fill: parent
            anchors.margins: Theme.spXs
            clip: true
            interactive: false
            model: acMatches
            spacing: 0
            delegate: Rectangle {
                id: acRow
                required property var modelData
                required property int index
                readonly property bool selected: index === root.acSelected
                width: ListView.view.width
                height: 36
                radius: Theme.radiusSm
                // rowHighlight and a focusRing bar, like a menu row: panel2 on
                // the popup's panel was 1.05:1 (design audit DES-21).
                color: acRow.selected ? Theme.rowHighlight : "transparent"
                Rectangle {
                    visible: acRow.selected
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: parent.height - 2 * Theme.spXs
                    radius: Theme.radiusXs
                    color: Theme.focusRing
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                    spacing: Theme.spMd

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
                            color: Theme.textOnAccent
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsXs
                            font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        visible: modelData.kind === "task"
                        width: 50; height: 18; radius: Theme.radiusSm
                        color: "transparent"
                        border.color: Theme.accent; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: modelData.id
                            color: Theme.accentStrong
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsXs
                            font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        visible: modelData.kind === "heading"
                        width: 22; height: 18; radius: Theme.radiusSm
                        color: "transparent"
                        border.color: Theme.heading; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "⌗"
                            color: Theme.heading
                            font.pixelSize: Theme.fsSm
                            font.weight: Font.DemiBold
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: modelData.label
                            color: Theme.text
                            font.pixelSize: Theme.fsMd
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: (modelData.sub || "").length > 0
                            text: modelData.sub || ""
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsXs
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
        _savedAgo = I18n.t("notes.saved");
        savedAgoTimer.restart();
    }
    // Following a [[link]] or a #TICKET from the preview.
    //
    // A [[target]] used to mean a heading in this document, because a profile
    // had one document. It now means a note first and a heading second, and
    // when it means neither it is an offer to write the note somebody clearly
    // expected to exist.
    signal taskRequested(string taskId)
    signal personRequested(string personId)

    function _followLink(kind, target) {
        // A ticket in a note is a task: opening it is the whole reason for
        // writing #HEAP-12 rather than the title. MdHtml calls it "task".
        if (kind === "task" || kind === "ticket") {
            root.taskRequested(target);
            return;
        }
        if (kind === "person") {
            const pid = AppController.personIdForHandle(target);
            if (pid.length > 0) root.personRequested(pid);
            return;
        }
        // A #tag lists the notes that carry it.
        if (kind === "tag") {
            notesList.setFilter("#" + target);
            return;
        }
        if (kind !== "note") return;
        const hit = AppController.resolveNoteLink(target);
        if (hit.kind === "note") {
            root._flushPending();
            AppController.activeNoteId = hit.noteId;
            return;
        }
        if (hit.kind === "heading") {
            // [[Note#Heading]] can name another note; open it first.
            if (hit.noteId && hit.noteId !== AppController.activeNoteId) {
                root._flushPending();
                AppController.activeNoteId = hit.noteId;
            }
            const off = AppController.noteHeadingOffset(editor.text, hit.heading);
            if (off >= 0) root._jumpToOffset(off);
            return;
        }
        // [[APP-101]] with no note of that name is the task of that id.
        const t = AppController.taskById(String(target).trim());
        if (t && t.id) {
            root.taskRequested(t.id);
            return;
        }
        missingLinkPopup.openFor(hit.title);
    }

    property string _loadedNoteId: ""
    function _loadFromController() {
        _reloading = true;
        const next = AppController.notesState || "";
        if (root._loadedNoteId === AppController.activeNoteId && root._loadedNoteId.length > 0 && editor.length > 0) {
            // The same note, changed from outside — a quick-capture append, an
            // import. Replace only what differs, so the caret stays where the
            // reader left it and Ctrl+Z still has the history (and can take the
            // outside change back too). Setting `text` reset both.
            const old = editor.text;
            if (old !== next) {
                let p = 0;
                const max = Math.min(old.length, next.length);
                while (p < max && old.charCodeAt(p) === next.charCodeAt(p)) p++;
                let s = 0;
                while (s < max - p && old.charCodeAt(old.length - 1 - s) === next.charCodeAt(next.length - 1 - s)) s++;
                const caret = editor.cursorPosition;
                if (old.length - s > p) editor.remove(p, old.length - s);
                const inserted = next.substring(p, next.length - s);
                if (inserted.length > 0) editor.insert(p, inserted);
                // Typing at the end of the note stays at the end; anywhere
                // else the caret keeps its place in the text it was in.
                if (caret <= p) editor.cursorPosition = caret;
            }
        } else {
            editor.text = next;
        }
        // "Load images" is consent for the note it was given in, not for the
        // next one: an imported note must not ping its tracker pixel on open
        // just because another note's images were allowed (KNOW-18).
        if (root._loadedNoteId !== AppController.activeNoteId) mdDocument.allowRemoteImages = false;
        root._loadedNoteId = AppController.activeNoteId;
        _reloading = false;
        root._refreshTitle();
        root._stats = AppController.noteStats(editor.text);
        root._refreshLinks();
        root._refreshAttachments();
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
        // Relative image paths resolve here; absolute local paths work anywhere.
        imageBaseDir: AppController.dataDir + "/attachments"
        palette: Theme.mdPalette
        ticketTitles: AppController.taskTitles
        // No preview on screen, no parse per pause; lookups still parse.
        live: preview.visible
    }

    // A pending edit is only in the editor until the 250 ms debounce fires.
    // Main.qml swaps views through a Loader, so this item is destroyed on
    // every view switch — without a flush the last keystrokes are lost.
    function _flushPending() {
        if (!persistTimer.running) return;
        persistTimer.stop();
        _persistNow();
    }

    Component.onCompleted: {
        highlighter.target = editor.textDocument;
        viewMode = _readViewMode();
        _loadFromController();
        _loadedOnce = true;
        // A palette hit that opened Notes for the first time: the binding's
        // first value does not fire the change handler.
        if (jumpToLine >= 0) Qt.callLater(root._consumeJump);
    }
    Component.onDestruction: _flushPending()
    // Quit is not covered by onDestruction: the engine tears down its root
    // objects and the AppController singleton in an unspecified order, and
    // ~AppController's own flushSave() may already have run by then. Flush
    // here, while both are alive, and push the debounced state.json write.
    Connections {
        target: Qt.application
        function onAboutToQuit() {
            root._flushPending();
            AppController.flushSave();
        }
    }
    // A broken link is usually a note somebody meant to write, so the offer to
    // write it is the useful thing to do with the click.
    Dialog {
        id: missingLinkPopup
        objectName: "missing-link"
        property string wanted: ""
        modal: true
        anchors.centerIn: Overlay.overlay
        parent: Overlay.overlay
        padding: Theme.inset
        width: 400
        title: I18n.t("notes.link.missingTitle")

        function openFor(target) {
            missingLinkPopup.wanted = target;
            missingLinkPopup.open();
        }

        background: Rectangle {
            radius: Theme.radiusXl
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        contentItem: Text {
            text: I18n.t("notes.link.missingBody").arg(missingLinkPopup.wanted)
            color: Theme.textMuted
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }

        footer: RowLayout {
            spacing: Theme.spMd
            Layout.margins: Theme.sp2xl
            Item { Layout.fillWidth: true }
            PillButton { text: I18n.t("common.cancel"); onClicked: missingLinkPopup.close() }
            PillButton {
                objectName: "missing-link-create"
                text: I18n.t("notes.link.create")
                primary: true
                onClicked: {
                    missingLinkPopup.close();
                    root._flushPending();
                    AppController.createNoteForLink(missingLinkPopup.wanted);
                }
            }
        }
    }

    Connections {
        target: AppController
        // Before the active note changes, while the old one is still active:
        // the debounced keystrokes go into the note they were typed in, not the
        // one about to be opened. Without this a "+" pressed inside the 250 ms
        // window moved the draft into the new note and emptied the old one.
        function onAboutToChangeActiveNote() { root._flushPending() }
        // An export or a search is about to read the whole profile.
        function onFlushEditorsRequested() { root._flushPending() }
        function onNotesStateChanged() {
            if (!root._loadedOnce || root._persisting) return;
            root._loadFromController();
            root._hideAutocomplete();
        }
    }
}
