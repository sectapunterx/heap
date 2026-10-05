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
    readonly property string hint: item.shortcutId.length > 0
        ? (AppController.shortcuts, AppController.shortcutFor(item.shortcutId)) : ""
    readonly property bool _check: item.marked || (item.checkable && item.checked)
    readonly property bool _arrow: item.subMenu !== null || item.opensList
    // The width the row wants for its whole label, hint and arrow. AppMenu
    // sizes itself from this; it does not depend on the row's own width, so
    // the menu and its rows do not chase each other (VISP-5).
    // A row that brings its own contentItem is measured by that.
    readonly property real _arrowW: item._arrow && arrowText ? Theme.spMd + arrowText.implicitWidth : 0
    readonly property real _hintW: item.hint.length > 0 ? Theme.sp2xl + hintText.implicitWidth : 0
    readonly property real naturalWidth: labelRow && item.contentItem === labelRow
        ? item.leftPadding + Theme.fsMd + Theme.spMd + labelText.implicitWidth + item._hintW + item._arrowW + item.rightPadding
        : item.implicitWidth

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)
    topPadding: Theme.spSm
    bottomPadding: Theme.spSm
    leftPadding: Theme.spLg
    rightPadding: Theme.spLg
    font.family: Theme.fontUi
    font.pixelSize: Theme.fsMd

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
        spacing: Theme.spMd
        // The check column is always there, so checked and unchecked rows
        // start their labels in the same place.
        Text {
            width: Theme.fsMd
            anchors.verticalCenter: parent.verticalCenter
            text: item._check ? "✓" : item.glyph
            color: item._check ? Theme.accentStrong : item.danger ? Theme.danger : Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            id: labelText
            // Never wider than the row leaves it: a row in a menu at its
            // widest elides instead of running under the panel's edge.
            width: Math.max(0, Math.min(implicitWidth,
                item.availableWidth - Theme.fsMd - Theme.spMd - item._hintW - item._arrowW))
            anchors.verticalCenter: parent.verticalCenter
            text: item.text
            textFormat: Text.PlainText
            color: !item.enabled ? Theme.textDim
                 : item.danger ? Theme.danger
                 : item._check ? Theme.accentStrong
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
            visible: item.enabled && item.highlighted
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height - 2 * Theme.spXs
            radius: Theme.radiusXs
            color: Theme.focusRing
        }
    }
}
