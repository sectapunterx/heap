pragma ComponentBehavior: Bound
import QtQuick
import TodoCpp

// The lens switch of "Tasks" (APP-259/261): Board / List / Calendar. The
// current lens is marked by the 2 px lavender underline (APP-280 motif);
// the bold style also sets the group on a panel. Keys per keymap.md
// (g b / g l / g c) show beside each label when Style.keyHints is on.
Item {
    id: root

    // [{ id, label, keys }]
    property var model: []
    property string current: ""
    signal selected(string id)

    implicitHeight: Theme.chipH + (Style.chipFill ? Theme.spXs : 0)
    // Q-Board: the tabs sit on the title's baseline (R3-032).
    baselineOffset: height / 2 + (lensFm.ascent - lensFm.descent) / 2
    // Q-Board: 14px tabs, inactive in the dim ink; bold keeps the panel.
    readonly property int _fs: Style.chipFill ? Theme.fsMd : Theme.px(14)
    FontMetrics {
        id: lensFm
        font.family: Theme.fontUi
        font.pixelSize: root._fs
    }
    implicitWidth: row.implicitWidth + (Style.chipFill ? 2 * Theme.spXs : 0)

    Rectangle {
        anchors.fill: parent
        visible: Style.chipFill
        radius: Theme.radiusLg
        color: Theme.panel
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.chipFill ? Theme.sp2xs : Theme.px(20)
        Repeater {
            model: root.model
            delegate: Item {
                id: tab
                required property var modelData
                readonly property bool on: tab.modelData.id === root.current
                width: tabRow.implicitWidth + (Style.chipFill ? 2 * Theme.spLg : 0)
                height: Theme.chipH
                objectName: "lens-" + tab.modelData.id

                Rectangle {
                    anchors.fill: parent
                    visible: Style.chipFill && tab.on
                    radius: Theme.radiusMd
                    color: Theme.panel3
                }
                Row {
                    id: tabRow
                    anchors.centerIn: parent
                    spacing: Theme.spXs
                    Text {
                        id: label
                        anchors.verticalCenter: parent.verticalCenter
                        text: tab.modelData.label
                        color: tab.on ? Theme.text : (Style.chipFill ? Theme.textMuted : Theme.textDim)
                        font.family: Theme.fontUi
                        font.pixelSize: root._fs
                        font.weight: tab.on ? Theme.fwTitle : Theme.fwBody
                    }
                    KeyHint {
                        anchors.verticalCenter: parent.verticalCenter
                        keys: tab.modelData.keys || ""
                    }
                }
                CursorBar {
                    anchors.horizontalCenter: Style.chipFill ? parent.horizontalCenter : undefined
                    anchors.left: Style.chipFill ? undefined : tabRow.left
                    anchors.bottom: parent.bottom
                    full: true
                    target: Style.chipFill ? tab : label
                    shown: tab.on
                }
                ClickArea {
                    label: tab.modelData.label
                    role: Accessible.PageTab
                    checkable: true
                    checked: tab.on
                    onActivated: root.selected(tab.modelData.id)
                }
            }
        }
    }
}
