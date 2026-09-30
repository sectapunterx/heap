import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls.impl
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    // Expanded shows a label next to every icon and names the groups; the
    // collapsed form is the original 56px icon rail. Main owns the state and
    // persists it — this only draws it.
    property bool expanded: true
    readonly property int expandedWidth: 216
    readonly property int collapsedWidth: 56
    // implicitWidth, not width: a Layout writes width itself, which would
    // break a binding on it.
    implicitWidth: expanded ? expandedWidth : collapsedWidth
    Behavior on implicitWidth { NumberAnimation { duration: Theme.scaledMs(120); easing.type: Easing.OutCubic } }
    clip: true

    signal openTweaks(Item anchor)
    signal openHotkeys(Item anchor)
    signal toggleRequested()

    // Expose anchors so Main can position popups when triggered via
    // shortcut (i.e. "as if the rail button had been clicked").
    property alias tweaksAnchor:  tweaksBtn
    property alias hotkeysAnchor: hotkeysBtn

    // Reactive badges. statusCounts is one pass over the model, recomputed
    // when it changes and shared with the top bar — these used to be two
    // separate full scans, repeated in all four handlers.
    readonly property int _blockedCount: AppController.statusCounts["blocked"] || 0
    readonly property int _reviewCount:  AppController.statusCounts["review"] || 0

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1; color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spLg
        anchors.leftMargin: Theme.spLg
        anchors.rightMargin: Theme.spLg
        spacing: Theme.sp2xs

        // Collapse / expand toggle
        RailBtn {
            expanded: root.expanded
            objectName: "rail-toggle"
            label: I18n.t("siderail.collapse")
            tooltipText: I18n.t("siderail.expand") + "  " + AppController.shortcutFor("rail.toggle")
            glyph: root.expanded ? "«" : "»"
            onActivated: root.toggleRequested()
            Layout.bottomMargin: Theme.spSm
        }

        SectionHead { expanded: root.expanded; text: I18n.t("siderail.section.views") }

        // View switcher
        RailBtn {
            expanded: root.expanded
            objectName: "rail-board"
            iconSource: "qrc:/brand/icons/heap-01-board.svg"
            label: I18n.t("siderail.board"); tooltipText: I18n.t("siderail.tip.board"); shortcutId: "view.board"
            active: AppController.currentView === "board"
            onActivated: AppController.currentView = "board" }
        RailBtn {
            expanded: root.expanded
            objectName: "rail-timeline"
            iconSource: "qrc:/brand/icons/heap-02-timeline.svg"
            label: I18n.t("siderail.timeline"); tooltipText: I18n.t("siderail.tip.timeline"); shortcutId: "view.timeline"
            active: AppController.currentView === "timeline"
            onActivated: AppController.currentView = "timeline" }
        RailBtn {
            expanded: root.expanded
            objectName: "rail-week"
            iconSource: "qrc:/brand/icons/heap-03-week.svg"
            label: I18n.t("siderail.week"); tooltipText: I18n.t("siderail.tip.week"); shortcutId: "view.week"
            active: AppController.currentView === "week"
            onActivated: AppController.currentView = "week" }
        RailBtn {
            expanded: root.expanded
            objectName: "rail-month"
            iconSource: "qrc:/brand/icons/heap-04-month.svg"
            label: I18n.t("siderail.month"); tooltipText: I18n.t("siderail.tip.month"); shortcutId: "view.month"
            active: AppController.currentView === "month"
            onActivated: AppController.currentView = "month" }
        RailBtn {
            expanded: root.expanded
            objectName: "rail-archive"
            iconSource: "qrc:/brand/icons/heap-05-archive.svg"
            label: I18n.t("siderail.archive"); tooltipText: I18n.t("siderail.tip.archive"); shortcutId: "view.archive"
            active: AppController.currentView === "archive"
            onActivated: AppController.currentView = "archive"
        }

        SectionHead { expanded: root.expanded; text: I18n.t("siderail.section.focus") }

        RailBtn {

            expanded: root.expanded
            objectName: "rail-blocked"
            iconSource: "qrc:/brand/icons/heap-06-blocked.svg"
            label: I18n.t("siderail.blocked"); tooltipText: I18n.t("siderail.tip.blocked")
            countText: root._blockedCount > 0 ? root._blockedCount : ""
            countColor: Theme.danger
            active: AppController.currentView === "board" && AppController.focusedStatus === "blocked"
            onActivated: AppController.focusStatusColumn("blocked") }
        RailBtn {
            expanded: root.expanded
            objectName: "rail-review"
            iconSource: "qrc:/brand/icons/heap-07-code-review.svg"
            label: I18n.t("siderail.review"); tooltipText: I18n.t("siderail.tip.review")
            countText: root._reviewCount > 0 ? root._reviewCount : ""
            countColor: Theme.accent
            active: AppController.currentView === "board" && AppController.focusedStatus === "review"
            onActivated: AppController.focusStatusColumn("review") }

        SectionHead { expanded: root.expanded; text: I18n.t("siderail.section.knowledge") }

        RailBtn {

            expanded: root.expanded
            objectName: "rail-docs"
            iconSource: "qrc:/brand/icons/heap-08-docs.svg"
            label: I18n.t("siderail.docs"); tooltipText: I18n.t("siderail.tip.docs"); shortcutId: "view.docs"
            active: AppController.currentView === "docs"
            onActivated: AppController.currentView = "docs" }
        RailBtn {
            expanded: root.expanded
            objectName: "rail-notes"
            iconSource: "qrc:/brand/icons/heap-09-notes.svg"
            label: I18n.t("siderail.notes"); tooltipText: I18n.t("siderail.tip.notes"); shortcutId: "view.notes"
            active: AppController.currentView === "notes"
            onActivated: AppController.currentView = "notes" }

        Item { Layout.fillHeight: true }

        RailBtn {

            expanded: root.expanded
            id: hotkeysBtn
            objectName: "rail-hotkeys"
            iconSource: "qrc:/brand/icons/heap-10-hotkeys.svg"
            label: I18n.t("siderail.hotkeys"); tooltipText: I18n.t("siderail.tip.hotkeys"); shortcutId: "hotkeys.open"
            onActivated: root.openHotkeys(hotkeysBtn)
        }
        RailBtn {
            expanded: root.expanded
            id: tweaksBtn
            objectName: "rail-tweaks"
            iconSource: "qrc:/brand/icons/heap-11-tweaks.svg"
            label: I18n.t("siderail.tweaks"); tooltipText: I18n.t("siderail.tip.tweaks"); shortcutId: "tweaks.open"
            onActivated: root.openTweaks(tweaksBtn)
        }
        RailBtn {
            expanded: root.expanded
            objectName: "rail-settings"
            iconSource: "qrc:/brand/icons/heap-12-settings.svg"
            label: I18n.t("siderail.settings"); tooltipText: I18n.t("siderail.tip.settings"); shortcutId: "view.settings"
            active: AppController.currentView === "settings"
            onActivated: AppController.currentView = "settings"
            Layout.bottomMargin: Theme.spLg
        }
    }

    // A group title when expanded; the old 24px hairline when collapsed, so
    // the rail keeps the same rhythm it always had.
    component SectionHead: Item {
        id: sh
        property string text
        property bool expanded: true
        Layout.fillWidth: true
        Layout.topMargin: Theme.spMd
        Layout.preferredHeight: sh.expanded ? 22 : 13
        Text {
            visible: sh.expanded
            anchors.left: parent.left; anchors.leftMargin: Theme.spMd
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: sh.text.toUpperCase()
            elide: Text.ElideRight
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
            font.weight: Font.DemiBold
            font.letterSpacing: 0.8
        }
        Rectangle {
            visible: !sh.expanded
            anchors.centerIn: parent
            width: 24; height: 1; color: Theme.border
        }
    }

    component RailBtn: Item {
        id: btn
        property bool expanded: true
        property url iconSource
        property string label: ""
        property string tooltipText: ""
        // The action's id in the shortcut catalog. Whatever it is bound to
        // now shows in the tooltip, and next to the label on hover, so the
        // rail teaches the keys instead of hiding them in the Hotkeys panel.
        property string shortcutId: ""
        readonly property string _combo: shortcutId.length && AppController.shortcuts.length >= 0
            ? AppController.shortcutFor(shortcutId) : ""
        // A text glyph in place of the icon (the collapse chevron).
        property string glyph: ""
        property bool active: false
        property string countText: ""
        property color countColor: Theme.danger
        property int iconSize: 18
        signal activated()
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: btn.tooltipText || btn.label
        Accessible.onPressAction: btn.activated()
        Keys.onReturnPressed: btn.activated()
        Keys.onSpacePressed: btn.activated()
        Layout.fillWidth: true
        Layout.preferredHeight: 34

        readonly property color _fg: btn.active ? Theme.accentStrong
                                    : (ma.containsMouse ? Theme.text : Theme.textMuted)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMd
            color: btn.active ? Theme.accentSoft
                 : ma.containsMouse ? Theme.panel2 : "transparent"
            border.color: Theme.accentStrong
            border.width: btn.activeFocus ? 2 : 0
        }
        // Fixed 36px icon cell on the left: the icon sits where it did in
        // the rail, so collapsing does not make it jump sideways.
        Item {
            id: iconCell
            anchors.left: parent.left
            anchors.top: parent.top; anchors.bottom: parent.bottom
            width: 36
            IconImage {
                visible: btn.glyph === ""
                anchors.centerIn: parent
                source: btn.iconSource
                width: btn.iconSize
                height: btn.iconSize
                sourceSize.width: btn.iconSize * 2
                sourceSize.height: btn.iconSize * 2
                color: btn._fg
            }
            Text {
                visible: btn.glyph !== ""
                anchors.centerIn: parent
                text: btn.glyph
                color: btn._fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsLg
            }
        }
        Text {
            objectName: "rail-label"
            visible: btn.expanded
            opacity: btn.width > 96 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.scaledMs(90) } }
            anchors.left: iconCell.right
            anchors.right: countBox.visible && btn.expanded ? countBox.left
                         : comboT.visible ? comboT.left : parent.right
            anchors.rightMargin: Theme.spMd
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            elide: Text.ElideRight
            color: btn.active ? Theme.accentStrong : (ma.containsMouse ? Theme.text : Theme.textMuted)
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: btn.active ? Font.DemiBold : Font.Normal
        }
        Text {
            id: comboT
            visible: btn.expanded && !countBox.visible && ma.containsMouse && btn._combo.length > 0
            anchors.right: parent.right; anchors.rightMargin: Theme.spMd
            anchors.verticalCenter: parent.verticalCenter
            text: btn._combo
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsXs
        }
        // Count badge: a pill at the row's right edge when expanded, the
        // corner dot over the icon when collapsed.
        Rectangle {
            id: countBox
            visible: btn.countText !== ""
            x: btn.expanded ? parent.width - width - 8 : 36 - width - 1
            y: btn.expanded ? (parent.height - height) / 2 : 1
            radius: height / 2
            color: btn.countColor
            implicitWidth: Math.max(implicitHeight, cntT.implicitWidth + 8)
            implicitHeight: cntT.implicitHeight + (btn.expanded ? 4 : 2)
            Text {
                id: cntT
                anchors.centerIn: parent
                text: btn.countText
                color: Theme.textOn(btn.countColor)
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
                font.weight: Font.DemiBold
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
            // Labels are on screen when expanded; the tooltip is only for
            // the icon-only rail.
            ToolTip.visible: containsMouse && !btn.expanded && btn.tooltipText !== ""
            ToolTip.text: btn._combo.length ? btn.tooltipText + "   " + btn._combo : btn.tooltipText
            ToolTip.delay: 400
        }
    }
}
