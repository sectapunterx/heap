import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    implicitHeight: 44
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
        ({ id: "title", label: I18n.t("filter.sort.title") })
    ]

    signal togglePriority(string p)
    signal clearPriorities()
    signal toggleArchived()
    signal sortModeRequested(string mode)

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1; color: Theme.border
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.sp2xl
        spacing: Theme.spMd

        Text {
            text: "<b><font color=\"" + Theme.text + "\">" + root.viewLabel + "</font></b> · "
                  + I18n.t("filter.label")
            textFormat: Text.RichText
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
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
                RowLayout {
                    id: chRow
                    anchors.centerIn: parent
                    spacing: Theme.spSm
                    Rectangle {
                        width: 8; height: 8; radius: Theme.radiusXs
                        color: Theme.priorityColor(modelData)
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

        Item { Layout.fillWidth: true }

        // Sort. Manual is the board's own order — the one a drag writes — so
        // it is first and is what the board starts on. One button and a menu:
        // five pills in a row were the busiest thing in the bar and the one
        // least often touched.
        Rectangle {
            id: sortBtn
            objectName: "sort-button"
            visible: root.showSort
            readonly property string label: {
                const modes = root._sortModes;
                for (let i = 0; i < modes.length; i++)
                    if (modes[i].id === root.sortMode) return modes[i].label;
                return modes[0].label;
            }
            radius: Theme.radiusPill
            color: sortMenu.visible ? Theme.panel3 : (sortMA.containsMouse ? Theme.panel3 : Theme.panel2)
            border.color: sortMA.containsMouse || sortMenu.visible ? Theme.borderStrong : Theme.border
            border.width: 1
            implicitWidth: sortRow.implicitWidth + 20
            implicitHeight: 24
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
            Menu {
                id: sortMenu
                Instantiator {
                    model: root._sortModes
                    delegate: MenuItem {
                        required property var modelData
                        objectName: "sort-" + modelData.id
                        text: modelData.label
                        checkable: true
                        checked: root.sortMode === modelData.id
                        onTriggered: root.sortModeRequested(modelData.id)
                    }
                    onObjectAdded: (index, object) => sortMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => sortMenu.removeItem(object)
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

        Text {
            text: I18n.t("filter.counts")
                    .arg(root.totalCount).arg(root.activeCount)
                    .arg(root.blockedCount).arg(root.reviewCount)
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsSm
            elide: Text.ElideRight
            Layout.maximumWidth: implicitWidth
        }
    }
}
