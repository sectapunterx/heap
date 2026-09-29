import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

// Every context and drop-down menu in the app. Basic's own Menu is a square
// box in the window colour with 40px rows, drawn black whatever the theme
// said; this is a themed panel with compact rows. Items are AppMenuItem and
// AppMenuSeparator.
Menu {
    id: menu
    topPadding: Theme.spXs
    bottomPadding: Theme.spXs
    leftPadding: Theme.spXs
    rightPadding: Theme.spXs
    // Actions and dynamic insertItem() calls get the themed row too.
    delegate: AppMenuItem {}

    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 32
        radius: Theme.radiusLg
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.scaledMs(90) }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.scaledMs(70) }
    }
}
