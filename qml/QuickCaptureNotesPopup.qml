import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp
import "PopupStack.js" as PopupStack

// Quick-capture popup for Notes — triggered by Ctrl+Shift+N.
//
//  • Enter           → submit (append to AppController.notesState)
//  • Shift+Enter     → newline in the editor
//  • @<token>        → people autocomplete via MentionAutocomplete
//  • Esc (empty)     → close silently
//  • Esc (non-empty) → discard-confirm child popup
//      ↳ Enter → drop the note and close both popups
//      ↳ Esc   → cancel the discard, return focus to the editor
Popup {
    id: root
    // Standalone it is the whole window — there is nothing behind it to
    // dim or block, so no scrim.
    modal: !root.standalone
    focus: true
    // We own all key handling (the discard-confirm flow needs to intercept
    // Esc), so the popup must NOT auto-close on Escape.
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: 600
    // Standalone: hosted by CaptureWindow — see QuickCapturePopup.
    property bool standalone: false
    anchors.centerIn: root.standalone ? undefined : Overlay.overlay
    x: root.standalone ? Math.round((root.parent.width - root.width) / 2) : 0
    y: root.standalone ? Theme.sp2xl : 0

    Overlay.modal: ModalScrim {}
    // A press beside the popup acts like Esc (APP-126): close when empty,
    // otherwise ask before dropping the text. See PopupStack.js.
    Overlay.onPressed: if (!root.standalone && PopupStack.isTopmost(root, Overlay.overlay)) root._maybeDiscard()

    // The note just saved, for the owner's confirmation (see QuickCapturePopup).
    signal captured(string title, string body, string taskId)

    readonly property bool hasText: editor.text.trim().length > 0

    function _submit() {
        const body = editor.text;
        if (body.trim().length === 0) {
            root.close();
            return;
        }
        // Named before the append: with no note open it lands in Inbox, and
        // the confirmation should say so, not "Note saved" somewhere unseen.
        const into = AppController.quickNoteTarget();
        AppController.appendNoteEntry(body);
        editor.text = "";
        at.dismiss();
        root.close();
        const flat = body.trim().replace(/\s+/g, " ");
        root.captured(I18n.t("quickNote.doneInto").arg(into), flat.length > 140 ? flat.substring(0, 139) + "…" : flat, "");
    }

    function _maybeDiscard() {
        if (editor.text.trim().length === 0) {
            root.close();
            return;
        }
        confirmDiscard.open();
    }

    property string _target: ""
    // Opt-in timing (HEAP_PERF_LOG=1 / --perf-log): hotkey or open() to the
    // first frame that shows the popup. Logs only; a no-op otherwise.
    onAboutToShow: AppController.perfMarkShown("capture-notes", contentItem)
    onOpened: {
        root._target = AppController.quickNoteTarget();
        editor.text = "";
        at.dismiss();
        editor.forceActiveFocus();
    }

    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: Theme.spLg

        Item {
            Layout.preferredHeight: 6
        }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            objectName: "quick-note-target"
            // Where it goes, before it goes there.
            text: I18n.t("quickNote.titleInto").arg(root._target)
            elide: Text.ElideRight
            Layout.fillWidth: true
            color: Theme.textDim
            font.pixelSize: Theme.fsSm
            font.weight: Theme.fwTitle
        }

        ScrollView {
            id: editorScroll
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            Layout.preferredHeight: 240
            clip: true

            TextArea {
                id: editor
                ContextMenu.menu: TextEditMenu { editor: editor }
                objectName: "quicknote-editor"
                wrapMode: TextEdit.Wrap
                font.pixelSize: Theme.fsLg
                color: Theme.text
                placeholderText: I18n.t("quickNote.placeholder")
                placeholderTextColor: Theme.textDim
                selectByMouse: true
                background: Rectangle {
                    radius: Theme.radiusMd
                    color: Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                }

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
                            && !(e.modifiers & Qt.ShiftModifier)) {
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

                    // Shift+Enter → fall through to TextArea (inserts "\n").
                    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                        && (e.modifiers & Qt.ShiftModifier)) {
                        return;
                    }

                    // Plain Enter → submit the note.
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        root._submit();
                        e.accepted = true;
                        return;
                    }

                    // Esc → discard-confirm flow (or silent close when empty).
                    if (e.key === Qt.Key_Escape) {
                        root._maybeDiscard();
                        e.accepted = true;
                        return;
                    }
                }
            }
        }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("quickNote.hint")
            color: Theme.textDim
            font.pixelSize: Theme.fsXs
        }

        RowLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.bottomMargin: Theme.sp2xl
            spacing: Theme.spMd
            Item {
                Layout.fillWidth: true
            }
            PillButton {
                text: I18n.t("common.cancel")
                onClicked: root._maybeDiscard()
            }
            PillButton {
                text: I18n.t("common.save")
                primary: true
                enabled: editor.text.trim().length > 0
                onClicked: root._submit()
            }
        }
    }

    MentionAutocomplete {
        id: at
        target: editor
        // The text goes into a note, where the editor writes @Name_Like_This;
        // an id-style @o.t for the same person read as somebody else.
        insertNames: true
    }

    // ── Discard confirmation ──
    // Modal child popup. Enter inside it commits the discard; Esc closes
    // the confirm via Popup.CloseOnEscape and onClosed returns focus to
    // the editor with text intact.
    //
    // Why a FocusScope content: Keys.onPressed attached directly to a
    // Popup never fires — focus lives on the contentItem, not on the
    // Popup. Wrapping in a FocusScope with `focus: true` makes the scope
    // the activeFocus target so Enter is captured here.
    Popup {
        id: confirmDiscard
        modal: !root.standalone
        focus: true
        closePolicy: Popup.CloseOnEscape
        padding: 0
        width: 360
        anchors.centerIn: Overlay.overlay

        Overlay.modal: ModalScrim {}

        background: ModalSurface {}

        function _commitDiscard() {
            editor.text = "";
            confirmDiscard.close();
            root.close();
        }

        contentItem: FocusScope {
            id: confirmScope
            focus: true
            implicitHeight: confirmCol.implicitHeight

            Keys.onReturnPressed: confirmDiscard._commitDiscard()
            Keys.onEnterPressed: confirmDiscard._commitDiscard()

            ColumnLayout {
                id: confirmCol
                anchors.fill: parent
                spacing: Theme.spLg

                Item {
                    Layout.preferredHeight: 6
                }

                Text {
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    text: I18n.t("quickNote.discard.title")
                    color: Theme.text
                    font.pixelSize: Theme.fsMd
                    font.weight: Theme.fwTitle
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
                    text: I18n.t("quickNote.discard.hint")
                    color: Theme.textDim
                    font.pixelSize: Theme.fsXs
                }

                RowLayout {
                    Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.bottomMargin: Theme.sp2xl
                    spacing: Theme.spMd
                    Item {
                        Layout.fillWidth: true
                    }
                    PillButton {
                        text: I18n.t("common.cancel")
                        onClicked: confirmDiscard.close()
                    }
                    PillButton {
                        text: I18n.t("common.delete")
                        danger: true
                        onClicked: confirmDiscard._commitDiscard()
                    }
                }
            }
        }

        onOpened: confirmScope.forceActiveFocus()
        onClosed: editor.forceActiveFocus()
    }
}
