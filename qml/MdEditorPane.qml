import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// A markdown document, edited and previewed.
//
// NotesView grew one of these over a thousand lines, wired directly to
// `notesState`. Docs pages want the same thing pointed at a different document,
// so this is the part that does not care which: hand it a page id, it loads the
// body, debounces the writes and flushes on the way out.
//
// The debounce is the reason `flush()` is public. A caller that switches
// documents has to call it first, or the last keystrokes are still only in the
// text field and switching drops them — the failure NotesView already guards
// against on destruction, and the one every new caller rediscovers.
Item {
    id: root

    // The doc page being edited. Empty shows the placeholder.
    property string pageId: ""
    property string emptyText: ""

    // "edit" or "split".
    property string mode: "split"

    property bool _loading: false
    property bool _dirty: false
    // The page the text field actually holds. Writes go here, never to
    // `pageId`: by the time pageId has changed it names the page being opened,
    // and writing the old text there is how "+" used to overwrite a new page
    // with the previous one's unsaved draft — and lose it from the old page.
    property string _loadedId: ""

    function load() {
        root._loading = true;
        root._loadedId = root.pageId;
        area.text = root.pageId.length > 0 ? AppController.docPageBody(root.pageId) : "";
        root._loading = false;
        root._dirty = false;
    }

    // Write now rather than in 250 ms. Called before anything that changes
    // which document is open, and on destruction.
    function flush() {
        saveTimer.stop();
        if (!root._dirty || root._loadedId.length === 0) return;
        AppController.setDocPageBody(root._loadedId, area.text);
        root._dirty = false;
    }

    // Every way the open page changes — a click, "+", a new subpage, a delete —
    // goes through here, so the flush does not depend on each caller
    // remembering to do it first.
    onPageIdChanged: {
        root.flush();
        // Remote images were allowed for the page they were allowed on only.
        previewDoc.allowRemoteImages = false;
        root.load();
    }
    Component.onCompleted: root.load()
    Component.onDestruction: root.flush()

    Connections {
        target: Qt.application
        function onAboutToQuit() {
            root.flush();
            AppController.flushSave();
        }
    }
    // An export or a search is about to read the whole profile.
    Connections {
        target: AppController
        function onFlushEditorsRequested() { root.flush() }
    }

    // The body may change under us — an undo, a profile switch, an import.
    property int _titleRev: 0
    Connections {
        target: AppController.docPages
        function onDataChanged() {
            root._titleRev++;
            if (root._dirty || root.pageId.length === 0) return;
            const fresh = AppController.docPageBody(root.pageId);
            if (fresh !== area.text) root.load();
        }
        function onRowsInserted() { root._titleRev++ }
        function onRowsRemoved() { root._titleRev++ }
        function onModelReset() { root._titleRev++; root.load() }
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: {
            if (root._loadedId.length === 0) return;
            AppController.setDocPageBody(root._loadedId, area.text);
            root._dirty = false;
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    EmptyState {
        objectName: "md-editor-empty"
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.sp3xl, 420)
        visible: root.pageId.length === 0
        icon: "heap-08-docs"
        title: root.emptyText
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.pageId.length > 0
        spacing: 0

        // Head: the title of the page, and how it is being shown.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            color: Theme.panel
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: Theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.spLg
                spacing: Theme.spMd
                Text {
                    objectName: "docpage-title"
                    // Reads `_titleRev` so a rename re-evaluates it: m.data()
                    // is a call, not a binding QML can watch, and the head
                    // kept the old title after every rename.
                    text: {
                        const _r = root._titleRev;
                        const m = AppController.docPages;
                        const r = m.roleOf("title");
                        const at = m.indexOfId(root.pageId);
                        return (at >= 0 && r >= 0) ? String(m.data(m.index(at, 0), r)) : "";
                    }
                    color: Theme.text
                    font.pixelSize: Theme.fsMd
                    font.weight: Theme.fwTitle
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    // Words, not characters: the number anybody writing a
                    // document actually wants.
                    text: I18n.t("docs.words").arg(area.text.trim().length === 0
                                                   ? 0
                                                   : area.text.trim().split(/\s+/).length)
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsXs
                }
                Repeater {
                    model: ["edit", "split"]
                    delegate: Rectangle {
                        id: modeChip
                        required property var modelData
                        objectName: "docpage-mode-" + modelData
                        implicitWidth: 44; implicitHeight: 22
                        radius: Theme.radiusSm
                        color: root.mode === modelData ? Theme.withAlpha(Theme.accent, 0.18)
                             : modeMA.hovered ? Theme.panel3 : "transparent"
                        border.color: root.mode === modelData ? Theme.accent : Theme.border
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: I18n.t("docs.mode." + modelData)
                            color: root.mode === modelData ? Theme.text : Theme.textDim
                            font.pixelSize: Theme.fsXs
                        }
                        ClickArea {
                            id: modeMA
                            label: I18n.t("docs.mode." + modeChip.modelData)
                            role: Accessible.RadioButton
                            checkable: true
                            checked: root.mode === modeChip.modelData
                            showTip: false
                            onActivated: root.mode = modeChip.modelData
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            QQC.ScrollView {
                // Equal preferred widths and both filling: that is what splits
                // a RowLayout down the middle. Sizing one half to parent.width
                // instead leaves the other at zero, which looks exactly like
                // the preview failing to render.
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                clip: true

                QQC.TextArea {
                    id: area
                    QQC.ContextMenu.menu: TextEditMenu { editor: area }
                    objectName: "docpage-text"
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsMd
                    leftPadding: Theme.sp2xl; rightPadding: Theme.sp2xl; topPadding: Theme.spXl
                    background: Rectangle { color: Theme.bg }
                    onTextChanged: {
                        if (root._loading) return;
                        root._dirty = true;
                        saveTimer.restart();
                    }
                    Keys.priority: Keys.BeforeItem
                    // The same keyboard as the notes editor: list
                    // continuation, Tab, the formatting keys — and Ctrl+K is a
                    // link here, not the command palette.
                    Keys.onShortcutOverride: (event) => {
                        if (mdEditor.claimsShortcut(event.key, event.modifiers)) event.accepted = true;
                    }
                    Keys.onPressed: (event) => {
                        // Nothing left to undo in the text: the key belongs to
                        // the app's undo (a deleted page, a move).
                        if (event.matches(StandardKey.Undo) && !area.canUndo && AppController.hasPendingUndo) {
                            AppController.undo();
                            event.accepted = true;
                            return;
                        }
                        if (event.matches(StandardKey.Redo) && !area.canRedo && AppController.canRedo) {
                            AppController.redo();
                            event.accepted = true;
                            return;
                        }
                        // Tab indents, so the way out is Esc (back to what
                        // came before — the page tree) or Ctrl+Tab / F6,
                        // with Shift for backwards (SHELL-18).
                        const mods = event.modifiers & ~Qt.KeypadModifier;
                        const leaveBack = event.key === Qt.Key_Escape && mods === Qt.NoModifier;
                        const ctrlTab = (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                                        && (mods & Qt.ControlModifier);
                        const f6 = event.key === Qt.Key_F6 && (mods & ~Qt.ShiftModifier) === Qt.NoModifier;
                        if (leaveBack || ctrlTab || f6) {
                            const back = leaveBack || event.key === Qt.Key_Backtab || (mods & Qt.ShiftModifier);
                            const next = area.nextItemInFocusChain(!back);
                            if (next) next.forceActiveFocus(back ? Qt.BacktabFocusReason : Qt.TabFocusReason);
                            event.accepted = true;
                            return;
                        }
                        mdEditor.setSelection(area.selectionStart, area.selectionEnd);
                        if (mdEditor.handleKey(event.key, event.modifiers)) event.accepted = true;
                    }
                }
            }

            Rectangle {
                visible: root.mode === "split"
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: Theme.border
            }

            MdView {
                id: preview
                objectName: "docpage-preview"
                visible: root.mode === "split"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                document: previewDoc
                // Checkboxes write through the editor, so a tick is one undo
                // step there; links follow the same rules as in notes.
                editorDocument: area.textDocument
                onSourceRequested: (line) => {
                    area.forceActiveFocus();
                    area.cursorPosition = previewDoc.positionForLine(line);
                }
                onInternalLinkActivated: (kind, target) => root.internalLinkActivated(kind, target)
            }
        }
    }

    // A [[link]], #TICKET or @person clicked in the preview. The page does not
    // know what a note or a task is; the view it sits in does.
    signal internalLinkActivated(string kind, string target)

    MarkdownEditorController {
        id: mdEditor
        target: area.textDocument
        cursorPosition: area.cursorPosition
        selectionStart: area.selectionStart
        selectionEnd: area.selectionEnd
        onSelectionRequested: (start, end) => {
            if (start === end) area.cursorPosition = start;
            else area.select(start, end);
        }
    }

    MdDocument {
        id: previewDoc
        // The preview follows the text field rather than the stored body, so it
        // keeps up while typing instead of lagging by the debounce.
        text: area.text
        allowRemoteImages: false
        // Relative image paths resolve here; absolute local paths work anywhere.
        imageBaseDir: AppController.dataDir + "/attachments"
        palette: Theme.mdPalette
        ticketTitles: AppController.taskTitles
    }
}
