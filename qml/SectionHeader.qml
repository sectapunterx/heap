import QtQuick
import QtQuick.Layouts
import TodoCpp

// A section title in heap 2 (APP-259): sentence case, no capitals, no
// tracking; hierarchy from weight and space, not from a box. An optional
// muted note beside it ("thu, 8 Oct", "until sun") and a count that follows
// Style.counters.
RowLayout {
    id: root

    property string title: ""
    property string note: ""
    property int count: -1
    // A signal title ("Today" in amber, bold style only).
    property color titleColor: Theme.text
    property int titleSize: Theme.fsMd
    property int titleWeight: Theme.fwHeading

    spacing: Theme.spMd

    Text {
        text: root.title
        color: root.titleColor
        font.family: Theme.fontUi
        font.pixelSize: root.titleSize
        font.weight: root.titleWeight
        Accessible.role: Accessible.Heading
        Accessible.name: root.title
    }
    Text {
        visible: root.note.length > 0
        text: root.note
        color: Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsSm
    }
    Text {
        visible: root.count >= 0 && Style.counters
        text: String(root.count)
        color: Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsSm
        font.features: Theme.tabularNums
    }
    Item { Layout.fillWidth: true }
}
