pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp
import "PopupStack.js" as PopupStack

// Quick-capture popup for Notes — triggered by Ctrl+Shift+N.
//
//  • Ctrl+Enter      → submit (append to AppController.notesState)
//  • Enter, Shift+Enter → newline in the editor (APP-209: the same keys
//                      as the task capture)
//  • @<token>        → people autocomplete via MentionAutocomplete
//  • Esc             → close; the text stays as a draft for the next open
//                      (R2-069, sheet X-Oth-Capture: "Esc — черновик
//                      сохранится")
//  • "прикрепить к …" → the entry links the task ([[id]]), so the task's
//                      backlinks list it
Popup {
    id: root
    // Standalone it is the whole window — there is nothing behind it to
    // dim or block, so no scrim.
    modal: !root.standalone
    focus: true
    // We own all key handling (the discard-confirm flow needs to intercept
    // Esc), so the popup must NOT auto-close on Escape.
    closePolicy: Popup.NoAutoClose
    width: Theme.px(600)
    // Standalone: hosted by CaptureWindow — see QuickCapturePopup.
    property bool standalone: false
    anchors.centerIn: root.standalone ? undefined : Overlay.overlay
    x: root.standalone ? Math.round((root.parent.width - root.width) / 2) : 0
    y: root.standalone ? Theme.sp2xl : 0

    Overlay.modal: ModalScrim {}
    // A press beside the popup acts like Esc (APP-126): close when empty,
    // otherwise ask before dropping the text. See PopupStack.js.
    Overlay.onPressed: if (!root.standalone && PopupStack.isTopmost(root, Overlay.overlay) && PopupStack.pressedOutside(root, AppController.lastPressGlobalPos())) root._maybeDiscard()

    // The note just saved, for the owner's confirmation (see QuickCapturePopup).
    signal captured(string title, string body, string taskId)

    readonly property bool hasText: editor.text.trim().length > 0
    // The task the entry is attached to ("" = none): the one the git branch
    // names by default, or one picked from the list.
    property string attachId: ""
    readonly property var attachTask: root.attachId.length ? AppController.taskById(root.attachId) : ({})
    function _taskLabel(t) {
        return t ? (t.externalKey || t.title || "") : "";
    }

    function _submit() {
        const body = editor.text;
        if (body.trim().length === 0) {
            root.close();
            return;
        }
        // Named before the append: with no note open it lands in Inbox, and
        // the confirmation should say so, not "Note saved" somewhere unseen.
        const into = AppController.quickNoteTarget();
        AppController.appendNoteEntry(root.attachId.length ? body.replace(/\s+$/, "") + " [[" + root.attachId + "]]" : body);
        editor.text = "";
        at.dismiss();
        root.close();
        const flat = body.trim().replace(/\s+/g, " ");
        root.captured(I18n.t("quickNote.doneInto").arg(into), flat.length > 140 ? flat.substring(0, 139) + "…" : flat, root.attachId);
    }

    // Esc or a press beside: close, the draft kept (onOpened leaves it).
    function _maybeDiscard() {
        at.dismiss();
        root.close();
    }

    property string _target: ""
    // Opt-in timing (HEAP_PERF_LOG=1 / --perf-log): hotkey or open() to the
    // first frame that shows the popup. Logs only; a no-op otherwise.
    onAboutToShow: AppController.perfMarkShown("capture-notes", contentItem)
    onOpened: {
        root._target = AppController.quickNoteTarget();
        root.attachId = AppController.focusedTaskId || "";
        at.dismiss();
        editor.cursorPosition = editor.length;
        editor.forceActiveFocus();
    }

    background: ModalSurface {}

    padding: Theme.spLg
    contentItem: ColumnLayout {
        spacing: Theme.spSm

        // "lowkey  быстрая заметка → «Входящие»   прикрепить к APP-101 ▾"
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spMd
            Item {
                Layout.preferredWidth: qnLogo.implicitWidth
                Layout.preferredHeight: qnLogo.height
                BrandLogo {
                    id: qnLogo
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "wordmark"
                    theme: Theme.dark ? "dark" : "light"
                    height: Theme.fsSm
                }
            }
            Text {
                objectName: "quick-note-target"
                Layout.fillWidth: true
                // Where it goes, before it goes there.
                text: I18n.t("quickNote.titleInto").arg(root._target)
                elide: Text.ElideRight
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
            Text {
                objectName: "quick-note-attach"
                text: (root.attachId.length ? I18n.t("quickNote.attachTo").arg(root._taskLabel(root.attachTask))
                                            : I18n.t("quickNote.attach")) + " ▾"
                color: attachCA.hovered ? Theme.text : Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                ClickArea {
                    id: attachCA
                    label: I18n.t("quickNote.attach")
                    onActivated: attachMenu.openList()
                }
                AppMenu {
                    id: attachMenu
                    property var tasks: []
                    function openList() {
                        const out = [];
                        const seen = {};
                        const add = (t) => { if (t && t.id && !seen[t.id] && out.length < 8) { seen[t.id] = true; out.push(t); } };
                        if (AppController.focusedTaskId) add(AppController.taskById(AppController.focusedTaskId));
                        if (root.attachId.length) add(root.attachTask);
                        const day = AppController.todayData(new Date(), false);
                        (day.inProgress || []).forEach(t => add(AppController.taskById(t.id)));
                        attachMenu.tasks = out;
                        attachMenu.popup();
                    }
                    Instantiator {
                        model: attachMenu.tasks
                        delegate: AppMenuItem {
                            id: attachRow
                            required property var modelData
                            text: (attachRow.modelData.externalKey ? attachRow.modelData.externalKey + " · " : "") + (attachRow.modelData.title || "")
                            marked: attachRow.modelData.id === root.attachId
                            onTriggered: { root.attachId = attachRow.modelData.id; editor.forceActiveFocus(); }
                        }
                        onObjectAdded: (index, object) => attachMenu.insertItem(index, object)
                        onObjectRemoved: (index, object) => attachMenu.removeItem(object)
                    }
                    AppMenuSeparator { visible: attachMenu.tasks.length > 0 }
                    AppMenuItem {
                        objectName: "quick-note-attach-none"
                        text: I18n.t("quickNote.attachNone")
                        marked: root.attachId.length === 0
                        onTriggered: { root.attachId = ""; editor.forceActiveFocus(); }
                    }
                }
            }
        }

        ScrollView {
            id: editorScroll
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(Theme.px(90), Math.min(Theme.px(240), editor.implicitHeight))
            clip: true

            TextArea {
                id: editor
                ContextMenu.menu: TextEditMenu { editor: editor }
                objectName: "quicknote-editor"
                wrapMode: TextEdit.Wrap
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                color: Theme.text
                placeholderText: I18n.t("quickNote.placeholder")
                placeholderTextColor: Theme.textDim
                selectByMouse: true
                leftPadding: 0
                rightPadding: 0
                background: Item {}

                onTextChanged: at.refresh()
                onCursorPositionChanged: at.refresh()

                Keys.onPressed: (e) => {
                    // ── Mention-dropdown navigation has top priority ──
                    if (at.isOpen) {
                        if (e.key === Qt.Key_Down) {
                            at.moveSelection(+1);
                            e.accepted = true;
                            return;
                        }
                        if (e.key === Qt.Key_Up) {
                            at.moveSelection(-1);
                            e.accepted = true;
                            return;
                        }
                        if (e.key === Qt.Key_Tab) {
                            if (at.accept()) {
                                e.accepted = true;
                                return;
                            }
                        }
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                            && !(e.modifiers & (Qt.ShiftModifier | Qt.ControlModifier))) {
                            if (at.accept()) {
                                e.accepted = true;
                                return;
                            }
                        }
                        if (e.key === Qt.Key_Escape) {
                            at.dismiss();
                            e.accepted = true;
                            return;
                        }
                    }

                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        e.accepted = true;
                        // Ctrl+Enter → save the note (APP-209).
                        if (e.modifiers & Qt.ControlModifier) {
                            at.dismiss();
                            root._submit();
                            return;
                        }
                        // Enter and Shift+Enter → a plain "\n" (Shift+Enter
                        // in a text area is otherwise a Unicode line separator).
                        if (editor.selectedText.length > 0)
                            editor.remove(editor.selectionStart, editor.selectionEnd);
                        editor.insert(editor.cursorPosition, "\n");
                        return;
                    }

                    // Esc → close, the draft kept.
                    if (e.key === Qt.Key_Escape) {
                        root._maybeDiscard();
                        e.accepted = true;
                        return;
                    }
                }
            }
        }

        // The keys, no buttons (sheet X-Oth-Capture).
        Text {
            objectName: "quick-note-hint"
            Layout.fillWidth: true
            text: I18n.t("quickNote.hint")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
        }
    }

    MentionAutocomplete {
        id: at
        target: editor
        // The text goes into a note, where the editor writes @Name_Like_This;
        // an id-style @o.t for the same person read as somebody else.
        insertNames: true
    }
}
