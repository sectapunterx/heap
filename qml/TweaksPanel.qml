import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp
import "ThemePresets.js" as Presets

Popup {
    id: root
    modal: false
    focus: true
    padding: 0
    width: 280
    // Main._togglePopover re-parents this to the rail button that opened it, so
    // "outside the parent" means "outside the panel and its button": any press
    // elsewhere in the app dismisses it, and a press on the button reaches the
    // rail handler, which toggles.
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    // Themes for the slot that is showing, its own base first — the quick
    // version of Settings → Appearance → Theme.
    readonly property var themeChoices: {
        const list = Presets.all(Theme.customThemes);
        const mine = list.filter((t) => (t.base === "light" ? "light" : "dark") === Theme.slot);
        const other = list.filter((t) => (t.base === "light" ? "light" : "dark") !== Theme.slot);
        return mine.concat(other);
    }

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
    // highContrast is written alongside for profiles that only know it.
    function setContrast(v) {
        const next = Object.assign({}, settings);
        next.appearance = Object.assign({}, next.appearance || {}, { contrast: v, highContrast: v === "high" });
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
        radius: Theme.radiusXl
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
                anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.spMd
                Text {
                    text: I18n.t("tweaks.title").toUpperCase()
                    color: Theme.textMuted
                    font.pixelSize: Theme.fsSm
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 22; height: 22; radius: Theme.radiusSm
                    color: closeMA.containsMouse ? Theme.panel3 : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.textDim
                        font.pixelSize: Theme.fsMd
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
            Layout.leftMargin: Theme.sp2xl; Layout.rightMargin: Theme.sp2xl
            Layout.topMargin: Theme.spXl; Layout.bottomMargin: Theme.sp2xl
            spacing: Theme.sp2xl

            // Внешний вид: theme + density
            ColumnLayout {
                spacing: Theme.spSm
                Layout.fillWidth: true
                SectLabel {
                    text: I18n.t("tweaks.section.appearance")
                }
                FieldLabel {
                    text: I18n.t("tweaks.theme")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spXs
                    SegButton {
                        text: I18n.t("settings.appearance.theme.dark"); active: AppController.theme === "dark"; onClicked: AppController.theme = "dark"
                    }
                    SegButton {
                        text: I18n.t("settings.appearance.theme.light"); active: AppController.theme === "light"; onClicked: AppController.theme = "light"
                    }
                }
                FieldLabel {
                    text: I18n.t("tweaks.density.label"); topPadding: Theme.spSm
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spXs
                    SegButton { text: I18n.t("common.density.compact"); active: AppController.density === "compact"; onClicked: AppController.density = "compact" }
                    SegButton { text: I18n.t("common.density.comfy");   active: AppController.density === "comfy";   onClicked: AppController.density = "comfy" }
                }
            }

            // Тема: one chip per theme; picks it for the slot that is showing
            ColumnLayout {
                spacing: Theme.spSm
                Layout.fillWidth: true
                SectLabel {
                    text: I18n.t("tweaks.themePreset")
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spSm
                    Repeater {
                        model: root.themeChoices
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property var t: Presets.resolve(modelData.id, Theme.customThemes, Theme.slot)
                            objectName: "tweaks-theme-" + modelData.id
                            width: 26; height: 26; radius: 13
                            color: t.colors.bg
                            border.width: 2
                            border.color: modelData.id === Theme.activePresetId ? Theme.text : Theme.border
                            Rectangle {
                                anchors.centerIn: parent
                                width: 12; height: 12; radius: 6
                                color: chip.t.colors.accent
                            }
                            ToolTip.visible: chipHover.hovered
                            ToolTip.text: chip.t.name
                            HoverHandler { id: chipHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._setAppearance(Theme.slot === "light" ? "lightPreset" : "darkPreset",
                                                               chip.modelData.id)
                            }
                        }
                    }
                }
            }

            // Доступность: reducedMotion + contrast (soft / normal / high)
            ColumnLayout {
                spacing: Theme.spSm
                Layout.fillWidth: true
                SectLabel {
                    text: I18n.t("tweaks.section.access")
                }
                ToggleRow {
                    label: I18n.t("settings.appearance.reducedMotion")
                    checked: !!root._appearanceValue("reducedMotion", false)
                    onToggled: (v) => root._setAppearance("reducedMotion", v)
                }
                FieldLabel {
                    text: I18n.t("settings.appearance.contrast"); topPadding: Theme.spSm
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spXs
                    Repeater {
                        model: ["soft", "normal", "high"]
                        SegButton {
                            required property string modelData
                            objectName: "tweaks-contrast-" + modelData
                            text: I18n.t("settings.appearance.contrast." + modelData)
                            active: Theme.contrast === modelData
                            onClicked: root.setContrast(modelData)
                        }
                    }
                }
            }

            // Hint: deeper config still lives in Settings.
            Text {
                Layout.fillWidth: true
                text: I18n.t("tweaks.allInSettings")
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsXs
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Inline components ─────────────────────────────────────────────

    component SectLabel: Text {
        color: Theme.textDim
        font.pixelSize: Theme.fsXs
        font.letterSpacing: 1
        font.weight: Font.DemiBold
    }

    component FieldLabel: Text {
        color: Theme.textMuted
        font.pixelSize: Theme.fsSm
    }

    component SegButton: Rectangle {
        property string text: ""
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: Theme.radiusMd
        color: active ? Theme.accentSoft : (segMA.containsMouse ? Theme.panel3 : Theme.panel2)
        border.color: active ? Theme.withAlpha(Theme.accent, 0.5) : Theme.border
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: parent.active ? Theme.accentStrong : Theme.text
            font.pixelSize: Theme.fsMd
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
        id: toggleRow
        property string label: ""
        property bool checked: false
        signal toggled(bool v)
        Layout.fillWidth: true
        spacing: Theme.spLg

        // Label included in the hit area — the 32x18 switch alone was a fiddly
        // target. Handlers, not a MouseArea: an Item here would become a cell.
        TapHandler { onTapped: toggleRow.toggled(!toggleRow.checked) }
        HoverHandler { cursorShape: Qt.PointingHandCursor }

        Text {
            Layout.fillWidth: true
            text: toggleRow.label
            color: Theme.text
            font.pixelSize: Theme.fsMd
        }
        Rectangle {
            width: 32; height: 18; radius: 9
            color: toggleRow.checked ? Theme.accent : Theme.panel3
            border.color: toggleRow.checked ? "transparent" : Theme.border
            border.width: 1
            Behavior on color { ColorAnimation { duration: Theme.animMs } }
            Rectangle {
                width: 14; height: 14; radius: 7
                y: 2
                x: toggleRow.checked ? parent.width - width - 2 : 2
                color: Theme.knob
                border.color: Qt.rgba(0, 0, 0, 0.18)
                border.width: 1
                Behavior on x { NumberAnimation { duration: Theme.animMs; easing.type: Easing.OutCubic } }
            }
        }
    }
}
