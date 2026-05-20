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

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    property var draft: ({})
    property bool isNew: false

    function showFor(initialDraft) {
        draft = initialDraft || {};
        isNew = !!draft._isNew;
        idField.text = draft.id || "";
        titleField.text = draft.title || "";
        descField.text = draft.desc || "";
        statusBox.currentIndex = Math.max(0, statusList().indexOf(draft.status));
        priBox.currentIndex = Math.max(0, ["P0", "P1", "P2", "P3"].indexOf(draft.priority || "P2"));
        branchField.text = draft.branch || "";
        deadlineField.text = formatDate(draft.deadline);
        open();
        // Kick a one-shot PR/state refresh for this task's branch across all
        // watched repos. Result lands on TaskModel via repoStateUpdated and
        // chips on the underlying TaskCard update without re-opening.
        if (draft.id && !isNew) AppController.refreshGitForTaskBranch(draft.id);
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
        return d.getFullYear() + "-" + (d.getMonth() + 1).toString().padStart(2, "0") + "-" + d.getDate().toString().padStart(2, "0");
    }

    function parseDate(s) {
        if (!s) return undefined;
        const r = AppController.parseDateTime(s, new Date());
        if (r && r.ok && r.start) return r.start;
        const parts = s.split("-");
        if (parts.length !== 3) return undefined;
        return new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
    }

    property var _deadlinePreview: ({ok: false})

    function _refreshDeadlinePreview() {
        const s = deadlineField.text;
        if (!s) {
            _deadlinePreview = {ok: false};
            return;
        }
        _deadlinePreview = AppController.parseDateTime(s, new Date()) || {ok: false};
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
        Item {
            Layout.preferredHeight: 4
        }

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
            Item {
                Layout.fillWidth: true
            }
        }

        FieldLabel {
            text: "ID ТИКЕТА"; Layout.leftMargin: 18; Layout.rightMargin: 18
        }
        TextField {
            id: idField
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            placeholderText: "LTE-XXXX"
            font.family: Theme.fontMono
            background: FieldBg {
            }
            color: Theme.text
            placeholderTextColor: Theme.textDim
            onTextChanged: text = text.toUpperCase()
        }

        FieldLabel {
            text: "ЗАГОЛОВОК"; Layout.leftMargin: 18; Layout.rightMargin: 18
        }
        TextField {
            id: titleField
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            placeholderText: "Короткое summary"
            background: FieldBg {
            }
            color: Theme.text
            placeholderTextColor: Theme.textDim
        }

        FieldLabel {
            text: "ОПИСАНИЕ"; Layout.leftMargin: 18; Layout.rightMargin: 18
        }
        ScrollView {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.fillWidth: true
            Layout.preferredHeight: 70
            TextArea {
                id: descField
                placeholderText: "Контекст, ссылки, спецификация…"
                wrapMode: TextEdit.Wrap
                background: FieldBg {
                }
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
            FieldLabel {
                text: "СТАТУС"
            }
            FieldLabel {
                text: "ПРИОРИТЕТ"
            }
            ComboBox {
                id: statusBox
                Layout.fillWidth: true
                model: root.statusNames()
                background: FieldBg {
                }
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
                model: ["P0", "P1", "P2", "P3"]
                background: FieldBg {
                }
                contentItem: Text {
                    text: priBox.displayText
                    color: Theme.text
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                }
            }
            FieldLabel {
                text: "ДЕДЛАЙН (любой формат)"
            }
            FieldLabel {
                text: "BRANCH"
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                TextField {
                    id: deadlineField
                    Layout.fillWidth: true
                    placeholderText: "завтра, 22 мая, in 2 weeks…"
                    font.family: Theme.fontMono
                    background: Rectangle {
                        radius: 6
                        color: Theme.panel2
                        border.color: deadlineField.text.length === 0
                            ? Theme.border
                            : (root._deadlinePreview && root._deadlinePreview.ok
                                ? (Theme.accent || Theme.borderStrong)
                                : (Theme.danger || "#c0392b"))
                        border.width: 1
                    }
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    onTextChanged: deadlinePreviewTimer.restart()
                    onEditingFinished: {
                        if (root._deadlinePreview && root._deadlinePreview.ok &&
                            root._deadlinePreview.start) {
                            text = root.formatDate(root._deadlinePreview.start);
                        }
                    }
                    ToolTip.visible: hovered && text.length > 0 &&
                        root._deadlinePreview && !root._deadlinePreview.ok
                    ToolTip.text: "не распознано"
                }
                Timer {
                    id: deadlinePreviewTimer
                    interval: 80
                    repeat: false
                    onTriggered: root._refreshDeadlinePreview()
                }
                Rectangle {
                    visible: root._deadlinePreview && root._deadlinePreview.ok
                    radius: 10
                    color: Theme.panel2
                    border.color: Theme.accent || Theme.borderStrong
                    border.width: 1
                    implicitHeight: chipLabel.implicitHeight + 6
                    implicitWidth: chipLabel.implicitWidth + 14
                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        font.pixelSize: 10
                        color: Theme.text
                        text: {
                            if (!root._deadlinePreview || !root._deadlinePreview.ok ||
                                !root._deadlinePreview.start) return "";
                            const d = root._deadlinePreview.start;
                            const iso = d.getFullYear() + "-" +
                                String(d.getMonth() + 1).padStart(2, "0") + "-" +
                                String(d.getDate()).padStart(2, "0");
                            if (root._deadlinePreview.hasTime) {
                                const hh = String(d.getHours()).padStart(2, "0");
                                const mm = String(d.getMinutes()).padStart(2, "0");
                                // ⏱ hint: a focus block will be created
                                return "↑ " + iso + " " + hh + ":" + mm + (root.isNew ? " ⏱" : "");
                            }
                            return "↑ " + iso;
                        }
                    }
                }
            }
            TextField {
                id: branchField
                Layout.fillWidth: true
                placeholderText: "fix/..."
                font.family: Theme.fontMono
                background: FieldBg {
                }
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
            Item {
                Layout.fillWidth: true
            }
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
                    // Task only stores QDate. If the user typed an explicit
                    // time ("завтра в 18:00") on a brand-new task, expose it
                    // via a focus block on the calendar — otherwise the time
                    // is silently dropped.
                    if (root.isNew
                        && root._deadlinePreview && root._deadlinePreview.ok
                        && root._deadlinePreview.hasTime
                        && root._deadlinePreview.start) {
                        const dt = root._deadlinePreview.start;
                        const startHour = dt.getHours() + dt.getMinutes() / 60.0;
                        AppController.scheduleTask(d.id, startHour, dt);
                    }
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
