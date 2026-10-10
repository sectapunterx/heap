pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import TodoCpp

// "Импорт профиля (JSON)" (N/X-Dlg-Log-Import, R3-080): a preview first,
// nothing is written before the button. The fact line is the file, the build
// that wrote it and what it holds; two choices — a new profile, or merged into
// the active one, where an id that is already here is never overwritten.
// ↑ ↓ pick, Enter imports, Esc leaves nothing behind.
SmallDialog {
    id: root
    objectName: "profile-import-dialog"
    width: 480

    property url fileUrl: ""
    property var preview: ({})
    // "new" | "merge"
    property string choice: "new"

    title: I18n.t("profileImport.title")
    fact: root.factText(root.preview)

    function factText(p) {
        if (!p || p.error) return p && p.error ? String(p.error) : "";
        const parts = [String(p.file || "")];
        if (p.version) parts.push(I18n.t("profileImport.version").arg(p.version));
        parts.push([I18n.count(p.tasks || 0, "profileImport.tasksN"),
                    I18n.count(p.notes || 0, "profileImport.notesN"),
                    I18n.count(p.views || 0, "profileImport.viewsN")].join(", "));
        return parts.join(" · ");
    }

    function openFor(url) {
        root.fileUrl = url;
        root.preview = AppController.previewProfileImport(url);
        root.choice = "new";
        root.open();
        choices.forceActiveFocus();
    }

    function run() {
        if (root.preview.error) return;
        const err = root.choice === "merge" ? AppController.mergeProfileFromFile(root.fileUrl)
                                            : AppController.importProfileFromFile(root.fileUrl, true);
        root.close();
        if (err && err.length > 0)
            AppController.toast(I18n.t("toast.profile.importFail") + err, "error");
    }
    onAccepted: root.run()

    ColumnLayout {
        id: choices
        objectName: "profile-import-choices"
        Layout.fillWidth: true
        visible: !root.preview.error
        spacing: Theme.spXs
        focus: true
        Keys.onUpPressed: root.choice = "new"
        Keys.onDownPressed: root.choice = "merge"
        Keys.onReturnPressed: root.run()
        Keys.onEnterPressed: root.run()
        Repeater {
            model: ["new", "merge"]
            delegate: Item {
                id: opt
                required property string modelData
                readonly property bool on: root.choice === opt.modelData
                readonly property string label: opt.modelData === "new"
                    ? I18n.t("profileImport.asNew").arg(root.preview.name || "")
                    : I18n.t("profileImport.merge").arg(root.preview.activeName || "")
                objectName: "profile-import-" + opt.modelData
                Layout.fillWidth: true
                implicitHeight: Math.max(Theme.chipH, optText.implicitHeight + Theme.spXs)
                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.spMd
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: Theme.sp2xs
                        implicitWidth: Theme.px(14); implicitHeight: Theme.px(14)
                        radius: width / 2
                        color: "transparent"
                        // The same plain radio as the series question (R4-051).
                        border.width: opt.on ? 4 : 1.5
                        border.color: opt.on ? Theme.accent : Theme.textMuted
                    }
                    Text {
                        id: optText
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        text: opt.label
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsMd
                        wrapMode: Text.Wrap
                    }
                }
                ClickArea {
                    label: opt.label
                    role: Accessible.RadioButton
                    checkable: true
                    checked: opt.on
                    onActivated: root.choice = opt.modelData
                }
            }
        }
    }

    // One button, as the sheet draws it; Esc cancels.
    buttons: [
        PillButton {
            objectName: "profile-import-go"
            text: I18n.t("profileImport.go")
            primary: true
            solid: Style.fills
            enabled: !root.preview.error
            onClicked: root.run()
        }
    ]
}
