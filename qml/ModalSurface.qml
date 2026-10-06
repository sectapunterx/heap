import QtQuick
import TodoCpp

// The "modal" level of elevation (APP-182): dialogs and editors that take
// the screen. A larger radius and a deeper shadow than a popup, and always
// over a ModalScrim, which is what says the page behind is on hold. Use as
// `background: ModalSurface {}`.
Rectangle {
    id: surface
    radius: Theme.modalRadius
    color: Theme.modalFill
    border.color: Theme.modalBorder
    border.width: 1
    ElevationShadow {
        objectName: "modal-shadow"
        offset: Theme.modalShadowOffset
        depth: Theme.modalShadowDepth
        radius: surface.radius
        color: Theme.modalShadow
    }
}
