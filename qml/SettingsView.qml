// Settings view — full per-profile / global configuration screen.
// Layout: left nav with 10 sections, right detail panel. New app-wide
// settings persist as JSON in AppController.appSettingsJson.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Controls.impl
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
            icon: "qrc:/brand/icons/heap-13-profile.svg",
            title: I18n.t("settings.section.profile.title"),
            sub: I18n.t("settings.section.profile.sub")
        },
        {
            id: "appearance",
            icon: "qrc:/brand/icons/heap-14-appearance.svg",
            title: I18n.t("settings.section.appearance.title"),
            sub: I18n.t("settings.section.appearance.sub")
        },
        {
            id: "language",
            icon: "qrc:/brand/icons/heap-15-language.svg",
            title: I18n.t("settings.section.language.title"),
            sub: I18n.t("settings.section.language.sub")
        },
        {
            id: "notifications",
            icon: "qrc:/brand/icons/heap-16-notifications.svg",
            title: I18n.t("settings.section.notifications.title"),
            sub: I18n.t("settings.section.notifications.sub")
        },
        {
            id: "calendar",
            icon: "qrc:/brand/icons/heap-17-calendar.svg",
            title: I18n.t("settings.section.calendar.title"),
            sub: I18n.t("settings.section.calendar.sub")
        },
        {
            id: "tasks",
            icon: "qrc:/brand/icons/heap-01-board.svg",
            title: I18n.t("settings.section.tasks.title"),
            sub: I18n.t("settings.section.tasks.sub")
        },
        {
            id: "shortcuts",
            icon: "qrc:/brand/icons/heap-10-hotkeys.svg",
            title: I18n.t("settings.section.shortcuts.title"),
            sub: I18n.t("settings.section.shortcuts.sub")
        },
        {
            id: "cpp",
            icon: "qrc:/brand/icons/heap-18-code.svg",
            title: I18n.t("settings.section.cpp.title"),
            sub: I18n.t("settings.section.cpp.sub"),
          unimplemented: true },
        {
            id: "integrations",
            icon: "qrc:/brand/icons/heap-19-integrations.svg",
            title: I18n.t("settings.section.integrations.title"),
            sub: I18n.t("settings.section.integrations.sub")
        },
        {id: "git", icon: "qrc:/brand/icons/heap-07-code-review.svg", title: I18n.t("settings.section.git.title"), sub: I18n.t("settings.section.git.sub")},
        {id: "data", icon: "qrc:/brand/icons/heap-20-data.svg", title: I18n.t("settings.section.data.title"), sub: I18n.t("settings.section.data.sub")},
        {id: "help", icon: "qrc:/brand/icons/heap-21-help.svg", title: I18n.t("settings.section.help.title"), sub: I18n.t("settings.section.help.sub")},
        {
            id: "about",
            icon: "qrc:/brand/icons/heap-22-about.svg",
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

    // Monochrome provider marks from the brand icon set, by catalogue id.
    readonly property var providerLogos: ({
        "github": "heap-23-github", "gitlab": "heap-24-gitlab",
        "gitea": "heap-25-gitea", "forgejo": "heap-26-forgejo",
        "redmine": "heap-27-redmine", "todoist": "heap-28-todoist",
        "asana": "heap-29-asana", "clickup": "heap-30-clickup",
        "sentry": "heap-31-sentry", "bitbucket": "heap-32-bitbucket",
        "jira": "heap-33-jira", "trello": "heap-34-trello",
        "mattermost": "heap-35-mattermost"
    })
    property string searchText: ""

    // ── Settings state — single source of truth, persisted via JSON blob ──
    property var settings: ({})
    property bool _loadedOnce: false
    property bool _persisting: false
    property bool _reloading:  false

    readonly property var defaults: ({
        // Blank until the user fills it in: a fresh install used to open on
        // the author's own name, role and team.
        profile: {
            name: "",
            handle: "",
            role: "",
            team: "",
            color: Theme.swatches[0]
        },
        appearance: {
            // No accent / theme defaults here: an absent darkPreset /
            // lightPreset means the built-in heap. themes (Theme.qml), and
            // writing a default would pin a profile to it.
            fontUI: "IBM Plex Sans",
            fontMono: "JetBrains Mono",
            reducedMotion: false,
            highContrast: false
        },
        notifications: {
            deadlineReminders: true, deadlineLeadHours: 24,
            standupReminder: true, meetingLead: 5, meetingReminders: true,
            blockedDailyDigest: false,
            soundOnPing: false, desktopNotif: true,
            quietHours: true, quietFrom: "19:00", quietTo: "09:00"
        },
        calendar: {
            weekStart: "mon", timeFormat: "24h",
            snapMinutes: 15, showWeekends: true,
            autoFocusBlock: true, focusBlockDuration: 90,
            standupTime: "10:00"
        },
        tasks: {
            idPrefix: "TASK", defaultPriority: "P2", defaultStatus: "todo",
            archiveDoneAfterDays: 7, autoMoveBlockedAfterDays: 3,
            // Off by default: a user without git could not move anything to
            // Code Review.
            requireBranchOnReview: false
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

    readonly property var avatarSwatches: Theme.swatches
    // Integration cards whose status mapping is unfolded, by integration id.
    property var _openStatusMaps: ({})
    function toggleStatusMap(key) {
        const m = Object.assign({}, root._openStatusMaps);
        m[key] = !(m[key] === true);
        root._openStatusMaps = m;
    }

    // A stored number, or `fallback` when there is none. `v || fallback` was
    // the old shape and turned a stored 0 into the default; `??` is the
    // obvious replacement but qmlcachegen 6.9.1 segfaults on it here.
    function _num(v, fallback) {
        return (v === undefined || v === null || v === false) ? fallback : v;
    }

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
        // Preferences only, onto a new install's look; connections, repos,
        // own themes and layout stay, and the toast offers Undo (UX-5).
        AppController.resetSettingsToDefaults();
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
                anchors.margins: Theme.sp2xl
                spacing: Theme.spSm

                Text {
                    text: I18n.t("settings.title")
                    color: Theme.text
                    font.weight: Font.DemiBold
                    font.pixelSize: Theme.fsLg
                }
                Text {
                    // The number of sections in the nav — it used to count
                    // the settings blob's top-level keys, which grew with
                    // every stored UI preference. The handle is dropped with
                    // its separator when there is none.
                    text: {
                        const handle = root.settings.profile ? (root.settings.profile.handle || "") : "";
                        const s = I18n.t("settings.groups").arg(root.sections.length).arg(handle);
                        return handle ? s : s.replace(/\s*·\s*$/, "");
                    }
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsXs
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    Layout.topMargin: Theme.spSm
                    radius: Theme.radiusMd
                    color: Theme.panel2
                    border.color: settingsSearch.activeFocus ? Theme.focusRing : Theme.fieldBorder
                    border.width: settingsSearch.activeFocus ? 2 : 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spMd
                        spacing: Theme.spSm
                        Text { text: "⌕"; color: Theme.textDim; font.pixelSize: Theme.fsSm }
                        TextField {
                            id: settingsSearch
                            objectName: "settings-search"
                            Layout.fillWidth: true
                            placeholderText: I18n.t("settings.search")
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                            background: Item {}
                            font.pixelSize: Theme.fsMd
                            text: root.searchText
                            onTextChanged: root.searchText = text
                            // Enter opens the first section that matches; ↓
                            // moves into the list. Both were dead.
                            onAccepted: root._openFirstMatch()
                            Keys.onDownPressed: root._focusNav(0)
                        }
                    }
                }

                // Scrollable: thirteen 44px rows plus the header and footer do
                // not fit the window's minimum height, and without a scroll the
                // layout just squeezed the rows into each other.
                Flickable {
                    id: navScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: Theme.spXs
                    clip: true
                    contentWidth: width
                    contentHeight: navCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ThinScrollBar {}

                    ColumnLayout {
                        id: navCol
                        width: navScroll.width
                        spacing: Theme.sp2xs
                        Repeater {
                            id: navRep
                            model: root.sections
                            delegate: Rectangle {
                                id: navRow
                                required property var modelData
                                required property int index
                                objectName: "settings-nav-" + modelData.id
                                visible: root._sectionMatches(modelData)
                                // A list box: Tab lands on it, ↑/↓ move and open,
                                // Enter / Space open.
                                activeFocusOnTab: true
                                Accessible.role: Accessible.PageTab
                                Accessible.name: modelData.title
                                Keys.onUpPressed: root._focusNav(index - 1, -1)
                                Keys.onDownPressed: root._focusNav(index + 1, 1)
                                Keys.onSpacePressed: root.activeSection = modelData.id
                                Keys.onReturnPressed: root.activeSection = modelData.id
                                onActiveFocusChanged: if (activeFocus) root.activeSection = modelData.id
                                FocusRing {}
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                Layout.minimumHeight: 44
                                radius: Theme.radiusMd
                                color: root.activeSection === modelData.id
                                       ? Theme.accentSoft
                                       : (navMA.containsMouse ? Theme.panel2 : "transparent")
                                border.color: root.activeSection === modelData.id ? Theme.accent : "transparent"
                                border.width: 1
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spLg
                                    spacing: Theme.spLg
                                    // One drawn icon set, the same as the side
                                    // rail's; the unicode glyphs came from
                                    // whatever font had them, in any size.
                                    IconImage {
                                        source: modelData.icon
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        sourceSize.width: 36
                                        sourceSize.height: 36
                                        color: root.activeSection === modelData.id ? Theme.accentStrong : Theme.textMuted
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text { text: modelData.title; color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Font.Medium }
                                        Text { text: modelData.sub;   color: Theme.textMuted; font.pixelSize: Theme.fsXs; elide: Text.ElideRight; Layout.fillWidth: true }
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
                }

                // Debug-only developer toggle. Lives in the nav footer so it
                // never appears in Release builds. Drives `_showUnimplemented`
                // → filters the stub sections out of `sections`.
                Rectangle {
                    visible: root._debugBuild
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spXs
                    radius: Theme.radiusMd
                    color: Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                    implicitHeight: devToggleRow.implicitHeight + 12
                    RowLayout {
                        id: devToggleRow
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spLg
                        anchors.rightMargin: Theme.spMd
                        spacing: Theme.spMd
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: I18n.t("settings.debug.label")
                                color: Theme.warning
                                font.pixelSize: Theme.fsXs
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                            }
                            Text {
                                text: I18n.t("settings.debug.showUnimpl")
                                color: Theme.text
                                font.pixelSize: Theme.fsSm
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                        // Drawn like SwitchRow's switch: the stock Basic
                        // indicator ignored the theme (DES-20).
                        Switch {
                            id: devSwitch
                            checked: root._showUnimplemented
                            onToggled: root.set("developer", "showUnimplemented", checked)
                            Accessible.name: I18n.t("settings.debug.showUnimpl")
                            indicator: Rectangle {
                                implicitWidth: 36; implicitHeight: 20; radius: 10
                                x: devSwitch.leftPadding
                                y: (devSwitch.height - height) / 2
                                color: devSwitch.checked ? Theme.accent : Theme.panel3
                                border.color: devSwitch.checked ? Theme.accent : Theme.fieldBorder
                                border.width: 1
                                FocusRing { target: devSwitch; radius: 13 }
                                Rectangle {
                                    width: 14; height: 14; radius: 7
                                    color: Theme.knob
                                    border.color: Theme.fieldBorder
                                    border.width: 1
                                    y: 3
                                    x: devSwitch.checked ? 36 - width - 3 : 3
                                }
                            }
                        }
                    }
                }

                Text {
                    text: I18n.t("settings.footer.stable").arg(AppController.appVersion)
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsXs
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
                        anchors.leftMargin: Theme.sp3xl; anchors.rightMargin: Theme.sp3xl
                        spacing: Theme.sp2xs
                        Layout.alignment: Qt.AlignVCenter
                        Text {
                            text: I18n.t("settings.crumb").arg(root._activeMeta().title || "")
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                            Layout.topMargin: Theme.spXl
                        }
                        RowLayout {
                            spacing: Theme.spLg
                            IconImage {
                                source: root._activeMeta().icon || ""
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                sourceSize.width: 40
                                sourceSize.height: 40
                                color: Theme.text
                            }
                            Text {
                                text: root._activeMeta().title || ""
                                color: Theme.text
                                font.pixelSize: Theme.fsXl
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            text: root._activeMeta().sub || ""
                            color: Theme.textMuted
                            font.pixelSize: Theme.fsMd
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
                        // A reading width. With the right panel folded on
                        // Settings the pane can be 1300px wide, and a name
                        // field that long is harder to use, not easier.
                        width: Math.min(bodyScroll.width, 960)
                        spacing: Theme.sp2xl
                        // Padding via wrapper
                        Item { Layout.preferredHeight: 8 }

                        // ── Unimplemented banner ──
                        // Shows on top of stub sections so the user can tell
                        // the controls below are read-only stubs.
                        Rectangle {
                            visible: root._isUnimplemented(root.activeSection)
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.sp3xl
                            Layout.rightMargin: Theme.sp3xl
                            radius: Theme.radius
                            color: Theme.withAlpha(Theme.warning, 0.12)
                            border.color: Theme.warning
                            border.width: 1
                            implicitHeight: notImplCol.implicitHeight + 16
                            ColumnLayout {
                                id: notImplCol
                                anchors.fill: parent
                                anchors.margins: Theme.spXl
                                spacing: Theme.spXs
                                Text {
                                    text: I18n.t("settings.notImpl.title")
                                    color: Theme.warning
                                    font.pixelSize: Theme.fsSm
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1
                                }
                                Text {
                                    text: I18n.t("settings.notImpl.body")
                                    color: Theme.text
                                    font.pixelSize: Theme.fsSm
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
                            Layout.leftMargin: Theme.sp3xl
                            Layout.rightMargin: Theme.sp3xl
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
    // Quiet hours are stored as HH:mm, which is all the C++ side parses.
    readonly property var _hhmmRe: /^([01]?[0-9]|2[0-3]):[0-5][0-9]$/
    function _hhmm(t) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(String(t).trim());
        return m ? m[1].padStart(2, "0") + ":" + m[2] : t;
    }

    // ── Settings search + keyboard nav ─────────────────────────────────
    function _sectionMatches(sec) {
        const q = root.searchText.toLowerCase().trim();
        if (q.length === 0) return true;
        return sec.title.toLowerCase().indexOf(q) >= 0 || sec.sub.toLowerCase().indexOf(q) >= 0;
    }
    function _openFirstMatch() {
        for (let i = 0; i < sections.length; i++) {
            if (_sectionMatches(sections[i])) {
                activeSection = sections[i].id;
                return true;
            }
        }
        return false;
    }
    // Focus the nav row at `from`, skipping rows the search hides in the
    // direction `dir` (1 down, -1 up).
    function _focusNav(from, dir) {
        const step = dir === -1 ? -1 : 1;
        for (let i = from; i >= 0 && i < navRep.count; i += step) {
            const it = navRep.itemAt(i);
            if (it && it.visible) {
                it.forceActiveFocus(Qt.TabFocusReason);
                return;
            }
        }
    }

    // Deep link from the command palette ("Settings: Appearance").
    function openSection(id) {
        for (let i = 0; i < sections.length; i++) {
            if (sections[i].id === id) {
                activeSection = id;
                return true;
            }
        }
        return false;
    }

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
        radius: Theme.radiusLg
        color: Theme.panel
        border.color: Theme.border; border.width: 1
        default property alias content: inner.data
        implicitHeight: inner.implicitHeight + 32
        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: Theme.sp2xl
            spacing: Theme.spXl
        }
    }

    // Themed ComboBox. Basic's stock one draws an up/down spinner glyph and a
    // flat grey slab that matches nothing else in Settings.
    component SettingsCombo: ComboBox {
        id: sc
        implicitHeight: 30
        font.pixelSize: Theme.fsMd
        background: Rectangle {
            radius: Theme.radiusMd
            color: sc.hovered || sc.popup.visible ? Theme.panel3 : Theme.panel2
            border.width: 1
            border.color: sc.activeFocus || sc.popup.visible ? Theme.accent : Theme.border
        }
        contentItem: Text {
            leftPadding: Theme.spLg
            rightPadding: sc.indicator.width + 6
            text: sc.displayText
            font: sc.font
            color: sc.currentIndex === 0 ? Theme.textMuted : Theme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: Text {
            x: sc.width - width - 10
            y: (sc.height - height) / 2
            text: "\u25BE"
            color: Theme.textDim
            font.pixelSize: Theme.fsMd
        }
        delegate: ItemDelegate {
            id: scRow
            required property var modelData
            required property int index
            width: sc.width - 8
            height: 28
            highlighted: sc.highlightedIndex === scRow.index
            contentItem: Text {
                text: scRow.modelData[sc.textRole]
                color: sc.currentIndex === scRow.index ? Theme.accentStrong : Theme.text
                font.pixelSize: Theme.fsMd
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: Theme.radiusSm
                color: scRow.highlighted ? Theme.panel3 : "transparent"
            }
        }
        popup: Popup {
            y: sc.height + 2
            width: sc.width
            padding: Theme.spXs
            implicitHeight: Math.min(contentItem.implicitHeight + 8, 320)
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: sc.popup.visible ? sc.delegateModel : null
                currentIndex: sc.highlightedIndex
            }
            background: Rectangle {
                radius: Theme.radius
                color: Theme.panel
                border.width: 1
                border.color: Theme.borderStrong
            }
        }
    }

    component Sub: Text {
        property string label: ""
        text: label
        color: Theme.textDim
        font.pixelSize: Theme.fsXs
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
        Layout.topMargin: Theme.spXs
    }

    component FieldLabel: ColumnLayout {
        property string label: ""
        property string hint: ""
        spacing: Theme.sp2xs
        Text { text: label.toUpperCase(); color: Theme.textMuted; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold; font.letterSpacing: 1 }
        Text { visible: hint.length > 0; text: hint; color: Theme.textDim; font.pixelSize: Theme.fsXs }
    }

    component TextRow: ColumnLayout {
        id: textRow
        property string label: ""
        property string hint: ""
        property string placeholder: ""
        property bool mono: false
        property bool secret: false
        // A password is masked even while focused — unlike a token, there is no
        // "check what I pasted" case that justifies revealing it.
        property bool alwaysMasked: false
        property string value: ""
        // Optional: text the field will not store. An edit that fails it is
        // put back to the stored value instead of being saved ("xyz" as a
        // quiet-hours time used to be).
        property alias validator: textRowField.validator
        // A time of day: only H:mm / HH:mm is accepted, and it is committed as
        // HH:mm — what the C++ side parses (SHELL-9, audit 2026-09-30).
        property bool clockTime: false
        readonly property RegularExpressionValidator _clockValidator: RegularExpressionValidator {
            regularExpression: /^([01]?[0-9]|2[0-3]):[0-5][0-9]$/
        }
        function _clock(t) {
            const m = /^(\d{1,2}):(\d{2})$/.exec(String(t).trim());
            return m ? m[1].padStart(2, "0") + ":" + m[2] : t;
        }
        readonly property bool invalid: textRowField.text.length > 0 && !textRowField.acceptableInput
        signal committed(string text)
        // What is typed right now, for fields that are never stored anywhere.
        function currentText() { return textRowField.text; }
        function clear() { textRowField.text = ""; }
        // The edit that has not been written yet, or null when the field is in
        // sync with the stored value.
        function pendingText() {
            return textRowField.text !== textRow.value ? textRowField.text : null;
        }
        // Flush a pending edit without waiting for focus loss. Buttons here are
        // MouseAreas, which never take focus, so clicking "Test connection"
        // straight after pasting a token would otherwise act on the old value.
        function commitPending() {
            const t = pendingText();
            if (t === null) return;
            if (textRowField.validator && !textRowField.acceptableInput) {
                textRowField.text = textRow.value;
                return;
            }
            textRow.committed(textRow.clockTime ? textRow._clock(t) : t);
        }
        spacing: Theme.spXs
        Layout.fillWidth: true
        FieldLabel { label: textRow.label; hint: textRow.hint }
        TextField {
            id: textRowField
            objectName: textRow.objectName.length > 0 ? textRow.objectName + "-field" : ""
            validator: textRow.clockTime ? textRow._clockValidator : null
            Layout.fillWidth: true
            placeholderText: textRow.placeholder
            placeholderTextColor: Theme.textDim
            color: Theme.text
            font.family: textRow.mono ? Theme.fontMono : Theme.fontUi
            // Secrets stay masked until focused, so a shoulder-surfer (or a
            // screenshot) never catches a token sitting in the panel.
            echoMode: (textRow.alwaysMasked || (textRow.secret && !activeFocus)) ? TextInput.Password : TextInput.Normal
            background: FieldFrame { border.color: textRow.invalid ? Theme.danger : (focused ? Theme.focusRing : Theme.fieldBorder) }
            selectByMouse: true
            // Re-sync from external value changes without breaking the user's
            // mid-edit text (no two-way binding → no loop, no per-keystroke
            // settings write).
            text: textRow.value
            onActiveFocusChanged: {
                if (!activeFocus) textRow.commitPending();
            }
            onAccepted: textRow.commitPending()
        }
    }

    component SwitchRow: RowLayout {
        id: switchRow
        property string label: ""
        property string hint: ""
        property bool checked: false
        signal toggled(bool checked)
        Layout.fillWidth: true
        spacing: Theme.spXl

        // The whole row toggles, not just the 36x20 switch — aiming at the
        // switch was the only way to flip a setting. Handlers rather than a
        // MouseArea because an Item child would become a layout cell.
        TapHandler { onTapped: switchRow.toggled(!switchRow.checked) }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        // Keyboard: Tab to the row, Space / Enter flips it.
        activeFocusOnTab: true
        Accessible.role: Accessible.CheckBox
        Accessible.name: switchRow.label
        Accessible.checked: switchRow.checked
        Keys.onSpacePressed: switchRow.toggled(!switchRow.checked)
        Keys.onReturnPressed: switchRow.toggled(!switchRow.checked)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: switchRow.label; color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Font.Medium }
            Text { visible: switchRow.hint.length > 0; text: switchRow.hint; color: Theme.textMuted; font.pixelSize: Theme.fsXs; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        Rectangle {
            Layout.preferredWidth: 36; Layout.preferredHeight: 20; radius: 10
            color: switchRow.checked ? Theme.accent : Theme.panel3
            // The OFF track had no edge on panel3 in the light themes, and
            // the knob was 1.2-2.3:1 on the accent track (DES-20).
            border.color: switchRow.checked ? Theme.accent : Theme.fieldBorder
            border.width: 1
            FocusRing { target: switchRow; radius: 13 }
            Rectangle {
                width: 14; height: 14; radius: 7
                color: Theme.knob
                border.color: Theme.fieldBorder
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                x: switchRow.checked ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: Theme.scaledMs(120) } }
            }
        }
    }

    component SegRow: ColumnLayout {
        id: segRow
        property string label: ""
        property string hint: ""
        property var options: []        // [{value,label}] or [string]
        property string value: ""
        signal selected(string value)
        spacing: Theme.spXs
        Layout.fillWidth: true
        function _valueAt(i) {
            const o = segRow.options[i];
            return typeof o === "string" ? o : o.value;
        }
        // ←/→ pick the neighbouring option, like a radio group.
        function _step(dir) {
            const n = segRow.options.length;
            if (n === 0) return;
            let cur = 0;
            for (let i = 0; i < n; i++) if (segRow._valueAt(i) === segRow.value) cur = i;
            segRow.selected(segRow._valueAt(Math.max(0, Math.min(n - 1, cur + dir))));
        }
        FieldLabel { label: parent.label; hint: parent.hint }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: Theme.radiusMd
            color: Theme.panel2
            border.color: Theme.border; border.width: 1
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: segRow.label
            Keys.onLeftPressed: segRow._step(-1)
            Keys.onRightPressed: segRow._step(1)
            FocusRing {}
            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.sp2xs
                spacing: 0
                Repeater {
                    model: parent.parent.parent.options
                    delegate: Rectangle {
                        required property var modelData
                        readonly property string v: typeof modelData === "string" ? modelData : modelData.value
                        readonly property string l: typeof modelData === "string" ? modelData : modelData.label
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSm
                        color: v === parent.parent.parent.value ? Theme.accent
                             : segMA.containsMouse ? Theme.panel3 : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: parent.l
                            color: parent.v === parent.parent.parent.parent.value ? Theme.textOnAccent : Theme.text
                            font.pixelSize: Theme.fsSm
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
        spacing: Theme.spXs
        Layout.fillWidth: true
        RowLayout {
            Layout.fillWidth: true
            Text { text: parent.parent.label.toUpperCase(); color: Theme.textMuted; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold; font.letterSpacing: 1 }
            Item { Layout.fillWidth: true }
            Text { text: Math.round(parent.parent.value) + parent.parent.unit; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: Theme.fsSm }
        }
        Text { visible: parent.hint.length > 0; text: parent.hint; color: Theme.textDim; font.pixelSize: Theme.fsXs }
        Slider {
            id: sliderCtl
            Layout.fillWidth: true
            from: parent.min; to: parent.max; stepSize: parent.step
            value: parent.value
            onMoved: parent.moved(value)
            // Tab reaches it and ←/→ move it (Slider's own keys); the handle
            // shows the focus ring while it has the keyboard.
            focusPolicy: Qt.StrongFocus
            Accessible.name: parent.label
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
                color: Theme.knob
                border.color: sliderCtl.activeFocus ? Theme.focusRing : Theme.border
                border.width: sliderCtl.activeFocus ? 2 : 1
            }
        }
    }

    component SwatchRow: ColumnLayout {
        id: swRoot
        property string label: ""
        property string value: ""
        property var options: []
        signal selected(string color)
        spacing: Theme.spXs
        Layout.fillWidth: true
        FieldLabel { label: swRoot.label }
        Row {
            spacing: Theme.spSm
            Repeater {
                model: swRoot.options
                delegate: Rectangle {
                    required property string modelData
                    width: 26; height: 26; radius: 13
                    color: modelData
                    border.color: String(swRoot.value).toLowerCase() === modelData.toLowerCase() ? Theme.text : "transparent"
                    border.width: 2
                    activeFocusOnTab: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData
                    Accessible.checked: String(swRoot.value).toLowerCase() === modelData.toLowerCase()
                    Keys.onSpacePressed: swRoot.selected(modelData)
                    Keys.onReturnPressed: swRoot.selected(modelData)
                    FocusRing {}
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: swRoot.selected(modelData) }
                }
            }
        }
    }

    component DangerRow: RowLayout {
        id: dangerRow
        property string title: ""
        property string hint: ""
        property string buttonText: ""
        // Two-step, like the other destructive rows: the first click arms,
        // the second commits, and it disarms by itself.
        property string confirmText: I18n.t("settings.data.wipe.confirm")
        property bool armed: false
        signal triggered()
        Layout.fillWidth: true
        spacing: Theme.spXl
        Timer { id: dangerDisarm; interval: 3500; onTriggered: dangerRow.armed = false }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: parent.parent.title; color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Font.Medium }
            Text { text: parent.parent.hint; color: Theme.textMuted; font.pixelSize: Theme.fsXs; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }
        Rectangle {
            radius: Theme.radiusMd
            color: dangerRow.armed ? Theme.danger
                 : (dangerMA.containsMouse ? Theme.withAlpha(Theme.danger, 0.20) : Theme.withAlpha(Theme.danger, 0.10))
            border.color: Theme.danger; border.width: 1
            implicitWidth: dangerTxt.implicitWidth + 24
            implicitHeight: 28
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: dangerTxt.text
            Keys.onSpacePressed: dangerMA.press()
            Keys.onReturnPressed: dangerMA.press()
            FocusRing {}
            Text {
                id: dangerTxt; anchors.centerIn: parent
                text: dangerRow.armed ? dangerRow.confirmText : dangerRow.buttonText
                color: dangerRow.armed ? Theme.textOnDanger : Theme.danger; font.pixelSize: Theme.fsMd; font.weight: Font.Medium
            }
            MouseArea {
                id: dangerMA; objectName: "danger-row-button"
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                function press() {
                    if (!dangerRow.armed) { dangerRow.armed = true; dangerDisarm.restart(); return; }
                    dangerRow.armed = false; dangerDisarm.stop(); dangerRow.triggered();
                }
                onClicked: press()
            }
        }
    }

    // ── Section components ────────────────────────────────────────────

    Component {
        id: sectionProfile
        ColumnLayout {
            spacing: Theme.sp2xl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.sp2xl
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
                                color: Theme.textOnAccent
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsXl
                                font.weight: Font.DemiBold
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spLg
                            TextRow {
                                label: I18n.t("settings.profile.fullName")
                                value: (root.settings.profile && root.settings.profile.name) || ""
                                onCommitted: (text) => root.set("profile", "name", text)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spLg
                                TextRow {
                                    Layout.fillWidth: true
                                    label: I18n.t("settings.profile.handle"); mono: true; placeholder: I18n.t("settings.profile.handle.ph")
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
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spLg
                        TextRow {
                            Layout.fillWidth: true
                            label: I18n.t("settings.profile.team")
                            value: (root.settings.profile && root.settings.profile.team) || ""
                            onCommitted: (text) => root.set("profile", "team", text)
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
            spacing: Theme.sp2xl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
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
                        options: [ ({ value: "compact", label: I18n.t("common.density.compact") }),
                                   ({ value: "comfy",   label: I18n.t("common.density.comfy") }) ]
                        onSelected: (value) => AppController.density = value
                    }
                }
            }
            SectionCard {
                objectName: "settings-theme-card"
                ThemeSettings {
                    Layout.fillWidth: true
                    appearance: root.settings.appearance || ({})
                    onSetKey: (key, value) => root.set("appearance", key, value)
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    SwitchRow {
                        label: I18n.t("settings.appearance.reducedMotion")
                        hint: I18n.t("settings.appearance.reducedMotion.hint")
                        checked: !!(root.settings.appearance && root.settings.appearance.reducedMotion)
                        onToggled: (checked) => root.set("appearance", "reducedMotion", checked)
                    }
                    // Soft: hairline borders, closer panels, muted colour —
                    // over whichever theme is showing. highContrast is kept
                    // in step for profiles that only know the old switch.
                    SegRow {
                        objectName: "settings-contrast"
                        label: I18n.t("settings.appearance.contrast")
                        hint: I18n.t("settings.appearance.contrast.hint")
                        value: Theme.contrast
                        options: [
                            ({ value: "soft",   label: I18n.t("settings.appearance.contrast.soft") }),
                            ({ value: "normal", label: I18n.t("settings.appearance.contrast.normal") }),
                            ({ value: "high",   label: I18n.t("settings.appearance.contrast.high") })
                        ]
                        onSelected: (value) => {
                            root.set("appearance", "contrast", value);
                            root.set("appearance", "highContrast", value === "high");
                        }
                    }
                    // Only where there is a tray to close into. Three states,
                    // because there are three: a switch showed ON while the
                    // choice was still unset, and the next close asked anyway.
                    SegRow {
                        objectName: "settings-close-to-tray"
                        visible: Qt.platform.os === "windows" || Qt.platform.os === "osx"
                        label: I18n.t("settings.system.closeToTray")
                        hint: I18n.t("settings.system.closeToTray.hint")
                        readonly property var _pref: root.settings.system ? root.settings.system.closeToTray : undefined
                        value: _pref === true ? "tray" : _pref === false ? "quit" : "ask"
                        options: [ ({ value: "ask",  label: I18n.t("settings.system.closeToTray.ask") }),
                                   ({ value: "tray", label: I18n.t("settings.system.closeToTray.tray") }),
                                   ({ value: "quit", label: I18n.t("settings.system.closeToTray.quit") }) ]
                        // "ask" drops the key: unset is what makes the next close ask.
                        onSelected: (v) => root.set("system", "closeToTray", v === "ask" ? undefined : v === "tray")
                    }
                    // Start at login (APP-154). The OS entry is the truth, read
                    // when this section opens: removed by hand, it shows off.
                    SwitchRow {
                        id: startAtLoginRow
                        objectName: "settings-start-at-login"
                        property var _os: AppController.autostartState()
                        visible: !!_os.supported
                        label: I18n.t("settings.system.startAtLogin")
                        hint: I18n.t("settings.system.startAtLogin.hint")
                        checked: !!_os.enabled
                        onToggled: (checked) => {
                            AppController.setAutostart(checked, !!startAtLoginRow._os.minimized);
                            startAtLoginRow._os = AppController.autostartState();
                        }
                    }
                    SwitchRow {
                        objectName: "settings-start-minimized"
                        visible: !!startAtLoginRow._os.supported && !!startAtLoginRow._os.enabled
                        label: I18n.t("settings.system.startMinimized")
                        hint: I18n.t("settings.system.startMinimized.hint")
                        checked: !!startAtLoginRow._os.minimized
                        onToggled: (checked) => {
                            AppController.setAutostart(!!startAtLoginRow._os.enabled, checked);
                            startAtLoginRow._os = AppController.autostartState();
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sectionLanguage
        ColumnLayout {
            spacing: Theme.sp2xl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
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
                        font.pixelSize: Theme.fsSm
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
            spacing: Theme.sp2xl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
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
                        unit: I18n.t("common.hours"); min: 1; max: 72; step: 1
                        value: _num(root.settings.notifications && root.settings.notifications.deadlineLeadHours, 24)
                        onMoved: (value) => root.set("notifications", "deadlineLeadHours", value)
                    }
                    SwitchRow {
                        label: I18n.t("settings.notif.meetingReminders")
                        hint: I18n.t("settings.notif.meetingReminders.hint")
                        checked: !!(root.settings.notifications && root.settings.notifications.meetingReminders)
                        onToggled: (checked) => root.set("notifications", "meetingReminders", checked)
                    }
                    SwitchRow {
                        label: I18n.t("settings.notif.standupReminder")
                        hint: I18n.t("settings.notif.standupReminder.hint")
                        checked: !!(root.settings.notifications && root.settings.notifications.standupReminder)
                        onToggled: (checked) => root.set("notifications", "standupReminder", checked)
                    }
                    SliderRow {
                        label: I18n.t("settings.notif.meetingLead")
                        unit: " " + I18n.t("common.minutes"); min: 0; max: 30; step: 1
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
                    spacing: Theme.spXl
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
                        label: I18n.t("settings.notif.blockedDigest")
                        checked: !!(root.settings.notifications && root.settings.notifications.blockedDailyDigest)
                        onToggled: (checked) => root.set("notifications", "blockedDailyDigest", checked)
                    }
                    // On unless switched off: the recap is the point of the
                    // feature, so an absent key means yes. Read and written
                    // through the controller; this view reloads on the change.
                    SwitchRow {
                        objectName: "settings-weekly-recap"
                        label: I18n.t("settings.notif.weeklyRecap")
                        hint: I18n.t("settings.notif.weeklyRecap.hint")
                        checked: {
                            try {
                                const n = (JSON.parse(AppController.appSettingsJson || "{}") || {}).notifications;
                                return !(n && n.weeklyRecap === false);
                            } catch (e) {
                                return true;
                            }
                        }
                        onToggled: (checked) => {
                            let s = {};
                            try { s = JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { s = {}; }
                            s.notifications = Object.assign({}, s.notifications || {}, { weeklyRecap: checked });
                            AppController.appSettingsJson = JSON.stringify(s);
                        }
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
                    spacing: Theme.spXl
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
                        Layout.fillWidth: true; spacing: Theme.spLg
                        visible: !!(root.settings.notifications && root.settings.notifications.quietHours)
                        TextRow {
                            Layout.fillWidth: true
                            label: I18n.t("common.from"); mono: true; placeholder: "19:00"
                            hint: invalid ? I18n.t("settings.notif.quiet.invalid") : ""
                            validator: RegularExpressionValidator { regularExpression: root._hhmmRe }
                            value: (root.settings.notifications && root.settings.notifications.quietFrom) || ""
                            onCommitted: (text) => root.set("notifications", "quietFrom", root._hhmm(text))
                        }
                        TextRow {
                            Layout.fillWidth: true
                            label: I18n.t("common.to"); mono: true; placeholder: "09:00"
                            hint: invalid ? I18n.t("settings.notif.quiet.invalid") : ""
                            validator: RegularExpressionValidator { regularExpression: root._hhmmRe }
                            value: (root.settings.notifications && root.settings.notifications.quietTo) || ""
                            onCommitted: (text) => root.set("notifications", "quietTo", root._hhmm(text))
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sectionCalendar
        ColumnLayout {
            spacing: Theme.sp2xl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.spLg
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
                        Layout.fillWidth: true; spacing: Theme.spLg
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
                        value: String(_num(root.settings.calendar && root.settings.calendar.snapMinutes, 15))
                        options: [ ({ value: "5", label: "5 " + I18n.t("common.minutes") }), ({ value: "15", label: "15 " + I18n.t("common.minutes") }), ({ value: "30", label: "30 " + I18n.t("common.minutes") }) ]
                        onSelected: (value) => root.set("calendar", "snapMinutes", parseInt(value))
                    }
                    SwitchRow {
                        label: I18n.t("settings.cal.showWeekends")
                        checked: !!(root.settings.calendar && root.settings.calendar.showWeekends)
                        onToggled: (checked) => root.set("calendar", "showWeekends", checked)
                    }
                    // The days the standup reminder fires and focus blocks
                    // are booked on. Qt weekday numbers, Mon=1 … Sun=7.
                    RowLayout {
                        id: workDaysRow
                        objectName: "settings-workdays"
                        Layout.fillWidth: true
                        spacing: Theme.spMd
                        readonly property var days: (root.settings.calendar && root.settings.calendar.workDays
                                                     && root.settings.calendar.workDays.length > 0)
                                                    ? root.settings.calendar.workDays : [1, 2, 3, 4, 5]
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("settings.cal.workDays")
                            color: Theme.text
                            font.pixelSize: Theme.fsMd
                        }
                        Repeater {
                            model: 7
                            delegate: Rectangle {
                                id: wdChip
                                required property int index
                                readonly property int day: wdChip.index + 1
                                readonly property bool on: workDaysRow.days.indexOf(wdChip.day) >= 0
                                implicitWidth: 34; implicitHeight: 24
                                radius: Theme.radiusMd
                                color: wdChip.on ? Theme.accentSoft : (wdMA.hovered ? Theme.panel3 : Theme.panel2)
                                border.color: wdChip.on ? Theme.accent : Theme.border
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: I18n.dayName(wdChip.day % 7)
                                    color: wdChip.on ? Theme.accentStrong : Theme.text
                                    font.pixelSize: Theme.fsXs
                                }
                                ClickArea {
                                    id: wdMA
                                    objectName: "settings-workday-" + wdChip.day
                                    label: I18n.t("settings.cal.workDays") + ": " + I18n.dayName(wdChip.day % 7)
                                    showTip: false
                                    role: Accessible.CheckBox
                                    checkable: true
                                    checked: wdChip.on
                                    onActivated: {
                                        const next = workDaysRow.days.slice();
                                        const i = next.indexOf(wdChip.day);
                                        if (i >= 0) next.splice(i, 1); else next.push(wdChip.day);
                                        next.sort();
                                        // At least one working day: none would silence
                                        // the standup and focus blocks for good.
                                        if (next.length > 0) root.set("calendar", "workDays", next);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
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
                        unit: " " + I18n.t("common.minutes"); min: 30; max: 240; step: 15
                        value: _num(root.settings.calendar && root.settings.calendar.focusBlockDuration, 90)
                        onMoved: (value) => root.set("calendar", "focusBlockDuration", value)
                    }
                    TextRow {
                        // Same rule as quiet hours: an invalid time is put back,
                        // "9:30" is stored as "09:30". It used to store "25:00"
                        // or "abc" and the standup reminder stopped (SHELL-9,
                        // audit 2026-09-30).
                        objectName: "standupTimeRow"
                        clockTime: true
                        label: I18n.t("settings.cal.standupTime"); mono: true; placeholder: "10:00"
                        hint: invalid ? I18n.t("settings.cal.standupTime.invalid") : ""
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
            spacing: Theme.sp2xl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.spLg
                        TextRow {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            label: I18n.t("settings.tasks.idPrefix"); mono: true; placeholder: "TASK"
                            hint: I18n.t("settings.tasks.idPrefix.hint").arg((root.settings.tasks && root.settings.tasks.idPrefix) || "TASK")
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
                            .arg(((root.settings.tasks && root.settings.tasks.idPrefix) || "TASK").toUpperCase())
                        checked: sectionTasksRoot.renameExistingOnCommit
                        onToggled: (checked) => sectionTasksRoot.renameExistingOnCommit = checked
                    }
                    SegRow {
                        label: I18n.t("settings.tasks.defaultColumn")
                        value: (root.settings.tasks && root.settings.tasks.defaultStatus) || "todo"
                        options: [ ({ value: "backlog", label: I18n.t("settings.tasks.col.backlog") }),
                                   ({ value: "todo",    label: I18n.t("settings.tasks.col.todo") }),
                                   ({ value: "prog",    label: I18n.t("settings.tasks.col.prog") }) ]
                        onSelected: (value) => root.set("tasks", "defaultStatus", value)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
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
                }
            }
        }
    }

    Component {
        id: sectionShortcuts
        ColumnLayout {
            spacing: Theme.spXl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spMd
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true
                        Sub {
                            label: I18n.t("settings.shortcuts.sub")
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            radius: Theme.radiusMd; implicitWidth: openTxt.implicitWidth + 18; implicitHeight: 26
                            color: openMA.hovered ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            Text {
                                id:
                                    openTxt; anchors.centerIn: parent; text: I18n.t("settings.shortcuts.open"); color: Theme.text; font.pixelSize: Theme.fsSm
                            }
                            ClickArea {
                                id: openMA
                                objectName: "settings-open-hotkeys"
                                label: I18n.t("settings.shortcuts.open")
                                tip: I18n.t("hotkeys.title")
                                shortcutId: "hotkeys.open"
                                onActivated: settingsBridge.openHotkeysRequested()
                            }
                        }
                    }
                    Text {
                        text: I18n.t("settings.shortcuts.intro")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spSm
                    Layout.fillWidth: true
                    Repeater {
                        model: AppController.shortcuts
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.spLg
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                Text { text: modelData.label; color: Theme.text; font.pixelSize: Theme.fsMd; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: modelData.description; color: Theme.textMuted; font.pixelSize: Theme.fsXs; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                            Rectangle {
                                radius: Theme.radiusSm
                                color: Theme.panel2
                                border.color: Theme.border; border.width: 1
                                implicitWidth: seqText.implicitWidth + 14; implicitHeight: 22
                                Text {
                                    id:
                                        seqText; anchors.centerIn: parent; text: modelData.sequence || I18n.t("settings.shortcuts.notSet"); color: modelData.sequence ? Theme.text : Theme.textDim; font.family: Theme.fontMono; font.pixelSize: Theme.fsSm
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
            spacing: Theme.sp2xl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.spLg
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
                        Layout.fillWidth: true; spacing: Theme.spLg
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
                    spacing: Theme.spXl
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
            spacing: Theme.spXl

            // Device-flow OAuth banner state (GitHub): the code the user types in
            // the browser. Set from AppController.oauthDeviceCode; empty = hidden.
            property string dcProvider: ""
            property string dcCode: ""
            property string dcUri: ""
            // Bumped on every keychain change. Secrets are read through a
            // Q_INVOKABLE (not a property), so the field bindings reference this
            // counter to re-read after the async keychain load and after writes.
            property int secretsRev: 0
            // Status-mapping rows are read through an invokable, not a property,
            // so a pick has to say it changed.
            property int statusMapRev: 0
            // A sign-in that landed but still needs a scope field: provider id
            // → the card labels that are empty. Cleared once they are filled.
            property var pendingFields: ({})
            // Bumped after every credential sign-in; the login fields bind to
            // it so a finished attempt never leaves a password on screen.
            property int loginRev: 0
            Connections {
                target: AppController
                function onOauthDeviceCode(provider, code, uri) {
                    intSection.dcProvider = provider
                    intSection.dcCode = code
                    intSection.dcUri = uri
                }
                function onIntegrationSecretsChanged() {
                    intSection.secretsRev++
                }
                function onIntegrationLoginFinished(provider, ok) {
                    intSection.loginRev++   // wipes whatever is in the password field
                }
                function onIntegrationNeedsFields(provider, labels) {
                    const next = Object.assign({}, intSection.pendingFields)
                    next[provider] = labels
                    intSection.pendingFields = next
                }
            }

            // Where the tokens are. Without a keychain they sit in a file in
            // the data folder, and a portable folder carries them with it.
            Text {
                objectName: "int-secrets-file-note"
                visible: !AppController.secretsInKeychain()
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: I18n.t(Qt.platform.os === "windows" ? "settings.integrations.secretsFileWin"
                                                          : "settings.integrations.secretsFile")
                color: Theme.warning
                font.pixelSize: Theme.fsSm
            }

            // What integrations do and do not do, before any of them.
            IntegrationsInfoCard {}
            // Outlook / Google / iCloud meetings by link (APP-118).
            CalendarSubscriptionsCard {}

            AutoSyncCard {}

            // One card per registered provider — the catalogue is the single
            // source of truth (AppController.integrationCatalog), so adding a
            // provider in C++ surfaces a card here with no QML change.
            Repeater {
                model: AppController.integrationCatalog()
                delegate: SectionCard {
                    required property var modelData
                    ColumnLayout {
                        id: intCard
                        objectName: "int-card-" + intCard.intKey
                        spacing: Theme.spLg
                        Layout.fillWidth: true
                        readonly property string intKey: modelData.id
                        // The status mapping folds away; which cards have it
                        // open is kept on the view, so it survives the card
                        // being rebuilt while Settings is open.
                        readonly property bool mapOpen: root._openStatusMaps[intKey] === true
                        readonly property var conf: (root.settings.integrations && root.settings.integrations[intKey]) || ({})
                        readonly property bool isConn: intCard.conf.connected === true
                        // Out of reach (token refresh got no answer) and cards
                        // a filter change left behind (audit INT-1/INT-5).
                        readonly property var liveState: AppController.integrationStates[intCard.intKey] || ({})
                        readonly property bool offline: !!intCard.liveState.offline
                        readonly property int outOfScope: intCard.liveState.outOfScope || 0
                        // Which actions are waiting on the provider, the last
                        // error it answered with and the last sync (DES-5).
                        readonly property var act: IntegrationActivity.states[intCard.intKey] || ({})
                        readonly property var busy: intCard.act.busy || ({})
                        readonly property string lastError: intCard.act.error || ""
                        function run(action) {
                            intCard.commitFields()
                            IntegrationActivity.start(intCard.intKey, action)
                            if (action === "sync") AppController.syncProvider(intCard.intKey)
                            else if (action === "test") AppController.testIntegration(intCard.intKey)
                            else if (action === "oauth") AppController.connectOAuth(intCard.intKey)
                        }
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
                        // "prog" is an id, not something to show a user.
                        function columnName(id) {
                            const list = AppController.statuses
                            for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i].name
                            return id
                        }
                        // Card labels the sign-in left empty (Asana workspace,
                        // Sentry org/project…), surfaced by AppController.
                        readonly property var missingFields: intSection.pendingFields[intCard.intKey] || []
                        // A card that needs a field is no use collapsed with the
                        // field hidden behind the Advanced disclosure.
                        onMissingFieldsChanged: if (intCard.missingFields.length > 0) { intCard.open = true; intCard.advanced = true }

                        // Flush every field that is still mid-edit. Every action
                        // below is a MouseArea, which never steals focus from the
                        // TextField, so without this a pasted token is still
                        // unsaved when "Connect"/"Test"/"Sync" fires.
                        function commitFields() {
                            // Read every pending edit before writing any of them.
                            // A write rebuilds the provider and re-evaluates the
                            // other fields' bindings, so reading field N's text
                            // after committing field 0 is reading it after
                            // something else may have moved it.
                            const pending = []
                            for (let i = 0; i < fieldsRep.count; ++i) {
                                const row = fieldsRep.itemAt(i)
                                if (!row || !row.pendingText) continue
                                const text = row.pendingText()
                                if (text !== null) pending.push({ row: row, text: text })
                            }
                            for (let i = 0; i < pending.length; ++i) {
                                pending[i].row.committed(pending[i].text)
                            }
                        }

                        // ── Header — click anywhere to expand / collapse ──
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: hdrRow.implicitHeight
                            RowLayout {
                                id: hdrRow
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spXl
                                Rectangle {
                                    id: intTile
                                    objectName: "int-card-tile"
                                    width: 32; height: 32; radius: Theme.radiusMd
                                    color: modelData.color
                                    readonly property string logo: root.providerLogos[modelData.id] || ""
                                    IconImage {
                                        visible: parent.logo !== ""
                                        anchors.centerIn: parent
                                        width: 18; height: 18
                                        sourceSize.width: 36; sourceSize.height: 36
                                        source: parent.logo !== "" ? "qrc:/brand/icons/" + parent.logo + ".svg" : ""
                                        // On the brand colour, not the accent:
                                        // textOnAccent was 2.8:1 on Jira red (DES-25).
                                        color: Theme.textOn(intTile.color)
                                    }
                                    // A provider without a drawn mark keeps
                                    // its catalogue glyph.
                                    Text {
                                        visible: parent.logo === ""
                                        anchors.centerIn: parent; text: modelData.icon; color: Theme.textOn(intTile.color); font.pixelSize: Theme.fsLg; font.weight: Font.DemiBold
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { id: intName; text: modelData.name; color: Theme.text; font.pixelSize: Theme.fsLg; font.weight: Font.DemiBold }
                                    Text { text: I18n.t(modelData.descKey); color: Theme.textMuted; font.pixelSize: Theme.fsMd; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                }
                                Text {
                                    objectName: "int-card-state"
                                    // Offline is still connected: heap keeps the
                                    // session and retries (audit INT-5).
                                    text: !intCard.isConn ? I18n.t("common.disconnected")
                                          : (intCard.offline ? I18n.t("settings.integrations.offline") : I18n.t("common.connected"))
                                    color: !intCard.isConn ? Theme.textDim : (intCard.offline ? Theme.warning : Theme.success)
                                    font.family: Theme.fontMono; font.pixelSize: Theme.fsSm
                                }
                                Text {
                                    text: intCard.open ? "▾" : "▸"   // ▾ / ▸
                                    color: Theme.textDim; font.pixelSize: Theme.fsMd
                                }
                            }
                            ClickArea {
                                objectName: "int-card-header"
                                label: intName.text
                                showTip: false
                                role: Accessible.CheckBox
                                checkable: true
                                checked: intCard.open
                                onActivated: intCard.open = !intCard.open
                            }
                        }

                        // ── Body (only when expanded) ──
                        ColumnLayout {
                            visible: intCard.open
                            Layout.fillWidth: true
                            Layout.leftMargin: 44
                            spacing: Theme.spMd

                            // How this card is signed in. A browser session
                            // expires, so say when — otherwise a card that had
                            // gone quiet looked identical to a working one.
                            Text {
                                visible: intCard.isConn && intCard.conf.authMode === "oauth"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Theme.textDim
                                font.pixelSize: Theme.fsXs
                                text: {
                                    // With a refresh token heap renews the
                                    // session itself; an expiry time then only
                                    // made a working card look about to break.
                                    if ((intSection.secretsRev, AppController.hasIntegrationSecret(intCard.intKey, "refreshToken")))
                                        return I18n.t("settings.integrations.signedInBrowserRenews");
                                    const raw = intCard.conf.tokenExpiresAt || "";
                                    if (raw.length === 0)
                                        return I18n.t("settings.integrations.signedInBrowser");
                                    const at = new Date(raw);
                                    if (isNaN(at.getTime()))
                                        return I18n.t("settings.integrations.signedInBrowser");
                                    return I18n.t("settings.integrations.signedInBrowserUntil")
                                        .replace("%1", AppController.humanDate(at) + " " + AppController.eventHourLabel(at.getHours()));
                                }
                            }

                            // A sign-in that still needs a scope field before it
                            // can sync anything.
                            Rectangle {
                                visible: intCard.missingFields.length > 0
                                Layout.fillWidth: true
                                radius: Theme.radiusMd
                                color: Theme.panel2
                                border.color: Theme.warning; border.width: 1
                                implicitHeight: missTxt.implicitHeight + 16
                                Text {
                                    id: missTxt
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Theme.spLg
                                    wrapMode: Text.WordWrap
                                    color: Theme.text; font.pixelSize: Theme.fsSm
                                    text: I18n.t("settings.integrations.needsFields").replace("%1", intCard.missingFields.join(", "))
                                }
                            }

                            // Offline: say what heap is doing about it.
                            Text {
                                objectName: "int-offline-hint"
                                visible: intCard.isConn && intCard.offline
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Theme.warning
                                font.pixelSize: Theme.fsXs
                                text: I18n.t("settings.integrations.offlineHint")
                            }

                            // Cards a filter change left behind: live issues this
                            // connection no longer pulls. Kept until the user
                            // says otherwise.
                            RowLayout {
                                objectName: "int-out-of-scope"
                                visible: intCard.outOfScope > 0
                                Layout.fillWidth: true
                                spacing: Theme.spMd
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fsSm
                                    text: I18n.t("settings.integrations.outOfScope").replace("%1", intCard.outOfScope)
                                }
                                PillButton {
                                    objectName: "int-archive-out-of-scope"
                                    text: I18n.t("settings.integrations.archiveOutOfScope")
                                    onClicked: AppController.archiveOutOfScope(intCard.intKey)
                                }
                            }

                            // Device-flow banner: show the code the user must
                            // enter in the browser (GitHub). Auto-clears on finish.
                            Rectangle {
                                visible: intSection.dcCode !== "" && intSection.dcProvider === intCard.intKey
                                Layout.fillWidth: true
                                radius: Theme.radiusMd
                                color: Theme.panel2
                                border.color: Theme.accent; border.width: 1
                                implicitHeight: dcCol.implicitHeight + 16
                                ColumnLayout {
                                    id: dcCol
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Theme.spLg
                                    spacing: Theme.spXs
                                    Text {
                                        text: I18n.t("settings.integrations.deviceCodePrompt")
                                        color: Theme.textMuted; font.pixelSize: Theme.fsSm
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    }
                                    TextEdit {
                                        text: intSection.dcCode
                                        readOnly: true; selectByMouse: true
                                        color: Theme.text; font.family: Theme.fontMono
                                        font.pixelSize: Theme.fsXl; font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: intSection.dcUri
                                        color: Theme.accentStrong; font.family: Theme.fontMono; font.pixelSize: Theme.fsXs
                                    }
                                }
                            }

                            // One-click browser connect: the primary action for
                            // OAuth providers. No fields to fill — credentials come
                            // from the app's registered OAuth app (or Advanced).
                            ActionButton {
                                objectName: "int-oauth-" + intCard.intKey
                                visible: intCard.canOneClick && !intCard.isConn
                                Layout.fillWidth: true
                                kind: "primary"
                                implicitHeight: 34
                                text: I18n.t("settings.integrations.browserSignIn")
                                busy: !!intCard.busy.oauth
                                busyText: I18n.t("settings.integrations.waitingBrowser")
                                onActivated: intCard.run("oauth")
                            }
                            Text {
                                visible: intCard.canOneClick && !intCard.isConn
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: I18n.t("settings.integrations.connectBrowserHint")
                                color: Theme.textDim; font.pixelSize: Theme.fsXs
                            }
                            // The browser is not the only way in, and on a
                            // self-hosted instance it is not a way in at all —
                            // say so where the button is, not in the docs.
                            Text {
                                visible: intCard.canOneClick && !intCard.isConn && !intCard.advanced
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: I18n.t("settings.integrations.manualHint")
                                color: Theme.textDim; font.pixelSize: Theme.fsXs
                            }
                            // OAuth-capable but no client ID yet (self-hosted gitea/
                            // forgejo): tell the user to add one under Advanced.
                            Text {
                                visible: intCard.isOAuth && !intCard.canOneClick && !intCard.isConn
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: I18n.t("settings.integrations.oauthNeedsId")
                                color: Theme.textDim; font.pixelSize: Theme.fsXs
                            }

                            // Advanced disclosure — hides the credential/scope
                            // fields (token, repo, client ID…) so they don't clutter
                            // the default view. Shown for OAuth cards and connected
                            // cards; non-OAuth cards that aren't connected show the
                            // fields directly (a token is required to connect).
                            Text {
                                visible: intCard.canOneClick || intCard.isConn
                                text: (intCard.advanced ? "▾  " : "▸  ") + I18n.t("settings.integrations.advanced")
                                color: Theme.textMuted; font.pixelSize: Theme.fsSm
                                ClickArea {
                                    objectName: "int-card-advanced"
                                    label: I18n.t("settings.integrations.advanced")
                                    showTip: false
                                    role: Accessible.CheckBox
                                    checkable: true
                                    checked: intCard.advanced
                                    onActivated: intCard.advanced = !intCard.advanced
                                }
                            }

                            // Credential / scope fields. Secret fields (token/key)
                            // go to the OS keychain via setIntegrationSecret — never
                            // into state.json.
                            ColumnLayout {
                                visible: intCard.advanced || (!intCard.canOneClick && !intCard.isConn)
                                Layout.fillWidth: true
                                spacing: Theme.spSm
                                Repeater {
                                    id: fieldsRep
                                    model: modelData.fields
                                    delegate: TextRow {
                                        required property var modelData
                                        label: modelData.label
                                        placeholder: modelData.placeholder
                                        mono: !!modelData.mono
                                        secret: !!modelData.secret
                                        value: modelData.secret
                                               ? (intSection.secretsRev, AppController.integrationSecret(intCard.intKey, modelData.key))
                                               : ((intCard.conf && intCard.conf[modelData.key]) || "")
                                        onCommitted: (txt) => modelData.secret
                                            ? AppController.setIntegrationSecret(intCard.intKey, modelData.key, txt)
                                            : root.setNested("integrations", intCard.intKey, modelData.key, txt)
                                    }
                                }
                            }

                            // Status mapping. StatusMap has always accepted
                            // per-user overrides and never been given any, so a
                            // status its built-in table does not recognise —
                            // "QA", "Needs triage", anything from a custom Jira
                            // workflow — landed in To Do with no way to say
                            // otherwise. The rows are the statuses this provider
                            // has actually sent, learned during sync.
                            ColumnLayout {
                                id: statusMapBlock
                                Layout.fillWidth: true
                                Layout.topMargin: Theme.spXs
                                spacing: Theme.spSm
                                visible: intCard.isConn && !modelData.directory === true && statusMapRep.count > 0

                                // Folded by default: once a tracker's statuses
                                // land where they should, the rows are only in
                                // the way. The closed header says how many there
                                // are and how many the user has set.
                                Item {
                                    objectName: "status-map-toggle"
                                    Layout.fillWidth: true
                                    implicitHeight: mapHead.implicitHeight + Theme.spXs
                                    RowLayout {
                                        id: mapHead
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spMd
                                        Text {
                                            text: (intCard.mapOpen ? "▾  " : "▸  ") + I18n.t("settings.integrations.statusMap")
                                            color: mapToggleMA.hovered ? Theme.accentStrong : Theme.text
                                            font.pixelSize: Theme.fsMd
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            visible: !intCard.mapOpen
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: {
                                                const rows = statusMapRep.model || [];
                                                let own = 0;
                                                for (let i = 0; i < rows.length; i++) if (rows[i].overridden) own++;
                                                return I18n.t("settings.integrations.statusMapSummary").arg(rows.length).arg(own);
                                            }
                                            color: Theme.textDim
                                            font.pixelSize: Theme.fsSm
                                        }
                                        Item { Layout.fillWidth: true; visible: intCard.mapOpen }
                                    }
                                    ClickArea {
                                        id: mapToggleMA
                                        objectName: "status-map-toggle-area"
                                        label: I18n.t("settings.integrations.statusMap")
                                        showTip: false
                                        role: Accessible.CheckBox
                                        checkable: true
                                        checked: intCard.mapOpen
                                        onActivated: root.toggleStatusMap(intCard.intKey)
                                    }
                                }
                                Text {
                                    visible: intCard.mapOpen
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: I18n.t("settings.integrations.statusMapHint")
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fsMd
                                }

                                Repeater {
                                    id: statusMapRep
                                    model: (intSection.statusMapRev, AppController.statusMappingFor(intCard.intKey))
                                    delegate: RowLayout {
                                        id: mapRow
                                        required property var modelData
                                        visible: intCard.mapOpen
                                        Layout.fillWidth: true
                                        spacing: Theme.spLg

                                        // Every cell fills up to a cap rather
                                        // than sitting at a fixed width: fixed
                                        // widths are also minimums in a
                                        // RowLayout, and together they made
                                        // the row wider than a narrow card.
                                        // The caps keep the combos aligned.
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 140
                                            Layout.maximumWidth: 140
                                            Layout.minimumWidth: Math.min(implicitWidth, 140)
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                            text: mapRow.modelData.status
                                            color: Theme.text
                                            font.pixelSize: Theme.fsMd
                                        }
                                        Text {
                                            text: "→"
                                            color: Theme.textDim
                                            font.pixelSize: Theme.fsMd
                                        }
                                        // Capped: stretched across the card,
                                        // the combo pushed its "auto" hint to
                                        // the far edge of the screen.
                                        SettingsCombo {
                                            id: columnPick
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 220
                                            Layout.maximumWidth: 220
                                            Layout.minimumWidth: 110
                                            // "Auto" first, so clearing a choice
                                            // is a pick rather than a hidden
                                            // gesture. Its value is the empty
                                            // string, which removes the override.
                                            objectName: "status-map-combo"
                                            readonly property var options: [{ id: "", name: I18n.t("settings.integrations.statusMapAuto") }].concat(AppController.statuses)
                                            model: options
                                            textRole: "name"
                                            valueRole: "id"
                                            // Looked up in the array this binding
                                            // owns. indexOfValue() ran before the
                                            // combo had its model, answered -1,
                                            // and was never asked again, so every
                                            // row read "Auto".
                                            currentIndex: {
                                                if (!mapRow.modelData.overridden) return 0;
                                                for (let i = 1; i < options.length; i++)
                                                    if (options[i].id === mapRow.modelData.column) return i;
                                                return 0;
                                            }
                                            onActivated: {
                                                AppController.setStatusMapping(intCard.intKey, mapRow.modelData.status, currentValue)
                                                intSection.statusMapRev++
                                            }
                                        }
                                        // What the built-in table guessed, shown
                                        // only while the user has not decided —
                                        // once they have, the combo says it.
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 130
                                            Layout.maximumWidth: 130
                                            Layout.minimumWidth: 0
                                            // Faded rather than removed, so the
                                            // row keeps its layout either way.
                                            opacity: mapRow.modelData.overridden ? 0 : 1
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                            text: I18n.t("settings.integrations.statusMapGuess").arg(intCard.columnName(mapRow.modelData.column))
                                            color: Theme.textDim
                                            font.pixelSize: Theme.fsMd
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                            }

                            // Password sign-in (Mattermost). Deliberately a
                            // separate Repeater from the credential fields
                            // below: those commit through setIntegrationSecret,
                            // and a password must never reach the keychain.
                            ColumnLayout {
                                id: loginBlock
                                visible: (modelData.loginFields || []).length > 0 && !intCard.isConn
                                Layout.fillWidth: true
                                spacing: Theme.spSm
                                function credentials() {
                                    const out = ({})
                                    for (let i = 0; i < loginRep.count; ++i) {
                                        const row = loginRep.itemAt(i)
                                        if (row && row.fieldKey) out[row.fieldKey] = row.currentText()
                                    }
                                    return out
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: I18n.t("settings.integrations.passwordSignInHint")
                                    color: Theme.textDim; font.pixelSize: Theme.fsXs
                                }
                                Repeater {
                                    id: loginRep
                                    model: modelData.loginFields
                                    delegate: TextRow {
                                        required property var modelData
                                        readonly property string fieldKey: modelData.key
                                        label: modelData.label
                                        placeholder: modelData.placeholder
                                        mono: !!modelData.mono
                                        secret: !!modelData.secret
                                        alwaysMasked: !!modelData.secret
                                        // Never bound to a stored value — these
                                        // are not persisted anywhere. The rev
                                        // counter empties them after a sign-in.
                                        value: (intSection.loginRev, "")
                                    }
                                }
                                ActionButton {
                                    objectName: "int-signin-" + intCard.intKey
                                    Layout.fillWidth: true
                                    kind: "primary"
                                    text: I18n.t("settings.integrations.signIn")
                                    busy: !!intCard.busy.signin
                                    busyText: I18n.t("settings.integrations.signingIn")
                                    onActivated: {
                                        intCard.commitFields()   // the host URL, not the password
                                        IntegrationActivity.start(intCard.intKey, "signin")
                                        AppController.connectWithCredentials(intCard.intKey, loginBlock.credentials())
                                    }
                                }
                            }

                            // What the last attempt said and when the last sync
                            // came back. The toast is gone in a few seconds;
                            // this stays until the next success (DES-5).
                            Text {
                                objectName: "int-last-error-" + intCard.intKey
                                visible: intCard.lastError.length > 0
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Theme.danger
                                font.pixelSize: Theme.fsSm
                                text: intCard.lastError.length > 0 && intCard.act.errorAt
                                      ? I18n.t("settings.integrations.lastError").replace("%1", AppController.eventHourLabel(intCard.act.errorAt.getHours() + intCard.act.errorAt.getMinutes() / 60)).replace("%2", intCard.lastError)
                                      : intCard.lastError
                            }
                            Text {
                                objectName: "int-last-sync-" + intCard.intKey
                                visible: intCard.isConn && !!intCard.act.syncedAt
                                Layout.fillWidth: true
                                color: Theme.textDim
                                font.pixelSize: Theme.fsXs
                                text: intCard.act.syncedAt ? I18n.t("settings.integrations.lastSync").replace("%1", AppController.eventHourLabel(intCard.act.syncedAt.getHours() + intCard.act.syncedAt.getMinutes() / 60)) : ""
                            }

                            // Actions: manual connect (non-OAuth) / test / sync / disconnect.
                            // ActionButtons: on the Tab path, named, run on
                            // Return / Space (DES-8), busy while the provider
                            // has not answered (DES-5).
                            RowLayout {
                                Layout.topMargin: Theme.sp2xs
                                spacing: Theme.spMd
                                // Connect with whatever is typed into the card.
                                // Offered whenever those fields are on screen —
                                // an OAuth card with Advanced open is a card
                                // being filled in by hand (a personal access
                                // token, a self-hosted Jira the Atlassian
                                // gateway has never heard of), and leaving it
                                // with only "Test connection" meant a card that
                                // tested green could never be connected.
                                ActionButton {
                                    objectName: "int-connect-" + intCard.intKey
                                    visible: !intCard.isConn && (!intCard.canOneClick || intCard.advanced)
                                    kind: "primary"
                                    text: I18n.t("common.connect")
                                    // Not a bare `connected = true`: the
                                    // controller checks the required fields
                                    // are filled and clears any leftover
                                    // browser session, so the typed
                                    // credentials are the ones that go out.
                                    onActivated: { intCard.commitFields(); AppController.connectIntegrationManually(intCard.intKey) }
                                }
                                ActionButton {
                                    objectName: "int-test-" + intCard.intKey
                                    visible: intCard.advanced || intCard.isConn || !intCard.canOneClick
                                    text: I18n.t("settings.integrations.testConnection")
                                    busy: !!intCard.busy.test
                                    busyText: I18n.t("settings.integrations.testing")
                                    onActivated: intCard.run("test")
                                }
                                ActionButton {
                                    objectName: "int-sync-" + intCard.intKey
                                    visible: intCard.isConn
                                    text: I18n.t("settings.integrations.syncNow")
                                    busy: !!intCard.busy.sync
                                    busyText: I18n.t("settings.integrations.syncing")
                                    onActivated: intCard.run("sync")
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    objectName: "int-disconnect-" + intCard.intKey
                                    visible: intCard.isConn
                                    kind: "quiet"
                                    text: I18n.t("common.disconnect")
                                    onActivated: {
                                        // A deliberate disconnect starts the card over.
                                        IntegrationActivity.clear(intCard.intKey)
                                        AppController.disconnectIntegration(intCard.intKey)
                                    }
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
            spacing: Theme.sp2xl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.git.repos")
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("settings.git.repos.hint")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("settings.git.match.hint")
                                .arg(((root.settings.tasks && root.settings.tasks.idPrefix) || "TASK").toUpperCase())
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: (root.settings.git && root.settings.git.watchedRepos) || []
                        delegate: RowLayout {
                            required property string modelData
                            required property int    index
                            Layout.fillWidth: true
                            spacing: Theme.spMd
                            Text {
                                Layout.fillWidth: true
                                text: modelData
                                elide: Text.ElideMiddle
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsSm
                            }
                            Rectangle {
                                radius: Theme.radiusSm
                                color: rmMA.hovered
                                    ? Theme.withAlpha(Theme.danger, 0.18)
                                    : "transparent"
                                border.color: Theme.danger; border.width: 1
                                implicitWidth: 22; implicitHeight: 22
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: Theme.danger
                                }
                                ClickArea {
                                    id: rmMA
                                    objectName: "settings-git-remove-repo"
                                    label: I18n.t("settings.git.removeRepo")
                                    onActivated: {
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
                        spacing: Theme.spMd
                        TextField {
                            id: newRepoField
                            Layout.fillWidth: true
                            placeholderText: "C:/path/to/repo"
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                            background: FieldFrame {}
                            selectByMouse: true
                        }
                        Rectangle {
                            radius: Theme.radiusMd
                            implicitHeight: 30
                            implicitWidth: addT.implicitWidth + 22
                            color: addMA.hovered ? Theme.accentHover : Theme.accent
                            opacity: addMA.enabled ? 1 : 0.45
                            Text {
                                id: addT
                                anchors.centerIn: parent
                                text: "+ " + I18n.t("common.add")
                                color: Theme.textOnAccent
                                font.weight: Font.Medium
                            }
                            ClickArea {
                                id: addMA
                                objectName: "settings-git-add-repo"
                                label: I18n.t("common.add")
                                showTip: false
                                enabled: newRepoField.text.trim().length > 0
                                onActivated: {
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
                    spacing: Theme.spXl
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
            spacing: Theme.sp2xl
            // Backups are read on demand (listBackups() is a plain invokable,
            // not a notifying property). The Data section is rebuilt whenever
            // the user opens it, so refreshing on completion keeps it current.
            property var backups: []
            function refreshBackups() { dataRoot.backups = AppController.listBackups(); }
            Component.onCompleted: dataRoot.refreshBackups()
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
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
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.data.restore")
                    }
                    Text {
                        visible: dataRoot.backups.length === 0
                        text: I18n.t("settings.data.restore.empty")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: dataRoot.backups
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.spXl
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text: modelData.mtime; color: Theme.text; font.pixelSize: Theme.fsMd; font.family: Theme.fontMono }
                                Text {
                                    text: modelData.fileName + "  ·  " + modelData.sizeKb + " KB"
                                    color: Theme.textMuted; font.pixelSize: Theme.fsXs; elide: Text.ElideRight; Layout.fillWidth: true
                                }
                            }
                            // Two-step confirm: first click arms (restore
                            // overwrites the live state), second within 3.5 s
                            // performs it. Auto-disarms so a stray click is safe.
                            ActionButton {
                                id: restoreBtn
                                objectName: "settings-restore-backup"
                                implicitHeight: 28
                                text: restoreBtn.armed ? I18n.t("settings.data.restore.confirm") : I18n.t("settings.data.restore.button")
                                Timer { id: restoreDisarm; interval: 3500; onTriggered: restoreBtn.armed = false }
                                onActivated: {
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
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.data.importExport")
                    }
                    Text {
                        text: I18n.t("settings.data.importExport.hint")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: Theme.spMd
                        ActionButton {
                            objectName: "settings-export-json"
                            text: I18n.t("settings.data.exportJson")
                            onActivated: settingsBridge.exportJsonRequested()
                        }
                        ActionButton {
                            objectName: "settings-import-json"
                            text: I18n.t("settings.data.importJson")
                            onActivated: settingsBridge.importJsonRequested()
                        }
                    }
                }
            }
            // Attached files nothing links any more. Counted when the section
            // opens and after a cleanup; deleting asks first (the button arms,
            // the second press deletes) and says how much it frees.
            SectionCard {
                objectName: "settings-attachments-cleanup"
                ColumnLayout {
                    id: attCleanup
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    property var unused: ({ count: 0, bytes: 0, sizeText: "" })
                    property bool armed: false
                    function refresh() { attCleanup.unused = AppController.unusedAttachments(); attCleanup.armed = false; }
                    Component.onCompleted: attCleanup.refresh()
                    Sub {
                        label: I18n.t("att.cleanup.title")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spXl
                        Text {
                            objectName: "att-cleanup-hint"
                            Layout.fillWidth: true
                            text: attCleanup.unused.count > 0
                                  ? I18n.t("att.cleanup.hint").arg(attCleanup.unused.count).arg(attCleanup.unused.sizeText)
                                  : I18n.t("att.cleanup.none")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fsSm
                            wrapMode: Text.WordWrap
                        }
                        PillButton {
                            objectName: "att-cleanup-button"
                            visible: attCleanup.unused.count > 0
                            danger: attCleanup.armed
                            text: attCleanup.armed ? I18n.t("att.cleanup.confirm").arg(attCleanup.unused.sizeText)
                                                   : I18n.t("att.cleanup.button")
                            onClicked: {
                                if (!attCleanup.armed) {
                                    attCleanup.armed = true;
                                    attCleanupDisarm.restart();
                                    return;
                                }
                                attCleanupDisarm.stop();
                                AppController.cleanUpUnusedAttachments();
                                attCleanup.refresh();
                            }
                            Timer { id: attCleanupDisarm; interval: 3500; onTriggered: attCleanup.armed = false }
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
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
                    // Full wipe → first-run. The most destructive thing in the
                    // app is confirmed in a dialog that says what goes (design
                    // audit DES-16); a second click within 3.5 s was all it took.
                    RowLayout {
                        id: wipeRow
                        Layout.fillWidth: true
                        spacing: Theme.spXl
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { text: I18n.t("settings.data.wipe"); color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Font.Medium }
                            Text { text: I18n.t("settings.data.wipe.hint"); color: Theme.textMuted; font.pixelSize: Theme.fsXs; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        ActionButton {
                            objectName: "settings-wipe"
                            kind: "danger"
                            implicitHeight: 28
                            text: I18n.t("settings.data.wipeButton")
                            onActivated: wipeDialog.open()
                            // "Delete all data?" — names what goes, and Cancel is where focus
                            // lands, so Return on an unread dialog keeps the data.
                            Popup {
                                id: wipeDialog
                                objectName: "settings-wipe-dialog"
                                modal: true
                                focus: true
                                parent: Overlay.overlay
                                anchors.centerIn: parent
                                width: Math.min(460, (parent ? parent.width : 460) - 2 * Theme.sp2xl)
                                padding: Theme.inset
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                Overlay.modal: Rectangle { color: Theme.scrim }
                                readonly property var profileNames: {
                                    const out = [];
                                    const ps = AppController.profiles || [];
                                    for (let i = 0; i < ps.length; i++) out.push(ps[i].name || ps[i].id);
                                    return out;
                                }
                                onOpened: wipeCancel.forceActiveFocus()
                                background: Rectangle {
                                    radius: Theme.radiusXl
                                    color: Theme.panel
                                    border.color: Theme.borderStrong
                                    border.width: 1
                                }
                                contentItem: ColumnLayout {
                                    spacing: Theme.spXl
                                    Text {
                                        text: I18n.t("settings.data.wipe.dialogTitle")
                                        color: Theme.text
                                        font.pixelSize: Theme.fsLg
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                    }
                                    Text {
                                        objectName: "settings-wipe-dialog-body"
                                        text: I18n.t("settings.data.wipe.dialogBody").arg(wipeDialog.profileNames.join(", "))
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fsMd
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spMd
                                        Item { Layout.fillWidth: true }
                                        PillButton {
                                            id: wipeCancel
                                            objectName: "settings-wipe-cancel"
                                            text: I18n.t("common.cancel")
                                            onClicked: wipeDialog.close()
                                        }
                                        PillButton {
                                            objectName: "settings-wipe-commit"
                                            text: I18n.t("settings.data.wipeButton")
                                            danger: true
                                            onClicked: { wipeDialog.close(); AppController.resetToFirstRun(); }
                                        }
                                    }
                                }
                            }
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
            spacing: Theme.sp2xl
            SectionCard {
                ColumnLayout {
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: Theme.spXl
                        BrandLogo {
                            variant: "mark"
                            theme: Theme.dark ? "dark" : "light"
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                        }
                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: "heap."; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: Theme.fsLg; font.weight: Font.DemiBold
                            }
                            Text {
                                text: Brand.tagline; color: Theme.textMuted; font.pixelSize: Theme.fsSm
                            }
                        }
                    }
                    ColumnLayout {
                        spacing: Theme.spSm
                        Layout.topMargin: Theme.spXs
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
                    spacing: Theme.spXl
                    Layout.fillWidth: true
                    Sub {
                        label: I18n.t("settings.about.diagnostics")
                    }
                    Text {
                        text: I18n.t("settings.about.diagnostics.hint")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: Theme.spMd
                        ActionButton {
                            objectName: "settings-report-issue"
                            text: I18n.t("settings.about.reportIssue")
                            onActivated: AppController.reportAnIssue()
                        }
                        ActionButton {
                            objectName: "settings-open-logs"
                            text: I18n.t("settings.about.openLogs")
                            onActivated: AppController.openLogsFolder()
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    id: updatesCol
                    property bool updateReady: false
                    spacing: Theme.spXl
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
                        font.pixelSize: Theme.fsSm
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    // Download progress (APP-125).
                    Rectangle {
                        objectName: "settings-update-progress"
                        visible: AppController.updatePhase === "downloading"
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.spSm
                        radius: height / 2
                        color: Theme.panel3
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, AppController.updateProgress))
                            height: parent.height
                            radius: parent.radius
                            color: Theme.accent
                        }
                    }
                    RowLayout {
                        spacing: Theme.spMd
                        ActionButton {
                            objectName: "settings-check-updates"
                            text: I18n.t("settings.about.checkUpdates")
                            enabled: AppController.updatePhase !== "downloading" && AppController.updatePhase !== "installing"
                            onActivated: AppController.checkForUpdates()
                        }
                        // Installs in place when heap can update this copy itself;
                        // otherwise opens the release page, as before.
                        ActionButton {
                            objectName: "settings-download-update"
                            visible: updatesCol.updateReady && AppController.updatePhase === ""
                                || AppController.updatePhase === "error"
                            hoverAccent: true
                            text: AppController.updateCanInstall ? I18n.t("settings.about.install") : I18n.t("settings.about.download")
                            onActivated: AppController.updateCanInstall ? AppController.downloadUpdate() : AppController.openLatestRelease()
                        }
                        ActionButton {
                            objectName: "settings-cancel-update"
                            visible: AppController.updatePhase === "downloading"
                            text: I18n.t("settings.about.cancelUpdate")
                            onActivated: AppController.cancelUpdateDownload()
                        }
                        ActionButton {
                            objectName: "settings-restart-update"
                            visible: AppController.updatePhase === "ready"
                            kind: "primary"
                            text: I18n.t("settings.about.restartToUpdate")
                            onActivated: AppController.installUpdate()
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
        spacing: Theme.sp2xl
        Text { text: aboutRow.label; color: Theme.textMuted; font.pixelSize: Theme.fsSm; Layout.preferredWidth: 80 }
        // Elided: the storage path is long enough to stretch the card past the
        // panel. The full value is on the tooltip.
        Text {
            text: aboutRow.value
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsSm
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            HoverHandler { id: aboutHover }
            ToolTip.visible: aboutHover.hovered && truncated
            ToolTip.delay: 400
            ToolTip.text: aboutRow.value
        }
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
