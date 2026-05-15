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
    width: 480

    property var draft: ({})
    property bool isNew: false

    function showFor(initialDraft) {
        draft = initialDraft || {};
        isNew = !!draft._isNew;
        idField.text     = draft.id || "";
        titleField.text  = draft.title || "";
        descField.text   = draft.desc || "";
        statusBox.currentIndex = Math.max(0, statusList().indexOf(draft.status));
        priBox.currentIndex    = Math.max(0, ["P0","P1","P2","P3"].indexOf(draft.priority || "P2"));
        branchField.text = draft.branch || "";
        deadlineField.text = formatDate(draft.deadline);
        open();
    }
    function statusList() {
        const out = [];
        const sts = AppController.statuses;
        for (let i = 0; i < sts.length; i++) out.push(sts[i].id);
        return out;
    }
    function statusNames() {
        const out = [];
        const sts = AppController.statuses;
        for (let i = 0; i < sts.length; i++) out.push(sts[i].name);
        return out;
    }
    function formatDate(d) {
        if (!d || !d.getFullYear) return "";
        return d.getFullYear() + "-" + (d.getMonth()+1).toString().padStart(2,"0") + "-" + d.getDate().toString().padStart(2,"0");
    }
    function parseDate(s) {
        if (!s) return undefined;
        const parts = s.split("-");
        if (parts.length !== 3) return undefined;
        return new Date(parseInt(parts[0]), parseInt(parts[1])-1, parseInt(parts[2]));
    }

    anchors.centerIn: Overlay.overlay

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 12
        // padding via Item margins
        Item { Layout.preferredHeight: 4 }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            spacing: 8
            Text {
                text: root.isNew ? "Новая задача" : "Редактировать задачу"
                color: Theme.text
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                visible: !root.isNew
                text: idField.text
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: 12
                font.weight: Font.Medium
            }
            Item { Layout.fillWidth: true }
        }

        FieldLabel { text: "ID ТИКЕТА"; Layout.leftMargin: 18; Layout.rightMargin: 18 }
        TextField {
            id: idField
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            placeholderText: "LTE-XXXX"
            font.family: Theme.fontMono
            background: FieldBg {}
            color: Theme.text
            placeholderTextColor: Theme.textDim
            onTextChanged: text = text.toUpperCase()
        }

        FieldLabel { text: "ЗАГОЛОВОК"; Layout.leftMargin: 18; Layout.rightMargin: 18 }
        TextField {
            id: titleField
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            placeholderText: "Короткое summary"
            background: FieldBg {}
            color: Theme.text
            placeholderTextColor: Theme.textDim
        }

        FieldLabel { text: "ОПИСАНИЕ"; Layout.leftMargin: 18; Layout.rightMargin: 18 }
        ScrollView {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            Layout.preferredHeight: 70
            TextArea {
                id: descField
                placeholderText: "Контекст, ссылки, спецификация…"
                wrapMode: TextEdit.Wrap
                background: FieldBg {}
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }
        }

        GridLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 4
            FieldLabel { text: "СТАТУС" }
            FieldLabel { text: "ПРИОРИТЕТ" }
            ComboBox {
                id: statusBox
                Layout.fillWidth: true
                model: root.statusNames()
                background: FieldBg {}
                contentItem: Text {
                    text: statusBox.displayText
                    color: Theme.text
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                }
            }
            ComboBox {
                id: priBox
                Layout.fillWidth: true
                model: ["P0","P1","P2","P3"]
                background: FieldBg {}
                contentItem: Text {
                    text: priBox.displayText
                    color: Theme.text
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                }
            }
            FieldLabel { text: "ДЕДЛАЙН (YYYY-MM-DD)" }
            FieldLabel { text: "BRANCH" }
            TextField {
                id: deadlineField
                Layout.fillWidth: true
                placeholderText: "2026-05-22"
                font.family: Theme.fontMono
                background: FieldBg {}
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }
            TextField {
                id: branchField
                Layout.fillWidth: true
                placeholderText: "fix/..."
                font.family: Theme.fontMono
                background: FieldBg {}
                color: Theme.text
                placeholderTextColor: Theme.textDim
            }
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.topMargin: 8; Layout.bottomMargin: 16
            spacing: 8
            PillButton {
                visible: !root.isNew
                text: "Удалить"
                danger: true
                onClicked: {
                    AppController.deleteTask(idField.text);
                    root.close();
                }
            }
            Item { Layout.fillWidth: true }
            PillButton {
                text: "Отмена"
                onClicked: root.close()
            }
            PillButton {
                text: root.isNew ? "Создать" : "Сохранить"
                primary: true
                onClicked: {
                    const d = {
                        _isNew: root.isNew,
                        id: idField.text,
                        title: titleField.text,
                        desc: descField.text,
                        priority: priBox.currentText,
                        status: root.statusList()[statusBox.currentIndex],
                        deadline: root.parseDate(deadlineField.text),
                        branch: branchField.text
                    };
                    AppController.saveTask(d);
                    root.close();
                }
            }
        }
    }

    component FieldLabel: Text {
        color: Theme.textMuted
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        topPadding: 2
    }
    component FieldBg: Rectangle {
        radius: 6
        color: Theme.panel2
        border.color: Theme.border
        border.width: 1
    }
}
