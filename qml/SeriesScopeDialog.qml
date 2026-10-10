pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// "This event, this and following, or all events?" (X-Dlg-Event) — asked
// when one occurrence of a series is moved, re-ruled or deleted, because
// every wrong answer is a quiet data loss.
//
//   Перенести повторяющуюся встречу
//   «1:1 с Олегом», пт 11:00 → пт 14:00
//   ( ) Только эту встречу
//   ( ) Эту и следующие
//   ( ) Все в серии
//                               [Отмена Esc] [Перенести ↵]
//
// One component for the event panel and a drag or resize on the grids. The
// default is "This event" — the answer that changes least — so Return is
// always safe. Esc (or a click outside) cancels, and the caller puts a drag
// back.
//
//   SeriesScopeDialog { id: scope }
//   scope.ask("move", (answer) => AppController.moveOccurrence(occ, dh, answer),
//             () => block.reset(), "«1:1», пт 11:00 → пт 14:00")
Popup {
    id: root
    objectName: "series-scope"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: 0
    width: 400
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // "save" | "delete" | "move" — the title and the main button.
    property string mode: "save"
    property string fact: ""
    property string choice: "this"
    property var _onAnswer: null
    property var _onCancel: null
    property bool _answered: false

    readonly property string title: root.mode === "delete" ? I18n.t("repeat.scope.deleteTitle")
         : root.mode === "move" ? I18n.t("repeat.scope.moveTitle")
         : I18n.t("repeat.scope.saveTitle")

    function ask(mode, onAnswer, onCancel, fact) {
        root.mode = mode;
        root.fact = fact || "";
        root.choice = "this";
        root._onAnswer = onAnswer || null;
        root._onCancel = onCancel || null;
        root._answered = false;
        root.open();
        okBtn.forceActiveFocus();
    }
    function answer(scope) {
        root._answered = true;
        const cb = root._onAnswer;
        root.close();
        if (cb) cb(scope);
    }

    onClosed: {
        if (!root._answered && root._onCancel) root._onCancel();
        root._onAnswer = null;
        root._onCancel = null;
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: root.opened
        onActivated: root.answer(root.choice)
    }
    Shortcut { sequence: "Up"; enabled: root.opened; onActivated: root.choice = root.choice === "all" ? "following" : "this" }
    Shortcut { sequence: "Down"; enabled: root.opened; onActivated: root.choice = root.choice === "this" ? "following" : "all" }

    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: 0
        Text {
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: root.title
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
            wrapMode: Text.Wrap
        }
        Text {
            visible: root.fact.length > 0
            Layout.topMargin: Theme.spXs
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: root.fact
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
        ColumnLayout {
            Layout.topMargin: Theme.spLg
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            // 32px rows, no gap between them (X-Dlg-Event, R4-051).
            spacing: 0
            Repeater {
                model: ["this", "following", "all"]
                delegate: Item {
                    id: opt
                    required property string modelData
                    readonly property bool on: root.choice === opt.modelData
                    objectName: "series-scope-" + opt.modelData
                    implicitWidth: optRow.implicitWidth
                    implicitHeight: Theme.px(32)
                    // Answers with this option (keyboard: pick, then Return).
                    function clicked() { root.answer(opt.modelData); }
                    RowLayout {
                        id: optRow
                        anchors.fill: parent
                        spacing: Theme.spMd
                        // A plain radio: the empty ring is drawn in
                        // the text colour so it reads on the panel.
                        Rectangle {
                            implicitWidth: Theme.px(14); implicitHeight: Theme.px(14)
                            radius: width / 2
                            color: "transparent"
                            border.width: opt.on ? 4 : 1.5
                            border.color: opt.on ? Theme.accent : Theme.textMuted
                        }
                        Text {
                            text: I18n.t("repeat.scope." + opt.modelData)
                            color: Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsMd
                        }
                    }
                    ClickArea {
                        label: I18n.t("repeat.scope." + opt.modelData)
                        role: Accessible.RadioButton
                        checkable: true
                        checked: opt.on
                        onActivated: root.choice = opt.modelData
                    }
                }
            }
        }
        RowLayout {
            Layout.margins: Theme.inset
            Layout.fillWidth: true
            spacing: Theme.spMd
            Item { Layout.fillWidth: true }
            PillButton {
                objectName: "series-scope-cancel"
                text: I18n.t("common.cancel")
                shortcutId: ""
                keyHint: "Esc"
                onClicked: root.close()
            }
            PillButton {
                id: okBtn
                objectName: "series-scope-ok"
                primary: true
                danger: root.mode === "delete"
                // The one filled button of the dialog in bold (R3-073).
                solid: Style.fills && root.mode !== "delete"
                text: root.mode === "delete" ? I18n.t("common.delete")
                    : root.mode === "move" ? I18n.t("repeat.scope.moveBtn") : I18n.t("editor.btn.save")
                keyHint: "↵"
                onClicked: root.answer(root.choice)
            }
        }
    }
    // Kept for callers that look the footer up.
    readonly property Item footer: root.contentItem
}
