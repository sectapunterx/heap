pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// The first run (APP-271): instead of a tour, an empty Today with the one
// input right on the page — one line, one task, the date, time and priority
// read from it the way Ctrl N reads them — the keys to know, and where tasks
// that already exist elsewhere come from. The example is a profile of its
// own; nothing here touches the person's tasks.
//
// Bold (H2-First): a heading, an emphasized box, three key cards, buttons.
// Quiet (Q-First, DG-111): a label, an underline input, two hint lines and
// three text links.
Item {
    id: root
    objectName: "first-run"

    signal created(string taskId)
    signal connectRequested()
    signal importRequested()
    signal exampleRequested()

    readonly property bool quiet: !Style.fills

    implicitHeight: col.implicitHeight

    function focusInput() { input.forceActiveFocus(); }

    // "Ctrl+K" as keymap.md writes it: "Ctrl K".
    function _keys(id, fallback) {
        const seq = AppController.shortcuts.length >= 0 ? AppController.shortcutFor(id) : "";
        const s = String(seq || fallback).split(", ")[0];
        return s.replace(/\+(?=.)/g, " ");
    }

    // The same draft Ctrl N saves: title, "when", deadline, priority, labels.
    function submit() {
        const raw = input.text.trim();
        if (raw.length === 0) return "";
        const draft = AppController.quickTaskDraft(raw, new Date());
        if (String(draft.title).length === 0) return "";
        AppController.saveTask(draft);
        AppController.markWelcomeSeen();
        input.text = "";
        root.created(draft.id);
        return draft.id;
    }

    ColumnLayout {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, Theme.px(root.quiet ? 560 : 640))
        spacing: 0

        Text {
            objectName: "first-run-title"
            Layout.fillWidth: true
            text: I18n.t("first.title")
            color: root.quiet ? Theme.textMuted : Theme.text
            font.family: Theme.fontUi
            font.pixelSize: root.quiet ? Theme.fsLg : Theme.fsXl
            font.weight: root.quiet ? Theme.fwBody : Theme.fwHeading
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Text {
            visible: !root.quiet
            Layout.fillWidth: true
            Layout.topMargin: Theme.spSm
            text: I18n.t("first.sub")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            wrapMode: Text.WordWrap
        }

        // The input, on the page: an emphasized box in bold, a line under
        // the words in quiet.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: root.quiet ? Theme.spLg : Theme.spXl
            implicitHeight: root.quiet ? Theme.px(44) : Theme.px(50)
            radius: root.quiet ? 0 : Theme.radiusXl
            color: root.quiet ? "transparent" : Theme.bg2
            border.width: root.quiet ? 0 : 1
            // Only real focus looks active: the brightest edge at rest read
            // as a caret that was not there (PERSONA-2).
            border.color: input.activeFocus ? Theme.focusRing : Theme.borderStrong
            Rectangle {
                visible: root.quiet
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: input.activeFocus ? Theme.focusRing : Theme.borderStrong
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.quiet ? 0 : Theme.spXl
                anchors.rightMargin: root.quiet ? 0 : Theme.spXl
                spacing: Theme.spMd
                QQC.TextField {
                    id: input
                    objectName: "first-run-input"
                    Layout.fillWidth: true
                    leftPadding: root.quiet ? Theme.spXs : 0
                    background: Item {}
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: root.quiet ? Theme.fsXl : Theme.px(16)
                    placeholderText: I18n.t(root.quiet ? "first.q.placeholder" : "first.placeholder")
                    // Bold draws its own two-tone placeholder below (R4-007).
                    placeholderTextColor: root.quiet ? Theme.textDim : "transparent"
                    selectByMouse: true
                    Accessible.name: I18n.t("first.title")
                    onAccepted: root.submit()
                    // H2-First: "например:" muted, the example brighter.
                    Text {
                        objectName: "first-run-placeholder"
                        visible: !root.quiet && input.text.length === 0 && !input.preeditText
                        anchors.left: parent.left
                        anchors.leftMargin: input.leftPadding
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property string _all: I18n.t("first.placeholder")
                        readonly property int _cut: _all.indexOf(":") + 1
                        text: "<font color=\"" + Theme.textDim + "\">" + _all.slice(0, _cut) + "</font>" + _all.slice(_cut)
                        textFormat: Text.StyledText
                        elide: Text.ElideRight
                        color: Theme.textMuted
                        font: input.font
                        Accessible.ignored: true
                    }
                }
                Text {
                    visible: !root.quiet
                    text: "Enter"
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsXs
                    Accessible.ignored: true
                }
            }
        }

        // Quiet: two lines of hints instead of the cards.
        Text {
            visible: root.quiet
            Layout.fillWidth: true
            Layout.topMargin: Theme.spLg
            text: I18n.t("first.q.hintSave")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            lineHeight: 1.5
            wrapMode: Text.WordWrap
        }
        Text {
            visible: root.quiet
            Layout.fillWidth: true
            text: I18n.t("first.q.hintKeys")
                  .arg("<font face=\"" + Theme.fontMono + "\" color=\"" + Theme.textMuted + "\">" + root._keys("palette.open", "Ctrl+K") + "</font>")
                  .arg("<font face=\"" + Theme.fontMono + "\" color=\"" + Theme.textMuted + "\">" + root._keys("hotkeys.open.alt", "?") + "</font>")
            textFormat: Text.StyledText
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            lineHeight: 1.5
            wrapMode: Text.WordWrap
        }

        // Bold: three keys, always shown here: this is where they are learnt.
        RowLayout {
            visible: !root.quiet
            Layout.fillWidth: true
            // H2-First: 28px above and below the cards, 14px inside (R4-008).
            Layout.topMargin: Theme.sp2xl + Theme.spXl
            spacing: Theme.spLg
            Repeater {
                model: [
                    { keys: root._keys("palette.open", "Ctrl+K"), text: I18n.t("first.key.palette") },
                    { keys: root._keys("task.done", "D").toLowerCase(), text: I18n.t("first.key.done") },
                    { keys: root._keys("hotkeys.open.alt", "?"), text: I18n.t("first.key.keys") }
                ]
                delegate: Rectangle {
                    id: keyCard
                    required property var modelData
                    objectName: "first-run-key"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    implicitHeight: keyCol.implicitHeight + 2 * (Theme.spLg + Theme.spXs)
                    radius: Theme.radiusLg
                    color: Theme.surfaceCard
                    ColumnLayout {
                        id: keyCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spLg + Theme.spXs
                        spacing: Theme.spSm
                        Text {
                            text: keyCard.modelData.keys
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsMd
                        }
                        Text {
                            Layout.fillWidth: true
                            text: keyCard.modelData.text
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsSm
                            lineHeight: 1.2
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: !root.quiet
            Layout.fillWidth: true
            Layout.topMargin: Theme.sp2xl + Theme.spXl
            implicitHeight: 1
            color: Theme.border
        }

        // Tasks that already live somewhere else: buttons in bold, words in
        // quiet.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: root.quiet ? Theme.px(60) : Theme.spXl
            spacing: root.quiet ? Theme.spXl : Theme.spMd
            Text {
                visible: !root.quiet
                Layout.fillWidth: true
                text: I18n.t("first.elsewhere")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                wrapMode: Text.WordWrap
            }
            PillButton {
                objectName: "first-run-connect"
                visible: !root.quiet
                text: I18n.t("first.connect")
                onClicked: root.connectRequested()
            }
            PillButton {
                objectName: "first-run-import"
                visible: !root.quiet
                text: I18n.t("first.import")
                onClicked: root.importRequested()
            }
            QuietLink { visible: root.quiet; text: I18n.t("first.q.connect"); onActivated: root.connectRequested() }
            QuietLink { visible: root.quiet; text: I18n.t("first.q.import"); onActivated: root.importRequested() }
            QuietLink { visible: root.quiet; text: I18n.t("first.q.example"); onActivated: root.exampleRequested() }
            Item { visible: root.quiet; Layout.fillWidth: true }
        }
        QuietLink {
            objectName: "first-run-example"
            visible: !root.quiet
            Layout.topMargin: Theme.spLg
            text: I18n.t("first.example")
            color: Theme.textMuted
            onActivated: root.exampleRequested()
        }
    }

    component QuietLink: Text {
        id: ql
        signal activated()
        color: Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: root.quiet ? Theme.fsMd : Theme.fsSm
        font.underline: true
        ClickArea {
            label: ql.text
            role: Accessible.Link
            onActivated: ql.activated()
        }
    }
}
