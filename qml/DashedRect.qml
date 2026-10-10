import QtQuick
import QtQuick.Shapes
import TodoCpp

// A rounded rectangle with a dashed edge: where a dragged card came from
// (X/N-Oth-Select-Drag, R3-051) and the block a task would take on the
// calendar while it is dragged there (R3-054).
Item {
    id: root
    property color strokeColor: Theme.borderStrong
    property real strokeWidth: 1
    property color fillColor: "transparent"
    property real radius: Theme.radius

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.fillColor
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            id: sp
            readonly property real h: root.strokeWidth / 2
            readonly property real r: Math.max(0, Math.min(root.radius, root.width / 2, root.height / 2) - h)
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            strokeStyle: ShapePath.DashLine
            dashPattern: [3, 3]
            fillColor: "transparent"
            startX: h + r; startY: h
            PathLine { x: root.width - sp.h - sp.r; y: sp.h }
            PathArc { x: root.width - sp.h; y: sp.h + sp.r; radiusX: sp.r; radiusY: sp.r }
            PathLine { x: root.width - sp.h; y: root.height - sp.h - sp.r }
            PathArc { x: root.width - sp.h - sp.r; y: root.height - sp.h; radiusX: sp.r; radiusY: sp.r }
            PathLine { x: sp.h + sp.r; y: root.height - sp.h }
            PathArc { x: sp.h; y: root.height - sp.h - sp.r; radiusX: sp.r; radiusY: sp.r }
            PathLine { x: sp.h; y: sp.h + sp.r }
            PathArc { x: sp.h + sp.r; y: sp.h; radiusX: sp.r; radiusY: sp.r }
        }
    }
}
