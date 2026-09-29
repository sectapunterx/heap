// Create / rename / re-color a profile. Single dialog handles both modes.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 420
    anchors.centerIn: Overlay.overlay

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle { color: Theme.scrim }

    // Not `palette`: that is QQuickPopup's own property, which every
    // Control inside this dialog resolves its colours through. Shadowing
    // it with an array of hex strings hands those controls an array where
    // they expect a palette.
    readonly property var swatches: [
        "#5cc2dd", "#6cc4b8", "#7cc492", "#dcb86b",
        "#e6984c", "#c07acf", "#7da8d9", "#e6624c"
    ]

    property string mode: "create"      // "create" | "rename" | "duplicate"
    property string profileId: ""       // for rename / duplicate
    property string presetName: ""
    property string presetColor: ""

    function showCreate() {
        mode = "create"; profileId = "";
        nameField.text = "";
        colorSwatch.selectedIndex = 0;
        open();
        Qt.callLater(nameField.forceActiveFocus);
    }

    function showRename(id, name, color) {
        mode = "rename"; profileId = id;
        nameField.text = name;
        const cur = String(color || swatches[0]).toLowerCase();
        let i = 0;
        for (let k = 0; k < swatches.length; k++)
            if (swatches[k].toLowerCase() === cur) { i = k; break; }
        colorSwatch.selectedIndex = i;
        open();
        Qt.callLater(function () { nameField.forceActiveFocus(); nameField.selectAll() });
    }

    function showDuplicate(id, sourceName, sourceColor) {
        mode = "duplicate"; profileId = id;
        nameField.text = sourceName + " copy";
        const cur = String(sourceColor || swatches[0]).toLowerCase();
        let i = 0;
        for (let k = 0; k < swatches.length; k++)
            if (swatches[k].toLowerCase() === cur) { i = k; break; }
        colorSwatch.selectedIndex = i;
        open();
        Qt.callLater(function () { nameField.forceActiveFocus(); nameField.selectAll() });
    }

    background: Rectangle {
        radius: Theme.radiusXl; color: Theme.panel
        border.color: Theme.borderStrong; border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: Theme.spXl
        Item { Layout.preferredHeight: 4 }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: root.mode === "create" ? I18n.t("editor.profile.new")
                : root.mode === "rename" ? I18n.t("editor.profile.rename")
                    : I18n.t("editor.profile.dup")
            color: Theme.text
            font.pixelSize: Theme.fsLg
            font.weight: Font.DemiBold
        }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("common.title").toUpperCase()
            color: Theme.textMuted; font.pixelSize: Theme.fsXs
            font.weight: Font.DemiBold; font.letterSpacing: 1
        }
        TextField {
            id: nameField
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.fillWidth: true
            placeholderText: I18n.t("profile.ph.name")
            background: Rectangle { radius: Theme.radiusMd; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
            placeholderTextColor: Theme.textDim
            selectByMouse: true
            onAccepted: saveBtn.activate()
        }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("common.color").toUpperCase()
            color: Theme.textMuted; font.pixelSize: Theme.fsXs
            font.weight: Font.DemiBold; font.letterSpacing: 1
        }
        Row {
            id: colorSwatch
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            property int selectedIndex: 0
            spacing: Theme.spSm
            Repeater {
                model: root.swatches
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: 26; height: 26; radius: 13
                    color: modelData
                    border.color: colorSwatch.selectedIndex === index ? Theme.text : "transparent"
                    border.width: 2
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: colorSwatch.selectedIndex = index
                    }
                }
            }
        }

        RowLayout {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.topMargin: Theme.spMd; Layout.bottomMargin: Theme.sp2xl
            Item { Layout.fillWidth: true }
            PillButton {
                text: I18n.t("common.cancel"); onClicked: root.close()
            }
            PillButton {
                id: saveBtn
                primary: true
                text: root.mode === "rename" ? I18n.t("editor.btn.save") : I18n.t("editor.btn.create")
                function activate() {
                    const name = nameField.text.trim();
                    if (name.length === 0) return;
                    const color = root.swatches[colorSwatch.selectedIndex];
                    if (root.mode === "create") {
                        AppController.createProfile(name, color);
                    } else if (root.mode === "rename") {
                        AppController.renameProfile(root.profileId, name);
                        AppController.setProfileColor(root.profileId, color);
                    } else if (root.mode === "duplicate") {
                        AppController.duplicateProfile(root.profileId, name);
                        // newly active profile is the duplicate; tweak color afterwards
                        AppController.setProfileColor(AppController.activeProfileId, color);
                    }
                    root.close();
                }
                onClicked: activate()
            }
        }
    }
}
