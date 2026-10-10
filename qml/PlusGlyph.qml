import QtQuick
import TodoCpp

// A line "+" drawn with two strokes (DG-070, Knowledge "+").
// Placeholder until the shared line-icon component qml/Icon.qml lands on
// heap2/0.8.1: then this becomes Icon { name: "plus" } at the call sites.
Item {
    id: root
    property real size: Theme.px(10)
    property color color: Theme.text
    readonly property real stroke: Math.max(1, Theme.px(1.5))
    implicitWidth: size
    implicitHeight: size
    Rectangle { anchors.centerIn: parent; width: root.size; height: root.stroke; radius: height / 2; color: root.color }
    Rectangle { anchors.centerIn: parent; width: root.stroke; height: root.size; radius: width / 2; color: root.color }
}
