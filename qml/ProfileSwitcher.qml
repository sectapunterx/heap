pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

// The active profile at the top of the sidebar (APP-258): a dot and the
// name; the dot is the profile's colour, and turns the live colour while a
// sync has been out long enough to notice (APP-186) — a click on it then
// shows how the integrations are doing. The name opens the profile menu;
// with eight profiles or more the list is a picker with a search field.
Item {
    id: root

    // Only the dot when the sidebar is folded to its icons.
    property bool compact: false

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
    // The example profile (APP-271) goes from here: the sheets have no
    // banner for it (DG-001), only its name in the sidebar.
    signal removeExampleRequested()

    // A picker with a search field from this many profiles on.
    readonly property int pickerFrom: 8

    implicitHeight: Theme.chipH
    implicitWidth: row.implicitWidth

    readonly property var active: {
        const list = AppController.profiles;
        const id = AppController.activeProfileId;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return ({ name: I18n.t("topbar.profile.fallback"), color: Theme.accent });
    }

    // ── Sync in flight (APP-186) ──
    // Bound to the controller; a test can set it by hand.
    property bool syncing: AppController.syncing
    // How long a sync runs before the dot says so.
    readonly property int syncDotDelay: 400
    property real _syncSince: 0
    property bool syncDotShown: false
    function syncDotDue(running, since, now) {
        return running && since > 0 && now - since >= root.syncDotDelay;
    }
    onSyncingChanged: {
        root._syncSince = root.syncing ? Date.now() : 0;
        root.syncDotShown = false;
        syncDotTimer.interval = root.syncDotDelay;
        if (root.syncing) syncDotTimer.restart();
        else syncDotTimer.stop();
    }
    Timer {
        id: syncDotTimer
        onTriggered: {
            const now = Date.now();
            if (root.syncDotDue(root.syncing, root._syncSince, now)) {
                root.syncDotShown = true;
            } else if (root.syncing) {
                // A coarse timer may wake a little early.
                syncDotTimer.interval = Math.max(1, root._syncSince + root.syncDotDelay - now);
                syncDotTimer.restart();
            }
        }
    }

    function openMenu() {
        if (AppController.profiles.length >= root.pickerFrom) picker.openAt(root);
        else profileMenu.popup(root, 0, root.height + Theme.spXs);
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        spacing: Theme.spSm

        Item {
            id: syncDot
            objectName: "sidebar-sync-dot"
            width: Theme.spLg
            height: root.height
            Rectangle {
                anchors.centerIn: parent
                width: Theme.spSm
                height: Theme.spSm
                radius: height / 2
                color: root.syncDotShown ? (syncDotMA.hovered ? Theme.withAlpha(Theme.live, 0.7) : Theme.live)
                                         : (root.active.color || Theme.accent)
            }
            ClickArea {
                id: syncDotMA
                objectName: "sidebar-sync-dot-area"
                enabled: root.syncDotShown
                label: I18n.t("topbar.syncing")
                tip: I18n.t("topbar.syncing.tip")
                onActivated: root.syncStatusRequested()
            }
        }
        Text {
            id: nameT
            objectName: "sidebar-profile-name"
            visible: !root.compact
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, root.width - syncDot.width - row.spacing))
            text: root.active.name || I18n.t("topbar.profile.fallback")
            elide: Text.ElideRight
            color: nameMA.hovered ? Theme.text : Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            font.weight: Theme.fwBody
        }
    }
    ClickArea {
        id: nameMA
        objectName: "sidebar-profile"
        // The full name for the pointer and the screen reader, the dot's
        // own area keeps the sync status.
        anchors.fill: undefined
        x: row.x + (root.compact ? 0 : nameT.x)
        width: root.compact ? syncDot.width : nameT.width
        height: root.height
        role: Accessible.ButtonMenu
        label: I18n.t("topbar.profile") + ": " + (root.active.name || I18n.t("topbar.profile.fallback"))
        tip: root.active.name || ""
        showTip: root.compact || nameT.truncated
        onActivated: root.openMenu()
    }

    AppMenu {
        id: profileMenu
        objectName: "sidebar-profile-menu"
        Instantiator {
            model: AppController.profiles.length < root.pickerFrom ? AppController.profiles : []
            delegate: AppMenuItem {
                id: profRow
                required property var modelData
                marked: profRow.modelData.id === AppController.activeProfileId
                text: profRow.modelData.name
                onTriggered: AppController.activeProfileId = profRow.modelData.id
            }
            onObjectAdded: (idx, obj) => profileMenu.insertItem(idx, obj)
            onObjectRemoved: (idx, obj) => profileMenu.removeItem(obj)
        }
        AppMenuSeparator {}
        AppMenuItem { text: I18n.t("topbar.profile.new"); onTriggered: root.newProfileRequested() }
        AppMenuItem { text: I18n.t("topbar.profile.rename"); onTriggered: root.renameProfileRequested() }
        AppMenuItem { text: I18n.t("topbar.profile.duplicate"); onTriggered: root.duplicateProfileRequested() }
        AppMenuSeparator {}
        AppMenuItem { text: I18n.t("topbar.profile.import"); onTriggered: root.importJsonRequested() }
        AppMenuItem { text: I18n.t("topbar.profile.export"); onTriggered: root.exportJsonRequested() }
        AppMenuSeparator {}
        AppMenuItem { text: I18n.t("topbar.cal.import"); onTriggered: root.importIcsRequested() }
        AppMenuItem { text: I18n.t("topbar.cal.export"); onTriggered: root.exportIcsRequested() }
        AppMenuSeparator {}
        AppMenuItem { text: I18n.t("topbar.notes.import"); onTriggered: root.importVaultRequested() }
        AppMenuItem { text: I18n.t("topbar.notes.export"); onTriggered: root.exportVaultRequested() }
        // Last, apart and in red, and it says which profile goes (DES-9).
        AppMenuSeparator {}
        AppMenuItem {
            objectName: "sidebar-profile-remove-example"
            visible: AppController.activeProfileId === "lowkey-example"
            height: visible ? implicitHeight : 0
            text: I18n.t("example.remove")
            danger: true
            onTriggered: root.removeExampleRequested()
        }
        AppMenuItem {
            objectName: "sidebar-profile-delete"
            visible: AppController.activeProfileId !== "lowkey-example"
            height: visible ? implicitHeight : 0
            text: I18n.t("topbar.profile.delete").arg(root.active.name || I18n.t("topbar.profile.fallback"))
            danger: true
            enabled: AppController.profiles.length > 1
            onTriggered: AppController.deleteProfile(AppController.activeProfileId)
        }
    }

    // Eight profiles or more: a search field over the list, the actions in
    // the menu behind "More…".
    QQC.Popup {
        id: picker
        objectName: "sidebar-profile-picker"
        padding: Theme.spXs
        width: Theme.px(260)
        height: Math.min(Theme.px(420), pickCol.implicitHeight + 2 * Theme.spXs)
        background: PopupSurface {}
        property string filter: ""
        readonly property var matches: {
            const q = picker.filter.trim().toLowerCase();
            const all = AppController.profiles;
            return q.length === 0 ? all : all.filter(p => String(p.name).toLowerCase().indexOf(q) >= 0);
        }
        function openAt(anchor) {
            picker.parent = anchor;
            picker.x = 0;
            picker.y = anchor.height + Theme.spXs;
            picker.filter = "";
            search.text = "";
            pickList.currentIndex = 0;
            picker.open();
            search.forceActiveFocus();
        }
        function choose(i) {
            const p = picker.matches[i];
            if (!p) return;
            AppController.activeProfileId = p.id;
            picker.close();
        }
        ColumnLayout {
            id: pickCol
            anchors.fill: parent
            spacing: Theme.spXs
            TextField {
                id: search
                objectName: "sidebar-profile-search"
                Layout.fillWidth: true
                placeholderText: I18n.t("sidebar.profile.find")
                color: Theme.text
                placeholderTextColor: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                background: Rectangle { radius: Theme.radiusMd; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                onTextChanged: { picker.filter = text; pickList.currentIndex = 0; }
                Keys.onDownPressed: pickList.currentIndex = Math.min(pickList.count - 1, pickList.currentIndex + 1)
                Keys.onUpPressed: pickList.currentIndex = Math.max(0, pickList.currentIndex - 1)
                Keys.onReturnPressed: picker.choose(pickList.currentIndex)
                Keys.onEnterPressed: picker.choose(pickList.currentIndex)
                Keys.onEscapePressed: picker.close()
            }
            ListView {
                id: pickList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                clip: true
                model: picker.matches
                boundsBehavior: Flickable.StopAtBounds
                delegate: AppMenuItem {
                    id: pickRow
                    required property var modelData
                    required property int index
                    width: pickList.width
                    text: pickRow.modelData.name
                    marked: pickRow.modelData.id === AppController.activeProfileId
                    highlighted: pickRow.index === pickList.currentIndex
                    onTriggered: picker.choose(pickRow.index)
                }
                ScrollBar.vertical: ThinScrollBar {}
            }
            Text {
                visible: picker.matches.length === 0
                Layout.leftMargin: Theme.spMd
                text: I18n.t("sidebar.profile.none")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
            }
            AppMenuItem {
                Layout.fillWidth: true
                text: I18n.t("sidebar.profile.more")
                onTriggered: {
                    picker.close();
                    profileMenu.popup(root, 0, root.height + Theme.spXs);
                }
            }
        }
    }
}
