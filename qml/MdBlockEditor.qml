pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as QQC
import TodoCpp

// A markdown document edited where it is drawn (heap 2, APP-265/269): the
// whole document is rendered (MdView), and the block under the caret turns
// into a field holding exactly its source lines. Leave the block and it is
// drawn again; ↑ on its first line / ↓ on its last go to the block next to
// it. No Text / Preview tabs.
//
// One source of truth: a hidden text area holds the whole source, so a
// checkbox click, a block's edit and Ctrl+Z all go through one undo stack.
Item {
    id: root

    // The source. Setting it from outside replaces the document (a different
    // task, a pull from the tracker) and drops the undo history.
    property string text: ""
    property string placeholder: ""
    property bool readOnly: false
    // How [[targets]] read (APP-269): AppController.wikiTargets(text).
    property var wikiTargets: ({})
    // The edited source, as each edit is taken in.
    signal edited(string text)
    // Esc with no block open: the caller goes back.
    signal escaped()
    signal internalLinkActivated(string kind, string target)

    readonly property bool editing: view.editFirst >= 0
    readonly property alias document: doc
    readonly property alias source: src
    readonly property alias editor: field

    property bool _loading: false
    onTextChanged: {
        if (root.text === src.text) return;
        root._leave(false);
        root._loading = true;
        src.text = root.text;
        root._loading = false;
    }
    Component.onCompleted: { root._loading = true; src.text = root.text; root._loading = false; }

    // Take what is in the open block now (before a save, a switch).
    function flush() { root._commit(); }
    // The caret into the document: the first block, or a new one if empty.
    function focusEditor() {
        if (root.editing) { field.forceActiveFocus(); return; }
        root.editLine(0, false);
    }

    // ── source helpers ──
    function _lineStart(t, line) {
        let pos = 0;
        for (let i = 0; i < line; i++) {
            const n = t.indexOf("\n", pos);
            if (n < 0) return t.length;
            pos = n + 1;
        }
        return pos;
    }
    function _lineEnd(t, line) {
        const s = root._lineStart(t, line);
        const n = t.indexOf("\n", s);
        return n < 0 ? t.length : n;
    }
    function _lineCount(t) { return t.length === 0 ? 1 : t.split("\n").length; }

    // Open the block that holds `line` for editing; the caret at its end, or
    // at its start with `atStart`.
    function editLine(line, atStart) {
        if (root.readOnly) return;
        root._commit();
        const t = src.text;
        const last = Math.max(0, root._lineCount(t) - 1);
        line = Math.max(0, Math.min(line, last));
        const row = doc.rowForLine(line);
        let first = line, lastLine = line;
        if (row >= 0) {
            first = Math.max(0, doc.firstLineOfRow(row));
            lastLine = Math.max(first, doc.lastLineOfRow(row));
        }
        // Not the blank lines after the block: they part it from the next.
        while (lastLine > first && t.substring(root._lineStart(t, lastLine), root._lineEnd(t, lastLine)).trim().length === 0)
            lastLine--;
        view.editRow = row;
        view.editFirst = first;
        view.editLast = lastLine;
        root._fieldLoading = true;
        field.text = t.substring(root._lineStart(t, first), root._lineEnd(t, lastLine));
        root._fieldLoading = false;
        field.cursorPosition = atStart ? 0 : field.length;
        field.forceActiveFocus();
        Qt.callLater(root._reveal);
    }
    function editRowAt(row, atStart) {
        if (row < 0 || row >= view.count) return false;
        root.editLine(doc.firstLineOfRow(row), atStart);
        return true;
    }
    // Close the open block; with `commit`, take its text in first.
    function _leave(commit) {
        if (!root.editing) return;
        if (commit) root._commit();
        commitTimer.stop();
        view.editFirst = -1;
        view.editLast = -1;
        view.editRow = -1;
    }
    property bool _fieldLoading: false
    // The open block's text into the source, replacing its lines.
    function _commit() {
        commitTimer.stop();
        if (!root.editing) return;
        const t = src.text;
        const s = root._lineStart(t, view.editFirst);
        const e = root._lineEnd(t, view.editLast);
        if (t.substring(s, e) !== field.text) {
            src.remove(s, e);
            src.insert(s, field.text);
        }
        view.editLast = view.editFirst + root._lineCount(field.text) - 1;
        doc.flush();
        view.editRow = doc.rowForLine(view.editFirst);
    }
    function _reveal() {
        const y = field._contentY;
        if (y < view.contentY) view.contentY = Math.max(0, y - Theme.spLg);
        else if (y + field.height > view.contentY + view.height)
            view.contentY = y + field.height - view.height + Theme.spLg;
    }
    // A new block after the last one (a click below the text).
    function appendBlock() {
        if (root.readOnly) return;
        root._commit();
        root._leave(false);
        const t = src.text;
        if (t.length > 0 && t.trim().length > 0) {
            const tail = t.endsWith("\n\n") ? "" : (t.endsWith("\n") ? "\n" : "\n\n");
            src.insert(t.length, tail);
        }
        doc.flush();
        root.editLine(root._lineCount(src.text) - 1, false);
    }

    Timer {
        id: commitTimer
        interval: 400
        onTriggered: root._commit()
    }

    // The whole source; its undo stack is the document's.
    QQC.TextArea {
        id: src
        visible: false
        textFormat: TextEdit.PlainText
        onTextChanged: if (!root._loading) root.edited(src.text)
    }

    MdDocument {
        id: doc
        text: src.text
        allowRemoteImages: false
        imageBaseDir: AppController.dataDir + "/attachments"
        palette: Theme.mdPalette
        ticketTitles: AppController.taskTitles
        wikiTargets: root.wikiTargets
    }

    MdView {
        id: view
        objectName: "md-block-view"
        anchors.fill: parent
        document: doc
        editorDocument: src.textDocument
        clickToEdit: !root.readOnly
        editHeight: field.implicitHeight
        onRowClicked: (row, line) => root.editLine(line, false)
        onSourceRequested: (line) => root.editLine(line, false)
        onInternalLinkActivated: (kind, target) => root.internalLinkActivated(kind, target)

        // Room to click below the last block: a new block there.
        footer: Item {
            width: view.width
            height: Theme.px(160)
            Text {
                objectName: "md-block-placeholder"
                visible: src.text.trim().length === 0 && !root.editing
                x: view.sideMargin
                y: Theme.spSm
                width: view.width - 2 * view.sideMargin
                text: root.placeholder
                wrapMode: Text.WordWrap
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
            }
            TapHandler {
                enabled: !root.readOnly
                onTapped: root.appendBlock()
            }
        }

        // The open block's source, laid where the block was drawn.
        QQC.TextArea {
            id: field
            objectName: "md-block-field"
            // Over the view, not inside it: inside, the ListView's focus
            // scope handed the keyboard to its current row on every relayout.
            parent: root
            z: 2
            visible: root.editing
            readonly property Item _host: view.editRow >= 0 ? view.itemAtIndex(view.editRow) : null
            readonly property real _contentY: _host ? _host.y : (view.count > 0 && view.itemAtIndex(view.count - 1)
                                  ? view.itemAtIndex(view.count - 1).y + view.itemAtIndex(view.count - 1).height : 0)
            x: view.x + view.sideMargin - leftPadding
            y: view.y + view.contentItem.y + _contentY
            width: view.width - 2 * view.sideMargin + leftPadding + rightPadding
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            textFormat: TextEdit.PlainText
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            topPadding: Theme.spXs
            bottomPadding: Theme.spXs
            leftPadding: Theme.spSm
            rightPadding: Theme.spSm
            background: Rectangle {
                radius: Theme.radiusSm
                color: Theme.panel
                border.color: Theme.border
                border.width: 1
            }
            QQC.ContextMenu.menu: TextEditMenu { editor: field }
            onTextChanged: if (!root._fieldLoading && root.editing) commitTimer.restart()
            onActiveFocusChanged: if (!activeFocus && !slashMenu.opened) root._leave(true)

            Keys.priority: Keys.BeforeItem
            Keys.onShortcutOverride: (event) => {
                if (mdEditor.claimsShortcut(event.key, event.modifiers)) event.accepted = true;
            }
            Keys.onPressed: (event) => {
                const mods = event.modifiers & ~Qt.KeypadModifier;
                // Ctrl+Z past what the block itself can undo: the document's.
                if (event.matches(StandardKey.Undo) && !field.canUndo) {
                    root._commit();
                    if (src.canUndo) {
                        const line = view.editFirst;
                        root._leave(false);
                        src.undo();
                        doc.flush();
                        root.editLine(line, false);
                    }
                    event.accepted = true;
                    return;
                }
                if (event.matches(StandardKey.Redo) && !field.canRedo) {
                    root._commit();
                    if (src.canRedo) {
                        const line = view.editFirst;
                        root._leave(false);
                        src.redo();
                        doc.flush();
                        root.editLine(line, false);
                    }
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Escape && mods === Qt.NoModifier) {
                    // First Esc leaves the block, the second the document.
                    root._leave(true);
                    view.forceActiveFocus();
                    event.accepted = true;
                    return;
                }
                const firstLine = field.text.lastIndexOf("\n", field.cursorPosition - 1) < 0;
                const lastLine = field.text.indexOf("\n", field.cursorPosition) < 0;
                if (event.key === Qt.Key_Up && mods === Qt.NoModifier && firstLine) {
                    const prev = view.editFirst - 1;
                    if (prev >= 0) {
                        root._commit();
                        let line = prev;
                        // Over blank lines between blocks.
                        while (line > 0 && src.text.substring(root._lineStart(src.text, line), root._lineEnd(src.text, line)).trim().length === 0) line--;
                        root.editLine(line, false);
                    }
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Down && mods === Qt.NoModifier && lastLine) {
                    root._commit();
                    const total = root._lineCount(src.text);
                    let line = view.editLast + 1;
                    while (line < total - 1 && src.text.substring(root._lineStart(src.text, line), root._lineEnd(src.text, line)).trim().length === 0) line++;
                    if (line < total) root.editLine(line, true);
                    event.accepted = true;
                    return;
                }
                // "/" at the start of a line: insert a checklist, code, a link.
                if (event.text === "/" && (field.cursorPosition === 0
                        || field.text.charAt(field.cursorPosition - 1) === "\n")) {
                    slashMenu.popup(field, field.cursorRectangle.x, field.cursorRectangle.y + field.cursorRectangle.height);
                    event.accepted = true;
                    return;
                }
                mdEditor.setSelection(field.selectionStart, field.selectionEnd);
                if (mdEditor.handleKey(event.key, event.modifiers)) event.accepted = true;
            }
        }
    }
    // Esc on the drawn document: back to whoever opened it.
    Keys.onEscapePressed: root.escaped()

    MarkdownEditorController {
        id: mdEditor
        target: field.textDocument
        cursorPosition: field.cursorPosition
        selectionStart: field.selectionStart
        selectionEnd: field.selectionEnd
        onSelectionRequested: (start, end) => {
            if (start === end) field.cursorPosition = start;
            else field.select(start, end);
        }
    }

    // What "/" inserts (sheet X-Oth-Knowledge).
    AppMenu {
        id: slashMenu
        objectName: "md-slash-menu"
        function put(s, back) {
            const at = field.cursorPosition;
            field.insert(at, s);
            field.cursorPosition = at + s.length - (back || 0);
            field.forceActiveFocus();
        }
        AppMenuItem { objectName: "md-slash-check"; text: I18n.t("md.slash.checklist"); onTriggered: slashMenu.put("- [ ] ") }
        AppMenuItem { objectName: "md-slash-code"; text: I18n.t("md.slash.code"); onTriggered: slashMenu.put("```\n\n```", 4) }
        AppMenuItem { objectName: "md-slash-task"; text: I18n.t("md.slash.task"); onTriggered: slashMenu.put("[[]]", 2) }
        AppMenuItem { objectName: "md-slash-heading"; text: I18n.t("md.slash.heading"); onTriggered: slashMenu.put("## ") }
        AppMenuItem { objectName: "md-slash-table"; text: I18n.t("md.slash.table"); onTriggered: slashMenu.put("| | |\n|---|---|\n| | |\n", 0) }
        AppMenuItem { objectName: "md-slash-quote"; text: I18n.t("md.slash.quote"); onTriggered: slashMenu.put("> ") }
        AppMenuItem { objectName: "md-slash-slash"; text: I18n.t("md.slash.literal"); onTriggered: slashMenu.put("/") }
    }
}
