import QtQuick
import QtQuick.Shapes
import TodoCpp

// A task's status as a shape, not a colour (APP-259): the shape is the
// column's stage, so a column of the user's own draws like the built-in of
// its stage. Readable without colour and at 12 px.
//
//   backlog  dashed ring        todo    ring
//   half     ring, ¼ filled     prog    ring, ½ filled
//   review   ring, ¾ filled     done    filled
//   blocked  ring with a bar    orphan  dashed ring with "?" (column deleted)
Item {
    id: root

    // A stage (see board/ColumnCategory.h) or "orphan".
    property string category: "todo"
    property int size: Theme.statusRingSize
    // Neutral by default; blocked takes the urgent signal (red in the bold
    // style, the text colour in the quiet one).
    property color ink: category === "blocked" ? Theme.signalUrgent : Theme.textMuted
    // A repeating task: a small arrow beside the shape, never instead of it.
    property bool repeats: false

    implicitWidth: size + (repeats ? Math.round(size * 0.7) : 0)
    implicitHeight: size

    readonly property real _fill: category === "half" ? 0.25
                                : category === "prog" ? 0.5
                                : category === "review" ? 0.75
                                : category === "done" ? 1 : 0
    readonly property real _stroke: Math.max(1.25, size / 9)
    readonly property real _r: (size - _stroke) / 2
    readonly property bool _dashed: category === "backlog" || category === "orphan"

    Accessible.role: Accessible.Graphic
    Accessible.name: I18n.t("status.stage." + category)

    Shape {
        id: shape
        width: root.size
        height: root.size
        preferredRendererType: Shape.CurveRenderer

        // the ring
        ShapePath {
            strokeColor: root.ink
            strokeWidth: root._stroke
            fillColor: root.category === "done" ? root.ink : "transparent"
            strokeStyle: root._dashed ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: [1.6, 1.6]
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.size / 2; centerY: root.size / 2
                radiusX: root._r; radiusY: root._r
                startAngle: 0; sweepAngle: 360
            }
        }
        // the filled part: a sector from 12 o'clock, clockwise
        ShapePath {
            strokeWidth: -1
            fillColor: root._fill > 0 && root._fill < 1 ? root.ink : "transparent"
            startX: root.size / 2; startY: root.size / 2
            PathLine { x: root.size / 2; y: root.size / 2 - root._r }
            PathAngleArc {
                centerX: root.size / 2; centerY: root.size / 2
                radiusX: root._r; radiusY: root._r
                startAngle: -90; sweepAngle: 360 * root._fill
                moveToStart: false
            }
            PathLine { x: root.size / 2; y: root.size / 2 }
        }
        // blocked: a bar across the middle
        ShapePath {
            strokeColor: root.category === "blocked" ? root.ink : "transparent"
            strokeWidth: root._stroke
            capStyle: ShapePath.RoundCap
            startX: root.size * 0.3; startY: root.size / 2
            PathLine { x: root.size * 0.7; y: root.size / 2 }
        }
    }

    Text {
        visible: root.category === "orphan"
        anchors.centerIn: shape
        text: "?"
        color: root.ink
        font.family: Theme.fontUi
        font.pixelSize: Math.max(Theme.fsXs - 3, Math.round(root.size * 0.7))
        font.weight: Theme.fwTitle
    }

    // repeat: ↻ beside the shape
    Text {
        visible: root.repeats
        anchors.left: shape.right
        anchors.leftMargin: Math.round(root.size * 0.15)
        anchors.verticalCenter: shape.verticalCenter
        text: "↻"
        color: root.ink
        font.family: Theme.fontUi
        font.pixelSize: Math.round(root.size * 0.75)
        Accessible.ignored: true
    }
}
