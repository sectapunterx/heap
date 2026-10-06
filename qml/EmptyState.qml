import QtQuick
import QtQuick.Controls.impl
import TodoCpp

// What a list says when it has nothing to show (APP-167): a small drawing
// from the brand icon set, monochrome in the theme's dim colour, a title and
// one line that says what to do next. `compact` is the size for a board
// column; the full size is for a whole view or pane.
Column {
    id: root
    // A brand icon by name ("heap-05-archive"), from qrc:/brand/icons.
    property string icon: ""
    property string title: ""
    property string line: ""
    property bool compact: false
    readonly property int _iconSize: compact ? 22 : 40

    spacing: compact ? Theme.spXs : Theme.spMd
    // Fades in rather than popping when the last card leaves.
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }

    IconImage {
        objectName: "empty-state-icon"
        visible: root.icon.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        source: root.icon.length > 0 ? "qrc:/brand/icons/" + root.icon + ".svg" : ""
        width: root._iconSize
        height: root._iconSize
        sourceSize.width: root._iconSize
        sourceSize.height: root._iconSize
        color: Theme.textDim
    }
    Text {
        objectName: "empty-state-title"
        visible: root.title.length > 0
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: root.title
        color: root.compact ? Theme.textDim : Theme.text
        font.pixelSize: root.compact ? Theme.fsSm : Theme.fsMd
        font.weight: root.compact ? Font.Normal : Font.DemiBold
        wrapMode: Text.WordWrap
    }
    Text {
        objectName: "empty-state-line"
        visible: root.line.length > 0
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: root.line
        color: Theme.textDim
        font.pixelSize: root.compact ? Theme.fsXs : Theme.fsSm
        wrapMode: Text.WordWrap
    }
}
