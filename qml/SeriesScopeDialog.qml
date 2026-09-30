import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// "This event, this and following, or all events?" — the question every
// calendar asks when one occurrence of a series is changed, because every
// wrong answer is a quiet data loss.
//
// One component for the three places that ask it: the event editor's save and
// delete, and a drag or resize on the day and week grids. The default is
// "This event" — the answer that changes least — so Return is always safe.
// Esc (or a click outside) cancels, and the caller puts a drag back.
//
//   SeriesScopeDialog { id: scope }
//   scope.ask("move", (answer) => AppController.moveOccurrence(occ, dh, answer),
//             () => block.reset())
Dialog {
    id: root
    objectName: "series-scope"
    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: Theme.inset
    // Explicit, because the contentItem wraps: without a width of its own it
    // sizes from the dialog, which is sizing from it.
    width: 440
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // "save" | "delete" | "move" — only the title differs.
    property string mode: "save"
    property var _onAnswer: null
    property var _onCancel: null
    property bool _answered: false

    title: root.mode === "delete" ? I18n.t("repeat.scope.deleteTitle")
         : root.mode === "move" ? I18n.t("repeat.scope.moveTitle")
         : I18n.t("repeat.scope.saveTitle")

    function ask(mode, onAnswer, onCancel) {
        root.mode = mode;
        root._onAnswer = onAnswer || null;
        root._onCancel = onCancel || null;
        root._answered = false;
        root.open();
        thisBtn.forceActiveFocus();
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
        onActivated: root.answer("this")
    }

    header: DialogHeader { text: root.title }
    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: Text {
        text: I18n.t("repeat.scope.body")
        color: Theme.textMuted
        font.pixelSize: Theme.fsMd
        wrapMode: Text.Wrap
    }

    // Cancel as a button too, not only Esc / a click outside (design audit
    // DES-24: the dialog offered three answers and no way back).
    footer: DialogFooter {
        PillButton {
            objectName: "series-scope-cancel"
            text: I18n.t("common.cancel")
            onClicked: root.close()
        }
        Item { Layout.fillWidth: true }
        PillButton {
            objectName: "series-scope-all"
            text: I18n.t("repeat.scope.all")
            onClicked: root.answer("all")
        }
        PillButton {
            objectName: "series-scope-following"
            text: I18n.t("repeat.scope.following")
            onClicked: root.answer("following")
        }
        PillButton {
            id: thisBtn
            objectName: "series-scope-this"
            text: I18n.t("repeat.scope.this")
            primary: true
            onClicked: root.answer("this")
        }
    }
}
