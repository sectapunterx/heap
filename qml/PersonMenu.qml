import QtQuick
import TodoCpp

// Right-click on a person in "Кому написать" (R2-063, sheet X/N-Menus-Other):
// the name and role on top, mark as written, edit the question, the tasks
// and meetings linked to them, delete. Nothing is sent anywhere.
AppMenu {
    id: menu
    objectName: "person-menu"

    property var person: ({})
    // Off where the linked tasks are already in view (the people dialog).
    property bool showLinks: true

    signal editRequested(string id)
    signal linksRequested(string id)

    function openFor(p) {
        // The stored person: a row's map may not carry the role.
        menu.person = p && p.id ? AppController.personById(p.id) : ({});
        menu.popup();
    }

    AppMenuHeader {
        text: (menu.person.name || "") + ((menu.person.role || "").length ? " · " + menu.person.role : "")
    }
    AppMenuItem {
        objectName: "person-menu-wrote"
        text: I18n.t("people.menu.wrote")
        onTriggered: AppController.setPersonState(menu.person.id, "pinged")
    }
    AppMenuItem {
        objectName: "person-menu-edit"
        text: I18n.t("people.menu.question")
        onTriggered: menu.editRequested(menu.person.id)
    }
    AppMenuItem {
        objectName: "person-menu-links"
        visible: menu.showLinks
        height: visible ? implicitHeight : 0
        text: I18n.t("people.dialog.tasks")
        onTriggered: menu.linksRequested(menu.person.id)
    }
    AppMenuSeparator {}
    AppMenuItem {
        objectName: "person-menu-delete"
        text: I18n.t("people.menu.deletePerson")
        danger: true
        onTriggered: AppController.deletePerson(menu.person.id)
    }
}
