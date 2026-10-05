import QtQuick
import QtQuick.Layouts
import TodoCpp

// A titled block of settings (APP-172): a heading, an optional one-line
// description, and a surface holding SettingsRows separated by hairlines.
//
//   SettingsGroup {
//       title: I18n.t(<key>); description: I18n.t(<key>)
//       SettingsRow { label: …; hint: …; <control> }
//       SettingsRow { … }
//   }
//
// - `framed: false` drops the surface: for content that draws its own card
//   (ThemeSettings, the integration cards) and only wants the heading.
// - `danger: true` tints the heading and the frame — the destructive block
//   at the bottom of a section.
// Rows carry their own padding; the surface adds only the side inset. The
// first row's hairline is clipped away under the top edge, whichever row is
// first visible.
ColumnLayout {
    id: group

    property string title: ""
    property string description: ""
    property bool framed: true
    property bool danger: false
    default property alias rows: rowsCol.data

    Layout.fillWidth: true
    spacing: Theme.spLg

    ColumnLayout {
        visible: group.title.length > 0 || group.description.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: group.framed ? Theme.sp2xs : 0
        spacing: Theme.sp2xs
        Text {
            visible: group.title.length > 0
            Layout.fillWidth: true
            text: group.title
            color: group.danger ? Theme.danger : Theme.text
            font.pixelSize: Theme.fsLg
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }
        Text {
            visible: group.description.length > 0
            Layout.fillWidth: true
            text: group.description
            color: Theme.textMuted
            font.pixelSize: Theme.fsSm
            wrapMode: Text.WordWrap
        }
    }

    Rectangle {
        id: surface
        Layout.fillWidth: true
        implicitHeight: group.framed ? rowsCol.implicitHeight + 1 : rowsCol.implicitHeight
        radius: Theme.radiusLg
        color: group.framed ? Theme.panel : "transparent"
        border.width: group.framed ? 1 : 0
        border.color: group.danger ? Theme.withAlpha(Theme.danger, 0.45) : Theme.border

        Item {
            anchors.fill: parent
            anchors.margins: group.framed ? 1 : 0
            clip: group.framed
            ColumnLayout {
                id: rowsCol
                x: group.framed ? Theme.inset - 1 : 0
                y: group.framed ? -1 : 0
                width: parent.width - 2 * x
                spacing: group.framed ? 0 : Theme.spLg
            }
        }
    }
}
