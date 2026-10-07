pragma ComponentBehavior: Bound

import QtQuick
import TodoCpp

// Settings → Appearance → Cursor colour (APP-174): the theme's accent first,
// then the ten swatches. `value` is the stored pick, "" for the accent;
// `selected` hands back the new one.
SettingsRow {
    id: ccRow
    property string value: ""
    signal selected(string color)
    readonly property var options: [""].concat(Theme.swatches)
    Row {
        spacing: Theme.spSm
        Repeater {
            model: ccRow.options
            delegate: Rectangle {
                id: ccDot
                required property string modelData
                required property int index
                readonly property bool picked: ccRow.value === ccDot.modelData.toLowerCase()
                objectName: "cursor-color-" + (ccDot.index === 0 ? "accent" : ccDot.index)
                width: 24; height: 24; radius: 12
                color: ccDot.modelData.length ? ccDot.modelData : Theme.accent
                border.color: ccDot.picked ? Theme.text : Theme.border
                border.width: ccDot.picked ? 2 : 1
                ClickArea {
                    label: ccDot.index === 0 ? I18n.t("settings.appearance.cursorColor.accent")
                                             : I18n.t("swatch.name").arg(ccDot.index)
                    role: Accessible.RadioButton
                    checkable: true
                    checked: ccDot.picked
                    onActivated: ccRow.selected(ccDot.modelData)
                }
            }
        }
    }
}
