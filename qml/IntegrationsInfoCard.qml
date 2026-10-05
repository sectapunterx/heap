pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import TodoCpp

// Settings → Integrations: what an integration does and does not do, in one
// place. Pulls are complete, the only thing written back is the column, edits
// made in heap stay in heap, and calendars by link are read-only — none of
// which the cards themselves said. Folds to its title; open by default.
Rectangle {
    id: root
    objectName: "integrations-info"
    property bool open: true

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Theme.sp2xl * 2
    radius: Theme.radiusLg
    color: Theme.panel
    border.color: Theme.border
    border.width: 1

    readonly property var points: ["pull", "push", "edits", "contacts", "calendars", "secrets"]

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.sp2xl
        spacing: Theme.spMd

        Item {
            Layout.fillWidth: true
            implicitHeight: headRow.implicitHeight
            RowLayout {
                id: headRow
                anchors.fill: parent
                spacing: Theme.spMd
                Text {
                    text: root.open ? "▾" : "▸"
                    color: Theme.textDim
                    font.pixelSize: Theme.fsMd
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("intinfo.title")
                    color: Theme.text
                    font.pixelSize: Theme.fsLg
                    font.weight: Font.DemiBold
                }
            }
            ClickArea {
                objectName: "integrations-info-toggle"
                label: I18n.t("intinfo.title")
                showTip: false
                role: Accessible.CheckBox
                checkable: true
                checked: root.open
                onActivated: root.open = !root.open
            }
        }

        Repeater {
            model: root.open ? root.points : []
            delegate: RowLayout {
                id: point
                required property string modelData
                objectName: "integrations-info-" + modelData
                Layout.fillWidth: true
                spacing: Theme.spMd
                Text {
                    Layout.alignment: Qt.AlignTop
                    text: "•"
                    color: Theme.textDim
                    font.pixelSize: Theme.fsMd
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("intinfo." + point.modelData)
                    textFormat: Text.StyledText
                    color: Theme.textMuted
                    font.pixelSize: Theme.fsSm
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
