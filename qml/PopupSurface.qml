import QtQuick
import TodoCpp

// The "popup" level of elevation (APP-182): menus, drop-downs, suggestion
// lists, tooltips and floating panels. One edge, one shadow, one radius:
// panel2 with a field-strength outline (3:1 on every surface, VISP-8) and a
// soft drop shadow, so it lifts off the cards under it. Use as
// `background: PopupSurface {}`; a popup that needs another edge for a state
// (a drop target) sets border.color itself.
Rectangle {
    id: surface
    radius: Theme.popupRadius
    color: Theme.popupFill
    border.color: Theme.popupBorder
    border.width: 1
    ElevationShadow {
        objectName: "popup-shadow"
        offset: Theme.popupShadowOffset
        depth: Theme.popupShadowDepth
        radius: surface.radius
        color: Theme.popupShadow
    }
}
