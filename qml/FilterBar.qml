pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls.impl
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    // One row when both groups fit; otherwise sort / archived / counts drop
    // to a second row instead of running off the right edge.
    readonly property bool _wrapped: !root.slim && filtersRow.implicitWidth + 24 + actionsRow.implicitWidth > width - 32
    // Under the Tasks header (APP-261) the conditions, the view name and the
    // count live in the query row; what stays is the view's own tools.
    property bool slim: false
    implicitHeight: _wrapped ? 44 + 34 : 44
    height: implicitHeight
    property var priorities: ({})  // map P0..P3 -> bool
    property int totalCount: 0
    property int activeCount: 0
    property int blockedCount: 0
    property int reviewCount: 0
    property bool showArchived: false
    property string viewLabel: "Board"
    // Only the board orders its columns; the other views carry their own
    // ordering, so the control hides rather than lying about what it does.
    property bool showSort: false
    property string sortMode: "manual"
    readonly property var _sortModes: [
        ({ id: "manual", label: I18n.t("filter.sort.manual") }),
        ({ id: "priority", label: I18n.t("filter.sort.priority") }),
        ({ id: "due", label: I18n.t("filter.sort.due") }),
        ({ id: "updated", label: I18n.t("filter.sort.updated") }),
        ({ id: "title", label: I18n.t("filter.sort.title") }),
        ({ id: "id", label: I18n.t("filter.sort.id") })
    ]

    signal togglePriority(string p)
    signal clearPriorities()
    signal toggleArchived()
    signal sortModeRequested(string mode)

    // Saved views. With none active the bar offers "Save view…"; with one it
    // names it, and once the filters move off it, offers to update it or keep
    // the change as a new view.
    property string savedViewName: ""
    property bool savedViewModified: false
    signal saveViewRequested()
    signal updateViewRequested()
    signal saveAsNewRequested()
    signal leaveViewRequested()

    // The weekly recap, from the board (APP-211): opens it any time; the dot
    // says this week's recap has not been seen yet.
    property bool showRecap: false
    property bool recapUnseen: false
    signal recapRequested()

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1; color: Theme.border
    }

    RowLayout {
        id: filtersRow
        visible: !root.slim
        x: 16
        y: (44 - height) / 2
        width: Math.min(implicitWidth, root.width - 32)
        spacing: Theme.spMd

        // The view's name, then its filters. "Board · Filters:" said the
        // same thing twice (APP-197): the chips beside it are the filters.
        Text {
            objectName: "filter-view-label"
            text: root.viewLabel
            textFormat: Text.PlainText
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: Theme.fwTitle
            rightPadding: Theme.spSm
        }

        Repeater {
            model: ["P0", "P1", "P2", "P3"]
            delegate: Rectangle {
                id: priChip
                required property string modelData
                objectName: "pri-" + modelData
                property bool active: root.priorities[modelData] === true
                radius: Theme.radiusPill
                color: active ? Theme.accentSoft : (priMA.containsMouse ? Theme.panel3 : Theme.panel2)
                border.color: active ? Theme.accent : (priMA.containsMouse ? Theme.borderStrong : Theme.border)
                border.width: 1
                implicitWidth: chRow.implicitWidth + 20
                implicitHeight: 24
                // Tab-reachable: the filter bar was mouse-only.
                activeFocusOnTab: true
                Accessible.role: Accessible.CheckBox
                Accessible.name: modelData
                Accessible.checked: active
                Keys.onSpacePressed: root.togglePriority(modelData)
                Keys.onReturnPressed: root.togglePriority(modelData)
                FocusRing {}
                RowLayout {
                    id: chRow
                    anchors.centerIn: parent
                    spacing: Theme.spSm
                    Text {
                        objectName: "priority-mark"
                        text: Theme.priorityMark(modelData)
                        color: Theme.priorityColor(modelData)
                        font.pixelSize: Theme.fsXs
                    }
                    Text {
                        text: modelData
                        color: priChip.active ? Theme.accentStrong : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsMd
                    }
                }
                MouseArea {
                    id: priMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePriority(modelData)
                }
            }
        }

        Rectangle {
            visible: {
                let any = false;
                for (const k in root.priorities) if (root.priorities[k]) any = true;
                return any;
            }
            radius: Theme.radiusPill
            border.color: clrMA.containsMouse ? Theme.borderStrong : Theme.border
            border.width: 1
            color: clrMA.containsMouse ? Theme.panel3 : Theme.panel2
            implicitWidth: clrT.implicitWidth + 16
            implicitHeight: 24
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: clrT.text
            Keys.onSpacePressed: root.clearPriorities()
            Keys.onReturnPressed: root.clearPriorities()
            FocusRing {}
            Text {
                id: clrT
                anchors.centerIn: parent
                text: I18n.t("filter.clear")
                color: clrMA.containsMouse ? Theme.text : Theme.textDim
                font.pixelSize: Theme.fsSm
            }
            MouseArea {
                id: clrMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearPriorities()
            }
        }

    }

    RowLayout {
        id: actionsRow
        x: root._wrapped ? 16 : root.width - 16 - width
        y: root._wrapped ? 44 + (34 - height) / 2 - 6 : (44 - height) / 2
        width: Math.min(implicitWidth, root.width - 32)
        spacing: Theme.spMd

        // ── Saved view ──
        BarChip {
            objectName: "save-view"
            visible: root.savedViewName.length === 0 && !root.slim
            glyph: "☆"
            text: I18n.t("filter.saveView")
            tip: I18n.t("filter.saveViewTip")
            onActivated: root.saveViewRequested()
        }
        BarChip {
            objectName: "saved-view-chip"
            visible: root.savedViewName.length > 0
            selected: !root.savedViewModified
            glyph: "★"
            text: root.savedViewModified ? I18n.t("filter.viewModified").arg(root.savedViewName) : root.savedViewName
            trailing: "×"
            tip: I18n.t("filter.leaveView")
            onActivated: root.leaveViewRequested()
            Layout.maximumWidth: 220
        }
        BarChip {
            objectName: "update-view"
            visible: root.savedViewName.length > 0 && root.savedViewModified
            text: I18n.t("filter.updateView")
            onActivated: root.updateViewRequested()
        }
        BarChip {
            objectName: "save-as-new-view"
            visible: root.savedViewName.length > 0 && root.savedViewModified
            text: I18n.t("filter.saveAsNew")
            onActivated: root.saveAsNewRequested()
        }

        BarChip {
            objectName: "recap-button"
            visible: root.showRecap
            iconSource: "qrc:/brand/icons/heap-03-week.svg"
            text: I18n.t("recap.button")
            dot: root.recapUnseen
            tip: {
                const keys = (AppController.shortcuts, AppController.shortcutFor("recap.open"));
                const what = root.recapUnseen ? I18n.t("recap.button.unseen") : I18n.t("recap.button.tip");
                return keys.length > 0 ? what + "  " + keys : what;
            }
            onActivated: root.recapRequested()
        }

        // Sort. Manual is the board's own order — the one a drag writes — so
        // it is first and is what the board starts on. One button and a menu:
        // five pills in a row were the busiest thing in the bar and the one
        // least often touched.
        Rectangle {
            id: sortBtn
            objectName: "sort-button"
            visible: root.showSort
            // "priority-desc" is the priority sort reversed (APP-117).
            readonly property bool desc: root.sortMode.endsWith("-desc")
            readonly property string baseMode: desc ? root.sortMode.slice(0, -5) : root.sortMode
            readonly property string label: {
                const modes = root._sortModes;
                for (let i = 0; i < modes.length; i++)
                    if (modes[i].id === sortBtn.baseMode) return modes[i].label + (sortBtn.desc ? " ↓" : "");
                return modes[0].label;
            }
            radius: Theme.radiusPill
            color: sortMenu.visible ? Theme.panel3 : (sortMA.containsMouse ? Theme.panel3 : Theme.panel2)
            border.color: sortMA.containsMouse || sortMenu.visible ? Theme.borderStrong : Theme.border
            border.width: 1
            implicitWidth: sortRow.implicitWidth + 20
            implicitHeight: 24
            activeFocusOnTab: visible
            Accessible.role: Accessible.ComboBox
            Accessible.name: I18n.t("filter.sortBy") + " " + sortBtn.label
            Keys.onSpacePressed: sortMenu.popup(sortBtn, 0, sortBtn.height + 4)
            Keys.onReturnPressed: sortMenu.popup(sortBtn, 0, sortBtn.height + 4)
            Keys.onDownPressed: sortMenu.popup(sortBtn, 0, sortBtn.height + 4)
            FocusRing {}
            RowLayout {
                id: sortRow
                anchors.centerIn: parent
                spacing: Theme.spXs
                Text {
                    text: I18n.t("filter.sortBy")
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm
                }
                Text {
                    text: sortBtn.label
                    color: root.sortMode === "manual" ? Theme.textMuted : Theme.accentStrong
                    font.pixelSize: Theme.fsMd
                }
                Text {
                    text: "▾"
                    color: Theme.textDim
                    font.pixelSize: Theme.fsXs
                }
            }
            MouseArea {
                id: sortMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sortMenu.popup(sortBtn, 0, sortBtn.height + 4)
            }
            AppMenu {
                id: sortMenu
                Instantiator {
                    model: root._sortModes
                    delegate: AppMenuItem {
                        required property var modelData
                        objectName: "sort-" + modelData.id
                        text: modelData.label
                        checkable: true
                        checked: sortBtn.baseMode === modelData.id
                        // Picking a mode keeps the direction; manual has none.
                        onTriggered: root.sortModeRequested(modelData.id !== "manual" && sortBtn.desc
                                                            ? modelData.id + "-desc" : modelData.id)
                    }
                    onObjectAdded: (index, object) => sortMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => sortMenu.removeItem(object)
                }
                AppMenuSeparator {}
                AppMenuItem {
                    objectName: "sort-reverse"
                    text: I18n.t("filter.sort.reverse")
                    checkable: true
                    checked: sortBtn.desc
                    enabled: sortBtn.baseMode !== "manual"
                    onTriggered: root.sortModeRequested(sortBtn.desc ? sortBtn.baseMode : sortBtn.baseMode + "-desc")
                }
            }
        }

        Rectangle {
            objectName: "archived-toggle"
            radius: Theme.radiusPill
            color: root.showArchived ? Theme.accentSoft : (archMA.containsMouse ? Theme.panel3 : Theme.panel2)
            border.color: root.showArchived ? Theme.accent : (archMA.containsMouse ? Theme.borderStrong : Theme.border)
            border.width: 1
            implicitWidth: archRow.implicitWidth + 16
            implicitHeight: 24
            activeFocusOnTab: true
            Accessible.role: Accessible.CheckBox
            Accessible.name: I18n.t("filter.archived")
            Accessible.checked: root.showArchived
            Keys.onSpacePressed: root.toggleArchived()
            Keys.onReturnPressed: root.toggleArchived()
            FocusRing {}
            RowLayout {
                id: archRow
                anchors.centerIn: parent
                spacing: Theme.spSm
                Text {
                    text: "▤"
                    color: root.showArchived ? Theme.accentStrong : Theme.textDim
                    font.pixelSize: Theme.fsSm
                }
                Text {
                    text: I18n.t("filter.archived")
                    color: root.showArchived ? Theme.accentStrong : Theme.textMuted
                    font.pixelSize: Theme.fsMd
                }
            }
            MouseArea {
                id: archMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleArchived()
            }
        }

        // One count (APP-197): how many tasks the view shows. The rest
        // (in progress, blocked, on review) are a tooltip away and have their
        // own filters in the sidebar.
        Text {
            objectName: "filter-count"
            visible: !root.slim
            text: I18n.tasks(root.totalCount)
            color: Theme.textDim
            font.family: Theme.fontUi
            font.features: Theme.tabularNums
            font.pixelSize: Theme.fsSm
            elide: Text.ElideRight
            // Shrinks (and elides) instead of running off the bar's edge
            // when the board column is narrow.
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.maximumWidth: implicitWidth
            ToolTip.visible: countHover.hovered
            ToolTip.text: I18n.t("filter.counts")
                    .arg(root.totalCount).arg(root.activeCount)
                    .arg(root.blockedCount).arg(root.reviewCount)
            ToolTip.delay: 500
            HoverHandler { id: countHover }
        }
    }

    // A pill in the bar's own style: the saved-view controls.
    component BarChip: Rectangle {
        id: chip
        property string text: ""
        property string glyph: ""
        property string trailing: ""
        property string tip: ""
        property bool selected: false
        // A brand icon in place of the glyph, and an unread dot on it.
        property url iconSource: ""
        property bool dot: false
        signal activated()
        radius: Theme.radiusPill
        color: chip.selected ? Theme.accentSoft : (chipMA.containsMouse ? Theme.panel3 : Theme.panel2)
        border.color: chip.selected ? Theme.accent : (chipMA.containsMouse ? Theme.borderStrong : Theme.border)
        border.width: 1
        implicitWidth: chipRow.implicitWidth + 16
        implicitHeight: 24
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: chip.tip.length > 0 ? chip.text + ", " + chip.tip : chip.text
        Accessible.onPressAction: chip.activated()
        Keys.onSpacePressed: chip.activated()
        Keys.onReturnPressed: chip.activated()
        FocusRing {}
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, chip.width - 16)
            spacing: Theme.spXs
            Text {
                visible: chip.glyph.length > 0
                text: chip.glyph
                color: chip.selected ? Theme.accentStrong : Theme.textDim
                font.pixelSize: Theme.fsSm
            }
            Item {
                visible: chip.iconSource.toString().length > 0
                implicitWidth: 18
                implicitHeight: 18
                IconImage {
                    anchors.fill: parent
                    source: chip.iconSource
                    sourceSize.width: 18
                    sourceSize.height: 18
                    color: chip.selected ? Theme.accentStrong : (chipMA.containsMouse ? Theme.text : Theme.textMuted)
                }
                Rectangle {
                    objectName: "bar-chip-dot"
                    visible: chip.dot
                    x: parent.width - width / 2 - 1
                    y: -1
                    width: 7
                    height: 7
                    radius: Theme.radiusPill
                    color: Theme.accent
                    border.color: Theme.panel2
                    border.width: 1
                }
            }
            Text {
                Layout.fillWidth: true
                text: chip.text
                elide: Text.ElideRight
                color: chip.selected ? Theme.accentStrong : Theme.textMuted
                font.pixelSize: Theme.fsMd
            }
            Text {
                visible: chip.trailing.length > 0
                text: chip.trailing
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
            }
        }
        MouseArea {
            id: chipMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activated()
            ToolTip.visible: (containsMouse || chip.activeFocus) && chip.tip.length > 0
            ToolTip.text: chip.tip
            ToolTip.delay: 500
        }
    }
}
