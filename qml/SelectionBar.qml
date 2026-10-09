pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Rectangle {
    id: bar
    visible: AppController.selectionCount > 0
    // Carries the selection on (APP-248): "tomorrow", "window", "someday", "clear".
    function carry(mode) { AppController.carryTasks(AppController.selectedTaskIds, mode); }
    opacity: visible ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.durPop; easing.type: Theme.easeEnter
        }
    }
    radius: Theme.radiusLg
    color: Theme.panel2
    border.color: Theme.borderStrong
    border.width: 1
    implicitHeight: 44
    implicitWidth: row.implicitWidth + 24

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Theme.spXl; anchors.rightMargin: Theme.spXl
        spacing: Theme.spLg

        Text {
            text: I18n.t("selection.bar.count").replace("%1", AppController.selectionCount)
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: Theme.fwTitle
        }
        Rectangle {
            Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Theme.border
        }

        PillButton {
            text: I18n.t("selection.bar.move")
            onClicked: moveMenu.popup()
        }
        // Priority and labels for the whole selection (TASKS-32): the two
        // edits a triage pass makes most, which took one editor per card.
        PillButton {
            objectName: "sel-priority"
            text: I18n.t("selection.bar.priority")
            onClicked: priorityMenu.popup()
        }
        // Carry the whole selection on (APP-248): tomorrow, the next free
        // windows one after another, someday, or no date.
        PillButton {
            objectName: "sel-carry"
            text: I18n.t("carry.menu")
            onClicked: carryMenu.popup()
        }
        PillButton {
            id: labelBtn
            objectName: "sel-label"
            text: I18n.t("selection.bar.label")
            onClicked: labelPopup.open()
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

    AppMenu {
        id: priorityMenu
        objectName: "sel-priority-menu"
        Repeater {
            model: ["P0", "P1", "P2", "P3"]
            AppMenuItem {
                required property string modelData
                text: modelData
                onTriggered: AppController.setSelectedTasksPriority(modelData)
            }
        }
    }

    AppMenu {
        id: carryMenu
        objectName: "sel-carry-menu"
        Repeater {
            model: ["tomorrow", "window", "someday", "clear"]
            AppMenuItem {
                required property string modelData
                objectName: "sel-carry-" + modelData
                text: I18n.t("carry." + modelData)
                onTriggered: bar.carry(modelData)
            }
        }
    }

    // Type a label: Enter adds it to every selected card, Shift+Enter takes
    // it off them.
    Popup {
        id: labelPopup
        objectName: "sel-label-popup"
        parent: labelBtn
        y: -height - Theme.spSm
        padding: Theme.spMd
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: PopupSurface {}
        onOpened: { labelField.text = ""; labelField.forceActiveFocus(); }
        function apply(present) {
            const name = labelField.text.trim();
            if (name.length === 0) return;
            AppController.setSelectedTasksLabel(name, present);
            labelPopup.close();
        }
        contentItem: ColumnLayout {
            spacing: Theme.spSm
            TextField {
                id: labelField
                ContextMenu.menu: TextEditMenu { editor: labelField }
                objectName: "sel-label-field"
                Layout.preferredWidth: 220
                placeholderText: I18n.t("selection.bar.labelPh")
                color: Theme.text
                placeholderTextColor: Theme.textDim
                background: FieldFrame {}
                Keys.onReturnPressed: (e) => labelPopup.apply((e.modifiers & Qt.ShiftModifier) === 0)
                Keys.onEnterPressed: (e) => labelPopup.apply((e.modifiers & Qt.ShiftModifier) === 0)
            }
            Text {
                text: I18n.t("selection.bar.labelHint")
                color: Theme.textDim
                font.pixelSize: Theme.fsXs
            }
        }
    }

    AppMenu {
        id: moveMenu
        Repeater {
            model: AppController.statuses
            AppMenuItem {
                required property var modelData
                text: modelData.name
                onTriggered: AppController.moveSelectedTasksToStatus(modelData.id)
            }
        }
    }
}
