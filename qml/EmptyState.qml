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
    // Or a line glyph from Icon.qml, drawn in thin dim strokes.
    property string glyph: ""
    property string title: ""
    property string line: ""
    property bool compact: false
    // The line as a link ("сбросить фильтр · Esc", DG-160).
    property bool lineLink: false
    signal lineActivated()
    // Whole multiples of the icons' 18px grid (APP-195), so their 1px lines
    // land on device pixels.
    readonly property int _iconSize: compact ? 18 : 36

    spacing: compact ? Theme.spXs : Theme.spMd
    // Fades in rather than popping when the last card leaves.
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: Theme.durMove; easing.type: Theme.easeEnter } }

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
    Icon {
        objectName: "empty-state-glyph"
        visible: root.glyph.length > 0 && root.icon.length === 0
        anchors.horizontalCenter: parent.horizontalCenter
        name: root.glyph
        size: root._iconSize
        color: Theme.textDim
    }
    Text {
        objectName: "empty-state-title"
        visible: root.title.length > 0
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: root.title
        // N/X-Err-Empty: one plain line in the muted text, then the key.
        color: root.compact ? Theme.textDim : Theme.textMuted
        font.pixelSize: root.compact ? Theme.fsSm : Theme.fsMd
        font.weight: Theme.fwBody
        wrapMode: Text.WordWrap
    }
    Text {
        objectName: "empty-state-line"
        visible: root.line.length > 0
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: root.line
        color: root.lineLink && lineCA.hovered ? Theme.text : Theme.textDim
        font.pixelSize: root.compact ? Theme.fsXs : Theme.fsMd
        wrapMode: Text.WordWrap
        ClickArea {
            id: lineCA
            objectName: "empty-state-link"
            visible: root.lineLink
            label: root.line
            role: Accessible.Link
            onActivated: root.lineActivated()
        }
    }
}
