import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

Rectangle {
    id: bar
    visible: AppController.selectionCount > 0
    opacity: visible ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.scaledMs(160); easing.type: Easing.OutCubic
        }
    }
    radius: 10
    color: Theme.panel2
    border.color: Theme.borderStrong
    border.width: 1
    implicitHeight: 44
    implicitWidth: row.implicitWidth + 24

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 12; anchors.rightMargin: 12
        spacing: 10

        Text {
            text: I18n.t("selection.bar.count").replace("%1", AppController.selectionCount)
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        Rectangle {
            Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Theme.border
        }

        PillButton {
            text: I18n.t("selection.bar.move")
            onClicked: moveMenu.popup()
        }
        PillButton {
            // Archive view operates on already-archived tickets — the only
            // sensible bulk action is to restore (unarchive). Elsewhere we
            // offer the inverse.
            readonly property bool _restoring: AppController.currentView === "archive"
            text: I18n.t(_restoring ? "selection.bar.unarchive" : "selection.bar.archive")
            onClicked: AppController.setSelectedTasksArchived(!_restoring)
        }
        PillButton {
            text: I18n.t("selection.bar.delete")
            danger: true
            onClicked: AppController.deleteSelectedTasks()
        }
        PillButton {
            text: I18n.t("selection.bar.clear")
            onClicked: AppController.clearSelection()
        }
    }

    QQC.Menu {
        id: moveMenu
        Repeater {
            model: AppController.statuses
            QQC.MenuItem {
                required property var modelData
                text: modelData.name
                onTriggered: AppController.moveSelectedTasksToStatus(modelData.id)
            }
        }
    }
}
