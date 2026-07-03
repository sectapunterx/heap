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

    // ── State for autocomplete popup ─────────────────────────────────
    property string acTrigger: ""        // "@" or "#" or ""
    property int    acTriggerPos: -1     // index of trigger char in editor.text
    property string acFilter: ""
    property var    acMatches: []
    property int    acSelected: 0

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
        return score;
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

    function _rebuildMatches() {
        const source = acTrigger === "@" ? _peopleEntries()
                     : acTrigger === "#" ? _taskEntries()
                     : [];
        const scored = [];
        for (let i = 0; i < source.length; i++) {
            const e = source[i];
            const hay = (acTrigger === "@") ? e.label
                                            : (e.id + " " + e.label);
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

    function _detectAutocomplete() {
        const pos = editor.cursorPosition;
        const txt = editor.text;
        if (pos <= 0) { _hideAutocomplete(); return; }
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
        const insert = (acTrigger === "@")
            ? "@" + _slugifyName(e.label) + " "
            : "#" + e.id + " ";
        const pos = editor.cursorPosition;
        // Replace the "@filter" / "#filter" span in place (remove + insert) so
        // the caret stays at the edit point instead of resetting to 0. (HEAP-65)
        Mention.commit(editor, acTriggerPos, pos, insert);
        _hideAutocomplete();
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
                        text: "Notes · scratchpad"
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

                // ── Edit · Split · Preview toggle ──────────────────────
                Row {
                    spacing: 0
                    Repeater {
                        model: [
                            { id: "edit",    label: "Edit" },
                            { id: "split",   label: "Split" },
                            { id: "preview", label: "Preview" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool active: root.viewMode === modelData.id
                            implicitWidth: 64
                            implicitHeight: 24
                            radius: 0
                            color: active ? Theme.accentSoft
                                 : (segMA.containsMouse ? Theme.panel2 : "transparent")
                            border.color: active ? Theme.accent : Theme.border
                            border.width: 1
                            // Merge borders into a continuous bar.
                            Component.onCompleted: {
                                if (index === 0)      { /* leftmost — full radius */ }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.active ? Theme.accentStrong : Theme.textMuted
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

        // ── Editor + preview body ─────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Editor pane — visible in edit + split modes.
            Flickable {
                id: notesScroll
                visible: root.viewMode === "edit" || root.viewMode === "split"
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

                        // Smart Enter — continue markdown structure (list,
                        // numbered, checklist, quote) and preserve indent
                        // inside fenced code blocks.
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const txt = editor.text;
                            const pos = editor.cursorPosition;
                            const before = txt.substring(0, pos);
                            const lineStart = before.lastIndexOf("\n") + 1;
                            const line = txt.substring(lineStart, pos);

                            // Count fence boundaries before the cursor — odd
                            // means we're inside an open ``` block.
                            const fences = (before.match(/^```/gm) || []).length;
                            const insideFence = fences % 2 === 1;

                            let insert = null;
                            if (insideFence) {
                                const m = line.match(/^(\s+)/);
                                insert = "\n" + (m ? m[1] : "");
                            } else {
                                const checkM = line.match(/^(\s*)([-*+])\s+\[([ xX])\]\s+(.*)$/);
                                const listM  = line.match(/^(\s*)([-*+])\s+(.*)$/);
                                const numM   = line.match(/^(\s*)(\d+)\.\s+(.*)$/);
                                const quoteM = line.match(/^(\s*>+)\s+(.*)$/);

                                if (checkM) {
                                    if (checkM[4].length === 0) {
                                        // Empty checklist item → break out by
                                        // wiping the marker; default Enter
                                        // (event not accepted) inserts \n.
                                        editor.remove(lineStart, pos);
                                        return;
                                    }
                                    insert = "\n" + checkM[1] + checkM[2] + " [ ] ";
                                } else if (listM) {
                                    if (listM[3].length === 0) {
                                        editor.remove(lineStart, pos);
                                        return;
                                    }
                                    insert = "\n" + listM[1] + listM[2] + " ";
                                } else if (numM) {
                                    if (numM[3].length === 0) {
                                        editor.remove(lineStart, pos);
                                        return;
                                    }
                                    const next = parseInt(numM[2]) + 1;
                                    insert = "\n" + numM[1] + next + ". ";
                                } else if (quoteM) {
                                    if (quoteM[2].length === 0) {
                                        editor.remove(lineStart, pos);
                                        return;
                                    }
                                    insert = "\n" + quoteM[1] + " ";
                                }
                            }

                            if (insert !== null) {
                                editor.insert(pos, insert);
                                event.accepted = true;
                                return;
                            }
                        }

                        // Tab — inside fenced code block insert 4 spaces so
                        // it acts as code indent (instead of focus shift).
                        if (event.key === Qt.Key_Tab && (event.modifiers & ~Qt.KeypadModifier) === 0) {
                            const before = editor.text.substring(0, editor.cursorPosition);
                            const fences = (before.match(/^```/gm) || []).length;
                            if (fences % 2 === 1) {
                                editor.insert(editor.cursorPosition, "    ");
                                event.accepted = true;
                                return;
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
            Flickable {
                id: previewScroll
                visible: root.viewMode === "preview" || root.viewMode === "split"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: previewArea.implicitHeight + 48
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThinScrollBar {}

                NumberAnimation {
                    id: previewWheelAnim
                    target: previewScroll
                    property: "contentY"
                    duration: Theme.scaledMs(220)
                    easing.type: Easing.OutCubic
                }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const dy = event.angleDelta.y;
                        if (dy === 0) return;
                        const maxY = Math.max(0, previewScroll.contentHeight - previewScroll.height);
                        if (maxY <= 0) return;
                        const base = previewWheelAnim.running ? previewWheelAnim.to : previewScroll.contentY;
                        const newY = Math.max(0, Math.min(maxY, base - dy * 3));
                        if (newY === base) return;
                        previewWheelAnim.from = previewScroll.contentY;
                        previewWheelAnim.to = newY;
                        previewWheelAnim.restart();
                    }
                }

                // Renders the same text Qt's QTextDocument::setMarkdown sees.
                // Headings get larger fonts, `code` becomes monospace, lists
                // indent, [text](url) becomes an underlined link.
                TextArea {
                    id: previewArea
                    x: 24; y: 16
                    width: previewScroll.width - 48
                    height: Math.max(previewScroll.height - 32, implicitHeight + 16)
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextArea.Wrap
                    text: editor.text
                    textFormat: TextEdit.MarkdownText
                    color: Theme.text
                    placeholderText: I18n.t("notes.preview.empty")
                    placeholderTextColor: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    background: Item {}
                    onLinkActivated: (link) => Qt.openUrlExternally(link)
                }
            }
        }
    }

    // Ctrl+Shift+P — cycle edit → split → preview → edit.
    Shortcut {
        sequence: "Ctrl+Shift+P"
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
    NotesHighlighter {
        id: highlighter
        palette: ({
            heading:      Theme.accentStrong,
            bold:         Theme.text,
            italic:       Theme.text,
            code:         Theme.p2,
            codeBg:       Theme.bg2,
            codeBlock:    Theme.p2,
            codeBlockBg:  Theme.bg2,
            quote:        Theme.textMuted,
            mention:      Theme.mStandup,
            ticket:       Theme.p2,
            link:         Theme.accent,
            list:         Theme.accent,
            tableRow:     Theme.accentStrong,
            tableSep:     Theme.accent,
            latex:        Theme.mOneone,
            checkboxDone: Theme.stDone,
            hr:           Theme.borderStrong
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
                            visible: modelData.sub.length > 0
                            text: modelData.sub
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
