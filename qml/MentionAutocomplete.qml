import QtQuick
import QtQuick.Controls
import TodoCpp
import "Mention.js" as Mention

// Reusable autocomplete dropdown that floats above a target
// TextField/TextArea at the caret. Supports two triggers:
//
//   @<token>  → AppController.matchPeople (id, a login made of the name —
//               "r.losev", "roman.losev" — or the name's words, either
//               script; "@roman losev" may carry one space)
//   #<token>  → AppController.tasks   (id + title, prefix/substring match)
//
// The owner wires it into the target's onTextChanged /
// onCursorPositionChanged hooks (→ refresh()) and routes keyboard
// navigation through moveSelection() / accept() / dismiss().
//
// Inserted format always uses the canonical id ("@<id> " or "#<id> ") —
// stable across renames and matches MdHighlighter's mention and
// ticket rules.
Popup {
    id: ac

    property Item target: null
    property int maxRows: 8
    // Which trigger sources to enable. Disable a trigger by setting the
    // corresponding flag to false from the owner.
    property bool enablePeople: true
    property bool enableTickets: true
    // Insert a person as @Their_Name rather than @their-id (for note text).
    property bool insertNames: false

    property var _suggestions: []
    property int _selectedIdx: 0
    property string _trigger: ""  // "@" or "#" while a suggestion list is live
    readonly property bool isOpen: visible && _suggestions.length > 0
    // True once the arrows have moved the highlight since the list opened —
    // the owner's cue that Enter means "take this one" rather than "submit".
    property bool navigated: false

    readonly property var _handleCharRe: /[A-Za-zА-Яа-яЁё0-9_.\-]/
    // The longest "@first last" query that still counts as one mention.
    readonly property int _maxPeopleQuery: 48

    padding: 0
    modal: false
    focus: false
    closePolicy: Popup.NoAutoClose
    parent: Overlay.overlay
    visible: _suggestions.length > 0
    width: Theme.px(260)
    height: Math.min(Math.max(_suggestions.length, 1), maxRows + 1) * Theme.px(30) + 2 * Theme.spXs

    function _text() {
        return target ? (target.text || "") : "";
    }

    function _caret() {
        return target ? target.cursorPosition : -1;
    }

    // Walks back from the caret across handle chars and returns the active
    // trigger range, or null if the caret isn't inside one. The trigger
    // char ("@" or "#") and the entered prefix are returned so the caller
    // (refresh / accept) can decide which source to query.
    function _currentTriggerRange() {
        const text = _text();
        const caret = _caret();
        if (caret < 0) return null;
        let start = caret;
        while (start > 0 && _handleCharRe.test(text.charAt(start - 1))) --start;
        // "@roman losev": a person's query may hold one space, once a word
        // follows it — a bare "@roman " (and the "@id " accept() leaves
        // behind) still ends the mention. refresh() closes the list again
        // as soon as the two words stop matching anyone.
        if (enablePeople && start < caret && start >= 2 && text.charAt(start - 1) === " ") {
            let first = start - 1;
            while (first > 0 && _handleCharRe.test(text.charAt(first - 1))) --first;
            if (first < start - 1 && first > 0 && text.charAt(first - 1) === "@"
                    && caret - first <= _maxPeopleQuery)
                start = first;
        }
        if (start === 0) return null;
        const trig = text.charAt(start - 1);
        if (trig !== "@" && trig !== "#") return null;
        if (trig === "@" && !enablePeople) return null;
        if (trig === "#" && !enableTickets) return null;
        // Must be at start-of-text or after whitespace/punctuation —
        // otherwise we're inside an e-mail or some non-handle token.
        if (start >= 2) {
            const lead = text.charAt(start - 2);
            if (!/\s|[,;(]/.test(lead)) return null;
        }
        return {
            trigger: trig,
            start: start - 1,
            end: caret,
            prefix: text.substring(start, caret)
        };
    }

    // Best match first (heap::text::personMatchRank, shared with the people
    // picker and the palette).
    function _peopleSuggestions(q) {
        const hits = AppController.matchPeople(q, maxRows);
        const out = [];
        for (let i = 0; i < hits.length; ++i)
            out.push({id: String(hits[i].id || ""), name: String(hits[i].name || ""), role: String(hits[i].role || "")});
        // The last row adds the typed word as a person (R2-042, X-Dlg-Small).
        // Not for "@first last": past a space the query is a name being
        // matched, and nobody matching closes the list.
        if (q.length > 0 && q.indexOf(" ") < 0)
            out.push({id: "", name: q, role: "", add: true});
        return out;
    }

    function _ticketSuggestions(q) {
        const out = [];
        const tasks = AppController.tasks;
        for (let i = 0; i < tasks.rowCount(); ++i) {
            const idx = tasks.index(i, 0);
            const id = String(tasks.data(idx, Qt.UserRole + 1) || "");
            const title = String(tasks.data(idx, Qt.UserRole + 2) || "");
            if (q.length === 0
                || id.toLowerCase().indexOf(q) >= 0
                || title.toLowerCase().indexOf(q) >= 0) {
                out.push({id: id, name: title});
            }
            if (out.length >= maxRows) break;
        }
        return out;
    }

    function refresh() {
        if (!target) {
            _suggestions = [];
            return;
        }
        const r = _currentTriggerRange();
        if (!r) {
            _suggestions = [];
            return;
        }
        const q = (r.prefix || "").toLowerCase();
        _trigger = r.trigger;
        _suggestions = (r.trigger === "@") ? _peopleSuggestions(q)
            : _ticketSuggestions(q);
        _selectedIdx = 0;
        navigated = false;
        if (_suggestions.length > 0) _reposition();
    }

    function accept(clicked) {
        if (!isOpen || !target) return false;
        const r = _currentTriggerRange();
        if (!r) return false;
        const pick = _suggestions[_selectedIdx];
        if (pick.add) {
            // Enter or Tab on an untouched list never makes a person; the
            // arrows or a click do.
            if (!navigated && !clicked) return false;
            const name = r.prefix.charAt(0).toUpperCase() + r.prefix.slice(1);
            const draft = AppController.newPersonDraft();
            draft.name = name;
            draft.id = AppController.suggestPersonId(name);
            draft.state = "idle";
            if (!AppController.savePerson(draft)) return false;
            pick.id = draft.id;
            pick.name = name;
        }
        // Notes write a person as @Their_Name (NotesView does the same), task
        // text as the id the task parser matches.
        const token = (insertNames && r.trigger === "@") ? String(pick.name || pick.id).replace(/\s+/g, "_") : pick.id;
        const insert = r.trigger + token + " ";
        // Edit in place (remove + insert) rather than reassigning target.text:
        // a whole-text assignment resets the caret to 0 on a TextArea/TextField,
        // dropping the user back to the start of the document. (HEAP-65)
        target.remove(r.start, r.end);
        target.insert(r.start, insert);
        target.cursorPosition = r.start + insert.length;
        _suggestions = [];
        _trigger = "";
        return true;
    }

    function moveSelection(delta) {
        if (!isOpen) return;
        _selectedIdx = Math.max(0, Math.min(_suggestions.length - 1,
            _selectedIdx + delta));
        navigated = true;
    }

    function dismiss() {
        _suggestions = [];
        _trigger = "";
    }

    function _reposition() {
        if (!target || !visible) return;
        let originX = 0;
        let originY = target.height || 24;
        const cr = target.cursorRectangle;
        if (cr && cr.height > 0) {
            originX = cr.x;
            originY = cr.y + cr.height;
        }
        const p = target.mapToItem(Overlay.overlay, originX, originY);
        x = p.x;
        y = p.y + 2;
    }

    onVisibleChanged: if (visible) _reposition()

    background: PopupSurface {}

    contentItem: ListView {
        clip: true
        model: ac._suggestions
        interactive: false
        topMargin: Theme.spXs
        delegate: Rectangle {
            id: acRow
            required property var modelData
            required property int index
            readonly property bool on: index === ac._selectedIdx
            x: Theme.spXs
            width: ListView.view.width - 2 * Theme.spXs
            height: Theme.px(30)
            radius: Theme.radiusSm
            color: acRow.on ? Theme.panel3 : (rowMA.containsMouse ? Theme.withAlpha(Theme.text, 0.04) : "transparent")
            // A person: the name, the role on the right (sheet X-Dlg-Small).
            // A task: its id and title. The add row: one dim line.
            Text {
                id: acName
                anchors.left: parent.left
                anchors.leftMargin: Theme.spMd
                anchors.right: acRole.left
                anchors.rightMargin: Theme.spMd
                anchors.verticalCenter: parent.verticalCenter
                text: acRow.modelData.add ? I18n.t("mention.addPerson").arg(acRow.modelData.name)
                    : ac._trigger === "#" ? acRow.modelData.id + " · " + acRow.modelData.name
                    : acRow.modelData.name
                color: acRow.modelData.add ? Theme.textMuted : Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                elide: Text.ElideRight
            }
            Text {
                id: acRole
                anchors.right: parent.right
                anchors.rightMargin: Theme.spMd
                anchors.verticalCenter: parent.verticalCenter
                text: acRow.modelData.role || ""
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
            MouseArea {
                id: rowMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    ac._selectedIdx = acRow.index;
                    ac.accept(true);
                    if (ac.target && ac.target.forceActiveFocus) {
                        ac.target.forceActiveFocus();
                    }
                }
            }
        }
    }
}
