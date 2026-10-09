import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

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
        : section === "knowledge"
        ? [{ id: "notes", label: I18n.t("lens.notes"), keys: "" },
           { id: "docs", label: I18n.t("lens.links"), keys: "" }]
        : []
    readonly property string lens: view === "timeline" ? "list"
                                 : (view === "week" || view === "month") ? "calendar"
                                 : view
    signal lensSelected(string id)
    // The task search belongs to the views that list tasks.
    property bool searchShown: section === "tasks"

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
        const neg = raw.startsWith("-");
        const body = neg ? raw.slice(1) : raw;
        const at = body.indexOf(":");
        const k = body.slice(0, at).toLowerCase();
        const v = body.slice(at + 1);
        const keys = { status: "status", priority: "priority", tag: "label", due: "due", deadline: "due",
                       is: "is", mention: "mention" };
        const key = I18n.t("query.key." + (keys[k] || "other"));
        let value = v;
        if (k === "is") value = I18n.t("query.is." + v.toLowerCase());
        else if (k === "priority") value = v.toUpperCase().split(",").join(", ");
        else if (k === "status") {
            const sts = AppController.statuses;
            value = v.split(",").map(id => { const st = sts.find(x => x.id === id.toLowerCase()); return st ? st.name : id; }).join(", ");
        } else if (k === "due" || k === "deadline") {
            const words = ["today", "tomorrow", "week", "overdue", "none"];
            value = words.indexOf(v.toLowerCase()) >= 0 ? I18n.t("query.due." + v.toLowerCase()) : v;
        }
        if (value.indexOf("query.") === 0) value = v;
        const bad = root.searchProblems.indexOf(raw) >= 0;
        return { key: (neg ? I18n.t("query.not") + " " : "") + key, value: value + (bad ? " · " + I18n.t("query.unknown") : ""), raw: raw, bad: bad };
    }
    // The "seen this before" hint under the search was clicked (APP-159).
    signal seenBeforeActivated(var hit)
    // Esc on an empty search box, or Return in it: give the keyboard back.
    signal leaveRequested()

    function focusSearch() {
        searchField.forceActiveFocus();
        searchField.selectAll();
    }
    function focusEnd() {
        searchField.forceActiveFocus();
        searchField.cursorPosition = searchField.text.length;
    }
    // Type to search (APP-117): the first letter typed on the board starts a
    // fresh search with it, and the rest follow into the field.
    function typeAhead(text) {
        searchField.text = text;
        searchField.forceActiveFocus();
        searchField.cursorPosition = searchField.text.length;
    }
    implicitHeight: headRow.implicitHeight + (root.searchShown ? queryRow.implicitHeight + Theme.spMd : 0) + 2 * Theme.spLg

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.sp2xl
        anchors.rightMargin: Theme.sp2xl
        anchors.topMargin: Theme.spLg
        anchors.bottomMargin: Theme.spLg
        spacing: Theme.spMd
    RowLayout {
        id: headRow
        Layout.fillWidth: true
        spacing: Theme.spXl

        Text {
            objectName: "view-header-title"
            text: root.title
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXl
            font.weight: Theme.fwHeading
            Accessible.role: Accessible.Heading
            Accessible.name: root.title
        }
        LensTabs {
            id: lensTabs
            objectName: "view-header-lenses"
            visible: root.lenses.length > 0
            model: root.lenses
            current: root.lens
            onSelected: (id) => root.lensSelected(id)
        }

        Item { Layout.fillWidth: true }

        // Git focus banner — appears when GitWatcher detects a checkout
        // matching a registered task prefix. Dismiss persists until next
        // branchChanged.
        Rectangle {
            id: gitBanner
            visible: AppController.focusedTaskId.length > 0
                  && !AppController.focusedBannerDismissed
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
                Text {
                    text: "⎇"
                    color: Theme.accentStrong
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsMd
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
                        text: {
                            if (ciBadge.ci === "passing") return "CI ✓";
                            if (ciBadge.ci === "failing") return "CI ✗";
                            return "CI …";
                        }
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
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: dismissMA.hovered ? Theme.accentStrong : Theme.textDim
                        font.family: Theme.fontUi
                        font.features: Theme.tabularNums
                        font.pixelSize: Theme.fsLg
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
            visible: root.searchShown && root.resultCount >= 0
            text: I18n.count(Math.max(0, root.resultCount), "query.n.tasks")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.features: Theme.tabularNums
            font.pixelSize: Theme.fsSm
        }
    }

        // The query (APP-261): conditions as chips (× drops one), then the
        // field in the same language as quick capture; "Save as view".
        Rectangle {
            id: queryRow
            objectName: "view-header-query"
            visible: root.searchShown
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
                Text {
                    text: "⌕"
                    color: root.searchIsQuery ? Theme.accentStrong : Theme.textDim
                    font.pixelSize: Theme.fsSm
                }
                Flow {
                    id: queryFlow
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
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
                    Item {
                        width: Math.max(Theme.px(200), queryFlow.width - x)
                        height: Theme.chipHSmall
                        Rectangle {
                            id: searchBox
                            anchors.fill: parent
                            color: "transparent"
            Behavior on border.color { ColorAnimation { duration: Theme.durTap; easing.type: Theme.easeEnter } }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spSm
                spacing: Theme.spXs
                // Lights up when the text holds a clause, so it is obvious that
                // `status:blocked` narrowed the board structurally rather than
                // failing to find the literal string anywhere.
                Text {
                    text: "⌕"
                    color: root.searchIsQuery ? Theme.accentStrong : Theme.textDim
                    font.pixelSize: Theme.fsSm
                    Behavior on color { ColorAnimation { duration: Theme.durTap; easing.type: Theme.easeEnter } }
                }
                TextField {
                    id: searchField
                    ContextMenu.menu: TextEditMenu { editor: searchField }
                    objectName: "topbar-search"
                    Layout.fillWidth: true
                    placeholderText: I18n.t("topbar.search")
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
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
                    visible: root.searchIsQuery || bad
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
                // Shortcut hint. It used to read "⌘K" — a macOS glyph on every
                // platform, and the wrong binding besides: Ctrl+K opens the
                // command palette, focusing this field is search.focus. Now it
                // shows the live binding and clicking it does what it says.
                Rectangle {
                    visible: kbd.text.length > 0
                    radius: Theme.radiusSm
                    border.color: kbdMA.hovered ? Theme.borderStrong : Theme.border
                    border.width: 1
                    color: kbdMA.hovered ? Theme.panel3 : "transparent"
                    width: kbd.implicitWidth + 10; height: 16
                    Text {
                        id: kbd; anchors.centerIn: parent
                        text: AppController.shortcuts.length >= 0 ? AppController.shortcutText("search.focus") : ""
                        color: kbdMA.hovered ? Theme.text : Theme.textDim
                        font.family: Theme.fontMono; font.pixelSize: Theme.fsXs
                    }
                    // Named, not a Tab stop: the search field right before it
                    // is where it would take the keyboard.
                    ClickArea {
                        id: kbdMA
                        objectName: "topbar-search-kbd"
                        activeFocusOnTab: false
                        label: I18n.t("topbar.searchHint").arg(kbd.text)
                        onActivated: root.focusSearch()
                    }
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
                    visible: root.conditions.length > 0 || searchField.text.length > 0
                    text: I18n.t("query.saveView")
                    color: saveCA.hovered ? Theme.text : Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    ClickArea { id: saveCA; label: parent.text; onActivated: root.saveViewRequested() }
                }
            }
        }
        // Nothing matches: say so, and the way back, in one line.
        Text {
            objectName: "view-header-nothing"
            visible: root.searchShown && root.resultCount === 0 && root.searchText.length > 0
            text: I18n.t("query.nothing")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            font.underline: resetCA.hovered
            ClickArea { id: resetCA; label: parent.text; onActivated: root.clearQuery() }
        }
    }
}
