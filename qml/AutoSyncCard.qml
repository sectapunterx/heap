pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// Settings → Integrations → Auto-sync (integrations.autoSyncMinutes, 0 =
// off). Quick picks, or any number of minutes, hours or days up to a month
// (APP-123). AppController checks at most hourly and keeps the last sync's
// time on disk, so even a monthly pull survives restarts.
Rectangle {
    id: root
    objectName: "auto-sync-card"

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Theme.sp2xl * 2
    radius: Theme.radiusLg
    color: Theme.panel
    border.color: Theme.border
    border.width: 1

    // A month, in minutes: the longest cadence offered.
    readonly property int maxMinutes: 44640
    readonly property var _settings: {
        try { return JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { return {}; }
    }
    readonly property int cur: (_settings.integrations && _settings.integrations.autoSyncMinutes) || 0
    // The unit the custom field speaks: the largest that divides the current
    // cadence, until the user picks another.
    property int unit: cur > 0 && cur % 1440 === 0 ? 1440 : (cur > 0 && cur % 60 === 0 ? 60 : 1)

    function setMinutes(m) {
        const s = Object.assign({}, root._settings);
        s.integrations = Object.assign({}, s.integrations || {}, { autoSyncMinutes: Math.max(0, Math.min(m, root.maxMinutes)) });
        AppController.appSettingsJson = JSON.stringify(s);
    }
    function setCustom(text) {
        root.setMinutes((parseInt(text || "0") || 0) * root.unit);
    }

    // A pill: the quick picks and the units share it.
    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool active: false
        property string name: ""
        signal picked()
        radius: Theme.radiusMd
        implicitWidth: pillTxt.implicitWidth + 20
        implicitHeight: 26
        Layout.minimumWidth: implicitWidth
        color: active ? Theme.accent : (pillMA.hovered ? Theme.panel3 : Theme.panel2)
        border.color: active ? Theme.accent : Theme.border
        border.width: 1
        Text {
            id: pillTxt
            anchors.centerIn: parent
            text: pill.label
            color: pill.active ? Theme.textOnAccent : Theme.text
            font.pixelSize: Theme.fsSm
        }
        ClickArea {
            id: pillMA
            objectName: pill.name
            label: pill.label
            showTip: false
            role: Accessible.RadioButton
            checkable: true
            checked: pill.active
            onActivated: pill.picked()
        }
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.sp2xl
        spacing: Theme.spMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spXl
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { text: I18n.t("settings.integrations.autoSync"); color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Theme.fwTitle }
                Text { text: I18n.t("settings.integrations.autoSyncHint"); color: Theme.textMuted; font.pixelSize: Theme.fsMd; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
            Repeater {
                model: [
                    { label: I18n.t("settings.integrations.off"), v: 0 },
                    { label: I18n.t("settings.integrations.every15m"), v: 15 },
                    { label: I18n.t("settings.integrations.every1h"), v: 60 },
                    { label: I18n.t("settings.integrations.every1d"), v: 1440 },
                    { label: I18n.t("settings.integrations.every1w"), v: 10080 }
                ]
                delegate: Pill {
                    required property var modelData
                    label: modelData.label
                    name: "settings-autosync-" + modelData.v
                    active: root.cur === modelData.v
                    onPicked: root.setMinutes(modelData.v)
                }
            }
        }

        // Any other cadence, up to a month.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spMd
            Text { text: I18n.t("settings.integrations.every"); color: Theme.textMuted; font.pixelSize: Theme.fsMd }
            TextField {
                id: field
                ContextMenu.menu: TextEditMenu { editor: field }
                objectName: "settings-autosync-custom"
                Layout.preferredWidth: 72
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: root.maxMinutes }
                text: root.cur > 0 ? String(root.cur / root.unit) : ""
                placeholderText: "0"
                color: Theme.text
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                background: FieldFrame {}
                onEditingFinished: root.setCustom(text)
            }
            Repeater {
                model: [
                    { label: I18n.t("settings.integrations.unitMin"), v: 1 },
                    { label: I18n.t("settings.integrations.unitHour"), v: 60 },
                    { label: I18n.t("settings.integrations.unitDay"), v: 1440 }
                ]
                delegate: Pill {
                    required property var modelData
                    label: modelData.label
                    name: "settings-autosync-unit-" + modelData.v
                    active: root.unit === modelData.v
                    onPicked: { root.unit = modelData.v; root.setCustom(field.text); }
                }
            }
            Item { Layout.fillWidth: true }
        }
    }
}
