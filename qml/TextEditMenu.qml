import QtQuick
import TodoCpp

// The right-click menu of a text field or text area, in the app's own menu
// and language. Qt's stock one (Qt 6.9+) was an English Undo/Redo/Cut/…
// list with 24px icons and 40px rows, unlike every other menu in heap
// (VISP-1). Attach with
//     ContextMenu.menu: TextEditMenu { editor: myField }
// on a TextField or TextArea; ContextMenu.menu is deferred, so the menu is
// only built on the first right-click.
AppMenu {
    id: menu
    objectName: "text-edit-menu"
    // A TextField, TextArea, TextInput or TextEdit. var, not Item: the
    // editing API (cut, canPaste, selectedText …) is not an Item member.
    required property var editor
    readonly property bool _editable: !!menu.editor && !menu.editor.readOnly
    readonly property bool _hasSelection: !!menu.editor && String(menu.editor.selectedText || "").length > 0

    AppMenuItem {
        objectName: "text-edit-undo"
        text: I18n.t("textmenu.undo")
        enabled: menu._editable && !!menu.editor.canUndo
        onTriggered: menu.editor.undo()
    }
    AppMenuItem {
        objectName: "text-edit-redo"
        text: I18n.t("textmenu.redo")
        enabled: menu._editable && !!menu.editor.canRedo
        onTriggered: menu.editor.redo()
    }
    AppMenuSeparator {}
    AppMenuItem {
        objectName: "text-edit-cut"
        text: I18n.t("textmenu.cut")
        enabled: menu._editable && menu._hasSelection
            && menu.editor.echoMode !== TextInput.Password
        onTriggered: menu.editor.cut()
    }
    AppMenuItem {
        objectName: "text-edit-copy"
        text: I18n.t("textmenu.copy")
        enabled: menu._hasSelection && menu.editor.echoMode !== TextInput.Password
        onTriggered: menu.editor.copy()
    }
    AppMenuItem {
        objectName: "text-edit-paste"
        text: I18n.t("textmenu.paste")
        enabled: menu._editable && !!menu.editor.canPaste
        onTriggered: menu.editor.paste()
    }
    AppMenuItem {
        objectName: "text-edit-delete"
        text: I18n.t("textmenu.delete")
        enabled: menu._editable && menu._hasSelection
        onTriggered: menu.editor.remove(menu.editor.selectionStart, menu.editor.selectionEnd)
    }
    AppMenuSeparator {}
    AppMenuItem {
        objectName: "text-edit-select-all"
        text: I18n.t("textmenu.selectAll")
        enabled: !!menu.editor && String(menu.editor.text || "").length > 0
        onTriggered: menu.editor.selectAll()
    }
}
