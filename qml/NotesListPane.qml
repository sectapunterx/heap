pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// The list of notes, beside the one being edited.
//
// Notes were one document per profile, so this pane had nothing to show and did
// not exist. Now that a profile holds many, the editor needs something that
// says which one is open and lets another be reached without a search.
//
// Pinned notes first, then folders, then loose notes — the order somebody
// scanning for a note actually uses, rather than the order they were created.
Rectangle {
    id: root

    property string filter: ""

    // Bumped by the model so the grouping rebuilds.
    property int rev: 0

    signal noteActivated(string id)
    // After "+": the view puts the cursor in the new note.
    signal noteCreated(string id)

    color: Theme.panel
    implicitWidth: 240

    function _data(idx, name) {
        const m = AppController.notes;
        const r = m.roleOf(name);
        return r < 0 ? undefined : m.data(idx, r);
    }

    // Flat rows with a `kind`, so one ListView can draw both headers and notes
    // and the keyboard can walk them without a second structure to keep in step.
    function buildRows() {
        const m = AppController.notes;
        const needle = root.filter.trim();
        // The whole body, not the excerpt: a word from the middle of a note
        // has to find it. Asked of the controller, which holds the bodies.
        const hits = needle.length > 0 ? AppController.notesMatching(needle) : null;
        const allowed = ({});
        if (hits) for (let h = 0; h < hits.length; h++) allowed[hits[h]] = true;

        const pinned = [];
        const byFolder = ({});
        const loose = [];
        const rId = m.roleOf("id"), rTitle = m.roleOf("title"), rFolder = m.roleOf("folder");
        const rPinned = m.roleOf("pinned"), rExcerpt = m.roleOf("excerpt");
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            const id = String(m.data(idx, rId));
            if (hits && !allowed[id]) continue;
            const note = {
                id:      id,
                title:   String(m.data(idx, rTitle) || ""),
                folder:  String(m.data(idx, rFolder) || ""),
                pinned:  !!m.data(idx, rPinned),
                excerpt: String(m.data(idx, rExcerpt) || "")
            };
            if (note.pinned) pinned.push(note);
            else if (note.folder.length > 0) {
                if (!byFolder[note.folder]) byFolder[note.folder] = [];
                byFolder[note.folder].push(note);
            } else loose.push(note);
        }

        const byTitle = function (a, b) {
            return a.title.toLowerCase() < b.title.toLowerCase() ? -1
                 : a.title.toLowerCase() > b.title.toLowerCase() ? 1 : 0;
        };
        pinned.sort(byTitle);
        loose.sort(byTitle);

        const rows = [];
        if (pinned.length > 0) {
            rows.push({ kind: "header", label: I18n.t("notes.pinned") });
            for (const n of pinned) rows.push({ kind: "note", note: n, inPinnedSection: true });
        }
        const folders = Object.keys(byFolder).sort();
        for (const f of folders) {
            rows.push({ kind: "header", label: f, folder: f });
            byFolder[f].sort(byTitle);
            for (const n of byFolder[f]) rows.push({ kind: "note", note: n });
        }
        if (loose.length > 0) {
            if (rows.length > 0) rows.push({ kind: "header", label: I18n.t("notes.other") });
            for (const n of loose) rows.push({ kind: "note", note: n });
        }
        return rows;
    }

    // Rebuilt on purpose rather than as a binding. As a binding it re-ran for
    // every row the model inserted — six hundred notes created in a loop meant
    // six hundred full rebuilds — and every rebuild handed the ListView a new
    // model, which threw the reader back to the top after each 250 ms save.
    // Now model changes are coalesced into one rebuild per event-loop turn, a
    // rebuild that changes nothing is not handed to the view at all, and one
    // that does keeps the scroll position.
    property var rows: []
    property string _rowsKey: ""
    property bool _rebuildQueued: false
    function rebuildNow() {
        root._rebuildQueued = false;
        const next = root.buildRows();
        const key = JSON.stringify(next);
        if (key === root._rowsKey) return;
        const y = list.contentY;
        root._rowsKey = key;
        root.rows = next;
        list.contentY = Math.max(0, Math.min(y, list.contentHeight - list.height));
    }
    function scheduleRebuild() {
        if (root._rebuildQueued) return;
        root._rebuildQueued = true;
        Qt.callLater(root.rebuildNow);
    }
    onFilterChanged: rebuildNow()
    Component.onCompleted: rebuildNow()
    Connections {
        target: I18n
        function onLangChanged() { root.rebuildNow() }
    }

    // The filter, set from outside: a #tag clicked in a note lists the notes
    // carrying it.
    function setFilter(text) {
        filterField.text = text;
        root.filter = text;
    }
    // F2: the rename dialog for the open note, wherever the focus is.
    function renameActive() {
        const m = AppController.notes;
        const row = m.indexOfId(AppController.activeNoteId);
        if (row < 0) return;
        const idx = m.index(row, 0);
        renamePopup.openFor(AppController.activeNoteId, String(m.data(idx, m.roleOf("title")) || ""),
                            String(m.data(idx, m.roleOf("folder")) || ""));
    }
    function takeFocus() { list.forceActiveFocus(); }
    function focusFilter() {
        filterField.forceActiveFocus();
        filterField.selectAll();
    }
    // Esc in the editor lands here, on the open note's row, so ↑/↓ walk the
    // notes from where the reader was.
    function focusList() {
        list.forceActiveFocus(Qt.OtherFocusReason);
        root._activeRowItem();
    }

    // The ids on screen, in order, so a caller can step through them.
    function visibleIds() {
        if (root._rebuildQueued) root.rebuildNow();
        const out = [];
        for (let i = 0; i < root.rows.length; i++)
            if (root.rows[i].kind === "note") out.push(root.rows[i].note.id);
        return out;
    }

    // The list row of the open note, scrolled into view — the keyboard's
    // way into that row's menu.
    function _activeRowItem() {
        if (root._rebuildQueued) root.rebuildNow();
        for (let i = 0; i < root.rows.length; i++) {
            const r = root.rows[i];
            if (r.kind !== "note" || r.note.id !== AppController.activeNoteId) continue;
            list.positionViewAtIndex(i, ListView.Contain);
            const loader = list.itemAtIndex(i) as Loader;
            return loader ? loader.item : null;
        }
        return null;
    }

    // Open the note `delta` places from the open one. Headers are skipped
    // because they are not somewhere the selection can land.
    function step(delta) {
        const ids = root.visibleIds();
        if (ids.length === 0) return;
        const at = ids.indexOf(AppController.activeNoteId);
        const next = at < 0 ? 0 : Math.max(0, Math.min(ids.length - 1, at + delta));
        root.noteActivated(ids[next]);
    }

    Connections {
        target: AppController.notes
        function onRowsInserted() { root.scheduleRebuild() }
        function onRowsRemoved()  { root.scheduleRebuild() }
        function onDataChanged()  { root.scheduleRebuild() }
        function onModelReset()   { root.scheduleRebuild() }
    }
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
                text: I18n.t("notes.all").toUpperCase()
                color: Theme.textMuted
                font.pixelSize: Theme.fsXs
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                Layout.fillWidth: true
            }
            Rectangle {
                objectName: "note-new"
                width: 22; height: 22; radius: Theme.radiusSm
                color: newMA.hovered ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.text
                    font.pixelSize: Theme.fsLg
                }
                ClickArea {
                    id: newMA
                    objectName: "notes-new"
                    label: I18n.t("notes.newNote")
                    shortcutId: "notes.new"
                    onActivated: {
                        const id = AppController.newNote();
                        root.noteActivated(id);
                        root.noteCreated(id);
                    }
                }
            }
        }

        QQC.TextField {
            id: filterField
            QQC.ContextMenu.menu: TextEditMenu { editor: filterField }
            objectName: "note-filter"
            Layout.fillWidth: true
            placeholderText: I18n.t("notes.filter")
            placeholderTextColor: Theme.textDim
            color: Theme.text
            font.pixelSize: Theme.fsSm
            background: FieldFrame {}
            onTextChanged: root.filter = text
        }

        Text {
            visible: root.rows.length === 0
            Layout.fillWidth: true
            text: root.filter.length > 0 ? I18n.t("notes.noMatches") : I18n.t("notes.empty")
            color: Theme.textDim
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            objectName: "note-list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.sp2xs
            model: root.rows
            QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }
            // Keyboard (design audit DES-3): Tab lands on the list, ↑/↓ open
            // the next note, the menu key (or Shift+F10) opens the open
            // note's menu — pin and delete had no keyboard path.
            activeFocusOnTab: true
            Accessible.role: Accessible.List
            Keys.onUpPressed: { root.step(-1); Qt.callLater(root._activeRowItem); }
            Keys.onDownPressed: { root.step(1); Qt.callLater(root._activeRowItem); }
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                    const r = root._activeRowItem();
                    if (r) r.openMenu();
                    event.accepted = true;
                }
            }

            delegate: Loader {
                required property var modelData
                width: list.width
                sourceComponent: modelData.kind === "header" ? headerRow : noteRow
                onLoaded: item.rowData = modelData
            }

            Component {
                id: headerRow
                Item {
                    id: headerItem
                    property var rowData: ({})
                    height: 22
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.bottomMargin: Theme.sp2xs
                        text: (rowData.label || "").toUpperCase()
                        color: Theme.textDim
                        font.pixelSize: Theme.fsXs
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                        elide: Text.ElideRight
                    }
                    // A folder header is the folder: right-click renames it or
                    // removes it (its notes move up a level, none are lost).
                    MouseArea {
                        anchors.fill: parent
                        enabled: (headerItem.rowData.folder || "").length > 0
                        acceptedButtons: Qt.RightButton
                        onClicked: folderMenu.popup()
                    }
                    AppMenu {
                        id: folderMenu
                        AppMenuItem {
                            text: I18n.t("notes.folder.rename")
                            onTriggered: folderPopup.openFor(headerItem.rowData.folder)
                        }
                        AppMenuSeparator {}
                        AppMenuItem {
                            text: I18n.t("notes.folder.remove")
                            danger: true
                            onTriggered: AppController.removeNoteFolder(headerItem.rowData.folder)
                        }
                    }
                }
            }

            Component {
                id: noteRow
                Rectangle {
                    id: row
                    property var rowData: ({})
                    readonly property var note: rowData.note || ({})
                    objectName: "note-row-" + (row.note.id || "")
                    height: 40
                    radius: Theme.radiusMd
                    readonly property bool current: row.note.id === AppController.activeNoteId
                    color: row.current ? Theme.withAlpha(Theme.accent, 0.14)
                         : rowMA.containsMouse ? Theme.panel2 : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: row.note.title || ""
                    readonly property alias menu: rowMenu
                    // The row sits in a Loader, the ListView's delegate.
                    readonly property bool listFocused: !!row.parent && !!row.parent.ListView.view
                                                        && row.parent.ListView.view.activeFocus
                    function openMenu() { rowMenu.popup(row, Theme.spXl, row.height / 2); }
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.color: Theme.focusRing
                        border.width: 2
                        visible: row.current && row.listFocused
                        z: 10
                    }

                    Rectangle {
                        visible: row.current
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.margins: Theme.spSm
                        width: 2; radius: 1
                        color: Theme.accent
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spXl; anchors.rightMargin: Theme.spMd
                        anchors.topMargin: Theme.spXs; anchors.bottomMargin: Theme.spXs
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spXs
                            Text {
                                text: row.note.title || ""
                                color: Theme.text
                                font.pixelSize: Theme.fsSm
                                font.weight: row.current ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            // A pin is only worth drawing where it is not
                            // already implied by the section it is under.
                            Text {
                                visible: row.note.pinned && row.rowData.inPinnedSection !== true
                                text: "•"
                                color: Theme.accent
                                font.pixelSize: Theme.fsMd
                            }
                        }
                        Text {
                            text: row.note.excerpt || ""
                            // textMuted on the selected row: textDim on the 14%
                            // accent tint fell to 3.3:1 (design audit DES-21).
                            color: row.current ? Theme.textMuted : Theme.textDim
                            font.pixelSize: Theme.fsXs
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            visible: (row.note.excerpt || "").length > 0
                        }
                    }

                    MouseArea {
                        id: rowMA
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        // APP-116: drag a note onto another to merge it in.
                        // The ghost moves, not the row, so the list stays put.
                        drag.target: dragGhost
                        drag.threshold: Theme.spMd
                        onPressed: (mouse) => {
                            if (mouse.button !== Qt.LeftButton) return;
                            const p = row.mapToItem(root, 0, 0);
                            dragGhost.x = p.x; dragGhost.y = p.y;
                            dragGhost.width = row.width;
                            dragGhost.noteId = row.note.id;
                            dragGhost.title = row.note.title || "";
                        }
                        onReleased: {
                            if (dragGhost.dragging) dragGhost.Drag.drop();
                            dragGhost.dragging = false;
                            dragGhost.noteId = "";
                            dragGhost.overTitle = "";
                        }
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) rowMenu.popup();
                            else root.noteActivated(row.note.id);
                        }
                    }
                    Connections {
                        target: rowMA.drag
                        function onActiveChanged() {
                            if (rowMA.drag.active) dragGhost.dragging = true;
                        }
                    }
                    DropArea {
                        id: rowDrop
                        objectName: "note-drop-" + (row.note.id || "")
                        anchors.fill: parent
                        keys: ["heap-note"]
                        onEntered: (drag) => {
                            drag.accepted = drag.source === dragGhost && dragGhost.noteId !== row.note.id;
                            if (drag.accepted) dragGhost.overTitle = row.note.title || "";
                        }
                        onExited: if (dragGhost.overTitle === (row.note.title || "")) dragGhost.overTitle = ""
                        onDropped: (drop) => {
                            if (drop.source !== dragGhost || dragGhost.noteId === row.note.id) return;
                            drop.accept();
                            AppController.mergeNotes(dragGhost.noteId, row.note.id);
                        }
                    }
                    // Where a drop would land: outlined, and the ghost says so.
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Theme.accentSoft
                        border.color: Theme.accent
                        border.width: 1
                        visible: rowDrop.containsDrag && dragGhost.noteId !== row.note.id
                        z: 9
                    }

                    AppMenu {
                        id: rowMenu
                        AppMenuItem {
                            text: row.note.pinned ? I18n.t("notes.unpin") : I18n.t("notes.pin")
                            onTriggered: AppController.setNotePinned(row.note.id, !row.note.pinned)
                        }
                        AppMenuItem {
                            text: I18n.t("notes.rename")
                            onTriggered: renamePopup.openFor(row.note.id, row.note.title, row.note.folder)
                        }
                        // The keyboard's way to merge: this note into the one open.
                        AppMenuItem {
                            objectName: "note-merge-into-open"
                            visible: !row.current && AppController.activeNoteId.length > 0
                            height: visible ? implicitHeight : 0
                            text: I18n.t("notes.mergeIntoOpen")
                            onTriggered: AppController.mergeNotes(row.note.id, AppController.activeNoteId)
                        }
                        AppMenuSeparator {}
                        AppMenuItem {
                            text: I18n.t("common.delete")
                            danger: true
                            onTriggered: AppController.deleteNote(row.note.id)
                        }
                    }
                }
            }
        }
    }

    // What a note drag carries: the note's id, drawn as a chip under the
    // pointer. Dropped on another row, that row merges it in (APP-116).
    Rectangle {
        id: dragGhost
        objectName: "note-drag-ghost"
        property string noteId: ""
        property string title: ""
        // Set by the row being dragged while its drag is live.
        property bool dragging: false
        // The note under the pointer that would take this one in.
        property string overTitle: ""
        visible: dragging
        height: 32
        z: 100
        radius: Theme.radiusMd
        color: Theme.panel3
        border.color: Theme.borderStrong
        opacity: 0.95
        Drag.active: dragging
        Drag.keys: ["heap-note"]
        Drag.source: dragGhost
        Drag.hotSpot.x: Theme.spXl
        Drag.hotSpot.y: height / 2
        Text {
            anchors.fill: parent
            anchors.leftMargin: Theme.spXl; anchors.rightMargin: Theme.spMd
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: dragGhost.overTitle.length > 0 ? I18n.t("notes.dropToMerge").arg(dragGhost.overTitle) : dragGhost.title
            color: Theme.text
            font.pixelSize: Theme.fsSm
            font.weight: Font.DemiBold
        }
    }

    QQC.Dialog {
        id: folderPopup
        objectName: "note-folder-rename"
        property string folder: ""
        modal: true
        anchors.centerIn: QQC.Overlay.overlay
        parent: QQC.Overlay.overlay
        padding: Theme.inset
        width: 380
        title: I18n.t("notes.folder.rename")

        function openFor(folder) {
            folderPopup.folder = folder;
            folderName.text = folder;
            folderPopup.open();
            folderName.forceActiveFocus();
            folderName.selectAll();
        }
        function commit() {
            AppController.renameNoteFolder(folderPopup.folder, folderName.text);
            folderPopup.close();
        }

        background: Rectangle {
            radius: Theme.radiusXl
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }
        contentItem: QQC.TextField {
            id: folderName
            objectName: "note-folder-name"
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsSm
            background: FieldFrame {}
            onAccepted: folderPopup.commit()
        }
        footer: RowLayout {
            spacing: Theme.spMd
            Layout.margins: Theme.sp2xl
            Item { Layout.fillWidth: true }
            PillButton { text: I18n.t("common.cancel"); onClicked: folderPopup.close() }
            PillButton { text: I18n.t("editor.btn.save"); primary: true; onClicked: folderPopup.commit() }
        }
    }

    // Rename and re-file in one place: they are the same edit as far as the
    // reader is concerned — what this note is called and where it lives.
    QQC.Dialog {
        id: renamePopup
        objectName: "note-rename"
        property string noteId: ""
        modal: true
        anchors.centerIn: QQC.Overlay.overlay
        parent: QQC.Overlay.overlay
        padding: Theme.inset
        width: 380
        title: I18n.t("notes.rename")

        function openFor(id, title, folder) {
            renamePopup.noteId = id;
            titleField.text = title;
            folderField.text = folder;
            renamePopup.open();
            titleField.forceActiveFocus();
            titleField.selectAll();
        }

        function commit() {
            AppController.renameNote(renamePopup.noteId, titleField.text);
            AppController.moveNoteToFolder(renamePopup.noteId, folderField.text);
            renamePopup.close();
        }

        background: Rectangle {
            radius: Theme.radiusXl
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: Theme.spMd
            QQC.TextField {
                id: titleField
                QQC.ContextMenu.menu: TextEditMenu { editor: titleField }
                objectName: "note-rename-title"
                Layout.fillWidth: true
                Layout.preferredWidth: 320
                color: Theme.text
                background: FieldFrame {}
                onAccepted: renamePopup.commit()
            }
            QQC.TextField {
                id: folderField
                QQC.ContextMenu.menu: TextEditMenu { editor: folderField }
                objectName: "note-rename-folder"
                Layout.fillWidth: true
                Layout.preferredWidth: 320
                placeholderText: I18n.t("notes.folderPlaceholder")
                placeholderTextColor: Theme.textDim
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsSm
                background: FieldFrame {}
                onAccepted: renamePopup.commit()
            }
        }

        footer: RowLayout {
            spacing: Theme.spMd
            Layout.margins: Theme.sp2xl
            Item { Layout.fillWidth: true }
            PillButton { text: I18n.t("common.cancel"); onClicked: renamePopup.close() }
            PillButton { text: I18n.t("editor.btn.save"); primary: true; onClicked: renamePopup.commit() }
        }
    }
}
