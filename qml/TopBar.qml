import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    height: 48

    property alias searchText: searchField.text
    // Parse-only, so this costs nothing per keystroke — it never touches the
    // task list, unlike the filtering itself.
    readonly property bool searchIsQuery: AppController.searchIsQuery(searchField.text)
    // The widest a breadcrumb or the profile name may get before it elides.
    readonly property int crumbMaxWidth: 150
    // Clauses that mean nothing ("stauts:x", an unknown column, "due:banana"):
    // shown on the badge, so a typo does not read as an empty board.
    readonly property var searchProblems: AppController.searchProblems(searchField.text)
    signal newTaskRequested()
    // Esc on an empty search box, or Return in it: give the keyboard back.
    signal leaveRequested()
    signal rightPanelToggleRequested()
    // Whether the calendar/people column is on screen, for the toggle's look.
    property bool rightPanelShown: true
    signal newProfileRequested()
    signal renameProfileRequested()
    signal duplicateProfileRequested()
    signal exportJsonRequested()
    signal importJsonRequested()
    signal exportIcsRequested()
    signal importIcsRequested()
    signal exportVaultRequested()
    signal importVaultRequested()

    function focusSearch() {
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    function _activeProfileMap() {
        const list = AppController.profiles;
        const id = AppController.activeProfileId;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return ({ name: "—", color: Theme.accent });
    }

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1; color: Theme.border
    }

    RowLayout {
        anchors.fill: parent
        // On macOS the window uses a full-size content view, so the traffic-light
        // buttons overlay the top-left of this bar — inset the content to clear them.
        anchors.leftMargin: 16 + (Qt.platform.os === "osx" ? 62 : 0)
        anchors.rightMargin: Theme.sp2xl
        spacing: Theme.sp2xl

        // Brand
        BrandLogo {
            Layout.preferredHeight: 26
            Layout.alignment: Qt.AlignVCenter
            variant: "lockup"
            theme: Theme.dark ? "dark" : "light"
        }

        // Breadcrumbs — editable in place
        RowLayout {
            id: crumbs
            spacing: Theme.spXs
            EditableCrumb {
                value: AppController.crumbProject
                placeholder: I18n.t("topbar.crumb.project")
                bold: true
                onCommitted: (v) => AppController.crumbProject = v
            }
            CrumbSep {}
            // sprint segment — derived; not editable
            Text {
                text: I18n.relang(AppController.sprintLabel())
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsMd
            }
            CrumbSep {}
            EditableCrumb {
                value: AppController.crumbUser
                placeholder: I18n.t("topbar.crumb.user")
                bold: true
                onCommitted: (v) => AppController.crumbUser = v
            }
            CrumbSep {}

            // Profile pill — color dot + name + dropdown
            Rectangle {
                id: profilePill
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: Theme.radiusMd
                color: profileMA.containsMouse ? Theme.panel2 : Theme.panel3
                border.color: profileMA.containsMouse ? Theme.borderStrong : Theme.border
                border.width: 1
                implicitWidth: pillRow.implicitWidth + 16
                // Keyboard: Tab to it, Enter / Space / ↓ opens the profile menu.
                activeFocusOnTab: true
                Accessible.role: Accessible.ButtonMenu
                Accessible.name: profilePill.active.name || I18n.t("topbar.profile.fallback")
                Keys.onSpacePressed: profileMenu.popup(profilePill, 0, profilePill.height + 4)
                Keys.onReturnPressed: profileMenu.popup(profilePill, 0, profilePill.height + 4)
                Keys.onDownPressed: profileMenu.popup(profilePill, 0, profilePill.height + 4)
                FocusRing {}

                property var active: root._activeProfileMap()

                RowLayout {
                    id: pillRow
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                    spacing: Theme.spSm
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: profilePill.active.color || Theme.accent
                    }
                    Text {
                        text: profilePill.active.name || I18n.t("topbar.profile.fallback")
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsMd
                        font.weight: Font.Medium
                        // A long profile name pushed "+ Task" and the panel
                        // toggle off the window.
                        elide: Text.ElideRight
                        Layout.maximumWidth: root.crumbMaxWidth
                    }
                    Text {
                        text: "▾"
                        color: Theme.textDim
                        font.pixelSize: Theme.fsXs
                    }
                }
                MouseArea {
                    id: profileMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: profileMenu.popup()
                }

                AppMenu {
                    id: profileMenu

                    // Profile rows are inserted dynamically at the top of the
                    // menu via Instantiator, so they show before the static
                    // actions in declaration-order.
                    Instantiator {
                        id: profilesInst
                        model: AppController.profiles
                        delegate: AppMenuItem {
                            required property var modelData
                            marked: modelData.id === AppController.activeProfileId
                            text: modelData.name
                            onTriggered: AppController.activeProfileId = modelData.id
                        }
                        onObjectAdded:   (idx, obj) => profileMenu.insertItem(idx, obj)
                        onObjectRemoved: (idx, obj) => profileMenu.removeItem(obj)
                    }
                    AppMenuSeparator {}
                    AppMenuItem {
                        text: I18n.t("topbar.profile.new"); onTriggered: root.newProfileRequested()
                    }
                    AppMenuItem {
                        text: I18n.t("topbar.profile.rename"); onTriggered: root.renameProfileRequested()
                    }
                    AppMenuItem {
                        text: I18n.t("topbar.profile.duplicate"); onTriggered: root.duplicateProfileRequested()
                    }
                    AppMenuItem {
                        text: I18n.t("topbar.profile.delete")
                        enabled: AppController.profiles.length > 1
                        onTriggered: AppController.deleteProfile(AppController.activeProfileId)
                    }
                    AppMenuSeparator {}
                    AppMenuItem {
                        text: I18n.t("topbar.profile.import"); onTriggered: root.importJsonRequested()
                    }
                    AppMenuItem {
                        text: I18n.t("topbar.profile.export"); onTriggered: root.exportJsonRequested()
                    }
                    AppMenuSeparator {}
                    AppMenuItem {
                        text: I18n.t("topbar.cal.import"); onTriggered: root.importIcsRequested()
                    }
                    AppMenuItem {
                        text: I18n.t("topbar.cal.export"); onTriggered: root.exportIcsRequested()
                    }
                    AppMenuSeparator {}
                    AppMenuItem {
                        text: I18n.t("topbar.notes.import"); onTriggered: root.importVaultRequested()
                    }
                    AppMenuItem {
                        text: I18n.t("topbar.notes.export"); onTriggered: root.exportVaultRequested()
                    }
                }
            }
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
                    font.weight: Font.DemiBold
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
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsXs
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: (prBadge.pr && prBadge.pr.url)
                                     ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (prBadge.pr && prBadge.pr.url)
                                       Qt.openUrlExternally(prBadge.pr.url)
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
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsXs
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    radius: Theme.radiusSm
                    color: openMA.containsMouse ? Theme.accentStrong : "transparent"
                    border.color: Theme.accentStrong
                    border.width: 1
                    implicitWidth: openT.implicitWidth + 12
                    implicitHeight: 18
                    Text {
                        id: openT
                        anchors.centerIn: parent
                        text: I18n.t("topbar.git.open")
                        color: openMA.containsMouse ? Theme.bg : Theme.accentStrong
                        font.pixelSize: Theme.fsXs
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: openMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AppController.openFocusedTask()
                    }
                }
                // Dismiss. The hit area used to be the glyph's own bounds —
                // roughly 8x16px — so the banner was hard to get rid of.
                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: Theme.radiusSm
                    color: dismissMA.containsMouse ? Theme.withAlpha(Theme.accentStrong, 0.18) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: dismissMA.containsMouse ? Theme.accentStrong : Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsLg
                    }
                    MouseArea {
                        id: dismissMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AppController.dismissGitBanner()
                        ToolTip.visible: containsMouse
                        ToolTip.delay: 400
                        ToolTip.text: I18n.t("topbar.git.dismiss")
                    }
                }
            }
        }

        // Search: 280px when there is room, down to 160 when there is not.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 280
            Layout.maximumWidth: 280
            Layout.minimumWidth: 160
            Layout.preferredHeight: 28
            radius: Theme.radiusMd
            color: Theme.panel2
            border.color: searchField.activeFocus ? Theme.accent : Theme.border
            border.width: searchField.activeFocus ? 2 : 1
            Behavior on border.color { ColorAnimation { duration: Theme.scaledMs(120) } }
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
                    Behavior on color { ColorAnimation { duration: Theme.scaledMs(120) } }
                }
                TextField {
                    id: searchField
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
                    Keys.onEscapePressed: (event) => {
                        if (searchField.text.length > 0) searchField.clear();
                        else root.leaveRequested();
                        event.accepted = true;
                    }
                    Keys.onReturnPressed: root.leaveRequested()
                    Keys.onEnterPressed: root.leaveRequested()
                    // The syntax is only discoverable if something says it out
                    // loud; the field itself is the only place the user looks.
                    QQC.ToolTip.visible: searchField.activeFocus && searchField.text.length === 0
                    QQC.ToolTip.delay: 600
                    QQC.ToolTip.text: I18n.t("topbar.searchQueryHint").arg(AppController.searchFields().join(": · ") + ":")
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
                    border.color: kbdMA.containsMouse ? Theme.borderStrong : Theme.border
                    border.width: 1
                    color: kbdMA.containsMouse ? Theme.panel3 : "transparent"
                    width: kbd.implicitWidth + 10; height: 16
                    Text {
                        id: kbd; anchors.centerIn: parent
                        text: AppController.shortcutFor("search.focus")
                        color: kbdMA.containsMouse ? Theme.text : Theme.textDim
                        font.family: Theme.fontMono; font.pixelSize: Theme.fsXs
                    }
                    MouseArea {
                        id: kbdMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.focusSearch()
                        ToolTip.visible: containsMouse
                        ToolTip.delay: 400
                        ToolTip.text: I18n.t("topbar.searchHint").arg(kbd.text)
                    }
                }
            }
        }

        PillButton {
            objectName: "topbar-new-task"
            text: I18n.t("topbar.newTask")
            primary: true
            onClicked: root.newTaskRequested()
        }
        PillButton {
            objectName: "topbar-right-panel"
            text: root.rightPanelShown ? "▸" : "◂"
            onClicked: root.rightPanelToggleRequested()
            ToolTip.visible: hovered
            ToolTip.delay: 400
            ToolTip.text: I18n.t(root.rightPanelShown ? "topbar.rightPanel.hide" : "topbar.rightPanel.show")
                          + "  " + AppController.shortcutFor("panel.right")
        }
    }

    component CrumbSep: Text {
        text: "/"
        color: Theme.textMuted
        font.family: Theme.fontMono
        font.pixelSize: Theme.fsMd
    }

    component EditableCrumb: Item {
        id: ec
        property string value: ""
        property string placeholder: ""
        property bool bold: false
        property bool editing: false
        signal committed(string text)

        implicitWidth: editing ? Math.max(60, Math.min(root.crumbMaxWidth + 60, edit.implicitWidth + 12))
                               : Math.max(20, label.width + 6)
        implicitHeight: 22

        // Keyboard: Tab to the crumb, Enter or F2 edits it.
        activeFocusOnTab: !editing
        Accessible.role: Accessible.Button
        Accessible.name: label.text
        function startEdit() {
            ec.editing = true;
            edit.forceActiveFocus();
            edit.selectAll();
        }
        Keys.onReturnPressed: ec.startEdit()
        Keys.onPressed: (event) => { if (event.key === Qt.Key_F2) { ec.startEdit(); event.accepted = true; } }
        FocusRing { visible: ec.activeFocus && !ec.editing }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusSm
            color: hoverMA.containsMouse && !ec.editing ? Theme.panel2 : (ec.editing ? Theme.panel2 : "transparent")
            border.color: ec.editing ? Theme.accent : "transparent"
            border.width: ec.editing ? 1 : 0
        }

        Text {
            id: label
            anchors.centerIn: parent
            visible: !ec.editing
            // Capped and elided, like the profile name.
            width: Math.min(implicitWidth, root.crumbMaxWidth)
            elide: Text.ElideRight
            text: ec.value.length > 0 ? ec.value : ec.placeholder
            color: ec.value.length > 0 ? Theme.text : Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsMd
            font.weight: ec.bold ? Font.Medium : Font.Normal
        }

        TextField {
            id: edit
            anchors.fill: parent
            anchors.leftMargin: Theme.spXs; anchors.rightMargin: Theme.spXs
            visible: ec.editing
            text: ec.value
            placeholderText: ec.placeholder
            color: Theme.text
            placeholderTextColor: Theme.textDim
            background: Item {}
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsMd
            font.weight: ec.bold ? Font.Medium : Font.Normal
            selectByMouse: true
            onAccepted: { ec.committed(edit.text.trim()); ec.editing = false }
            onActiveFocusChanged: if (!activeFocus && ec.editing) { ec.committed(edit.text.trim()); ec.editing = false }
            Keys.onEscapePressed: { edit.text = ec.value; ec.editing = false }
        }

        MouseArea {
            id: hoverMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            visible: !ec.editing
            onClicked: ec.startEdit()
        }
    }
}
