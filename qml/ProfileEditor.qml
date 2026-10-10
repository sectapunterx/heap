// Create / rename / re-color a profile (X-Dlg-Small "Новый профиль"): the
// fact line, the name, eight swatches, Cancel and an outlined Create.
import QtQuick
import QtQuick.Layouts
import TodoCpp

SmallDialog {
    id: root
    objectName: "profile-editor"

    // Not `palette`: that is QQuickPopup's own property, which every
    // Control inside this dialog resolves its colours through.
    // The sheet offers eight.
    readonly property var swatches: Theme.profileSwatches

    property string mode: "create"      // "create" | "rename" | "duplicate"
    property string profileId: ""       // for rename / duplicate
    property string presetName: ""
    property string presetColor: ""
    property int selectedIndex: 0
    // Why Enter did not close it: a taken or empty name, said under the field
    // with the name still there (IDIOT-SHELL-12).
    property string nameError: ""

    title: root.mode === "create" ? I18n.t("editor.profile.new")
         : root.mode === "rename" ? I18n.t("editor.profile.rename")
         : I18n.t("editor.profile.dup")
    fact: I18n.t("profile.fact")

    function _indexOf(color) {
        const cur = String(color || root.swatches[0]).toLowerCase();
        for (let k = 0; k < root.swatches.length; k++)
            if (String(root.swatches[k]).toLowerCase() === cur) return k;
        return 0;
    }
    function showCreate() {
        mode = "create"; profileId = "";
        nameField.text = "";
        root.nameError = "";
        root.selectedIndex = 0;
        open();
        nameField.focusField();
    }
    function showRename(id, name, color) {
        mode = "rename"; profileId = id;
        nameField.text = name;
        root.nameError = "";
        root.selectedIndex = root._indexOf(color);
        open();
        nameField.focusField();
    }
    function showDuplicate(id, sourceName, sourceColor) {
        mode = "duplicate"; profileId = id;
        nameField.text = sourceName + " copy";
        root.nameError = "";
        root.selectedIndex = root._indexOf(sourceColor);
        open();
        nameField.focusField();
    }

    function activate() {
        const name = nameField.text.trim();
        if (name.length === 0) {
            root.nameError = I18n.t("profile.err.empty");
            return;
        }
        // A duplicate gets "(2)" on its own; a create or rename with a taken
        // name closed the dialog and did nothing (IDIOT-SHELL-12).
        if (root.mode !== "duplicate"
                && AppController.profileNameTaken(name, root.mode === "rename" ? root.profileId : "")) {
            root.nameError = I18n.t("profile.err.taken");
            nameField.focusField();
            return;
        }
        const color = root.swatches[root.selectedIndex];
        if (root.mode === "create") {
            AppController.createProfile(name, color);
        } else if (root.mode === "rename") {
            AppController.renameProfile(root.profileId, name);
            AppController.setProfileColor(root.profileId, color);
        } else if (root.mode === "duplicate") {
            AppController.duplicateProfile(root.profileId, name);
            // The copy is the active profile now; its colour comes after.
            AppController.setProfileColor(AppController.activeProfileId, color);
        }
        root.close();
    }

    DialogField {
        id: nameField
        fieldName: "profile-name-field"
        label: I18n.t("common.title")
        placeholderText: I18n.t("profile.ph.name")
        maximumLength: 64  // AppController.kMaxProfileName (IDIOT-SHELL-16)
        onAccepted: root.activate()
        onTextChanged: root.nameError = ""
    }
    Text {
        objectName: "profile-name-error"
        Layout.fillWidth: true
        visible: root.nameError.length > 0
        text: root.nameError
        color: Theme.warning
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsXs
        wrapMode: Text.WordWrap
    }
    Row {
        id: colorSwatch
        objectName: "profile-swatches"
        Layout.topMargin: Theme.spXs
        spacing: Theme.spSm
        Repeater {
            model: root.swatches
            delegate: Item {
                id: swatch
                required property string modelData
                required property int index
                readonly property bool picked: root.selectedIndex === swatch.index
                width: Theme.chipH; height: Theme.chipH
                // The picked one: a ring with the surface between.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: swatch.picked ? Theme.text : "transparent"
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.sp2xs - 2; height: width
                    radius: width / 2
                    color: swatch.modelData
                }
                ClickArea {
                    label: I18n.t("swatch.name").arg(swatch.index + 1)
                    role: Accessible.RadioButton
                    checkable: true
                    checked: swatch.picked
                    onActivated: root.selectedIndex = swatch.index
                }
            }
        }
    }

    buttons: [
        PillButton {
            text: I18n.t("common.cancel")
            onClicked: root.close()
        },
        PillButton {
            id: saveBtn
            objectName: "profile-save"
            primary: true
            text: root.mode === "rename" ? I18n.t("editor.btn.save") : I18n.t("editor.btn.create")
            onClicked: root.activate()
        }
    ]
}
