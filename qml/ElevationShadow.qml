import QtQuick
import TodoCpp

// A soft drop shadow under a PopupSurface or ModalSurface (APP-182): rings
// of faint shadow colour, each one pixel wider, stack into a falloff, so
// the edge blurs instead of ending as a solid offset slab. Cheap: a few
// plain rectangles, no effect pass. Fills its parent and sits under it.
Item {
    id: sh
    // How far the light seems to come from above, and how far it spreads.
    property int offset: 0
    property int depth: 6
    property color color: "transparent"
    property real radius: 0
    anchors.fill: parent
    z: -1
    // One entry per ring, worked out here so the delegate reads only its
    // own model data.
    readonly property var _rings: {
        const out = [];
        const c = Theme.withAlpha(sh.color, sh.color.a / Math.max(1, sh.depth));
        for (let i = 1; i <= sh.depth; i++)
            out.push({ x: -i, y: sh.offset - i, w: sh.width + 2 * i, h: sh.height + 2 * i,
                       r: sh.radius + i, c: c });
        return out;
    }
    Repeater {
        model: sh._rings
        Rectangle {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            radius: modelData.r
            color: modelData.c
        }
    }
}
