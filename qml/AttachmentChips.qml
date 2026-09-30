pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// Attached files as a row of chips: what each is called, how big it is, and
// open / show in folder / remove. Used by the task editor (the task's own
// list) and the notes editor (the files the note links).
//
// Keyboard: every chip is one Tab stop. Enter or Space opens the file,
// Shift+Enter shows it in its folder, Delete or Backspace removes it. A file
// missing from the attachments folder is drawn as broken and cannot be
// opened; it can still be removed.
Flow {
    id: root

    // [{ id, name, sizeText, exists, isImage, … }] — from
    // AppController.taskAttachments / describeAttachments / markdownAttachments.
    property var model: []
    property bool removable: true
    // What "remove" means for the caller: the task editor detaches the file,
    // the notes editor takes the link out of the text.
    signal removeRequested(string attachmentId, string name)

    spacing: Theme.spSm

    // Opens through the controller, which asks first about a file that would
    // run something rather than show (a script, a program, a shortcut).
    function open(attachmentId, name) {
        const r = AppController.openAttachment(attachmentId, false);
        if (r === "confirm") root._askOpen(attachmentId, name || attachmentId);
    }
    function reveal(attachmentId) {
        AppController.revealAttachment(attachmentId);
    }
    // The chip for an id, so a caller (or a test) can give it the keyboard.
    function chipFor(attachmentId) {
        for (let i = 0; i < rep.count; ++i) {
            const c = rep.itemAt(i);
            if (c && c.objectName === "att-chip-" + attachmentId) return c;
        }
        return null;
    }

    Repeater {
        id: rep
        model: root.model
        delegate: Rectangle {
            id: chip
            required property var modelData
            required property int index
            readonly property string attId: String(modelData.id || "")
            readonly property string attName: String(modelData.name || modelData.id || "")
            readonly property bool broken: !modelData.exists
            objectName: "att-chip-" + attId
            radius: Theme.radiusMd
            color: chipHover.hovered ? Theme.panel3 : Theme.panel2
            border.color: chip.broken ? Theme.danger : Theme.border
            border.width: 1
            implicitWidth: chipRow.implicitWidth + 2 * Theme.spMd
            implicitHeight: chipRow.implicitHeight + 2 * Theme.spXs
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: chip.broken ? I18n.t("att.chip.missing").arg(chip.attName)
                                         : chip.attName + ", " + String(modelData.sizeText || "")
            Accessible.description: I18n.t("att.chip.keys")
            Keys.onPressed: (event) => {
                const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
                if (enter && (event.modifiers & Qt.ShiftModifier)) {
                    if (!chip.broken) root.reveal(chip.attId);
                    event.accepted = true;
                } else if (enter || event.key === Qt.Key_Space) {
                    if (!chip.broken) root.open(chip.attId, chip.attName);
                    event.accepted = true;
                } else if (root.removable && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
                    // The chip is about to go: hand the keyboard to a neighbour.
                    const next = chip.nextItemInFocusChain(true);
                    root.removeRequested(chip.attId, chip.attName);
                    if (next && next !== chip) next.forceActiveFocus(Qt.TabFocusReason);
                    event.accepted = true;
                }
            }
            HoverHandler { id: chipHover }
            FocusRing {}
            QQC.ToolTip.visible: chipHover.hovered
            QQC.ToolTip.delay: 500
            QQC.ToolTip.text: chip.broken ? I18n.t("att.chip.missing").arg(chip.attName) : I18n.t("att.chip.keys")

            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: Theme.spSm
                Text {
                    text: chip.broken ? "⚠" : (chip.modelData.isImage ? "🖼" : "📄")
                    color: chip.broken ? Theme.danger : Theme.textMuted
                    font.pixelSize: Theme.fsSm
                }
                Text {
                    objectName: "att-name"
                    text: chip.attName
                    textFormat: Text.PlainText
                    color: chip.broken ? Theme.danger : Theme.text
                    font.pixelSize: Theme.fsSm
                    font.strikeout: chip.broken
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 220
                    MouseArea {
                        anchors.fill: parent
                        enabled: !chip.broken
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.open(chip.attId, chip.attName)
                    }
                }
                Text {
                    text: chip.broken ? I18n.t("att.chip.missingShort") : String(chip.modelData.sizeText || "")
                    color: chip.broken ? Theme.danger : Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsXs
                }
                ChipButton {
                    objectName: "att-reveal"
                    visible: !chip.broken
                    glyph: "📂"
                    tip: I18n.t("att.chip.reveal")
                    onActivated: root.reveal(chip.attId)
                }
                ChipButton {
                    objectName: "att-remove"
                    visible: root.removable
                    glyph: "✕"
                    tip: I18n.t("att.chip.remove")
                    onActivated: root.removeRequested(chip.attId, chip.attName)
                }
            }
        }
    }

    // A glyph that acts on a click. Not a Tab stop of its own: the chip's keys
    // do the same, and three stops per file would make the row a slog.
    component ChipButton: Text {
        id: cb
        property string glyph
        property string tip
        signal activated()
        text: glyph
        color: cbMA.containsMouse ? Theme.text : Theme.textDim
        font.pixelSize: Theme.fsSm
        MouseArea {
            id: cbMA
            anchors.fill: parent
            anchors.margins: -Theme.spXs
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cb.activated()
        }
        QQC.ToolTip.visible: cbMA.containsMouse
        QQC.ToolTip.delay: 400
        QQC.ToolTip.text: cb.tip
    }

    // "Open this file?" for a type that would run rather than show. Built on
    // first use rather than declared as a child: a child of a Flow is one of
    // the items it lays out.
    property var _confirm: null
    function _askOpen(attachmentId, name) {
        if (!root._confirm) root._confirm = confirmComponent.createObject(root);
        root._confirm.ask(attachmentId, name);
    }
    Component {
        id: confirmComponent
    QQC.Dialog {
        id: confirm
        objectName: "att-open-confirm"
        property string attId: ""
        property string attName: ""
        function ask(id, name) {
            confirm.attId = id;
            confirm.attName = name;
            confirm.open();
        }
        modal: true
        parent: QQC.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, (parent ? parent.width : 460) - 2 * Theme.sp3xl)
        padding: Theme.inset
        title: I18n.t("att.confirm.title")
        background: Rectangle {
            radius: Theme.radiusXl
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: Theme.spMd
            Text {
                Layout.fillWidth: true
                text: I18n.t("att.confirm.body")
                color: Theme.textMuted
                font.pixelSize: Theme.fsMd
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                text: confirm.attName
                textFormat: Text.PlainText
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsMd
                wrapMode: Text.WrapAnywhere
            }
        }
        footer: RowLayout {
            spacing: Theme.spMd
            Item { Layout.fillWidth: true }
            PillButton {
                text: I18n.t("common.cancel")
                onClicked: confirm.close()
            }
            PillButton {
                objectName: "att-open-confirm-open"
                text: I18n.t("att.confirm.open")
                danger: true
                onClicked: {
                    confirm.close();
                    AppController.openAttachment(confirm.attId, true);
                }
            }
            Item { Layout.preferredWidth: Theme.spMd }
        }
    }
    }
}
