// The command line (APP-267, sheets Q-Command / H2-Command): Ctrl+K, Ctrl+P,
// ":" — search, filter and act in one line. What is typed is read in the
// language quick capture speaks ("заблок p0 до пт оформ"): a finished
// condition becomes a chip, the rest searches. Results come in groups —
// the tasks found, what to do with them, what to do with this filter, the
// task the cursor was on, the commands, and notes, docs and people — each
// action with its key. ">" (or ":") leaves only the commands.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp
import "PaletteMatch.js" as Match
import "KeyRules.js" as KeyRules

Popup {
    id: root
    objectName: "command-line"
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 2 * Theme.sp3xl : 960,
                    root.syntaxShown ? Theme.px(980) : Theme.px(680))
    height: Theme.px(520)
    anchors.centerIn: Overlay.overlay

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: ModalScrim {}

    // Catalogue entries are found in the Knowledge list (DG-070): the text
    // to search it for.
    signal navigateToDoc(string text)
    signal navigateToSnippets(string text)
    signal navigateToContacts(string text)
    signal openTask(string taskId)
    signal openPerson(string personId)
    // A note hit carries the line its section starts on, so opening it lands
    // the reader where the words were rather than at the top of the note.
    signal navigateToNoteLine(int line)
    signal navigateToDocPage(string pageId)

    // A command the palette cannot run itself (it needs a popup Main owns):
    // Main.runCommand(id) handles it. Ids are the shortcut catalog's
    // ("view.board", "task.new", "theme.toggle"…) plus "settings:<section>"
    // and a palette-only one ("event.new").
    signal commandRequested(string id)
    // This filter in Tasks: on the board, as a list, or saved as a view
    // (mode "board" | "list" | "save").
    signal queryRequested(string query, string mode)
    // "Nothing found · create «…»": the task input with the words in it.
    signal createRequested(string text)

    // function () → the ids of the task(s) the cursor or selection was on
    // when the line opened (Main's _keyTaskIds): the "For the selected task"
    // group acts on them.
    property var contextProvider: null
    property var _context: []

    property var _entries: []           // cached full list
    property var _rows: []              // what the list shows: headers and entries
    property var _matches: []           // the entries of _rows, in order — what ↑↓ walk
    property int _selectedIdx: 0

    // Conditions already turned into chips: [{kind, clause, value, words}].
    property var chips: []
    // The parse of the field, for the "Tab →" hint and the results.
    property var _parse: ({ tokens: [], text: "", tasks: [], total: 0, query: "" })
    property bool _sync: false

    // The syntax card beside the results (hideable, remembered).
    readonly property bool syntaxShown: {
        const s = root._settingsObj();
        return !(s.commandLine && s.commandLine.syntax === false);
    }
    function toggleSyntax() {
        const s = root._settingsObj();
        s.commandLine = Object.assign({}, s.commandLine || {}, { syntax: !root.syntaxShown });
        AppController.appSettingsJson = JSON.stringify(s);
    }

    // Views a task editor can open over without losing the reader's place.
    readonly property var _taskViews: ["board", "timeline", "week", "month", "archive"]

    // Catalog actions that only mean something on a surface, with a cursor or
    // a selection — offered by the palette they would do nothing. A second
    // key of an action (".alt") is the same command.
    readonly property var _contextual: ["palette.open", "palette.commands", "task.openExternal", "undo", "redo"]
    function _isContextual(id) {
        // savedView.N is offered by name instead ("View: Urgent"), below.
        return _contextual.indexOf(id) >= 0 || id.indexOf("board.") === 0 || id.indexOf("savedView.") === 0
            || id.indexOf("cal.") === 0 || id.indexOf("selection.") === 0 || id.indexOf("cursor.") === 0
            || id.indexOf("nav.") === 0 || /\.alt\d*$/.test(id)
            || (id.indexOf("task.") === 0 && id !== "task.new");
    }

    // Catalog actions whose palette name says more than their hotkey label.
    readonly property var _paletteLabels: ({
        "timeMachine.open": "palette.cmd.timeMachine",
        "standup.draft":    "palette.cmd.standupDraft",
        "recap.open":       "palette.cmd.weeklyRecap",
        "endOfDay.open":    "palette.cmd.endOfDay",
        "welcome.replay":   "palette.cmd.replayTour"
    })

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
                out.push({ kind: "command", commandId: c.id, sub: AppController.keyText(c.sequence || ""), body: c.description || "",
                           label: AppController.immersion ? I18n.t("palette.cmd.immersionOff") : c.label });
                continue;
            }
            // The standup draft (APP-170), once Settings → Safety net turns it on.
            if (c.id === "standup.draft" && !(AppController.safety && AppController.safety.standupDraft)) continue;
            // The 0.6 tools read clearer in the palette with what they do.
            const label = _paletteLabels[c.id] ? I18n.t(_paletteLabels[c.id]) : c.label;
            out.push({ kind: "command", commandId: c.id, label: label, sub: AppController.keyText(c.sequence || ""),
                       body: c.description || "" });
        }
        // A new event at 9:00 of the selected day; the catalog's key for a
        // new event (at the next free slot) is the nearest thing to a hint.
        out.push({ kind: "command", commandId: "event.new", label: I18n.t("palette.cmd.newEvent"),
                   sub: AppController.shortcutText("cal.newEvent") });
        // Saved views: one command per view, by name, plus saving the current
        // filters as one.
        const views = AppController.savedViews;
        for (let v = 0; v < views.length; v++) {
            out.push({ kind: "command", commandId: "savedview:" + views[v].id,
                       label: I18n.t("palette.cmd.savedView").arg(views[v].name),
                       sub: v < 9 ? AppController.shortcutText("savedView." + (v + 1)) : "",
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
                AppController.currentView = "notes";
                root.navigateToDoc(entry.title || entry.label);
            } else if (entry.kind === "snippet") {
                AppController.currentView = "notes";
                root.navigateToSnippets(entry.label);
            } else if (entry.kind === "contact") {
                AppController.currentView = "notes";
                root.navigateToContacts(entry.label);
            } else if (entry.kind === "person") {
                root.openPerson(entry.personId);
            } else if (entry.kind === "note") {
                // Any note of the profile, not just the open one.
                if (entry.noteId) AppController.activeNoteId = entry.noteId;
                AppController.currentView = "notes";
                root.navigateToNoteLine(entry.line !== undefined ? entry.line : 0);
            } else if (entry.kind === "docPage") {
                AppController.activeDocPageId = entry.pageId;
                AppController.currentView = "notes";
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

    // ── The command line ─────────────────────────────────────────────
    function openWith(text) {
        root._initial = text || "";
        root.open();
    }
    property string _initial: ""

    // The chips' clauses, then the field: what the task search runs.
    function _fullText() {
        return root.chips.map(c => c.clause).concat([searchField.text]).join(" ").trim();
    }
    function _commandsOnly() {
        return root.chips.length === 0 && searchField.text.trim().indexOf(">") === 0;
    }
    // A finished condition ("заблок ", "p0 ") moves out of the field into a
    // chip; Tab does it for the word still being typed.
    function commitTokens(all) {
        if (root._commandsOnly()) return false;
        const raw = searchField.text;
        if (!all && !/\s$/.test(raw)) return false;
        const p = AppController.commandLine(raw, 0);
        if (!p.tokens || p.tokens.length === 0) return false;
        root._sync = true;
        root.chips = root.chips.concat(p.tokens);
        searchField.text = p.text.length > 0 ? p.text + (all ? "" : " ") : "";
        root._sync = false;
        root._rebuild();
        return true;
    }
    function removeChip(i) {
        const list = root.chips.slice();
        list.splice(i, 1);
        root.chips = list;
        root._rebuild();
    }
    // The words a chip shows: a key for the field and the value.
    function chipKey(c) {
        const keys = { status: "status", priority: "priority", tag: "label", due: "due", when: "when", ticket: "ticket" };
        if (keys[c.kind]) return I18n.t("query.key." + keys[c.kind]);
        const at = String(c.clause).indexOf(":");
        return at > 0 ? String(c.clause).slice(0, at) : I18n.t("query.key.other");
    }
    function chipValue(c) {
        if (c.kind === "clause") {
            const at = String(c.clause).indexOf(":");
            return at > 0 ? String(c.clause).slice(at + 1) : c.clause;
        }
        return c.value;
    }

    // The task actions, for the task the line opened on or for what it found.
    function _taskAction(action, ids, labelKey, keyId, extra) {
        return Object.assign({ kind: "action", action: action, ids: ids, label: I18n.t(labelKey),
                               keys: keyId ? AppController.shortcutText(keyId) : "", sub: "" }, extra || {});
    }
    function _contextActions(filter) {
        const ids = root._context || [];
        if (ids.length === 0) return [];
        const t = AppController.taskById(ids[0]);
        if (!t || !t.id) return [];
        const done = AppController.statusCategory(t.status) === "done";
        const url = String((t.ticket && t.ticket.url) || t.externalUrl || "");
        const out = [
            root._taskAction("done", ids, done ? "taskmenu.reopen" : "taskmenu.done", "task.done"),
            root._taskAction("schedule", ids, "taskmenu.schedule", "task.schedule"),
            root._taskAction("due", ids, "taskmenu.due", "task.due"),
            root._taskAction("timer", ids, t.isTiming ? "taskcard.stopTimer" : "taskcard.startTimer", "task.timer"),
            root._taskAction("copyId", ids, "taskcard.copyId", "task.copyId"),
            root._taskAction("branch", ids, "taskcard.createBranch", "task.createBranch"),
            root._taskAction("archive", ids, t.archived ? "taskcard.unarchive" : "taskcard.archive", "board.archive")
        ];
        if (url.length > 0) out.splice(5, 0, root._taskAction("external", ids, "cmd.openInTracker", "task.openExternal"));
        const q = String(filter || "").trim();
        return q.length === 0 ? out : out.filter(a => Match.score(q, a.label) >= 0);
    }
    // A task command asked for by its exact name with no task to act on:
    // shown, off, with the reason (APP-267 corner case).
    function _unavailable(q) {
        const query = String(q || "").trim().toLowerCase();
        if (query.length < 3 || (root._context || []).length > 0) return [];
        const out = [];
        const list = AppController.shortcuts;
        for (let i = 0; i < list.length; i++) {
            const c = list[i];
            if (c.id.indexOf("task.") !== 0 || c.id === "task.new" || /\.alt\d*$/.test(c.id)) continue;
            if (String(c.label).toLowerCase() !== query) continue;
            out.push({ kind: "action", action: "none", ids: [], label: c.label, keys: AppController.shortcutText(c.id),
                       sub: "", off: true, note: I18n.t("cmd.why.noTask") });
        }
        return out;
    }

    function _rebuild() {
        const raw = searchField.text;
        const rows = [];
        const header = function (label) { rows.push({ header: true, label: label }); };
        const free = raw.trim();
        if (root._commandsOnly()) {
            const q = free.slice(1).trim();
            root._parse = { tokens: [], text: q, tasks: [], total: 0, query: "" };
            const cmds = (q.length > 0 ? root._filterAndScore(q) : root._entries)
                .filter(e => e.kind === "command" || e.kind === "setting");
            const extra = root._unavailable(q);
            if (cmds.length + extra.length > 0) header(I18n.t("cmd.group.commands"));
            for (const e of extra) rows.push(e);
            for (const e of cmds) rows.push(Object.assign({}, e, { keys: e.sub || "", sub: "" }));
        } else if (free.length === 0 && root.chips.length === 0) {
            root._parse = { tokens: [], text: "", tasks: [], total: 0, query: "" };
            const ctx = root._contextActions("");
            if (ctx.length > 0) {
                header(I18n.t("cmd.group.selected").arg(root._context.length === 1 ? root._context[0] : root._context.length));
                for (const a of ctx) rows.push(a);
            }
            const rest = root._filterAndScore("");
            if (rest.length > 0) header(I18n.t("cmd.group.recent"));
            for (const e of rest) rows.push(Object.assign({}, e, { keys: e.kind === "command" ? (e.sub || "") : "",
                                                                   sub: e.kind === "command" ? "" : e.sub }));
        } else {
            const p = AppController.commandLine(root._fullText(), 50);
            root._parse = p;
            const words = p.text;
            // The tasks found.
            const found = [];
            for (const t of p.tasks) {
                found.push({ kind: "task", taskId: t.id, label: t.id + " · " + t.title,
                             sub: t.statusName + (t.archived ? " · " + I18n.t("cmd.archived") : ""),
                             archived: t.archived, category: t.category, keys: "" });
            }
            if (found.length > 0) {
                header(I18n.t("cmd.group.tasks").arg(p.total));
                for (const e of found) rows.push(e);
                if (p.total > found.length)
                    rows.push({ kind: "more", label: I18n.t("cmd.more").arg(p.total - found.length),
                                keys: AppController.keyText("Ctrl+Return"), sub: "" });
                // What to do with them.
                const open = found.filter(e => e.category !== "done" && !e.archived).map(e => e.taskId);
                const acts = [];
                if (open.length > 0)
                    acts.push(root._taskAction("doneFound", open, "cmd.doneFound", "task.done",
                                               { sub: I18n.count(open.length, "cmd.n.tasks") }));
                const allBlocked = found.length > 0 && found.every(e => e.category === "blocked");
                const prog = AppController.statuses.find(st => AppController.statusCategory(st.id) === "prog");
                if (allBlocked && prog)
                    acts.push({ kind: "action", action: "unblock", ids: found.map(e => e.taskId), status: prog.id,
                                label: I18n.t("cmd.unblock").arg(prog.name), keys: "", sub: "" });
                if (acts.length > 0) {
                    header(I18n.t("cmd.group.withFound"));
                    for (const a of acts) rows.push(a);
                }
            }
            // What to do with this filter.
            const q = p.query;
            if (q.length > 0 && (root.chips.length > 0 || p.tokens.length > 0)) {
                header(I18n.t("cmd.group.withFilter"));
                const name = root.chips.concat(p.tokens).map(c => root.chipValue(c)).join(" · ");
                rows.push({ kind: "action", action: "saveView", query: q, label: I18n.t("cmd.saveView").arg(name),
                            keys: AppController.keyText("Ctrl+S"), sub: I18n.t("cmd.saveView.sub") });
                rows.push({ kind: "action", action: "openBoard", query: q, label: I18n.t("cmd.openBoard"),
                            keys: AppController.shortcutText("view.board"), sub: "" });
                rows.push({ kind: "action", action: "openList", query: q, label: I18n.t("cmd.openList"),
                            keys: AppController.keyText("Ctrl+Return"), sub: "" });
            }
            // The task the line opened on, then the commands, then the rest.
            const ctx = root._contextActions(words);
            if (ctx.length > 0) {
                header(I18n.t("cmd.group.selected").arg(root._context.length === 1 ? root._context[0] : root._context.length));
                for (const a of ctx) rows.push(a);
            }
            const scored = words.length > 0 ? root._filterAndScore(words) : [];
            const cmds = scored.filter(e => e.kind === "command" || e.kind === "setting").slice(0, 8);
            const extra = root._unavailable(words);
            if (cmds.length + extra.length > 0) header(I18n.t("cmd.group.commands"));
            for (const e of extra) rows.push(e);
            for (const e of cmds) rows.push(Object.assign({}, e, { keys: e.sub || "", sub: "" }));
            const shownTasks = {};
            for (const e of found) shownTasks[e.taskId] = true;
            const other = scored.filter(e => e.kind !== "command" && e.kind !== "setting"
                                             && !(e.kind === "task" && (shownTasks[e.taskId]
                                                                        || e.profileId === AppController.activeProfileId)))
                .slice(0, 20);
            if (other.length > 0) header(I18n.t("cmd.group.other"));
            for (const e of other) rows.push(Object.assign({}, e, { keys: "" }));
            // Nothing at all: make it a task.
            if (rows.length === 0)
                rows.push({ kind: "create", label: I18n.t("cmd.create").arg(raw.trim()), text: raw.trim(),
                            keys: AppController.keyText("Return"), sub: "" });
        }
        const matches = [];
        for (const r of rows) {
            if (r.header) continue;
            r._idx = matches.length;
            matches.push(r);
        }
        root._rows = rows;
        root._matches = matches;
        root._selectedIdx = 0;
    }

    function _move(step) {
        if (root._matches.length === 0) return;
        let i = root._selectedIdx;
        for (let n = 0; n < root._matches.length; n++) {
            i = Math.max(0, Math.min(root._matches.length - 1, i + step));
            if (!root._matches[i].off) break;
        }
        root._selectedIdx = i;
    }

    function _runAction(e) {
        const ids = e.ids || [];
        switch (e.action) {
        case "done": case "doneFound": AppController.toggleDone(ids); break;
        case "unblock": for (const id of ids) AppController.moveTaskTo(id, e.status, ""); break;
        case "schedule": for (const id of ids) AppController.scheduleTaskAtNextFreeSlot(id, AppController.selectedDate); break;
        case "due": if (ids.length > 0) root.openTask(ids[0]); break;
        case "timer":
            for (const id of ids) {
                const t = AppController.taskById(id);
                if (t && t.isTiming) AppController.stopTaskTimer(id); else AppController.startTaskTimer(id);
            }
            break;
        case "copyId": AppController.copyToClipboard(ids.join(", ")); break;
        case "external": if (ids.length > 0) AppController.openTaskExternal(ids[0]); break;
        case "branch": if (ids.length > 0) AppController.createBranchForTask(ids[0]); break;
        case "archive":
            for (const id of ids) {
                const t = AppController.taskById(id);
                AppController.setArchived(id, !(t && t.archived));
            }
            break;
        case "saveView": root.queryRequested(e.query, "save"); break;
        case "openBoard": root.queryRequested(e.query, "board"); break;
        case "openList": root.queryRequested(e.query, "list"); break;
        }
    }

    function activateSelected() {
        const e = root._matches[root._selectedIdx];
        if (!e || e.off) return;
        if (e.kind === "action") {
            root.close();
            root._runAction(e);
            return;
        }
        if (e.kind === "more") {
            root.close();
            root.queryRequested(root._parse.query, "list");
            return;
        }
        if (e.kind === "create") {
            root.close();
            root.createRequested(e.text);
            return;
        }
        root._activate(e);
    }
    // Ctrl+Enter: everything found, in Tasks as a list.
    function showAllAsList() {
        const q = root._parse.query || "";
        if (q.length === 0) return;
        root.close();
        root.queryRequested(q, "list");
    }

    onAboutToShow: {
        root._context = root.contextProvider ? root.contextProvider() : [];
        root._entries = AppController.commandPaletteEntries().concat(root._commands());
        root._sync = true;
        root.chips = [];
        searchField.text = root._initial;
        root._initial = "";
        root._sync = false;
        root._rebuild();
        Qt.callLater(function () {
            searchField.forceActiveFocus();
            searchField.cursorPosition = searchField.text.length;
        });
    }

    // Ctrl+K again closes it (APP-267).
    Shortcut {
        sequences: [AppController.shortcuts.length >= 0 ? AppController.shortcutFor("palette.open") : "",
                    AppController.shortcutFor("palette.open.alt")]
        context: Qt.WindowShortcut
        enabled: root.opened
        onActivated: root.close()
        onActivatedAmbiguously: root.close()
    }

    background: ModalSurface {}

    contentItem: RowLayout {
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // The line: chips, then the field.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(Theme.px(48), inputFlow.implicitHeight + 2 * Theme.spMd)
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 1; color: Theme.border
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.spXl
                    spacing: Theme.spMd
                    Text {
                        text: root._commandsOnly() ? "›" : "⌕"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsXl
                    }
                    Flow {
                        id: inputFlow
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.spSm
                        Repeater {
                            model: root.chips
                            delegate: PropertyChip {
                                id: chip
                                required property var modelData
                                required property int index
                                objectName: "cmd-chip-" + chip.index
                                small: true
                                removable: true
                                key: root.chipKey(chip.modelData)
                                value: root.chipValue(chip.modelData)
                                onRemoved: root.removeChip(chip.index)
                            }
                        }
                        TextField {
                            id: searchField
                            objectName: "cmd-field"
                            ContextMenu.menu: TextEditMenu { editor: searchField }
                            width: Math.max(Theme.px(200), inputFlow.width - x)
                            placeholderText: root.chips.length > 0 ? "" : I18n.t("cmd.placeholder")
                            background: Item {}
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                            font.pixelSize: Theme.fsLg
                            selectByMouse: true
                            onTextChanged: {
                                if (root._sync) return;
                                if (!root.commitTokens(false)) root._rebuild();
                            }
                            Keys.onDownPressed: root._move(1)
                            Keys.onUpPressed: root._move(-1)
                            Keys.onTabPressed: (event) => {
                                root.commitTokens(true);
                                event.accepted = true;
                            }
                            Keys.onPressed: (event) => {
                                const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
                                if (enter && (event.modifiers & Qt.ControlModifier)) {
                                    root.showAllAsList();
                                    event.accepted = true;
                                } else if (enter) {
                                    root.activateSelected();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                                    const q = root._parse.query || "";
                                    if (q.length > 0) {
                                        root.close();
                                        root.queryRequested(q, "save");
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Backspace && searchField.text.length === 0
                                           && root.chips.length > 0) {
                                    root.removeChip(root.chips.length - 1);
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                    // The syntax card, shown or hidden.
                    Text {
                        objectName: "cmd-syntax-toggle"
                        text: "?"
                        color: syntaxCA.hovered || root.syntaxShown ? Theme.text : Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsMd
                        ClickArea {
                            id: syntaxCA
                            label: I18n.t(root.syntaxShown ? "cmd.syntax.hide" : "cmd.syntax.show")
                            onActivated: root.toggleSyntax()
                        }
                    }
                }
            }

            // Results, in groups.
            ListView {
                id: resultsView
                objectName: "cmd-results"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root._rows
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThinScrollBar {}
                topMargin: Theme.spMd
                bottomMargin: Theme.spMd
                Connections {
                    target: root
                    function on_SelectedIdxChanged() {
                        const e = root._matches[root._selectedIdx];
                        if (!e) return;
                        const i = root._rows.indexOf(e);
                        if (i >= 0) resultsView.positionViewAtIndex(i, ListView.Contain);
                    }
                }

                delegate: Item {
                    id: rowItem
                    required property var modelData
                    readonly property bool selected: !rowItem.modelData.header && rowItem.modelData._idx === root._selectedIdx
                    width: ListView.view.width
                    height: rowItem.modelData.header ? headText.implicitHeight + Theme.spLg
                          : Math.max(Theme.px(34), rowLabel.implicitHeight + 2 * Theme.spSm)

                    Text {
                        id: headText
                        visible: rowItem.modelData.header === true
                        anchors.left: parent.left; anchors.leftMargin: Theme.sp2xl
                        anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.spXs
                        text: rowItem.modelData.header ? rowItem.modelData.label : ""
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsXs
                    }
                    Rectangle {
                        visible: !rowItem.modelData.header
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                        radius: Theme.radiusSm
                        color: rowItem.selected ? Theme.rowHighlight : "transparent"
                        // The selected row's marker: 3:1 against the panel on
                        // every theme.
                        Rectangle {
                            objectName: "palette-row-marker"
                            visible: rowItem.selected
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
                            Text {
                                id: rowLabel
                                Layout.fillWidth: true
                                text: rowItem.modelData.label || ""
                                textFormat: Text.PlainText
                                color: rowItem.modelData.off || rowItem.modelData.archived ? Theme.textDim : Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsMd
                                font.weight: rowItem.modelData.kind === "task" ? Theme.fwTitle : Theme.fwBody
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: text.length > 0
                                Layout.maximumWidth: Theme.px(260)
                                text: rowItem.modelData.note || (rowItem.modelData._snippet ? "" : (rowItem.modelData.sub || ""))
                                color: Theme.textDim
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsXs
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: !!rowItem.modelData.kind && rowItem.modelData.kind !== "task"
                                         && rowItem.modelData.kind !== "action" && rowItem.modelData.kind !== "command"
                                         && rowItem.modelData.kind !== "more" && rowItem.modelData.kind !== "create"
                                text: (rowItem.modelData._recent ? "↺ " : "") + root._kindLabel(rowItem.modelData.kind)
                                color: Theme.textDim
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsXs
                            }
                            KeyHint {
                                always: true
                                keys: rowItem.modelData.keys
                                      || (rowItem.selected && rowItem.modelData.kind === "task" ? AppController.keyText("Return") : "")
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: if (!rowItem.modelData.off) root._selectedIdx = rowItem.modelData._idx
                            onClicked: {
                                root._selectedIdx = rowItem.modelData._idx;
                                root.activateSelected();
                            }
                        }
                    }
                }

                // Empty state: nothing typed yet, or nothing found.
                EmptyState {
                    objectName: "palette-empty"
                    visible: root._matches.length === 0
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 2 * Theme.sp3xl, Theme.px(380))
                    compact: searchField.text.length === 0
                    title: searchField.text.length === 0 ? I18n.t("palette.empty.start") : I18n.t("palette.empty.miss")
                    line: searchField.text.length === 0 ? "" : I18n.t("palette.empty.missHint")
                }
            }

            // Hints: the keys of the line, and what Tab would make of the word
            // being typed.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(30)
                color: Theme.panel2
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: Theme.border }
                Text {
                    objectName: "cmd-hints"
                    anchors.left: parent.left; anchors.leftMargin: Theme.sp2xl
                    anchors.right: parent.right; anchors.rightMargin: Theme.sp2xl
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property var pending: root._parse.tokens
                        ? root._parse.tokens.filter(t => !root.chips.some(c => c.clause === t.clause)) : []
                    text: pending.length > 0
                          ? I18n.t("cmd.tabHint").arg(pending.map(t => root.chipKey(t) + " " + root.chipValue(t)).join(" · "))
                          : I18n.t("cmd.kbdHint")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                    elide: Text.ElideRight
                }
            }
        }

        // The language, beside the results (hideable).
        Rectangle {
            objectName: "cmd-syntax"
            visible: root.syntaxShown
            Layout.preferredWidth: Theme.px(300)
            Layout.fillHeight: true
            color: Theme.panel2
            radius: Theme.radiusXl
            Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.sp2xl
                spacing: Theme.spMd
                Text {
                    text: I18n.t("cmd.syntax.title")
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
                    font.weight: Theme.fwTitle
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("cmd.syntax.intro")
                    wrapMode: Text.WordWrap
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
                Repeater {
                    model: ["priority", "when", "due", "label", "status", "ticket", "commands"]
                    delegate: RowLayout {
                        id: syn
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: Theme.spLg
                        Text {
                            Layout.preferredWidth: Theme.px(120)
                            text: I18n.t("cmd.syntax." + syn.modelData + ".example")
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("cmd.syntax." + syn.modelData)
                            wrapMode: Text.WordWrap
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsSm
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
