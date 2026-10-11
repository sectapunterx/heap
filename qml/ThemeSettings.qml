// Settings → Appearance → Theme: pick a theme for each slot, make your own,
// and edit every colour token of it.
//
// Two slots, dark and light; AppController.theme (Ctrl+Shift+T) says which is
// showing, settings.appearance.darkPreset / lightPreset say what sits in
// each. Built-in themes are read-only: editing a token of one makes a copy
// and edits that, so a built-in can always be gone back to.
//
// Writes go through setKey(key, value) into settings.appearance; SettingsView
// persists them and Theme repaints from the blob, so every edit is live.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp
import "ThemePresets.js" as Presets
import "ArmGuard.js" as ArmGuard

ColumnLayout {
    id: ts
    objectName: "theme-settings"

    property var appearance: ({})
    signal setKey(string key, var value)

    spacing: Theme.spXl
    Layout.fillWidth: true

    readonly property var customs: Presets.list(appearance.customThemes)
    readonly property string slot: Theme.slot
    readonly property string slotKey: slot === "light" ? "lightPreset" : "darkPreset"
    readonly property string currentId: Theme.activePresetId
    readonly property var current: Theme.active
    readonly property bool currentIsBuiltin: !!Presets.builtin(currentId)
    // Themes of the slot's base first, the rest after: any theme may sit in
    // either slot, but the matching ones are what you are looking for.
    readonly property var themes: {
        const list = Presets.all(customs);
        const mine = list.filter((t) => (t.base === "light" ? "light" : "dark") === slot);
        const other = list.filter((t) => (t.base === "light" ? "light" : "dark") !== slot);
        return mine.concat(other);
    }

    property string filter: ""
    property string importError: ""
    property bool copied: false
    // Whether the colour editor is unfolded. Not saved: it opens folded.
    property bool colorsOpen: false

    function pick(id) { setKey(slotKey, id); }

    function _saveCustoms(list) { setKey("customThemes", list); }

    function _custom(id) {
        for (let i = 0; i < customs.length; i++)
            if (customs[i].id === id) return customs[i];
        return null;
    }

    // Adds `theme` as a new custom theme and puts it in the current slot. A
    // name already in the picker gets " (2)", " (3)"… (APP-127).
    function _add(name, base, colors, from) {
        const id = Presets.newId(customs);
        const t = { id: id, name: Presets.uniqueName(name, customs), base: base, from: from || "", colors: colors };
        _saveCustoms(customs.concat([t]));
        pick(id);
        return id;
    }

    function duplicate(id) {
        const t = Presets.resolve(id, customs, slot);
        return _add(I18n.t("settings.theme.copyName").arg(t.name), t.base,
                    Object.assign({}, t.colors), Presets.builtin(id) ? id : (_custom(id) && _custom(id).from) || "");
    }

    function _updateCustom(id, fn) {
        const next = customs.map((t) => {
            if (t.id !== id) return t;
            const copy = Object.assign({}, t);
            copy.colors = Object.assign({}, t.colors);
            fn(copy);
            return copy;
        });
        _saveCustoms(next);
    }

    function setToken(key, hex) {
        if (!Presets.isHex(hex)) return;
        if (currentIsBuiltin) {
            const t = current;
            const colors = Object.assign({}, t.colors);
            colors[key] = hex;
            _add(I18n.t("settings.theme.copyName").arg(t.name), t.base, colors, t.id);
            return;
        }
        _updateCustom(currentId, (t) => { t.colors[key] = hex; });
    }

    // The value `key` had in the theme this one was copied from.
    function origin(key) {
        const c = _custom(currentId);
        const from = c && c.from ? c.from : (current.base === "light" ? Presets.DEFAULT_LIGHT : Presets.DEFAULT_DARK);
        return Presets.resolve(from, customs, slot).colors[key];
    }

    function resetToken(key) {
        if (currentIsBuiltin) return;
        const v = origin(key);
        _updateCustom(currentId, (t) => { t.colors[key] = v; });
    }

    function rename(name) {
        const n = String(name || "").trim();
        if (!n.length || currentIsBuiltin) return;
        _updateCustom(currentId, (t) => { t.name = n.slice(0, 60); });
    }

    function setBase(base) {
        if (currentIsBuiltin) return;
        _updateCustom(currentId, (t) => { t.base = base; });
    }

    // Where a slot showing theme `id` lands once `id` is gone: the theme it was
    // copied from, followed back past other deleted copies, as long as that
    // one belongs in the slot; otherwise the slot's default. It used to be the
    // default every time, so deleting a copy of Crimson landed on heap. dark.
    function fallbackFor(id, slotName, remaining) {
        const seen = {};
        let cur = _custom(id);
        while (cur && cur.from && !seen[cur.from]) {
            seen[cur.from] = true;
            const b = Presets.builtin(cur.from) || Presets.builtin(Presets.RETIRED[cur.from]);
            if (b) return b.id;
            const next = remaining.filter((t) => t.id === cur.from)[0];
            if (next) return next.id;
            cur = _custom(cur.from);
        }
        return slotName === "light" ? Presets.DEFAULT_LIGHT : Presets.DEFAULT_DARK;
    }

    function remove(id) {
        if (Presets.builtin(id)) return;
        const remaining = customs.filter((t) => t.id !== id);
        const darkNext = fallbackFor(id, "dark", remaining);
        const lightNext = fallbackFor(id, "light", remaining);
        _saveCustoms(remaining);
        if (appearance.darkPreset === id) setKey("darkPreset", darkNext);
        if (appearance.lightPreset === id) setKey("lightPreset", lightNext);
    }

    function exportCurrent() {
        AppController.copyToClipboard(Presets.exportJson(currentId, customs, slot));
        copied = true;
        copiedTimer.restart();
    }

    function importText(text) {
        let obj = null;
        try { obj = JSON.parse(text); } catch (e) { obj = null; }
        const v = Presets.validateTheme(obj);
        if (!v) {
            importError = I18n.t("settings.theme.importInvalid");
            return false;
        }
        importError = "";
        // Tokens the file does not name come from the built-in of its base.
        const base = Presets.resolve(v.base === "light" ? Presets.DEFAULT_LIGHT : Presets.DEFAULT_DARK, [], v.base);
        const colors = Object.assign({}, base.colors, v.colors);
        _add(v.name.length ? v.name : I18n.t("settings.theme.imported"), v.base, colors, "");
        return true;
    }

    Timer { id: copiedTimer; interval: 1600; onTriggered: ts.copied = false }

    // ── Slot ─────────────────────────────────────────────────────────
    Text {
        text: I18n.t("settings.theme.slotHint")
        color: Theme.textMuted
        font.pixelSize: Theme.fsSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    // ── Theme cards, by contrast ─────────────────────────────────────
    Repeater {
        model: Presets.CATEGORIES
        delegate: ColumnLayout {
            id: catCol
            required property string modelData
            readonly property var members: ts.themes.filter((t) => Presets.category(t, ts.customs) === catCol.modelData)
            objectName: "theme-category-" + modelData
            visible: members.length > 0
            Layout.fillWidth: true
            spacing: Theme.spSm

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spMd
                Text {
                    text: I18n.t("settings.theme.cat." + catCol.modelData)
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("settings.theme.cat." + catCol.modelData + ".hint")
                    color: Theme.textDim
                    font.pixelSize: Theme.fsXs
                    elide: Text.ElideRight
                }
            }
            Flow {
                objectName: "theme-cards-" + catCol.modelData
                Layout.fillWidth: true
                spacing: Theme.spMd
                Repeater {
                    model: catCol.members
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        readonly property var t: Presets.resolve(card.modelData.id, ts.customs, ts.slot)
                        readonly property bool selected: card.modelData.id === ts.currentId
                        objectName: "theme-card-" + modelData.id
                        width: 150; height: 92
                        radius: Theme.radius
                        color: t.colors.bg
                        border.color: selected ? Theme.accent : (cardMA.hovered ? Theme.borderStrong : Theme.border)
                        border.width: selected ? 2 : 1

                        // A miniature of the theme: a panel, a line of text, accent
                        // and the alert / priority colours.
                        Rectangle {
                            x: 8; y: 8; width: parent.width - 16; height: 44
                            radius: Theme.radiusSm
                            color: card.t.colors.panel
                            border.color: card.t.colors.border; border.width: 1
                            Rectangle { x: 8; y: 8; width: 60; height: 5; radius: 2; color: card.t.colors.text }
                            Rectangle { x: 8; y: 18; width: 40; height: 4; radius: 2; color: card.t.colors.textMuted }
                            Rectangle { x: parent.width - 34; y: 8; width: 26; height: 12; radius: Theme.radiusXs; color: card.t.colors.accent }
                            Row {
                                x: 8; y: 30; spacing: Theme.spXs
                                Repeater {
                                    model: ["danger", "warning", "success", "info", "p2", "p3", "stReview"]
                                    Rectangle {
                                        required property string modelData
                                        width: 8; height: 8; radius: 4
                                        color: card.t.colors[modelData]
                                    }
                                }
                            }
                        }
                        Text {
                            x: 10; y: 58
                            width: parent.width - 20
                            text: card.t.name
                            color: card.t.colors.text
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fsSm
                            font.weight: Theme.fwTitle
                        }
                        Text {
                            x: 10; y: 74
                            text: (card.t.builtin ? I18n.t("settings.theme.builtin") : I18n.t("settings.theme.custom"))
                                  + " · " + I18n.t(card.t.base === "light" ? "settings.appearance.theme.light"
                                                                          : "settings.appearance.theme.dark")
                            color: card.t.colors.textMuted
                            font.pixelSize: Theme.fsXs
                        }
                        ClickArea {
                            id: cardMA
                            objectName: "theme-card-area-" + card.modelData.id
                            label: card.t.name
                            showTip: false
                            role: Accessible.RadioButton
                            checkable: true
                            checked: card.selected
                            onActivated: ts.pick(card.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // ── Actions on the selected theme ───────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spMd

        TextField {
            id: nameField
            ContextMenu.menu: TextEditMenu { editor: nameField }
            objectName: "theme-name"
            Layout.preferredWidth: 200
            enabled: !ts.currentIsBuiltin
            text: ts.current.name
            color: Theme.text
            font.pixelSize: Theme.fsMd
            selectByMouse: true
            background: FieldFrame {}
            onAccepted: ts.rename(text)
            onActiveFocusChanged: if (!activeFocus && text !== ts.current.name) ts.rename(text)
        }
        PillButton {
            objectName: "theme-duplicate"
            text: I18n.t("settings.theme.duplicate")
            onClicked: ts.duplicate(ts.currentId)
        }
        PillButton {
            objectName: "theme-export"
            text: ts.copied ? I18n.t("settings.theme.copied") : I18n.t("settings.theme.export")
            onClicked: ts.exportCurrent()
        }
        PillButton {
            id: delBtn
            objectName: "theme-delete"
            property bool armed: false
            property real armedAt: 0
            visible: !ts.currentIsBuiltin
            danger: true
            text: armed ? I18n.t("settings.theme.deleteConfirm") : I18n.t("common.delete")
            onClicked: {
                if (!armed) { armed = true; armedAt = Date.now(); disarm.restart(); return; }
                if (ArmGuard.tooSoon(armedAt)) return;  // a double-click (IDIOT-SHELL-5)
                armed = false;
                ts.remove(ts.currentId);
            }
            Timer { id: disarm; interval: 3000; onTriggered: delBtn.armed = false }
        }
        Item { Layout.fillWidth: true }
    }

    // Base of a custom theme: which built-in fills tokens it lacks and how
    // high contrast pushes it.
    RowLayout {
        visible: !ts.currentIsBuiltin
        spacing: Theme.spMd
        Text { text: I18n.t("settings.theme.base"); color: Theme.textMuted; font.pixelSize: Theme.fsSm }
        Repeater {
            model: ["dark", "light"]
            PillButton {
                required property string modelData
                selected: ts.current.base === modelData
                text: I18n.t(modelData === "light" ? "settings.appearance.theme.light" : "settings.appearance.theme.dark")
                onClicked: ts.setBase(modelData)
            }
        }
    }

    // ── Import ──────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spXs
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spMd
            TextField {
                id: importField
                ContextMenu.menu: TextEditMenu { editor: importField }
                objectName: "theme-import-field"
                Layout.fillWidth: true
                placeholderText: I18n.t("settings.theme.importPh")
                placeholderTextColor: Theme.textDim
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsSm
                selectByMouse: true
                background: FieldFrame { border.color: ts.importError.length ? Theme.danger : (focused ? Theme.focusRing : Theme.fieldBorder) }
                onAccepted: if (ts.importText(text)) text = ""
            }
            PillButton {
                objectName: "theme-import"
                text: I18n.t("settings.theme.import")
                enabled: importField.text.length > 0
                onClicked: if (ts.importText(importField.text)) importField.text = ""
            }
        }
        Text {
            visible: ts.importError.length > 0
            text: ts.importError
            color: Theme.danger
            font.pixelSize: Theme.fsXs
        }
    }

    // ── Token editor ────────────────────────────────────────────────
    // Folded by default: sixty-odd colour rows buried the theme picker and
    // the switches below it, and most people only ever pick a theme.
    Rectangle {
        id: colorsHeader
        objectName: "theme-colors-header"
        Layout.fillWidth: true
        Layout.topMargin: Theme.spSm
        implicitHeight: colorsRow.implicitHeight + Theme.spMd * 2
        radius: Theme.radiusMd
        color: colorsMA.hovered ? Theme.panel3 : Theme.panel2
        border.color: Theme.border
        RowLayout {
            id: colorsRow
            anchors.fill: parent
            anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spLg
            spacing: Theme.spMd
            Text {
                text: ts.colorsOpen ? "▾" : "▸"
                color: Theme.textDim
                font.pixelSize: Theme.fsMd
            }
            Text {
                text: I18n.t("settings.theme.colors")
                color: Theme.textDim
                font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle
            }
            Text {
                Layout.fillWidth: true
                text: I18n.t("settings.theme.colorsHint").arg(Presets.TOKENS.length)
                color: Theme.textDim
                font.pixelSize: Theme.fsXs
                elide: Text.ElideRight
            }
        }
        ClickArea {
            id: colorsMA
            objectName: "theme-colors-toggle"
            label: I18n.t("settings.theme.colors")
            showTip: false
            role: Accessible.CheckBox
            checkable: true
            checked: ts.colorsOpen
            onActivated: ts.colorsOpen = !ts.colorsOpen
        }
    }
    TextField {
        id: tokenFilterField
        ContextMenu.menu: TextEditMenu { editor: tokenFilterField }
        objectName: "theme-token-filter"
        visible: ts.colorsOpen
        Layout.preferredWidth: 220
        placeholderText: I18n.t("settings.theme.filter")
        placeholderTextColor: Theme.textDim
        color: Theme.text
        font.pixelSize: Theme.fsSm
        selectByMouse: true
        background: FieldFrame {}
        onTextChanged: ts.filter = text.toLowerCase()
    }
    Text {
        visible: ts.colorsOpen && ts.currentIsBuiltin
        text: I18n.t("settings.theme.builtinHint")
        color: Theme.textDim
        font.pixelSize: Theme.fsXs
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    Repeater {
        model: Presets.GROUPS
        delegate: ColumnLayout {
            id: grp
            required property string modelData
            readonly property var tokens: Presets.TOKENS.filter((t) => {
                if (t.group !== modelData) return false;
                if (!ts.filter.length) return true;
                return t.key.toLowerCase().indexOf(ts.filter) >= 0
                    || I18n.t("theme.token." + t.key).toLowerCase().indexOf(ts.filter) >= 0;
            })
            visible: ts.colorsOpen && grp.tokens.length > 0
            Layout.fillWidth: true
            spacing: Theme.spXs

            Text {
                text: I18n.t("theme.group." + grp.modelData)
                color: Theme.textDim
                font.pixelSize: Theme.fsSm; font.weight: Theme.fwTitle
                Layout.topMargin: Theme.spSm
            }
            GridLayout {
                id: grid
                Layout.fillWidth: true
                // Sized off the section, not the grid: the grid's own width
                // follows its cells, so deriving the cells from it collapses
                // to one column.
                columns: Math.max(1, Math.floor(ts.width / 280))
                // Equal cells, so the swatches line up from group to group.
                readonly property real cellW: Math.floor((ts.width - columnSpacing * (columns - 1)) / columns)
                columnSpacing: Theme.spXl
                rowSpacing: Theme.spXs
                Repeater {
                    model: grp.tokens
                    delegate: RowLayout {
                        id: tokRow
                        required property var modelData
                        readonly property string key: modelData.key
                        readonly property string value: String(ts.current.colors[key] || "")
                        readonly property bool changed: !ts.currentIsBuiltin
                                                        && value.toLowerCase() !== String(ts.origin(key)).toLowerCase()
                        objectName: "theme-token-" + key
                        Layout.preferredWidth: grid.cellW
                        Layout.maximumWidth: grid.cellW
                        spacing: Theme.spMd

                        Rectangle {
                            id: sw
                            objectName: "theme-swatch-" + tokRow.key
                            Layout.preferredWidth: 26; Layout.preferredHeight: 22
                            radius: Theme.radiusSm
                            color: tokRow.value
                            border.color: Theme.borderStrong; border.width: 1
                            ClickArea {
                                objectName: "theme-swatch-area-" + tokRow.key
                                label: I18n.t("settings.theme.pickColor").arg(I18n.t("theme.token." + tokRow.key))
                                onActivated: {
                                    picker.token = tokRow.key;
                                    picker.openFor(tokRow.value, sw);
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("theme.token." + tokRow.key)
                            color: Theme.text
                            font.pixelSize: Theme.fsSm
                            elide: Text.ElideRight
                        }
                        TextField {
                            id: tokenHexField
                            ContextMenu.menu: TextEditMenu { editor: tokenHexField }
                            objectName: "theme-hex-" + tokRow.key
                            Layout.preferredWidth: 92
                            text: tokRow.value
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                            color: acceptableInput ? Theme.text : Theme.danger
                            selectByMouse: true
                            validator: RegularExpressionValidator { regularExpression: /#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})/ }
                            background: FieldFrame { radius: Theme.radiusSm }
                            onAccepted: ts.setToken(tokRow.key, text.toLowerCase())
                            onActiveFocusChanged: {
                                if (!activeFocus && acceptableInput && text.toLowerCase() !== tokRow.value.toLowerCase())
                                    ts.setToken(tokRow.key, text.toLowerCase());
                            }
                        }
                        Text {
                            objectName: "theme-reset-" + tokRow.key
                            text: "↺"
                            opacity: tokRow.changed ? 1 : 0
                            color: resetMA.hovered ? Theme.accentStrong : Theme.textMuted
                            font.pixelSize: Theme.fsMd
                            Layout.preferredWidth: 14
                            ClickArea {
                                id: resetMA
                                objectName: "theme-reset-area-" + tokRow.key
                                enabled: tokRow.changed
                                label: I18n.t("settings.theme.resetToken").arg(I18n.t("theme.token." + tokRow.key))
                                onActivated: ts.resetToken(tokRow.key)
                            }
                        }
                    }
                }
            }
        }
    }

    ColorPickerPopup {
        id: picker
        property string token: ""
        parent: Overlay.overlay
        // The first drag on a built-in makes the copy; the rest land on it.
        onPicked: (hex) => ts.setToken(token, hex)
    }
}
