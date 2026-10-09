pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls.impl
import TodoCpp

// The heap 2 sidebar (APP-258): the wordmark and the profile, a field that
// starts a new task, the three places — Today, Tasks, Knowledge — then "My
// views" (saved queries with their counts), and Settings at the bottom.
// Exactly one row is active. Folded (Ctrl+Shift+B, or on its own below
// ~1100px) it keeps an icon per row and moves the names to tooltips.
// Main owns the expanded state and persists it — this only draws it.
Rectangle {
    id: root
    objectName: "sidebar"
    color: Theme.surfaceNav

    property bool expanded: true
    readonly property int expandedWidth: Theme.px(208)
    // The 36px icon cell plus the margins.
    readonly property int collapsedWidth: 36 + 2 * Theme.spLg
    // implicitWidth, not width: a Layout writes width itself.
    implicitWidth: expanded ? expandedWidth : collapsedWidth
    Behavior on implicitWidth { NumberAnimation { duration: Theme.durMove; easing.type: Theme.easeEnter } }
    clip: true

    signal toggleRequested()
    signal newTaskRequested()
    signal openTweaks(Item anchor)
    signal openHotkeys(Item anchor)

    // ── Profile (forwarded from the switcher) ──
    signal syncStatusRequested()
    signal newProfileRequested()
    signal renameProfileRequested()
    signal duplicateProfileRequested()
    signal exportJsonRequested()
    signal importJsonRequested()
    signal exportIcsRequested()
    signal importIcsRequested()
    signal exportVaultRequested()
    signal importVaultRequested()
    property alias profileSwitcher: profile

    // ── My views ──
    // The list is AppController.savedViews; which one is active and whether
    // the filters have moved off it is Main's (SavedViewsHost), handed in.
    property string activeSavedViewId: ""
    property bool savedViewModified: false
    signal savedViewActivated(string id)
    signal savedViewRenameRequested(string id)
    signal savedViewUpdateRequested(string id)
    signal saveViewRequested()
    readonly property var _savedViews: AppController.savedViews
    readonly property var _savedCounts: AppController.savedViewCounts

    // Popovers opened from the keyboard sit by the Settings row.
    property alias tweaksAnchor: settingsRow
    property alias hotkeysAnchor: settingsRow

    // A section is active only while no saved view is: one row lit at a time.
    readonly property string _section: activeSavedViewId.length > 0 && AppController.currentSection === "tasks"
                                       ? "" : AppController.currentSection

    // "Ctrl+N" as keymap.md writes it: "Ctrl N".
    function prettyKeys(seq) {
        if (!seq) return "";
        return String(seq).split(", ")[0].replace(/\+(?=.)/g, " ");
    }
    // A count as the list shows it: nothing for 0, "999+" past that.
    function countText(n) {
        if (n === undefined || n === null || n <= 0) return "";
        return n > 999 ? "999+" : String(n);
    }

    function focusSavedView(index) {
        if (index < 0 || index >= viewsList.count) return;
        viewsList.positionViewAtIndex(index, ListView.Contain);
        const it = viewsList.itemAtIndex(index);
        if (it) it.forceActiveFocus(Qt.TabFocusReason);
    }
    function _moveSavedView(id, index, delta) {
        if (AppController.moveSavedView(id, delta))
            Qt.callLater(root.focusSavedView, index + delta);
    }
    function _deleteSavedView(id, index) {
        if (!AppController.deleteSavedView(id)) return;
        Qt.callLater(function () {
            if (viewsList.count > 0) root.focusSavedView(Math.min(index, viewsList.count - 1));
        });
    }
    function _openSavedMenu(item, id, index) {
        savedMenu.targetId = id;
        savedMenu.targetIndex = index;
        savedMenu.popup(item, item.width - Theme.spMd, item.height / 2);
    }

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1; color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spLg + (Qt.platform.os === "osx" ? Theme.spXl : 0)
        anchors.bottomMargin: Theme.spLg
        anchors.leftMargin: Theme.spLg
        anchors.rightMargin: Theme.spLg
        spacing: Theme.sp2xs

        // Wordmark (the mark when folded) and the profile.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.chipH
            Layout.bottomMargin: Theme.spMd
            spacing: Theme.spSm
            Item {
                Layout.preferredWidth: logo.implicitWidth
                Layout.preferredHeight: Theme.chipH
                visible: root.expanded
                BrandLogo {
                    id: logo
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18
                    variant: "wordmark"
                    theme: Theme.dark ? "dark" : "light"
                }
                ClickArea {
                    objectName: "sidebar-collapse"
                    label: I18n.t("sidebar.collapse")
                    shortcutId: "rail.toggle"
                    onActivated: root.toggleRequested()
                }
            }
            ProfileSwitcher {
                id: profile
                Layout.fillWidth: true
                // What is left beside the wordmark, not the name's own width:
                // a long name elides instead of running off the sidebar.
                Layout.preferredWidth: 0
                Layout.minimumWidth: Theme.spLg
                Layout.preferredHeight: Theme.chipH
                compact: !root.expanded
                onSyncStatusRequested: root.syncStatusRequested()
                onNewProfileRequested: root.newProfileRequested()
                onRenameProfileRequested: root.renameProfileRequested()
                onDuplicateProfileRequested: root.duplicateProfileRequested()
                onExportJsonRequested: root.exportJsonRequested()
                onImportJsonRequested: root.importJsonRequested()
                onExportIcsRequested: root.exportIcsRequested()
                onImportIcsRequested: root.importIcsRequested()
                onExportVaultRequested: root.exportVaultRequested()
                onImportVaultRequested: root.importVaultRequested()
            }
        }

        // "New task…" — a field to look at, a button underneath.
        Rectangle {
            id: newTask
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.chipH + Theme.spXs
            Layout.bottomMargin: Theme.spLg
            radius: Theme.radiusMd
            color: newTaskCA.hovered ? Theme.panel2 : Theme.panel
            border.color: newTaskCA.hovered ? Theme.borderStrong : Theme.border
            border.width: 1
            Text {
                visible: root.expanded
                anchors.left: parent.left; anchors.leftMargin: Theme.spMd
                anchors.right: newTaskKey.left; anchors.rightMargin: Theme.spSm
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t("sidebar.newTask")
                elide: Text.ElideRight
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
            }
            KeyHint {
                id: newTaskKey
                visible: root.expanded && keys.length > 0 && Style.keyHints
                anchors.right: parent.right; anchors.rightMargin: Theme.spMd
                anchors.verticalCenter: parent.verticalCenter
                keys: AppController.shortcuts.length >= 0 ? root.prettyKeys(AppController.shortcutFor("task.new")) : ""
            }
            Text {
                visible: !root.expanded
                anchors.centerIn: parent
                text: "+"
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsLg
            }
            ClickArea {
                id: newTaskCA
                objectName: "sidebar-new-task"
                label: I18n.t("sidebar.newTask")
                shortcutId: "task.new"
                showTip: !root.expanded
                onActivated: root.newTaskRequested()
            }
        }

        NavRow {
            objectName: "sidebar-section-today"
            section: "today"
            label: I18n.t("sidebar.today")
            iconSource: "qrc:/brand/icons/heap-17-calendar.svg"
            shortcutId: "section.today"
        }
        NavRow {
            objectName: "sidebar-section-tasks"
            section: "tasks"
            label: I18n.t("sidebar.tasks")
            iconSource: "qrc:/brand/icons/heap-01-board.svg"
            shortcutId: "section.tasks"
        }
        NavRow {
            objectName: "sidebar-section-knowledge"
            section: "knowledge"
            label: I18n.t("sidebar.knowledge")
            iconSource: "qrc:/brand/icons/heap-09-notes.svg"
            shortcutId: "section.knowledge"
        }

        // ── My views ──
        Item {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spLg
            Layout.preferredHeight: root.expanded ? viewsHead.implicitHeight + Theme.spXs : Theme.spSm
            Text {
                id: viewsHead
                objectName: "sidebar-views-head"
                visible: root.expanded
                anchors.left: parent.left; anchors.leftMargin: Theme.spMd
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t("sidebar.myViews")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Rectangle {
                visible: !root.expanded
                anchors.centerIn: parent
                width: 24; height: 1; color: Theme.border
            }
        }
        Text {
            objectName: "sidebar-views-empty"
            visible: root._savedViews.length === 0 && root.expanded
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spMd
            text: I18n.t("sidebar.myViews.empty")
            wrapMode: Text.WordWrap
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }
        // Twenty views scroll inside the block; the sidebar does not grow.
        ListView {
            id: viewsList
            objectName: "sidebar-views-list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.sp2xs
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: root._savedViews
            ScrollBar.vertical: ThinScrollBar { objectName: "sidebar-views-scrollbar" }
            delegate: ViewRow {}
        }

        NavRow {
            id: settingsRow
            objectName: "sidebar-section-settings"
            section: "settings"
            label: I18n.t("sidebar.settings")
            iconSource: "qrc:/brand/icons/heap-12-settings.svg"
            shortcutId: "view.settings"
        }
        // The rest is in the command line.
        Row {
            objectName: "sidebar-palette-hint"
            visible: root.expanded && Style.keyHints && paletteKey.keys.length > 0
            Layout.leftMargin: Theme.spMd
            Layout.topMargin: Theme.spMd
            spacing: Theme.spXs
            KeyHint {
                id: paletteKey
                keys: AppController.shortcuts.length >= 0 ? root.prettyKeys(AppController.shortcutFor("palette.open")) : ""
                font.weight: Theme.fwTitle
                color: Theme.textMuted
            }
            Text {
                text: I18n.t("sidebar.everythingElse")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
        }
    }

    // One menu for every view row; the row says which view it is for.
    AppMenu {
        id: savedMenu
        objectName: "sidebar-views-menu"
        property string targetId: ""
        property int targetIndex: -1
        AppMenuItem {
            objectName: "sidebar-view-apply"
            text: I18n.t("siderail.saved.apply")
            onTriggered: root.savedViewActivated(savedMenu.targetId)
        }
        AppMenuItem {
            objectName: "sidebar-view-update"
            text: I18n.t("siderail.saved.update")
            onTriggered: root.savedViewUpdateRequested(savedMenu.targetId)
        }
        AppMenuItem {
            objectName: "sidebar-view-rename"
            text: I18n.t("siderail.saved.rename")
            onTriggered: root.savedViewRenameRequested(savedMenu.targetId)
        }
        AppMenuItem {
            objectName: "sidebar-view-duplicate"
            text: I18n.t("siderail.saved.duplicate")
            onTriggered: AppController.duplicateSavedView(savedMenu.targetId)
        }
        AppMenuSeparator {}
        AppMenuItem {
            objectName: "sidebar-view-up"
            text: I18n.t("siderail.saved.moveUp")
            enabled: savedMenu.targetIndex > 0
            onTriggered: root._moveSavedView(savedMenu.targetId, savedMenu.targetIndex, -1)
        }
        AppMenuItem {
            objectName: "sidebar-view-down"
            text: I18n.t("siderail.saved.moveDown")
            enabled: savedMenu.targetIndex >= 0 && savedMenu.targetIndex < root._savedViews.length - 1
            onTriggered: root._moveSavedView(savedMenu.targetId, savedMenu.targetIndex, 1)
        }
        AppMenuSeparator {}
        AppMenuItem {
            objectName: "sidebar-view-delete"
            text: I18n.t("siderail.saved.delete")
            danger: true
            onTriggered: root._deleteSavedView(savedMenu.targetId, savedMenu.targetIndex)
        }
    }

    // A place: Today, Tasks, Knowledge, Settings.
    component NavRow: Item {
        id: nav
        property string section: ""
        property string label: ""
        property url iconSource
        property string shortcutId: ""
        readonly property bool active: root._section === nav.section
        readonly property string _keys: nav.shortcutId.length && AppController.shortcuts.length >= 0
            ? root.prettyKeys(AppController.shortcutFor(nav.shortcutId)) : ""
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.chipH + Theme.spXs
        activeFocusOnTab: false

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMd
            color: navCA.hovered && !nav.active ? Theme.panel2 : "transparent"
        }
        IconImage {
            visible: !root.expanded
            anchors.centerIn: parent
            source: nav.iconSource
            width: 18; height: 18
            sourceSize.width: 18; sourceSize.height: 18
            color: nav.active ? Theme.text : Theme.textMuted
        }
        Text {
            id: navLabel
            objectName: "sidebar-label"
            visible: root.expanded
            anchors.left: parent.left; anchors.leftMargin: Theme.spMd
            anchors.right: navKey.visible ? navKey.left : parent.right
            anchors.rightMargin: Theme.spSm
            anchors.verticalCenter: parent.verticalCenter
            text: nav.label
            elide: Text.ElideRight
            color: nav.active || navCA.hovered ? Theme.text : Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: nav.active ? Theme.fwTitle : Theme.fwBody
        }
        CursorBar {
            objectName: "sidebar-cursor"
            shown: nav.active
            anchors.left: root.expanded ? navLabel.left : undefined
            anchors.horizontalCenter: root.expanded ? undefined : parent.horizontalCenter
            anchors.top: root.expanded ? navLabel.bottom : undefined
            anchors.bottom: root.expanded ? undefined : parent.bottom
            anchors.topMargin: 1
        }
        KeyHint {
            id: navKey
            visible: root.expanded && keys.length > 0 && Style.keyHints
            anchors.right: parent.right; anchors.rightMargin: Theme.spMd
            anchors.verticalCenter: parent.verticalCenter
            keys: nav._keys
            color: nav.active ? Theme.text : Theme.textDim
            font.weight: nav.active ? Theme.fwTitle : Theme.fwBody
        }
        ClickArea {
            id: navCA
            label: nav.label
            role: Accessible.PageTab
            checkable: true
            checked: nav.active
            shortcutId: nav.shortcutId
            showTip: !root.expanded
            onActivated: {
                if (nav.shortcutId.length > 0) AppController.noteMouseAction(nav.shortcutId);
                AppController.openSection(nav.section);
            }
        }
    }

    // One of My views.
    component ViewRow: Item {
        id: vr
        required property var modelData
        required property int index
        width: viewsList.width
        height: Theme.chipH + Theme.spXs
        objectName: "sidebar-view-" + vr.index
        activeFocusOnTab: true

        readonly property bool active: vr.modelData.id === root.activeSavedViewId
        readonly property bool modified: vr.active && root.savedViewModified
        readonly property var _problems: vr.modelData.problems || []
        readonly property string _count: root.countText(root._savedCounts[vr.modelData.id])
        readonly property string _fullName: vr.modelData.name
            + (vr._problems.length > 0 ? " — " + I18n.t("topbar.searchUnknown").arg(vr._problems.join("  ")) : "")
        // What the row shows at its right edge, and what its tooltip says.
        readonly property string countText: vrCount.visible ? vrCount.text : ""
        readonly property string tooltipText: vrMA.ToolTip.text

        Accessible.role: Accessible.Button
        Accessible.name: vr.modelData.name
            + (vr._problems.length > 0 ? ", " + I18n.t("topbar.searchUnknown").arg(vr._problems.join("  "))
               : vr._count.length > 0 ? ", " + I18n.t("siderail.saved.count").arg(vr._count) : "")
        Accessible.onPressAction: root.savedViewActivated(vr.modelData.id)

        Keys.onReturnPressed: root.savedViewActivated(vr.modelData.id)
        Keys.onEnterPressed: root.savedViewActivated(vr.modelData.id)
        Keys.onSpacePressed: root.savedViewActivated(vr.modelData.id)
        Keys.onUpPressed: (e) => {
            if (e.modifiers & Qt.ControlModifier) root._moveSavedView(vr.modelData.id, vr.index, -1);
            else root.focusSavedView(vr.index - 1);
        }
        Keys.onDownPressed: (e) => {
            if (e.modifiers & Qt.ControlModifier) root._moveSavedView(vr.modelData.id, vr.index, 1);
            else root.focusSavedView(vr.index + 1);
        }
        Keys.onDeletePressed: root._deleteSavedView(vr.modelData.id, vr.index)
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_F2) {
                root.savedViewRenameRequested(vr.modelData.id);
                e.accepted = true;
            } else if (e.key === Qt.Key_Menu || (e.key === Qt.Key_F10 && (e.modifiers & Qt.ShiftModifier))) {
                root._openSavedMenu(vr, vr.modelData.id, vr.index);
                e.accepted = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMd
            color: vrMA.dragging ? Theme.panel3 : vrMA.containsMouse && !vr.active ? Theme.panel2 : "transparent"
            border.color: Theme.focusRing
            border.width: vr.activeFocus ? 2 : 0
        }
        // Folded: the bookmark with its Alt+N digit.
        Item {
            visible: !root.expanded
            anchors.fill: parent
            IconImage {
                anchors.centerIn: parent
                source: "qrc:/brand/icons/heap-36-saved-view.svg"
                width: 18; height: 18
                sourceSize.width: 18; sourceSize.height: 18
                color: vr.active ? Theme.text : Theme.textMuted
            }
            Text {
                objectName: "sidebar-view-digit"
                visible: vr.index < 9
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: String(vr.index + 1)
                color: vr.active ? Theme.text : Theme.textMuted
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsXs
                font.weight: Theme.fwTitle
            }
        }
        Text {
            id: vrName
            objectName: "sidebar-view-name"
            visible: root.expanded
            anchors.left: parent.left; anchors.leftMargin: Theme.spMd
            anchors.right: vrCount.visible ? vrCount.left : parent.right
            anchors.rightMargin: Theme.spSm
            anchors.verticalCenter: parent.verticalCenter
            text: vr.modified ? vr.modelData.name + " •" : vr.modelData.name
            elide: Text.ElideRight
            font.italic: vr.modified
            color: vr.active || vrMA.containsMouse ? Theme.text : Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: vr.active ? Theme.fwTitle : Theme.fwBody
        }
        CursorBar {
            visible: vr.active && root.expanded
            anchors.left: vrName.left
            anchors.top: vrName.bottom
            anchors.topMargin: 1
        }
        Text {
            id: vrCount
            objectName: "sidebar-view-count"
            visible: root.expanded && (vr._problems.length > 0 || (Style.counters && vr._count.length > 0))
            anchors.right: parent.right; anchors.rightMargin: Theme.spMd
            anchors.verticalCenter: parent.verticalCenter
            text: vr._problems.length > 0 ? "?" : vr._count
            color: vr._problems.length > 0 ? Theme.warning : Theme.textDim
            font.family: Theme.fontUi
            font.features: Theme.tabularNums
            font.pixelSize: Theme.fsXs
        }
        MouseArea {
            id: vrMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            // Drag to reorder: past a few pixels the row follows the
            // pointer's slot, and lands there on release.
            property real _pressY: 0
            property bool dragging: false
            property int _target: -1
            onPressed: (m) => { _pressY = m.y; dragging = false; _target = -1; }
            onPositionChanged: (m) => {
                if (!pressed || !(m.buttons & Qt.LeftButton)) return;
                if (!dragging && Math.abs(m.y - _pressY) < Theme.spMd) return;
                dragging = true;
                const p = vrMA.mapToItem(viewsList.contentItem, m.x, m.y);
                const i = viewsList.indexAt(viewsList.width / 2, p.y);
                _target = i >= 0 ? i : (p.y < 0 ? 0 : viewsList.count - 1);
            }
            onReleased: {
                if (!dragging) return;
                dragging = false;
                if (_target >= 0 && _target !== vr.index)
                    root._moveSavedView(vr.modelData.id, vr.index, _target - vr.index);
            }
            onCanceled: dragging = false
            onClicked: (m) => {
                if (m.button === Qt.RightButton) {
                    root._openSavedMenu(vr, vr.modelData.id, vr.index);
                    return;
                }
                root.savedViewActivated(vr.modelData.id);
            }
            ToolTip.visible: (containsMouse || vr.activeFocus) && !dragging
                             && (!root.expanded || vrName.truncated || vr._problems.length > 0)
            ToolTip.delay: 400
            ToolTip.text: vr._fullName
                + (!root.expanded && vr._count.length > 0 ? "  ·  " + I18n.t("siderail.saved.count").arg(vr._count) : "")
        }
    }
}
