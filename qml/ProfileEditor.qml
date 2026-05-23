// Create / rename / re-color a profile. Single dialog handles both modes.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    width: 420
    anchors.centerIn: Overlay.overlay

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

    readonly property var palette: [
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
        const cur = String(color || palette[0]).toLowerCase();
        let i = 0;
        for (let k = 0; k < palette.length; k++)
            if (palette[k].toLowerCase() === cur) { i = k; break; }
        colorSwatch.selectedIndex = i;
        open();
        Qt.callLater(function () { nameField.forceActiveFocus(); nameField.selectAll() });
    }

    function showDuplicate(id, sourceName, sourceColor) {
        mode = "duplicate"; profileId = id;
        nameField.text = sourceName + " copy";
        const cur = String(sourceColor || palette[0]).toLowerCase();
        let i = 0;
        for (let k = 0; k < palette.length; k++)
            if (palette[k].toLowerCase() === cur) { i = k; break; }
        colorSwatch.selectedIndex = i;
        open();
        Qt.callLater(function () { nameField.forceActiveFocus(); nameField.selectAll() });
    }

    background: Rectangle {
        radius: 12; color: Theme.panel
        border.color: Theme.borderStrong; border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 12
        Item { Layout.preferredHeight: 4 }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: root.mode === "create" ? I18n.t("editor.profile.new")
                : root.mode === "rename" ? I18n.t("editor.profile.rename")
                    : I18n.t("editor.profile.dup")
            color: Theme.text
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: I18n.t("common.title").toUpperCase()
            color: Theme.textMuted; font.pixelSize: 10
            font.weight: Font.DemiBold; font.letterSpacing: 1
        }
        TextField {
            id: nameField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            placeholderText: "LTE handover · feat/timeout · …"
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
            placeholderTextColor: Theme.textDim
            selectByMouse: true
            onAccepted: saveBtn.activate()
        }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: I18n.t("common.color").toUpperCase()
            color: Theme.textMuted; font.pixelSize: 10
            font.weight: Font.DemiBold; font.letterSpacing: 1
        }
        Row {
            id: colorSwatch
            Layout.leftMargin: 18; Layout.rightMargin: 18
            property int selectedIndex: 0
            spacing: 6
            Repeater {
                model: root.palette
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
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.topMargin: 8; Layout.bottomMargin: 16
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
                    const color = root.palette[colorSwatch.selectedIndex];
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
