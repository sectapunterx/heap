// Ctrl+K fuzzy palette across profiles: tasks, docs, snippets, contacts, people.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp
import "PaletteMatch.js" as Match

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 600
    height: 480
    anchors.centerIn: Overlay.overlay

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: ModalScrim {}

    signal navigateToDoc(string sectionId)
    signal navigateToSnippets()
    signal navigateToContacts()
    signal openTask(string taskId)
    signal openPerson(string personId)
    // A note hit carries the line its section starts on, so opening it lands
    // the reader where the words were rather than at the top of the note.
    signal navigateToNoteLine(int line)
    signal navigateToDocPage(string pageId)

    // A command the palette cannot run itself (it needs a popup Main owns):
    // Main.runCommand(id) handles it. Ids are the shortcut catalog's
    // ("view.board", "task.new", "theme.toggle"…) plus "settings:<section>"
    // and a few palette-only ones ("event.new", "welcome.replay").
    signal commandRequested(string id)

    property var _entries: []           // cached full list
    property var _matches: []           // filtered + scored
    property int _selectedIdx: 0

    // Views a task editor can open over without losing the reader's place.
    readonly property var _taskViews: ["board", "timeline", "week", "month", "archive"]

    // Catalog actions that only mean something on a surface, with a cursor or
    // a selection — offered by the palette they would do nothing.
    readonly property var _contextual: ["palette.open", "task.openExternal", "undo", "redo"]
    function _isContextual(id) {
        // savedView.N is offered by name instead ("View: Urgent"), below.
        return _contextual.indexOf(id) >= 0 || id.indexOf("board.") === 0 || id.indexOf("savedView.") === 0
            || id.indexOf("cal.") === 0 || id.indexOf("selection.") === 0;
    }

    readonly property var _settingsSections: ["profile", "appearance", "language", "notifications", "safety",
                                              "calendar", "tasks", "shortcuts", "integrations", "git", "data", "help", "about"]

    // Commands: every app-wide action in the shortcut catalog (so the palette
    // and the keys never disagree on what exists or what it is called), each
    // Settings section, and a few that have no key of their own.
    function _commands() {
        const out = [];
        const list = AppController.shortcuts;
        for (let i = 0; i < list.length; i++) {
            const c = list[i];
            if (_isContextual(c.id)) continue;
            // Focus mode (APP-160) is offered once Settings → Safety net
            // turns it on, and says which way it goes.
            if (c.id === "focus.immersion") {
                if (!(AppController.safety && AppController.safety.immersion)) continue;
                out.push({ kind: "command", commandId: c.id, sub: c.sequence || "", body: c.description || "",
                           label: AppController.immersion ? I18n.t("palette.cmd.immersionOff") : c.label });
                continue;
            }
            out.push({ kind: "command", commandId: c.id, label: c.label, sub: c.sequence || "",
                       body: c.description || "" });
        }
        out.push({ kind: "command", commandId: "event.new", label: I18n.t("palette.cmd.newEvent"), sub: "" });
        out.push({ kind: "command", commandId: "welcome.replay", label: I18n.t("palette.cmd.replayTour"), sub: "" });
        out.push({ kind: "command", commandId: "recap.open", label: I18n.t("palette.cmd.weeklyRecap"), sub: "" });
        // The standup draft (APP-170), once Settings → Safety net turns it on.
        if (AppController.safety && AppController.safety.standupDraft)
            out.push({ kind: "command", commandId: "standup.draft", label: I18n.t("palette.cmd.standupDraft"), sub: "" });
        out.push({ kind: "command", commandId: "timeMachine.open", label: I18n.t("palette.cmd.timeMachine"), sub: "" });
        // The day's summary (APP-190): read-only, so always on offer.
        out.push({ kind: "command", commandId: "endOfDay.open", label: I18n.t("palette.cmd.endOfDay"), sub: "" });
        // Saved views: one command per view, by name, plus saving the current
        // filters as one.
        const views = AppController.savedViews;
        for (let v = 0; v < views.length; v++) {
            out.push({ kind: "command", commandId: "savedview:" + views[v].id,
                       label: I18n.t("palette.cmd.savedView").arg(views[v].name),
                       sub: v < 9 ? AppController.shortcutFor("savedView." + (v + 1)) : "",
                       body: views[v].query });
        }
        out.push({ kind: "command", commandId: "savedview.save", label: I18n.t("palette.cmd.saveView"), sub: "" });
        // Integrations health (APP-164) lives at the top of that section.
        out.push({ kind: "setting", commandId: "settings:integrations", label: I18n.t("palette.cmd.integrationsHealth"),
                   sub: I18n.t("health.hint") });
        for (let j = 0; j < _settingsSections.length; j++) {
            const id = _settingsSections[j];
            out.push({ kind: "setting", commandId: "settings:" + id,
                       label: I18n.t("palette.cmd.settings").arg(I18n.t("settings.section." + id + ".title")),
                       sub: I18n.t("settings.section." + id + ".sub") });
        }
        return out;
    }

    // ── Recents ──────────────────────────────────────────────────────
    // An empty query used to list whatever came first (the docs catalogue);
    // it shows what was opened last now, then the commands. Kept in the
    // settings blob (paletteRecents), newest first, eight at most.
    readonly property int _recentMax: 8
    function _key(e) {
        if (!e) return "";
        const id = e.commandId || e.taskId || e.personId || e.templateName || e.eventId
                // Which note and which heading in it: profile + line alone
                // made every note's title row the same key (KNOW-5).
                || (e.kind === "note" ? (e.profileId || "") + "#" + (e.noteId || "") + "#" + (e.line || 0) : "")
                || (e.kind === "docPage" ? (e.pageId || "") + "#" + (e.line || 0) : "")
                || (e.kind === "doc" ? (e.sectionId || "") + "#" + e.label : "")
                || (e.kind === "profile" ? e.profileId : "")
                || e.label;
        return e.kind + ":" + id;
    }
    function _settingsObj() {
        const raw = AppController.appSettingsJson || "";
        if (!raw.length) return ({});
        try { return JSON.parse(raw) || ({}); } catch (err) { return ({}); }
    }
    function _recentKeys() {
        const r = _settingsObj().paletteRecents;
        return Array.isArray(r) ? r.filter(function (k) { return typeof k === "string"; }) : [];
    }
    function _remember(entry) {
        const k = _key(entry);
        if (!k.length) return;
        const s = _settingsObj();
        const keys = _recentKeys().filter(function (x) { return x !== k; });
        keys.unshift(k);
        s.paletteRecents = keys.slice(0, _recentMax);
        AppController.appSettingsJson = JSON.stringify(s);
    }
    function _recents() {
        const keys = _recentKeys();
        const byKey = {};
        for (let i = 0; i < _entries.length; i++) {
            const k = _key(_entries[i]);
            if (!byKey[k]) byKey[k] = _entries[i];
        }
        const out = [];
        for (let j = 0; j < keys.length; j++) {
            const e = byKey[keys[j]];
            if (e) out.push(Object.assign({}, e, { _recent: true }));
        }
        return out;
    }

    function _refresh() {
        _entries = AppController.commandPaletteEntries().concat(_commands());
        _matches = _filterAndScore("");
        _selectedIdx = 0;
    }

    // Word-order independent, typo tolerant (PaletteMatch.js). Returns -1 for
    // no match, otherwise >= 0.
    function _fuzzyScore(q, s) {
        return Match.score(q, s);
    }

    function _escapeHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // Build a StyledText snippet: ~30 chars of context on each side of the first
    // occurrence of `q` in `body`, with the match emphasised. "" if not present.
    function _snippetFor(body, q) {
        if (!body || q.length < 2) return "";
        const idx = body.toLowerCase().indexOf(q.toLowerCase());
        if (idx < 0) return "";
        const start = Math.max(0, idx - 30);
        const end = Math.min(body.length, idx + q.length + 40);
        const frag = body.substring(start, end).replace(/\s+/g, " ").trim();
        const mi = frag.toLowerCase().indexOf(q.toLowerCase());
        const lead = start > 0 ? "…" : "";
        const tail = end < body.length ? "…" : "";
        if (mi < 0) return lead + _escapeHtml(frag) + tail;
        return lead + _escapeHtml(frag.substring(0, mi))
             + "<b>" + _escapeHtml(frag.substring(mi, mi + q.length)) + "</b>"
             + _escapeHtml(frag.substring(mi + q.length)) + tail;
    }

    function _filterAndScore(q) {
        const trimmed = (q || "").trim();
        if (trimmed.length === 0) {
            // Recents, then every command — something to act on, never an
            // arbitrary slice of the docs.
            const rec = _recents();
            const seen = {};
            for (let r = 0; r < rec.length; r++) seen[_key(rec[r])] = true;
            const out0 = rec.slice();
            for (let i = 0; i < _entries.length; i++) {
                const e = _entries[i];
                if ((e.kind === "command" || e.kind === "setting") && !seen[_key(e)]) out0.push(e);
            }
            return out0.slice(0, 80).map(function (e) { const c = Object.assign({}, e); c._snippet = ""; return c; });
        }
        const out = [];
        const firstWord = trimmed.split(/\s+/)[0];
        const ql = trimmed.toLowerCase();
        for (let i = 0; i < _entries.length; i++) {
            const e = _entries[i];
            let score = _fuzzyScore(trimmed, e.label + " " + (e.sub || ""));
            // The words themselves in the label beat a scattered subsequence:
            // "windows" should rank "Release › Windows" above "Release".
            if (ql.length >= 2 && score >= 0 && e.label.toLowerCase().indexOf(ql) >= 0) score += 20;
            // A person is found as an @-mention finds them: by a login made of
            // the name ("r.losev" for Роман Лосев), by the name in the other
            // script ("roman losev"). Exact login ~ 180, a word prefix 100.
            if (e.kind === "person" || e.kind === "contact") {
                const pr = AppController.personMatchRank(trimmed, e.label, e.personId || "");
                if (pr > 0) score = Math.max(score, pr * 2);
            }
            let snippet = "";
            // Full-text (HEAP-80): every word in the body, with a context
            // snippet. A body hit floors the entry at tier 5, below head matches.
            if (trimmed.length >= 2 && e.body && Match.bodyHit(trimmed, e.body)) {
                snippet = _snippetFor(e.body, trimmed.toLowerCase().indexOf(" ") < 0 ? trimmed : firstWord);
                score = Math.max(score, 5);
            }
            if (score < 0) continue;
            // tiny boost so an entry in the active profile floats up
            const profBonus = (e.profileId === AppController.activeProfileId) ? 1 : 0;
            out.push({ entry: e, score: score + profBonus, snippet: snippet });
        }
        out.sort(function (a, b) { return b.score - a.score; });
        return out.slice(0, 80).map(function (x) {
            const c = Object.assign({}, x.entry);
            c._snippet = x.snippet;
            return c;
        });
    }

    function _activate(entry) {
        if (!entry) return;
        _remember(entry);
        const switchProfile = (entry.profileId && entry.profileId !== AppController.activeProfileId);
        if (switchProfile) AppController.activeProfileId = entry.profileId;
        Qt.callLater(function () {
            if (entry.kind === "profile") {
                // already switched above
            } else if (entry.kind === "command" || entry.kind === "setting") {
                // Closed first: a command often opens a popup of its own.
                root.close();
                root.commandRequested(entry.commandId);
                return;
            } else if (entry.kind === "task") {
                // The editor opens over any view that shows tasks; only a view
                // with no tasks on it (notes, docs, settings) gives way to the
                // board. It used to jump to the board from anywhere.
                if (root._taskViews.indexOf(AppController.currentView) < 0)
                    AppController.currentView = "board";
                root.openTask(entry.taskId);
            } else if (entry.kind === "doc") {
                AppController.currentView = "docs";
                root.navigateToDoc(entry.sectionId);
            } else if (entry.kind === "snippet") {
                AppController.currentView = "docs";
                root.navigateToSnippets();
            } else if (entry.kind === "contact") {
                AppController.currentView = "docs";
                root.navigateToContacts();
            } else if (entry.kind === "person") {
                root.openPerson(entry.personId);
            } else if (entry.kind === "note") {
                // Any note of the profile, not just the open one.
                if (entry.noteId) AppController.activeNoteId = entry.noteId;
                AppController.currentView = "notes";
                root.navigateToNoteLine(entry.line !== undefined ? entry.line : 0);
            } else if (entry.kind === "docPage") {
                AppController.activeDocPageId = entry.pageId;
                AppController.currentView = "docs";
                root.navigateToDocPage(entry.pageId);
            } else if (entry.kind === "dailyNote") {
                AppController.currentView = "notes";
                AppController.openDailyNote();
            } else if (entry.kind === "event") {
                // The week the event is in, selected on the day it falls on —
                // landing on the month would leave the reader to find it again.
                if (entry.eventDate) AppController.selectedDate = entry.eventDate;
                AppController.currentView = "week";
            } else if (entry.kind === "template") {
                if (root._taskViews.indexOf(AppController.currentView) < 0)
                    AppController.currentView = "board";
                AppController.createTaskFromTemplate(entry.templateName);
            }
            root.close();
        });
    }

    // Badge glyph and the localized kind name, for every kind the palette
    // lists; an unknown kind used to render "?".
    function _kindGlyph(kind) {
        switch (kind) {
            case "task":      return "T";
            case "doc":       return "D";
            case "snippet":   return "S";
            case "contact":   return "C";
            case "profile":   return "●";
            case "person":    return "P";
            case "note":      return "N";
            case "docPage":   return "¶";
            case "dailyNote": return "☼";
            case "event":     return "E";
            case "template":  return "✚";
            case "command":   return "›";
            case "setting":   return "⚙";
        }
        return "·";
    }
    function _kindLabel(kind) {
        const k = "palette.kind." + kind;
        const t = I18n.t(k);
        return t === k ? kind : t;
    }

    onAboutToShow: {
        _refresh();
        searchField.text = "";
        Qt.callLater(searchField.forceActiveFocus);
    }

    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: 0

        // Search row
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            color: "transparent"
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: Theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.sp2xl
                spacing: Theme.spLg
                Text { text: "⌕"; color: Theme.textMuted; font.pixelSize: Theme.fsXl }
                TextField {
                    id: searchField
                    ContextMenu.menu: TextEditMenu { editor: searchField }
                    Layout.fillWidth: true
                    placeholderText: I18n.t("palette.placeholderLong")
                    background: Item {}
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    font.pixelSize: Theme.fsLg
                    selectByMouse: true
                    onTextChanged: {
                        root._matches = root._filterAndScore(text);
                        root._selectedIdx = 0;
                    }
                    Keys.onDownPressed:  if (root._matches.length > 0) root._selectedIdx = Math.min(root._matches.length - 1, root._selectedIdx + 1)
                    Keys.onUpPressed:    if (root._matches.length > 0) root._selectedIdx = Math.max(0, root._selectedIdx - 1)
                    Keys.onReturnPressed: root._activate(root._matches[root._selectedIdx])
                    Keys.onEnterPressed:  root._activate(root._matches[root._selectedIdx])
                }
                Text {
                    visible: root._matches.length > 0
                    text: (root._selectedIdx + 1) + " / " + root._matches.length
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsSm
                }
            }
        }

        // Results
        ListView {
            id: resultsView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            currentIndex: root._selectedIdx
            highlightFollowsCurrentItem: true
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            model: root._matches
            spacing: Theme.sp2xs

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: ListView.view.width
                height: (modelData._snippet && modelData._snippet.length > 0) ? 58 : 42
                color: index === root._selectedIdx ? Theme.rowHighlight : "transparent"
                radius: Theme.radiusSm
                // The selected row's marker: 3:1 against the panel on every
                // theme (panel2 alone was 1.03:1).
                Rectangle {
                    objectName: "palette-row-marker"
                    visible: index === root._selectedIdx
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: parent.height - 2 * Theme.spSm
                    radius: Theme.radiusXs
                    color: Theme.focusRing
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spXl; anchors.rightMargin: Theme.spXl
                    spacing: Theme.spLg

                    Rectangle {
                        width: 18; height: 18; radius: Theme.radiusSm
                        color: "transparent"
                        border.color: modelData.color || Theme.accent
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: root._kindGlyph(modelData.kind)
                            color: modelData.color || Theme.accentStrong
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsXs
                            font.weight: Theme.fwTitle
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
                            visible: !(modelData._snippet && modelData._snippet.length > 0)
                            text: modelData.sub
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsXs
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        // Full-text context snippet with the match emphasised
                        // (HEAP-80). Shown in place of `sub` when the hit is in
                        // the body rather than the title.
                        Text {
                            visible: modelData._snippet && modelData._snippet.length > 0
                            text: modelData._snippet || ""
                            textFormat: Text.StyledText
                            color: Theme.textMuted
                            font.pixelSize: Theme.fsSm
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        text: (modelData._recent ? "↺ " : "") + root._kindLabel(modelData.kind)
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.features: Theme.tabularNums
                        font.pixelSize: Theme.fsXs
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root._selectedIdx = index
                    onClicked: root._activate(modelData)
                }
            }

            // Empty state: nothing typed yet, or nothing found — with a line
            // on what the palette does search (APP-167).
            EmptyState {
                objectName: "palette-empty"
                visible: root._matches.length === 0
                anchors.centerIn: parent
                width: Math.min(parent.width - 2 * Theme.sp3xl, 380)
                compact: searchField.text.length === 0
                title: searchField.text.length === 0 ? I18n.t("palette.empty.start") : I18n.t("palette.empty.miss")
                line: searchField.text.length === 0 ? "" : I18n.t("palette.empty.missHint")
            }
        }

        // Hints
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: Theme.panel2
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: Theme.border }
            Text {
                anchors.centerIn: parent
                text: I18n.t("palette.kbdHint")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsXs
            }
        }
    }
}
