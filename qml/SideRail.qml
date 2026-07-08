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

    // Reactive badges — refresh on task model mutations + profile switches.
    property int _blockedCount: AppController.countByStatus("blocked")
    property int _reviewCount:  AppController.countByStatus("review")
    Connections {
        target: AppController.tasks
        function onModelReset()   { root._blockedCount = AppController.countByStatus("blocked"); root._reviewCount = AppController.countByStatus("review") }
        function onRowsInserted() { root._blockedCount = AppController.countByStatus("blocked"); root._reviewCount = AppController.countByStatus("review") }
        function onRowsRemoved()  { root._blockedCount = AppController.countByStatus("blocked"); root._reviewCount = AppController.countByStatus("review") }
        function onDataChanged()  { root._blockedCount = AppController.countByStatus("blocked"); root._reviewCount = AppController.countByStatus("review") }
    }

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1; color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 14
        spacing: 6

        // View switcher
        RailBtn {
            objectName: "rail-board"
            iconSource: "qrc:/brand/icons/heap-01-board.svg"; tooltipText: I18n.t("siderail.tip.board")
                   active: AppController.currentView === "board"
                   onActivated: AppController.currentView = "board" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-02-timeline.svg"; tooltipText: I18n.t("siderail.tip.timeline")
                   active: AppController.currentView === "timeline"
                   onActivated: AppController.currentView = "timeline" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-03-week.svg"; tooltipText: I18n.t("siderail.tip.week")
                   active: AppController.currentView === "week"
                   onActivated: AppController.currentView = "week" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-04-month.svg"; tooltipText: I18n.t("siderail.tip.month")
                   active: AppController.currentView === "month"
                   onActivated: AppController.currentView = "month" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-05-archive.svg"; tooltipText: I18n.t("siderail.tip.archive")
            active: AppController.currentView === "archive"
            onActivated: AppController.currentView = "archive"
        }

        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 24; height: 1; color: Theme.border; Layout.topMargin: 6; Layout.bottomMargin: 6 }

        RailBtn {
            objectName: "rail-blocked"
            iconSource: "qrc:/brand/icons/heap-06-blocked.svg"; tooltipText: I18n.t("siderail.tip.blocked")
                   countText: root._blockedCount > 0 ? root._blockedCount : ""
                   countColor: Theme.p0
                   active: AppController.currentView === "board" && AppController.focusedStatus === "blocked"
                   onActivated: AppController.focusStatusColumn("blocked") }
        RailBtn {
            objectName: "rail-review"
            iconSource: "qrc:/brand/icons/heap-07-code-review.svg"; tooltipText: I18n.t("siderail.tip.review")
                   countText: root._reviewCount > 0 ? root._reviewCount : ""
                   countColor: Theme.stReview
                   active: AppController.currentView === "board" && AppController.focusedStatus === "review"
                   onActivated: AppController.focusStatusColumn("review") }

        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 24; height: 1; color: Theme.border; Layout.topMargin: 6; Layout.bottomMargin: 6 }

        RailBtn {
            objectName: "rail-docs"
            iconSource: "qrc:/brand/icons/heap-08-docs.svg"; tooltipText: I18n.t("siderail.tip.docs")
                   active: AppController.currentView === "docs"
                   onActivated: AppController.currentView = "docs" }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-09-notes.svg"; tooltipText: I18n.t("siderail.tip.notes")
                   active: AppController.currentView === "notes"
                   onActivated: AppController.currentView = "notes" }

        Item { Layout.fillHeight: true }

        RailBtn {
            id: hotkeysBtn
            iconSource: "qrc:/brand/icons/heap-10-hotkeys.svg"
            tooltipText: I18n.t("siderail.tip.hotkeys")
            onActivated: root.openHotkeys(hotkeysBtn)
        }
        RailBtn {
            id: tweaksBtn
            iconSource: "qrc:/brand/icons/heap-11-tweaks.svg"
            tooltipText: I18n.t("siderail.tip.tweaks")
            onActivated: root.openTweaks(tweaksBtn)
        }
        RailBtn {
            iconSource: "qrc:/brand/icons/heap-12-settings.svg"
            tooltipText: I18n.t("siderail.tip.settings")
            active: AppController.currentView === "settings"
            onActivated: AppController.currentView = "settings"
            Layout.bottomMargin: 14
        }
    }

    component RailBtn: Item {
        id: btn
        property url iconSource
        property string tooltipText: ""
        property bool active: false
        property string countText: ""
        property color countColor: Theme.p0
        property int iconSize: 20
        signal activated()
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: btn.active ? Theme.accentSoft
                 : ma.containsMouse ? Theme.panel2 : "transparent"
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
            anchors.topMargin: 2; anchors.rightMargin: 2
            radius: 6
            color: btn.countColor
            implicitWidth: cntT.implicitWidth + 8
            implicitHeight: cntT.implicitHeight + 2
            Text {
                id: cntT
                anchors.centerIn: parent
                text: btn.countText
                color: "white"
                font.family: Theme.fontMono
                font.pixelSize: 9
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
            ToolTip.text: btn.tooltipText
            ToolTip.delay: 400
        }
    }
}
