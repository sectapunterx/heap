import QtQuick
import QtQuick.Shapes
import TodoCpp

// The one line-icon set of the design sheets (DG-003): 16-unit glyphs,
// 1.4 stroke, round caps, drawn in `color`. Status rings and the meeting
// glyph have their own components (StatusRing, MeetingIcon); this is every
// other glyph. Never use emoji or text characters as icons.
//
//   Icon { name: "search"; color: Theme.textMuted }
//
// Names: search, filter, calendar, flag, chevron-down, chevron-up,
// chevron-left, chevron-right, branch, lock, expand, collapse, info, link,
// attachment, timer, check, plus, close, more, arrow-out, arrow-up,
// arrow-down, arrow-left, arrow-right, settings, list, doc, person, archive,
// bolt, undo, sidebar.
Item {
    id: root

    property string name: ""
    property color color: Theme.textMuted
    property int size: Theme.iconSize
    // In 16-unit space; the sheets draw 1.4 at 16 px and 1.6 below 13 px.
    property real strokeUnits: size < 13 ? 1.6 : 1.4

    implicitWidth: size
    implicitHeight: size
    Accessible.role: Accessible.Graphic
    Accessible.ignored: true

    // A full circle as a path (two arcs): PathSvg has no <circle>.
    function _c(cx, cy, r) {
        return "M" + (cx + r) + " " + cy
             + "a" + r + " " + r + " 0 1 1 " + (-2 * r) + " 0"
             + "a" + r + " " + r + " 0 1 1 " + (2 * r) + " 0";
    }

    // name → { s: stroked path, f: filled path }
    readonly property var _glyphs: ({
        "search":        { s: _c(7.2, 7.2, 4.6) + "M10.6 10.6 13.6 13.6" },
        "filter":        { s: "M2.7 3.3h10.6l-4 5.4v4l-2.6-1.4v-2.6z" },
        "calendar":      { s: "M4 3h8a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM2 6.5h12M5.5 1.5v3M10.5 1.5v3" },
        "flag":          { s: "M3 15V2M3 2h9l-2 3.5L12 9H3" },
        "chevron-down":  { s: "M4 6l4 4 4-4" },
        "chevron-up":    { s: "M4 10l4-4 4 4" },
        "chevron-left":  { s: "M10 4l-4 4 4 4" },
        "chevron-right": { s: "M6 4l4 4-4 4" },
        "branch":        { s: _c(5, 3.5, 1.5) + _c(5, 12.5, 1.5) + _c(11, 4.5, 1.5) + "M5 5v6M11 6c0 3-6 2.5-6 5" },
        "lock":          { s: "M4.5 7h7a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-7a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1zM5.5 7V5a2.5 2.5 0 0 1 5 0v2" },
        "expand":        { s: "M9.5 2.5h4v4M13.5 2.5 9 7M6.5 13.5h-4v-4M2.5 13.5 7 9" },
        "collapse":      { s: "M13.5 2.5 9.5 6.5M9.5 3v3.5H13M2.5 13.5l4-4M3 9.5h3.5V13" },
        "info":          { s: _c(8, 8, 6) + "M8 7.5v3.5", f: _c(8, 5.2, 0.8) },
        "link":          { s: "M7 9a3 3 0 0 0 4.2 0l2-2a3 3 0 0 0-4.2-4.2l-.8.8M9 7a3 3 0 0 0-4.2 0l-2 2a3 3 0 0 0 4.2 4.2l.8-.8" },
        "attachment":    { s: "M13 7.5 8 12.5a3 3 0 0 1-4.2-4.2l5.3-5.3a2 2 0 0 1 2.8 2.8L6.6 11a1 1 0 0 1-1.4-1.4L10 4.8" },
        "timer":         { s: _c(8, 9, 5) + "M8 9V6.5M6.5 1.5h3M12.3 4.7l1-1" },
        "check":         { s: "M3 8.5l3 3 7-7" },
        "plus":          { s: "M8 3v10M3 8h10" },
        "close":         { s: "M4 4l8 8M12 4l-8 8" },
        "more":          { f: _c(3.5, 8, 1.1) + _c(8, 8, 1.1) + _c(12.5, 8, 1.1) },
        "arrow-out":     { s: "M5 11 11 5M6 5h5v5" },
        "arrow-up":      { s: "M8 13V3M4 7l4-4 4 4" },
        "arrow-down":    { s: "M8 3v10M4 9l4 4 4-4" },
        "arrow-left":    { s: "M13 8H3M7 4 3 8l4 4" },
        "arrow-right":   { s: "M3 8h10M9 4l4 4-4 4" },
        "settings":      { s: _c(8, 8, 2.2) + "M8 1.8v2M8 12.2v2M1.8 8h2M12.2 8h2M3.6 3.6 5 5M11 11l1.4 1.4M3.6 12.4 5 11M11 5l1.4-1.4" },
        "list":          { s: "M6 4h8M6 8h8M6 12h8", f: _c(2.5, 4, 1) + _c(2.5, 8, 1) + _c(2.5, 12, 1) },
        "doc":           { s: "M3 2.5h7l3 3v8H3zM10 2.5v3h3M5.5 8.5h5M5.5 11h5" },
        "person":        { s: _c(8, 5.5, 2.5) + "M3 13.5c.8-2.4 2.7-3.5 5-3.5s4.2 1.1 5 3.5" },
        "archive":       { s: "M2.5 3h11v3.5h-11zM3.5 6.5v6.5h9V6.5M6.5 9.5h3" },
        "bolt":          { s: "M9 1.5 3.5 9H8l-1 5.5L12.5 7H8z" },
        "undo":          { s: "M5.5 3.5 2.5 6.5l3 3M2.5 6.5h7a3.5 3.5 0 0 1 0 7H7" },
        "sidebar":       { s: "M3.5 2.5h9a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1zM6.5 2.5v11" }
    })
    readonly property var _g: _glyphs[name] || ({})

    Shape {
        width: 16
        height: 16
        scale: root.size / 16
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root._g.s ? root.color : "transparent"
            strokeWidth: root.strokeUnits
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root._g.s || "" }
        }
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: -1
            fillColor: root._g.f ? root.color : "transparent"
            PathSvg { path: root._g.f || "" }
        }
    }
}
