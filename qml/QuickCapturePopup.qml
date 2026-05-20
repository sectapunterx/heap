import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    width: 560
    anchors.centerIn: Overlay.overlay

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

    property var _preview: ({ ok: false })
    property string _title: ""

    function _refreshPreview() {
        const raw = inputField.text;
        const r = AppController.parseDateTime(raw, new Date());
        _preview = r || { ok: false };
        if (_preview.ok && _preview.consumed && _preview.consumed.length > 0) {
            const left  = raw.substr(0, _preview.startOffset).trim();
            const right = raw.substr(_preview.endOffset).trim();
            _title = (left + " " + right).replace(/\s+/g, " ").trim();
        } else {
            _title = raw.trim();
        }
    }

    function _submit() {
        if (_title.length === 0) return;
        const draft = AppController.newTaskDraft(AppController.statuses.length > 0 ? AppController.statuses[0].id : "");
        draft._isNew = true;
        draft.title = _title;
        if (_preview && _preview.ok && _preview.start) {
            draft.deadline = _preview.start;
        }
        AppController.saveTask(draft);
        inputField.clear();
        root.close();
    }

    onOpened: {
        inputField.text = "";
        _preview = { ok: false };
        _title = "";
        inputField.forceActiveFocus();
    }

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 10
        Item { Layout.preferredHeight: 6 }

        Text {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            text: "Быстрое создание задачи"
            color: Theme.textMuted
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }

        TextField {
            id: inputField
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            placeholderText: "напр.: купить хлеб завтра в 18:00"
            font.pixelSize: 14
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            color: Theme.text
            placeholderTextColor: Theme.textDim
            onTextChanged: previewTimer.restart()
            Keys.onReturnPressed: root._submit()
            Keys.onEnterPressed: root._submit()
        }

        Timer {
            id: previewTimer
            interval: 80
            repeat: false
            onTriggered: root._refreshPreview()
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
            spacing: 8
            Text {
                visible: root._title.length > 0
                text: "" + root._title
                color: Theme.text
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Rectangle {
                visible: root._preview && root._preview.ok
                radius: 10
                color: Theme.panel2
                border.color: Theme.accent
                border.width: 1
                implicitHeight: previewChip.implicitHeight + 6
                implicitWidth:  previewChip.implicitWidth + 16
                Text {
                    id: previewChip
                    anchors.centerIn: parent
                    color: Theme.text
                    font.pixelSize: 11
                    text: {
                        if (!root._preview || !root._preview.ok) return "";
                        const d = root._preview.start;
                        if (!d) return "";
                        const iso = d.getFullYear() + "-" +
                                    String(d.getMonth() + 1).padStart(2, "0") + "-" +
                                    String(d.getDate()).padStart(2, "0");
                        if (root._preview.hasTime) {
                            const hh = String(d.getHours()).padStart(2, "0");
                            const mm = String(d.getMinutes()).padStart(2, "0");
                            return iso + " " + hh + ":" + mm;
                        }
                        return iso;
                    }
                }
            }
        }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 14
            spacing: 8
            Item { Layout.fillWidth: true }
            PillButton {
                text: "Отмена"
                onClicked: root.close()
            }
            PillButton {
                text: "Создать"
                primary: true
                enabled: root._title.length > 0
                onClicked: root._submit()
            }
        }
    }
}
