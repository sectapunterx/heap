import QtQuick
import QtQuick.Shapes
import TodoCpp

// A meeting is a calendar glyph, whatever its type (stand-up, 1:1, sync,
// focus block); the type is a word in the caption (APP-259). Always shown,
// in both styles: it is what tells a meeting from a task.
Item {
    id: root
    property int size: Theme.statusRingSize
    property color ink: Style.chipFill ? Theme.meeting : Theme.textMuted

    implicitWidth: size
    implicitHeight: size
    Accessible.role: Accessible.Graphic
    Accessible.name: I18n.t("event.kind.meeting")

    readonly property real _s: Math.max(1.25, size / 10)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {   // the page
            strokeColor: root.ink
            strokeWidth: root._s
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathRectangle {
                x: root._s / 2 + root.size * 0.06
                y: root.size * 0.16
                width: root.size - root._s - root.size * 0.12
                height: root.size * 0.78
                radius: root.size * 0.12
            }
        }
        ShapePath {   // the rule under the header and the two rings
            strokeColor: root.ink
            strokeWidth: root._s
            capStyle: ShapePath.RoundCap
            startX: root.size * 0.1; startY: root.size * 0.42
            PathLine { x: root.size * 0.9; y: root.size * 0.42 }
            PathMove { x: root.size * 0.33; y: root.size * 0.06 }
            PathLine { x: root.size * 0.33; y: root.size * 0.24 }
            PathMove { x: root.size * 0.67; y: root.size * 0.06 }
            PathLine { x: root.size * 0.67; y: root.size * 0.24 }
        }
    }
}
