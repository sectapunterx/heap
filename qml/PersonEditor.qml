import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    width: 460
    anchors.centerIn: Overlay.overlay

    property var draft: ({})
    property bool isNew: false

    readonly property var palette: [
        "#d97a6c", "#c87fc7", "#6cc4b8", "#7da8d9",
        "#dcc06a", "#7cc492", "#e69854", "#a4a4d6"
    ]
    readonly property var states: ["todo", "pinged", "replied"]
    readonly property var stateLabels: ({ todo: "написать", pinged: "написал", replied: "ответил" })

    function showFor(initialDraft) {
        draft = initialDraft || {};
        isNew = !!draft._isNew;
        nameField.text     = draft.name || "";
        roleField.text     = draft.role || "";
        questionField.text = draft.question || "";
        stateBox.currentIndex = Math.max(0, states.indexOf(draft.state || "todo"));
        const cur = String(draft.color || palette[0]).toLowerCase();
        let i = 0;
        for (let k = 0; k < palette.length; k++)
            if (palette[k].toLowerCase() === cur) { i = k; break; }
        colorSwatch.selectedIndex = i;
        open();
    }

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 12
        Item { Layout.preferredHeight: 4 }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: root.isNew ? "Новый контакт" : "Редактировать контакт"
            color: Theme.text
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Text { Layout.leftMargin: 18; Layout.rightMargin: 18; text: "ИМЯ"
               color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        TextField {
            id: nameField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            placeholderText: "Иван Иванов"
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
            placeholderTextColor: Theme.textDim
        }

        Text { Layout.leftMargin: 18; Layout.rightMargin: 18; text: "РОЛЬ"
               color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        TextField {
            id: roleField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            placeholderText: "Tech Lead / QA / PHY team…"
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
            placeholderTextColor: Theme.textDim
        }

        Text { Layout.leftMargin: 18; Layout.rightMargin: 18; text: "ВОПРОС / ЗАДАЧА"
               color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        ScrollView {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            Layout.preferredHeight: 64
            TextArea {
                id: questionField
                placeholderText: "О чём написать…"
                wrapMode: TextEdit.Wrap
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text { text: "СТАТУС"; color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                ComboBox {
                    id: stateBox
                    Layout.fillWidth: true
                    model: ["написать", "написал", "ответил"]
                    background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                    contentItem: Text { text: stateBox.displayText; color: Theme.text; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text { text: "ЦВЕТ АВАТАРА"; color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                Row {
                    id: colorSwatch
                    property int selectedIndex: 0
                    spacing: 4
                    Repeater {
                        model: root.palette
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: 22; height: 22; radius: 11
                            color: modelData
                            border.color: colorSwatch.selectedIndex === index ? Theme.text : "transparent"
                            border.width: 2
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: colorSwatch.selectedIndex = index
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.topMargin: 8; Layout.bottomMargin: 16
            spacing: 8
            PillButton {
                visible: !root.isNew
                text: "Удалить"; danger: true
                onClicked: {
                    AppController.deletePerson(root.draft.id);
                    root.close();
                }
            }
            Item { Layout.fillWidth: true }
            PillButton { text: "Отмена"; onClicked: root.close() }
            PillButton {
                text: root.isNew ? "Добавить" : "Сохранить"
                primary: true
                onClicked: {
                    const d = {
                        _isNew: root.isNew,
                        id: root.draft.id,
                        name: nameField.text,
                        role: roleField.text,
                        question: questionField.text,
                        state: root.states[stateBox.currentIndex],
                        color: root.palette[colorSwatch.selectedIndex]
                    };
                    AppController.savePerson(d);
                    root.close();
                }
            }
        }
    }
}
