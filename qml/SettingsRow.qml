import QtQuick
import QtQuick.Layouts
import TodoCpp

// One setting inside a SettingsGroup (APP-172): the label and a one-line hint
// on the left, in a column of fixed width so every label in a group lines up,
// and the control on the right. Rows carry their own vertical padding and a
// hairline on top; SettingsGroup hides the first one, so a group reads as
// one surface with thin dividers.
//
//   SettingsGroup {
//       title: I18n.t(<key>)
//       SettingsRow {
//           label: I18n.t(<key>); hint: I18n.t(<key>)
//           Switch { … }                        // goes to the control slot
//       }
//   }
//
// - Children go to the control slot, right-aligned at their implicit width,
//   and the label takes the rest; `fillControl: true` gives the controls
//   everything right of a `labelWidth` label column instead.
// - No label and no hint: the slot spans the full row (paragraphs, lists).
// - Too narrow for label and controls side by side (`stackBelow`), the row
//   stacks: label on top, controls under it.
// - `control`: an item that must stay a direct child of the row (TextRow's
//   field — tests walk `children`). The row reserves its place in the slot
//   and positions it there.
Item {
    id: row

    property string label: ""
    property string hint: ""
    property color hintColor: Theme.textMuted
    // The label column. Capped at a share of the row so a narrow window
    // still leaves the control room.
    property int labelWidth: 248
    // Stacks once the label would get less than `minLabelWidth` beside the
    // controls — a switch never forces it, a 300px field does on a narrow
    // window.
    property int minLabelWidth: 200
    property int stackBelow: minLabelWidth + Theme.sp3xl + slot.implicitWidth
    property bool fillControl: false
    property bool separator: true
    property Item control: null
    // The whole row is the hit target (a switch row): a click anywhere on it
    // emits clicked(). Handlers live on the row itself — declared in a
    // derived row they would land in the control slot.
    property bool clickable: false
    signal clicked()

    default property alias content: slot.data
    onControlChanged: if (row.control) row.control.parent = row
    Component.onCompleted: if (row.control) row.control.parent = row

    TapHandler {
        enabled: row.clickable
        onTapped: row.clicked()
    }
    HoverHandler {
        enabled: row.clickable
        cursorShape: Qt.PointingHandCursor
    }
    readonly property bool stacked: width > 0 && width < stackBelow
    readonly property bool hasLabel: label.length > 0 || hint.length > 0
    readonly property int vpad: Theme.spXl
    // Every one-line row is the same height whatever its control (a switch,
    // a slider, a 30px segmented control), so a group reads as an even list.
    readonly property int minContent: 32

    Layout.fillWidth: true
    implicitWidth: grid.implicitWidth
    implicitHeight: Math.max(grid.implicitHeight, minContent) + 2 * vpad

    Rectangle {
        visible: row.separator
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.border
    }

    GridLayout {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        columns: row.stacked || !row.hasLabel ? 1 : 2
        columnSpacing: Theme.sp3xl
        rowSpacing: Theme.spMd

        ColumnLayout {
            visible: row.hasLabel
            spacing: Theme.sp2xs
            Layout.alignment: Qt.AlignVCenter
            // Beside a compact control (a switch, a few chips) the label and
            // its hint take all the room there is; beside a control that
            // fills, the label keeps to `labelWidth` so the controls of a
            // group start on one line.
            Layout.fillWidth: true
            Layout.preferredWidth: row.labelWidth
            Layout.maximumWidth: row.fillControl && !row.stacked
                                 ? Math.min(row.labelWidth, Math.round(row.width * 0.45))
                                 : Number.POSITIVE_INFINITY
            Text {
                visible: row.label.length > 0
                Layout.fillWidth: true
                text: row.label
                color: Theme.text
                font.pixelSize: Theme.fsMd
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Text {
                visible: row.hint.length > 0
                Layout.fillWidth: true
                text: row.hint
                color: row.hintColor
                font.pixelSize: Theme.fsSm
                lineHeight: 1.15
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            id: slot
            // At its controls' width on the right, unless they fill.
            Layout.fillWidth: row.fillControl || row.stacked || !row.hasLabel
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: Theme.spMd
            // The place a `control` occupies.
            Item {
                id: controlSpot
                visible: row.control !== null
                Layout.fillWidth: row.fillControl || row.stacked
                Layout.preferredWidth: row.control ? row.control.implicitWidth : 0
                Layout.preferredHeight: row.control ? row.control.implicitHeight : 0
            }
        }
    }

    Binding {
        when: row.control !== null
        target: row.control
        property: "x"
        value: grid.x + slot.x + controlSpot.x
    }
    Binding {
        when: row.control !== null
        target: row.control
        property: "y"
        value: grid.y + slot.y + controlSpot.y
    }
    Binding {
        when: row.control !== null
        target: row.control
        property: "width"
        value: controlSpot.width
    }
}
