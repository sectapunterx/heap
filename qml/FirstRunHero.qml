pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// The first run (APP-271, sheet H2-First): instead of a tour, an empty Today
// with the one input right on the page — one line, one task, the date, time
// and priority read from it the way Ctrl N reads them — three keys to know,
// and where tasks that already exist elsewhere come from. The example is a
// profile of its own; nothing here touches the person's tasks.
Item {
    id: root
    objectName: "first-run"

    signal created(string taskId)
    signal connectRequested()
    signal importRequested()
    signal exampleRequested()

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
        width: Math.min(parent.width, Theme.px(640))
        spacing: 0

        Text {
            objectName: "first-run-title"
            Layout.fillWidth: true
            text: I18n.t("first.title")
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXl
            font.weight: Theme.fwHeading
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spSm
            text: I18n.t("first.sub")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            wrapMode: Text.WordWrap
        }

        // The input, on the page.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.sp2xl
            implicitHeight: Theme.px(48)
            radius: Theme.radiusLg
            color: Theme.bg
            border.width: 1
            border.color: input.activeFocus ? Theme.focusRing : Theme.fieldBorder
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spXl
                anchors.rightMargin: Theme.spXl
                spacing: Theme.spMd
                QQC.TextField {
                    id: input
                    objectName: "first-run-input"
                    Layout.fillWidth: true
                    background: Item {}
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsLg
                    placeholderText: I18n.t("first.placeholder")
                    placeholderTextColor: Theme.textDim
                    selectByMouse: true
                    Accessible.name: I18n.t("first.title")
                    onAccepted: root.submit()
                }
                Text {
                    text: "↵"
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm
                    Accessible.ignored: true
                }
            }
        }

        // Three keys, always shown here: this is where they are learnt.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.sp2xl
            spacing: Theme.spLg
            Repeater {
                model: [
                    { keys: root._keys("palette.open", "Ctrl+K"), text: I18n.t("first.key.palette") },
                    { keys: root._keys("task.done", "D").toLowerCase(), text: I18n.t("first.key.done") },
                    { keys: root._keys("hotkeys.open", "?"), text: I18n.t("first.key.keys") }
                ]
                delegate: Rectangle {
                    id: keyCard
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: keyCol.implicitHeight + 2 * Theme.spXl
                    radius: Theme.radiusLg
                    color: Theme.surfaceCard
                    ColumnLayout {
                        id: keyCol
                        anchors.fill: parent
                        anchors.margins: Theme.spXl
                        spacing: Theme.spSm
                        KeyHint {
                            always: true
                            keys: keyCard.modelData.keys
                            color: Theme.text
                            font.pixelSize: Theme.fsSm
                        }
                        Text {
                            Layout.fillWidth: true
                            text: keyCard.modelData.text
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsSm
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.sp3xl
            implicitHeight: 1
            color: Theme.border
        }

        // Tasks that already live somewhere else.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.sp2xl
            spacing: Theme.spMd
            Text {
                Layout.fillWidth: true
                text: I18n.t("first.elsewhere")
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                wrapMode: Text.WordWrap
            }
            PillButton {
                objectName: "first-run-connect"
                text: I18n.t("first.connect")
                onClicked: root.connectRequested()
            }
            PillButton {
                objectName: "first-run-import"
                text: I18n.t("first.import")
                onClicked: root.importRequested()
            }
        }
        Text {
            id: exampleLink
            objectName: "first-run-example"
            Layout.topMargin: Theme.spLg
            text: I18n.t("first.example")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            font.underline: true
            ClickArea {
                label: exampleLink.text
                role: Accessible.Link
                onActivated: root.exampleRequested()
            }
        }
    }
}
