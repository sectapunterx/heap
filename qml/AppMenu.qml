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

    // A list opened from a row of another menu (the card's Status ›,
    // Priority ›) goes back to that menu on Left, as a cascading submenu
    // does (PERA-2). The owner reopens the parent on back(), once this list
    // has finished closing, so focus is handed over in one direction only.
    property bool backOnLeft: false
    signal back()
    property bool _backPending: false
    function goBack() {
        menu._backPending = true;
        menu.close();
    }
    onClosed: {
        if (!menu._backPending) return;
        menu._backPending = false;
        menu.back();
    }

    // As wide as the longest row, between the old fixed 200px and a cap
    // past which a row elides. A fixed 200px cut Russian rows mid-letter
    // ("Запланировать в календар") with no ellipsis (VISP-5). Measured from
    // each row's naturalWidth, which does not depend on the row's own width,
    // so the menu's width and its rows' widths do not chase each other.
    readonly property int minWidth: 200
    readonly property int maxWidth: 360
    contentWidth: {
        let w = menu.minWidth - menu.leftPadding - menu.rightPadding;
        for (let i = 0; i < menu.count; i++) {
            const it = menu.itemAt(i) as AppMenuItem;
            if (it && it.visible) w = Math.max(w, it.naturalWidth);
        }
        return Math.min(w, menu.maxWidth - menu.leftPadding - menu.rightPadding);
    }

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

    // A raised surface (VISP-8): panel was the colour of the board's columns
    // and the hairline borderStrong 1.2:1 against them, so a card menu ran
    // into the cards under it. The popup level of elevation (APP-182) lifts
    // it off the page, like every drop-down, suggestion list and tooltip.
    background: PopupSurface {
        implicitWidth: menu.minWidth
        implicitHeight: 32
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durPop; easing.type: Theme.easeEnter }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durPopOut; easing.type: Theme.easeExit }
    }
}
