import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls.impl
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    width: 56

    signal openTweaks(Item anchor)
    signal openHotkeys(Item anchor)

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
        anchors.topMargin: Theme.sp2xl
        spacing: Theme.spSm

        // View switcher
        RailBtn {
            objectName: "rail-board"
            iconSource: "qrc:/brand/icons/heap-01-board.svg"; tooltipText: I18n.t("siderail.tip.board"); shortcutId: "view.board"
                   active: AppController.currentView === "board"
                   onActivated: AppController.currentView = "board" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-02-timeline.svg"; tooltipText: I18n.t("siderail.tip.timeline"); shortcutId: "view.timeline"
                   active: AppController.currentView === "timeline"
                   onActivated: AppController.currentView = "timeline" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-03-week.svg"; tooltipText: I18n.t("siderail.tip.week"); shortcutId: "view.week"
                   active: AppController.currentView === "week"
                   onActivated: AppController.currentView = "week" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-04-month.svg"; tooltipText: I18n.t("siderail.tip.month"); shortcutId: "view.month"
                   active: AppController.currentView === "month"
                   onActivated: AppController.currentView = "month" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-05-archive.svg"; tooltipText: I18n.t("siderail.tip.archive"); shortcutId: "view.archive"
            active: AppController.currentView === "archive"
            onActivated: AppController.currentView = "archive"
        }

        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 24; height: 1; color: Theme.border; Layout.topMargin: Theme.spSm; Layout.bottomMargin: Theme.spSm }

        RailBtn {
            objectName: "rail-blocked"
            iconSource: "qrc:/brand/icons/heap-06-blocked.svg"; tooltipText: I18n.t("siderail.tip.blocked")
                   countText: root._blockedCount > 0 ? root._blockedCount : ""
                   countColor: Theme.danger
                   active: AppController.currentView === "board" && AppController.focusedStatus === "blocked"
                   onActivated: AppController.focusStatusColumn("blocked") }
        RailBtn {
            objectName: "rail-review"
            iconSource: "qrc:/brand/icons/heap-07-code-review.svg"; tooltipText: I18n.t("siderail.tip.review")
                   countText: root._reviewCount > 0 ? root._reviewCount : ""
                   countColor: Theme.accent
                   active: AppController.currentView === "board" && AppController.focusedStatus === "review"
                   onActivated: AppController.focusStatusColumn("review") }

        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 24; height: 1; color: Theme.border; Layout.topMargin: Theme.spSm; Layout.bottomMargin: Theme.spSm }

        RailBtn {
            objectName: "rail-docs"
            iconSource: "qrc:/brand/icons/heap-08-docs.svg"; tooltipText: I18n.t("siderail.tip.docs"); shortcutId: "view.docs"
                   active: AppController.currentView === "docs"
                   onActivated: AppController.currentView = "docs" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-09-notes.svg"; tooltipText: I18n.t("siderail.tip.notes"); shortcutId: "view.notes"
                   active: AppController.currentView === "notes"
                   onActivated: AppController.currentView = "notes" }

        Item { Layout.fillHeight: true }

        RailBtn {
            id: hotkeysBtn
            iconSource: "qrc:/brand/icons/heap-10-hotkeys.svg"
            tooltipText: I18n.t("siderail.tip.hotkeys")
            shortcutId: "hotkeys.open"
            onActivated: root.openHotkeys(hotkeysBtn)
        }
        RailBtn {
            id: tweaksBtn
            iconSource: "qrc:/brand/icons/heap-11-tweaks.svg"
            tooltipText: I18n.t("siderail.tip.tweaks")
            shortcutId: "tweaks.open"
            onActivated: root.openTweaks(tweaksBtn)
        }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-12-settings.svg"
            tooltipText: I18n.t("siderail.tip.settings")
            shortcutId: "view.settings"
            active: AppController.currentView === "settings"
            onActivated: AppController.currentView = "settings"
            Layout.bottomMargin: Theme.sp2xl
        }
    }

    component RailBtn: Item {
        id: btn
        property url iconSource
        property string tooltipText: ""
        // The action's id in the shortcut catalog. The tooltip shows whatever
        // it is bound to now, so a rebind shows up here too, and the rail
        // teaches the keys instead of hiding them in the Hotkeys panel.
        property string shortcutId: ""
        readonly property string _combo: shortcutId.length && AppController.shortcuts.length >= 0
            ? AppController.shortcutFor(shortcutId) : ""
        property bool active: false
        property string countText: ""
        property color countColor: Theme.danger
        property int iconSize: 20
        signal activated()
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: btn.tooltipText
        Accessible.onPressAction: btn.activated()
        Keys.onReturnPressed: btn.activated()
        Keys.onSpacePressed: btn.activated()
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: btn.active ? Theme.accentSoft
                 : ma.containsMouse ? Theme.panel2 : "transparent"
            border.color: Theme.accentStrong
            border.width: btn.activeFocus ? 2 : 0
        }
        IconImage {
            anchors.centerIn: parent
            source: btn.iconSource
            width: btn.iconSize
            height: btn.iconSize
            sourceSize.width: btn.iconSize * 2
            sourceSize.height: btn.iconSize * 2
            color: btn.active ? Theme.accentStrong : (ma.containsMouse ? Theme.text : Theme.textMuted)
        }
        Rectangle {
            visible: btn.countText !== ""
            anchors.top: parent.top; anchors.right: parent.right
            anchors.topMargin: Theme.sp2xs; anchors.rightMargin: Theme.sp2xs
            radius: Theme.radiusMd
            color: btn.countColor
            implicitWidth: cntT.implicitWidth + 8
            implicitHeight: cntT.implicitHeight + 2
            Text {
                id: cntT
                anchors.centerIn: parent
                text: btn.countText
                color: Theme.textOnBadge
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
            ToolTip.visible: containsMouse && btn.tooltipText !== ""
            ToolTip.text: btn._combo.length ? btn.tooltipText + "   " + btn._combo : btn.tooltipText
            ToolTip.delay: 400
        }
    }
}
