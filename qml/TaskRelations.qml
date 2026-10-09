pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// Links drawn by hand (APP-240), in the document's side column: related
// cards (both ways, any tracker), what this waits on and what waits on it,
// and the card it is part of. Each with its status, opening in lowkey or in
// the browser in one click. Added by key, URL or id; nothing links itself,
// and nothing here goes to a tracker.
ColumnLayout {
    id: root
    objectName: "task-doc-links"

    property string taskId: ""
    property int rev: 0
    signal openTask(string id)

    readonly property var links: root.rev >= 0 && root.taskId.length > 0 ? AppController.taskRelations(root.taskId) : []
    // "related" | "blocks" | "blockedBy": what the field below adds.
    property string _adding: ""

    spacing: Theme.spSm

    SectionHeader { title: I18n.t("local.links"); count: root.links.length }

    Repeater {
        model: root.links
        delegate: RowLayout {
            id: link
            required property var modelData
            required property int index
            objectName: "task-doc-link-" + link.index
            Layout.fillWidth: true
            spacing: Theme.spSm
            Text {
                text: I18n.t("local.link." + link.modelData.kind)
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
            Text {
                Layout.fillWidth: true
                text: (link.modelData.key && link.modelData.isTask ? link.modelData.key + "  " : "") + link.modelData.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: !link.modelData.exists ? Theme.textDim : (link.modelData.done ? Theme.textMuted : Theme.text)
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                font.strikeout: !!link.modelData.done
                ClickArea {
                    enabled: !!link.modelData.exists
                    label: parent.text
                    tip: link.modelData.statusName || link.modelData.url || ""
                    onActivated: {
                        if (link.modelData.isTask) root.openTask(link.modelData.target);
                        else Qt.openUrlExternally(link.modelData.url);
                    }
                }
            }
            Text {
                visible: String(link.modelData.statusName || "").length > 0
                text: link.modelData.statusName || ""
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
            // In the browser, for a tracker card or a URL.
            Text {
                visible: String(link.modelData.url || "").length > 0 && link.modelData.isTask
                text: "↗"
                color: Theme.textMuted
                font.pixelSize: Theme.fsSm
                ClickArea { label: I18n.t("local.link.openBrowser"); onActivated: Qt.openUrlExternally(link.modelData.url) }
            }
            Text {
                objectName: "task-doc-link-remove"
                visible: link.modelData.kind !== "partOf"
                text: "×"
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
                ClickArea {
                    label: I18n.t("local.link.remove")
                    onActivated: {
                        const k = link.modelData.kind;
                        if (k === "related") AppController.removeRelatedLink(root.taskId, link.modelData.linkId);
                        else if (k === "blocks") AppController.removeBlockLink(root.taskId, link.modelData.target);
                        else if (k === "blockedBy") AppController.removeBlockLink(link.modelData.target, root.taskId);
                    }
                }
            }
        }
    }

    // + related · + waits on · + blocks
    Flow {
        Layout.fillWidth: true
        spacing: Theme.spMd
        visible: root._adding.length === 0
        Repeater {
            model: ["related", "blockedBy", "blocks"]
            delegate: Text {
                id: addLink
                required property string modelData
                objectName: "task-doc-link-add-" + addLink.modelData
                text: "+ " + I18n.t("local.link.add." + addLink.modelData)
                color: addCA.hovered ? Theme.text : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                ClickArea {
                    id: addCA
                    label: addLink.text
                    onActivated: { root._adding = addLink.modelData; refField.text = ""; refField.forceActiveFocus(); }
                }
            }
        }
    }
    QQC.TextField {
        id: refField
        objectName: "task-doc-link-field"
        visible: root._adding.length > 0
        Layout.fillWidth: true
        placeholderText: I18n.t("local.link.ph")
        placeholderTextColor: Theme.textDim
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsSm
        leftPadding: Theme.spSm
        background: Rectangle { radius: Theme.radiusMd; color: Theme.panel2; border.width: 1; border.color: refField.activeFocus ? Theme.focusRing : Theme.border }
        onAccepted: {
            const ref = refField.text.trim();
            if (ref.length === 0) { root._adding = ""; return; }
            let ok = false;
            if (root._adding === "related") ok = AppController.addRelatedLink(root.taskId, ref);
            else ok = AppController.addBlockLink(root.taskId, ref, root._adding === "blocks");
            if (ok) root._adding = "";
        }
        Keys.onEscapePressed: root._adding = ""
        Keys.onDownPressed: if (suggestions.count > 0) root._pick = Math.min(root._pick + 1, suggestions.count - 1)
        Keys.onUpPressed: root._pick = Math.max(-1, root._pick - 1)
        Keys.onReturnPressed: (e) => {
            if (root._pick >= 0 && root._pick < suggestions.count) {
                refField.text = root._matches[root._pick].id;
                root._pick = -1;
            }
            e.accepted = false;  // onAccepted does the adding
        }
        onTextChanged: root._pick = -1
        onActiveFocusChanged: if (!activeFocus && refField.text.length === 0) root._adding = ""
    }
    // By search: cards whose title or key hold the words typed.
    property int _pick: -1
    readonly property var _matches: root._adding.length > 0 && refField.text.trim().length >= 2
        && refField.text.indexOf("://") < 0 ? AppController.matchTasks(refField.text, 6, root.taskId) : []
    Repeater {
        id: suggestions
        model: root._matches
        delegate: Text {
            id: sug
            required property var modelData
            required property int index
            objectName: "task-doc-link-match-" + sug.index
            Layout.fillWidth: true
            text: sug.modelData.key + "  " + sug.modelData.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root._pick === sug.index || sugCA.hovered ? Theme.text : Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
            ClickArea {
                id: sugCA
                label: sug.text
                onActivated: {
                    refField.text = sug.modelData.id;
                    refField.accepted();
                }
            }
        }
    }
}
