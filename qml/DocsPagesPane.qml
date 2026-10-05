import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// Docs pages: the tree on the left, the page on the right.
//
// The catalog next door holds links, snippets and contacts — all of them one
// line long. This is where the paragraph explaining why the link matters goes,
// which is the half a team's docs actually need and the half that used to end
// up in Notes or in somebody's head.
Item {
    id: root

    property string filter: ""

    // A [[note]], #TICKET or @person clicked in a page's preview.
    signal linkActivated(string kind, string target)

    // Flush first: the editor debounces its saves, so switching pages would
    // drop the last keystrokes.
    function _openPage(id) {
        editorPane.flush();
        AppController.activeDocPageId = id;
    }

    // Ctrl+F on the Pages tab: the page filter, not the catalogue search.
    function focusFilter() {
        pageFilter.forceActiveFocus();
        pageFilter.selectAll();
    }

    // Bumped by the model so the tree rebuilds.
    property int rev: 0

    // Which parents are open. A page with children starts closed, or a deep
    // tree opens as a wall of rows nobody asked for.
    property var expanded: ({})

    function _data(idx, name) {
        const m = AppController.docPages;
        const r = m.roleOf(name);
        return r < 0 ? undefined : m.data(idx, r);
    }

    function isExpanded(id) {
        return root.expanded[id] === true;
    }

    function toggle(id) {
        // Reassigned wholesale: QML does not track a write into a var map.
        const next = ({});
        for (const k in root.expanded) next[k] = root.expanded[k];
        next[id] = !next[id];
        root.expanded = next;
    }

    // Flat rows with a depth, which is what a ListView can draw and what the
    // keyboard can walk. A filter flattens the tree instead of pruning it:
    // hiding a match because its parent is closed is the one thing a search
    // must not do.
    function buildRows() {
        const _r = root.rev;
        const m = AppController.docPages;
        const needle = root.filter.trim().toLowerCase();

        if (needle.length > 0) {
            // Title and the whole body, not a one-line excerpt: a word from
            // the middle of a page has to find it.
            const hits = AppController.docPagesMatching(needle);
            const allowed = ({});
            for (let h = 0; h < hits.length; h++) allowed[hits[h]] = true;
            const flat = [];
            for (let i = 0; i < m.rowCount(); i++) {
                const idx = m.index(i, 0);
                const title = String(root._data(idx, "title") || "");
                const excerpt = String(root._data(idx, "excerpt") || "");
                if (!allowed[String(root._data(idx, "id"))]) continue;
                flat.push({
                    id: String(root._data(idx, "id")),
                    title: title,
                    excerpt: excerpt,
                    depth: 0,
                    hasChildren: false
                });
            }
            flat.sort(function (a, b) {
                return a.title.toLowerCase() < b.title.toLowerCase() ? -1
                     : a.title.toLowerCase() > b.title.toLowerCase() ? 1 : 0;
            });
            return flat;
        }

        const rows = [];
        const walk = function (parentId, depth) {
            // Depth-capped: a cycle cannot exist (moveDocPage refuses one), but
            // a corrupt file could still describe a parent chain that loops.
            if (depth > 12) return;
            const kids = AppController.docPageChildren(parentId);
            for (let i = 0; i < kids.length; i++) {
                const k = kids[i];
                rows.push({
                    id: k.id,
                    title: k.title,
                    excerpt: "",
                    depth: depth,
                    hasChildren: k.hasChildren
                });
                if (k.hasChildren && root.isExpanded(k.id)) walk(k.id, depth + 1);
            }
        };
        walk("", 0);
        return rows;
    }
    readonly property var rows: buildRows()

    Connections {
        target: AppController.docPages
        function onRowsInserted() { root.rev++ }
        function onRowsRemoved()  { root.rev++ }
        function onDataChanged()  { root.rev++ }
        function onModelReset()   { root.rev++ }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── The tree ──
        Rectangle {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            color: Theme.panel
            Rectangle {
                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: 1; color: Theme.border
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spLg
                anchors.rightMargin: Theme.spLg
                spacing: Theme.spMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spSm
                    Text {
                        text: I18n.t("docs.pages").toUpperCase()
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsXs
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        objectName: "docpage-new"
                        width: 22; height: 22; radius: Theme.radiusSm
                        color: newMA.hovered ? Theme.panel3 : Theme.panel2
                        border.color: Theme.border; border.width: 1
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.text; font.pixelSize: Theme.fsLg }
                        ClickArea {
                            id: newMA
                            objectName: "docpage-new-button"
                            label: I18n.t("docs.newPage")
                            onActivated: AppController.newDocPage()
                        }
                    }
                }

                QQC.TextField {
                    id: pageFilter
                    QQC.ContextMenu.menu: TextEditMenu { editor: pageFilter }
                    objectName: "docpage-filter"
                    Layout.fillWidth: true
                    placeholderText: I18n.t("docs.filterPages")
                    placeholderTextColor: Theme.textDim
                    color: Theme.text
                    font.pixelSize: Theme.fsSm
                    background: FieldFrame {}
                    onTextChanged: root.filter = text
                }

                Text {
                    visible: root.rows.length === 0
                    Layout.fillWidth: true
                    text: root.filter.length > 0 ? I18n.t("docs.noPageMatches") : I18n.t("docs.noPages")
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm
                    wrapMode: Text.Wrap
                }

                ListView {
                    id: tree
                    objectName: "docpage-tree"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    // Keyboard (design audit DES-3): Tab lands on the tree,
                    // ↑/↓ walk it, Enter opens the page, →/← unfold and fold,
                    // the menu key (or Shift+F10) opens the row's menu —
                    // rename, subpage, delete had no keyboard path at all.
                    activeFocusOnTab: true
                    keyNavigationEnabled: true
                    Accessible.role: Accessible.Tree
                    signal menuRequested()
                    onActiveFocusChanged: if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0
                    Keys.onReturnPressed: if (tree.currentIndex >= 0) root._openPage(root.rows[tree.currentIndex].id)
                    Keys.onEnterPressed: if (tree.currentIndex >= 0) root._openPage(root.rows[tree.currentIndex].id)
                    Keys.onPressed: (event) => {
                        if (tree.currentIndex < 0) return;
                        const d = root.rows[tree.currentIndex];
                        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                            tree.menuRequested();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right && d.hasChildren && !root.isExpanded(d.id)) {
                            root.toggle(d.id);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left && d.hasChildren && root.isExpanded(d.id)) {
                            root.toggle(d.id);
                            event.accepted = true;
                        }
                    }
                    spacing: 1
                    model: root.rows
                    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: pageRow
                        required property var modelData
                        objectName: "docpage-row-" + pageRow.modelData.id
                        width: tree.width
                        height: 30
                        radius: Theme.radiusMd
                        readonly property bool current: pageRow.modelData.id === AppController.activeDocPageId
                        color: pageRow.current ? Theme.withAlpha(Theme.accent, 0.14)
                             : rowMA.containsMouse ? Theme.panel2 : "transparent"
                        Accessible.role: Accessible.TreeItem
                        Accessible.name: pageRow.modelData.title || ""
                        function openMenu() { pageMenu.popup(pageRow, Theme.spXl, pageRow.height / 2); }
                        Connections {
                            target: pageRow.ListView.view
                            function onMenuRequested() { if (pageRow.ListView.isCurrentItem) pageRow.openMenu(); }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.color: Theme.focusRing
                            border.width: 2
                            visible: pageRow.ListView.isCurrentItem && pageRow.ListView.view.activeFocus
                            z: 10
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6 + (pageRow.modelData.depth * 14)
                            anchors.rightMargin: Theme.spMd
                            spacing: Theme.spXs

                            // The disclosure triangle only where there is
                            // something to disclose; an empty slot keeps the
                            // titles of childless siblings aligned.
                            Item {
                                Layout.preferredWidth: 14
                                Layout.preferredHeight: 14
                                Text {
                                    anchors.centerIn: parent
                                    visible: pageRow.modelData.hasChildren
                                    text: root.isExpanded(pageRow.modelData.id) ? "▾" : "▸"
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fsXs
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    enabled: pageRow.modelData.hasChildren
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggle(pageRow.modelData.id)
                                }
                            }

                            Text {
                                text: pageRow.modelData.title || ""
                                color: Theme.text
                                font.pixelSize: Theme.fsSm
                                font.weight: pageRow.current ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: rowMA
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) { pageMenu.popup(); return; }
                                root._openPage(pageRow.modelData.id);
                            }
                        }

                        AppMenu {
                            id: pageMenu
                            AppMenuItem {
                                text: I18n.t("docs.newSubpage")
                                onTriggered: {
                                    // Opening the parent, or the new page lands
                                    // somewhere the tree is not showing.
                                    if (!root.isExpanded(pageRow.modelData.id)) root.toggle(pageRow.modelData.id);
                                    AppController.newDocPage("", pageRow.modelData.id);
                                }
                            }
                            AppMenuItem {
                                text: I18n.t("docs.renamePage")
                                onTriggered: renamePagePopup.openFor(pageRow.modelData.id, pageRow.modelData.title)
                            }
                            AppMenuSeparator {}
                            AppMenuItem {
                                text: pageRow.modelData.hasChildren ? I18n.t("docs.deletePageTree")
                                                                    : I18n.t("common.delete")
                                danger: true
                                onTriggered: AppController.deleteDocPage(pageRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // ── The page ──
        MdEditorPane {
            id: editorPane
            objectName: "docpage-editor"
            Layout.fillWidth: true
            Layout.fillHeight: true
            pageId: AppController.activeDocPageId
            emptyText: I18n.t("docs.noPageOpen")
            onInternalLinkActivated: (kind, target) => root.linkActivated(kind, target)
        }
    }

    QQC.Dialog {
        id: renamePagePopup
        objectName: "docpage-rename"
        property string pageId: ""
        modal: true
        anchors.centerIn: QQC.Overlay.overlay
        parent: QQC.Overlay.overlay
        padding: Theme.inset
        width: 380
        title: I18n.t("docs.renamePage")

        function openFor(id, title) {
            renamePagePopup.pageId = id;
            pageTitleField.text = title;
            renamePagePopup.open();
            pageTitleField.forceActiveFocus();
            pageTitleField.selectAll();
        }

        function commit() {
            AppController.renameDocPage(renamePagePopup.pageId, pageTitleField.text);
            renamePagePopup.close();
        }

        background: Rectangle {
            radius: Theme.radiusXl
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        contentItem: QQC.TextField {
            id: pageTitleField
            objectName: "docpage-rename-title"
            implicitWidth: 320
            color: Theme.text
            background: FieldFrame {}
            onAccepted: renamePagePopup.commit()
        }

        footer: RowLayout {
            spacing: Theme.spMd
            Layout.margins: Theme.sp2xl
            Item { Layout.fillWidth: true }
            PillButton { text: I18n.t("common.cancel"); onClicked: renamePagePopup.close() }
            PillButton { text: I18n.t("editor.btn.save"); primary: true; onClicked: renamePagePopup.commit() }
        }
    }
}
