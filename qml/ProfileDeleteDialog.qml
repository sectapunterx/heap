// "Удалить профиль «…»?" (DG-151, sheet X/N-Dlg-Small): how many tasks and
// notes go, that a snapshot stays in the Time Machine, and the profile's
// name typed to confirm. A whole profile is too big for one click; Ctrl Z
// still brings it back after.
import QtQuick
import TodoCpp

SmallDialog {
    id: root
    objectName: "profile-delete-dialog"

    property string profileId: ""
    property string profileName: ""
    property int taskCount: 0
    property int noteCount: 0
    readonly property bool confirmed: confirmField.text.trim() === root.profileName.trim()

    title: I18n.t("profile.delete.title").arg(root.profileName)
    fact: I18n.t("profile.delete.fact").arg(I18n.count(root.taskCount, "profile.delete.tasks"))
                                        .arg(I18n.count(root.noteCount, "profile.delete.notes"))

    function openFor(id) {
        const p = (AppController.profiles || []).find(x => x.id === id);
        if (!p) return;
        root.profileId = p.id;
        root.profileName = p.name || "";
        root.taskCount = p.tasks || 0;
        root.noteCount = p.notes || 0;
        confirmField.text = "";
        open();
        confirmField.focusField();
    }

    function submit() {
        if (!root.confirmed) return;
        root.close();
        AppController.deleteProfile(root.profileId);
    }
    onAccepted: root.submit()

    DialogField {
        id: confirmField
        fieldName: "profile-delete-confirm"
        label: I18n.t("profile.delete.confirm")
        onAccepted: root.submit()
    }

    buttons: [
        PillButton {
            objectName: "profile-delete-cancel"
            text: I18n.t("common.cancel")
            onClicked: root.close()
        },
        PillButton {
            objectName: "profile-delete-ok"
            danger: true
            enabled: root.confirmed
            text: I18n.t("profile.delete.ok")
            onClicked: root.submit()
        }
    ]
}
