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
    signal newTaskRequested()
    signal newProfileRequested()
    signal renameProfileRequested()
    signal duplicateProfileRequested()
    signal exportJsonRequested()
    signal importJsonRequested()

    function focusSearch() {
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    function _activeProfileMap() {
        const list = AppController.profiles;
        const id = AppController.activeProfileId;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return ({ name: "—", color: "#5cc2dd" });
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
        anchors.rightMargin: 16
        spacing: 14

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
            spacing: 4
            EditableCrumb {
                value: AppController.crumbProject
                placeholder: "project"
                bold: true
                onCommitted: (v) => AppController.crumbProject = v
            }
            CrumbSep {}
            // sprint segment — derived; not editable
            Text {
                text: AppController.sprintLabel()
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 12
            }
            CrumbSep {}
            EditableCrumb {
                value: AppController.crumbUser
                placeholder: "you"
                bold: true
                onCommitted: (v) => AppController.crumbUser = v
            }
            CrumbSep {}

            // Profile pill — color dot + name + dropdown
            Rectangle {
                id: profilePill
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: 6
                color: profileMA.containsMouse ? Theme.panel2 : Theme.panel3
                border.color: profileMA.containsMouse ? Theme.borderStrong : Theme.border
                border.width: 1
                implicitWidth: pillRow.implicitWidth + 16

                property var active: root._activeProfileMap()

                RowLayout {
                    id: pillRow
                    anchors.fill: parent
                    anchors.leftMargin: 8; anchors.rightMargin: 8
                    spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: profilePill.active.color || Theme.accent
                    }
                    Text {
                        text: profilePill.active.name || "Profile"
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    Text {
                        text: "▾"
                        color: Theme.textDim
                        font.pixelSize: 10
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

                QQC.Menu {
                    id: profileMenu

                    // Profile rows are inserted dynamically at the top of the
                    // menu via Instantiator, so they show before the static
                    // actions in declaration-order.
                    Instantiator {
                        id: profilesInst
                        model: AppController.profiles
                        delegate: QQC.MenuItem {
                            required property var modelData
                            text: (modelData.id === AppController.activeProfileId ? "✓ " : "    ")
                                  + modelData.name
                            onTriggered: AppController.activeProfileId = modelData.id
                        }
                        onObjectAdded:   (idx, obj) => profileMenu.insertItem(idx, obj)
                        onObjectRemoved: (idx, obj) => profileMenu.removeItem(obj)
                    }
                    QQC.MenuSeparator {}
                    QQC.MenuItem {
                        text: I18n.t("topbar.profile.new"); onTriggered: root.newProfileRequested()
                    }
                    QQC.MenuItem {
                        text: I18n.t("topbar.profile.rename"); onTriggered: root.renameProfileRequested()
                    }
                    QQC.MenuItem {
                        text: I18n.t("topbar.profile.duplicate"); onTriggered: root.duplicateProfileRequested()
                    }
                    QQC.MenuItem {
                        text: I18n.t("topbar.profile.delete")
                        enabled: AppController.profiles.length > 1
                        onTriggered: AppController.deleteProfile(AppController.activeProfileId)
                    }
                    QQC.MenuSeparator {}
                    QQC.MenuItem {
                        text: I18n.t("topbar.profile.import"); onTriggered: root.importJsonRequested()
                    }
                    QQC.MenuItem {
                        text: I18n.t("topbar.profile.export"); onTriggered: root.exportJsonRequested()
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
            radius: 6
            color: Theme.accentSoft
            border.color: Theme.accent
            border.width: 1
            implicitWidth: bannerRow.implicitWidth + 14
            RowLayout {
                id: bannerRow
                anchors.fill: parent
                anchors.leftMargin: 8; anchors.rightMargin: 6
                spacing: 8
                Text {
                    text: "⎇"
                    color: Theme.accentStrong
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                }
                Text {
                    text: "Working on " + AppController.focusedTaskId
                    color: Theme.accentStrong
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                // ── Live PR state on the focused repo (HEAP-76) ──
                Rectangle {
                    id: prBadge
                    property var pr: AppController.focusedRepoState
                                     ? AppController.focusedRepoState.pr : null
                    visible: pr && String(pr.state || "").length > 0
                          && Number(pr.number || 0) > 0
                    radius: 4
                    implicitWidth: prBadgeT.implicitWidth + 12
                    implicitHeight: 18
                    color: {
                        const s = prBadge.pr ? String(prBadge.pr.state || "") : "";
                        if (s === "merged") return Theme.withAlpha(Theme.mFocus, 0.20);
                        if (s === "closed") return Theme.withAlpha(Theme.textDim, 0.20);
                        return Theme.withAlpha(Theme.p1, 0.20);
                    }
                    border.width: 1
                    border.color: {
                        const s = prBadge.pr ? String(prBadge.pr.state || "") : "";
                        if (s === "merged") return Theme.mFocus;
                        if (s === "closed") return Theme.textDim;
                        return Theme.p1;
                    }
                    Text {
                        id: prBadgeT
                        anchors.centerIn: parent
                        text: {
                            if (!prBadge.pr) return "";
                            const n = prBadge.pr.number || 0;
                            const s = String(prBadge.pr.state || "");
                            const d = prBadge.pr.draft === true ? " · draft" : "";
                            return "PR #" + n + " " + s + d;
                        }
                        color: Theme.accentStrong
                        font.family: Theme.fontMono
                        font.pixelSize: 10
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
                    radius: 4
                    implicitWidth: ciT.implicitWidth + 12
                    implicitHeight: 18
                    color: {
                        if (ciBadge.ci === "passing") return Theme.withAlpha(Theme.mFocus, 0.20);
                        if (ciBadge.ci === "failing") return Theme.withAlpha(Theme.p0, 0.20);
                        return Theme.withAlpha(Theme.p2, 0.20);
                    }
                    border.width: 1
                    border.color: {
                        if (ciBadge.ci === "passing") return Theme.mFocus;
                        if (ciBadge.ci === "failing") return Theme.p0;
                        return Theme.p2;
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
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    radius: 4
                    color: openMA.containsMouse ? Theme.accentStrong : "transparent"
                    border.color: Theme.accentStrong
                    border.width: 1
                    implicitWidth: openT.implicitWidth + 12
                    implicitHeight: 18
                    Text {
                        id: openT
                        anchors.centerIn: parent
                        text: "Open"
                        color: openMA.containsMouse ? Theme.bg : Theme.accentStrong
                        font.pixelSize: 10
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
                Text {
                    text: "×"
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 14
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AppController.dismissGitBanner()
                    }
                }
            }
        }

        // Search
        Rectangle {
            Layout.preferredWidth: 280
            Layout.preferredHeight: 28
            radius: 6
            color: Theme.panel2
            border.color: searchField.activeFocus ? Theme.accent : Theme.border
            border.width: searchField.activeFocus ? 2 : 1
            Behavior on border.color { ColorAnimation { duration: Theme.scaledMs(120) } }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 6
                spacing: 4
                Text { text: "⌕"; color: Theme.textDim; font.pixelSize: 11 }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: I18n.t("topbar.search")
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    background: Item {}
                    selectByMouse: true
                }
                Rectangle {
                    radius: 4
                    border.color: Theme.border; border.width: 1
                    color: "transparent"
                    width: kbd.implicitWidth + 10; height: 16
                    Text {
                        id: kbd; anchors.centerIn: parent
                        text: "⌘K"; color: Theme.textDim
                        font.family: Theme.fontMono; font.pixelSize: 10
                    }
                }
            }
        }

        PillButton {
            text: "+ Task"
            primary: true
            onClicked: root.newTaskRequested()
        }
    }

    component CrumbSep: Text {
        text: "/"
        color: Theme.textMuted
        font.family: Theme.fontMono
        font.pixelSize: 12
    }

    component EditableCrumb: Item {
        id: ec
        property string value: ""
        property string placeholder: ""
        property bool bold: false
        property bool editing: false
        signal committed(string text)

        implicitWidth: editing ? Math.max(60, edit.implicitWidth + 12) : Math.max(20, label.implicitWidth + 6)
        implicitHeight: 22

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: hoverMA.containsMouse && !ec.editing ? Theme.panel2 : (ec.editing ? Theme.panel2 : "transparent")
            border.color: ec.editing ? Theme.accent : "transparent"
            border.width: ec.editing ? 1 : 0
        }

        Text {
            id: label
            anchors.centerIn: parent
            visible: !ec.editing
            text: ec.value.length > 0 ? ec.value : ec.placeholder
            color: ec.value.length > 0 ? Theme.text : Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.weight: ec.bold ? Font.Medium : Font.Normal
        }

        TextField {
            id: edit
            anchors.fill: parent
            anchors.leftMargin: 4; anchors.rightMargin: 4
            visible: ec.editing
            text: ec.value
            placeholderText: ec.placeholder
            color: Theme.text
            placeholderTextColor: Theme.textDim
            background: Item {}
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontMono
            font.pixelSize: 12
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
            onClicked: {
                ec.editing = true;
                edit.forceActiveFocus();
                edit.selectAll();
            }
        }
    }
}
