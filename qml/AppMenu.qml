import QtQuick
import QtQuick.Controls.Basic
import TodoCpp
import "KeyRules.js" as KeyRules

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
    // Whether the rows keep a check / glyph column (R3-041): only when one
    // of them has a glyph, a ring or a check to show.
    readonly property bool glyphColumn: {
        for (let i = 0; i < menu.count; i++) {
            const it = menu.itemAt(i) as AppMenuItem;
            if (it && it.visible && it._ownCol) return true;
        }
        return false;
    }
    // A list opened from a row goes back on Esc too, and only a second Esc
    // (in the menu it came from) closes everything (APP-279).
    closePolicy: menu.backOnLeft ? (Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent)
                                 : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    signal back()
    property bool _backPending: false
    function goBack() {
        menu._backPending = true;
        menu.close();
    }
    onClosed: {
        menu._typed = "";
        if (!menu._backPending) return;
        menu._backPending = false;
        menu.back();
    }

    // Typing in a menu (APP-279): a digit runs the row that has it as its
    // number (1–4 in Priority, the columns in Status); letters find a row
    // by the start of its name, "гот" → "Готово", and a pause of a second
    // starts the search over.
    property string _typed: ""
    property real _typedAt: 0
    function typeKey(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false;
        const t = event.text;
        if (!t || t.length !== 1 || t.charCodeAt(0) <= 32 || t.charCodeAt(0) === 127) return false;
        if (t >= "1" && t <= "9") {
            for (let i = 0; i < menu.count; i++) {
                const it = menu.itemAt(i) as AppMenuItem;
                if (it && it.number === Number(t) && it.enabled && it.visible) {
                    menu.currentIndex = i;
                    it.triggered();
                    return true;
                }
            }
        }
        const now = Date.now();
        const fresh = now - menu._typedAt > 1000;
        menu._typed = KeyRules.typeAheadBuffer(menu._typed, t, now, menu._typedAt, 1000);
        menu._typedAt = now;
        const labels = [];
        for (let i = 0; i < menu.count; i++) {
            const it = menu.itemAt(i) as AppMenuItem;
            labels.push(it && it.enabled && it.visible && !it.isBack ? it.text : "");
        }
        const from = menu.currentIndex + (fresh && menu._typed.length === 1 ? 1 : 0);
        const hit = KeyRules.typeAheadMatch(labels, menu._typed, from < 0 ? 0 : from % Math.max(1, menu.count));
        if (hit >= 0) menu.currentIndex = hit;
        return true;
    }

    // As wide as the longest row, between the old fixed 200px and a cap
    // past which a row elides. A fixed 200px cut Russian rows mid-letter
    // ("Запланировать в календар") with no ellipsis (VISP-5). Measured from
    // each row's naturalWidth, which does not depend on the row's own width,
    // so the menu's width and its rows' widths do not chase each other.
    property int minWidth: 200
    // The check / glyph column is drawn only when a row of this menu uses
    // it (R3-101): a menu of plain actions starts its labels at the row's
    // padding, as the sheets draw every menu without marks.
    readonly property bool glyphColumn: {
        for (let i = 0; i < menu.count; i++) {
            const it = menu.itemAt(i) as AppMenuItem;
            if (it && it.visible && (it.glyph.length > 0 || it.ring.length > 0 || it.marked || it.checkable))
                return true;
        }
        return false;
    }
    readonly property int maxWidth: 360
    contentWidth: {
        let w = menu.minWidth - menu.leftPadding - menu.rightPadding;
        // The header line counts too, so "APP-109 · Рефакторинг обработчика
        // вебхуков" fits up to the cap (R3-047).
        for (let i = 0; i < menu.count; i++) {
            const it = menu.itemAt(i) as AppMenuItem;
            const head = menu.itemAt(i) as AppMenuHeader;
            if (it && it.visible) w = Math.max(w, it.naturalWidth);
            else if (head && head.visible) w = Math.max(w, head.naturalWidth);
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
