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
    // While true the tour is merely paused: the user tapped a step's "open →" /
    // "Learn more →" and jumped to a surface, so the guide hid itself instead of
    // finishing. Main shows a "Continue tour" pill bound to this and reopens the
    // popup at the same step. Distinct from finishing, which marks it seen.
    // Cleared every time the popup is shown (fresh open or resume). Callers that
    // start a fresh run set `step = 0` before open(); a resume leaves step as-is.
    property bool paused: false
    onAboutToShow: paused = false

    Overlay.modal: Rectangle {
        color: Theme.scrim
    }

    background: Rectangle {
        radius: Theme.radiusXl
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
    // A hint with the shortcuts as bound now, not as they shipped (design
    // audit DES-15): the keys are rebindable, the text was not.
    function withKeys(key, ids) {
        let text = I18n.t(key);
        const list = ids || [];
        for (let i = 0; i < list.length; i++) text = text.arg(AppController.shortcutFor(list[i]));
        return text;
    }
    readonly property var steps: [
        { glyph: "✦", title: "welcome.title", desc: "welcome.subtitle",
          keys: [], action: null, help: "",
          // The first page was one line over a blank frame; it now says what
          // the app is made of before the tour walks through each part.
          highlights: [
              { glyph: "▦", title: "welcome.board.title", desc: "welcome.board.desc", descText: I18n.t("welcome.board.desc") },
              { glyph: "◷", title: "welcome.calendar.title", desc: "welcome.calendar.desc", descText: I18n.t("welcome.calendar.desc") },
              { glyph: "↯", title: "welcome.capture.title", desc: "welcome.capture.desc", descText: root.withKeys("welcome.capture.desc", ["quick-capture"]) },
              { glyph: "⌘", title: "welcome.palette.title", desc: "welcome.palette.desc", descText: root.withKeys("welcome.palette.desc", ["palette.open"]) }
          ],
          note: "welcome.demoNote" },
        { glyph: "▦", title: "welcome.views.title", desc: "welcome.views.desc",
          keys: ["view.board", "view.timeline", "view.week", "view.docs", "view.notes", "view.settings"],
          action: { label: "welcome.act.board", kind: "view", arg: "board" }, help: "help-views" },
        { glyph: "✎", title: "welcome.tasks.title", desc: "welcome.tasks.desc",
          keys: ["task.new"],
          action: { label: "welcome.act.task", kind: "action", arg: "task-new" }, help: "help-tasks" },
        { glyph: "↯", title: "welcome.capture.title", desc: "welcome.capture.body",
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
        // Real dismissal (Skip / Get started / giving up from the pill): mark it
        // seen so it never auto-shows again.
        root.paused = false;
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
        // Pause (do NOT finish) so the tour survives the detour: hide it, jump to
        // the surface, and let Main's "Continue tour" pill bring it back at the
        // same step. Never marks welcomeSeen here.
        root.paused = true;
        root.close();
        if (a.kind === "view")
            AppController.currentView = a.arg;
        else if (a.kind === "action")
            root.openAction(a.arg);
    }
    function _learnMore(anchor) {
        // Same pause-and-resume contract as _doAction — jumping into Help must
        // not throw the tour away.
        root.paused = true;
        root.close();
        root.openHelp(anchor);
    }

    // One rebindable-hotkey chip: live combo + its label. Hidden when the combo
    // is unset so a cleared binding does not leave an empty pill.
    component KeyChip: Rectangle {
        id: chip
        property string sid: ""
        readonly property string combo: AppController.shortcutFor(sid)
        visible: combo !== ""
        radius: Theme.radiusMd
        color: Theme.panel2
        border.color: Theme.border
        border.width: 1
        implicitHeight: 24
        implicitWidth: chipRow.implicitWidth + 16
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.spSm
            Text {
                text: chip.combo
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsSm
                font.weight: Font.DemiBold
            }
            Text {
                text: AppController.shortcutLabel(chip.sid)
                color: Theme.textMuted
                font.pixelSize: Theme.fsSm
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        // The guide is a keyboard-first app's first screen, so it has to be
        // drivable from the keyboard: ←/→ walk the steps, Enter advances (and
        // finishes on the last one), Esc opts out exactly like the ✕.
        focus: true
        Keys.onEscapePressed: root._finish()
        Keys.onLeftPressed:   root._back()
        Keys.onRightPressed:  root._next()
        Keys.onReturnPressed: root._next()
        Keys.onEnterPressed:  root._next()

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
                Layout.fillWidth: true
                text: I18n.t(root.cur.title)
                color: Theme.text
                font.pixelSize: Theme.fsXl
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            // Progress dots.
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
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }
            }

            // Close = opt out (marks welcome seen).
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 26; height: 26; radius: Theme.radiusMd
                color: closeMa.containsMouse ? Theme.panel2 : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: Theme.textMuted; font.pixelSize: Theme.fsMd }
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
            Layout.topMargin: Theme.sp2xl
            Layout.preferredHeight: 232
            clip: true

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Theme.sp3xl
                anchors.rightMargin: Theme.sp3xl
                spacing: Theme.sp2xl

                Text {
                    Layout.fillWidth: true
                    text: I18n.t(root.cur.desc)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fsMd
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                // What heap is made of — the first page only.
                GridLayout {
                    objectName: "welcome-highlights"
                    Layout.fillWidth: true
                    visible: !!root.cur.highlights
                    columns: 2
                    columnSpacing: Theme.sp2xl
                    rowSpacing: Theme.spLg
                    Repeater {
                        model: root.cur.highlights || []
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            spacing: Theme.spMd
                            Text {
                                Layout.alignment: Qt.AlignTop
                                text: modelData.glyph
                                color: Theme.accentStrong
                                font.pixelSize: Theme.fsLg
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.sp2xs
                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.t(modelData.title)
                                    color: Theme.text
                                    font.pixelSize: Theme.fsMd
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.descText
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fsSm
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!root.cur.note
                    text: root.cur.note ? I18n.t(root.cur.note) : ""
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm
                    wrapMode: Text.WordWrap
                }

                // Live, rebindable hotkey chips for this step.
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spMd
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
                    Layout.topMargin: Theme.sp2xs
                    spacing: Theme.sp2xl

                    PillButton {
                        visible: root.cur.action !== null
                        text: root.cur.action ? I18n.t(root.cur.action.label) : ""
                        onClicked: if (root.cur.action) root._doAction(root.cur.action)
                    }

                    Text {
                        visible: root.cur.help !== ""
                        text: I18n.t("welcome.learnMore")
                        color: learnMa.containsMouse ? Theme.accent : Theme.accentStrong
                        font.pixelSize: Theme.fsMd
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
            Layout.margins: Theme.sp2xl
            spacing: Theme.spMd

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
