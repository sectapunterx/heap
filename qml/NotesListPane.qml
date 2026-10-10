pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import QtQuick.Dialogs
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
    // The doc page open in the document, so its row reads as the open one.
    property string openPageId: ""

    // Bumped by the model so the grouping rebuilds.
    property int rev: 0

    signal noteActivated(string id)
    // A note's "Экспорт в .md" (R2-062): where to, then one file.
    function exportNote(id, title) {
        noteExportDialog.noteId = id;
        noteExportDialog.currentFile = "file:///" + (title.replace(/[\\/:*?"<>|]/g, " ").trim() || "note") + ".md";
        noteExportDialog.open();
    }
    FileDialog {
        id: noteExportDialog
        property string noteId: ""
        fileMode: FileDialog.SaveFile
        nameFilters: ["Markdown (*.md)", "All files (*)"]
        defaultSuffix: "md"
        title: I18n.t("notes.menu.export")
        onAccepted: AppController.showToast(AppController.exportNoteToFile(noteExportDialog.noteId, selectedFile)
                                         ? I18n.t("notes.export.done") : I18n.t("notes.export.fail"))
    }
    // After "+": the view puts the cursor in the new note.
    signal noteCreated(string id)
    // Knowledge (APP-269): Docs live in the same list — the reference links
    // pinned at the top, the doc pages and the snippets below the notes.
    signal refActivated(string url)
    signal pageActivated(string id)
    signal snippetActivated(string title, string code)
    signal contactActivated(string handle)

    // The Docs catalogue, read as it is stored: nothing is moved or copied,
    // so nothing of it can be lost on the way to Knowledge.
    function _docs() {
        const raw = AppController.docsState || "";
        if (!raw.length) return ({ sections: [], snippets: [], contacts: [] });
        try { return JSON.parse(raw) || ({}); } catch (e) { return ({}); }
    }
    // "RFC 9110" → tag "RFC", number "9110"; a ref without a number is its tag.
    function _splitRef(ref) {
        const m = /^(\S+)\s+(.+)$/.exec(String(ref || "").trim());
        return m ? { tag: m[1], rest: m[2] } : { tag: String(ref || ""), rest: "" };
    }

    // Pin or unpin a reference of the catalogue (DG-073): only pinned ones
    // stand in Закреплено at rest; the rest come up in the search and Ctrl+K.
    // The blob is rewritten as read, with only this one flag changed.
    function setRefPinned(sectionIdx, itemIdx, pinned) {
        const raw = AppController.docsState || "";
        if (!raw.length) return;
        let d;
        try { d = JSON.parse(raw); } catch (e) { return; }
        const sec = (d.sections || [])[sectionIdx];
        const it = sec && (sec.items || [])[itemIdx];
        if (!it) return;
        if (pinned) it.pinned = true;
        else delete it.pinned;
        AppController.docsState = JSON.stringify(d);
    }

    color: Theme.bg
    implicitWidth: 260

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
        const rPinned = m.roleOf("pinned"), rExcerpt = m.roleOf("excerpt"), rCreated = m.roleOf("created");
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            const id = String(m.data(idx, rId));
            if (hits && !allowed[id]) continue;
            const note = {
                id:      id,
                title:   String(m.data(idx, rTitle) || ""),
                folder:  String(m.data(idx, rFolder) || ""),
                pinned:  !!m.data(idx, rPinned),
                excerpt: String(m.data(idx, rExcerpt) || ""),
                created: new Date(m.data(idx, rCreated) || 0).getTime() || 0
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
        // Notes newest first (sheet H2-Knowledge, DG-073): by when they were
        // made, so a note being typed in does not jump to the top.
        const newest = function (a, b) { return b.created - a.created || byTitle(a, b); };
        pinned.sort(byTitle);
        loose.sort(newest);

        // Docs: the reference links, the pages, the snippets (APP-269).
        const q = needle.toLowerCase();
        const has = (s) => q.length === 0 || String(s || "").toLowerCase().indexOf(q) >= 0;
        const docs = root._docs();
        // Pinned references stand in Закреплено (DG-073); the others are
        // listed only while searching, under their own header.
        const refs = [], otherRefs = [];
        const secs = docs.sections || [];
        for (let si = 0; si < secs.length; si++) {
            const items = (secs[si] && secs[si].items) || [];
            for (let ii = 0; ii < items.length; ii++) {
                const it = items[ii];
                if (!it || !(it.url || "").length) continue;
                const pinnedRef = it.pinned === true;
                if (!pinnedRef && q.length === 0) continue;
                if (!has(it.title) && !has(it.ref) && !has(it.desc) && !has(it.url)) continue;
                const r = root._splitRef(it.ref);
                const title = String(it.title || it.ref || it.url);
                (pinnedRef ? refs : otherRefs).push({
                    kind: "ref", tag: r.tag, rest: r.rest, name: title,
                    title: title + (r.rest.length ? " · " + r.rest : ""),
                    url: String(it.url), sec: si, item: ii, pinned: pinnedRef
                });
            }
        }
        const contacts = [];
        if (q.length > 0) {
            const cs = docs.contacts || [];
            for (let ci = 0; ci < cs.length; ci++) {
                const c = cs[ci];
                if (!c || (!has(c.name) && !has(c.role) && !has(c.channel) && !has(c.mattermost))) continue;
                const handle = String(c.mattermost || c.channel || c.name || "");
                contacts.push({ kind: "contact", tag: "", title: String(c.name || "") + (c.role ? " · " + c.role : ""), handle: handle });
            }
        }
        const noteTitles = ({});
        for (const n of pinned.concat(loose)) noteTitles[n.title.toLowerCase()] = true;
        for (const f in byFolder) for (const n of byFolder[f]) noteTitles[n.title.toLowerCase()] = true;
        const pages = [];
        const dp = AppController.docPages;
        if (dp) {
            const rpId = dp.roleOf("id"), rpTitle = dp.roleOf("title");
            for (let i = 0; i < dp.rowCount(); i++) {
                const idx = dp.index(i, 0);
                const t = String(dp.data(idx, rpTitle) || "");
                if (!has(t)) continue;
                // A page named like a note says where it is from.
                const shown = noteTitles[t.toLowerCase()] ? t + " " + I18n.t("knowledge.fromDocs") : t;
                pages.push({ kind: "page", id: String(dp.data(idx, rpId)), title: shown, name: t });
            }
        }
        const snippets = [];
        for (const sn of docs.snippets || []) {
            if (!sn || (!has(sn.title) && !has(sn.code))) continue;
            snippets.push({ kind: "snippet", tag: String(sn.lang || "txt"), title: String(sn.title || ""), code: String(sn.code || "") });
        }

        const rows = [];
        if (pinned.length > 0 || refs.length > 0) {
            rows.push({ kind: "header", label: I18n.t("notes.pinned") });
            for (const r of refs) rows.push(r);
            for (const n of pinned) rows.push({ kind: "note", note: n, inPinnedSection: true });
        }
        const folders = Object.keys(byFolder).sort();
        for (const f of folders) {
            rows.push({ kind: "header", label: f, folder: f });
            byFolder[f].sort(newest);
            for (const n of byFolder[f]) rows.push({ kind: "note", note: n });
        }
        if (loose.length > 0) {
            rows.push({ kind: "header", label: I18n.t("notes.other") });
            for (const n of loose) rows.push({ kind: "note", note: n });
        }
        if (pages.length > 0) {
            rows.push({ kind: "header", label: I18n.t("knowledge.pages") });
            for (const p of pages) rows.push(p);
        }
        if (snippets.length > 0) {
            rows.push({ kind: "header", label: I18n.t("knowledge.snippets") });
            for (const sn of snippets) rows.push(sn);
        }
        if (otherRefs.length > 0) {
            rows.push({ kind: "header", label: I18n.t("knowledge.refs") });
            for (const r of otherRefs) rows.push(r);
        }
        if (contacts.length > 0) {
            rows.push({ kind: "header", label: I18n.t("knowledge.contacts") });
            for (const c of contacts) rows.push(c);
        }
        // The first header sits closer to the search than the others to
        // the group above them.
        if (rows.length > 0 && rows[0].kind === "header") rows[0].first = true;
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
        target: AppController
        function onDocsStateChanged() { root.scheduleRebuild() }
    }
    Connections {
        target: AppController.docPages
        function onRowsInserted() { root.scheduleRebuild() }
        function onRowsRemoved()  { root.scheduleRebuild() }
        function onDataChanged()  { root.scheduleRebuild() }
        function onModelReset()   { root.scheduleRebuild() }
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
            Layout.topMargin: Style.quiet ? Theme.px(18) : Theme.spXs
            Text {
                text: I18n.t("sidebar.knowledge")
                color: Theme.text
                font.pixelSize: Style.quiet ? Theme.fsXl : Theme.fsLg
                font.weight: Theme.fwHeading
                Layout.fillWidth: true
            }
            // Bold: a framed "+"; quiet: the mark alone (sheets H2/Q-Knowledge).
            Rectangle {
                objectName: "note-new"
                width: Theme.px(26); height: Theme.px(26); radius: Theme.radiusSm
                color: newMA.hovered ? Theme.panel3 : (Style.quiet ? "transparent" : Theme.panel2)
                border.color: Style.quiet ? "transparent" : Theme.border
                border.width: 1
                PlusGlyph {
                    anchors.centerIn: parent
                    size: Theme.px(9)
                    color: Style.quiet ? Theme.textMuted : Theme.text
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
            placeholderText: Style.quiet ? I18n.t("notes.filter.short") : I18n.t("notes.filter")
            placeholderTextColor: Theme.textDim
            color: Theme.text
            font.pixelSize: Theme.fsSm
            leftPadding: Style.quiet ? 0 : Theme.spMd
            // Quiet: a line under the words, no box.
            background: Item {
                implicitHeight: Theme.px(30)
                FieldFrame { anchors.fill: parent; visible: !Style.quiet }
                Rectangle {
                    visible: Style.quiet
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 1
                    color: filterField.activeFocus ? Theme.accent : Theme.border
                }
            }
            onTextChanged: root.filter = text
        }

        EmptyState {
            objectName: "notes-empty"
            // No notes, even with pinned links and snippets listed (R3-134).
            visible: root.filter.length > 0 ? root.rows.length === 0 : !root.rows.some(r => r.kind === "note")
            Layout.fillWidth: true
            Layout.topMargin: Theme.sp2xl
            Layout.bottomMargin: root.rows.length > 0 ? Theme.sp2xl : 0
            title: root.filter.length > 0 ? I18n.t("notes.noMatches") : I18n.t("notes.empty")
            line: root.filter.length > 0 ? I18n.t("notes.noMatches.hint") : I18n.t("notes.empty.line").arg(AppController.shortcutText("notes.new"))
        }

        ListView {
            id: list
            objectName: "note-list"
            Accessible.name: I18n.t("siderail.notes")
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
                sourceComponent: modelData.kind === "header" ? headerRow
                               : modelData.kind === "note" ? noteRow : docRow
                onLoaded: item.rowData = modelData
            }

            Component {
                id: headerRow
                Item {
                    id: headerItem
                    property var rowData: ({})
                    height: headerItem.rowData.first ? Theme.px(30) : Theme.px(40)
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Theme.spMd
                        anchors.bottomMargin: Theme.spSm
                        text: headerItem.rowData.label || ""
                        color: Theme.textDim
                        font.pixelSize: Theme.fsXs
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

            // A reference link, a doc page or a snippet: a small tag and a title.
            Component {
                id: docRow
                Rectangle {
                    id: drow
                    property var rowData: ({})
                    objectName: "knowledge-" + (drow.rowData.kind || "") + "-row"
                    height: Theme.px(30)
                    radius: Theme.radiusMd
                    color: drowCA.hovered ? Theme.panel2 : "transparent"
                    readonly property bool current: drow.rowData.kind === "page" && drow.rowData.id === root.openPageId
                    // Quiet draws no tag chip: a reference reads "RFC 9110 · title".
                    readonly property string shownTitle: {
                        const r = drow.rowData;
                        if (Style.quiet && r.kind === "ref")
                            return (r.rest || "").length > 0 ? r.tag + " " + r.rest + " · " + r.name : r.name;
                        return r.title || "";
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                        spacing: Theme.spMd
                        Rectangle {
                            visible: !Style.quiet && (drow.rowData.tag || "").length > 0
                            implicitWidth: tagTxt.implicitWidth + 2 * Theme.spXs
                            implicitHeight: tagTxt.implicitHeight + Theme.sp2xs
                            radius: Theme.radiusSm
                            color: "transparent"
                            border.color: Theme.border
                            border.width: 1
                            Text {
                                id: tagTxt
                                anchors.centerIn: parent
                                text: String(drow.rowData.tag || "").substring(0, 4)
                                color: Theme.textDim
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsXs
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: drow.shownTitle
                            color: Theme.text
                            font.pixelSize: Theme.fsSm
                            font.weight: drow.current ? Theme.fwHeading : Theme.fwBody
                            elide: Text.ElideRight
                            CursorBar {
                                shown: drow.current
                                anchors.left: parent.left
                                anchors.top: parent.bottom
                            }
                        }
                    }
                    ClickArea {
                        id: drowCA
                        label: drow.rowData.title || ""
                        role: Accessible.Link
                        onActivated: {
                            const r = drow.rowData;
                            if (r.kind === "ref") root.refActivated(r.url);
                            else if (r.kind === "page") root.pageActivated(r.id);
                            else if (r.kind === "snippet") root.snippetActivated(r.title, r.code);
                            else if (r.kind === "contact") root.contactActivated(r.handle);
                        }
                    }
                    // Right-click: pin a reference, rename or delete a page.
                    MouseArea {
                        anchors.fill: parent
                        enabled: drow.rowData.kind === "ref" || drow.rowData.kind === "page"
                        acceptedButtons: Qt.RightButton
                        onClicked: docMenu.popup()
                    }
                    AppMenu {
                        id: docMenu
                        AppMenuItem {
                            objectName: "knowledge-ref-pin"
                            visible: drow.rowData.kind === "ref"
                            height: visible ? implicitHeight : 0
                            text: drow.rowData.pinned ? I18n.t("notes.unpin") : I18n.t("notes.pin")
                            onTriggered: root.setRefPinned(drow.rowData.sec, drow.rowData.item, !drow.rowData.pinned)
                        }
                        AppMenuItem {
                            visible: drow.rowData.kind === "page"
                            height: visible ? implicitHeight : 0
                            text: I18n.t("notes.rename")
                            onTriggered: pageRenamePopup.openFor(drow.rowData.id, drow.rowData.name || "")
                        }
                        AppMenuItem {
                            visible: drow.rowData.kind === "page"
                            height: visible ? implicitHeight : 0
                            text: I18n.t("common.delete")
                            danger: true
                            onTriggered: AppController.deleteDocPage(drow.rowData.id)
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
                    height: Theme.px(30)
                    radius: Theme.radiusMd
                    // A doc page open in the document is the current row instead.
                    readonly property bool current: row.note.id === AppController.activeNoteId && root.openPageId.length === 0
                    color: rowMA.containsMouse ? Theme.panel2 : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: row.note.title || ""
                    readonly property alias menu: rowMenu
                    // The row sits in a Loader, the ListView's delegate.
                    readonly property bool listFocused: !!row.parent && !!row.parent.ListView.view
                                                        && row.parent.ListView.view.activeFocus
                    function openMenu() { rowMenu.popup(row, Theme.spXl, row.height / 2); }
                    FocusRing {
                        anchors.margins: 0
                        radius: row.radius
                        visible: row.current && row.listFocused
                        z: 10
                    }


                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                        anchors.topMargin: Theme.spXs; anchors.bottomMargin: Theme.spXs
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spXs
                            Text {
                                id: noteTitleTxt
                                text: row.note.title || ""
                                color: Theme.text
                                font.pixelSize: Theme.fsSm
                                font.weight: row.current ? Theme.fwHeading : Theme.fwBody
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                CursorBar {
                                    shown: row.current
                                    anchors.left: parent.left
                                    anchors.top: parent.bottom
                                }
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
                            // One line per note in Knowledge (sheet H2-Knowledge).
                            visible: false
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

                    // The note's menu (R2-062, sheet X/N-Menus-Other). Merging
                    // stays on drag and drop: a row dropped on another.
                    AppMenu {
                        id: rowMenu
                        objectName: "note-row-menu"
                        AppMenuHeader {
                            text: I18n.t("notes.menu.header").arg(row.note.title || "")
                        }
                        AppMenuItem {
                            objectName: "note-menu-open"
                            text: I18n.t("notes.menu.open")
                            keyText: "↵"
                            onTriggered: root.noteActivated(row.note.id)
                        }
                        AppMenuItem {
                            objectName: "note-menu-pin"
                            text: row.note.pinned ? I18n.t("notes.unpin") : I18n.t("notes.pin")
                            onTriggered: AppController.setNotePinned(row.note.id, !row.note.pinned)
                        }
                        AppMenuItem {
                            objectName: "note-menu-rename"
                            text: I18n.t("notes.menu.rename")
                            shortcutId: "notes.rename"
                            onTriggered: renamePopup.openFor(row.note.id, row.note.title, row.note.folder)
                        }
                        AppMenuItem {
                            objectName: "note-menu-copy-link"
                            text: I18n.t("notes.menu.copyLink")
                            onTriggered: AppController.copyToClipboard("[[" + (row.note.title || "") + "]]")
                        }
                        AppMenuItem {
                            objectName: "note-menu-export"
                            text: I18n.t("notes.menu.export")
                            onTriggered: root.exportNote(row.note.id, row.note.title || "")
                        }
                        AppMenuSeparator {}
                        AppMenuItem {
                            objectName: "note-menu-delete"
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
            font.weight: Theme.fwTitle
        }
    }

    QQC.Dialog {
        id: folderPopup
        objectName: "note-folder-rename"
        property string folder: ""
        modal: true
        QQC.Overlay.modal: ModalScrim {}
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

        background: ModalSurface {}
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

    // A page keeps its name and body; renaming is all the list offers.
    QQC.Dialog {
        id: pageRenamePopup
        objectName: "knowledge-page-rename"
        property string pageId: ""
        modal: true
        QQC.Overlay.modal: ModalScrim {}
        anchors.centerIn: QQC.Overlay.overlay
        parent: QQC.Overlay.overlay
        padding: Theme.inset
        width: 380
        title: I18n.t("notes.rename")
        function openFor(id, title) {
            pageRenamePopup.pageId = id;
            pageName.text = title;
            pageRenamePopup.open();
            pageName.forceActiveFocus();
            pageName.selectAll();
        }
        function commit() {
            if (pageName.text.trim().length > 0) AppController.renameDocPage(pageRenamePopup.pageId, pageName.text.trim());
            pageRenamePopup.close();
        }
        background: ModalSurface {}
        contentItem: QQC.TextField {
            id: pageName
            color: Theme.text
            background: FieldFrame {}
            onAccepted: pageRenamePopup.commit()
        }
        footer: RowLayout {
            spacing: Theme.spMd
            Layout.margins: Theme.sp2xl
            Item { Layout.fillWidth: true }
            PillButton { text: I18n.t("common.cancel"); onClicked: pageRenamePopup.close() }
            PillButton { text: I18n.t("editor.btn.save"); primary: true; onClicked: pageRenamePopup.commit() }
        }
    }

    // Rename and re-file in one place: they are the same edit as far as the
    // reader is concerned — what this note is called and where it lives.
    QQC.Dialog {
        id: renamePopup
        objectName: "note-rename"
        property string noteId: ""
        modal: true
        QQC.Overlay.modal: ModalScrim {}
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

        background: ModalSurface {}

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
