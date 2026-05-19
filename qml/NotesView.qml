// Notes view — single per-profile markdown canvas with @mention / #ticket
// autocomplete. Mirrors the DocsView layout (header bar + scrollable body)
// and the docsState round-trip pattern.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import TodoCpp

Item {
    id: root

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
        const txt = editor.text;
        editor.text = txt.substring(0, acTriggerPos) + insert + txt.substring(pos);
        editor.cursorPosition = acTriggerPos + insert.length;
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
                            const parts = [lines + " строк", mentions + " @mentions", tickets + " #tickets"];
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
                    visible: editor.text.length > 0
                    text: "Markdown · @ — контакты · # — тикеты"
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
            }
        }

        // ── Editor body ───────────────────────────────────────────
        Flickable {
            id: notesScroll
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
                placeholderText: "Начните писать заметку…  (поддерживается markdown, @упоминания и #тикеты)"
                placeholderTextColor: Theme.textDim
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: 13
                background: Item {}
                onTextChanged: { root._scheduleSave(); root._detectAutocomplete(); }
                onCursorPositionChanged: root._detectAutocomplete()
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: (event) => {
                    if (!acPopup.opened || acMatches.length === 0) return;
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
            }
        }
    }

    // ── Markdown highlighter ─────────────────────────────────────
    NotesHighlighter {
        target: editor.textDocument
        palette: ({
            heading: Theme.accentStrong,
            bold:    Theme.text,
            italic:  Theme.text,
            code:    Theme.p2,
            codeBg:  Theme.bg2,
            quote:   Theme.textMuted,
            mention: Theme.mStandup,
            ticket:  Theme.p2,
            link:    Theme.accent,
            list:    Theme.accent
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
    Component.onCompleted: { _loadFromController(); _loadedOnce = true; }
    Connections {
        target: AppController
        function onNotesStateChanged() {
            if (!root._loadedOnce || root._persisting) return;
            root._loadFromController();
            root._hideAutocomplete();
        }
    }
}
