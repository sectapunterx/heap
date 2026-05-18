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
    readonly property var sections: [
        { id: "profile",       icon: "◉",   title: "Profile",          sub: "Имя, роль, команда" },
        { id: "appearance",    icon: "◑",   title: "Appearance",       sub: "Тема, акцент, плотность" },
        { id: "notifications", icon: "◔",   title: "Notifications",    sub: "Дедлайны, созвоны" },
        { id: "calendar",      icon: "◫",   title: "Calendar",         sub: "Часы, focus time" },
        { id: "tasks",         icon: "▦",   title: "Tasks & Workflow", sub: "Префикс ID, дефолты" },
        { id: "shortcuts",     icon: "⌨",   title: "Shortcuts",        sub: "Горячие клавиши" },
        { id: "cpp",           icon: "C++", title: "C++ Defaults",     sub: "Сборка, sanitizers" },
        { id: "integrations",  icon: "⎘",   title: "Integrations",     sub: "Jira, GitHub, MM" },
        { id: "data",          icon: "↯",   title: "Data",             sub: "Import / export, reset" },
        { id: "about",         icon: "?",   title: "About",            sub: "Версия, лицензии" }
    ]

    property string activeSection: "profile"
    property string searchText: ""

    // ── Settings state — single source of truth, persisted via JSON blob ──
    property var settings: ({})
    property bool _loadedOnce: false
    property bool _persisting: false
    property bool _reloading:  false

    readonly property var defaults: ({
        profile: {
            name: "Алексей Тимофеев",
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
            jira:       ({ connected: false, url: "", project: "" }),
            github:     ({ connected: false, org: "", branchTemplate: "{type}/{id}-{slug}" }),
            mattermost: ({ connected: false, workspace: "", channel: "" }),
            pagerduty:  ({ connected: false, schedule: "" }),
            confluence: ({ connected: false, space: "" })
        },
        data: { autoBackup: true, backupInterval: "daily" }
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
                    text: "Settings"
                    color: Theme.text
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Object.keys(root.settings).length + " groups · "
                          + (root.settings.profile ? root.settings.profile.handle : "")
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
                            placeholderText: "Search settings…"
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
                Text {
                    text: "todo·cpp · 0.4.2 · stable"
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
                            text: "Settings / " + (root._activeMeta().title || "")
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
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    NumberAnimation {
                        id: scrollAnim
                        target: bodyScroll
                        property: "contentY"
                        duration: 220
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

                        // Each section gets its own loader-style block
                        Loader {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            sourceComponent: {
                                if (root.activeSection === "profile")       return sectionProfile;
                                if (root.activeSection === "appearance")    return sectionAppearance;
                                if (root.activeSection === "notifications") return sectionNotifications;
                                if (root.activeSection === "calendar")      return sectionCalendar;
                                if (root.activeSection === "tasks")         return sectionTasks;
                                if (root.activeSection === "shortcuts")     return sectionShortcuts;
                                if (root.activeSection === "cpp")           return sectionCpp;
                                if (root.activeSection === "integrations")  return sectionIntegrations;
                                if (root.activeSection === "data")          return sectionData;
                                if (root.activeSection === "about")         return sectionAbout;
                                return null;
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
        property string label: ""
        property string hint: ""
        property string placeholder: ""
        property bool mono: false
        property string value: ""
        signal committed(string text)
        spacing: 4
        Layout.fillWidth: true
        FieldLabel { label: parent.label; hint: parent.hint }
        TextField {
            Layout.fillWidth: true
            text: parent.value
            placeholderText: parent.placeholder
            placeholderTextColor: Theme.textDim
            color: Theme.text
            font.family: parent.mono ? Theme.fontMono : Theme.fontUi
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            selectByMouse: true
            onTextChanged: parent.committed(text)
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
                Behavior on x { NumberAnimation { duration: 120 } }
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
        property string label: ""
        property string value: ""
        property var options: []
        signal selected(string color)
        spacing: 4
        Layout.fillWidth: true
        FieldLabel { label: parent.label }
        Row {
            spacing: 6
            Repeater {
                model: parent.parent.options
                delegate: Rectangle {
                    required property string modelData
                    width: 26; height: 26; radius: 13
                    color: modelData
                    border.color: String(parent.parent.parent.value).toLowerCase() === modelData.toLowerCase() ? Theme.text : "transparent"
                    border.width: 2
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.parent.parent.parent.selected(modelData) }
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
                                label: "Полное имя"
                                value: (root.settings.profile && root.settings.profile.name) || ""
                                onCommitted: root.set("profile", "name", text)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                TextRow {
                                    Layout.fillWidth: true
                                    label: "Handle"; mono: true; placeholder: "alex.t"
                                    value: (root.settings.profile && root.settings.profile.handle) || ""
                                    onCommitted: root.set("profile", "handle", text)
                                }
                                TextRow {
                                    Layout.fillWidth: true
                                    label: "Роль"
                                    value: (root.settings.profile && root.settings.profile.role) || ""
                                    onCommitted: root.set("profile", "role", text)
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
                            label: "Команда"
                            value: (root.settings.profile && root.settings.profile.team) || ""
                            onCommitted: root.set("profile", "team", text)
                        }
                        TextRow {
                            Layout.fillWidth: true
                            label: "Часовой пояс"; mono: true
                            value: (root.settings.profile && root.settings.profile.timezone) || ""
                            onCommitted: root.set("profile", "timezone", text)
                        }
                    }
                    SwatchRow {
                        label: "Цвет аватара"
                        value: (root.settings.profile && root.settings.profile.color) || root.avatarSwatches[0]
                        options: root.avatarSwatches
                        onSelected: root.set("profile", "color", color)
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
                        label: "Тема"
                        value: AppController.theme
                        options: [ ({ value: "dark", label: "Тёмная" }), ({ value: "light", label: "Светлая" }) ]
                        onSelected: AppController.theme = value
                    }
                    SegRow {
                        label: "Плотность интерфейса"
                        value: AppController.density
                        options: [ ({ value: "compact", label: "Compact" }), ({ value: "comfy", label: "Comfy" }) ]
                        onSelected: AppController.density = value
                    }
                    SwatchRow {
                        label: "Акцентный цвет"
                        value: (root.settings.appearance && root.settings.appearance.accent) || Theme.accent
                        options: root.accentSwatches
                        onSelected: root.set("appearance", "accent", color)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    SwitchRow {
                        label: "Reduced motion"
                        hint: "Отключить анимации и плавные переходы."
                        checked: !!(root.settings.appearance && root.settings.appearance.reducedMotion)
                        onToggled: root.set("appearance", "reducedMotion", checked)
                    }
                    SwitchRow {
                        label: "High contrast"
                        hint: "Усилить контраст текста и границ."
                        checked: !!(root.settings.appearance && root.settings.appearance.highContrast)
                        onToggled: root.set("appearance", "highContrast", checked)
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
                    Sub { label: "Дедлайны и созвоны" }
                    SwitchRow {
                        label: "Напоминать о дедлайнах"
                        hint: "Уведомлять заранее, если приближается deadline."
                        checked: !!(root.settings.notifications && root.settings.notifications.deadlineReminders)
                        onToggled: root.set("notifications", "deadlineReminders", checked)
                    }
                    SliderRow {
                        visible: !!(root.settings.notifications && root.settings.notifications.deadlineReminders)
                        label: "За сколько часов до дедлайна"
                        unit: "h"; min: 1; max: 72; step: 1
                        value: (root.settings.notifications && root.settings.notifications.deadlineLeadHours) || 24
                        onMoved: root.set("notifications", "deadlineLeadHours", value)
                    }
                    SwitchRow {
                        label: "Standup reminder"
                        hint: "Pop-up за минуты до daily standup."
                        checked: !!(root.settings.notifications && root.settings.notifications.standupReminder)
                        onToggled: root.set("notifications", "standupReminder", checked)
                    }
                    SliderRow {
                        label: "За сколько минут до встречи"
                        unit: " min"; min: 0; max: 30; step: 1
                        value: (root.settings.notifications && root.settings.notifications.meetingLead) || 5
                        onMoved: root.set("notifications", "meetingLead", value)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub { label: "Каналы доставки" }
                    SwitchRow {
                        label: "Desktop notifications"
                        checked: !!(root.settings.notifications && root.settings.notifications.desktopNotif)
                        onToggled: root.set("notifications", "desktopNotif", checked)
                    }
                    SwitchRow {
                        label: "Mattermost pings при code review"
                        hint: "Авто-пинг ревьюера, если PR висит >24 часов."
                        checked: !!(root.settings.notifications && root.settings.notifications.mmPingsOnReview)
                        onToggled: root.set("notifications", "mmPingsOnReview", checked)
                    }
                    SwitchRow {
                        label: "Daily digest по Blocked"
                        checked: !!(root.settings.notifications && root.settings.notifications.blockedDailyDigest)
                        onToggled: root.set("notifications", "blockedDailyDigest", checked)
                    }
                    SwitchRow {
                        label: "Звук при ping"
                        checked: !!(root.settings.notifications && root.settings.notifications.soundOnPing)
                        onToggled: root.set("notifications", "soundOnPing", checked)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub { label: "Quiet hours" }
                    SwitchRow {
                        label: "Не беспокоить вечером"
                        hint: "Ничего не присылать в указанное окно."
                        checked: !!(root.settings.notifications && root.settings.notifications.quietHours)
                        onToggled: root.set("notifications", "quietHours", checked)
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        visible: !!(root.settings.notifications && root.settings.notifications.quietHours)
                        TextRow {
                            Layout.fillWidth: true
                            label: "С"; mono: true; placeholder: "19:00"
                            value: (root.settings.notifications && root.settings.notifications.quietFrom) || ""
                            onCommitted: root.set("notifications", "quietFrom", text)
                        }
                        TextRow {
                            Layout.fillWidth: true
                            label: "До"; mono: true; placeholder: "09:00"
                            value: (root.settings.notifications && root.settings.notifications.quietTo) || ""
                            onCommitted: root.set("notifications", "quietTo", text)
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
                            label: "Начало недели"
                            value: (root.settings.calendar && root.settings.calendar.weekStart) || "mon"
                            options: [ ({ value: "mon", label: "Понедельник" }), ({ value: "sun", label: "Воскресенье" }) ]
                            onSelected: root.set("calendar", "weekStart", value)
                        }
                        SegRow {
                            Layout.fillWidth: true
                            label: "Формат времени"
                            value: (root.settings.calendar && root.settings.calendar.timeFormat) || "24h"
                            options: [ ({ value: "24h", label: "24h" }), ({ value: "12h", label: "12h" }) ]
                            onSelected: root.set("calendar", "timeFormat", value)
                        }
                    }
                    Sub { label: "Рабочие часы" }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        SliderRow {
                            Layout.fillWidth: true
                            label: "Начало"; unit: ":00"; min: 6; max: 12; step: 1
                            value: AppController.workdayStart
                            onMoved: AppController.workdayStart = value
                        }
                        SliderRow {
                            Layout.fillWidth: true
                            label: "Окончание"; unit: ":00"; min: 14; max: 23; step: 1
                            value: AppController.workdayEnd
                            onMoved: AppController.workdayEnd = value
                        }
                    }
                    SegRow {
                        label: "Сетка слотов"
                        value: String((root.settings.calendar && root.settings.calendar.snapMinutes) || 15)
                        options: [ ({ value: "5", label: "5 min" }), ({ value: "15", label: "15 min" }), ({ value: "30", label: "30 min" }) ]
                        onSelected: root.set("calendar", "snapMinutes", parseInt(value))
                    }
                    SwitchRow {
                        label: "Показывать выходные"
                        checked: !!(root.settings.calendar && root.settings.calendar.showWeekends)
                        onToggled: root.set("calendar", "showWeekends", checked)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub { label: "Focus time" }
                    SwitchRow {
                        label: "Автоматически создавать focus-блок"
                        hint: "Когда задача переходит в In Progress — добавлять блок в календарь."
                        checked: !!(root.settings.calendar && root.settings.calendar.autoFocusBlock)
                        onToggled: root.set("calendar", "autoFocusBlock", checked)
                    }
                    SliderRow {
                        visible: !!(root.settings.calendar && root.settings.calendar.autoFocusBlock)
                        label: "Длительность focus-блока"
                        unit: " min"; min: 30; max: 240; step: 15
                        value: (root.settings.calendar && root.settings.calendar.focusBlockDuration) || 90
                        onMoved: root.set("calendar", "focusBlockDuration", value)
                    }
                    TextRow {
                        label: "Время daily standup"; mono: true; placeholder: "10:00"
                        value: (root.settings.calendar && root.settings.calendar.standupTime) || ""
                        onCommitted: root.set("calendar", "standupTime", text)
                    }
                }
            }
        }
    }

    Component {
        id: sectionTasks
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        TextRow {
                            Layout.fillWidth: true
                            label: "Префикс ID"; mono: true; placeholder: "LTE"
                            hint: "Новые задачи: " + ((root.settings.tasks && root.settings.tasks.idPrefix) || "LTE") + "-XXXX"
                            value: (root.settings.tasks && root.settings.tasks.idPrefix) || ""
                            onCommitted: root.set("tasks", "idPrefix", text.toUpperCase())
                        }
                        SegRow {
                            Layout.fillWidth: true
                            label: "Дефолтный приоритет"
                            value: (root.settings.tasks && root.settings.tasks.defaultPriority) || "P2"
                            options: ["P0", "P1", "P2", "P3"]
                            onSelected: root.set("tasks", "defaultPriority", value)
                        }
                    }
                    SegRow {
                        label: "Дефолтная колонка"
                        value: (root.settings.tasks && root.settings.tasks.defaultStatus) || "todo"
                        options: [ ({ value: "backlog", label: "Backlog" }), ({ value: "todo", label: "To Do" }), ({ value: "prog", label: "In Progress" }) ]
                        onSelected: root.set("tasks", "defaultStatus", value)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub { label: "Автоматизации" }
                    SliderRow {
                        label: "Архивировать Done через"
                        unit: " дн"; min: 0; max: 30; step: 1
                        hint: "0 — никогда не архивировать."
                        value: (root.settings.tasks && root.settings.tasks.archiveDoneAfterDays) || 0
                        onMoved: root.set("tasks", "archiveDoneAfterDays", value)
                    }
                    SliderRow {
                        label: "Подсвечивать Blocked после"
                        unit: " дн"; min: 1; max: 14; step: 1
                        hint: "Задача в Blocked дольше — отмечается красным."
                        value: (root.settings.tasks && root.settings.tasks.autoMoveBlockedAfterDays) || 3
                        onMoved: root.set("tasks", "autoMoveBlockedAfterDays", value)
                    }
                    SwitchRow {
                        label: "Требовать branch перед Code Review"
                        hint: "Запрещать перевод задачи в Review без branch name."
                        checked: !!(root.settings.tasks && root.settings.tasks.requireBranchOnReview)
                        onToggled: root.set("tasks", "requireBranchOnReview", checked)
                    }
                    SwitchRow {
                        label: "Показывать subtasks"
                        checked: !!(root.settings.tasks && root.settings.tasks.showSubtasks)
                        onToggled: root.set("tasks", "showSubtasks", checked)
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
                        Sub { label: "Горячие клавиши" }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            radius: 6; implicitWidth: openTxt.implicitWidth + 18; implicitHeight: 26
                            color: openMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            Text { id: openTxt; anchors.centerIn: parent; text: "Открыть панель Hotkeys ↗"; color: Theme.text; font.pixelSize: 11 }
                            MouseArea { id: openMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settingsBridge.openHotkeysRequested() }
                        }
                    }
                    Text {
                        text: "Полный список с capture-режимом перебинда — в отдельной панели Hotkeys (Ctrl+/). Ниже — текущие значения только для просмотра."
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
                                Text { id: seqText; anchors.centerIn: parent; text: modelData.sequence || "(не задан)"; color: modelData.sequence ? Theme.text : Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 11 }
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
                            label: "Компилятор"
                            value: (root.settings.cpp && root.settings.cpp.defaultCompiler) || "clang-17"
                            options: ["gcc-13", "clang-17", "clang-18"]
                            onSelected: root.set("cpp", "defaultCompiler", value)
                        }
                        SegRow {
                            Layout.fillWidth: true
                            label: "Стандарт C++"
                            value: (root.settings.cpp && root.settings.cpp.defaultStandard) || "C++20"
                            options: ["C++17", "C++20", "C++23"]
                            onSelected: root.set("cpp", "defaultStandard", value)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        SegRow {
                            Layout.fillWidth: true
                            label: "Sanitizer"
                            value: (root.settings.cpp && root.settings.cpp.defaultSanitizer) || "asan"
                            options: [ ({ value: "none", label: "None" }), ({ value: "asan", label: "ASan" }), ({ value: "tsan", label: "TSan" }), ({ value: "ubsan", label: "UBSan" }) ]
                            onSelected: root.set("cpp", "defaultSanitizer", value)
                        }
                        SegRow {
                            Layout.fillWidth: true
                            label: "Build type"
                            value: (root.settings.cpp && root.settings.cpp.defaultBuildType) || "RelWithDebInfo"
                            options: ["Debug", "RelWithDebInfo", "Release"]
                            onSelected: root.set("cpp", "defaultBuildType", value)
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    TextRow {
                        label: "Bazel args"; mono: true; placeholder: "--jobs=12 --keep_going"
                        value: (root.settings.cpp && root.settings.cpp.bazelArgs) || ""
                        onCommitted: root.set("cpp", "bazelArgs", text)
                    }
                    TextRow {
                        label: "Compiler Explorer URL"; mono: true; placeholder: "https://godbolt.org/"
                        value: (root.settings.cpp && root.settings.cpp.compilerExplorerUrl) || ""
                        onCommitted: root.set("cpp", "compilerExplorerUrl", text)
                    }
                    SwitchRow {
                        label: "Inline ASM preview"
                        hint: "Показывать компиляторный вывод прямо в task card."
                        checked: !!(root.settings.cpp && root.settings.cpp.showAsmInline)
                        onToggled: root.set("cpp", "showAsmInline", checked)
                    }
                }
            }
        }
    }

    Component {
        id: sectionIntegrations
        ColumnLayout {
            spacing: 12
            Repeater {
                model: [
                    { key: "jira",       name: "Jira",       icon: "J", color: "#5aa3e6", desc: "Sync задач, ID prefix, статусов" },
                    { key: "github",     name: "GitHub",     icon: "◯", color: "#5a6371", desc: "PR статус, branch template, code-review pings" },
                    { key: "mattermost", name: "Mattermost", icon: "#", color: "#c07acf", desc: "Notification routing, follow-ups" },
                    { key: "pagerduty",  name: "PagerDuty",  icon: "!", color: "#6ec18a", desc: "On-call schedule, incident escalation" },
                    { key: "confluence", name: "Confluence", icon: "§", color: "#5aa3e6", desc: "Wiki + runbooks, link previews" }
                ]
                delegate: SectionCard {
                    required property var modelData
                    ColumnLayout {
                        spacing: 10
                        Layout.fillWidth: true
                        RowLayout {
                            Layout.fillWidth: true
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
                                Text { text: modelData.desc; color: Theme.textMuted; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                            readonly property var conf: (root.settings.integrations && root.settings.integrations[modelData.key]) || ({})
                            Text {
                                text: parent.conf.connected ? "● connected" : "○ disconnected"
                                color: parent.conf.connected ? Theme.mFocus : Theme.textDim
                                font.family: Theme.fontMono; font.pixelSize: 10
                            }
                            Rectangle {
                                radius: 6
                                color: parent.conf.connected
                                       ? (toggleMA.containsMouse ? Theme.panel3 : Theme.panel2)
                                       : (toggleMA.containsMouse ? Theme.accentStrong : Theme.accent)
                                border.color: parent.conf.connected ? Theme.border : Theme.accent
                                border.width: 1
                                implicitWidth: toggleTxt.implicitWidth + 18; implicitHeight: 26
                                Text { id: toggleTxt; anchors.centerIn: parent; text: parent.parent.conf.connected ? "Disconnect" : "Connect"; color: parent.parent.conf.connected ? Theme.text : "#06121a"; font.pixelSize: 11; font.weight: Font.Medium }
                                MouseArea {
                                    id: toggleMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setNested("integrations", modelData.key, "connected", !parent.parent.conf.connected)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sectionData
        ColumnLayout {
            spacing: 16
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub { label: "Резервные копии" }
                    SwitchRow {
                        label: "Auto backup"
                        hint: "Сохранять снапшоты state.json в <AppData>/backups (раз в 5 минут, до 20 копий)."
                        checked: !!(root.settings.data && root.settings.data.autoBackup)
                        onToggled: root.set("data", "autoBackup", checked)
                    }
                    SegRow {
                        visible: !!(root.settings.data && root.settings.data.autoBackup)
                        label: "Интервал"
                        value: (root.settings.data && root.settings.data.backupInterval) || "daily"
                        options: [ ({ value: "hourly", label: "Каждый час" }), ({ value: "daily", label: "Каждый день" }), ({ value: "weekly", label: "Раз в неделю" }) ]
                        onSelected: root.set("data", "backupInterval", value)
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub { label: "Импорт / экспорт активного профиля" }
                    Text {
                        text: "Экспортирует / импортирует JSON-файл с задачами, людьми, доками и notes текущего профиля."
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
                            Text { id: expTxt; anchors.centerIn: parent; text: "↓ Export as JSON"; color: Theme.text; font.pixelSize: 12 }
                            MouseArea { id: expMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settingsBridge.exportJsonRequested() }
                        }
                        Rectangle {
                            radius: 6
                            color: impMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            implicitWidth: impTxt.implicitWidth + 24; implicitHeight: 30
                            Text { id: impTxt; anchors.centerIn: parent; text: "↑ Import from JSON"; color: Theme.text; font.pixelSize: 12 }
                            MouseArea { id: impMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settingsBridge.importJsonRequested() }
                        }
                    }
                }
            }
            SectionCard {
                ColumnLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Sub { label: "Опасная зона" }
                    DangerRow {
                        title: "Сбросить все настройки"
                        hint: "Откатить к значениям по умолчанию. Профили, задачи и заметки останутся."
                        buttonText: "Reset all"
                        onTriggered: root.resetAll()
                    }
                }
            }
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
                        Rectangle {
                            width: 36; height: 36; radius: 8
                            color: Theme.accent
                        }
                        ColumnLayout {
                            spacing: 1
                            Text { text: "todo·cpp"; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 16; font.weight: Font.DemiBold }
                            Text { text: "A C++ programmer's day, structured."; color: Theme.textMuted; font.pixelSize: 11 }
                        }
                    }
                    ColumnLayout {
                        spacing: 6
                        Layout.topMargin: 4
                        Layout.fillWidth: true
                        AboutRow { label: "Version"; value: "0.4.2 — build 240617" }
                        AboutRow { label: "Channel"; value: "stable" }
                        AboutRow { label: "Storage"; value: "~/.local/share/todocpp" }
                        AboutRow { label: "Engine";  value: "Qt 6.4 + QML" }
                    }
                }
            }
        }
    }

    component AboutRow: RowLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 16
        Text { text: parent.parent.label; color: Theme.textMuted; font.pixelSize: 11; Layout.preferredWidth: 80 }
        Text { text: parent.parent.value; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11; Layout.fillWidth: true }
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
