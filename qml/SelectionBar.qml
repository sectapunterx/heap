pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

// The multi-select bar along the bottom (X-Menus-Task, DG-026): "3 выбрано",
// then each bulk action as a word with its key — Готово d, Запланировать s,
// Приоритет 1–4, Переместить Shift H / L, В архив e, Удалить Del, Снять Esc.
// The label and carry-on actions the bar used to hold stay in the command
// line while a selection exists (Ctrl K: "Метка для выбранных…",
// "Перенести выбранные…").
Rectangle {
    id: bar
    objectName: "selection-bar"
    // The list under "is:archived" (DG-161): the bulk action restores.
    property bool restoring: false
    // Done and Schedule run the window's own commands, as d and s do.
    signal commandRequested(string id)
    visible: AppController.selectionCount > 0
    // Carries the selection on (APP-248): "tomorrow", "window", "someday", "clear".
    function carry(mode) { AppController.carryTasks(AppController.selectedTaskIds, mode); }
    function openCarry() { carryMenu.popup(bar, 0, -carryMenu.implicitHeight - Theme.spSm); }
    function openLabel() { labelPopup.open(); }
    opacity: visible ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.durPop; easing.type: Theme.easeEnter
        }
    }
    radius: Theme.radiusLg
    color: Theme.panel
    border.color: Theme.border
    border.width: 1
    implicitHeight: Theme.px(42)
    implicitWidth: row.implicitWidth + 2 * Theme.spXl

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Theme.spXl; anchors.rightMargin: Theme.spXl
        spacing: Theme.sp2xl

        Text {
            objectName: "selection-count"
            text: I18n.t("selection.bar.count").replace("%1", AppController.selectionCount)
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: Theme.fwTitle
        }
        // The selection's estimates added up (APP-246): "~6 h · 3 without
        // an estimate". A fact; nothing is asked for.
        Text {
            id: estSum
            objectName: "selection-estimate"
            readonly property var sum: AppController.selectionCount > 0
                ? AppController.estimateSummary(AppController.selectedTaskIds) : ({ minutes: 0, without: 0 })
            visible: estSum.sum.minutes > 0
            text: "~" + I18n.fmtMinutes(estSum.sum.minutes)
                + (estSum.sum.without > 0 ? " · " + I18n.count(estSum.sum.without, "estimate.without") : "")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.features: Theme.tabularNums
            font.pixelSize: Theme.fsSm
        }
        BarAction {
            objectName: "sel-done"
            text: I18n.t("selection.bar.done")
            keys: AppController.shortcutText("task.done")
            onActivated: bar.commandRequested("task.done")
        }
        BarAction {
            objectName: "sel-schedule"
            text: I18n.t("selection.bar.schedule")
            keys: AppController.shortcutText("task.schedule")
            onActivated: bar.commandRequested("task.schedule")
        }
        // Priority for the whole selection (TASKS-32): 1–4 on the keyboard.
        BarAction {
            id: priBtn
            objectName: "sel-priority"
            text: I18n.t("selection.bar.priority")
            keys: AppController.shortcutText("task.priority0") + "–" + AppController.shortcutText("task.priority3")
            onActivated: priorityMenu.popup(priBtn, 0, -priorityMenu.implicitHeight - Theme.spSm)
        }
        BarAction {
            id: moveBtn
            objectName: "sel-move"
            text: I18n.t("selection.bar.move")
            keys: AppController.shortcutText("board.moveLeft") + " / " + AppController.shortcutText("board.moveRight").replace(/^Shift\s+/, "")
            onActivated: moveMenu.popup(moveBtn, 0, -moveMenu.implicitHeight - Theme.spSm)
        }
        BarAction {
            // The archive holds already-archived tasks — the bulk action
            // there restores them.
            objectName: "sel-archive"
            text: I18n.t(bar.restoring ? "selection.bar.unarchive" : "selection.bar.archive")
            keys: bar.restoring ? "" : AppController.shortcutText("board.archive")
            onActivated: AppController.setSelectedTasksArchived(!bar.restoring)
        }
        BarAction {
            objectName: "sel-delete"
            text: I18n.t("selection.bar.delete")
            keys: AppController.shortcutText("selection.deleteSel")
            onActivated: AppController.deleteSelectedTasks()
        }
        BarAction {
            objectName: "sel-clear"
            text: I18n.t("selection.bar.clear")
            keys: AppController.shortcutText("selection.clearSel")
            onActivated: AppController.clearSelection()
        }
    }

    // A word and its key: the bar's one kind of button.
    component BarAction: Item {
        id: act
        property string text: ""
        property string keys: ""
        signal activated()
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: actRow.implicitWidth
        implicitHeight: actRow.implicitHeight
        Row {
        id: actRow
        spacing: Theme.spSm
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: act.text
            color: actArea.hovered ? Theme.text : Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: Theme.fwTitle
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: Style.keyHints && act.keys.length > 0
            text: act.keys
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsXs
        }
        }
        ClickArea {
            id: actArea
            anchors.fill: parent
            anchors.margins: -Theme.spXs
            label: act.text
            showTip: false
            onActivated: act.activated()
        }
    }

    AppMenu {
        id: priorityMenu
        objectName: "sel-priority-menu"
        Repeater {
            model: ["P0", "P1", "P2", "P3"]
            AppMenuItem {
                required property string modelData
                required property int index
                text: modelData
                shortcutId: "task.priority" + index
                number: index + 1
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
        parent: bar
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
        objectName: "sel-move-menu"
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
