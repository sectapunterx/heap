pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp
import "QueryWords.js" as QueryWords

// The header of the content column (heap 2, APP-258): the section's title,
// its lenses (Tasks: Board / List / Calendar; Knowledge: Notes / Links), the
// git focus banner and focus mode, and the task search. The profile, "+ Task"
// and the right panel's toggle that the old top bar carried moved to the
// sidebar, the "New task" field and the Today screen.
Rectangle {
    id: root
    objectName: "view-header"
    color: Theme.bg

    // The current section and view, handed in by Main.
    property string section: "tasks"
    property string view: "board"
    readonly property string title: section === "today" ? I18n.t("sidebar.today")
                                  : section === "knowledge" ? I18n.t("sidebar.knowledge")
                                  : section === "settings" ? I18n.t("sidebar.settings")
                                  : I18n.t("sidebar.tasks")
    readonly property var lenses: section === "tasks"
        ? [{ id: "board", label: I18n.t("lens.board"), keys: "g b" },
           { id: "list", label: I18n.t("lens.list"), keys: "g l" },
           { id: "calendar", label: I18n.t("lens.calendar"), keys: "g c" }]
        : []
    readonly property string lens: view === "timeline" ? "list"
                                 : (view === "day" || view === "week" || view === "month") ? "calendar"
                                 : view
    signal lensSelected(string id)
    // The lens's own setting, shown beside the tabs (see optionBtn).
    property var option: null
    signal optionPicked(string id)
    // The calendar's zoom (APP-264): day / week / month, keys z d / z w / z m.
    signal zoomSelected(string id)
    readonly property var zooms: [{ id: "day", label: I18n.t("calzoom.day"), keys: "z d" },
                                  { id: "week", label: I18n.t("calzoom.week"), keys: "z w" },
                                  { id: "month", label: I18n.t("calzoom.month"), keys: "z m" }]
    readonly property bool _quietNav: lens === "calendar" && !Style.fills
    // The task search belongs to the views that list tasks.
    // The calendar sheets draw no query row (H2/Q-Calendar): there it shows
    // only while a query holds something or is being typed (Ctrl F, type
    // to search), so a filter on the grid is never invisible.
    property bool _queryOpened: false
    onLensChanged: _queryOpened = false
    property bool searchShown: section === "tasks"
    // The calendar sheets have no query line and no count (DG-046). A query
    // beyond the default "не готово" still shows there: a filter is never
    // at work out of sight.
    readonly property bool _beyondDefault: root.searchText.replace(/(^|\s)is:open(?=\s|$)/gi, " ").trim().length > 0
    readonly property bool queryShown: searchShown && (lens !== "calendar" || root._beyondDefault || root._queryOpened)
    // The board is one profile's: the sheet names it as a chip (DG-020).
    property string profileName: ""
    readonly property bool profileChipShown: lens === "board" && profileName.length > 0
    signal profileChipClicked()
    // Quiet (Q-Board / Q-List, DG-021): the conditions are a row of plain
    // outline chips and "изменить фильтр"; the field opens on that link or
    // on "/", and folds back when the keyboard leaves it.
    property bool editing: false
    readonly property bool _boxed: Style.fills || root.editing

    // The whole query: the conditions shown as chips, then what is still
    // being typed (APP-261). Set from outside (a saved view, a link) it is
    // split again into chips and the rest.
    property string searchText: ""
    // Clauses ("status:blocked", "due:week"), space-separated; drawn as chips.
    property string _committed: ""
    property bool _sync: false
    onSearchTextChanged: if (!root._sync) root._split(root.searchText)
    // The count under the query ("14 tasks"), from Main.
    property int resultCount: -1
    signal saveViewRequested()
    // Parse-only, so this costs nothing per keystroke — it never touches the
    // task list, unlike the filtering itself.
    readonly property bool searchIsQuery: AppController.searchIsQuery(root.searchText)
    // Clauses that mean nothing ("stauts:x", an unknown column, "due:banana"):
    // shown on the badge, so a typo does not read as an empty board.
    readonly property var searchProblems: AppController.searchProblems(root.searchText)

    function _tokens(t) { return String(t || "").match(/"[^"]*"|\S+/g) || []; }
    function _isClause(tok) { return /^-?[a-z]+:\S+$/i.test(tok); }
    function _split(t) {
        const toks = root._tokens(t);
        // An OR query stays as typed: its parts belong together.
        const chips = toks.indexOf("OR") >= 0 ? [] : toks.filter(root._isClause);
        const rest = toks.indexOf("OR") >= 0 ? toks : toks.filter(x => !root._isClause(x));
        root._sync = true;
        root._committed = chips.join(" ");
        searchField.text = rest.join(" ");
        root._sync = false;
    }
    function _compose() {
        root._sync = true;
        root.searchText = [root._committed, searchField.text].filter(x => x.length > 0).join(" ");
        root._sync = false;
    }
    // A finished "key:value " moves out of the field into a chip.
    function _onTyped() {
        if (root._sync) return;
        const m = /^(.*?)(-?[a-z]+:\S+)\s$/i.exec(searchField.text);
        if (m && searchField.text.indexOf(" OR ") < 0) {
            root._sync = true;
            root._committed = [root._committed, m[2]].filter(x => x.length > 0).join(" ");
            searchField.text = m[1].trim();
            root._sync = false;
        }
        root._compose();
    }
    function removeCondition(i) {
        const list = root._tokens(root._committed);
        list.splice(i, 1);
        root._committed = list.join(" ");
        root._compose();
    }
    function clearQuery() {
        root._committed = "";
        searchField.text = "";
        root._compose();
    }
    readonly property var conditions: root._tokens(root._committed).map(root._chip)
    // A clause as a chip: a word for the field, a word for the value.
    function _chip(raw) {
        const c = QueryWords.clause(raw) || { key: I18n.t("query.key.other"), value: raw };
        const bad = root.searchProblems.indexOf(raw) >= 0;
        return { key: c.key, value: c.value + (bad ? " · " + I18n.t("query.unknown") : ""), raw: raw, bad: bad };
    }
    // The "seen this before" hint under the search was clicked (APP-159).
    signal seenBeforeActivated(var hit)
    // Esc on an empty search box, or Return in it: give the keyboard back.
    signal leaveRequested()
    // Quiet folds the field back into its chips when the keyboard is handed
    // back (Esc on an empty field, Return) or the lens changes; not on a
    // plain focus loss, which its own right-click menu causes too.
    onLeaveRequested: if (searchField.text.length === 0) root.editing = false
    onViewChanged: if (searchField.text.length === 0) root.editing = false

    function focusSearch() {
        root._queryOpened = true;
        root.editing = true;
        searchField.forceActiveFocus();
        searchField.selectAll();
    }
    function focusEnd() {
        root._queryOpened = true;
        root.editing = true;
        searchField.forceActiveFocus();
        searchField.cursorPosition = searchField.text.length;
    }
    // Type to search (APP-117): the first letter typed on the board starts a
    // fresh search with it, and the rest follow into the field.
    function typeAhead(text) {
        root._queryOpened = true;
        root.editing = true;
        searchField.text = text;
        searchField.forceActiveFocus();
        searchField.cursorPosition = searchField.text.length;
    }
    implicitHeight: headCol.implicitHeight + headCol.anchors.topMargin + headCol.anchors.bottomMargin

    ColumnLayout {
        id: headCol
        anchors.fill: parent
        anchors.leftMargin: root.section === "tasks" ? Theme.pagePadX : Theme.sp2xl
        anchors.rightMargin: root.section === "tasks" ? Theme.pagePadX : Theme.sp2xl
        anchors.topMargin: root.section === "tasks" ? Theme.pagePadTop : Theme.spLg
        anchors.bottomMargin: root.section === "tasks" ? Theme.px(14) : Theme.spLg
        spacing: Style.fills ? Theme.px(14) : Theme.spMd
    RowLayout {
        id: headRow
        Layout.fillWidth: true
        // Q-Board: 28px from the title to the tabs (R3-032).
        spacing: Style.fills ? Theme.spXl : Theme.px(28)

        Text {
            objectName: "view-header-title"
            Layout.alignment: Style.fills ? Qt.AlignVCenter : Qt.AlignBaseline
            text: root.title
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsScreenTitle
            font.weight: Theme.fwScreenTitle
            Accessible.role: Accessible.Heading
            Accessible.name: root.title
        }
        LensTabs {
            id: lensTabs
            objectName: "view-header-lenses"
            Layout.alignment: Style.fills ? Qt.AlignVCenter : Qt.AlignBaseline
            visible: root.lenses.length > 0
            model: root.lenses
            current: root.lens
            onSelected: (id) => root.lensSelected(id)
        }
        // The lens's own setting beside the tabs (H2-List): "Group: by date"
        // on the list, the sort on the board. { label, value, current,
        // items: [{ id, label }] } from Main; a pick comes back as optionPicked.
        Rectangle {
            id: optionBtn
            objectName: "view-header-option"
            // Quiet draws it as a chip in the conditions row (DG-021).
            visible: !!root.option && root.section === "tasks" && Style.fills
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Theme.chipH
            implicitWidth: optionRow.implicitWidth + 2 * Theme.spLg
            radius: Theme.radiusMd
            color: optionArea.hovered || optionMenu.visible ? Theme.surfaceCardHover : Theme.chipBg
            border.width: 1
            border.color: Theme.chipBorder
            Row {
                id: optionRow
                anchors.centerIn: parent
                spacing: Theme.spXs
                Text {
                    text: root.option ? root.option.label + ":" : ""
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
                Text {
                    objectName: "view-header-option-value"
                    text: root.option ? root.option.value : ""
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
            }
            ClickArea {
                id: optionArea
                label: root.option ? root.option.label + " " + root.option.value : ""
                showTip: false
                onActivated: optionMenu.popup(optionBtn, 0, optionBtn.height + Theme.spXs)
            }
            AppMenu {
                id: optionMenu
                objectName: "view-header-option-menu"
                Instantiator {
                    model: root.option ? root.option.items : []
                    delegate: AppMenuItem {
                        required property var modelData
                        objectName: "view-header-option-" + modelData.id
                        text: modelData.label
                        checkable: true
                        checked: !!root.option && root.option.current === modelData.id
                        onTriggered: root.optionPicked(modelData.id)
                    }
                    onObjectAdded: (index, object) => optionMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => optionMenu.removeItem(object)
                }
            }
        }
        // The calendar's zoom (DG-044): a segmented group after the tabs in
        // bold (H2-Calendar), lowercase words at the right in quiet.
        Rectangle {
            objectName: "view-header-zoom"
            visible: root.lens === "calendar" && Style.fills
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: zoomSeg.implicitWidth + 2 * Theme.sp2xs
            implicitHeight: Theme.chipH
            radius: Theme.radiusLg
            color: "transparent"
            border.width: 1
            border.color: Theme.buttonLine
            Row {
                id: zoomSeg
                anchors.centerIn: parent
                spacing: Theme.sp2xs
                Repeater {
                    model: root.zooms
                    delegate: Rectangle {
                        id: seg
                        required property var modelData
                        readonly property bool on: root.view === seg.modelData.id
                        objectName: "zoom-" + seg.modelData.id
                        width: segText.implicitWidth + 2 * Theme.spLg
                        height: Theme.chipH - 2 * Theme.sp2xs - 2
                        radius: Theme.radiusMd
                        color: seg.on ? Theme.segmentSelected : (segCA.hovered ? Theme.panel2 : "transparent")
                        Text {
                            id: segText
                            anchors.centerIn: parent
                            text: seg.modelData.label
                            color: seg.on ? Theme.segmentSelectedText : Theme.textMuted
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsSm
                            font.weight: seg.on ? Theme.fwHeading : Theme.fwBody
                        }
                        ClickArea {
                            id: segCA
                            label: seg.modelData.label
                            tip: seg.modelData.label + "  " + seg.modelData.keys
                            role: Accessible.RadioButton
                            checkable: true
                            checked: seg.on
                            onActivated: root.zoomSelected(seg.modelData.id)
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        CalendarNav {
            id: calendarNav
            visible: root.lens === "calendar" && Style.fills
            Layout.alignment: Qt.AlignVCenter
            zoom: root.view
        }
        Row {
            objectName: "view-header-zoom-words"
            visible: root.lens === "calendar" && !Style.fills
            Layout.alignment: Qt.AlignVCenter
            Repeater {
                model: root.zooms
                delegate: Row {
                    id: word
                    required property var modelData
                    required property int index
                    readonly property bool on: root.view === word.modelData.id
                    Text {
                        visible: word.index > 0
                        text: " · "
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsMd
                    }
                    Text {
                        objectName: "zoom-" + word.modelData.id
                        text: word.modelData.label.toLowerCase()
                        color: word.on || wordCA.hovered ? Theme.text : Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsMd
                        font.weight: word.on ? Theme.fwTitle : Theme.fwBody
                        ClickArea {
                            id: wordCA
                            label: word.modelData.label
                            tip: word.modelData.label + "  " + word.modelData.keys
                            role: Accessible.RadioButton
                            checkable: true
                            checked: word.on
                            onActivated: root.zoomSelected(word.modelData.id)
                        }
                    }
                }
            }
        }

        // Git focus banner — appears when GitWatcher detects a checkout
        // matching a registered task prefix. Dismiss persists until next
        // branchChanged.
        Rectangle {
            id: gitBanner
            visible: AppController.focusedTaskId.length > 0
                  && !AppController.focusedBannerDismissed
                  && Theme.gitWorkingLine
            Layout.preferredHeight: 26
            Layout.alignment: Qt.AlignVCenter
            radius: Theme.radiusMd
            color: Theme.accentSoft
            border.color: Theme.accent
            border.width: 1
            implicitWidth: bannerRow.implicitWidth + 14
            RowLayout {
                id: bannerRow
                anchors.fill: parent
                anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spSm
                spacing: Theme.spMd
                Icon {
                    name: "branch"
                    color: Theme.accentStrong
                }
                Text {
                    text: I18n.t("topbar.git.workingOn").arg(AppController.focusedTaskId)
                    color: Theme.accentStrong
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsMd
                    font.weight: Theme.fwTitle
                }
                // ── Live PR state on the focused repo (HEAP-76) ──
                Rectangle {
                    id: prBadge
                    property var pr: AppController.focusedRepoState
                                     ? AppController.focusedRepoState.pr : null
                    // !! — with no PR the leading `pr &&` yields null, and QML
                    // logs "Unable to assign [undefined] to bool" on every start.
                    visible: !!(pr && String(pr.state || "").length > 0
                                   && Number(pr.number || 0) > 0)
                    radius: Theme.radiusSm
                    implicitWidth: prBadgeT.implicitWidth + 12
                    implicitHeight: 18
                    color: {
                        const s = prBadge.pr ? String(prBadge.pr.state || "") : "";
                        if (s === "merged") return Theme.withAlpha(Theme.success, 0.16);
                        if (s === "closed") return Theme.withAlpha(Theme.textDim, 0.16);
                        return Theme.withAlpha(Theme.info, 0.16);
                    }
                    border.width: 1
                    border.color: {
                        const s = prBadge.pr ? String(prBadge.pr.state || "") : "";
                        if (s === "merged") return Theme.success;
                        if (s === "closed") return Theme.textDim;
                        return Theme.info;
                    }
                    Text {
                        id: prBadgeT
                        anchors.centerIn: parent
                        text: {
                            if (!prBadge.pr) return "";
                            const n = prBadge.pr.number || 0;
                            const s = String(prBadge.pr.state || "");
                            const d = prBadge.pr.draft === true ? " · " + I18n.t("topbar.pr.draft") : "";
                            const st = s === "open" || s === "merged" || s === "closed" ? I18n.t("topbar.pr." + s) : s;
                            return "PR #" + n + " " + st + d;
                        }
                        color: Theme.accentStrong
                        font.family: Theme.fontUi
                        font.features: Theme.tabularNums
                        font.pixelSize: Theme.fsXs
                        font.weight: Theme.fwTitle
                    }
                    ClickArea {
                        objectName: "topbar-pr-badge"
                        enabled: !!(prBadge.pr && prBadge.pr.url)
                        label: prBadgeT.text
                        tip: I18n.t("topbar.pr.openTip")
                        onActivated: Qt.openUrlExternally(prBadge.pr.url)
                    }
                }
                // ── CI check rollup on the focused repo (HEAP-76) ──
                Rectangle {
                    id: ciBadge
                    property string ci: (AppController.focusedRepoState
                                         && AppController.focusedRepoState.pr)
                        ? String(AppController.focusedRepoState.pr.checks || "") : ""
                    visible: ci.length > 0
                    radius: Theme.radiusSm
                    implicitWidth: ciT.implicitWidth + 12
                    implicitHeight: 18
                    color: {
                        if (ciBadge.ci === "passing") return Theme.withAlpha(Theme.success, 0.16);
                        if (ciBadge.ci === "failing") return Theme.withAlpha(Theme.danger, 0.16);
                        return Theme.withAlpha(Theme.warning, 0.16);
                    }
                    border.width: 1
                    border.color: {
                        if (ciBadge.ci === "passing") return Theme.success;
                        if (ciBadge.ci === "failing") return Theme.danger;
                        return Theme.warning;
                    }
                    Text {
                        id: ciT
                        anchors.centerIn: parent
                        // Words, not glyphs (DG-003).
                        text: "CI " + I18n.t(ciBadge.ci === "passing" ? "topbar.ci.passing"
                                             : ciBadge.ci === "failing" ? "topbar.ci.failing" : "topbar.ci.running")
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.features: Theme.tabularNums
                        font.pixelSize: Theme.fsXs
                        font.weight: Theme.fwTitle
                    }
                }
                Rectangle {
                    radius: Theme.radiusSm
                    color: openMA.hovered ? Theme.accentStrong : "transparent"
                    border.color: Theme.accentStrong
                    border.width: 1
                    implicitWidth: openT.implicitWidth + 12
                    implicitHeight: 18
                    Text {
                        id: openT
                        anchors.centerIn: parent
                        text: I18n.t("topbar.git.open")
                        color: openMA.hovered ? Theme.bg : Theme.accentStrong
                        font.pixelSize: Theme.fsXs
                        font.weight: Theme.fwTitle
                    }
                    ClickArea {
                        id: openMA
                        objectName: "topbar-git-open"
                        label: I18n.t("topbar.git.open")
                        showTip: false
                        onActivated: AppController.openFocusedTask()
                    }
                }
                // Dismiss. The hit area used to be the glyph's own bounds —
                // roughly 8x16px — so the banner was hard to get rid of.
                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: Theme.radiusSm
                    color: dismissMA.hovered ? Theme.withAlpha(Theme.accentStrong, 0.18) : "transparent"
                    Icon {
                        anchors.centerIn: parent
                        name: "close"
                        size: Theme.px(12)
                        color: dismissMA.hovered ? Theme.accentStrong : Theme.textDim
                    }
                    ClickArea {
                        id: dismissMA
                        objectName: "topbar-git-dismiss"
                        label: I18n.t("topbar.git.dismiss")
                        onActivated: AppController.dismissGitBanner()
                    }
                }
            }
        }

        // Focus mode is on (APP-160): how long, quietly; a click leaves it.
        Rectangle {
            id: immersionPill
            objectName: "topbar-immersion"
            visible: AppController.immersion
            Layout.preferredHeight: 24
            Layout.preferredWidth: immersionRow.implicitWidth + 2 * Theme.spLg
            radius: Theme.radiusMd
            color: immersionMA.hovered ? Theme.panel3 : Theme.accentSoft
            border.color: Theme.accent
            border.width: 1
            property int _tick: 0
            Timer {
                interval: 1000
                repeat: true
                running: AppController.immersion
                onTriggered: immersionPill._tick++
            }
            function _elapsed() {
                immersionPill._tick;
                const start = AppController.immersionStartedAt;
                if (!start || !start.getTime) return "0:00";
                const s = Math.max(0, Math.floor((Date.now() - start.getTime()) / 1000));
                const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
                const p2 = (n) => (n < 10 ? "0" : "") + n;
                return h > 0 ? h + ":" + p2(m) + ":" + p2(sec) : m + ":" + p2(sec);
            }
            RowLayout {
                id: immersionRow
                anchors.centerIn: parent
                spacing: Theme.spSm
                Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: Theme.accentStrong }
                Text {
                    text: I18n.t("immersion.on")
                    color: Theme.accentStrong
                    font.pixelSize: Theme.fsXs
                    font.weight: Theme.fwTitle
                }
                Text {
                    objectName: "topbar-immersion-time"
                    text: immersionPill._elapsed()
                    color: Theme.accentStrong
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsXs
                }
            }
            ClickArea {
                id: immersionMA
                objectName: "topbar-immersion-exit"
                label: I18n.t("immersion.exit")
                onActivated: AppController.stopImmersion()
            }
        }

        // "14 tasks" under the query.
        Text {
            objectName: "view-header-count"
            visible: root.queryShown && Style.counters && root.resultCount >= 0
            text: I18n.count(Math.max(0, root.resultCount), "query.n.tasks")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.features: Theme.tabularNums
            font.pixelSize: Theme.fsSm
        }
    }

        // Quiet calendar: "‹ 5 – 11 октября ›" under the title (Q-Calendar).
        CalendarNav {
            objectName: "calendar-nav-quiet"
            visible: root.lens === "calendar" && !Style.fills
            zoom: root.view
        }

        // The query (APP-261): conditions as chips (× drops one), then the
        // field in the same language as quick capture; "Save as view".
        Rectangle {
            id: queryRow
            objectName: "view-header-query"
            visible: root.queryShown && root._boxed
            Layout.fillWidth: true
            implicitHeight: Math.max(Theme.chipH + 2 * Theme.spSm, queryFlow.implicitHeight + 2 * Theme.spSm)
            radius: Theme.radiusLg
            color: Style.chipFill ? Theme.panel : "transparent"
            border.color: searchField.activeFocus ? Theme.focusRing : Theme.border
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spLg
                spacing: Theme.spMd
                // The sheets' funnel (DG-003); lights up while the text
                // holds a clause.
                Icon {
                    objectName: "view-header-query-icon"
                    name: "filter"
                    color: Theme.textDim
                    size: Theme.px(14)
                    Layout.alignment: Qt.AlignVCenter
                }
                Flow {
                    id: queryFlow
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Theme.spSm
                    // The chips as one group, so the field's width follows
                    // their width and not its own place in the flow (which
                    // fed back into itself and wrapped the field).
                    Row {
                    id: chipsRow
                    spacing: Theme.spSm
                    Repeater {
                        model: root.conditions
                        delegate: PropertyChip {
                            id: qc
                            required property var modelData
                            required property int index
                            objectName: "query-chip-" + qc.index
                            small: true
                            removable: true
                            key: qc.modelData.key
                            value: qc.modelData.value
                            valueColor: qc.modelData.bad ? Theme.warning : Theme.text
                            onRemoved: root.removeCondition(qc.index)
                        }
                    }
                    // The board's profile (H2-Board): the scope, not a clause
                    // of the query; a click opens the profile switcher.
                    PropertyChip {
                        objectName: "query-chip-profile"
                        visible: root.profileChipShown
                        small: true
                        key: I18n.t("query.key.profile")
                        value: root.profileName
                        onClicked: root.profileChipClicked()
                    }
                    }
                    Item {
                        width: Math.max(Theme.px(200), queryFlow.width - (chipsRow.width > 0 ? chipsRow.width + queryFlow.spacing : 0))
                        height: Theme.chipHSmall
                        // A plain holder: the row draws the box. As a
                        // transparent Rectangle it filled black on Windows.
                        Item {
                            id: searchBox
                            anchors.fill: parent
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spSm
                spacing: Theme.spXs
                // The row's funnel says the field is a query (one icon, not
                // a second one here: DG-003).
                TextField {
                    id: searchField
                    ContextMenu.menu: TextEditMenu { editor: searchField }
                    objectName: "topbar-search"
                    onActiveFocusChanged: if (!activeFocus && root.searchText.length === 0) root._queryOpened = false
                    Layout.fillWidth: true
                    placeholderText: I18n.t("query.placeholder")
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    background: Item {}
                    selectByMouse: true
                    // Esc clears what was typed, and a second Esc (or Return)
                    // hands the keyboard back to the view, so the board cursor
                    // can walk what the search left. It used to do neither.
                    onTextChanged: root._onTyped()
                    Keys.onEscapePressed: (event) => {
                        if (searchField.text.length > 0) searchField.clear();
                        else root.leaveRequested();
                        event.accepted = true;
                    }
                    // Backspace on an empty field takes the last condition back.
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Backspace && searchField.text.length === 0 && root.conditions.length > 0) {
                            root.removeCondition(root.conditions.length - 1);
                            event.accepted = true;
                        }
                    }
                    Keys.onReturnPressed: root.leaveRequested()
                    Keys.onEnterPressed: root.leaveRequested()
                    // The syntax is only discoverable if something says it out
                    // loud; the field itself is the only place the user looks.
                    QQC.ToolTip.visible: searchField.activeFocus && searchField.text.length === 0
                    QQC.ToolTip.delay: 600
                    QQC.ToolTip.text: I18n.t("topbar.searchQueryHint").arg(AppController.searchFields().join(": · ") + ":")
                                                        .arg(AppController.shortcutText("palette.open"))
                }
                // Clause count is not worth showing; that it *is* a query is.
                Rectangle {
                    objectName: "search-query-badge"
                    readonly property bool bad: root.searchProblems.length > 0
                    visible: bad
                    radius: Theme.radiusSm
                    color: bad ? Theme.withAlpha(Theme.warning, 0.14) : Theme.accentSoft
                    border.color: bad ? Theme.warning : Theme.accent
                    border.width: 1
                    width: qLbl.implicitWidth + 10; height: 16
                    Text {
                        id: qLbl
                        anchors.centerIn: parent
                        text: parent.bad ? "?" + root.searchProblems.length : I18n.t("topbar.searchQueryBadge")
                        color: parent.bad ? Theme.warning : Theme.accentStrong
                        font.family: Theme.fontMono; font.pixelSize: Theme.fsXs
                    }
                    QQC.ToolTip.visible: bad && (qBadgeHover.hovered || searchField.activeFocus)
                    QQC.ToolTip.text: I18n.t("topbar.searchUnknown").arg(root.searchProblems.join("  "))
                    HoverHandler { id: qBadgeHover }
                }
            }
            // An error pasted into search that this workspace has met
            // before (APP-159): a line under the box, over the view.
            QQC.Popup {
                id: seenPopup
                y: searchBox.height + Theme.spXs
                x: 0
                width: Math.max(searchBox.width, 320)
                padding: Theme.spSm
                focus: false
                closePolicy: QQC.Popup.NoAutoClose
                visible: seenHint.shown && searchField.text.length > 0
                background: PopupSurface {}
                contentItem: SeenBeforeHint {
                    id: seenHint
                    text: searchField.text
                    onActivated: (hit) => {
                        searchField.clear();
                        root.seenBeforeActivated(hit);
                    }
                }
            }
        }
                    }
                }
                Text {
                    objectName: "query-save-view"
                    text: I18n.t("query.saveView")
                    color: saveCA.hovered ? Theme.text : Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    Layout.alignment: Qt.AlignVCenter
                    ClickArea { id: saveCA; label: parent.text; onActivated: root.saveViewRequested() }
                }
            }
        }
        // Quiet (Q-Board / Q-List, DG-021): no box — the conditions as
        // outline chips with their values only, the lens's own option as one
        // more chip, and "изменить фильтр" to open the field.
        Flow {
            id: quietRow
            objectName: "view-header-query-quiet"
            visible: root.queryShown && !root._boxed
            Layout.fillWidth: true
            Layout.topMargin: Theme.spXs
            spacing: Theme.spMd
            Repeater {
                model: root.conditions
                delegate: PropertyChip {
                    id: qq
                    required property var modelData
                    required property int index
                    objectName: "query-quiet-chip-" + qq.index
                    value: qq.modelData.value
                    valueColor: qq.modelData.bad ? Theme.warning : Theme.textMuted
                    onClicked: root.focusEnd()
                    removable: false
                }
            }
            PropertyChip {
                objectName: "query-quiet-profile"
                visible: root.profileChipShown
                value: root.profileName
                valueColor: Theme.textMuted
                onClicked: root.profileChipClicked()
            }
            PropertyChip {
                id: quietOption
                objectName: "query-quiet-option"
                visible: !!root.option
                value: root.option ? String(root.option.value).toLowerCase() : ""
                valueColor: Theme.textMuted
                onClicked: optionMenu.popup(quietOption, 0, quietOption.height + Theme.spXs)
            }
            Text {
                objectName: "query-quiet-edit"
                height: Theme.chipH
                verticalAlignment: Text.AlignVCenter
                leftPadding: Theme.spXs
                text: I18n.t("query.editFilter")
                color: editCA.hovered ? Theme.textMuted : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                ClickArea { id: editCA; label: parent.text; shortcutId: "search.focus"; onActivated: root.focusEnd() }
            }
        }
    }
}
