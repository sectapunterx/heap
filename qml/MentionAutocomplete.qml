import QtQuick
import QtQuick.Controls
import TodoCpp
import "Mention.js" as Mention

// Reusable autocomplete dropdown that floats above a target
// TextField/TextArea at the caret. Supports two triggers:
//
//   @<token>  → AppController.people  (id + name, prefix match)
//   #<token>  → AppController.tasks   (id + title, prefix/substring match)
//
// The owner wires it into the target's onTextChanged /
// onCursorPositionChanged hooks (→ refresh()) and routes keyboard
// navigation through moveSelection() / accept() / dismiss().
//
// Inserted format always uses the canonical id ("@<id> " or "#<id> ") —
// stable across renames and matches NotesHighlighter's mention and
// ticket rules.
Popup {
    id: ac

    property Item target: null
    property int maxRows: 8
    // Which trigger sources to enable. Disable a trigger by setting the
    // corresponding flag to false from the owner.
    property bool enablePeople: true
    property bool enableTickets: true

    property var _suggestions: []
    property int _selectedIdx: 0
    property string _trigger: ""  // "@" or "#" while a suggestion list is live
    readonly property bool isOpen: visible && _suggestions.length > 0

    readonly property var _handleCharRe: /[A-Za-zА-Яа-яЁё0-9_.\-]/

    padding: 0
    modal: false
    focus: false
    closePolicy: Popup.NoAutoClose
    parent: Overlay.overlay
    visible: _suggestions.length > 0
    width: 320
    height: Math.min(Math.max(_suggestions.length, 1), maxRows) * 28 + 4

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

    function _peopleSuggestions(q) {
        const out = [];
        const people = AppController.people;
        for (let i = 0; i < people.rowCount(); ++i) {
            const idx = people.index(i, 0);
            const id = String(people.data(idx, Qt.UserRole + 1) || "");
            const name = String(people.data(idx, Qt.UserRole + 2) || "");
            if (q.length === 0
                || id.toLowerCase().indexOf(q) === 0
                || name.toLowerCase().indexOf(q) >= 0) {
                out.push({id: id, name: name});
            }
            if (out.length >= maxRows) break;
        }
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
        if (_suggestions.length > 0) _reposition();
    }

    function accept() {
        if (!isOpen || !target) return false;
        const r = _currentTriggerRange();
        if (!r) return false;
        const pick = _suggestions[_selectedIdx];
        const insert = r.trigger + pick.id + " ";
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

    background: Rectangle {
        radius: 6
        color: Theme.panel2
        border.color: Theme.border
        border.width: 1
    }

    contentItem: ListView {
        clip: true
        model: ac._suggestions
        interactive: false
        delegate: Rectangle {
            required property var modelData
            required property int index
            width: ListView.view.width
            height: 28
            color: index === ac._selectedIdx
                ? Theme.withAlpha(Theme.accent, 0.18)
                : "transparent"
            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                Text {
                    text: ac._trigger + modelData.id
                    color: Theme.accentStrong
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    visible: (modelData.name || "").length > 0
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
                    ac._selectedIdx = index;
                    ac.accept();
                    if (ac.target && ac.target.forceActiveFocus) {
                        ac.target.forceActiveFocus();
                    }
                }
            }
        }
    }
}
