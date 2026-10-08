pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp
import "ThemePresets.js" as Presets
import "SettingsIndex.js" as Idx

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
    // Esc goes to the popup only with nothing typed: the first Esc clears
    // the search (APP-210), the next one closes.
    closePolicy: query.length > 0 ? Popup.CloseOnPressOutsideParent
                                  : Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

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
    onClosed: {
        _focusedThemeName = "";
        query = "";
    }
    // Opened by its key, typing goes straight into the search (APP-210).
    onOpened: searchField.forceActiveFocus()

    // ── Search (APP-210) ──────────────────────────────────────────────
    // One query filters the panel's own rows and lists the settings it
    // finds in the same index Settings search uses (qml/SettingsIndex.js).
    property string query: ""
    readonly property string _q: Idx.norm(query)
    readonly property bool searching: _q.length > 0
    // A setting picked from the results: Main opens Settings on it.
    signal openSettingsItem(var item)

    readonly property var settingsIndex: Idx.build(I18n, I18n.lang, AppController.integrationCatalog())
    // What the panel itself already has is not listed again under Settings.
    readonly property var _ownKeys: ["settings.appearance.theme", "settings.appearance.density",
                                     "settings.appearance.reducedMotion", "settings.appearance.contrast",
                                     "settings.appearance.group.themes"]
    readonly property var settingsMatches: Idx.search(settingsIndex, query)
                                              .filter((it) => _ownKeys.indexOf(it.key) < 0)

    function _keyHit(keys) {
        for (let i = 0; i < keys.length; i++)
            if (Idx.textMatches(_q, I18n.t(keys[i]), I18n.dict.en[keys[i]])) return true;
        return false;
    }
    readonly property bool _appearanceSectionHit: searching && _keyHit(["tweaks.section.appearance"])
    readonly property bool _accessSectionHit: searching && _keyHit(["tweaks.section.access"])
    readonly property bool modeHit: !searching || _appearanceSectionHit
        || _keyHit(["tweaks.theme", "settings.appearance.theme", "settings.appearance.theme.dark",
                    "settings.appearance.theme.light"])
    readonly property bool densityHit: !searching || _appearanceSectionHit
        || _keyHit(["tweaks.density.label", "settings.appearance.density",
                    "common.density.compact", "common.density.comfy"])
    readonly property bool _themesLabelHit: !searching || _keyHit(["tweaks.themePreset", "settings.appearance.group.themes"])
    // Themes by name; all of them when the query names the block itself.
    readonly property var visibleThemes: _themesLabelHit
        ? themeChoices
        : themeChoices.filter((t) => Idx.textMatches(_q, Presets.resolve(t.id, Theme.customThemes, Theme.slot).name, t.name))
    readonly property bool motionHit: !searching || _accessSectionHit
        || _keyHit(["settings.appearance.reducedMotion"])
    readonly property bool contrastHit: !searching || _accessSectionHit
        || _keyHit(["settings.appearance.contrast", "settings.appearance.contrast.soft",
                    "settings.appearance.contrast.normal", "settings.appearance.contrast.high"])
    readonly property bool tweakHits: modeHit || densityHit || visibleThemes.length > 0 || motionHit || contrastHit
    readonly property bool nothingFound: searching && !tweakHits && settingsMatches.length === 0

    // The panel keeps the height it has without a query, so typing never
    // makes it jump: results scroll inside it instead.
    property real _restHeight: 0

    // ↑ / ↓ walk the results: the panel's own controls, then the settings.
    function _results() {
        const out = [];
        const walk = (it) => {
            const kids = it ? it.children : [];
            for (let i = 0; i < kids.length; i++) {
                const k = kids[i];
                if (!k || !k.visible) continue;
                if (k.activeFocusOnTab && k.enabled) out.push(k);
                walk(k);
            }
        };
        walk(bodyCol);
        return out;
    }
    function _move(from, dir) {
        const list = _results();
        const at = from === searchField ? -1 : list.indexOf(from);
        const next = at + dir;
        if (next < 0) {
            searchField.forceActiveFocus(Qt.BacktabFocusReason);
            return;
        }
        if (next >= list.length) return;
        list[next].forceActiveFocus(Qt.TabFocusReason);
        _ensureVisible(list[next]);
    }
    function _ensureVisible(item) {
        const y = item.mapToItem(bodyCol, 0, 0).y + bodyCol.y;
        if (y < bodyFlick.contentY)
            bodyFlick.contentY = Math.max(0, y - Theme.spSm);
        else if (y + item.height > bodyFlick.contentY + bodyFlick.height)
            bodyFlick.contentY = Math.min(bodyFlick.contentHeight - bodyFlick.height,
                                          y + item.height - bodyFlick.height + Theme.spSm);
    }
    // Enter in the box: a setting that is the only kind of hit opens;
    // otherwise focus goes to the first result.
    function _acceptSearch() {
        if (!searching) return;
        if (settingsMatches.length > 0 && !tweakHits) {
            _openSettings(settingsMatches[0]);
            return;
        }
        _move(searchField, 1);
    }
    function _openSettings(item) {
        root.openSettingsItem({ section: item.section, id: item.id, key: item.key });
        root.close();
    }
    // Esc clears the query first; with nothing typed it closes the panel
    // (closePolicy hands Esc to the popup only then).
    function _escape() {
        if (query.length > 0) {
            query = "";
            searchField.forceActiveFocus();
            return true;
        }
        return false;
    }

    background: PopupSurface {}

    contentItem: ColumnLayout {
        spacing: 0
        Keys.onEscapePressed: (event) => { event.accepted = root._escape(); }
        // ↑ / ↓ from any result: the controls leave the arrows unhandled,
        // so they arrive here.
        Keys.onUpPressed: root._move(searchField.Window.activeFocusItem, -1)
        Keys.onDownPressed: root._move(searchField.Window.activeFocusItem, 1)

        // ── Header: the search box and ✕ ─────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.spMd
                spacing: Theme.spSm
                Text { text: "⌕"; color: Theme.textDim; font.pixelSize: Theme.fsSm }
                TextField {
                    id: searchField
                    objectName: "tweaks-search"
                    Layout.fillWidth: true
                    leftPadding: 0
                    placeholderText: I18n.t("tweaks.search")
                    placeholderTextColor: Theme.textDim
                    color: Theme.text
                    background: Item {}
                    font.pixelSize: Theme.fsMd
                    Accessible.name: I18n.t("tweaks.title")
                    Accessible.description: I18n.t("tweaks.search")
                    text: root.query
                    onTextChanged: root.query = text
                    onAccepted: root._acceptSearch()
                    Keys.onDownPressed: root._move(searchField, 1)
                    Keys.onEscapePressed: (event) => { event.accepted = root._escape(); }
                }
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
        Flickable {
            id: bodyFlick
            objectName: "tweaks-body"
            Layout.fillWidth: true
            Layout.preferredHeight: root.searching && root._restHeight > 0 ? root._restHeight : contentHeight
            contentWidth: width
            contentHeight: bodyCol.implicitHeight + Theme.spXl + Theme.sp2xl
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ThinScrollBar {}
            onContentHeightChanged: if (!root.searching) root._restHeight = contentHeight

            ColumnLayout {
                id: bodyCol
                x: Theme.sp2xl
                y: Theme.spXl
                width: bodyFlick.width - 2 * Theme.sp2xl
                spacing: Theme.sp2xl

                // Внешний вид: theme + density
                ColumnLayout {
                    objectName: "tweaks-appearance"
                    visible: root.modeHit || root.densityHit
                    spacing: Theme.spSm
                    Layout.fillWidth: true
                    SectLabel {
                        text: I18n.t("tweaks.section.appearance")
                    }
                    FieldLabel {
                        visible: root.modeHit
                        text: I18n.t("tweaks.theme")
                    }
                    RowLayout {
                        objectName: "tweaks-mode"
                        visible: root.modeHit
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
                        visible: root.densityHit
                        text: I18n.t("tweaks.density.label"); topPadding: Theme.spSm
                    }
                    RowLayout {
                        objectName: "tweaks-density"
                        visible: root.densityHit
                        Layout.fillWidth: true
                        spacing: Theme.spXs
                        SegButton { text: I18n.t("common.density.compact"); active: AppController.density === "compact"; onClicked: AppController.density = "compact" }
                        SegButton { text: I18n.t("common.density.comfy");   active: AppController.density === "comfy";   onClicked: AppController.density = "comfy" }
                    }
                }

                // Тема: one chip per theme; picks it for the slot that is showing
                ColumnLayout {
                    objectName: "tweaks-themes"
                    visible: root.visibleThemes.length > 0
                    spacing: Theme.spSm
                    Layout.fillWidth: true
                    SectLabel {
                        text: I18n.t("tweaks.themePreset")
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spSm
                        Repeater {
                            model: root.visibleThemes
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
                                ToolTip.visible: chipHover.hovered || chip.activeFocus
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
                    objectName: "tweaks-access"
                    visible: root.motionHit || root.contrastHit
                    spacing: Theme.spSm
                    Layout.fillWidth: true
                    SectLabel {
                        text: I18n.t("tweaks.section.access")
                    }
                    ToggleRow {
                        objectName: "tweaks-reduced-motion"
                        visible: root.motionHit
                        label: I18n.t("settings.appearance.reducedMotion")
                        checked: !!root._appearanceValue("reducedMotion", false)
                        onToggled: (v) => root._setAppearance("reducedMotion", v)
                    }
                    FieldLabel {
                        visible: root.contrastHit
                        text: I18n.t("settings.appearance.contrast"); topPadding: Theme.spSm
                    }
                    RowLayout {
                        objectName: "tweaks-contrast"
                        visible: root.contrastHit
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

                // What the query finds in Settings: "Section → setting". Enter
                // or a click opens Settings on it and closes the panel.
                ColumnLayout {
                    objectName: "tweaks-settings-hits"
                    visible: root.searching && root.settingsMatches.length > 0
                    spacing: Theme.sp2xs
                    Layout.fillWidth: true
                    SectLabel {
                        Layout.bottomMargin: Theme.spXs
                        text: I18n.t("tweaks.search.inSettings")
                    }
                    Repeater {
                        model: root.searching ? root.settingsMatches : []
                        delegate: Rectangle {
                            id: hit
                            required property var modelData
                            required property int index
                            objectName: "tweaks-settings-hit-" + index
                            readonly property string sectionTitle: I18n.t("settings.section." + modelData.section + ".title")
                            Layout.fillWidth: true
                            implicitHeight: hitText.implicitHeight + 2 * Theme.spSm
                            radius: Theme.radiusMd
                            color: hitCA.hovered || hitCA.activeFocus ? Theme.panel2 : "transparent"
                            Text {
                                id: hitText
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: Theme.spSm; anchors.rightMargin: Theme.spSm
                                anchors.verticalCenter: parent.verticalCenter
                                text: hit.sectionTitle + "  →  " + hit.modelData.title
                                color: Theme.text
                                font.pixelSize: Theme.fsSm
                                elide: Text.ElideRight
                            }
                            ClickArea {
                                id: hitCA
                                label: hitText.text
                                showTip: false
                                onActivated: root._openSettings(hit.modelData)
                            }
                        }
                    }
                }

                EmptyState {
                    objectName: "tweaks-search-empty"
                    visible: root.nothingFound
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spXl
                    compact: true
                    title: I18n.t("settings.search.empty")
                    line: I18n.t("settings.search.emptyLine")
                }

                // Hint: deeper config still lives in Settings.
                Text {
                    visible: !root.searching
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
