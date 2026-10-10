import QtQuick
import QtQuick.Layouts
import TodoCpp

// A titled block of settings (APP-172): a sub-heading, an optional one-line
// description, and SettingsRows separated by hairlines — flat, no card
// around them (sheets H2-Settings / X-Set-*, DG-090).
//
//   SettingsGroup {
//       title: I18n.t(<key>); description: I18n.t(<key>)
//       SettingsRow { label: …; hint: …; <control> }
//       SettingsRow { … }
//   }
//
// - `framed` is kept for callers and no longer draws a card.
// - `danger: true` tints the heading.
ColumnLayout {
    id: group

    property string title: ""
    property string description: ""
    property bool framed: false
    property bool danger: false
    default property alias rows: rowsCol.data

    Layout.fillWidth: true
    spacing: Theme.spXs

    ColumnLayout {
        visible: group.title.length > 0 || group.description.length > 0
        Layout.fillWidth: true
        spacing: Theme.sp2xs
        Text {
            visible: group.title.length > 0
            Layout.fillWidth: true
            text: group.title
            color: group.danger ? Theme.danger : Theme.text
            // A section heading on the sheets (N-Set-*: 15px, 600), a step
            // over its rows so a page does not read as one block.
            font.pixelSize: Theme.fsLg
            font.weight: Style.chipFill ? Theme.fwHeading : Theme.fwTitle
            wrapMode: Text.WordWrap
        }
        Text {
            visible: group.description.length > 0
            Layout.fillWidth: true
            text: group.description
            color: Theme.textDim
            font.pixelSize: Theme.fsSm
            wrapMode: Text.WordWrap
        }
    }

    ColumnLayout {
        id: rowsCol
        Layout.fillWidth: true
        spacing: 0
    }
}
