pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// My tags on a card (APP-239), typed with completion from the tags already in
// use: "#after-release #quick". They are mine — on any card, from any tracker
// — and never go to a tracker. "Manage" renames (onto an existing tag =
// merge), recolours or removes a tag on every card of the profile.
ColumnLayout {
    id: root
    objectName: "task-doc-tags-editor"

    property string taskId: ""
    property int rev: 0
    // Tags the card has now: [{id, color}].
    property var tags: []
    signal done()

    readonly property var catalog: root.rev >= 0 ? AppController.localTagCatalog() : []
    property bool _manage: false
    property int _pick: -1

    spacing: Theme.spXs

    function open() {
        field.text = root.tags.map(t => "#" + t.id).join(" ") + (root.tags.length > 0 ? " " : "");
        field.forceActiveFocus();
        field.cursorPosition = field.length;
    }
    function commit() {
        const ids = field.text.split(/[\s,]+/).map(w => w.replace(/^#+/, "")).filter(w => w.length > 0);
        AppController.setTaskLocalTags(root.taskId, ids);
        root.done();
    }
    // The word being typed and the catalogue entries that start with it.
    readonly property string _word: {
        const m = field.text.slice(0, field.cursorPosition).match(/#?([^\s,#]*)$/);
        return m ? m[1].toLowerCase() : "";
    }
    readonly property var _matches: {
        if (!field.activeFocus) return [];
        const have = field.text.toLowerCase().split(/[\s,]+/).map(w => w.replace(/^#+/, ""));
        return root.catalog.filter(c => c.id.toLowerCase().startsWith(root._word)
                                   && (have.indexOf(c.id.toLowerCase()) < 0 || c.id.toLowerCase() === root._word)).slice(0, 6);
    }
    function complete(id) {
        const before = field.text.slice(0, field.cursorPosition).replace(/#?[^\s,#]*$/, "");
        const after = field.text.slice(field.cursorPosition);
        field.text = before + "#" + id + " " + after.replace(/^\S*\s*/, "");
        field.cursorPosition = before.length + id.length + 2;
        root._pick = -1;
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spSm
        QQC.TextField {
            id: field
            objectName: "task-doc-tags-field"
            Layout.fillWidth: true
            placeholderText: I18n.t("local.tags.ph")
            placeholderTextColor: Theme.textDim
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            leftPadding: Theme.spSm
            background: Rectangle { radius: Theme.radiusMd; color: Theme.panel2; border.width: 1; border.color: field.activeFocus ? Theme.focusRing : Theme.border }
            onTextChanged: root._pick = -1
            Keys.onDownPressed: root._pick = Math.min(root._pick + 1, root._matches.length - 1)
            Keys.onUpPressed: root._pick = Math.max(-1, root._pick - 1)
            Keys.onTabPressed: (e) => {
                if (root._matches.length > 0) root.complete(root._matches[Math.max(0, root._pick)].id);
                else e.accepted = false;
            }
            Keys.onReturnPressed: {
                if (root._pick >= 0 && root._pick < root._matches.length) root.complete(root._matches[root._pick].id);
                else root.commit();
            }
            Keys.onEnterPressed: root.commit()
            Keys.onEscapePressed: root.done()
        }
        Text {
            objectName: "task-doc-tags-manage"
            text: root._manage ? I18n.t("local.tags.manageDone") : I18n.t("local.tags.manage")
            color: manCA.hovered ? Theme.text : Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
            ClickArea { id: manCA; label: parent.text; onActivated: root._manage = !root._manage }
        }
    }

    // Completion: the tags in use that start with what is typed.
    Flow {
        Layout.fillWidth: true
        spacing: Theme.spMd
        visible: root._matches.length > 0
        Repeater {
            model: root._matches
            delegate: Text {
                id: m
                required property var modelData
                required property int index
                objectName: "task-doc-tags-match-" + m.index
                text: "#" + m.modelData.id + "  " + m.modelData.count
                color: root._pick === m.index || mCA.hovered ? Theme.text : Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                ClickArea { id: mCA; label: m.text; onActivated: { root.complete(m.modelData.id); field.forceActiveFocus(); } }
            }
        }
    }

    // Every tag of the profile: colour, rename (merge), remove.
    Repeater {
        model: root._manage ? root.catalog : []
        delegate: RowLayout {
            id: tagRow
            required property var modelData
            Layout.fillWidth: true
            spacing: Theme.spSm
            Rectangle {
                implicitWidth: Theme.iconSize; implicitHeight: Theme.iconSize
                radius: Theme.radiusPill
                color: tagRow.modelData.color || "transparent"
                border.width: 1
                border.color: Theme.borderStrong
                ClickArea {
                    label: I18n.t("local.tags.color")
                    // The next swatch of the palette, round and round.
                    onActivated: {
                        const sw = Theme.swatches;
                        const i = sw.indexOf(String(tagRow.modelData.color));
                        AppController.setLocalTagColor(tagRow.modelData.id, i + 1 < sw.length ? sw[i + 1] : "");
                    }
                }
            }
            QQC.TextField {
                Layout.fillWidth: true
                text: tagRow.modelData.id
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                color: Theme.text
                padding: 0
                leftPadding: Theme.spXs
                background: Rectangle { radius: Theme.radiusSm; color: "transparent"; border.width: parent.activeFocus ? 1 : 0; border.color: Theme.focusRing }
                onAccepted: AppController.renameLocalTag(tagRow.modelData.id, text)
            }
            Text {
                text: String(tagRow.modelData.count)
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
            Text {
                text: "×"
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
                ClickArea { label: I18n.t("local.tags.delete"); onActivated: AppController.deleteLocalTag(tagRow.modelData.id) }
            }
        }
    }
}
