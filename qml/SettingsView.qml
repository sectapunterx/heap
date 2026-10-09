// Settings view — full per-profile / global configuration screen.
// Layout: left nav with 10 sections, right detail panel. New app-wide
// settings persist as JSON in AppController.appSettingsJson.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Controls.impl
import TodoCpp
import "SettingsIndex.js" as Idx

Item {
    id: root

    // ── Sections list (left nav) ──────────────────────────────────────
    // Full catalogue of settings sections.
    //   unimplemented: section is a stub. In Release builds these are hidden
    //                  completely. In Debug they obey the dev toggle in the
    //                  nav footer.
    readonly property var allSections: Idx.SECTIONS.map((s) => ({
        id: s.id,
        icon: s.icon,
        title: I18n.t("settings.section." + s.id + ".title"),
        sub: I18n.t("settings.section." + s.id + ".sub"),
        titleEn: I18n.dict.en["settings.section." + s.id + ".title"] || "",
        subEn: I18n.dict.en["settings.section." + s.id + ".sub"] || "",
        unimplemented: !!s.unimplemented
    }))

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

    property string activeSection: "appearance"

    // ── Page metrics (APP-172) ─────────────────────────────────────────
    // A reading column of `pageWidth` at most; Help's document keeps a
    // wider one for its table of contents. Groups sit further apart than
    // the rows inside them, so the eye finds a block first, then a row.
    readonly property int pageWidth: 720
    readonly property int pageMargin: bodyScroll.width < 760 ? Theme.sp3xl : Theme.sp3xl * 2
    readonly property int pageTop: Theme.sp3xl + Theme.spXl
    readonly property int pageBottom: Theme.sp3xl * 2
    readonly property int groupGap: Theme.sp3xl + Theme.spLg

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
    // Every setting a search can find (APP-207), shared with the Tweaks
    // panel: qml/SettingsIndex.js.
    readonly property var searchIndex: Idx.build(I18n, I18n.lang, AppController.integrationCatalog())
    readonly property var searchMatches: Idx.search(searchIndex, searchText)
    // section id → how many of its settings the search found.
    readonly property var searchCounts: Idx.counts(searchMatches)
    readonly property bool searching: Idx.norm(searchText).length > 0
    // Searching and no section left in the nav.
    readonly property bool searchEmpty: {
        if (!searching) return false;
        for (let i = 0; i < sections.length; i++)
            if (_sectionMatches(sections[i])) return false;
        return true;
    }

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
            fontUI: Brand.fontSans,
            fontMono: Brand.fontMono,
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
        // Off until switched on (APP-177); the volume is 0–100. The meeting
        // chimes (APP-178) ring at these minutes before, latest first.
        sound: { enabled: false, volume: 55, meetingChimes: true, meetingChimeMinutes: [15, 10, 5] },
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

        // Left nav. Grows with the interface scale (APP-183) and with the
        // longest section name (APP-189), up to a third more, or large text
        // and longer languages cut the names short.
        FontMetrics {
            id: navFont
            font.pixelSize: Theme.fsMd
            font.weight: Theme.fwTitle
        }
        Rectangle {
            readonly property real _widestTitle: {
                let w = 0;
                for (let i = 0; i < root.sections.length; i++)
                    w = Math.max(w, navFont.advanceWidth(String(root.sections[i].title)));
                return w;
            }
            // Outer margins, the row's margins, the icon and its gap, and a
            // little slack for rounding and glyphs from a fallback font.
            Layout.preferredWidth: Math.min(Theme.px(320), Math.max(Theme.px(240),
                Math.ceil(_widestTitle) + 2 * Theme.sp2xl + 3 * Theme.spXl + 16 + Theme.spLg))
            Layout.fillHeight: true
            color: Theme.bg
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.sp2xl
                spacing: Theme.spSm

                // One page with its contents on the left (APP-270, sheet
                // H2-Settings): the title, the search, the sections.
                Text {
                    objectName: "settings-title"
                    text: I18n.t("settings.title")
                    color: Theme.text
                    font.weight: Theme.fwHeading
                    font.pixelSize: Theme.fsXl
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(28)
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
                            ContextMenu.menu: TextEditMenu { editor: settingsSearch }
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
                            // Esc clears the search; on an empty box it
                            // goes on to whatever Esc does around it.
                            Keys.onEscapePressed: (event) => {
                                if (text.length > 0) {
                                    root.searchText = "";
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            }
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
                    objectName: "settings-nav-scroll"
                    // Thirteen groups do not fit at 125 % on a laptop: the
                    // thumb stays drawn and the cut edge fades (SCALE-2), where
                    // "Help" sat half under the footer and "About" was nowhere
                    // with nothing saying the list went on.
                    ScrollBar.vertical: ThinScrollBar { objectName: "settings-nav-scrollbar"; cue: true }
                    onHeightChanged: Qt.callLater(root._revealNavActive)

                    ColumnLayout {
                        id: navCol
                        width: navScroll.width
                        spacing: Theme.sp2xs + 1
                        Repeater {
                            id: navRep
                            model: root.sections
                            // One tab stop for the list (SHELL-11, see the delegate). Bound here:
                            // Qt 6.9's qmllint does not resolve root inside the delegate.
                            onItemAdded: (idx, item) => {
                                item.activeFocusOnTab = Qt.binding(() => item.activeFocus || idx === root._navTabIndex);
                                item.searchCount = Qt.binding(() => root.searching ? (root.searchCounts[item.modelData.id] || 0) : 0);
                            }
                            delegate: Rectangle {
                                id: navRow
                                required property var modelData
                                required property int index
                                objectName: "settings-nav-" + modelData.id
                                visible: root._sectionMatches(modelData)
                                // How many of its settings the search found
                                // (APP-207); navRep binds it.
                                property int searchCount: 0
                                // A list box: Tab lands on it, ↑/↓ move and open,
                                // Enter / Space open. One tab stop for the whole
                                // list (the open section's row): every row used
                                // to be one, focus opened its section, so Tab
                                // walked Profile → … → About and only ever
                                // entered About's body (SHELL-11). navRep binds
                                // activeFocusOnTab; its `activeFocus` term keeps a
                                // row that still holds focus a stop after a click
                                // opened another section.
                                Accessible.role: Accessible.PageTab
                                Accessible.name: modelData.title
                                Keys.onUpPressed: root._focusNav(index - 1, -1)
                                Keys.onDownPressed: root._focusNav(index + 1, 1)
                                Keys.onSpacePressed: root.activeSection = modelData.id
                                Keys.onReturnPressed: root.activeSection = modelData.id
                                onActiveFocusChanged: if (activeFocus) root.activeSection = modelData.id
                                FocusRing {}
                                Layout.fillWidth: true
                                // One line per section: the subtitle is the
                                // page's own heading now, and two lines of
                                // small print per row made the list a wall
                                // (APP-172). Search still matches it.
                                Layout.preferredHeight: Theme.px(36)
                                Layout.minimumHeight: Theme.px(36)
                                radius: Theme.radiusMd
                                // The section in view: its name bold with the
                                // short lavender underline (heap 2), no fill.
                                color: navMA.containsMouse ? Theme.panel2 : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                                    spacing: Theme.spXl
                                    Text {
                                        id: navTitle
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        color: Theme.text
                                        font.pixelSize: Theme.fsMd
                                        font.weight: root.activeSection === modelData.id ? Theme.fwHeading : Theme.fwBody
                                        elide: Text.ElideRight
                                        CursorBar {
                                            shown: root.activeSection === navRow.modelData.id
                                            anchors.left: parent.left
                                            anchors.top: parent.bottom
                                            anchors.topMargin: Theme.sp2xs
                                        }
                                    }
                                    // How many of the section's settings the
                                    // search found (APP-207).
                                    Text {
                                        objectName: "settings-nav-count-" + navRow.modelData.id
                                        visible: navRow.searchCount > 0
                                        text: String(navRow.searchCount)
                                        color: Theme.textDim
                                        font.family: Theme.fontUi
                                        font.features: Theme.tabularNums
                                        font.pixelSize: Theme.fsXs
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
                        // A search that leaves no section (APP-207).
                        EmptyState {
                            objectName: "settings-search-empty"
                            visible: root.searchEmpty
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.sp2xl
                            compact: true
                            title: I18n.t("settings.search.empty")
                            line: I18n.t("settings.search.emptyLine")
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
                                font.pixelSize: Theme.fsSm
                                font.weight: Theme.fwTitle
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
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsXs
                }
            }
        }

        // Main detail
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Section body — scrollable. The heading scrolls with it: a
            // fixed 76px bar on top of every page was one more band to read
            // past (APP-172).
            Flickable {
                id: bodyScroll
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: bodyCol.implicitHeight + root.pageBottom
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThinScrollBar {}

                NumberAnimation {
                    id: scrollAnim
                    target: bodyScroll
                    property: "contentY"
                    duration: Theme.durMove
                    easing.type: Theme.easeEnter
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
                        root._navScroll = false;
                        scrollAnim.from = bodyScroll.contentY;
                        scrollAnim.to = newY;
                        scrollAnim.restart();
                    }
                }
                onMovementStarted: root._navScroll = false
                onContentYChanged: if (!root._navScroll) root._spy()

                ColumnLayout {
                    id: bodyCol
                    // A reading column: lines stop at `pageWidth` however
                    // wide the window is, and the page keeps a generous
                    // margin from the nav (APP-172).
                    x: root.pageMargin
                    y: root.pageTop
                    width: Math.max(0, Math.min(bodyScroll.width - 2 * root.pageMargin, root.pageWidth))
                    spacing: 0

                    // Every section on one page (APP-270), in the order of
                    // SettingsIndex.SECTIONS (tst_SettingsPage checks): its
                    // heading, its line, its rows; the nav follows the scroll.
                    // Declared one by one, not by a Repeater: a delegate is no
                    // QObject child of the page, and the dialogs inside the
                    // sections could not be found from it.
                    PageBlock { sectionId: "appearance" }
                    PageBlock { sectionId: "calendar" }
                    PageBlock { sectionId: "tasks" }
                    PageBlock { sectionId: "notifications" }
                    PageBlock { sectionId: "safety" }
                    PageBlock { sectionId: "shortcuts" }
                    PageBlock { sectionId: "integrations" }
                    PageBlock { sectionId: "git" }
                    PageBlock { sectionId: "data" }
                    PageBlock { sectionId: "language" }
                    PageBlock { sectionId: "profile" }
                    PageBlock { sectionId: "help" }
                    PageBlock { sectionId: "about" }
                }
            }
        }
    }

    // The page of a section, by id.
    function _pageFor(id) {
        if (id === "profile")       return sectionProfile;
        if (id === "appearance")    return sectionAppearance;
        if (id === "language")      return sectionLanguage;
        if (id === "notifications") return sectionNotifications;
        if (id === "safety")        return sectionSafety;
        if (id === "calendar")      return sectionCalendar;
        if (id === "tasks")         return sectionTasks;
        if (id === "shortcuts")     return sectionShortcuts;
        if (id === "integrations")  return sectionIntegrations;
        if (id === "git")           return sectionGit;
        if (id === "data")          return sectionData;
        if (id === "help")          return sectionHelp;
        if (id === "about")         return sectionAbout;
        return null;
    }
    // The blocks of the page, in page order.
    function _blocks() {
        const out = [];
        for (let i = 0; i < bodyCol.children.length; i++) {
            const it = bodyCol.children[i];
            if (it && it.sectionId !== undefined) out.push(it);
        }
        return out;
    }
    // The block of a section on the page.
    function _blockFor(id) {
        const list = _blocks();
        for (let i = 0; i < list.length; i++)
            if (list[i].sectionId === id) return list[i];
        return null;
    }

    // ── Scroll spy ────────────────────────────────────────────────────
    // While the page moves under the reader, the nav marks the section at
    // the top of the view. A jump from the nav sets `_navScroll` so the
    // sections it passes on the way do not flicker through the nav, and the
    // last section, which cannot reach the top, stays the one picked.
    property bool _navScroll: false
    property bool _spying: false
    function _spy() {
        const top = bodyScroll.contentY + bodyScroll.height * 0.25;
        let pick = "";
        const list = _blocks();
        for (let i = 0; i < list.length; i++) {
            const it = list[i];
            if (!it.visible) continue;
            if (pick === "" || bodyCol.y + it.y <= top) pick = it.sectionId;
        }
        if (pick === "" || pick === activeSection) return;
        _spying = true;
        activeSection = pick;
        _spying = false;
    }
    onActiveSectionChanged: {
        Qt.callLater(root._revealNavActive);
        if (!_spying) _scrollToSection(activeSection);
    }
    // Bring a section's heading to the top, once the page has laid out.
    function _scrollToSection(id) {
        if (!_blockFor(id)) return;
        _navScroll = true;
        _reveal = { block: id, lastY: -1, steady: 0, ticks: 0 };
        revealSettle.restart();
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
    // A section stays in the nav when its own title or subtitle matches, in
    // either language, or when any of its settings does (APP-207).
    function _sectionMatches(sec) {
        const q = Idx.norm(root.searchText);
        if (q.length === 0) return true;
        return Idx.textMatches(q, sec.title, sec.titleEn) || Idx.textMatches(q, sec.sub, sec.subEn)
            || (root.searchCounts[sec.id] || 0) > 0;
    }
    // Enter in the search box: a section the query names opens at its top;
    // otherwise the first section left in the nav opens, and its first
    // matching setting scrolls into view with focus on it.
    function _openFirstMatch() {
        const q = Idx.norm(root.searchText);
        for (let i = 0; q.length > 0 && i < sections.length; i++) {
            if (Idx.textMatches(q, sections[i].title, sections[i].titleEn)) {
                activeSection = sections[i].id;
                return true;
            }
        }
        for (let i = 0; i < sections.length; i++) {
            if (!_sectionMatches(sections[i])) continue;
            const id = sections[i].id;
            for (let m = 0; m < searchMatches.length; m++) {
                if (searchMatches[m].section === id && revealItem(searchMatches[m]))
                    return true;
            }
            activeSection = id;
            return true;
        }
        return false;
    }

    // Open `item`'s section (an entry of searchIndex, or {section, key}),
    // then scroll to that setting and focus it once the page is built.
    function revealItem(item) {
        if (!item || !openSection(item.section)) return false;
        _navScroll = true;
        _reveal = { entry: _indexEntry(item), lastY: -1, steady: 0, ticks: 0 };
        revealSettle.restart();
        return true;
    }
    // The page a section opens on is laid out over the next frames: its
    // Layouts polish, text wraps, and contentHeight grows with them. A
    // scroll worked out before that lands short of the setting (on another
    // platform's fonts, by a lot). So the target is measured each frame and
    // the scroll redone until its position has stopped moving.
    property var _reveal: null
    Timer {
        id: revealSettle
        interval: 16
        repeat: true
        onTriggered: root._revealStep()
    }
    function _revealStep() {
        const r = _reveal;
        if (!r) { revealSettle.stop(); return; }
        r.ticks++;
        const target = r.block ? _blockFor(r.block) : _revealTarget(r.entry);
        if (!target) {
            if (r.ticks > 120) { _reveal = null; revealSettle.stop(); }
            return;
        }
        const y = _scrollYFor(target);
        if (y !== r.lastY) {
            r.lastY = y;
            r.steady = 0;
            _scrollToItem(target);
        } else {
            r.steady++;
        }
        // A few ticks with nothing moving (and not before the first frames
        // had a chance to polish), or stop waiting after two seconds.
        if ((r.ticks >= 10 && r.steady >= 3) || r.ticks > 120) {
            _reveal = null;
            revealSettle.stop();
            if (!r.block) _revealNow(r.entry);
        }
    }
    // The full index entry for a {section, key} or {section, id} pair.
    function _indexEntry(item) {
        for (let i = 0; i < searchIndex.length; i++) {
            const e = searchIndex[i];
            if (e.section !== item.section) continue;
            if ((item.id && e.id === item.id) || (!item.id && item.key && e.key === item.key))
                return e;
        }
        return item;
    }
    // The page item that shows `entry`: a SettingsRow by its label, a
    // SettingsGroup by its title, a card by its objectName or title text.
    function _findSettingItem(entry) {
        // Within its own section: the same words can name rows of two.
        const scope = _blockFor(entry.section) || bodyCol;
        if (entry.objectName && entry.objectName.length > 0)
            return _findChildByName(scope, entry.objectName);
        const text = entry.title || (entry.key ? I18n.t(entry.key) : "");
        if (!text) return null;
        let textHit = null;
        const walk = (it) => {
            const kids = it ? it.children : [];
            for (let i = 0; i < kids.length; i++) {
                const k = kids[i];
                if (!k) continue;
                if (_isRow(k) && k.label === text) return k;
                if (_isGroup(k) && k.title === text) return k;
                if (!textHit && k.text === text && k.visible) textHit = k;
                const sub = walk(k);
                if (sub) return sub;
            }
            return null;
        };
        return walk(scope) || textHit;
    }
    function _isRow(it) { return it.hasLabel !== undefined && it.stackBelow !== undefined; }
    function _isGroup(it) { return it.framed !== undefined && it.danger !== undefined && it.rows !== undefined; }

    function _revealTarget(entry) {
        let target = _findSettingItem(entry);
        // A row shown only in some state (the chime minutes under a sound
        // switch that is off): its group, where the switch that shows it is.
        while (target && !target.visible && target !== bodyCol) target = target.parent;
        return target && target !== bodyCol ? target : null;
    }
    // Focus the setting once the scroll to it has settled.
    function _revealNow(entry) {
        const target = _revealTarget(entry);
        if (!target) return;
        // The setting's own control when it takes focus (a switch row), else
        // the first focusable thing in it (a text field, a combo).
        // A row with nothing to focus (About → Version) is only scrolled to.
        let f = target.activeFocusOnTab ? target : target.nextItemInFocusChain(true);
        if (f && _isRow(target) && f !== target && !_isInside(f, target)) f = null;
        if (f) f.forceActiveFocus(Qt.TabFocusReason);
        _applySearchMarks();
    }
    function _isInside(item, ancestor) {
        for (let p = item; p; p = p.parent)
            if (p === ancestor) return true;
        return false;
    }

    // Highlight the matching rows and dim the others while a search is on.
    // Written from here, not bound: the rows come with the section Loaders.
    function _applySearchMarks() {
        const q = Idx.norm(root.searchText);
        const list = _blocks();
        for (let b = 0; b < list.length; b++) {
            const block = list[b];
            const titles = {};
            let any = false;
            for (let i = 0; i < searchMatches.length; i++) {
                if (searchMatches[i].section !== block.sectionId) continue;
                titles[searchMatches[i].title] = true;
                any = true;
            }
            const visit = (it, inMatchedGroup) => {
                const kids = it ? it.children : [];
                for (let i = 0; i < kids.length; i++) {
                    const k = kids[i];
                    if (!k) continue;
                    let grp = inMatchedGroup;
                    if (_isGroup(k)) grp = any && titles[k.title] === true;
                    if (_isRow(k)) {
                        const hit = any && (titles[k.label] === true
                                            || Idx.textMatches(q, k.label, "") || Idx.textMatches(q, k.hint, ""));
                        k.searchMark = !any ? 0 : (hit ? 1 : (grp ? 0 : -1));
                    }
                    visit(k, grp);
                }
            };
            visit(block, false);
        }
    }
    onSearchTextChanged: Qt.callLater(root._applySearchMarks)
    // The nav row Tab lands on: the open section's, or the first one the
    // search leaves when it hides that.
    readonly property int _navTabIndex: {
        let first = -1;
        for (let i = 0; i < sections.length; i++) {
            if (!_sectionMatches(sections[i])) continue;
            if (sections[i].id === activeSection) return i;
            if (first < 0) first = i;
        }
        return first;
    }
    // Focus the nav row at `from`, skipping rows the search hides in the
    // direction `dir` (1 down, -1 up).
    // The open group's row in view, after a deep link or a resize.
    function _revealNavActive() {
        for (let i = 0; i < navRep.count; i++) {
            const it = navRep.itemAt(i);
            if (!it || it.objectName !== "settings-nav-" + root.activeSection) continue;
            const y = it.mapToItem(navCol, 0, 0).y;
            if (y < navScroll.contentY)
                navScroll.contentY = Math.max(0, y - Theme.spMd);
            else if (y + it.height > navScroll.contentY + navScroll.height)
                navScroll.contentY = Math.max(0, Math.min(navScroll.contentHeight - navScroll.height,
                                                          y + it.height - navScroll.height + Theme.spMd));
            return;
        }
    }
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
                // Asked for by name: scroll there even when it is the
                // section the nav already marks.
                if (activeSection === id) _scrollToSection(id);
                else activeSection = id;
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
        if (target) _scrollToItem(target);
    }
    function _scrollYFor(target) {
        const p = target.mapToItem(bodyCol, 0, 0);
        const maxY = Math.max(0, bodyScroll.contentHeight - bodyScroll.height);
        return Math.max(0, Math.min(Math.round(bodyCol.y + p.y - Theme.spMd), maxY));
    }
    function _scrollToItem(target) {
        const newY = _scrollYFor(target);
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

    // One section on the page: heading, line, rows.
    component PageBlock: ColumnLayout {
        id: block
        property string sectionId: ""
        readonly property var meta: root._sectionMeta(block.sectionId) || ({ title: "", sub: "" })
        objectName: "settings-block-" + block.sectionId
        visible: root._sectionMatches(block.meta)
        Layout.fillWidth: true
        spacing: 0

        Text {
            objectName: block.sectionId === "appearance" ? "settings-page-heading" : ""
            Layout.fillWidth: true
            text: block.meta.title
            color: Theme.text
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spXs
            visible: text.length > 0
            text: block.meta.sub
            color: Theme.textMuted
            font.pixelSize: Theme.fsSm
            wrapMode: Text.WordWrap
        }
        Item { Layout.preferredHeight: Theme.sp2xl }

        Item {
            Layout.fillWidth: true
            implicitHeight: blockLoader.implicitHeight
            Loader {
                id: blockLoader
                anchors.fill: parent
                onLoaded: Qt.callLater(root._applySearchMarks)
                sourceComponent: root._pageFor(block.sectionId)
            }
        }
        Item { Layout.preferredHeight: root.groupGap + Theme.sp2xl }
    }

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
        implicitHeight: Theme.px(30)
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
            height: Theme.px(28)
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
            background: PopupSurface {}
        }
    }

    // A paragraph inside a group: full width, secondary colour, its own row.
    component NoteRow: SettingsRow {
        id: noteRow
        property string text: ""
        property color textColor: Theme.textMuted
        fillControl: true
        Text {
            Layout.fillWidth: true
            text: noteRow.text
            color: noteRow.textColor
            font.pixelSize: Theme.fsSm
            lineHeight: 1.15
            wrapMode: Text.WordWrap
        }
    }

    // The rows below are SettingsRows (qml/SettingsRow.qml): label and hint
    // on the left, the control on the right (APP-172). Their own API —
    // value / checked / committed / toggled / selected / moved — is what the
    // sections and the tests have always used.

    component TextRow: SettingsRow {
        id: textRow
        property string placeholder: ""
        property bool mono: false
        property bool secret: false
        // A password is masked even while focused — unlike a token, there is no
        // "check what I pasted" case that justifies revealing it.
        property bool alwaysMasked: false
        property string value: ""
        // How wide the field is in the control column: a time or a prefix
        // does not need a field the width of the page.
        property int fieldWidth: 300
        // Optional: text the field will not store. An edit that fails it is
        // put back to the stored value instead of being saved ("xyz" as a
        // quiet-hours time used to be).
        property alias validator: textRowField.validator
        // A time of day: only H:mm / HH:mm is accepted, and it is committed as
        // HH:mm — what the C++ side parses (SHELL-9, audit 2026-09-30).
        property bool clockTime: false
        // Stored upper-case, so typed and shown that way too.
        property bool upperCase: false
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
        hintColor: textRow.invalid ? Theme.danger : Theme.textMuted
        // A direct child of the row, not of the control slot: callers find
        // the field among the row's own children.
        control: TextField {
            id: textRowField
            ContextMenu.menu: TextEditMenu { editor: textRowField }
            objectName: textRow.objectName.length > 0 ? textRow.objectName + "-field" : ""
            validator: textRow.clockTime ? textRow._clockValidator : null
            // The row's label is the field's name (APP-168); a field with no
            // placeholder was announced as just "edit".
            Accessible.name: textRow.label
            Accessible.description: textRow.hint
            implicitWidth: textRow.fieldWidth
            placeholderText: textRow.placeholder
            placeholderTextColor: Theme.textDim
            color: Theme.text
            font.family: textRow.mono ? Theme.fontMono : Theme.fontUi
            font.capitalization: textRow.upperCase ? Font.AllUppercase : Font.MixedCase
            // Secrets stay masked until focused, so a shoulder-surfer (or a
            // screenshot) never catches a token sitting in the panel.
            echoMode: (textRow.alwaysMasked || (textRow.secret && !activeFocus)) ? TextInput.Password : TextInput.Normal
            background: FieldFrame { border.color: textRow.invalid ? Theme.danger : (textRowField.activeFocus ? Theme.focusRing : Theme.fieldBorder) }
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

    component SwitchRow: SettingsRow {
        id: switchRow
        property bool checked: false
        signal toggled(bool checked)

        // The whole row toggles, not just the 36x20 switch — aiming at the
        // switch was the only way to flip a setting.
        clickable: true
        onClicked: switchRow.toggled(!switchRow.checked)
        // Keyboard: Tab to the row, Space / Enter flips it.
        activeFocusOnTab: true
        Accessible.role: Accessible.CheckBox
        Accessible.name: switchRow.label
        Accessible.description: switchRow.hint
        Accessible.checked: switchRow.checked
        Keys.onSpacePressed: switchRow.toggled(!switchRow.checked)
        Keys.onReturnPressed: switchRow.toggled(!switchRow.checked)

        Rectangle {
            id: switchTrack
            Layout.preferredWidth: 36; Layout.preferredHeight: 20; radius: 10
            color: switchRow.checked ? Theme.accent : Theme.panel3
            // The OFF track had no edge on panel3 in the light themes, and
            // the knob was 1.2-2.3:1 on the accent track (DES-20).
            border.color: switchRow.checked ? Theme.accent : Theme.fieldBorder
            border.width: 1
            FocusRing { target: switchRow; radius: 13 }
            Rectangle {
                id: switchKnob
                width: 14; height: 14; radius: 7
                color: Theme.knob
                border.color: Theme.fieldBorder
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                // Slides by transform, not by x: only transform and opacity
                // animate (APP-175).
                x: 3
                transform: Translate {
                    x: switchRow.checked ? switchTrack.width - switchKnob.width - 6 : 0
                    Behavior on x { NumberAnimation { duration: Theme.durTap; easing.type: Theme.easeEnter } }
                }
            }
        }
    }

    component SegRow: SettingsRow {
        id: segRow
        property var options: []        // [{value,label}] or [string]
        property string value: ""
        signal selected(string value)
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
        Rectangle {
            Layout.preferredWidth: segInner.implicitWidth + 2 * Theme.sp2xs
            Layout.fillWidth: segRow.stacked
            Layout.preferredHeight: Theme.px(30)
            radius: Theme.radiusMd
            color: Theme.panel2
            border.color: Theme.border; border.width: 1
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: segRow.label
            Accessible.description: segRow.hint
            Keys.onLeftPressed: segRow._step(-1)
            Keys.onRightPressed: segRow._step(1)
            FocusRing {}
            RowLayout {
                id: segInner
                anchors.fill: parent
                anchors.margins: Theme.sp2xs
                spacing: 0
                Repeater {
                    model: segRow.options
                    delegate: Rectangle {
                        id: segOpt
                        required property var modelData
                        readonly property string v: typeof modelData === "string" ? modelData : modelData.value
                        readonly property string l: typeof modelData === "string" ? modelData : modelData.label
                        readonly property bool sel: segOpt.v === segRow.value
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: Math.max(Theme.px(64), segTxt.implicitWidth + 2 * Theme.spXl)
                        implicitWidth: Layout.preferredWidth
                        radius: Theme.radiusSm
                        color: segOpt.sel ? Theme.accent
                             : segMA.containsMouse ? Theme.panel3 : "transparent"
                        Text {
                            id: segTxt
                            anchors.centerIn: parent
                            text: segOpt.l
                            color: segOpt.sel ? Theme.textOnAccent : Theme.text
                            font.pixelSize: Theme.fsSm
                            font.weight: Theme.fwTitle
                        }
                        MouseArea {
                            id: segMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: segRow.selected(segOpt.v)
                        }
                    }
                }
            }
        }
    }

    component SliderRow: SettingsRow {
        id: sliderRow
        property string unit: ""
        property real min: 0
        property real max: 100
        property real step: 1
        property real value: 0
        signal moved(real value)
        // The handle let go of after a drag or a click on the track.
        signal released()
        Slider {
            id: sliderCtl
            Layout.preferredWidth: 220
            Layout.fillWidth: sliderRow.stacked
            from: sliderRow.min; to: sliderRow.max; stepSize: sliderRow.step
            value: sliderRow.value
            onMoved: sliderRow.moved(value)
            onPressedChanged: if (!pressed) sliderRow.released()
            // Tab reaches it and ←/→ move it (Slider's own keys); the handle
            // shows the focus ring while it has the keyboard.
            focusPolicy: Qt.StrongFocus
            Accessible.name: sliderRow.label
            Accessible.description: sliderRow.hint
            background: Rectangle {
                x: sliderCtl.leftPadding; y: sliderCtl.topPadding + sliderCtl.availableHeight / 2 - 2
                implicitWidth: 200; implicitHeight: 4
                width: sliderCtl.availableWidth; height: implicitHeight
                radius: 2
                color: Theme.panel3
                Rectangle {
                    width: sliderCtl.visualPosition * parent.width
                    height: parent.height; radius: 2; color: Theme.accent
                }
            }
            handle: Rectangle {
                x: sliderCtl.leftPadding + sliderCtl.visualPosition * (sliderCtl.availableWidth - width)
                y: sliderCtl.topPadding + sliderCtl.availableHeight / 2 - height / 2
                width: 14; height: 14; radius: 7
                color: Theme.knob
                border.color: sliderCtl.activeFocus ? Theme.focusRing : Theme.border
                border.width: sliderCtl.activeFocus ? 2 : 1
            }
        }
        // The value, right-aligned in a fixed cell so the slider does not
        // jump as the number grows a digit.
        Text {
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
            text: Math.round(sliderRow.value) + sliderRow.unit
            color: Theme.text
            font.family: Theme.fontUi
            font.features: Theme.tabularNums
            font.pixelSize: Theme.fsSm
        }
    }

    component SwatchRow: SettingsRow {
        id: swRoot
        property string value: ""
        property var options: []
        signal selected(string color)
        Row {
            spacing: Theme.spSm
            Repeater {
                model: swRoot.options
                delegate: Rectangle {
                    required property string modelData
                    width: 24; height: 24; radius: 12
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

    component DangerRow: SettingsRow {
        id: dangerRow
        property string title: ""
        property string buttonText: ""
        // Two-step, like the other destructive rows: the first click arms,
        // the second commits, and it disarms by itself.
        property string confirmText: I18n.t("settings.data.wipe.confirm")
        property bool armed: false
        signal triggered()
        label: dangerRow.title
        Timer { id: dangerDisarm; interval: 3500; onTriggered: dangerRow.armed = false }
        Rectangle {
            radius: Theme.radiusMd
            color: dangerRow.armed ? Theme.danger
                 : (dangerMA.containsMouse ? Theme.withAlpha(Theme.danger, 0.20) : Theme.withAlpha(Theme.danger, 0.10))
            border.color: Theme.danger; border.width: 1
            Layout.preferredWidth: dangerTxt.implicitWidth + 2 * Theme.spXl
            Layout.preferredHeight: 30
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: dangerTxt.text
            Keys.onSpacePressed: dangerMA.press()
            Keys.onReturnPressed: dangerMA.press()
            FocusRing {}
            Text {
                id: dangerTxt; anchors.centerIn: parent
                text: dangerRow.armed ? dangerRow.confirmText : dangerRow.buttonText
                color: dangerRow.armed ? Theme.textOnDanger : Theme.danger; font.pixelSize: Theme.fsMd; font.weight: Theme.fwTitle
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
    // Every section is a column of SettingsGroups (qml/SettingsGroup.qml)
    // `groupGap` apart; rows inside a group are SettingsRows. Rare and
    // destructive things go last, in a group of their own (APP-172).

    Component {
        id: sectionProfile
        ColumnLayout {
            spacing: root.groupGap
            SettingsGroup {
                title: I18n.t("settings.profile.group.you")
                // A preview of how the name reads on cards and mentions.
                SettingsRow {
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.sp2xl
                        Rectangle {
                            Layout.preferredWidth: Theme.px(48); Layout.preferredHeight: Theme.px(48); radius: width / 2
                            color: root.settings.profile ? root.settings.profile.color : Theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    const n = (root.settings.profile && root.settings.profile.name) || "?";
                                    const parts = n.split(/\s+/);
                                    return (parts[0] ? parts[0][0] : "") + (parts[1] ? parts[1][0] : "");
                                }
                                color: Theme.textOnAccent
                                font.family: Theme.fontUi
                                font.features: Theme.tabularNums
                                font.pixelSize: Theme.fsLg
                                font.weight: Theme.fwTitle
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.sp2xs
                            Text {
                                Layout.fillWidth: true
                                text: (root.settings.profile && root.settings.profile.name) || I18n.t("settings.profile.fullName")
                                color: (root.settings.profile && root.settings.profile.name) ? Theme.text : Theme.textDim
                                font.pixelSize: Theme.fsLg
                                font.weight: Theme.fwTitle
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: {
                                    const p = root.settings.profile || {};
                                    return [p.handle ? "@" + String(p.handle).replace(/^@/, "") : "", p.role || "", p.team || ""]
                                        .filter((s) => s.length > 0).join("  ·  ");
                                }
                                color: Theme.textMuted
                                font.pixelSize: Theme.fsSm
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                TextRow {
                    label: I18n.t("settings.profile.fullName")
                    value: (root.settings.profile && root.settings.profile.name) || ""
                    onCommitted: (text) => root.set("profile", "name", text)
                }
                TextRow {
                    label: I18n.t("settings.profile.handle"); mono: true; placeholder: I18n.t("settings.profile.handle.ph")
                    value: (root.settings.profile && root.settings.profile.handle) || ""
                    onCommitted: (text) => root.set("profile", "handle", text)
                }
                TextRow {
                    label: I18n.t("settings.profile.role")
                    value: (root.settings.profile && root.settings.profile.role) || ""
                    onCommitted: (text) => root.set("profile", "role", text)
                }
                TextRow {
                    label: I18n.t("settings.profile.team")
                    value: (root.settings.profile && root.settings.profile.team) || ""
                    onCommitted: (text) => root.set("profile", "team", text)
                }
            }
            SettingsGroup {
                title: I18n.t("settings.profile.group.avatar")
                SwatchRow {
                    label: I18n.t("settings.profile.avatarColor")
                    value: (root.settings.profile && root.settings.profile.color) || root.avatarSwatches[0]
                    options: root.avatarSwatches
                    onSelected: (color) => root.set("profile", "color", color)
                }
            }
        }
    }

    Component {
        id: sectionAppearance
        ColumnLayout {
            spacing: root.groupGap
            // What was in Tweaks (APP-270, sheet H2-Settings): theme, accent,
            // density, animations — straight on the page.
            SettingsGroup {
                objectName: "settings-appearance-main"
                SegRow {
                    objectName: "settings-theme"
                    label: I18n.t("settings.appearance.theme")
                    hint: I18n.t("settings.appearance.theme.hint")
                    value: AppController.theme
                    options: [
                        ({value: "system", label: I18n.t("settings.appearance.theme.system")}),
                        ({value: "dark", label: I18n.t("settings.appearance.theme.dark")}),
                        ({value: "light", label: I18n.t("settings.appearance.theme.light")})
                    ]
                    onSelected: (value) => AppController.theme = value
                }
                // The colour of the cursor and of what is picked; Lavender
                // is the theme's own accent.
                SegRow {
                    objectName: "settings-accent"
                    label: I18n.t("settings.appearance.accent")
                    hint: I18n.t("settings.appearance.accent.hint")
                    value: Theme.accentTone
                    options: [
                        ({value: "lavender", label: I18n.t("settings.appearance.accent.lavender")}),
                        ({value: "ink", label: I18n.t("settings.appearance.accent.ink")}),
                        ({value: "graphite", label: I18n.t("settings.appearance.accent.graphite")})
                    ]
                    onSelected: (value) => root.set("appearance", "cursorColor", value === "lavender" ? "" : value)
                }
                SegRow {
                    objectName: "settings-density"
                    label: I18n.t("settings.appearance.density")
                    hint: I18n.t("settings.appearance.density.hint")
                    value: AppController.density === "compact" || AppController.density === "spacious" ? AppController.density : "comfy"
                    options: [ ({ value: "compact",  label: I18n.t("common.density.compact") }),
                               ({ value: "comfy",    label: I18n.t("common.density.comfy") }),
                               ({ value: "spacious", label: I18n.t("common.density.spacious") }) ]
                    onSelected: (value) => AppController.density = value
                }
                SegRow {
                    objectName: "settings-motion"
                    label: I18n.t("settings.appearance.reducedMotion")
                    hint: I18n.t("settings.appearance.reducedMotion.hint")
                    value: Theme.reducedMotion ? "min" : "full"
                    options: [ ({ value: "full", label: I18n.t("settings.appearance.motion.full") }),
                               ({ value: "min",  label: I18n.t("settings.appearance.motion.min") }) ]
                    onSelected: (value) => root.set("appearance", "reducedMotion", value === "min")
                }
            }
            // The style (APP-275): Bold or Quiet, each a set of the switches
            // below; flip one and the style is "Custom".
            SettingsGroup {
                objectName: "settings-style-card"
                title: I18n.t("settings.appearance.group.style")
                description: I18n.t("settings.appearance.group.style.desc")
                SegRow {
                    objectName: "settings-style"
                    label: I18n.t("settings.appearance.style")
                    hint: Style.name === "custom" ? I18n.t("settings.appearance.style.customHint") : ""
                    value: Style.name
                    options: Style.name === "custom"
                        ? [ ({ value: "quiet",  label: I18n.t("style.quiet") }),
                            ({ value: "bold",   label: I18n.t("style.bold") }),
                            ({ value: "custom", label: I18n.t("style.custom") }) ]
                        : [ ({ value: "quiet",  label: I18n.t("style.quiet") }),
                            ({ value: "bold",   label: I18n.t("style.bold") }) ]
                    onSelected: (value) => { if (value !== "custom") Style.apply(value); }
                }
                SettingsRow {
                    objectName: "settings-style-reset"
                    visible: Style.name === "custom"
                    PillButton {
                        objectName: "settings-style-reset-button"
                        text: I18n.t("settings.appearance.style.reset").arg(I18n.t("style." + Style.defaultStyle))
                        onClicked: Style.apply(Style.defaultStyle)
                    }
                }
                SwitchRow {
                    objectName: "settings-style-urgency"
                    label: I18n.t("style.flag.urgency")
                    hint: I18n.t("style.flag.urgency.hint")
                    checked: Style.urgency
                    onToggled: (checked) => Style.setFlag("urgency", checked)
                }
                SwitchRow {
                    objectName: "settings-style-counters"
                    label: I18n.t("style.flag.counters")
                    checked: Style.counters
                    onToggled: (checked) => Style.setFlag("counters", checked)
                }
                SwitchRow {
                    objectName: "settings-style-keyHints"
                    label: I18n.t("style.flag.keyHints")
                    hint: I18n.t("style.flag.keyHints.hint")
                    checked: Style.keyHints
                    onToggled: (checked) => Style.setFlag("keyHints", checked)
                }
                SwitchRow {
                    objectName: "settings-style-chipFill"
                    label: I18n.t("style.flag.chipFill")
                    hint: I18n.t("style.flag.chipFill.hint")
                    checked: Style.chipFill
                    onToggled: (checked) => Style.setFlag("chipFill", checked)
                }
                SwitchRow {
                    objectName: "settings-style-factsLine"
                    label: I18n.t("style.flag.factsLine")
                    checked: Style.factsLine
                    onToggled: (checked) => Style.setFlag("factsLine", checked)
                }
                SegRow {
                    objectName: "settings-style-todayExtras"
                    label: I18n.t("style.flag.todayExtras")
                    value: Style.todayExtras
                    options: [ ({ value: "open",      label: I18n.t("style.flag.todayExtras.open") }),
                               ({ value: "collapsed", label: I18n.t("style.flag.todayExtras.collapsed") }),
                               ({ value: "hidden",    label: I18n.t("style.flag.todayExtras.hidden") }) ]
                    onSelected: (value) => Style.setFlag("todayExtras", value)
                }
                // Not a switch: without the icons a meeting and a task cannot
                // be told apart.
                SettingsRow {
                    objectName: "settings-style-icons"
                    label: I18n.t("style.flag.icons")
                    hint: I18n.t("style.flag.icons.hint")
                    Text {
                        text: I18n.t("style.flag.icons.always")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                    }
                }
            }
            // The finer knobs: scale, contrast, a cursor colour of its own.
            SettingsGroup {
                title: I18n.t("settings.appearance.group.more")
                // Type and spacing, live (APP-168).
                SegRow {
                    objectName: "settings-ui-scale"
                    label: I18n.t("settings.appearance.scale")
                    // Unset, the scale is the system's text size (APP-183):
                    // say so, or the 150 % nobody picked looks like a bug.
                    hint: Theme._appearance.uiScale === undefined && Theme.systemScale() !== 1
                          ? I18n.t("settings.appearance.scale.system")
                          : I18n.t("settings.appearance.scale.hint")
                    value: String(Math.round(Theme.scale * 100))
                    options: Theme.scaleSteps.map((s) => ({ value: String(Math.round(s * 100)), label: Math.round(s * 100) + "%" }))
                    onSelected: (value) => root.set("appearance", "uiScale", Number(value) / 100)
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
                // The keyboard cursor's colour (APP-174) from the swatches;
                // the first dot is the accent picked above.
                CursorColorRow {
                    objectName: "settings-cursor-color"
                    label: I18n.t("settings.appearance.cursorColor")
                    hint: I18n.t("settings.appearance.cursorColor.hint")
                    value: Theme.accentTone === "custom" ? Theme.cursorColorPick : ""
                    // Straight into the settings JSON: no unqualified `root`
                    // from in here.
                    onSelected: (color) => {
                        let s = {};
                        try { s = JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { s = {}; }
                        s.appearance = Object.assign({}, s.appearance, { cursorColor: color });
                        AppController.appSettingsJson = JSON.stringify(s);
                    }
                }
            }
            SettingsGroup {
                objectName: "settings-theme-card"
                title: I18n.t("settings.appearance.group.themes")
                SettingsRow {
                    ThemeSettings {
                        Layout.fillWidth: true
                        appearance: root.settings.appearance || ({})
                        onSetKey: (key, value) => root.set("appearance", key, value)
                    }
                }
            }
            SettingsGroup {
                title: I18n.t("settings.appearance.group.behaviour")
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
            // The sound palette (APP-177): a task closed, an undo, a refused
            // action — never navigation, typing or hover. Off by default;
            // quiet hours and focus mode keep it silent (AppController).
            // Reads and writes the settings JSON directly (this view reloads
            // on the change), so no unqualified `root` from in here.
            SettingsGroup {
                id: soundCard
                objectName: "settings-sound-card"
                title: I18n.t("settings.sound.group")
                readonly property var sound: {
                    try { return (JSON.parse(AppController.appSettingsJson || "{}") || {}).sound || ({}); } catch (e) { return ({}); }
                }
                readonly property bool on: soundCard.sound.enabled === true
                function setSound(key, value) {
                    let s = {};
                    try { s = JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { s = {}; }
                    const next = Object.assign({}, s.sound);
                    next[key] = value;
                    s.sound = next;
                    AppController.appSettingsJson = JSON.stringify(s);
                }
                // The meeting chimes' moments (APP-178): up to three whole
                // minutes from 1 to 120, latest first — the order the C++
                // side reads them in.
                function parseChimeMinutes(text) {
                    const out = [];
                    for (const part of String(text).split(",")) {
                        const m = parseInt(part.trim(), 10);
                        if (m >= 1 && m <= 120 && out.indexOf(m) < 0) out.push(m);
                    }
                    out.sort((a, b) => b - a);
                    return out.slice(0, 3);
                }
                function chimeMinutesText(list) {
                    return (Array.isArray(list) && list.length > 0 ? list : [15, 10, 5]).join(", ");
                }
                SwitchRow {
                    objectName: "settings-sound-enabled"
                    label: I18n.t("settings.sound.enabled")
                    hint: I18n.t("settings.sound.enabled.hint")
                    checked: soundCard.on
                    onToggled: (checked) => soundCard.setSound("enabled", checked)
                }
                // Letting go of the slider plays the "done" sound at the new
                // level, so the number has something to go by.
                SliderRow {
                    id: soundVolumeRow
                    objectName: "settings-sound-volume"
                    visible: soundCard.on
                    label: I18n.t("settings.sound.volume")
                    min: 0; max: 100; step: 5
                    value: typeof soundCard.sound.volume === "number" ? soundCard.sound.volume : 55
                    onMoved: (value) => soundCard.setSound("volume", Math.round(value))
                    onReleased: AppController.previewSound(Math.round(soundVolumeRow.value))
                }
                // Three melodies as a meeting comes closer (APP-178): two
                // chords, a rise, a call at the last moment.
                SwitchRow {
                    objectName: "settings-sound-meeting"
                    visible: soundCard.on
                    label: I18n.t("settings.sound.meeting")
                    hint: I18n.t("settings.sound.meeting.hint")
                    checked: soundCard.sound.meetingChimes !== false
                    onToggled: (checked) => soundCard.setSound("meetingChimes", checked)
                }
                TextRow {
                    id: chimeMinutesRow
                    objectName: "settings-sound-meeting-minutes"
                    visible: soundCard.on && soundCard.sound.meetingChimes !== false
                    label: I18n.t("settings.sound.meetingMinutes")
                    hint: chimeMinutesRow.invalid ? I18n.t("settings.sound.meetingMinutes.invalid") : I18n.t("settings.sound.meetingMinutes.hint")
                    placeholder: "15, 10, 5"
                    fieldWidth: 120
                    validator: RegularExpressionValidator { regularExpression: /^\s*\d{1,3}(\s*,\s*\d{1,3}){0,2}\s*$/ }
                    value: soundCard.chimeMinutesText(soundCard.sound.meetingChimeMinutes)
                    onCommitted: (text) => {
                        const list = soundCard.parseChimeMinutes(text);
                        if (list.length > 0) soundCard.setSound("meetingChimeMinutes", list);
                    }
                }
            }
        }
    }

    Component {
        id: sectionLanguage
        ColumnLayout {
            spacing: root.groupGap
            SettingsGroup {
                SegRow {
                    label: I18n.t("settings.language.label")
                    hint: I18n.t("settings.language.hint")
                    value: AppController.language
                    options: [
                        ({value: "en", label: "English"}),
                        ({value: "ru", label: "Русский"})
                    ]
                    onSelected: (value) => AppController.language = value
                }
            }
        }
    }

    Component {
        id: sectionNotifications
        ColumnLayout {
            spacing: root.groupGap
            SettingsGroup {
                title: I18n.t("settings.notif.sub.deadlines")
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
                SliderRow {
                    label: I18n.t("settings.notif.meetingLead")
                    unit: " " + I18n.t("common.minutes"); min: 0; max: 30; step: 1
                    // Undefined-aware fallback: a stored 0 is a valid lead
                    // (min is 0) and must not collapse to 5 via a falsy `||`.
                    value: root.settings.notifications
                           ? (root.settings.notifications.meetingLead ?? 5) : 5
                    onMoved: (value) => root.set("notifications", "meetingLead", value)
                }
                // The two snooze buttons on a reminder (APP-155).
                SliderRow {
                    objectName: "settings-snooze-short"
                    label: I18n.t("settings.notif.snoozeShort")
                    hint: I18n.t("settings.notif.snoozeShort.hint")
                    unit: " " + I18n.t("common.minutes"); min: 5; max: 60; step: 5
                    value: root.settings.notifications
                           ? (root.settings.notifications.snoozeShortMin ?? 10) : 10
                    onMoved: (value) => root.set("notifications", "snoozeShortMin", value)
                }
                SliderRow {
                    objectName: "settings-snooze-long"
                    label: I18n.t("settings.notif.snoozeLong")
                    unit: " " + I18n.t("common.minutes"); min: 15; max: 240; step: 15
                    value: root.settings.notifications
                           ? (root.settings.notifications.snoozeLongMin ?? 60) : 60
                    onMoved: (value) => root.set("notifications", "snoozeLongMin", value)
                }
                SwitchRow {
                    label: I18n.t("settings.notif.standupReminder")
                    hint: I18n.t("settings.notif.standupReminder.hint")
                    checked: !!(root.settings.notifications && root.settings.notifications.standupReminder)
                    onToggled: (checked) => root.set("notifications", "standupReminder", checked)
                }
            }
            SettingsGroup {
                title: I18n.t("settings.notif.sub.channels")
                SwitchRow {
                    label: I18n.t("settings.notif.desktopNotif")
                    checked: !!(root.settings.notifications && root.settings.notifications.desktopNotif)
                    onToggled: (checked) => root.set("notifications", "desktopNotif", checked)
                }
                // Shows a sample reminder with its buttons now, so the
                // user can see the OS lets heap's notifications through.
                SettingsRow {
                    label: I18n.t("settings.notif.test")
                    PillButton {
                        objectName: "settings-test-notification"
                        text: I18n.t("settings.notif.test")
                        onClicked: AppController.sendTestNotification()
                    }
                }
                SwitchRow {
                    label: I18n.t("settings.notif.soundOnPing")
                    checked: !!(root.settings.notifications && root.settings.notifications.soundOnPing)
                    onToggled: (checked) => root.set("notifications", "soundOnPing", checked)
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
            }
            SettingsGroup {
                title: I18n.t("settings.notif.sub.quiet")
                SwitchRow {
                    label: I18n.t("settings.notif.quietHours")
                    hint: I18n.t("settings.notif.quietHours.hint")
                    checked: !!(root.settings.notifications && root.settings.notifications.quietHours)
                    onToggled: (checked) => root.set("notifications", "quietHours", checked)
                }
                TextRow {
                    visible: !!(root.settings.notifications && root.settings.notifications.quietHours)
                    label: I18n.t("common.from"); mono: true; placeholder: "19:00"
                    fieldWidth: 120
                    hint: invalid ? I18n.t("settings.notif.quiet.invalid") : ""
                    validator: RegularExpressionValidator { regularExpression: root._hhmmRe }
                    value: (root.settings.notifications && root.settings.notifications.quietFrom) || ""
                    onCommitted: (text) => root.set("notifications", "quietFrom", root._hhmm(text))
                }
                TextRow {
                    visible: !!(root.settings.notifications && root.settings.notifications.quietHours)
                    label: I18n.t("common.to"); mono: true; placeholder: "09:00"
                    fieldWidth: 120
                    hint: invalid ? I18n.t("settings.notif.quiet.invalid") : ""
                    validator: RegularExpressionValidator { regularExpression: root._hhmmRe }
                    value: (root.settings.notifications && root.settings.notifications.quietTo) || ""
                    onCommitted: (text) => root.set("notifications", "quietTo", root._hhmm(text))
                }
            }
        }
    }

    // Safety net (APP-172): gentle, opt-in heads-ups, every one off by
    // default. Each says what it noticed once and changes nothing by itself.
    Component {
        id: sectionSafety
        ColumnLayout {
            spacing: root.groupGap
            // Rows read AppController.safety and write through
            // setSafetySetting(); this view reloads on the change.
            // APP-157: one notice at the end of the day.
            SettingsGroup {
                title: I18n.t("settings.safety.group.endOfDay")
                SwitchRow {
                    objectName: "settings-safety-endOfDay"
                    label: I18n.t("settings.safety.endOfDay")
                    hint: I18n.t("settings.safety.endOfDay.hint")
                    checked: AppController.safety.endOfDay === true
                    onToggled: (checked) => AppController.setSafetySetting("endOfDay", checked)
                }
                TextRow {
                    objectName: "settings-safety-endOfDayTime"
                    visible: AppController.safety.endOfDay === true
                    label: I18n.t("settings.safety.endOfDayTime"); mono: true; placeholder: "18:00"
                    fieldWidth: 120
                    hint: invalid ? I18n.t("settings.safety.time.invalid") : ""
                    clockTime: true
                    value: AppController.safety.endOfDayTime || "18:00"
                    onCommitted: (text) => AppController.setSafetySetting("endOfDayTime", text)
                }
                SliderRow {
                    objectName: "settings-safety-staleDays"
                    visible: AppController.safety.endOfDay === true
                    label: I18n.t("settings.safety.staleDays")
                    unit: " " + I18n.t("common.days"); min: 1; max: 14; step: 1
                    value: AppController.safety.staleDays ?? 3
                    onMoved: (value) => AppController.setSafetySetting("staleDays", Math.round(value))
                }
            }
            // APP-158: a task waiting on someone's reply.
            SettingsGroup {
                title: I18n.t("settings.safety.group.waiting")
                SwitchRow {
                    objectName: "settings-safety-waiting"
                    label: I18n.t("settings.safety.waiting")
                    hint: I18n.t("settings.safety.waiting.hint")
                    checked: AppController.safety.waitingOn === true
                    onToggled: (checked) => AppController.setSafetySetting("waitingOn", checked)
                }
                SliderRow {
                    objectName: "settings-safety-waitingDays"
                    visible: AppController.safety.waitingOn === true
                    label: I18n.t("settings.safety.waitingDays")
                    unit: " " + I18n.t("common.days"); min: 1; max: 7; step: 1
                    value: AppController.safety.waitingDays ?? 2
                    onMoved: (value) => AppController.setSafetySetting("waitingDays", Math.round(value))
                }
            }
            // APP-159: an error pasted somewhere that came up before.
            SettingsGroup {
                title: I18n.t("settings.safety.group.seen")
                SwitchRow {
                    objectName: "settings-safety-seenBefore"
                    label: I18n.t("settings.safety.seen")
                    hint: I18n.t("settings.safety.seen.hint")
                    checked: AppController.safety.seenBefore === true
                    onToggled: (checked) => AppController.setSafetySetting("seenBefore", checked)
                }
            }
            // APP-160: focus mode, from the palette or its shortcut.
            SettingsGroup {
                title: I18n.t("settings.safety.group.immersion")
                SwitchRow {
                    objectName: "settings-safety-immersion"
                    label: I18n.t("settings.safety.immersion")
                    hint: I18n.t("settings.safety.immersion.hint").arg(AppController.shortcutFor("focus.immersion"))
                    checked: AppController.safety.immersion === true
                    onToggled: (checked) => AppController.setSafetySetting("immersion", checked)
                }
                SwitchRow {
                    objectName: "settings-safety-immersionPassMeetings"
                    visible: AppController.safety.immersion === true
                    label: I18n.t("settings.safety.immersionPassMeetings")
                    hint: I18n.t("settings.safety.immersionPassMeetings.hint")
                    checked: AppController.safety.immersionPassMeetings !== false
                    onToggled: (checked) => AppController.setSafetySetting("immersionPassMeetings", checked)
                }
            }
            // APP-170: a standup draft from yesterday's facts.
            SettingsGroup {
                title: I18n.t("settings.safety.group.standup")
                SwitchRow {
                    objectName: "settings-safety-standupDraft"
                    label: I18n.t("settings.safety.standup")
                    hint: I18n.t("settings.safety.standup.hint")
                    checked: AppController.safety.standupDraft === true
                    onToggled: (checked) => AppController.setSafetySetting("standupDraft", checked)
                }
            }
        }
    }

    Component {
        id: sectionCalendar
        ColumnLayout {
            spacing: root.groupGap
            SettingsGroup {
                title: I18n.t("settings.cal.group.week")
                SegRow {
                    label: I18n.t("settings.cal.weekStart")
                    value: (root.settings.calendar && root.settings.calendar.weekStart) || "mon"
                    options: [
                        ({value: "mon", label: I18n.t("settings.cal.weekStart.mon")}),
                        ({value: "sun", label: I18n.t("settings.cal.weekStart.sun")})
                    ]
                    onSelected: (value) => root.set("calendar", "weekStart", value)
                }
                SegRow {
                    label: I18n.t("settings.cal.timeFormat")
                    value: (root.settings.calendar && root.settings.calendar.timeFormat) || "24h"
                    options: [ ({ value: "24h", label: "24h" }), ({ value: "12h", label: "12h" }) ]
                    onSelected: (value) => root.set("calendar", "timeFormat", value)
                }
                SwitchRow {
                    label: I18n.t("settings.cal.showWeekends")
                    checked: !!(root.settings.calendar && root.settings.calendar.showWeekends)
                    onToggled: (checked) => root.set("calendar", "showWeekends", checked)
                }
                // The days the standup reminder fires and focus blocks
                // are booked on. Qt weekday numbers, Mon=1 … Sun=7.
                SettingsRow {
                    id: workDaysRow
                    objectName: "settings-workdays"
                    label: I18n.t("settings.cal.workDays")
                    readonly property var days: (root.settings.calendar && root.settings.calendar.workDays
                                                 && root.settings.calendar.workDays.length > 0)
                                                ? root.settings.calendar.workDays : [1, 2, 3, 4, 5]
                    Row {
                        spacing: Theme.spXs
                        Repeater {
                            model: 7
                            delegate: Rectangle {
                                id: wdChip
                                required property int index
                                readonly property int day: wdChip.index + 1
                                readonly property bool on: workDaysRow.days.indexOf(wdChip.day) >= 0
                                width: 34; height: 26
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
            SettingsGroup {
                title: I18n.t("settings.cal.workHours")
                SliderRow {
                    label: I18n.t("settings.cal.workStart"); unit: ":00"; min: 6; max: 12; step: 1
                    value: AppController.workdayStart
                    onMoved: (value) => AppController.workdayStart = value
                }
                SliderRow {
                    label: I18n.t("settings.cal.workEnd"); unit: ":00"; min: 14; max: 23; step: 1
                    value: AppController.workdayEnd
                    onMoved: (value) => AppController.workdayEnd = value
                }
                SegRow {
                    label: I18n.t("settings.cal.snap")
                    value: String(_num(root.settings.calendar && root.settings.calendar.snapMinutes, 15))
                    options: [ ({ value: "5", label: "5 " + I18n.t("common.minutes") }), ({ value: "15", label: "15 " + I18n.t("common.minutes") }), ({ value: "30", label: "30 " + I18n.t("common.minutes") }) ]
                    onSelected: (value) => root.set("calendar", "snapMinutes", parseInt(value))
                }
            }
            SettingsGroup {
                title: I18n.t("settings.cal.focus")
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
                    fieldWidth: 120
                    label: I18n.t("settings.cal.standupTime"); mono: true; placeholder: "10:00"
                    hint: invalid ? I18n.t("settings.cal.standupTime.invalid") : ""
                    value: (root.settings.calendar && root.settings.calendar.standupTime) || ""
                    onCommitted: (text) => root.set("calendar", "standupTime", text)
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
            spacing: root.groupGap
            SettingsGroup {
                title: I18n.t("settings.tasks.group.new")
                TextRow {
                    label: I18n.t("settings.tasks.idPrefix"); mono: true; placeholder: "TASK"
                    fieldWidth: 160
                    // What a #KEY-1 link and a branch name can carry (SHELL-10):
                    // a letter, then letters and digits. Shown as stored, upper case.
                    validator: RegularExpressionValidator { regularExpression: /^([A-Za-z][A-Za-z0-9]{0,15})?$/ }
                    upperCase: true
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
                SwitchRow {
                    label: I18n.t("settings.tasks.renameExisting")
                    hint: I18n.t("settings.tasks.renameExisting.hint")
                        .arg(((root.settings.tasks && root.settings.tasks.idPrefix) || "TASK").toUpperCase())
                    checked: sectionTasksRoot.renameExistingOnCommit
                    onToggled: (checked) => sectionTasksRoot.renameExistingOnCommit = checked
                }
                SegRow {
                    label: I18n.t("settings.tasks.defaultPriority")
                    value: (root.settings.tasks && root.settings.tasks.defaultPriority) || "P2"
                    options: ["P0", "P1", "P2", "P3"]
                    onSelected: (value) => root.set("tasks", "defaultPriority", value)
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
            SettingsGroup {
                title: I18n.t("settings.tasks.automations")
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

    Component {
        id: sectionShortcuts
        ColumnLayout {
            spacing: root.groupGap
            SettingsGroup {
                SettingsRow {
                    label: I18n.t("settings.shortcuts.sub")
                    hint: I18n.t("settings.shortcuts.intro")
                    Rectangle {
                        radius: Theme.radiusMd
                        Layout.preferredWidth: openTxt.implicitWidth + 2 * Theme.spXl
                        Layout.preferredHeight: 30
                        color: openMA.hovered ? Theme.panel3 : Theme.panel2
                        border.color: Theme.border; border.width: 1
                        Text {
                            id: openTxt
                            anchors.centerIn: parent
                            text: I18n.t("settings.shortcuts.open")
                            color: Theme.text
                            font.pixelSize: Theme.fsSm
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
                // Where heap cannot listen for the capture hotkey system-wide
                // (Wayland without the shortcuts portal), the desktop can run
                // `heap --capture` instead (APP-171).
                NoteRow {
                    objectName: "settings-capture-command-hint"
                    visible: Qt.platform.os === "linux" && AppController.globalHotkeyBackend() === "none"
                    text: I18n.t("settings.shortcuts.captureCommand").arg("lowkey --capture")
                }
                // On by default: it speaks once per action, ever (APP-166).
                SwitchRow {
                    objectName: "settings-shortcut-hints"
                    label: I18n.t("settings.shortcuts.mouseHints")
                    hint: I18n.t("settings.shortcuts.mouseHints.hint")
                    checked: !(root.settings.shortcuts && root.settings.shortcuts.mouseHints === false)
                    onToggled: (checked) => root.set("shortcuts", "mouseHints", checked)
                }
            }
            SettingsGroup {
                title: I18n.t("settings.shortcuts.group.all")
                Repeater {
                    model: AppController.shortcuts
                    delegate: SettingsRow {
                        required property var modelData
                        label: modelData.label
                        hint: modelData.description
                        labelWidth: 420
                        Rectangle {
                            radius: Theme.radiusSm
                            color: Theme.panel2
                            border.color: Theme.border; border.width: 1
                            Layout.preferredWidth: seqText.implicitWidth + 2 * Theme.spMd
                            Layout.preferredHeight: 24
                            Text {
                                id: seqText
                                anchors.centerIn: parent
                                text: modelData.sequence || I18n.t("settings.shortcuts.notSet")
                                color: modelData.sequence ? Theme.text : Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsSm
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sectionIntegrations
        ColumnLayout {
            id: intSection
            spacing: Theme.sp2xl

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
            // The page stays built (APP-270), so a sync that saw new tracker
            // statuses has to say so too.
            Connections {
                target: AppController
                function onAppSettingsJsonChanged() { intSection.statusMapRev++; }
            }
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
            // How each connected tracker has been doing (APP-164).
            IntegrationHealthCard {}
            // Outlook / Google / iCloud meetings by link (APP-118).
            CalendarSubscriptionsCard {}

            AutoSyncCard {}

            SettingsGroup {
                framed: false
                title: I18n.t("settings.integrations.group.services")
                // One card per registered provider — the catalogue is the single
                // source of truth (AppController.integrationCatalog), so adding a
                // provider in C++ surfaces a card here with no QML change.
                Repeater {
                    model: AppController.integrationCatalog()
                    delegate: SectionCard {
                        id: intDelegate
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
                                        implicitWidth: 32; implicitHeight: 32; radius: Theme.radiusMd
                                        color: modelData.color
                                        readonly property string logo: root.providerLogos[modelData.id] || ""
                                        IconImage {
                                            visible: parent.logo !== ""
                                            anchors.centerIn: parent
                                            width: 18; height: 18
                                            sourceSize.width: 18; sourceSize.height: 18
                                            source: parent.logo !== "" ? "qrc:/brand/icons/" + parent.logo + ".svg" : ""
                                            // On the brand colour, not the accent:
                                            // textOnAccent was 2.8:1 on Jira red (DES-25).
                                            color: Theme.textOn(intTile.color)
                                        }
                                        // A provider without a drawn mark keeps
                                        // its catalogue glyph.
                                        Text {
                                            visible: parent.logo === ""
                                            anchors.centerIn: parent; text: modelData.icon; color: Theme.textOn(intTile.color); font.pixelSize: Theme.fsLg; font.weight: Theme.fwTitle
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text { id: intName; text: modelData.name; color: Theme.text; font.pixelSize: Theme.fsLg; font.weight: Theme.fwTitle }
                                        Text { text: I18n.t(modelData.descKey); color: Theme.textMuted; font.pixelSize: Theme.fsMd; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                    }
                                    Text {
                                        objectName: "int-card-state"
                                        // Offline is still connected: heap keeps the
                                        // session and retries (audit INT-5).
                                        text: !intCard.isConn ? I18n.t("common.disconnected")
                                              : (intCard.offline ? I18n.t("settings.integrations.offline") : I18n.t("common.connected"))
                                        color: !intCard.isConn ? Theme.textDim : (intCard.offline ? Theme.warning : Theme.success)
                                        font.family: Theme.fontUi; font.features: Theme.tabularNums; font.pixelSize: Theme.fsSm
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

                                // Writing to the tracker is the user's call, per
                                // tracker, and off until they make it (APP-243):
                                // with it off a card's move stays in heap.
                                SwitchRow {
                                    objectName: "int-write-status-" + intCard.intKey
                                    visible: intDelegate.modelData.writesStatus === true
                                    Layout.fillWidth: true
                                    separator: false
                                    label: I18n.t("settings.integrations.writeStatus").arg(intDelegate.modelData.name)
                                    hint: intCard.conf.writeStatus === true
                                          ? I18n.t("settings.integrations.writeStatus.onHint")
                                          : I18n.t("settings.integrations.writeStatus.offHint").arg(intDelegate.modelData.name)
                                    checked: intCard.conf.writeStatus === true
                                    onToggled: (checked) => AppController.setTrackerWriteEnabled(intCard.intKey, checked)
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
                                            font.pixelSize: Theme.fsXl; font.weight: Theme.fwTitle
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
                                    // The rows pad themselves (SettingsRow).
                                    spacing: 0
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
                                                font.weight: Theme.fwTitle
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
    }

    Component {
        id: sectionGit
        ColumnLayout {
            spacing: root.groupGap
            SettingsGroup {
                title: I18n.t("settings.git.repos")
                description: I18n.t("settings.git.repos.hint")
                Repeater {
                    model: (root.settings.git && root.settings.git.watchedRepos) || []
                    delegate: SettingsRow {
                        required property string modelData
                        required property int    index
                        fillControl: true
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
                            Layout.preferredWidth: 22; Layout.preferredHeight: 22
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
                SettingsRow {
                    fillControl: true
                    TextField {
                        id: newRepoField
                        ContextMenu.menu: TextEditMenu { editor: newRepoField }
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
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: addT.implicitWidth + 2 * Theme.spXl
                        color: addMA.hovered ? Theme.accentHover : Theme.accent
                        opacity: addMA.enabled ? 1 : 0.45
                        Text {
                            id: addT
                            anchors.centerIn: parent
                            text: "+ " + I18n.t("common.add")
                            color: Theme.textOnAccent
                            font.weight: Theme.fwTitle
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
                NoteRow {
                    text: I18n.t("settings.git.match.hint")
                        .arg(((root.settings.tasks && root.settings.tasks.idPrefix) || "TASK").toUpperCase())
                }
            }
            SettingsGroup {
                title: I18n.t("settings.git.autoOn")
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
                SwitchRow {
                    objectName: "settings-git-show-move"
                    label: I18n.t("settings.git.showMove")
                    hint: I18n.t("settings.git.showMove.hint")
                    checked: !(root.settings.git && root.settings.git.showWhoseMove === false)
                    onToggled: (checked) => root.set("git", "showWhoseMove", checked)
                }
            }
        }
    }

    Component {
        id: sectionData
        ColumnLayout {
            id: dataRoot
            spacing: root.groupGap
            // Backups are read on demand (listBackups() is a plain invokable,
            // not a notifying property). The Data section is rebuilt whenever
            // the user opens it, so refreshing on completion keeps it current.
            property var backups: []
            function refreshBackups() { dataRoot.backups = AppController.listBackups(); }
            Component.onCompleted: dataRoot.refreshBackups()
            SettingsGroup {
                title: I18n.t("settings.data.backups")
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
                // APP-162: hourly history, browsed in its own dialog.
                SettingsRow {
                    label: I18n.t("settings.data.timeMachine")
                    hint: I18n.t("settings.data.timeMachine.hint")
                    ActionButton {
                        objectName: "settings-open-time-machine"
                        text: I18n.t("settings.data.timeMachine.open")
                        onActivated: settingsBridge.timeMachineRequested()
                    }
                }
            }
            SettingsGroup {
                title: I18n.t("settings.data.restore")
                NoteRow {
                    visible: dataRoot.backups.length === 0
                    text: I18n.t("settings.data.restore.empty")
                }
                Repeater {
                    model: dataRoot.backups
                    delegate: SettingsRow {
                        required property var modelData
                        label: modelData.mtime
                        hint: modelData.fileName + "  ·  " + modelData.sizeKb + " KB"
                        // Two-step confirm: first click arms (restore
                        // overwrites the live state), second within 3.5 s
                        // performs it. Auto-disarms so a stray click is safe.
                        ActionButton {
                            id: restoreBtn
                            objectName: "settings-restore-backup"
                            implicitHeight: 30
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
            SettingsGroup {
                title: I18n.t("settings.data.importExport")
                SettingsRow {
                    hint: I18n.t("settings.data.importExport.hint")
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
            // Attached files nothing links any more. Counted when the section
            // opens and after a cleanup; deleting asks first (the button arms,
            // the second press deletes) and says how much it frees.
            SettingsGroup {
                id: attCleanup
                objectName: "settings-attachments-cleanup"
                title: I18n.t("att.cleanup.title")
                property var unused: ({ count: 0, bytes: 0, sizeText: "" })
                property bool armed: false
                function refresh() { attCleanup.unused = AppController.unusedAttachments(); attCleanup.armed = false; }
                Component.onCompleted: attCleanup.refresh()
                SettingsRow {
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
            // The destructive pair, last and on its own.
            SettingsGroup {
                title: I18n.t("settings.data.danger")
                danger: true
                Layout.topMargin: Theme.spXl
                DangerRow {
                    title: I18n.t("settings.data.reset")
                    hint: I18n.t("settings.data.reset.hint")
                    buttonText: I18n.t("settings.data.resetButton")
                    onTriggered: root.resetAll()
                }
                // Full wipe → first-run. The most destructive thing in the
                // app is confirmed in a dialog that says what goes (design
                // audit DES-16); a second click within 3.5 s was all it took.
                SettingsRow {
                    id: wipeRow
                    label: I18n.t("settings.data.wipe")
                    hint: I18n.t("settings.data.wipe.hint")
                    ActionButton {
                        objectName: "settings-wipe"
                        kind: "danger"
                        implicitHeight: 30
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
                            Overlay.modal: ModalScrim {}
                            readonly property var profileNames: {
                                const out = [];
                                const ps = AppController.profiles || [];
                                for (let i = 0; i < ps.length; i++) out.push(ps[i].name || ps[i].id);
                                return out;
                            }
                            onOpened: wipeCancel.forceActiveFocus()
                            background: ModalSurface {}
                            contentItem: ColumnLayout {
                                spacing: Theme.spXl
                                Text {
                                    text: I18n.t("settings.data.wipe.dialogTitle")
                                    color: Theme.text
                                    font.pixelSize: Theme.fsLg
                                    font.weight: Theme.fwHeading
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

    Component {
        id: sectionHelp
        HelpContent {
            onAnchorRequested: (name) => root._scrollToAnchor(name)
        }
    }

    Component {
        id: sectionAbout
        ColumnLayout {
            spacing: root.groupGap
            SettingsGroup {
                SettingsRow {
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spXl
                        BrandLogo {
                            variant: "mark"
                            theme: Theme.dark ? "dark" : "light"
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.sp2xs
                            Text {
                                text: Brand.name; color: Theme.text; font.family: Theme.fontUi; font.pixelSize: Theme.fsLg; font.weight: Theme.fwTitle
                            }
                            Text {
                                Layout.fillWidth: true
                                text: Brand.tagline; color: Theme.textMuted; font.pixelSize: Theme.fsSm
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
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
            SettingsGroup {
                id: updatesCol
                title: I18n.t("settings.about.updates")
                property bool updateReady: false
                Connections {
                    target: AppController
                    function onUpdateAvailable(version, url) { updatesCol.updateReady = true }
                }
                SettingsRow {
                    hint: AppController.updateStatus === "" ? I18n.t("settings.about.updates.hint") : AppController.updateStatus
                    labelWidth: 360
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
                // Download progress (APP-125).
                SettingsRow {
                    visible: AppController.updatePhase === "downloading"
                    Rectangle {
                        objectName: "settings-update-progress"
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
                }
                SwitchRow {
                    label: I18n.t("settings.about.autoCheck")
                    checked: !!(root.settings.updates && root.settings.updates.autoCheck)
                    onToggled: (checked) => root.set("updates", "autoCheck", checked)
                }
            }
            SettingsGroup {
                title: I18n.t("settings.about.diagnostics")
                SettingsRow {
                    hint: I18n.t("settings.about.diagnostics.hint")
                    labelWidth: 360
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
    }

    component AboutRow: SettingsRow {
        id: aboutRow
        property string value: ""
        labelWidth: 160
        fillControl: true
        // Elided: the storage path is long enough to stretch the card past the
        // panel. The full value is on the tooltip.
        Text {
            text: aboutRow.value
            color: Theme.text
            font.family: Theme.fontUi
            font.features: Theme.tabularNums
            font.pixelSize: Theme.fsSm
            Layout.fillWidth: true
            horizontalAlignment: aboutRow.stacked ? Text.AlignLeft : Text.AlignRight
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
        signal timeMachineRequested()
    }
    Connections {
        target: settingsBridge
        function onOpenHotkeysRequested() { if (typeof settingsBus !== "undefined") settingsBus.openHotkeys() }
        function onExportJsonRequested()  { if (typeof settingsBus !== "undefined") settingsBus.exportJson() }
        function onImportJsonRequested()  { if (typeof settingsBus !== "undefined") settingsBus.importJson() }
        function onTimeMachineRequested() { if (typeof settingsBus !== "undefined") settingsBus.openTimeMachine() }
    }

    // Over the list, not in it: parented to the Flickable itself
    // (not its content), so it stays put while the rows scroll.
    ScrollFade {
        objectName: "settings-nav-fade"
        parent: navScroll
        anchors.fill: parent
        flick: navScroll
        color: Theme.panel
    }
}
