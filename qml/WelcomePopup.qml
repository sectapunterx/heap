// First-run tour (APP-169): four short steps, all from the keyboard — Enter
// moves on, Esc skips, ←/→ step back and forth.
//   1. Your first task: a real capture field; what is typed is saved as a
//      task on Enter. Nothing is ever filled in for the user.
//   2. Views and the command palette.
//   3. Keys: ? for the cheat-sheet, H/J/K/L on the board.
//   4. Bring your stuff: import a markdown folder or a profile, connect a
//      tracker — each only when the user picks it.
// Skipping or finishing marks it seen (AppController.markWelcomeSeen), so it
// never shows again by itself; Settings → Help replays it. A step's action
// pauses the tour instead, and Main's "Continue tour" pill brings it back.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp
import "PopupStack.js" as PopupStack
import "Tour.js" as Tour

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: 600
    anchors.centerIn: Overlay.overlay

    // A step wants Main.qml to open something it owns: "palette", "hotkeys",
    // "vault-import", "profile-import", "integrations".
    signal openAction(string id)
    // A step's "Learn more" wants Main.qml to jump to Settings → Help at `anchor`.
    signal openHelp(string anchor)

    property int step: 0
    // Paused, not finished: the user took a step's action and left for that
    // surface. Main shows a "Continue tour" pill bound to this.
    property bool paused: false
    onAboutToShow: paused = false
    onOpened: root._focusStep()
    onStepChanged: if (root.opened) Qt.callLater(root._focusStep)

    // Titles of the tasks saved from the capture step in this run.
    property var captured: []
    property string lastCapturedId: ""

    Overlay.modal: ModalScrim {}
    // A press beside the tour ends it like ✕ and Esc do (APP-126).
    Overlay.onPressed: if (PopupStack.isTopmost(root, Overlay.overlay) && PopupStack.pressedOutside(root, AppController.lastPressGlobalPos())) root._finish()

    background: ModalSurface {}

    // A hint with the shortcuts as bound now, not as they shipped (DES-15).
    function withKeys(key, ids) {
        let text = I18n.t(key);
        const list = ids || [];
        for (let i = 0; i < list.length; i++) text = text.arg(AppController.shortcutFor(list[i]));
        return text;
    }

    readonly property var steps: [
        { id: "capture", glyph: "↯", title: "welcome.tour.capture.title", desc: "welcome.tour.capture.desc",
          keys: [], action: null, help: "help-capture" },
        { id: "views", glyph: "▦", title: "welcome.tour.views.title", desc: "welcome.tour.views.desc",
          keys: ["view.board", "view.timeline", "view.week", "view.notes", "palette.open"],
          action: { label: "welcome.act.palette", kind: "action", arg: "palette" }, help: "help-views" },
        { id: "keys", glyph: "⌨", title: "welcome.tour.keys.title", desc: "welcome.tour.keys.desc",
          keys: ["board.cursorLeft", "board.cursorDown", "board.cursorUp", "board.cursorRight", "board.open"],
          action: { label: "welcome.act.hotkeys", kind: "action", arg: "hotkeys" }, help: "help-hotkeys" },
        { id: "bring", glyph: "⇣", title: "welcome.tour.bring.title", desc: "welcome.tour.bring.desc",
          keys: [], action: null, help: "help-data" }
    ]

    readonly property var cur: steps[Math.max(0, Math.min(steps.length - 1, step))]
    readonly property bool lastStep: step === steps.length - 1

    function _focusStep() {
        if (root.cur.id === "capture") captureField.forceActiveFocus();
        else body.forceActiveFocus();
    }

    // One key through the tour's state machine (Tour.js).
    function handleKey(key) {
        const r = Tour.onKey(root.step, key, captureField.text);
        switch (r.action) {
        case "save":   root._saveCapture(); break;
        case "next":
        case "back":   root.step = r.step; break;
        case "finish":
        case "skip":   root._finish(); break;
        }
        return r.action !== "none";
    }

    // The capture step's text, saved as a real task in To Do, read the way
    // every task input reads it (APP-266): "tomorrow at 15:00 p1" is a date
    // and a priority, not part of the title.
    function _saveCapture() {
        const typed = captureField.text.trim();
        if (typed.length === 0) return false;
        const draft = AppController.quickTaskDraft(typed, new Date());
        const title = String(draft.title);
        if (title.length === 0) return false;
        if (!AppController.saveTask(draft)) return false;
        root.captured = root.captured.concat([title]);
        root.lastCapturedId = draft.id;
        captureField.text = "";
        return true;
    }

    function _finish() {
        root.paused = false;
        AppController.markWelcomeSeen();
        root.close();
    }
    // Next with something typed on the capture step keeps it: the button
    // must not throw away what Enter would have saved.
    function _next() {
        if (root.cur.id === "capture" && captureField.text.trim().length > 0) root._saveCapture();
        root.handleKey(root.lastStep ? "enter" : "right");
    }
    function _back() { root.handleKey("left"); }
    function _doAction(a) {
        // Pause (do NOT finish) so the tour survives the detour.
        root.paused = true;
        root.close();
        if (a.kind === "view")
            AppController.currentView = a.arg;
        else if (a.kind === "action")
            root.openAction(a.arg);
    }
    function _learnMore(anchor) {
        root.paused = true;
        root.close();
        root.openHelp(anchor);
    }

    // One rebindable-hotkey chip: live combo + its label. Hidden when unset.
    component KeyChip: Rectangle {
        id: chip
        property string sid: ""
        // A key that is not in the catalogue (the `?` of the cheat-sheet).
        property string fixedKey: ""
        property string fixedLabel: ""
        readonly property string combo: chip.fixedKey.length > 0 ? chip.fixedKey : AppController.shortcutFor(sid)
        visible: combo !== ""
        radius: Theme.radiusMd
        color: Theme.panel2
        border.color: Theme.border
        border.width: 1
        implicitHeight: chipRow.implicitHeight + 2 * Theme.spXs
        implicitWidth: chipRow.implicitWidth + 2 * Theme.spMd
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.spSm
            Text {
                text: chip.combo
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsSm
                font.weight: Theme.fwTitle
            }
            Text {
                text: chip.fixedLabel.length > 0 ? chip.fixedLabel : AppController.shortcutLabel(chip.sid)
                color: Theme.textMuted
                font.pixelSize: Theme.fsSm
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0
        focus: true
        Keys.onEscapePressed: root.handleKey("esc")
        Keys.onLeftPressed: root.handleKey("left")
        Keys.onRightPressed: root.handleKey("right")
        Keys.onReturnPressed: root.handleKey("enter")
        Keys.onEnterPressed: root.handleKey("enter")

        // ── Header: glyph + title + progress dots + close ──
        RowLayout {
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.sp3xl
            Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            spacing: Theme.spXl

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 38; height: 38; radius: Theme.radiusLg
                color: Theme.panel2
                border.color: Theme.border; border.width: 1
                Text { anchors.centerIn: parent; text: root.cur.glyph; color: Theme.accentStrong; font.pixelSize: Theme.fsXl }
            }

            Text {
                objectName: "welcome-title"
                Layout.fillWidth: true
                text: I18n.t(root.cur.title)
                color: Theme.text
                font.pixelSize: Theme.fsXl
                font.weight: Theme.fwHeading
                elide: Text.ElideRight
            }

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.spXs
                Repeater {
                    model: root.steps.length
                    delegate: Rectangle {
                        required property int index
                        width: index === root.step ? 16 : 6
                        height: 6
                        radius: 3
                        color: index <= root.step ? Theme.accent : Theme.border
                        Behavior on width { NumberAnimation { duration: Theme.durTap; easing.type: Theme.easeEnter } }
                    }
                }
            }

            // Close = opt out (marks the tour seen).
            Rectangle {
                objectName: "welcome-close"
                Layout.alignment: Qt.AlignVCenter
                width: 22; height: 22; radius: Theme.radiusSm
                color: closeMa.hovered ? Theme.panel3 : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: closeMa.hovered ? Theme.text : Theme.textDim; font.pixelSize: Theme.fsSm }
                ClickArea {
                    id: closeMa
                    label: I18n.t("welcome.skip")
                    onActivated: root._finish()
                }
            }
        }

        // ── Body: as tall as the step's content (APP-201). A fixed 212px
        // left a blank band under "Learn more" on the short steps; the
        // height eases between steps instead of jumping. ──
        Item {
            id: body
            objectName: "welcome-body"
            Layout.fillWidth: true
            Layout.topMargin: Theme.sp2xl
            Layout.bottomMargin: Theme.sp2xl
            property real contentHeight: bodyCol.implicitHeight
            Behavior on contentHeight { NumberAnimation { duration: Theme.durMove; easing.type: Theme.easeEnter } }
            Layout.preferredHeight: contentHeight
            clip: true
            activeFocusOnTab: false

            ColumnLayout {
                id: bodyCol
                objectName: "welcome-body-content"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Theme.sp3xl
                anchors.rightMargin: Theme.sp3xl
                spacing: Theme.spXl

                Text {
                    objectName: "welcome-desc"
                    Layout.fillWidth: true
                    text: I18n.t(root.cur.desc)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fsMd
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                // 1 · the capture field: a real task on Enter.
                TextField {
                    id: captureField
                    objectName: "welcome-capture-field"
                    visible: root.cur.id === "capture"
                    Layout.fillWidth: true
                    placeholderText: I18n.t("welcome.tour.capture.ph")
                    placeholderTextColor: Theme.textDim
                    color: Theme.text
                    font.pixelSize: Theme.fsMd
                    selectByMouse: true
                    Accessible.name: I18n.t("welcome.tour.capture.title")
                    background: FieldFrame { border.color: captureField.activeFocus ? Theme.focusRing : Theme.fieldBorder }
                    Keys.onReturnPressed: (event) => { root.handleKey("enter"); event.accepted = true; }
                    Keys.onEnterPressed: (event) => { root.handleKey("enter"); event.accepted = true; }
                }
                Text {
                    objectName: "welcome-capture-saved"
                    visible: root.cur.id === "capture" && root.captured.length > 0
                    Layout.fillWidth: true
                    text: root.captured.length > 0
                          ? I18n.t("welcome.tour.capture.saved").arg(root.captured[root.captured.length - 1]) : ""
                    textFormat: Text.PlainText
                    color: Theme.success
                    font.pixelSize: Theme.fsSm
                    wrapMode: Text.WordWrap
                }
                Text {
                    visible: root.cur.id === "capture"
                    Layout.fillWidth: true
                    text: root.withKeys("welcome.capture.desc", ["quick-capture"])
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm
                    wrapMode: Text.WordWrap
                }
                Text {
                    visible: root.cur.id === "views"
                    Layout.fillWidth: true
                    text: root.withKeys("welcome.palette.desc", ["palette.open"])
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm
                    wrapMode: Text.WordWrap
                }

                // Live, rebindable hotkey chips for this step.
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spMd
                    visible: root.cur.keys.length > 0
                    KeyChip {
                        visible: root.cur.id === "keys"
                        fixedKey: "?"
                        fixedLabel: I18n.t("hotkeys.title")
                    }
                    Repeater {
                        model: root.cur.keys
                        delegate: KeyChip {
                            required property var modelData
                            sid: modelData
                        }
                    }
                }

                // 4 · bring your stuff — each one only when picked.
                Flow {
                    objectName: "welcome-bring"
                    visible: root.cur.id === "bring"
                    Layout.fillWidth: true
                    spacing: Theme.spMd
                    PillButton {
                        objectName: "welcome-bring-vault"
                        text: I18n.t("welcome.tour.bring.vault")
                        onClicked: root._doAction({ kind: "action", arg: "vault-import" })
                    }
                    PillButton {
                        objectName: "welcome-bring-profile"
                        text: I18n.t("welcome.tour.bring.profile")
                        onClicked: root._doAction({ kind: "action", arg: "profile-import" })
                    }
                    PillButton {
                        objectName: "welcome-bring-integrations"
                        text: I18n.t("welcome.tour.bring.integrations")
                        onClicked: root._doAction({ kind: "action", arg: "integrations" })
                    }
                }

                // Optional "open →" and "Learn more →".
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.sp2xl

                    PillButton {
                        visible: root.cur.action !== null
                        text: root.cur.action ? I18n.t(root.cur.action.label) : ""
                        onClicked: if (root.cur.action) root._doAction(root.cur.action)
                    }

                    Text {
                        visible: root.cur.help !== ""
                        text: I18n.t("welcome.learnMore")
                        color: Theme.accentStrong
                        font.underline: learnMa.hovered
                        font.pixelSize: Theme.fsMd
                        font.weight: Theme.fwTitle
                        ClickArea {
                            id: learnMa
                            label: I18n.t("welcome.learnMore")
                            showTip: false
                            onActivated: root._learnMore(root.cur.help)
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }

        // ── Footer ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.sp2xl
            spacing: Theme.spMd

            PillButton {
                text: I18n.t("welcome.skip")
                onClicked: root._finish()
            }
            Text {
                text: I18n.t("welcome.tour.footer")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsXs
            }
            Item { Layout.fillWidth: true }
            PillButton {
                visible: root.step > 0
                text: I18n.t("welcome.back")
                onClicked: root._back()
            }
            PillButton {
                objectName: "welcome-next"
                text: root.lastStep ? I18n.t("welcome.getStarted") : I18n.t("welcome.next")
                primary: true
                onClicked: root._next()
            }
        }
    }
}
