import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp

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
    modal: true
    focus: true
    // We own all key handling (the discard-confirm flow needs to intercept
    // Esc), so the popup must NOT auto-close on Escape.
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: 600
    anchors.centerIn: Overlay.overlay

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    function _submit() {
        const body = editor.text;
        if (body.trim().length === 0) {
            root.close();
            return;
        }
        AppController.appendNoteEntry(body);
        editor.text = "";
        at.dismiss();
        root.close();
    }

    function _maybeDiscard() {
        if (editor.text.trim().length === 0) {
            root.close();
            return;
        }
        confirmDiscard.open();
    }

    onOpened: {
        editor.text = "";
        at.dismiss();
        editor.forceActiveFocus();
    }

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 10

        Item {
            Layout.preferredHeight: 6
        }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: I18n.t("quickNote.title")
            color: Theme.textMuted
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }

        ScrollView {
            id: editorScroll
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            Layout.preferredHeight: 240
            clip: true

            TextArea {
                id: editor
                wrapMode: TextEdit.Wrap
                font.pixelSize: 14
                color: Theme.text
                placeholderText: I18n.t("quickNote.placeholder")
                placeholderTextColor: Theme.textDim
                selectByMouse: true
                background: Rectangle {
                    radius: 6
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
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: I18n.t("quickNote.hint")
            color: Theme.textDim
            font.pixelSize: 10
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 14
            spacing: 8
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
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        padding: 0
        width: 360
        anchors.centerIn: Overlay.overlay

        Overlay.modal: Rectangle {
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        background: Rectangle {
            radius: 10
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

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
                spacing: 10

                Item {
                    Layout.preferredHeight: 6
                }

                Text {
                    Layout.leftMargin: 18; Layout.rightMargin: 18
                    text: I18n.t("quickNote.discard.title")
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    Layout.leftMargin: 18; Layout.rightMargin: 18
                    text: I18n.t("quickNote.discard.hint")
                    color: Theme.textDim
                    font.pixelSize: 10
                }

                RowLayout {
                    Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 14
                    spacing: 8
                    Item {
                        Layout.fillWidth: true
                    }
                    PillButton {
                        text: I18n.t("common.cancel")
                        onClicked: confirmDiscard.close()
                    }
                    PillButton {
                        text: I18n.t("common.delete")
                        primary: true
                        onClicked: confirmDiscard._commitDiscard()
                    }
                }
            }
        }

        onOpened: confirmScope.forceActiveFocus()
        onClosed: editor.forceActiveFocus()
    }
}
