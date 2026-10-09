import QtQuick
import QtQuick.Layouts
import TodoCpp

// The one filter line over every lens of "Tasks" (APP-259/261): conditions
// as chips (× drops one), then the same input language as quick capture and
// the command line (p1, @week, #label, status, due…). `/` focuses it from
// anywhere in the view (keymap.md), Esc gives the cursor back.
Item {
    id: root

    // [{ key, value }]
    property var conditions: []
    property alias text: input.text
    property string placeholder: I18n.t("query.placeholder")
    property bool canSave: conditions.length > 0

    signal conditionRemoved(int index)
    signal conditionClicked(int index)
    signal submitted(string text)
    signal saveRequested()
    signal escaped()

    implicitHeight: Math.max(Theme.chipH + 2 * Theme.spSm, flow.implicitHeight + 2 * Theme.spSm)

    function focusInput() { input.forceActiveFocus(); }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Style.chipFill ? Theme.panel : "transparent"
        border.width: Style.chipFill || input.activeFocus ? 1 : 0
        border.color: input.activeFocus ? Theme.focusRing : Theme.border
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spLg
        anchors.rightMargin: Theme.spLg
        spacing: Theme.spMd

        Flow {
            id: flow
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spMd
            Repeater {
                model: root.conditions
                delegate: PropertyChip {
                    required property var modelData
                    required property int index
                    small: true
                    removable: true
                    key: modelData.key
                    value: modelData.value
                    onRemoved: root.conditionRemoved(index)
                    onClicked: root.conditionClicked(index)
                }
            }
            TextInput {
                id: input
                objectName: "query-input"
                width: Math.max(Theme.chipMaxW, flow.width - x - Theme.spMd)
                height: Theme.chipHSmall
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                selectionColor: Theme.accentSoft
                selectedTextColor: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                clip: true
                Accessible.role: Accessible.EditableText
                Accessible.name: I18n.t("query.label")
                Keys.onReturnPressed: root.submitted(text)
                Keys.onEscapePressed: root.escaped()
                Keys.onPressed: (e) => {
                    // Backspace on an empty input takes the last condition back.
                    if (e.key === Qt.Key_Backspace && text.length === 0 && root.conditions.length > 0) {
                        root.conditionRemoved(root.conditions.length - 1);
                        e.accepted = true;
                    }
                }
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: input.text.length === 0
                    text: root.placeholder
                    color: Theme.textDim
                    font: input.font
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            visible: root.canSave
            Layout.alignment: Qt.AlignVCenter
            text: I18n.t("query.saveView")
            color: saveArea.hovered ? Theme.text : Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            ClickArea { id: saveArea; label: parent.text; shortcutId: "view.save"; onActivated: root.saveRequested() }
        }
    }
}
