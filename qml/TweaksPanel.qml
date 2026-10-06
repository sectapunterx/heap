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

    // Name shown under the theme dots (hovered / focused one).
    property string _focusedThemeName: ""
    onClosed: _focusedThemeName = ""

    background: PopupSurface {}

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
                    text: I18n.t("tweaks.title")
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm
                    font.weight: Theme.fwTitle
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 22; height: 22; radius: Theme.radiusSm
                    color: closeMA.hovered ? Theme.panel3 : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.textDim
                        font.pixelSize: Theme.fsMd
                    }
                    ClickArea {
                        id: closeMA
                        objectName: "tweaks-close"
                        label: I18n.t("tweaks.close")
                        shortcutId: "tweaks.open"
                        onActivated: root.close()
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
                            // Tab / Space like the rest of the panel, and named.
                            activeFocusOnTab: true
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: chip.t.name
                            Accessible.checked: modelData.id === Theme.activePresetId
                            Keys.onSpacePressed: root._setAppearance(Theme.slot === "light" ? "lightPreset" : "darkPreset", chip.modelData.id)
                            Keys.onReturnPressed: root._setAppearance(Theme.slot === "light" ? "lightPreset" : "darkPreset", chip.modelData.id)
                            onActiveFocusChanged: if (activeFocus) root._focusedThemeName = chip.t.name
                            FocusRing {}
                            Rectangle {
                                anchors.centerIn: parent
                                width: 12; height: 12; radius: 6
                                color: chip.t.colors.accent
                            }
                            ToolTip.visible: chipHover.hovered
                            ToolTip.text: chip.t.name
                            HoverHandler { id: chipHover; onHoveredChanged: if (hovered) root._focusedThemeName = chip.t.name }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._setAppearance(Theme.slot === "light" ? "lightPreset" : "darkPreset",
                                                               chip.modelData.id)
                            }
                        }
                    }
                }
                // The dots had no names: the one hovered or focused, else the
                // theme in use.
                Text {
                    objectName: "tweaks-theme-name"
                    Layout.fillWidth: true
                    text: root._focusedThemeName.length ? root._focusedThemeName : Theme.active.name
                    color: Theme.textMuted
                    font.pixelSize: Theme.fsSm
                    elide: Text.ElideRight
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
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsXs
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Inline components ─────────────────────────────────────────────

    component SectLabel: Text {
        color: Theme.textDim
        font.pixelSize: Theme.fsSm
        font.weight: Theme.fwTitle
    }

    component FieldLabel: Text {
        color: Theme.textMuted
        font.pixelSize: Theme.fsSm
    }

    component SegButton: Rectangle {
        id: segBtn
        property string text: ""
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: Theme.radiusMd
        // Tab moves through the panel; it used to stay on the popup itself.
        activeFocusOnTab: true
        Accessible.role: Accessible.RadioButton
        Accessible.name: segBtn.text
        Accessible.checked: segBtn.active
        Keys.onSpacePressed: segBtn.clicked()
        Keys.onReturnPressed: segBtn.clicked()
        FocusRing {}
        color: active ? Theme.accentSoft : (segMA.containsMouse ? Theme.panel3 : Theme.panel2)
        border.color: active ? Theme.withAlpha(Theme.accent, 0.5) : Theme.border
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: parent.active ? Theme.accentStrong : Theme.text
            font.pixelSize: Theme.fsMd
            font.weight: Theme.fwTitle
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
        activeFocusOnTab: true
        Accessible.role: Accessible.CheckBox
        Accessible.name: toggleRow.label
        Accessible.checked: toggleRow.checked
        Keys.onSpacePressed: toggleRow.toggled(!toggleRow.checked)
        Keys.onReturnPressed: toggleRow.toggled(!toggleRow.checked)

        Text {
            Layout.fillWidth: true
            text: toggleRow.label
            color: Theme.text
            font.pixelSize: Theme.fsMd
        }
        Rectangle {
            id: toggleTrack
            width: 32; height: 18; radius: 9
            color: toggleRow.checked ? Theme.accent : Theme.panel3
            // An edge for the OFF track and the knob: both vanished on the
            // light themes' panel3 and accent (DES-20).
            border.color: toggleRow.checked ? "transparent" : Theme.fieldBorder
            border.width: 1
            Behavior on color { ColorAnimation { duration: Theme.durTap; easing.type: Theme.easeEnter } }
            FocusRing { target: toggleRow; radius: 12 }
            Rectangle {
                width: 14; height: 14; radius: 7
                id: toggleKnob
                y: 2
                x: 2
                color: Theme.knob
                border.color: Theme.fieldBorder
                border.width: 1
                // Slides by transform, not by x: only transform and opacity
                // animate (APP-175).
                transform: Translate {
                    x: toggleRow.checked ? toggleTrack.width - toggleKnob.width - 4 : 0
                    Behavior on x { NumberAnimation { duration: Theme.durTap; easing.type: Theme.easeEnter } }
                }
            }
        }
    }
}
