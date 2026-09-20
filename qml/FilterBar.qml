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
        anchors.leftMargin: 16; anchors.rightMargin: 16
        spacing: 8

        Text {
            text: "<b><font color=\"" + Theme.text + "\">" + root.viewLabel + "</font></b> · "
                  + I18n.t("filter.label")
            textFormat: Text.RichText
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: 12
        }

        Repeater {
            model: ["P0", "P1", "P2", "P3"]
            delegate: Rectangle {
                id: priChip
                required property string modelData
                objectName: "pri-" + modelData
                property bool active: root.priorities[modelData] === true
                radius: 999
                color: active ? Theme.accentSoft : (priMA.containsMouse ? Theme.panel3 : Theme.panel2)
                border.color: active ? Theme.accent : (priMA.containsMouse ? Theme.borderStrong : Theme.border)
                border.width: 1
                implicitWidth: chRow.implicitWidth + 20
                implicitHeight: 24
                RowLayout {
                    id: chRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 2
                        color: Theme.priorityColor(modelData)
                    }
                    Text {
                        text: modelData
                        color: priChip.active ? Theme.accentStrong : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 12
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
            radius: 999
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
                font.pixelSize: 11
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
        // it is first and is what the board starts on.
        Text {
            visible: root.showSort
            text: I18n.t("filter.sortBy")
            color: Theme.textDim
            font.pixelSize: 11
        }
        Repeater {
            model: root.showSort
                ? [ ({ id: "manual", label: I18n.t("filter.sort.manual") }),
                    ({ id: "priority", label: I18n.t("filter.sort.priority") }),
                    ({ id: "due", label: I18n.t("filter.sort.due") }),
                    ({ id: "updated", label: I18n.t("filter.sort.updated") }),
                    ({ id: "title", label: I18n.t("filter.sort.title") }) ]
                : []
            delegate: Rectangle {
                required property var modelData
                objectName: "sort-" + modelData.id
                readonly property bool active: root.sortMode === modelData.id
                radius: 999
                color: active ? Theme.accentSoft : (sortMA.containsMouse ? Theme.panel3 : Theme.panel2)
                border.color: active ? Theme.accent : (sortMA.containsMouse ? Theme.borderStrong : Theme.border)
                border.width: 1
                implicitWidth: sortT.implicitWidth + 16
                implicitHeight: 24
                Text {
                    id: sortT
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.active ? Theme.accentStrong : Theme.textMuted
                    font.pixelSize: 12
                }
                MouseArea {
                    id: sortMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortModeRequested(modelData.id)
                }
            }
        }

        Rectangle {
            objectName: "archived-toggle"
            radius: 999
            color: root.showArchived ? Theme.accentSoft : (archMA.containsMouse ? Theme.panel3 : Theme.panel2)
            border.color: root.showArchived ? Theme.accent : (archMA.containsMouse ? Theme.borderStrong : Theme.border)
            border.width: 1
            implicitWidth: archRow.implicitWidth + 16
            implicitHeight: 24
            RowLayout {
                id: archRow
                anchors.centerIn: parent
                spacing: 6
                Text {
                    text: "▤"
                    color: root.showArchived ? Theme.accentStrong : Theme.textDim
                    font.pixelSize: 11
                }
                Text {
                    text: I18n.t("filter.archived")
                    color: root.showArchived ? Theme.accentStrong : Theme.textMuted
                    font.pixelSize: 12
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
            font.pixelSize: 11
            elide: Text.ElideRight
            Layout.maximumWidth: implicitWidth
        }
    }
}
