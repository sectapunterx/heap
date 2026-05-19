import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: false
    focus: true
    padding: 0
    width: 280
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    readonly property var accentSwatches: [
        "#5cc2dd", "#6ec18a", "#c07acf", "#dcb86b",
        "#e6624c", "#7da8d9", "#9aa3b4"
    ]

    // ── Settings JSON shadow ──────────────────────────────────────────
    property var settings: ({})

    function _reload() {
        const raw = AppController.appSettingsJson || "";
        if (!raw.length) { settings = ({}); return; }
        try { settings = JSON.parse(raw); } catch (e) { settings = ({}); }
    }
    function _setAppearance(key, val) {
        const next = Object.assign({}, settings);
        next.appearance = Object.assign({}, next.appearance || {}, { [key]: val });
        settings = next;
        AppController.appSettingsJson = JSON.stringify(next);
    }
    function _appearanceValue(key, fallback) {
        const a = (settings && settings.appearance) || ({});
        return (a[key] !== undefined) ? a[key] : fallback;
    }

    Component.onCompleted: _reload()
    Connections {
        target: AppController
        function onAppSettingsJsonChanged() { root._reload(); }
    }

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Header ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 8
                Text {
                    text: "TWEAKS"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 22; height: 22; radius: 5
                    color: closeMA.containsMouse ? Theme.panel3 : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.textDim
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: closeMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        // ── Body ──────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14; Layout.rightMargin: 14
            Layout.topMargin: 12; Layout.bottomMargin: 14
            spacing: 14

            // Внешний вид: theme + density
            ColumnLayout {
                spacing: 6
                Layout.fillWidth: true
                SectLabel { text: "Внешний вид" }
                FieldLabel { text: "Тема" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    SegButton { text: "Тёмная";  active: AppController.theme === "dark";  onClicked: AppController.theme = "dark" }
                    SegButton { text: "Светлая"; active: AppController.theme === "light"; onClicked: AppController.theme = "light" }
                }
                FieldLabel { text: "Плотность"; topPadding: 6 }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    SegButton { text: "Compact"; active: AppController.density === "compact"; onClicked: AppController.density = "compact" }
                    SegButton { text: "Comfy";   active: AppController.density === "comfy";   onClicked: AppController.density = "comfy" }
                }
            }

            // Акцент: chip row mirroring SettingsView accent picker
            ColumnLayout {
                spacing: 6
                Layout.fillWidth: true
                SectLabel { text: "Акцент" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.accentSwatches
                        delegate: Rectangle {
                            required property string modelData
                            width: 26; height: 26; radius: 13
                            color: modelData
                            border.width: 2
                            border.color: String(root._appearanceValue("accent", Theme._defaultAccent)).toLowerCase() === modelData.toLowerCase()
                                ? Theme.text
                                : "transparent"
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._setAppearance("accent", parent.modelData)
                            }
                        }
                    }
                }
            }

            // Доступность: reducedMotion + highContrast toggles
            ColumnLayout {
                spacing: 6
                Layout.fillWidth: true
                SectLabel { text: "Доступность" }
                ToggleRow {
                    label: "Reduced motion"
                    checked: !!root._appearanceValue("reducedMotion", false)
                    onToggled: (v) => root._setAppearance("reducedMotion", v)
                }
                ToggleRow {
                    label: "High contrast"
                    checked: !!root._appearanceValue("highContrast", false)
                    onToggled: (v) => root._setAppearance("highContrast", v)
                }
            }

            // Hint: deeper config still lives in Settings.
            Text {
                Layout.fillWidth: true
                text: "Все остальные параметры — в Settings"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Inline components ─────────────────────────────────────────────

    component SectLabel: Text {
        color: Theme.textDim
        font.pixelSize: 10
        font.letterSpacing: 1
        font.weight: Font.DemiBold
    }

    component FieldLabel: Text {
        color: Theme.textMuted
        font.pixelSize: 11
    }

    component SegButton: Rectangle {
        property string text: ""
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: 6
        color: active ? Theme.accent : (segMA.containsMouse ? Theme.panel3 : Theme.panel2)
        border.color: active ? "transparent" : Theme.border
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: parent.active ? "#06121a" : Theme.text
            font.pixelSize: 12
            font.weight: parent.active ? Font.DemiBold : Font.Medium
        }
        MouseArea {
            id: segMA
            x: 0; y: 0; width: parent.width; height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component ToggleRow: RowLayout {
        property string label: ""
        property bool checked: false
        signal toggled(bool v)
        Layout.fillWidth: true
        spacing: 10
        Text {
            Layout.fillWidth: true
            text: parent.label
            color: Theme.text
            font.pixelSize: 12
        }
        Rectangle {
            width: 32; height: 18; radius: 9
            color: parent.checked ? Theme.accent : Theme.panel3
            border.color: parent.checked ? "transparent" : Theme.border
            border.width: 1
            Behavior on color { ColorAnimation { duration: Theme.animMs } }
            Rectangle {
                width: 14; height: 14; radius: 7
                y: 2
                x: parent.parent.checked ? parent.width - width - 2 : 2
                color: "#ffffff"
                border.color: Qt.rgba(0, 0, 0, 0.18)
                border.width: 1
                Behavior on x { NumberAnimation { duration: Theme.animMs; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.parent.toggled(!parent.parent.checked)
            }
        }
    }
}
