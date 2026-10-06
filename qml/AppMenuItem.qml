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
    // A catalogue shortcut that does the same: shown at the row's end, and a
    // third pick with the mouse suggests the key once (APP-166).
    property string shortcutId: ""
    readonly property string _keys: item.shortcutId.length > 0 && AppController.shortcuts.length >= 0
                                    ? AppController.shortcutFor(item.shortcutId) : ""
    // The menu's own keys highlight a row without hovering it.
    onTriggered: if (item._keys.length > 0 && item.hovered) AppController.noteMouseAction(item.shortcutId)
    readonly property bool _check: item.marked || (item.checkable && item.checked)

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

    indicator: Item {}
    arrow: Text {
        visible: item.subMenu !== null
        x: item.width - width - item.rightPadding
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: Theme.textDim
        font.pixelSize: Theme.fsLg
    }

    contentItem: Row {
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
        Text {
            visible: item._keys.length > 0
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Theme.spLg
            text: item._keys
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsXs
        }
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
