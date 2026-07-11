// Settings view — full per-profile / global configuration screen.
// Layout: left nav with 10 sections, right detail panel. New app-wide
// settings persist as JSON in AppController.appSettingsJson.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import TodoCpp

Item {
    id: root

    // ── Sections list (left nav) ──────────────────────────────────────
    // Full catalogue of settings sections.
    //   unimplemented: section is a stub. In Release builds these are hidden
    //                  completely. In Debug they obey the dev toggle in the
    //                  nav footer.
    readonly property var allSections: [
        {
            id: "profile",
            icon: "◉",
            title: I18n.t("settings.section.profile.title"),
            sub: I18n.t("settings.section.profile.sub")
        },
        {
            id: "appearance",
            icon: "◑",
            title: I18n.t("settings.section.appearance.title"),
            sub: I18n.t("settings.section.appearance.sub")
        },
        {
            id: "language",
            icon: "Aa",
            title: I18n.t("settings.section.language.title"),
            sub: I18n.t("settings.section.language.sub")
        },
        {
            id: "notifications",
            icon: "◔",
            title: I18n.t("settings.section.notifications.title"),
            sub: I18n.t("settings.section.notifications.sub")
        },
        {
            id: "calendar",
            icon: "◫",
            title: I18n.t("settings.section.calendar.title"),
            sub: I18n.t("settings.section.calendar.sub")
        },
        {
            id: "tasks",
            icon: "▦",
            title: I18n.t("settings.section.tasks.title"),
            sub: I18n.t("settings.section.tasks.sub")
        },
        {
            id: "shortcuts",
            icon: "⌨",
            title: I18n.t("settings.section.shortcuts.title"),
            sub: I18n.t("settings.section.shortcuts.sub")
        },
        {
            id: "cpp",
            icon: "C++",
            title: I18n.t("settings.section.cpp.title"),
            sub: I18n.t("settings.section.cpp.sub"),
          unimplemented: true },
        {
            id: "integrations",
            icon: "⎘",
            title: I18n.t("settings.section.integrations.title"),
            sub: I18n.t("settings.section.integrations.sub")
        },
        {id: "git", icon: "⎇", title: I18n.t("settings.section.git.title"), sub: I18n.t("settings.section.git.sub")},
        {id: "data", icon: "↯", title: I18n.t("settings.section.data.title"), sub: I18n.t("settings.section.data.sub")},
        {id: "help", icon: "?", title: I18n.t("settings.section.help.title"), sub: I18n.t("settings.section.help.sub")},
        {
            id: "about",
            icon: "ⓘ",
            title: I18n.t("settings.section.about.title"),
            sub: I18n.t("settings.section.about.sub")
        }
    ]

    readonly property bool _debugBuild: !!AppController.debugBuild
    // Persisted toggle: only meaningful in Debug builds. Defaults to true so
    // a developer sees the stub sections out of the box.
    readonly property bool _showUnimplemented:
        !!(settings.developer && settings.developer.showUnimplemented)

    // Visible sections:
    //   * implemented   — always shown,
    //   * unimplemented — Debug AND showUnimplemented; never in Release.
    readonly property var sections: {
        const out = [];
        for (let i = 0; i < allSections.length; ++i) {
            const s = allSections[i];
            if (s.unimplemented && !(_debugBuild && _showUnimplemented)) continue;
            out.push(s);
        }
        return out;
    }
    function _sectionMeta(id) {
        for (let i = 0; i < allSections.length; ++i)
            if (allSections[i].id === id) return allSections[i];
        return null;
    }
    function _isUnimplemented(id) {
        const m = _sectionMeta(id);
        return !!(m && m.unimplemented);
    }
    // If the toggle just hid the currently-open section, fall back to the
    // first visible one — otherwise the user sees an empty Loader.
    onSectionsChanged: {
        const list = sections;
        for (let i = 0; i < list.length; ++i)
            if (list[i].id === activeSection) return;
        if (list.length > 0) activeSection = list[0].id;
    }

    property string activeSection: "profile"
    property string searchText: ""

    // ── Settings state — single source of truth, persisted via JSON blob ──
    property var settings: ({})
    property bool _loadedOnce: false
    property bool _persisting: false
    property bool _reloading:  false

    readonly property var defaults: ({
        profile: {
            name: I18n.lang === "ru" ? "Алексей Тимофеев" : "Alex Timofeev",
            handle: "alex.t",
            role: "C++ Engineer · LTE",
            team: "eNB-core",
            timezone: "Europe/Moscow",
            color: "#5cc2dd"
        },
        appearance: {
            accent: Theme.accent,
            fontUI: "IBM Plex Sans",
            fontMono: "JetBrains Mono",
            reducedMotion: false,
            highContrast: false
        },
        notifications: {
            deadlineReminders: true, deadlineLeadHours: 24,
            standupReminder: true, meetingLead: 5,
            mmPingsOnReview: true, blockedDailyDigest: false,
            soundOnPing: false, desktopNotif: true,
            quietHours: true, quietFrom: "19:00", quietTo: "09:00"
        },
        calendar: {
            weekStart: "mon", timeFormat: "24h",
            snapMinutes: 15, showWeekends: false,
            autoFocusBlock: true, focusBlockDuration: 90,
            standupTime: "10:00"
        },
        tasks: {
            idPrefix: "LTE", defaultPriority: "P2", defaultStatus: "todo",
            archiveDoneAfterDays: 7, autoMoveBlockedAfterDays: 3,
            requireBranchOnReview: true, showSubtasks: true
        },
        cpp: {
            defaultCompiler: "clang-17", defaultStandard: "C++20",
            defaultSanitizer: "asan", defaultBuildType: "RelWithDebInfo",
            bazelArgs: "--jobs=12 --keep_going",
            compilerExplorerUrl: "https://godbolt.org/",
            showAsmInline: false
        },
        integrations: {
            // Tokens/keys are NOT stored here — they live in the OS keychain via
            // AppController.setIntegrationSecret. Only non-secret config persists.
            autoSyncMinutes: 0,
            jira:   ({ connected: false, baseUrl: "", email: "", jql: "" }),
            github: ({ connected: false, repo: "", branchTemplate: "{type}/{id}-{slug}" }),
            gitlab: ({ connected: false, host: "", projectId: "" })
        },
        data: { autoBackup: true, backupInterval: "daily" },
        updates: { autoCheck: true },
        git: {
            watchedRepos: [],
            autoMoveToInProgress: true,
            autoCreateFocusBlock: false,
            watchPrState: true
        },
        developer: {
            showUnimplemented: true   // default ON in Debug; ignored in Release
        }
    })

    readonly property var accentSwatches: [
        "#5cc2dd", "#6ec18a", "#c07acf", "#dcb86b",
        "#e6624c", "#7da8d9", "#9aa3b4"
    ]
    readonly property var avatarSwatches: [
        "#d97a6c", "#dcb86b", "#7cc492", "#6cc4b8",
        "#5cc2dd", "#7da8d9", "#a4a4d6", "#c87fc7", "#e6624c"
    ]

    function _mergeDefaults(src) {
        // Deep-merge user-stored settings on top of defaults; missing
        // keys/sections fall back to defaults so the UI never sees undefined.
        const out = JSON.parse(JSON.stringify(defaults));
        if (src && typeof src === "object") {
            for (const k in src) {
                if (out[k] && typeof out[k] === "object" && !Array.isArray(out[k])) {
                    out[k] = Object.assign({}, out[k], src[k]);
                } else {
                    out[k] = src[k];
                }
            }
        }
        return out;
    }

    function _loadFromController() {
        _reloading = true;
        const raw = AppController.appSettingsJson || "";
        let parsed = {};
        if (raw.length > 0) {
            try { parsed = JSON.parse(raw); } catch (e) { parsed = {}; }
        }
        settings = _mergeDefaults(parsed);
        _reloading = false;
    }
    function _persistNow() {
        if (!_loadedOnce || _reloading) return;
        _persisting = true;
        AppController.appSettingsJson = JSON.stringify(settings);
        _persisting = false;
    }
    function set(group, key, value) {
        const g = Object.assign({}, settings[group]);
        g[key] = value;
        const next = Object.assign({}, settings);
        next[group] = g;
        settings = next;
        _persistNow();
    }
    function setNested(group, subgroup, key, value) {
        const sg = Object.assign({}, (settings[group] && settings[group][subgroup]) || {});
        sg[key] = value;
        const g = Object.assign({}, settings[group]);
        g[subgroup] = sg;
        const next = Object.assign({}, settings);
        next[group] = g;
        settings = next;
        _persistNow();
    }
    function resetAll() {
        AppController.appSettingsJson = "";
        _loadFromController();
    }

    Component.onCompleted: {
        _loadFromController();
        _loadedOnce = true;
    }
    Connections {
        target: AppController
        function onAppSettingsJsonChanged() {
            if (!root._loadedOnce || root._persisting) return;
            root._loadFromController();
        }
    }

    // ── Layout ────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: Theme.bg }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left nav
        Rectangle {
            Layout.preferredWidth: 240
            Layout.fillHeight: true
            color: Theme.panel
            Rectangle {
                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: 1; color: Theme.border
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                Text {
                    text: I18n.t("settings.title")
                    color: Theme.text
                    font.weight: Font.DemiBold
                    font.pixelSize: 16
                }
                Text {
                    text: I18n.t("settings.groups")
                        .arg(Object.keys(root.settings).length)
                        .arg(root.settings.profile ? root.settings.profile.handle : "")
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    Layout.topMargin: 6
                    radius: 6
                    color: Theme.panel2
                    border.color: Theme.border; border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 8
                        spacing: 6
                        Text { text: "⌕"; color: Theme.textDim; font.pixelSize: 11 }
                        TextField {
                            Layout.fillWidth: true
                            placeholderText: I18n.t("settings.search")
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                            background: Item {}
                            font.pixelSize: 12
                            text: root.searchText
                            onTextChanged: root.searchText = text
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 2
                    Repeater {
                        model: root.sections
                        delegate: Rectangle {
                            required property var modelData
                            visible: {
                                const q = root.searchText.toLowerCase().trim();
                                if (q.length === 0) return true;
                                return (modelData.title.toLowerCase().indexOf(q) >= 0
                                     || modelData.sub.toLowerCase().indexOf(q) >= 0);
                            }
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 6
                            color: root.activeSection === modelData.id
                                   ? Theme.accentSoft
                                   : (navMA.containsMouse ? Theme.panel2 : "transparent")
                            border.color: root.activeSection === modelData.id ? Theme.accent : "transparent"
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 10
                                spacing: 10
                                Text {
                                    text: modelData.icon
                                    color: root.activeSection === modelData.id ? Theme.accentStrong : Theme.textMuted
                                    font.pixelSize: modelData.icon === "C++" ? 11 : 16
                                    font.family: modelData.icon === "C++" ? Theme.fontMono : Theme.fontUi
                                    font.weight: Font.DemiBold
                                    Layout.preferredWidth: 24
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text { text: modelData.title; color: Theme.text; font.pixelSize: 12; font.weight: Font.Medium }
                                    Text { text: modelData.sub;   color: Theme.textMuted; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                            MouseArea {
                                id: navMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeSection = modelData.id
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // Debug-only developer toggle. Lives in the nav footer so it
                // never appears in Release builds. Drives `_showUnimplemented`
                // → filters the stub sections out of `sections`.
                Rectangle {
                    visible: root._debugBuild
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    radius: 6
                    color: Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                    implicitHeight: devToggleRow.implicitHeight + 12
                    RowLayout {
                        id: devToggleRow
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: I18n.t("settings.debug.label")
                                color: Theme.p1
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                            }
                            Text {
                                text: I18n.t("settings.debug.showUnimpl")
                                color: Theme.text
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                        Switch {
                            id: devSwitch
                            checked: root._showUnimplemented
                            onToggled: root.set("developer", "showUnimplemented", checked)
                        }
                    }
                }

                Text {
                    text: I18n.t("settings.footer.stable").arg(AppController.appVersion)
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
            }
        }

        // Main detail
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Section header
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    color: Theme.panel
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 24; anchors.rightMargin: 24
                        spacing: 2
                        Layout.alignment: Qt.AlignVCenter
                        Text {
                            text: I18n.t("settings.crumb").arg(root._activeMeta().title || "")
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            Layout.topMargin: 12
                        }
                        Text {
                            text: (root._activeMeta().icon || "") + "  " + (root._activeMeta().title || "")
                            color: Theme.text
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: root._activeMeta().sub || ""
                            color: Theme.textMuted
                            font.pixelSize: 12
                        }
                    }
                }

                // Section body — scrollable
                Flickable {
                    id: bodyScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: bodyCol.implicitHeight + 48
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ThinScrollBar {}

                    NumberAnimation {
                        id: scrollAnim
                        target: bodyScroll
                        property: "contentY"
                        duration: Theme.scaledMs(220)
                        easing.type: Easing.OutCubic
                    }
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            const dy = event.angleDelta.y;
                            if (dy === 0) return;
                            const maxY = Math.max(0, bodyScroll.contentHeight - bodyScroll.height);
                            if (maxY <= 0) return;
                            const base = scrollAnim.running ? scrollAnim.to : bodyScroll.contentY;
                            const newY = Math.max(0, Math.min(maxY, base - dy * 3));
                            if (newY === base) return;
                            scrollAnim.from = bodyScroll.contentY;
                            scrollAnim.to = newY;
                            scrollAnim.restart();
                        }
                    }

                    ColumnLayout {
                        id: bodyCol
                        width: bodyScroll.width
                        spacing: 16
                        // Padding via wrapper
                        Item { Layout.preferredHeight: 8 }

                        // ── Unimplemented banner ──
                        // Shows on top of stub sections so the user can tell
                        // the controls below are read-only stubs.
                        Rectangle {
                            visible: root._isUnimplemented(root.activeSection)
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            radius: 8
                            color: Theme.withAlpha(Theme.p1, 0.12)
                            border.color: Theme.p1
                            border.width: 1
                            implicitHeight: notImplCol.implicitHeight + 16
                            ColumnLayout {
                                id: notImplCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 4
                                Text {
                                    text: I18n.t("settings.notImpl.title")
                                    color: Theme.p1
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1
                                }
                                Text {
                                    text: I18n.t("settings.notImpl.body")
                                    color: Theme.text
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        // Each section gets its own loader-style block.
                        // The wrapper Item disables every interactive widget
                        // when the section is marked unimplemented — this
                        // satisfies "в релизе отключены без возможности
                        // включения".
                        Item {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            implicitHeight: sectionLoader.implicitHeight
                            enabled: !root._isUnimplemented(root.activeSection)
                            opacity: enabled ? 1.0 : 0.55
                            Loader {
                                id: sectionLoader
                                anchors.fill: parent
                                sourceComponent: {
                                    if (root.activeSection === "profile")       return sectionProfile;
                                    if (root.activeSection === "appearance")    return sectionAppearance;
                                    if (root.activeSection === "language") return sectionLanguage;
                                    if (root.activeSection === "notifications") return sectionNotifications;
                                    if (root.activeSection === "calendar")      return sectionCalendar;
                                    if (root.activeSection === "tasks")         return sectionTasks;
                                    if (root.activeSection === "shortcuts")     return sectionShortcuts;
                                    if (root.activeSection === "cpp")           return sectionCpp;
                                    if (root.activeSection === "integrations")  return sectionIntegrations;
                                    if (root.activeSection === "git")           return sectionGit;
                                    if (root.activeSection === "data")          return sectionData;
                                    if (root.activeSection === "help") return sectionHelp;
                                    if (root.activeSection === "about")         return sectionAbout;
                                    return null;
                                }
                            }
                        }
                        Item { Layout.preferredHeight: 24 }
                    }
                }
            }
        }
    }

    function _activeMeta() {
        for (let i = 0; i < sections.length; i++)
            if (sections[i].id === activeSection) return sections[i];
        return sections[0];
    }

    // Deep-link entry from the Welcome guide ("Learn more →"). Switch to the
    // Help section, then scroll to `anchor` once the body Loader has built
    // HelpContent (deferred a tick so _findChildByName can see it).
    function openHelp(anchor) {
        activeSection = "help";
        if (anchor && anchor.length > 0)
            Qt.callLater(() => _scrollToAnchor(anchor));
    }

    // In-page anchor scroll for HelpContent's TOC. Ported from DocsView.qml
    // (scrollToAnchor / findChildByName). Reuses bodyScroll + scrollAnim.
    function _scrollToAnchor(objectName) {
        const target = _findChildByName(bodyCol, objectName);
        if (!target) return;
        const p = target.mapToItem(bodyCol, 0, 0);
        const maxY = Math.max(0, bodyScroll.contentHeight - bodyScroll.height);
        const newY = Math.max(0, Math.min(p.y - 8, maxY));
        scrollAnim.from = bodyScroll.contentY;
        scrollAnim.to = newY;
        scrollAnim.restart();
    }

    function _findChildByName(parentItem, name) {
        if (!parentItem) return null;
        const kids = parentItem.children;
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i];
            if (k && k.objectName === name) return k;
            const sub = _findChildByName(k, name);
            if (sub) return sub;
        }
        return null;
    }

    // ── Reusable controls ─────────────────────────────────────────────

    component SectionCard: Rectangle {
        Layout.fillWidth: true
        radius: 10
        color: Theme.panel
        border.color: Theme.border; border.width: 1
        default property alias content: inner.data
        implicitHeight: inner.implicitHeight + 24
        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
        }
    }

    component Sub: Text {
        property string label: ""
        text: label
        color: Theme.textDim
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
        Layout.topMargin: 4
    }

    component FieldLabel: ColumnLayout {
        property string label: ""
        property string hint: ""
        spacing: 2
        Text { text: label.toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        Text { visible: hint.length > 0; text: hint; color: Theme.textDim; font.pixelSize: 10 }
    }

    component TextRow: ColumnLayout {
        id: textRow
        property string label: ""
        property string hint: ""
        property string placeholder: ""
        property bool mono: false
        property string value: ""
        signal committed(string text)
        spacing: 4
        Layout.fillWidth: true
        FieldLabel { label: textRow.label; hint: textRow.hint }
        TextField {
            id: textRowField
            Layout.fillWidth: true
            placeholderText: textRow.placeholder
            placeholderTextColor: Theme.textDim
            color: Theme.text
            font.family: textRow.mono ? Theme.fontMono : Theme.fontUi
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            selectByMouse: true
            // Re-sync from external value changes without breaking the user's
            // mid-edit text (no two-way binding → no loop, no per-keystroke
            // settings write).
            text: textRow.value
            onActiveFocusChanged: {
                if (!activeFocus && text !== textRow.value) textRow.committed(text);
            }
            onAccepted: {
                if (text !== textRow.value) textRow.committed(text);
            }
        }
    }

    component SwitchRow: RowLayout {
        property string label: ""
        property string hint: ""
        property bool checked: false
        signal toggled(bool checked)
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: parent.parent.label; color: Theme.text; font.pixelSize: 12; font.weight: Font.Medium }
            Text { visible: parent.parent.hint.length > 0; text: parent.parent.hint; color: Theme.textMuted; font.pixelSize: 10; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        Rectangle {
            Layout.preferredWidth: 36; Layout.preferredHeight: 20; radius: 10
            color: parent.checked ? Theme.accent : Theme.panel3
            border.color: parent.checked ? Theme.accent : Theme.border
            border.width: 1
            Rectangle {
                width: 14; height: 14; radius: 7
                color: "#fff"
                anchors.verticalCenter: parent.verticalCenter
                x: parent.parent.checked ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: Theme.scaledMs(120) } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.parent.toggled(!parent.parent.checked)
            }
        }
    }

    component SegRow: ColumnLayout {
        property string label: ""
        property string hint: ""
        property var options: []        // [{value,label}] or [string]
        property string value: ""
        signal selected(string value)
        spacing: 4
        Layout.fillWidth: true
        FieldLabel { label: parent.label; hint: parent.hint }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 6
            color: Theme.panel2
            border.color: Theme.border; border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 0
                Repeater {
                    model: parent.parent.parent.options
                    delegate: Rectangle {
                        required property var modelData
                        readonly property string v: typeof modelData === "string" ? modelData : modelData.value
                        readonly property string l: typeof modelData === "string" ? modelData : modelData.label
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 4
                        color: v === parent.parent.parent.value ? Theme.accent
                             : segMA.containsMouse ? Theme.panel3 : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: parent.l
                            color: parent.v === parent.parent.parent.parent.value ? "#06121a" : Theme.text
                            font.pixelSize: 11
                            font.weight: parent.v === parent.parent.parent.parent.value ? Font.DemiBold : Font.Medium
                        }
                        MouseArea {
                            id: segMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.parent.parent.parent.selected(parent.v)
                        }
                    }
                }
            }
        }
    }

    component SliderRow: ColumnLayout {
        property string label: ""
        property string hint: ""
        property string unit: ""
        property real min: 0
        property real max: 100
        property real step: 1
        property real value: 0
        signal moved(real value)
        spacing: 4
        Layout.fillWidth: true
        RowLayout {
            Layout.fillWidth: true
            Text { text: parent.parent.label.toUpperCase(); color: Theme.textMuted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
            Item { Layout.fillWidth: true }
            Text { text: Math.round(parent.parent.value) + parent.parent.unit; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11 }
        }
        Text { visible: parent.hint.length > 0; text: parent.hint; color: Theme.textDim; font.pixelSize: 10 }
        Slider {
            Layout.fillWidth: true
            from: parent.min; to: parent.max; stepSize: parent.step
            value: parent.value
            onMoved: parent.moved(value)
            background: Rectangle {
                x: parent.leftPadding; y: parent.topPadding + parent.availableHeight / 2 - 2
                implicitWidth: 200; implicitHeight: 4
                width: parent.availableWidth; height: implicitHeight
                radius: 2
                color: Theme.panel3
                Rectangle {
                    width: parent.parent.visualPosition * parent.width
                    height: parent.height; radius: 2; color: Theme.accent
                }
            }
            handle: Rectangle {
                x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                y: parent.topPadding + parent.availableHeight / 2 - height / 2
                width: 14; height: 14; radius: 7
                color: "#fff"
                border.color: Theme.border; border.width: 1
            }
        }
    }

    component SwatchRow: ColumnLayout {
        id: swRoot
        property string label: ""
        property string value: ""
        property var options: []
        signal selected(string color)
        spacing: 4
        Layout.fillWidth: true
        FieldLabel { label: swRoot.label }
        Row {
            spacing: 6
            Repeater {
                model: swRoot.options
                delegate: Rectangle {
                    required property string modelData
                    width: 26; height: 26; radius: 13
                    color: modelData
                    border.color: String(swRoot.value).toLowerCase() === modelData.toLowerCase() ? Theme.text : "transparent"
                    border.width: 2
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: swRoot.selected(modelData) }
                }
            }
        }
    }

    component DangerRow: RowLayout {
        property string title: ""
        property string hint: ""
        property string buttonText: ""
        signal triggered()
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: parent.parent.title; color: Theme.text; font.pixelSize: 12; font.weight: Font.Medium }
            Text { text: parent.parent.hint; color: Theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }
        Rectangle {
            radius: 6
            color: dangerMA.containsMouse ? Theme.withAlpha(Theme.p0, 0.20) : Theme.withAlpha(Theme.p0, 0.10)
            border.color: Theme.p0; border.width: 1
            implicitWidth: dangerTxt.implicitWidth + 24
            implicitHeight: 28
            Text { id: dangerTxt; anchors.centerIn: parent; text: parent.parent.buttonText; color: Theme.p0; font.pixelSize: 12; font.weight: Font.Medium }
            MouseArea { id: dangerMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.parent.triggered() }
        }
    }

    // ── Section components ────────────────────────────────────────────

    Component {
        id: sectionProfile
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Rectangle {
                            width: 56; height: 56; radius: 28
                            color: root.settings.profile ? root.settings.profile.color : Theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    const n = (root.settings.profile && root.settings.profile.name) || "?";
                                    const parts = n.split(/\s+/);
                                    return (parts[0] ? parts[0][0] : "") + (parts[1] ? parts[1][0] : "");
                                }
                                color: "#06121a"
                                font.family: Theme.fontMono
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            TextRow {
                                label: I18n.t("settings.profile.fullName")
                                value: (root.settings.profile && root.settings.profile.name) || ""
                                onCommitted: (text) => root.set("profile", "name", text)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                TextRow {
                                    Layout.fillWidth: true
                                    label: I18n.t("settings.profile.handle"); mono: true; placeholder: "alex.t"
                                    value: (root.settings.profile && root.settings.profile.handle) || ""
                                    onCommitted: (text) => root.set("profile", "handle", text)
                                }
                                TextRow {
                                    Layout.fillWidth: true
                                    label: I18n.t("settings.profile.role")
                                    value: (root.settings.profile && root.settings.profile.role) || ""
                                    onCommitted: (text) => root.set("profile", "role", text)
                                }
                            }
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        TextRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.profile.team")
                            value: (root.settings.profile && root.settings.profile.team) || ""
                            onCommitted: (text) => root.set("profile", "team", text)
                        }
                        TextRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.profile.timezone"); mono: true
                            value: (root.settings.profile && root.settings.profile.timezone) || ""
                            onCommitted: (text) => root.set("profile", "timezone", text)
                        }
                    }
                    SwatchRow {
                        label: I18n.t("settings.profile.avatarColor")
                        value: (root.settings.profile && root.settings.profile.color) || root.avatarSwatches[0]
                        options: root.avatarSwatches
                        onSelected: (color) => root.set("profile", "color", color)
                    }
                }
            }
        }
    }

    Component {
        id: sectionAppearance
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    SegRow {
                        label: I18n.t("settings.appearance.theme")
                        value: AppController.theme
                        options: [
                            ({value: "dark", label: I18n.t("settings.appearance.theme.dark")}),
                            ({value: "light", label: I18n.t("settings.appearance.theme.light")})
                        ]
                        onSelected: (value) => AppController.theme = value
                    }
                    SegRow {
                        label: I18n.t("settings.appearance.density")
                        value: AppController.density
                        options: [ ({ value: "compact", label: "Compact" }), ({ value: "comfy", label: "Comfy" }) ]
                        onSelected: (value) => AppController.density = value
                    }
                    SwatchRow {
                        label: I18n.t("settings.appearance.accent")
                        value: (root.settings.appearance && root.settings.appearance.accent) || Theme.accent
                        options: root.accentSwatches
                        onSelected: (color) => root.set("appearance", "accent", color)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    SwitchRow {
                        label: I18n.t("settings.appearance.reducedMotion")
                        hint: I18n.t("settings.appearance.reducedMotion.hint")
                        checked: !!(root.settings.appearance && root.settings.appearance.reducedMotion)
                        onToggled: (checked) => root.set("appearance", "reducedMotion", checked)
                    }
                    SwitchRow {
                        label: I18n.t("settings.appearance.highContrast")
                        hint: I18n.t("settings.appearance.highContrast.hint")
                        checked: !!(root.settings.appearance && root.settings.appearance.highContrast)
                        onToggled: (checked) => root.set("appearance", "highContrast", checked)
                    }
                }
            }
        }
    }

    Component {
        id: sectionLanguage
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    SegRow {
                        label: I18n.t("settings.language.label")
                        value: AppController.language
                        options: [
                            ({value: "en", label: "English"}),
                            ({value: "ru", label: "Русский"})
                        ]
                        onSelected: (value) => AppController.language = value
                    }
                    Text {
                        text: I18n.t("settings.language.hint")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    Component {
        id: sectionNotifications
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.notif.sub.deadlines")
                    }
                    SwitchRow {
                        label: I18n.t("settings.notif.deadlineReminders")
                        hint: I18n.t("settings.notif.deadlineReminders.hint")
                        checked: !!(root.settings.notifications && root.settings.notifications.deadlineReminders)
                        onToggled: (checked) => root.set("notifications", "deadlineReminders", checked)
                    }
                    SliderRow {
                        visible: !!(root.settings.notifications && root.settings.notifications.deadlineReminders)
                        label: I18n.t("settings.notif.leadHours")
                        unit: "h"; min: 1; max: 72; step: 1
                        value: (root.settings.notifications && root.settings.notifications.deadlineLeadHours) || 24
                        onMoved: (value) => root.set("notifications", "deadlineLeadHours", value)
                    }
                    SwitchRow {
                        label: I18n.t("settings.notif.standupReminder")
                        hint: I18n.t("settings.notif.standupReminder.hint")
                        checked: !!(root.settings.notifications && root.settings.notifications.standupReminder)
                        onToggled: (checked) => root.set("notifications", "standupReminder", checked)
                    }
                    SliderRow {
                        label: I18n.t("settings.notif.meetingLead")
                        unit: " min"; min: 0; max: 30; step: 1
                        // Undefined-aware fallback: a stored 0 is a valid lead
                        // (min is 0) and must not collapse to 5 via a falsy `||`.
                        value: root.settings.notifications
                               ? (root.settings.notifications.meetingLead ?? 5) : 5
                        onMoved: (value) => root.set("notifications", "meetingLead", value)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.notif.sub.channels")
                    }
                    SwitchRow {
                        label: I18n.t("settings.notif.desktopNotif")
                        checked: !!(root.settings.notifications && root.settings.notifications.desktopNotif)
                        onToggled: (checked) => root.set("notifications", "desktopNotif", checked)
                    }
                    SwitchRow {
                        label: I18n.t("settings.notif.mmPings")
                        hint: I18n.t("settings.notif.mmPings.hint")
                        checked: !!(root.settings.notifications && root.settings.notifications.mmPingsOnReview)
                        onToggled: (checked) => root.set("notifications", "mmPingsOnReview", checked)
                    }
                    SwitchRow {
                        label: I18n.t("settings.notif.blockedDigest")
                        checked: !!(root.settings.notifications && root.settings.notifications.blockedDailyDigest)
                        onToggled: (checked) => root.set("notifications", "blockedDailyDigest", checked)
                    }
                    SwitchRow {
                        label: I18n.t("settings.notif.soundOnPing")
                        checked: !!(root.settings.notifications && root.settings.notifications.soundOnPing)
                        onToggled: (checked) => root.set("notifications", "soundOnPing", checked)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.notif.sub.quiet")
                    }
                    SwitchRow {
                        label: I18n.t("settings.notif.quietHours")
                        hint: I18n.t("settings.notif.quietHours.hint")
                        checked: !!(root.settings.notifications && root.settings.notifications.quietHours)
                        onToggled: (checked) => root.set("notifications", "quietHours", checked)
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        visible: !!(root.settings.notifications && root.settings.notifications.quietHours)
                        TextRow {
                            Layout.fillWidth: true
                            label: I18n.t("common.from"); mono: true; placeholder: "19:00"
                            value: (root.settings.notifications && root.settings.notifications.quietFrom) || ""
                            onCommitted: (text) => root.set("notifications", "quietFrom", text)
                        }
                        TextRow {
                            Layout.fillWidth: true
                            label: I18n.t("common.to"); mono: true; placeholder: "09:00"
                            value: (root.settings.notifications && root.settings.notifications.quietTo) || ""
                            onCommitted: (text) => root.set("notifications", "quietTo", text)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sectionCalendar
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        SegRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.cal.weekStart")
                            value: (root.settings.calendar && root.settings.calendar.weekStart) || "mon"
                            options: [
                                ({value: "mon", label: I18n.t("settings.cal.weekStart.mon")}),
                                ({value: "sun", label: I18n.t("settings.cal.weekStart.sun")})
                            ]
                            onSelected: (value) => root.set("calendar", "weekStart", value)
                        }
                        SegRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.cal.timeFormat")
                            value: (root.settings.calendar && root.settings.calendar.timeFormat) || "24h"
                            options: [ ({ value: "24h", label: "24h" }), ({ value: "12h", label: "12h" }) ]
                            onSelected: (value) => root.set("calendar", "timeFormat", value)
                        }
                    }
                    Sub {
                        label: I18n.t("settings.cal.workHours")
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        SliderRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.cal.workStart"); unit: ":00"; min: 6; max: 12; step: 1
                            value: AppController.workdayStart
                            onMoved: (value) => AppController.workdayStart = value
                        }
                        SliderRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.cal.workEnd"); unit: ":00"; min: 14; max: 23; step: 1
                            value: AppController.workdayEnd
                            onMoved: (value) => AppController.workdayEnd = value
                        }
                    }
                    SegRow {
                        label: I18n.t("settings.cal.snap")
                        value: String((root.settings.calendar && root.settings.calendar.snapMinutes) || 15)
                        options: [ ({ value: "5", label: "5 min" }), ({ value: "15", label: "15 min" }), ({ value: "30", label: "30 min" }) ]
                        onSelected: (value) => root.set("calendar", "snapMinutes", parseInt(value))
                    }
                    SwitchRow {
                        label: I18n.t("settings.cal.showWeekends")
                        checked: !!(root.settings.calendar && root.settings.calendar.showWeekends)
                        onToggled: (checked) => root.set("calendar", "showWeekends", checked)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.cal.focus")
                    }
                    SwitchRow {
                        label: I18n.t("settings.cal.autoFocus")
                        hint: I18n.t("settings.cal.autoFocus.hint")
                        checked: !!(root.settings.calendar && root.settings.calendar.autoFocusBlock)
                        onToggled: (checked) => root.set("calendar", "autoFocusBlock", checked)
                    }
                    SliderRow {
                        visible: !!(root.settings.calendar && root.settings.calendar.autoFocusBlock)
                        label: I18n.t("settings.cal.focusDuration")
                        unit: " min"; min: 30; max: 240; step: 15
                        value: (root.settings.calendar && root.settings.calendar.focusBlockDuration) || 90
                        onMoved: (value) => root.set("calendar", "focusBlockDuration", value)
                    }
                    TextRow {
                        label: I18n.t("settings.cal.standupTime"); mono: true; placeholder: "10:00"
                        value: (root.settings.calendar && root.settings.calendar.standupTime) || ""
                        onCommitted: (text) => root.set("calendar", "standupTime", text)
                    }
                }
            }
        }
    }

    Component {
        id: sectionTasks
        ColumnLayout {
            id: sectionTasksRoot
            // Local UI toggle: when ON, committing a new idPrefix also rewrites
            // existing task ids (LTE-123 → HEAP-123). Not persisted across
            // sessions — it's a one-shot intent.
            property bool renameExistingOnCommit: false
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        TextRow {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            label: I18n.t("settings.tasks.idPrefix"); mono: true; placeholder: "LTE"
                            hint: I18n.t("settings.tasks.idPrefix.hint").arg((root.settings.tasks && root.settings.tasks.idPrefix) || "LTE")
                            value: (root.settings.tasks && root.settings.tasks.idPrefix) || ""
                            onCommitted: (text) => {
                                const next = (text || "").toUpperCase().trim();
                                const prior = (((root.settings.tasks && root.settings.tasks.idPrefix) || "")).toUpperCase().trim();
                                root.set("tasks", "idPrefix", next);
                                if (sectionTasksRoot.renameExistingOnCommit
                                    && next.length > 0
                                    && prior.length > 0
                                    && prior !== next) {
                                    AppController.renameTaskIdPrefix(prior, next);
                                    sectionTasksRoot.renameExistingOnCommit = false;
                                }
                            }
                        }
                        SegRow {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            label: I18n.t("settings.tasks.defaultPriority")
                            value: (root.settings.tasks && root.settings.tasks.defaultPriority) || "P2"
                            options: ["P0", "P1", "P2", "P3"]
                            onSelected: (value) => root.set("tasks", "defaultPriority", value)
                        }
                    }
                    SwitchRow {
                        label: I18n.t("settings.tasks.renameExisting")
                        hint: I18n.t("settings.tasks.renameExisting.hint")
                            .arg(((root.settings.tasks && root.settings.tasks.idPrefix) || "LTE").toUpperCase())
                        checked: sectionTasksRoot.renameExistingOnCommit
                        onToggled: (checked) => sectionTasksRoot.renameExistingOnCommit = checked
                    }
                    SegRow {
                        label: I18n.t("settings.tasks.defaultColumn")
                        value: (root.settings.tasks && root.settings.tasks.defaultStatus) || "todo"
                        options: [ ({ value: "backlog", label: "Backlog" }), ({ value: "todo", label: "To Do" }), ({ value: "prog", label: "In Progress" }) ]
                        onSelected: (value) => root.set("tasks", "defaultStatus", value)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.tasks.automations")
                    }
                    SliderRow {
                        label: I18n.t("settings.tasks.archiveDone")
                        unit: " " + I18n.t("common.days"); min: 0; max: 30; step: 1
                        hint: I18n.t("settings.tasks.archiveDone.hint")
                        value: (root.settings.tasks && root.settings.tasks.archiveDoneAfterDays) || 0
                        onMoved: (value) => root.set("tasks", "archiveDoneAfterDays", value)
                    }
                    SliderRow {
                        label: I18n.t("settings.tasks.blockedHi")
                        unit: " " + I18n.t("common.days"); min: 1; max: 14; step: 1
                        hint: I18n.t("settings.tasks.blockedHi.hint")
                        value: (root.settings.tasks && root.settings.tasks.autoMoveBlockedAfterDays) || 3
                        onMoved: (value) => root.set("tasks", "autoMoveBlockedAfterDays", value)
                    }
                    SwitchRow {
                        label: I18n.t("settings.tasks.branchOnReview")
                        hint: I18n.t("settings.tasks.branchOnReview.hint")
                        checked: !!(root.settings.tasks && root.settings.tasks.requireBranchOnReview)
                        onToggled: (checked) => root.set("tasks", "requireBranchOnReview", checked)
                    }
                    SwitchRow {
                        label: I18n.t("settings.tasks.showSubtasks")
                        checked: !!(root.settings.tasks && root.settings.tasks.showSubtasks)
                        onToggled: (checked) => root.set("tasks", "showSubtasks", checked)
                    }
                }
            }
        }
    }

    Component {
        id: sectionShortcuts
        ColumnLayout {
            spacing: 12
            SectionCard {
                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true
                        Sub {
                            label: I18n.t("settings.shortcuts.sub")
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            radius: 6; implicitWidth: openTxt.implicitWidth + 18; implicitHeight: 26
                            color: openMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            Text {
                                id:
                                    openTxt; anchors.centerIn: parent; text: I18n.t("settings.shortcuts.open"); color: Theme.text; font.pixelSize: 11
                            }
                            MouseArea { id: openMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settingsBridge.openHotkeysRequested() }
                        }
                    }
                    Text {
                        text: I18n.t("settings.shortcuts.intro")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 6
                    Layout.fillWidth: true
                    Repeater {
                        model: AppController.shortcuts
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                Text { text: modelData.label; color: Theme.text; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: modelData.description; color: Theme.textMuted; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                            Rectangle {
                                radius: 5
                                color: Theme.panel2
                                border.color: Theme.border; border.width: 1
                                implicitWidth: seqText.implicitWidth + 14; implicitHeight: 22
                                Text {
                                    id:
                                        seqText; anchors.centerIn: parent; text: modelData.sequence || I18n.t("settings.shortcuts.notSet"); color: modelData.sequence ? Theme.text : Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sectionCpp
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        SegRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.cpp.compiler")
                            value: (root.settings.cpp && root.settings.cpp.defaultCompiler) || "clang-17"
                            options: ["gcc-13", "clang-17", "clang-18"]
                            onSelected: (value) => root.set("cpp", "defaultCompiler", value)
                        }
                        SegRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.cpp.standard")
                            value: (root.settings.cpp && root.settings.cpp.defaultStandard) || "C++20"
                            options: ["C++17", "C++20", "C++23"]
                            onSelected: (value) => root.set("cpp", "defaultStandard", value)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        SegRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.cpp.sanitizer")
                            value: (root.settings.cpp && root.settings.cpp.defaultSanitizer) || "asan"
                            options: [ ({ value: "none", label: "None" }), ({ value: "asan", label: "ASan" }), ({ value: "tsan", label: "TSan" }), ({ value: "ubsan", label: "UBSan" }) ]
                            onSelected: (value) => root.set("cpp", "defaultSanitizer", value)
                        }
                        SegRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.cpp.buildType")
                            value: (root.settings.cpp && root.settings.cpp.defaultBuildType) || "RelWithDebInfo"
                            options: ["Debug", "RelWithDebInfo", "Release"]
                            onSelected: (value) => root.set("cpp", "defaultBuildType", value)
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    TextRow {
                        label: I18n.t("settings.cpp.bazelArgs"); mono: true; placeholder: "--jobs=12 --keep_going"
                        value: (root.settings.cpp && root.settings.cpp.bazelArgs) || ""
                        onCommitted: (text) => root.set("cpp", "bazelArgs", text)
                    }
                    TextRow {
                        label: I18n.t("settings.cpp.godbolt"); mono: true; placeholder: "https://godbolt.org/"
                        value: (root.settings.cpp && root.settings.cpp.compilerExplorerUrl) || ""
                        onCommitted: (text) => root.set("cpp", "compilerExplorerUrl", text)
                    }
                    SwitchRow {
                        label: I18n.t("settings.cpp.inlineAsm")
                        hint: I18n.t("settings.cpp.inlineAsm.hint")
                        checked: !!(root.settings.cpp && root.settings.cpp.showAsmInline)
                        onToggled: (checked) => root.set("cpp", "showAsmInline", checked)
                    }
                }
            }
        }
    }

    Component {
        id: sectionIntegrations
        ColumnLayout {
            id: intSection
            spacing: 12

            // Device-flow OAuth banner state (GitHub): the code the user types in
            // the browser. Set from AppController.oauthDeviceCode; empty = hidden.
            property string dcProvider: ""
            property string dcCode: ""
            property string dcUri: ""
            Connections {
                target: AppController
                function onOauthDeviceCode(provider, code, uri) {
                    intSection.dcProvider = provider
                    intSection.dcCode = code
                    intSection.dcUri = uri
                }
            }

            // Periodic auto-sync cadence (integrations.autoSyncMinutes, 0 = off).
            SectionCard {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { text: I18n.t("settings.integrations.autoSync"); color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { text: I18n.t("settings.integrations.autoSyncHint"); color: Theme.textMuted; font.pixelSize: 11 }
                    }
                    Repeater {
                        model: [
                            { label: I18n.t("settings.integrations.off"), v: 0 },
                            { label: "15m", v: 15 },
                            { label: "30m", v: 30 },
                            { label: "60m", v: 60 }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property int cur: (root.settings.integrations && root.settings.integrations.autoSyncMinutes) || 0
                            radius: 6
                            implicitWidth: asTxt.implicitWidth + 20; implicitHeight: 26
                            color: cur === modelData.v ? Theme.accent : (asMA.containsMouse ? Theme.panel3 : Theme.panel2)
                            border.color: cur === modelData.v ? Theme.accent : Theme.border; border.width: 1
                            Text {
                                id: asTxt; anchors.centerIn: parent; text: modelData.label
                                color: parent.cur === modelData.v ? "#06121a" : Theme.text; font.pixelSize: 11
                            }
                            MouseArea {
                                id: asMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.set("integrations", "autoSyncMinutes", modelData.v)
                            }
                        }
                    }
                }
            }

            // One card per registered provider — the catalogue is the single
            // source of truth (AppController.integrationCatalog), so adding a
            // provider in C++ surfaces a card here with no QML change.
            Repeater {
                model: AppController.integrationCatalog()
                delegate: SectionCard {
                    required property var modelData
                    ColumnLayout {
                        id: intCard
                        spacing: 10
                        Layout.fillWidth: true
                        readonly property string intKey: modelData.id
                        readonly property var conf: (root.settings.integrations && root.settings.integrations[intKey]) || ({})
                        readonly property bool isConn: intCard.conf.connected === true
                        readonly property bool isOAuth: modelData.oauth === true
                        // One-click browser sign-in is only offered when a client ID
                        // exists — baked into the build (oauthReady) or entered under
                        // Advanced (self-hosted). Otherwise the card is PAT-only, so
                        // gitea/forgejo never show a dead "No OAuth app" button.
                        readonly property bool canOneClick: modelData.oauthReady === true
                            || (intCard.isOAuth && intCard.conf.clientId !== undefined && String(intCard.conf.clientId).length > 0)
                        // Collapsed by default; connected cards start open. Assigning
                        // to `open`/`advanced` on click breaks the initial binding.
                        property bool open: intCard.isConn
                        property bool advanced: false

                        // ── Header — click anywhere to expand / collapse ──
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: hdrRow.implicitHeight
                            RowLayout {
                                id: hdrRow
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12
                                Rectangle {
                                    width: 32; height: 32; radius: 6
                                    color: modelData.color
                                    Text { anchors.centerIn: parent; text: modelData.icon; color: "#06121a"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { text: modelData.name; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { text: I18n.t(modelData.descKey); color: Theme.textMuted; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                                }
                                Text {
                                    text: intCard.isConn ? I18n.t("common.connected") : I18n.t("common.disconnected")
                                    color: intCard.isConn ? Theme.mFocus : Theme.textDim
                                    font.family: Theme.fontMono; font.pixelSize: 10
                                }
                                Text {
                                    text: intCard.open ? "▾" : "▸"   // ▾ / ▸
                                    color: Theme.textDim; font.pixelSize: 12
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: intCard.open = !intCard.open
                            }
                        }

                        // ── Body (only when expanded) ──
                        ColumnLayout {
                            visible: intCard.open
                            Layout.fillWidth: true
                            Layout.leftMargin: 44
                            spacing: 8

                            // Device-flow banner: show the code the user must
                            // enter in the browser (GitHub). Auto-clears on finish.
                            Rectangle {
                                visible: intSection.dcCode !== "" && intSection.dcProvider === intCard.intKey
                                Layout.fillWidth: true
                                radius: 6
                                color: Theme.panel2
                                border.color: Theme.accent; border.width: 1
                                implicitHeight: dcCol.implicitHeight + 16
                                ColumnLayout {
                                    id: dcCol
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: 10
                                    spacing: 4
                                    Text {
                                        text: I18n.t("settings.integrations.deviceCodePrompt")
                                        color: Theme.textMuted; font.pixelSize: 11
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    }
                                    TextEdit {
                                        text: intSection.dcCode
                                        readOnly: true; selectByMouse: true
                                        color: Theme.text; font.family: Theme.fontMono
                                        font.pixelSize: 20; font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: intSection.dcUri
                                        color: Theme.mFocus; font.family: Theme.fontMono; font.pixelSize: 10
                                    }
                                }
                            }

                            // One-click browser connect: the primary action for
                            // OAuth providers. No fields to fill — credentials come
                            // from the app's registered OAuth app (or Advanced).
                            Rectangle {
                                visible: intCard.canOneClick && !intCard.isConn
                                Layout.fillWidth: true
                                radius: 6
                                color: oauthMA.containsMouse ? Theme.accentStrong : Theme.accent
                                border.color: Theme.accent; border.width: 1
                                implicitHeight: 34
                                Text { anchors.centerIn: parent; text: I18n.t("settings.integrations.browserSignIn"); color: "#06121a"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                MouseArea { id: oauthMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AppController.connectOAuth(intCard.intKey) }
                            }
                            Text {
                                visible: intCard.canOneClick && !intCard.isConn
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: I18n.t("settings.integrations.connectBrowserHint")
                                color: Theme.textDim; font.pixelSize: 10
                            }
                            // OAuth-capable but no client ID yet (self-hosted gitea/
                            // forgejo): tell the user to add one under Advanced.
                            Text {
                                visible: intCard.isOAuth && !intCard.canOneClick && !intCard.isConn
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: I18n.t("settings.integrations.oauthNeedsId")
                                color: Theme.textDim; font.pixelSize: 10
                            }

                            // Advanced disclosure — hides the credential/scope
                            // fields (token, repo, client ID…) so they don't clutter
                            // the default view. Shown for OAuth cards and connected
                            // cards; non-OAuth cards that aren't connected show the
                            // fields directly (a token is required to connect).
                            Text {
                                visible: intCard.canOneClick || intCard.isConn
                                text: (intCard.advanced ? "▾  " : "▸  ") + I18n.t("settings.integrations.advanced")
                                color: Theme.textMuted; font.pixelSize: 11
                                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: intCard.advanced = !intCard.advanced }
                            }

                            // Credential / scope fields. Secret fields (token/key)
                            // go to the OS keychain via setIntegrationSecret — never
                            // into state.json.
                            ColumnLayout {
                                visible: intCard.advanced || (!intCard.canOneClick && !intCard.isConn)
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: modelData.fields
                                    delegate: TextRow {
                                        required property var modelData
                                        label: modelData.label
                                        placeholder: modelData.placeholder
                                        mono: !!modelData.mono
                                        value: modelData.secret
                                               ? AppController.integrationSecret(intCard.intKey, modelData.key)
                                               : ((intCard.conf && intCard.conf[modelData.key]) || "")
                                        onCommitted: (txt) => modelData.secret
                                            ? AppController.setIntegrationSecret(intCard.intKey, modelData.key, txt)
                                            : root.setNested("integrations", intCard.intKey, modelData.key, txt)
                                    }
                                }
                            }

                            // Actions: manual connect (non-OAuth) / test / sync / disconnect.
                            RowLayout {
                                Layout.topMargin: 2
                                spacing: 8
                                Rectangle {
                                    visible: !intCard.canOneClick && !intCard.isConn
                                    radius: 6
                                    color: connMA.containsMouse ? Theme.accentStrong : Theme.accent
                                    border.color: Theme.accent; border.width: 1
                                    implicitWidth: connTxt.implicitWidth + 24; implicitHeight: 28
                                    Text { id: connTxt; anchors.centerIn: parent; text: I18n.t("common.connect"); color: "#06121a"; font.pixelSize: 11; font.weight: Font.Medium }
                                    MouseArea { id: connMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setNested("integrations", intCard.intKey, "connected", true) }
                                }
                                Rectangle {
                                    visible: intCard.advanced || intCard.isConn || !intCard.canOneClick
                                    radius: 6
                                    color: testMA.containsMouse ? Theme.panel3 : Theme.panel2
                                    border.color: Theme.border; border.width: 1
                                    implicitWidth: testTxt.implicitWidth + 24; implicitHeight: 28
                                    Text { id: testTxt; anchors.centerIn: parent; text: I18n.t("settings.integrations.testConnection"); color: Theme.text; font.pixelSize: 11 }
                                    MouseArea { id: testMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AppController.testIntegration(intCard.intKey) }
                                }
                                Rectangle {
                                    visible: intCard.isConn
                                    radius: 6
                                    color: syncMA.containsMouse ? Theme.panel3 : Theme.panel2
                                    border.color: Theme.border; border.width: 1
                                    implicitWidth: syncTxt.implicitWidth + 24; implicitHeight: 28
                                    Text { id: syncTxt; anchors.centerIn: parent; text: I18n.t("settings.integrations.syncNow"); color: Theme.text; font.pixelSize: 11 }
                                    MouseArea { id: syncMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AppController.syncProvider(intCard.intKey) }
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    visible: intCard.isConn
                                    radius: 6
                                    color: discMA.containsMouse ? Theme.panel3 : Theme.panel2
                                    border.color: Theme.border; border.width: 1
                                    implicitWidth: discTxt.implicitWidth + 24; implicitHeight: 28
                                    Text { id: discTxt; anchors.centerIn: parent; text: I18n.t("common.disconnect"); color: Theme.textDim; font.pixelSize: 11 }
                                    MouseArea { id: discMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setNested("integrations", intCard.intKey, "connected", false) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sectionGit
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.git.repos")
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("settings.git.repos.hint")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("settings.git.match.hint")
                                .arg(((root.settings.tasks && root.settings.tasks.idPrefix) || "LTE").toUpperCase())
                        color: Theme.textMuted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: (root.settings.git && root.settings.git.watchedRepos) || []
                        delegate: RowLayout {
                            required property string modelData
                            required property int    index
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: modelData
                                elide: Text.ElideMiddle
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }
                            Rectangle {
                                radius: 4
                                color: rmMA.containsMouse
                                    ? Theme.withAlpha(Theme.p0, 0.18)
                                    : "transparent"
                                border.color: Theme.p0; border.width: 1
                                implicitWidth: 22; implicitHeight: 22
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: Theme.p0
                                }
                                MouseArea {
                                    id: rmMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const arr = ((root.settings.git
                                                    && root.settings.git.watchedRepos) || []).slice();
                                        arr.splice(index, 1);
                                        root.set("git", "watchedRepos", arr);
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextField {
                            id: newRepoField
                            Layout.fillWidth: true
                            placeholderText: "C:/path/to/repo"
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            background: Rectangle {
                                radius: 6
                                color: Theme.panel2
                                border.color: Theme.border
                                border.width: 1
                            }
                            selectByMouse: true
                        }
                        Rectangle {
                            radius: 6
                            implicitHeight: 30
                            implicitWidth: addT.implicitWidth + 22
                            color: addMA.containsMouse ? Theme.accentStrong : Theme.accent
                            Text {
                                id: addT
                                anchors.centerIn: parent
                                text: "+ " + I18n.t("common.add")
                                color: Theme.bg
                                font.weight: Font.Medium
                            }
                            MouseArea {
                                id: addMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const p = newRepoField.text.trim();
                                    if (!p.length) return;
                                    const arr = ((root.settings.git
                                                && root.settings.git.watchedRepos) || []).slice();
                                    if (!arr.includes(p)) arr.push(p);
                                    root.set("git", "watchedRepos", arr);
                                    newRepoField.text = "";
                                }
                            }
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.git.autoOn")
                    }
                    SwitchRow {
                        label: I18n.t("settings.git.autoMove")
                        hint: I18n.t("settings.git.autoMove.hint")
                        checked: !!(root.settings.git && root.settings.git.autoMoveToInProgress)
                        onToggled: (checked) => root.set("git", "autoMoveToInProgress", checked)
                    }
                    SwitchRow {
                        label: I18n.t("settings.git.autoFocus")
                        hint: I18n.t("settings.git.autoFocus.hint")
                        checked: !!(root.settings.git && root.settings.git.autoCreateFocusBlock)
                        onToggled: (checked) => root.set("git", "autoCreateFocusBlock", checked)
                    }
                    SwitchRow {
                        label: I18n.t("settings.git.prState")
                        hint: I18n.t("settings.git.prState.hint")
                        checked: !!(root.settings.git && root.settings.git.watchPrState)
                        onToggled: (checked) => root.set("git", "watchPrState", checked)
                    }
                }
            }
        }
    }

    Component {
        id: sectionData
        ColumnLayout {
            id: dataRoot
            spacing: 16
            // Backups are read on demand (listBackups() is a plain invokable,
            // not a notifying property). The Data section is rebuilt whenever
            // the user opens it, so refreshing on completion keeps it current.
            property var backups: []
            function refreshBackups() { dataRoot.backups = AppController.listBackups(); }
            Component.onCompleted: dataRoot.refreshBackups()
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.data.backups")
                    }
                    SwitchRow {
                        label: I18n.t("settings.data.autoBackup")
                        hint: I18n.t("settings.data.autoBackup.hint")
                        checked: !!(root.settings.data && root.settings.data.autoBackup)
                        onToggled: (checked) => root.set("data", "autoBackup", checked)
                    }
                    SegRow {
                        visible: !!(root.settings.data && root.settings.data.autoBackup)
                        label: I18n.t("settings.data.interval")
                        value: (root.settings.data && root.settings.data.backupInterval) || "daily"
                        options: [
                            ({value: "hourly", label: I18n.t("settings.data.interval.hourly")}),
                            ({value: "daily", label: I18n.t("settings.data.interval.daily")}),
                            ({value: "weekly", label: I18n.t("settings.data.interval.weekly")})
                        ]
                        onSelected: (value) => root.set("data", "backupInterval", value)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.data.restore")
                    }
                    Text {
                        visible: dataRoot.backups.length === 0
                        text: I18n.t("settings.data.restore.empty")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: dataRoot.backups
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 12
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: modelData.mtime; color: Theme.text; font.pixelSize: 12; font.family: Theme.fontMono }
                                Text {
                                    text: modelData.fileName + "  ·  " + modelData.sizeKb + " KB"
                                    color: Theme.textMuted; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true
                                }
                            }
                            // Two-step confirm: first click arms (restore
                            // overwrites the live state), second within 3.5 s
                            // performs it. Auto-disarms so a stray click is safe.
                            Rectangle {
                                id: restoreBtn
                                property bool armed: false
                                radius: 6
                                color: restoreMA.containsMouse ? Theme.panel3 : Theme.panel2
                                border.color: restoreBtn.armed ? Theme.p0 : Theme.border
                                border.width: 1
                                implicitWidth: restoreTxt.implicitWidth + 24
                                implicitHeight: 28
                                Text {
                                    id: restoreTxt
                                    anchors.centerIn: parent
                                    text: restoreBtn.armed ? I18n.t("settings.data.restore.confirm") : I18n.t("settings.data.restore.button")
                                    color: restoreBtn.armed ? Theme.p0 : Theme.text
                                    font.pixelSize: 12
                                }
                                Timer { id: restoreDisarm; interval: 3500; onTriggered: restoreBtn.armed = false }
                                MouseArea {
                                    id: restoreMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!restoreBtn.armed) {
                                            restoreBtn.armed = true;
                                            restoreDisarm.restart();
                                        } else {
                                            restoreBtn.armed = false;
                                            restoreDisarm.stop();
                                            AppController.restoreFromBackup(modelData.fileName);
                                            dataRoot.refreshBackups();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.data.importExport")
                    }
                    Text {
                        text: I18n.t("settings.data.importExport.hint")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            radius: 6
                            color: expMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            implicitWidth: expTxt.implicitWidth + 24; implicitHeight: 30
                            Text {
                                id:
                                    expTxt; anchors.centerIn: parent; text: I18n.t("settings.data.exportJson"); color: Theme.text; font.pixelSize: 12
                            }
                            MouseArea { id: expMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settingsBridge.exportJsonRequested() }
                        }
                        Rectangle {
                            radius: 6
                            color: impMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            implicitWidth: impTxt.implicitWidth + 24; implicitHeight: 30
                            Text {
                                id:
                                    impTxt; anchors.centerIn: parent; text: I18n.t("settings.data.importJson"); color: Theme.text; font.pixelSize: 12
                            }
                            MouseArea { id: impMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settingsBridge.importJsonRequested() }
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.data.danger")
                    }
                    DangerRow {
                        title: I18n.t("settings.data.reset")
                        hint: I18n.t("settings.data.reset.hint")
                        buttonText: I18n.t("settings.data.resetButton")
                        onTriggered: root.resetAll()
                    }
                    // Full wipe → first-run. Two-step confirm (the button arms,
                    // then commits) because this erases everything irreversibly.
                    RowLayout {
                        id: wipeRow
                        property bool armed: false
                        Layout.fillWidth: true
                        spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { text: I18n.t("settings.data.wipe"); color: Theme.text; font.pixelSize: 12; font.weight: Font.Medium }
                            Text { text: I18n.t("settings.data.wipe.hint"); color: Theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        Rectangle {
                            radius: 6
                            color: wipeRow.armed ? Theme.p0
                                 : (wipeMA.containsMouse ? Theme.withAlpha(Theme.p0, 0.20) : Theme.withAlpha(Theme.p0, 0.10))
                            border.color: Theme.p0; border.width: 1
                            implicitWidth: wipeTxt.implicitWidth + 24
                            implicitHeight: 28
                            Text {
                                id: wipeTxt; anchors.centerIn: parent
                                text: wipeRow.armed ? I18n.t("settings.data.wipe.confirm") : I18n.t("settings.data.wipeButton")
                                color: wipeRow.armed ? "#0b0b0f" : Theme.p0; font.pixelSize: 12; font.weight: Font.Medium
                            }
                            MouseArea {
                                id: wipeMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!wipeRow.armed) { wipeRow.armed = true; wipeDisarm.restart(); }
                                    else { wipeRow.armed = false; wipeDisarm.stop(); AppController.resetToFirstRun(); }
                                }
                            }
                            Timer { id: wipeDisarm; interval: 3500; onTriggered: wipeRow.armed = false }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sectionHelp
        HelpContent {
            onAnchorRequested: (name) => root._scrollToAnchor(name)
        }
    }

    Component {
        id: sectionAbout
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 12
                        BrandLogo {
                            variant: "mark"
                            theme: Theme.dark ? "dark" : "light"
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                        }
                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: "heap."; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 16; font.weight: Font.DemiBold
                            }
                            Text {
                                text: Brand.tagline; color: Theme.textMuted; font.pixelSize: 11
                            }
                        }
                    }
                    ColumnLayout {
                        spacing: 6
                        Layout.topMargin: 4
                        Layout.fillWidth: true
                        AboutRow {
                            label: I18n.t("settings.about.version"); value: AppController.appVersion
                        }
                        AboutRow {
                            label: I18n.t("settings.about.channel"); value: "stable"
                        }
                        AboutRow {
                            label: I18n.t("settings.about.storage"); value: AppController.dataDir
                        }
                        AboutRow {
                            label: I18n.t("settings.about.engine"); value: "Qt " + AppController.qtVersion + " · QML"
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.about.diagnostics")
                    }
                    Text {
                        text: I18n.t("settings.about.diagnostics.hint")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            radius: 6
                            color: reportMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            implicitWidth: reportTxt.implicitWidth + 24; implicitHeight: 30
                            Text {
                                id: reportTxt; anchors.centerIn: parent; text: I18n.t("settings.about.reportIssue"); color: Theme.text; font.pixelSize: 12
                            }
                            MouseArea { id: reportMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AppController.reportAnIssue() }
                        }
                        Rectangle {
                            radius: 6
                            color: logsMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            implicitWidth: logsTxt.implicitWidth + 24; implicitHeight: 30
                            Text {
                                id: logsTxt; anchors.centerIn: parent; text: I18n.t("settings.about.openLogs"); color: Theme.text; font.pixelSize: 12
                            }
                            MouseArea { id: logsMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AppController.openLogsFolder() }
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    id: updatesCol
                    property bool updateReady: false
                    spacing: 12
                    Layout.fillWidth: true
                    Connections {
                        target: AppController
                        function onUpdateAvailable(version, url) { updatesCol.updateReady = true }
                    }
                    Sub {
                        label: I18n.t("settings.about.updates")
                    }
                    Text {
                        text: AppController.updateStatus === "" ? I18n.t("settings.about.updates.hint") : AppController.updateStatus
                        color: Theme.textMuted
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            radius: 6
                            color: checkMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            implicitWidth: checkTxt.implicitWidth + 24; implicitHeight: 30
                            Text {
                                id: checkTxt; anchors.centerIn: parent; text: I18n.t("settings.about.checkUpdates"); color: Theme.text; font.pixelSize: 12
                            }
                            MouseArea { id: checkMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AppController.checkForUpdates() }
                        }
                        Rectangle {
                            visible: updatesCol.updateReady
                            radius: 6
                            color: dlMA.containsMouse ? Theme.accent : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            implicitWidth: dlTxt.implicitWidth + 24; implicitHeight: 30
                            Text {
                                id: dlTxt; anchors.centerIn: parent; text: I18n.t("settings.about.download"); color: Theme.text; font.pixelSize: 12
                            }
                            MouseArea { id: dlMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AppController.openLatestRelease() }
                        }
                    }
                    SwitchRow {
                        label: I18n.t("settings.about.autoCheck")
                        checked: !!(root.settings.updates && root.settings.updates.autoCheck)
                        onToggled: (checked) => root.set("updates", "autoCheck", checked)
                    }
                }
            }
        }
    }

    component AboutRow: RowLayout {
        id: aboutRow
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 16
        Text { text: aboutRow.label; color: Theme.textMuted; font.pixelSize: 11; Layout.preferredWidth: 80 }
        Text { text: aboutRow.value; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11; Layout.fillWidth: true }
    }

    // ── Bridge to Main.qml for popups (HotkeysPanel, FileDialog) ──────
    QtObject {
        id: settingsBridge
        signal openHotkeysRequested()
        signal exportJsonRequested()
        signal importJsonRequested()
    }
    Connections {
        target: settingsBridge
        function onOpenHotkeysRequested() { if (typeof settingsBus !== "undefined") settingsBus.openHotkeys() }
        function onExportJsonRequested()  { if (typeof settingsBus !== "undefined") settingsBus.exportJson() }
        function onImportJsonRequested()  { if (typeof settingsBus !== "undefined") settingsBus.importJson() }
    }
}
