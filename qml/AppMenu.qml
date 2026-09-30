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

    // A menu the keyboard has left is closed. Left open behind the board or
    // a dialog, it got focus back when that dialog closed, invisible to the
    // user, and the next Enter triggered whichever row it was on (PERA-1).
    // An open cascading submenu of this one does not count as leaving.
    onActiveFocusChanged: {
        if (activeFocus || !visible) return;
        const cur = menu.currentIndex >= 0 ? menu.itemAt(menu.currentIndex) as MenuItem : null;
        if (cur && cur.subMenu && cur.subMenu.visible) return;
        menu.close();
    }

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
