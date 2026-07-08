// First-run welcome. An interactive, multi-step guide (carousel) that tours
// heap's views, hotkeys and headline features. It can be skipped at any point
// (both the ✕ and the Skip button call AppController.markWelcomeSeen() so it is
// never shown again), and replayed on demand from Settings → Help. Per-step
// "open →" actions jump to the real surface; "Learn more →" deep-links into the
// full Settings → Help document.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: 600
    anchors.centerIn: Overlay.overlay

    // A step wants Main.qml to open a popup / editor it owns (palette, quick
    // capture, hotkeys panel, new-task editor). Kept as a signal so this popup
    // stays decoupled from those objects.
    signal openAction(string id)
    // A step's "Learn more" wants Main.qml to jump to Settings → Help at `anchor`.
    signal openHelp(string anchor)

    property int step: 0
    // Always start from the top — matters for replay from Settings → Help.
    onAboutToShow: step = 0

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.6)
    }

    background: Rectangle {
        radius: 14
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    // ── Step model ───────────────────────────────────────────────────────
    // Each step: glyph badge, title/desc i18n keys, live hotkey chips (ids from
    // AppController's rebindable catalog), an optional primary action, and an
    // optional Help anchor for "Learn more".
    //   action.kind: "view"   → set AppController.currentView = arg
    //                "action" → emit openAction(arg), handled in Main.qml
    readonly property var steps: [
        { glyph: "✦", title: "welcome.title", desc: "welcome.subtitle",
          keys: [], action: null, help: "" },
        { glyph: "▦", title: "welcome.views.title", desc: "welcome.views.desc",
          keys: ["view.board", "view.timeline", "view.week", "view.docs", "view.notes", "view.settings"],
          action: { label: "welcome.act.board", kind: "view", arg: "board" }, help: "help-views" },
        { glyph: "✎", title: "welcome.tasks.title", desc: "welcome.tasks.desc",
          keys: ["task.new"],
          action: { label: "welcome.act.task", kind: "action", arg: "task-new" }, help: "help-tasks" },
        { glyph: "⚡", title: "welcome.capture.title", desc: "welcome.capture.body",
          keys: ["quick-capture", "quick-capture-notes"],
          action: { label: "welcome.act.capture", kind: "action", arg: "quick-capture" }, help: "help-capture" },
        { glyph: "◷", title: "welcome.calendar.title", desc: "welcome.calendar.body",
          keys: [], action: null, help: "help-calendar" },
        { glyph: "⌘", title: "welcome.search.title", desc: "welcome.search.desc",
          keys: ["palette.open", "search.focus"],
          action: { label: "welcome.act.palette", kind: "action", arg: "palette" }, help: "help-search" },
        { glyph: "⌨", title: "welcome.keys.title", desc: "welcome.keys.desc",
          keys: ["tweaks.open", "hotkeys.open", "undo", "theme.toggle"],
          action: { label: "welcome.act.hotkeys", kind: "action", arg: "hotkeys" }, help: "help-hotkeys" },
        { glyph: "◐", title: "welcome.data.title", desc: "welcome.data.desc",
          keys: ["profile.next", "profile.prev"], action: null, help: "help-data" }
    ]

    readonly property var cur: steps[step]
    readonly property bool lastStep: step === steps.length - 1

    function _finish() {
        AppController.markWelcomeSeen();
        root.close();
    }
    function _next() {
        if (lastStep)
            _finish();
        else
            step++;
    }
    function _back() {
        if (step > 0)
            step--;
    }
    function _doAction(a) {
        // Finish first, then jump — a modal must never cover the surface it opens.
        _finish();
        if (a.kind === "view")
            AppController.currentView = a.arg;
        else if (a.kind === "action")
            root.openAction(a.arg);
    }
    function _learnMore(anchor) {
        _finish();
        root.openHelp(anchor);
    }

    // One rebindable-hotkey chip: live combo + its label. Hidden when the combo
    // is unset so a cleared binding does not leave an empty pill.
    component KeyChip: Rectangle {
        id: chip
        property string sid: ""
        readonly property string combo: AppController.shortcutFor(sid)
        visible: combo !== ""
        radius: 6
        color: Theme.panel2
        border.color: Theme.border
        border.width: 1
        implicitHeight: 24
        implicitWidth: chipRow.implicitWidth + 16
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: chip.combo
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            Text {
                text: AppController.shortcutLabel(chip.sid)
                color: Theme.textMuted
                font.pixelSize: 11
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Header: glyph + title + progress dots + close ──
        RowLayout {
            Layout.topMargin: 20
            Layout.leftMargin: 22
            Layout.rightMargin: 18
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 38; height: 38; radius: 9
                color: Theme.panel2
                border.color: Theme.border; border.width: 1
                Text { anchors.centerIn: parent; text: root.cur.glyph; color: Theme.accentStrong; font.pixelSize: 19 }
            }

            Text {
                Layout.fillWidth: true
                text: I18n.t(root.cur.title)
                color: Theme.text
                font.pixelSize: 18
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            // Progress dots.
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 5
                Repeater {
                    model: root.steps.length
                    delegate: Rectangle {
                        required property int index
                        width: index === root.step ? 16 : 6
                        height: 6
                        radius: 3
                        color: index <= root.step ? Theme.accent : Theme.border
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }
            }

            // Close = opt out (marks welcome seen).
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 26; height: 26; radius: 6
                color: closeMa.containsMouse ? Theme.panel2 : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: Theme.textMuted; font.pixelSize: 13 }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._finish()
                }
            }
        }

        // ── Body (fixed height so the frame doesn't jump between steps) ──
        Item {
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.preferredHeight: 232
            clip: true

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 14

                Text {
                    Layout.fillWidth: true
                    text: I18n.t(root.cur.desc)
                    color: Theme.textMuted
                    font.pixelSize: 13
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                // Live, rebindable hotkey chips for this step.
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.cur.keys.length > 0
                    Repeater {
                        model: root.cur.keys
                        delegate: KeyChip {
                            required property var modelData
                            sid: modelData
                        }
                    }
                }

                // Actions row: optional "open →" and "Learn more →".
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 14

                    PillButton {
                        visible: root.cur.action !== null
                        text: root.cur.action ? I18n.t(root.cur.action.label) : ""
                        onClicked: if (root.cur.action) root._doAction(root.cur.action)
                    }

                    Text {
                        visible: root.cur.help !== ""
                        text: I18n.t("welcome.learnMore")
                        color: learnMa.containsMouse ? Theme.accent : Theme.accentStrong
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        MouseArea {
                            id: learnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._learnMore(root.cur.help)
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
            Layout.margins: 16
            spacing: 8

            PillButton {
                text: I18n.t("welcome.skip")
                onClicked: root._finish()
            }
            Item { Layout.fillWidth: true }
            PillButton {
                visible: root.step > 0
                text: I18n.t("welcome.back")
                onClicked: root._back()
            }
            PillButton {
                text: root.lastStep ? I18n.t("welcome.getStarted") : I18n.t("welcome.next")
                primary: true
                onClicked: root._next()
            }
        }
    }
}
