pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls.impl
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    // Expanded shows a label next to every icon and names the groups; the
    // collapsed form is the original 56px icon rail. Main owns the state and
    // persists it — this only draws it.
    property bool expanded: true
    readonly property int expandedWidth: 216
    readonly property int collapsedWidth: 56
    // implicitWidth, not width: a Layout writes width itself, which would
    // break a binding on it.
    implicitWidth: expanded ? expandedWidth : collapsedWidth
    Behavior on implicitWidth { NumberAnimation { duration: Theme.durMove; easing.type: Theme.easeEnter } }
    clip: true

    signal openTweaks(Item anchor)
    signal openHotkeys(Item anchor)
    signal toggleRequested()

    // ── Saved views ──
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

    // Put the keyboard on the n-th saved view row (after a reorder rebuilt
    // the list, or from the arrows).
    function focusSavedView(index) {
        if (index < 0 || index >= savedList.count) return;
        const it = savedList.itemAtIndex(index);
        if (it) it.forceActiveFocus(Qt.TabFocusReason);
    }
    function _moveSavedView(id, index, delta) {
        if (AppController.moveSavedView(id, delta))
            Qt.callLater(root.focusSavedView, index + delta);
    }
    function _deleteSavedView(id, index) {
        if (!AppController.deleteSavedView(id)) return;
        Qt.callLater(function () {
            if (savedList.count > 0) root.focusSavedView(Math.min(index, savedList.count - 1));
        });
    }
    function _openSavedMenu(item, id, index) {
        savedMenu.targetId = id;
        savedMenu.targetIndex = index;
        savedMenu.popup(item, item.width - Theme.spMd, item.height / 2);
    }

    // Expose anchors so Main can position popups when triggered via
    // shortcut (i.e. "as if the rail button had been clicked").
    property alias tweaksAnchor:  tweaksBtn
    property alias hotkeysAnchor: hotkeysBtn

    // Reactive badges. statusCounts is one pass over the model, recomputed
    // when it changes and shared with the top bar — these used to be two
    // separate full scans, repeated in all four handlers.
    readonly property int _blockedCount: AppController.statusCounts["blocked"] || 0
    readonly property int _reviewCount:  AppController.statusCounts["review"] || 0

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1; color: Theme.border
    }

    // Everything above the bottom group scrolls when the window is too short
    // for it — with saved views in the list, a laptop screen was — instead of
    // the lower buttons being cut off. The keyboard's row is kept in view.
    function _revealFocus() {
        const w = root.Window.window;
        const f = w ? w.activeFocusItem : null;
        for (let p = f; p; p = p.parent) {
            if (p !== railUpper) continue;
            const y = f.mapToItem(railUpper, 0, 0).y;
            if (y < railScroll.contentY)
                railScroll.contentY = Math.max(0, y - Theme.spMd);
            else if (y + f.height > railScroll.contentY + railScroll.height)
                railScroll.contentY = Math.min(railScroll.contentHeight - railScroll.height, y + f.height - railScroll.height + Theme.spMd);
            return;
        }
    }
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() { root._revealFocus(); }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spLg
        anchors.leftMargin: Theme.spLg
        anchors.rightMargin: Theme.spLg
        spacing: Theme.sp2xs

        Flickable {
            id: railScroll
            objectName: "rail-scroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: railUpper.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ThinScrollBar {}

            ColumnLayout {
                id: railUpper
                width: railScroll.width
                spacing: Theme.sp2xs

                // Collapse / expand toggle
                RailBtn {
                    expanded: root.expanded
                    objectName: "rail-toggle"
                    label: I18n.t("siderail.collapse")
                    tooltipText: I18n.t("siderail.expand") + "  " + AppController.shortcutFor("rail.toggle")
                    glyph: root.expanded ? "«" : "»"
                    onActivated: root.toggleRequested()
                    Layout.bottomMargin: Theme.spSm
                }

                SectionHead { expanded: root.expanded; text: I18n.t("siderail.section.views") }

                // View switcher
                RailBtn {
                    expanded: root.expanded
                    objectName: "rail-board"
                    iconSource: "qrc:/brand/icons/heap-01-board.svg"
                    label: I18n.t("siderail.board"); tooltipText: I18n.t("siderail.tip.board"); shortcutId: "view.board"
                    // Blocked and Review below jump to their column on the
                    // board; they are not places of their own, so they do not
                    // light up next to it (design audit DES-11: the board and
                    // "Blocked" read as two places open at once).
                    active: AppController.currentView === "board"
                    onActivated: AppController.currentView = "board" }
                RailBtn {
                    expanded: root.expanded
                    objectName: "rail-timeline"
                    iconSource: "qrc:/brand/icons/heap-02-timeline.svg"
                    label: I18n.t("siderail.timeline"); tooltipText: I18n.t("siderail.tip.timeline"); shortcutId: "view.timeline"
                    active: AppController.currentView === "timeline"
                    onActivated: AppController.currentView = "timeline" }
                RailBtn {
                    expanded: root.expanded
                    objectName: "rail-week"
                    iconSource: "qrc:/brand/icons/heap-03-week.svg"
                    label: I18n.t("siderail.week"); tooltipText: I18n.t("siderail.tip.week"); shortcutId: "view.week"
                    active: AppController.currentView === "week"
                    onActivated: AppController.currentView = "week" }
                RailBtn {
                    expanded: root.expanded
                    objectName: "rail-month"
                    iconSource: "qrc:/brand/icons/heap-04-month.svg"
                    label: I18n.t("siderail.month"); tooltipText: I18n.t("siderail.tip.month"); shortcutId: "view.month"
                    active: AppController.currentView === "month"
                    onActivated: AppController.currentView = "month" }
                RailBtn {
                    expanded: root.expanded
                    objectName: "rail-archive"
                    iconSource: "qrc:/brand/icons/heap-05-archive.svg"
                    label: I18n.t("siderail.archive"); tooltipText: I18n.t("siderail.tip.archive"); shortcutId: "view.archive"
                    active: AppController.currentView === "archive"
                    onActivated: AppController.currentView = "archive"
                }

                SectionHead { expanded: root.expanded; text: I18n.t("siderail.section.focus") }

                RailBtn {

                    expanded: root.expanded
                    objectName: "rail-blocked"
                    iconSource: "qrc:/brand/icons/heap-06-blocked.svg"
                    label: I18n.t("siderail.blocked"); tooltipText: I18n.t("siderail.tip.blocked")
                    countText: root._blockedCount > 0 ? root._blockedCount : ""
                    countColor: Theme.danger
                    onActivated: AppController.focusStatusColumn("blocked") }
                RailBtn {
                    expanded: root.expanded
                    objectName: "rail-review"
                    iconSource: "qrc:/brand/icons/heap-07-code-review.svg"
                    label: I18n.t("siderail.review"); tooltipText: I18n.t("siderail.tip.review")
                    countText: root._reviewCount > 0 ? root._reviewCount : ""
                    countColor: Theme.accent
                    onActivated: AppController.focusStatusColumn("review") }

                SectionHead {
                    objectName: "rail-saved-head"
                    expanded: root.expanded
                    text: I18n.t("siderail.section.saved")
                }

                // One row per saved view, numbered like the Alt+N that applies it.
                // As tall as its rows: the rail scrolls, not the list.
                ListView {
                    id: savedList
                    objectName: "rail-saved-list"
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    interactive: false
                    spacing: Theme.sp2xs
                    model: root._savedViews
                    delegate: RailBtn {
                        id: svBtn
                        required property var modelData
                        required property int index
                        width: savedList.width
                        height: svBtn.implicitHeight
                        objectName: "rail-saved-" + svBtn.index
                        expanded: root.expanded
                        glyph: svBtn.index < 9 ? String(svBtn.index + 1) : "·"
                        glyphMono: true
                        label: svBtn.modelData.name
                        readonly property bool _active: svBtn.modelData.id === root.activeSavedViewId
                        active: svBtn._active
                        modified: svBtn._active && root.savedViewModified
                        readonly property var _problems: svBtn.modelData.problems || []
                        countText: svBtn._problems.length > 0 ? "?"
                                 : (root._savedCounts[svBtn.modelData.id] !== undefined ? String(root._savedCounts[svBtn.modelData.id]) : "")
                        countColor: svBtn._problems.length > 0 ? Theme.warning : Theme.panel3
                        shortcutId: svBtn.index < 9 ? "savedView." + (svBtn.index + 1) : ""
                        tooltipText: svBtn._problems.length > 0
                            ? svBtn.modelData.name + " — " + I18n.t("topbar.searchUnknown").arg(svBtn._problems.join("  "))
                            : svBtn.modelData.name + (svBtn.modelData.query.length > 0 ? "  ·  " + svBtn.modelData.query : "")
                        Accessible.name: svBtn.modelData.name + (svBtn._problems.length > 0 ? "" : ", " + I18n.t("siderail.saved.count").arg(svBtn.countText))
                        onActivated: root.savedViewActivated(svBtn.modelData.id)
                        onContextRequested: root._openSavedMenu(svBtn, svBtn.modelData.id, svBtn.index)
                        Keys.onUpPressed: (e) => {
                            if (e.modifiers & Qt.ControlModifier) root._moveSavedView(svBtn.modelData.id, svBtn.index, -1);
                            else root.focusSavedView(svBtn.index - 1);
                        }
                        Keys.onDownPressed: (e) => {
                            if (e.modifiers & Qt.ControlModifier) root._moveSavedView(svBtn.modelData.id, svBtn.index, 1);
                            else root.focusSavedView(svBtn.index + 1);
                        }
                        Keys.onDeletePressed: root._deleteSavedView(svBtn.modelData.id, svBtn.index)
                        Keys.onPressed: (e) => {
                            if (e.key === Qt.Key_F2) {
                                root.savedViewRenameRequested(svBtn.modelData.id);
                                e.accepted = true;
                            } else if (e.key === Qt.Key_Menu || (e.key === Qt.Key_F10 && (e.modifiers & Qt.ShiftModifier))) {
                                root._openSavedMenu(svBtn, svBtn.modelData.id, svBtn.index);
                                e.accepted = true;
                            }
                        }
                    }
                }
                // Nothing saved yet: the one thing to do here.
                RailBtn {
                    objectName: "rail-saved-empty"
                    visible: root._savedViews.length === 0 && root.expanded
                    expanded: root.expanded
                    glyph: "+"
                    label: I18n.t("siderail.saved.empty")
                    tooltipText: I18n.t("siderail.saved.empty")
                    onActivated: root.saveViewRequested()
                }

                SectionHead { expanded: root.expanded; text: I18n.t("siderail.section.knowledge") }

                RailBtn {

                    expanded: root.expanded
                    objectName: "rail-docs"
                    iconSource: "qrc:/brand/icons/heap-08-docs.svg"
                    label: I18n.t("siderail.docs"); tooltipText: I18n.t("siderail.tip.docs"); shortcutId: "view.docs"
                    active: AppController.currentView === "docs"
                    onActivated: AppController.currentView = "docs" }
                RailBtn {
                    expanded: root.expanded
                    objectName: "rail-notes"
                    iconSource: "qrc:/brand/icons/heap-09-notes.svg"
                    label: I18n.t("siderail.notes"); tooltipText: I18n.t("siderail.tip.notes"); shortcutId: "view.notes"
                    active: AppController.currentView === "notes"
                    onActivated: AppController.currentView = "notes" }
            }
        }

        RailBtn {

            expanded: root.expanded
            id: hotkeysBtn
            objectName: "rail-hotkeys"
            iconSource: "qrc:/brand/icons/heap-10-hotkeys.svg"
            label: I18n.t("siderail.hotkeys"); tooltipText: I18n.t("siderail.tip.hotkeys"); shortcutId: "hotkeys.open"
            onActivated: root.openHotkeys(hotkeysBtn)
        }
        RailBtn {
            expanded: root.expanded
            id: tweaksBtn
            objectName: "rail-tweaks"
            iconSource: "qrc:/brand/icons/heap-11-tweaks.svg"
            label: I18n.t("siderail.tweaks"); tooltipText: I18n.t("siderail.tip.tweaks"); shortcutId: "tweaks.open"
            onActivated: root.openTweaks(tweaksBtn)
        }
        RailBtn {
            expanded: root.expanded
            objectName: "rail-settings"
            iconSource: "qrc:/brand/icons/heap-12-settings.svg"
            label: I18n.t("siderail.settings"); tooltipText: I18n.t("siderail.tip.settings"); shortcutId: "view.settings"
            active: AppController.currentView === "settings"
            onActivated: AppController.currentView = "settings"
            Layout.bottomMargin: Theme.spLg
        }
    }

    // One menu for every saved view row; the row sets which view it is for.
    AppMenu {
        id: savedMenu
        objectName: "rail-saved-menu"
        property string targetId: ""
        property int targetIndex: -1
        AppMenuItem {
            objectName: "rail-saved-apply"
            text: I18n.t("siderail.saved.apply")
            onTriggered: root.savedViewActivated(savedMenu.targetId)
        }
        AppMenuItem {
            objectName: "rail-saved-update"
            text: I18n.t("siderail.saved.update")
            onTriggered: root.savedViewUpdateRequested(savedMenu.targetId)
        }
        AppMenuItem {
            objectName: "rail-saved-rename"
            text: I18n.t("siderail.saved.rename")
            onTriggered: root.savedViewRenameRequested(savedMenu.targetId)
        }
        AppMenuItem {
            objectName: "rail-saved-duplicate"
            text: I18n.t("siderail.saved.duplicate")
            onTriggered: AppController.duplicateSavedView(savedMenu.targetId)
        }
        AppMenuSeparator {}
        AppMenuItem {
            objectName: "rail-saved-up"
            text: I18n.t("siderail.saved.moveUp")
            enabled: savedMenu.targetIndex > 0
            onTriggered: root._moveSavedView(savedMenu.targetId, savedMenu.targetIndex, -1)
        }
        AppMenuItem {
            objectName: "rail-saved-down"
            text: I18n.t("siderail.saved.moveDown")
            enabled: savedMenu.targetIndex >= 0 && savedMenu.targetIndex < root._savedViews.length - 1
            onTriggered: root._moveSavedView(savedMenu.targetId, savedMenu.targetIndex, 1)
        }
        AppMenuSeparator {}
        AppMenuItem {
            objectName: "rail-saved-delete"
            text: I18n.t("siderail.saved.delete")
            danger: true
            onTriggered: root._deleteSavedView(savedMenu.targetId, savedMenu.targetIndex)
        }
    }

    // A group title when expanded; the old 24px hairline when collapsed, so
    // the rail keeps the same rhythm it always had.
    component SectionHead: Item {
        id: sh
        property string text
        property bool expanded: true
        Layout.fillWidth: true
        Layout.topMargin: Theme.spMd
        Layout.preferredHeight: sh.expanded ? 22 : 13
        Text {
            visible: sh.expanded
            anchors.left: parent.left; anchors.leftMargin: Theme.spMd
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: sh.text
            elide: Text.ElideRight
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            font.weight: Theme.fwTitle
        }
        Rectangle {
            visible: !sh.expanded
            anchors.centerIn: parent
            width: 24; height: 1; color: Theme.border
        }
    }

    component RailBtn: Item {
        id: btn
        property bool expanded: true
        property url iconSource
        property string label: ""
        property string tooltipText: ""
        // The action's id in the shortcut catalog. Whatever it is bound to
        // now shows in the tooltip, and next to the label on hover, so the
        // rail teaches the keys instead of hiding them in the Hotkeys panel.
        property string shortcutId: ""
        readonly property string _combo: shortcutId.length && AppController.shortcuts.length >= 0
            ? AppController.shortcutFor(shortcutId) : ""
        // A text glyph in place of the icon (the collapse chevron).
        property string glyph: ""
        property bool active: false
        property string countText: ""
        property color countColor: Theme.danger
        // The icons are drawn on an 18px grid with 1px lines on the pixel
        // grid (APP-195); shown at 18, every line is one device pixel.
        property int iconSize: 18
        // Saved views: the glyph is the Alt+N digit, set in the mono face; a
        // view whose filters were changed since it was applied gets a dot.
        property bool glyphMono: false
        property bool modified: false
        signal activated()
        // Right click, or the Menu key on a row that has a menu.
        signal contextRequested()
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: btn.tooltipText || btn.label
        Accessible.onPressAction: btn.activated()
        Keys.onReturnPressed: btn.activated()
        Keys.onEnterPressed: btn.activated()
        Keys.onSpacePressed: btn.activated()
        Layout.fillWidth: true
        // Taller only when a long name needs its second line (APP-200).
        implicitHeight: Math.max(34, railLabel.implicitHeight + Theme.spMd)
        Layout.preferredHeight: implicitHeight

        readonly property color _fg: btn.active ? Theme.accentStrong
                                    : (ma.containsMouse ? Theme.text : Theme.textMuted)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMd
            color: btn.active ? Theme.accentSoft
                 : ma.containsMouse ? Theme.panel2 : "transparent"
            border.color: Theme.accentStrong
            border.width: btn.activeFocus ? 2 : 0
        }
        // Fixed 36px icon cell on the left: the icon sits where it did in
        // the rail, so collapsing does not make it jump sideways.
        Item {
            id: iconCell
            anchors.left: parent.left
            anchors.top: parent.top; anchors.bottom: parent.bottom
            width: 36
            IconImage {
                visible: btn.glyph === ""
                anchors.centerIn: parent
                source: btn.iconSource
                width: btn.iconSize
                height: btn.iconSize
                sourceSize.width: btn.iconSize
                sourceSize.height: btn.iconSize
                color: btn._fg
            }
            Text {
                visible: btn.glyph !== ""
                anchors.centerIn: parent
                text: btn.glyph
                color: btn._fg
                font.family: btn.glyphMono ? Theme.fontMono : Theme.fontUi
                font.pixelSize: btn.glyphMono ? Theme.fsSm : Theme.fsLg
            }
        }
        // A name that does not fit on the line steps down a size and, if it
        // still does not, takes a second line (APP-200): saved views are
        // named by the user, and "Срок на этой нед…" said less than its name.
        TextMetrics {
            id: labelFull
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            font.weight: btn.active ? Theme.fwTitle : Theme.fwBody
            font.italic: btn.modified
            text: railLabel.text
        }
        Text {
            id: railLabel
            objectName: "rail-label"
            readonly property bool tight: labelFull.advanceWidth > railLabel.width
            visible: btn.expanded
            opacity: btn.width > 96 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durTap; easing.type: Theme.easeEnter } }
            anchors.left: iconCell.right
            anchors.right: countBox.visible && btn.expanded ? countBox.left
                         : comboT.visible ? comboT.left : parent.right
            anchors.rightMargin: Theme.spMd
            anchors.verticalCenter: parent.verticalCenter
            text: btn.modified ? btn.label + " •" : btn.label
            wrapMode: railLabel.tight ? Text.WordWrap : Text.NoWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 0.95
            font.italic: btn.modified
            color: btn.active ? Theme.accentStrong : (ma.containsMouse ? Theme.text : Theme.textMuted)
            font.family: Theme.fontUi
            font.pixelSize: railLabel.tight ? Theme.fsSm : Theme.fsMd
            font.weight: btn.active ? Theme.fwTitle : Theme.fwBody
        }
        Text {
            id: comboT
            visible: btn.expanded && !countBox.visible && ma.containsMouse && btn._combo.length > 0
            anchors.right: parent.right; anchors.rightMargin: Theme.spMd
            anchors.verticalCenter: parent.verticalCenter
            text: btn._combo
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsXs
        }
        // Count badge: a pill at the row's right edge when expanded, the
        // corner dot over the icon when collapsed.
        Rectangle {
            id: countBox
            visible: btn.countText !== ""
            x: btn.expanded ? parent.width - width - 8 : 36 - width - 1
            y: btn.expanded ? (parent.height - height) / 2 : 1
            radius: height / 2
            color: btn.countColor
            implicitWidth: Math.max(implicitHeight, cntT.implicitWidth + 8)
            implicitHeight: cntT.implicitHeight + (btn.expanded ? 4 : 2)
            Text {
                id: cntT
                anchors.centerIn: parent
                text: btn.countText
                color: Theme.textOn(btn.countColor)
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsXs
                font.weight: Theme.fwTitle
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => {
                if (m.button === Qt.RightButton) {
                    btn.contextRequested();
                    return;
                }
                if (btn.shortcutId.length > 0) AppController.noteMouseAction(btn.shortcutId);
                btn.activated();
            }
            // Labels are on screen when expanded; the tooltip is only for
            // the icon-only rail.
            ToolTip.visible: containsMouse && !btn.expanded && btn.tooltipText !== ""
            ToolTip.text: btn._combo.length ? btn.tooltipText + "   " + btn._combo : btn.tooltipText
            ToolTip.delay: 400
        }
    }
}
