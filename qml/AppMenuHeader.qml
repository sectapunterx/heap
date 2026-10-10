import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

// The context line on top of a menu (X-Menus-*): what the menu is for —
// "Колонка «В работе» · 2 задачи", "APP-109 · Рефакторинг…". Small, dim,
// proportional; not a row the keyboard or a typed letter can land on.
MenuItem {
    id: head
    enabled: false
    topPadding: Theme.spSm
    bottomPadding: Theme.spXs
    leftPadding: Theme.spLg
    rightPadding: Theme.spLg
    // AppMenu sizes itself from its rows' naturalWidth; a long title elides
    // at the menu's cap instead of widening it.
    readonly property real naturalWidth: Math.min(implicitWidth, Theme.px(320))
    readonly property bool isBack: false
    readonly property int number: 0
    implicitWidth: label.implicitWidth + leftPadding + rightPadding
    implicitHeight: label.implicitHeight + topPadding + bottomPadding
    indicator: Item {}
    arrow: Item {}
    background: Item {}
    contentItem: Text {
        id: label
        objectName: "menu-header"
        text: head.text
        textFormat: Text.PlainText
        color: Theme.textDim
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsXs
        elide: Text.ElideRight
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: head.text
}
