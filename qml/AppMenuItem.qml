import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

// A row of an AppMenu: the label in the theme's text colour, a hover tint,
// a check mark for the selected option, and an optional glyph in a column of
// its own so the labels line up whether or not a row has one.
MenuItem {
    id: item
    // A text glyph shown before the label ("↗", "⎘" …).
    property string glyph: ""
    // A stage ring in the glyph column (the column's "Этап колонки" list).
    property string ring: ""
    // Marks the current choice without making the row a toggle — a list of
    // profiles, say, where picking one is an action, not a switch.
    property bool marked: false
    // A destructive action (Delete): the label in the danger colour.
    property bool danger: false
    // The row opens a list of its own (the card's Status ›, Priority ›)
    // rather than acting: drawn with the submenu arrow, and Right opens it as
    // Enter does, the way a cascading submenu opens (PERA-2).
    property bool opensList: false
    // The catalog action this row also has a key for. The key is shown at
    // the end of the row, dim, as a desktop menu shows its accelerators, so
    // a single-key action can be learnt from the menu (PERA-3).
    property string shortcutId: ""
    // A word at the row's end, before its key (heap 2, APP-268): why the
    // row is off ("no branch yet"), or "now" on the current choice.
    property string note: ""
    // What the note means, on hover or keyboard focus ("the tracker is not
    // changed: writing to it is off").
    property string noteTip: ""
    ToolTip.visible: item.noteTip.length > 0 && (item.hovered || item.highlighted)
    ToolTip.delay: 500
    ToolTip.text: item.noteTip
    // A key that works in this menu only — a column's number in Status.
    property string keyText: ""
    // The digit that runs this row while its menu is open (1–4 in Priority).
    property int number: 0
    // The "‹ Priority" row on top of a list opened from another menu. It
    // reads as the menu's small grey header line (X-Menus-Task, R3-042),
    // and still goes back on a click or Enter.
    property bool isBack: false
    // A label colour of the row's own (the priority list's P0 / P1 in bold,
    // N-Menus-Task, R3-043); transparent = the usual colour.
    property color labelColor: "transparent"
    property int labelWeight: Theme.fwBody
    // The check / glyph column is drawn only when a row of the menu has a
    // glyph, a ring or a check; otherwise labels start on the header's left
    // edge (R3-041).
    readonly property bool _ownCol: item.ring.length > 0 || item.glyph.length > 0 || item.checkable || item.marked
    readonly property bool _col: {
        const m = item.menu as AppMenu;
        return m ? m.glyphColumn : item._ownCol;
    }
    readonly property real _colW: item._col ? Theme.fsMd + Theme.spMd : 0
    // Written the way every key is (keymap.md, APP-279): "s", "Shift S",
    // "y y", "Enter", from the one catalogue, so a rebinding shows here too.
    readonly property string hint: item.shortcutId.length > 0
        ? (AppController.shortcuts.length >= 0 ? AppController.shortcutText(item.shortcutId) : "") : item.keyText
    // A third pick of the row with the mouse suggests its key once (APP-166).
    onTriggered: if (item.shortcutId.length > 0 && item.hint.length > 0 && item.hovered) AppController.noteMouseAction(item.shortcutId)
    readonly property bool _check: item.marked || (item.checkable && item.checked)
    readonly property bool _arrow: item.subMenu !== null || item.opensList
    // The width the row wants for its whole label, hint and arrow. AppMenu
    // sizes itself from this; it does not depend on the row's own width, so
    // the menu and its rows do not chase each other (VISP-5).
    // A row that brings its own contentItem is measured by that.
    readonly property real _arrowW: item._arrow && arrowText ? Theme.spMd + arrowText.implicitWidth : 0
    readonly property real _hintW: (item.hint.length > 0 ? Theme.sp2xl + hintText.implicitWidth : 0)
                                   + (item.note.length > 0 ? Theme.sp2xl + noteText.implicitWidth : 0)
    readonly property real naturalWidth: labelRow && item.contentItem === labelRow
        ? item.leftPadding + item._colW + labelText.implicitWidth + item._hintW + item._arrowW + item.rightPadding
        : item.implicitWidth

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)
    topPadding: Theme.spSm
    bottomPadding: item.isBack ? Theme.spXs : Theme.spSm
    leftPadding: Theme.spLg
    rightPadding: Theme.spLg
    font.family: Theme.fontUi
    font.pixelSize: item.isBack ? Theme.fsXs : Theme.fsMd
    font.weight: item.labelWeight
    // Right opens a row's list, as it opens a cascading submenu; Left in a
    // list that came from a row goes back to the menu it came from.
    Keys.onRightPressed: (event) => {
        if (item.opensList && item.enabled) { item.triggered(); event.accepted = true; }
        else event.accepted = false;
    }
    Keys.onLeftPressed: (event) => {
        const m = item.menu as AppMenu;
        if (m && m.backOnLeft) { m.goBack(); event.accepted = true; }
        else event.accepted = false;
    }
    // Esc in such a list goes back to the menu it came from; the menu's own
    // Esc then closes everything.
    Keys.onEscapePressed: (event) => {
        const m = item.menu as AppMenu;
        if (m && m.backOnLeft) { m.goBack(); event.accepted = true; }
        else event.accepted = false;
    }
    Keys.onPressed: (event) => {
        const m = item.menu as AppMenu;
        event.accepted = !!m && m.typeKey(event);
    }

    indicator: Item {}
    arrow: Text {
        id: arrowText
        visible: item._arrow
        x: item.width - width - item.rightPadding
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: Theme.textDim
        font.pixelSize: Theme.fsLg
    }

    contentItem: Row {
        id: labelRow
        spacing: item._col ? Theme.spMd : 0
        // The check column is there whenever a row of the menu uses it, so
        // checked and unchecked rows start their labels in the same place.
        Item {
            visible: item._col
            width: Theme.fsMd
            height: Math.max(glyphText.implicitHeight, Theme.statusRingSize)
            anchors.verticalCenter: parent.verticalCenter
            Text {
                id: glyphText
                anchors.fill: parent
                visible: item.ring.length === 0
                text: item._check ? "✓" : item.glyph
                color: item._check ? Theme.accentStrong : item.danger ? Theme.dangerInk : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            StatusRing {
                anchors.centerIn: parent
                visible: item.ring.length > 0
                category: item.ring.length > 0 ? item.ring : "todo"
            }
        }
        Text {
            id: labelText
            // Never wider than the row leaves it: a row in a menu at its
            // widest elides instead of running under the panel's edge.
            width: Math.max(0, Math.min(implicitWidth,
                item.availableWidth - item._colW - item._hintW - item._arrowW))
            anchors.verticalCenter: parent.verticalCenter
            text: item.text
            textFormat: Text.PlainText
            color: !item.enabled ? Theme.textDim
                 : item.isBack ? Theme.textDim
                 : item.danger ? Theme.dangerInk
                 : item._check ? Theme.accentStrong
                 : item.labelColor.a > 0 ? item.labelColor
                 : Theme.text
            font: item.font
            elide: Text.ElideRight
        }
    }

    Text {
        id: hintText
        objectName: "menu-row-hint"
        visible: item.hint.length > 0
        x: item.width - width - item.rightPadding - item._arrowW
        anchors.verticalCenter: parent.verticalCenter
        text: item.hint
        textFormat: Text.PlainText
        color: Theme.textDim
        font.family: Theme.fontMono
        font.pixelSize: Theme.fsXs
    }

    Text {
        id: noteText
        objectName: "menu-row-note"
        visible: item.note.length > 0
        x: item.width - width - item.rightPadding - item._arrowW
           - (item.hint.length > 0 ? hintText.implicitWidth + Theme.spLg : 0)
        anchors.verticalCenter: parent.verticalCenter
        text: item.note
        textFormat: Text.PlainText
        color: Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsXs
    }

    background: Rectangle {
        implicitWidth: 180
        implicitHeight: 28
        radius: Theme.radiusSm
        color: !item.enabled ? "transparent"
             : (item.down || item.highlighted) ? Theme.rowHighlight
             : "transparent"
        // panel2 on the menu's panel was 1.03:1 — the keyboard's place in a
        // menu could not be seen. A focusRing bar marks the highlighted row.
        Rectangle {
            objectName: "menu-row-marker"
            // The quiet sheets mark the row by its fill alone (R3-102).
            visible: item.enabled && item.highlighted && Style.fills
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height - 2 * Theme.spXs
            radius: Theme.radiusXs
            color: Theme.focusRing
        }
    }
}
