import QtQuick
import TodoCpp

// The right-click menu of a text field or text area, in the app's own menu
// and language (X-Menus-Other, DG-152): an optional context line ("Описание
// задачи"), Undo / Redo, Cut / Copy / Paste / Paste as plain text, "Link to
// a task… [[" where the field takes Markdown links, Select all — each with
// its key on the right. Attach with
//     ContextMenu.menu: TextEditMenu { editor: myField }
// on a TextField or TextArea; ContextMenu.menu is deferred, so the menu is
// only built on the first right-click.
AppMenu {
    id: menu
    objectName: "text-edit-menu"
    // A TextField, TextArea, TextInput or TextEdit. var, not Item: the
    // editing API (cut, canPaste, selectedText …) is not an Item member.
    required property var editor
    // What the field is, for the context line; none when empty.
    property string context: ""
    // The field reads "[[" as the start of a link to a task or a note.
    property bool taskLink: false
    readonly property bool _editable: !!menu.editor && !menu.editor.readOnly
    readonly property bool _hasSelection: !!menu.editor && String(menu.editor.selectedText || "").length > 0
    readonly property bool _secret: !!menu.editor && menu.editor.echoMode !== undefined && menu.editor.echoMode !== TextInput.Normal

    AppMenuHeader {
        visible: menu.context.length > 0
        height: visible ? implicitHeight : 0
        text: menu.context
    }
    AppMenuItem {
        objectName: "text-edit-undo"
        text: I18n.t("textmenu.undo")
        keyText: AppController.keyText("Ctrl+Z")
        enabled: menu._editable && !!menu.editor.canUndo
        onTriggered: menu.editor.undo()
    }
    AppMenuItem {
        objectName: "text-edit-redo"
        text: I18n.t("textmenu.redo")
        keyText: AppController.keyText("Ctrl+Shift+Z")
        enabled: menu._editable && !!menu.editor.canRedo
        onTriggered: menu.editor.redo()
    }
    AppMenuSeparator {}
    AppMenuItem {
        objectName: "text-edit-cut"
        text: I18n.t("textmenu.cut")
        keyText: AppController.keyText("Ctrl+X")
        enabled: menu._editable && menu._hasSelection && !menu._secret
        onTriggered: menu.editor.cut()
    }
    AppMenuItem {
        objectName: "text-edit-copy"
        text: I18n.t("textmenu.copy")
        keyText: AppController.keyText("Ctrl+C")
        enabled: menu._hasSelection && !menu._secret
        onTriggered: menu.editor.copy()
    }
    AppMenuItem {
        objectName: "text-edit-paste"
        text: I18n.t("textmenu.paste")
        keyText: AppController.keyText("Ctrl+V")
        enabled: menu._editable && !!menu.editor.canPaste
        onTriggered: menu.editor.paste()
    }
    // Every field here keeps plain text or Markdown, so a paste never brings
    // formatting in; the row says so where a rich editor would differ.
    AppMenuItem {
        objectName: "text-edit-paste-plain"
        text: I18n.t("textmenu.pastePlain")
        keyText: AppController.keyText("Ctrl+Shift+V")
        enabled: menu._editable && !!menu.editor.canPaste
        onTriggered: menu.editor.paste()
    }
    AppMenuSeparator { visible: menu.taskLink }
    AppMenuItem {
        objectName: "text-edit-task-link"
        visible: menu.taskLink
        height: visible ? implicitHeight : 0
        text: I18n.t("textmenu.taskLink")
        keyText: "[["
        enabled: menu._editable
        onTriggered: {
            const e = menu.editor;
            if (e.selectedText && String(e.selectedText).length > 0) e.remove(e.selectionStart, e.selectionEnd);
            e.insert(e.cursorPosition, "[[");
            e.forceActiveFocus();
        }
    }
    AppMenuItem {
        objectName: "text-edit-select-all"
        text: I18n.t("textmenu.selectAll")
        keyText: AppController.keyText("Ctrl+A")
        enabled: !!menu.editor && String(menu.editor.text || "").length > 0
        onTriggered: menu.editor.selectAll()
    }
}
