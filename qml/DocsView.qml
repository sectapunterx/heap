// Docs view — spec / wiki / refs / snippets / contacts (editable)
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp
import "DocsStarter.js" as Starter

Item {
    id: root

    property string searchText: ""

    // A [[note]], #TICKET or @person clicked in a doc page. Opening a task or
    // a note is Main's business, not the docs view's.
    signal linkRequested(string kind, string target)

    // ── Data ─────────────────────────────────────────────────────────────────

    // Filled with the starter content (qml/DocsStarter.js) on creation, in the
    // UI language of that moment, then from the profile's saved docs. Plain
    // values rather than bindings, so a theme or language change later never
    // resets what the user has.
    property var sections: []
    property var snippets: []
    property var contacts: []

    // Pristine copies of the starter content above, so a blob that carries only
    // contacts (the first Mattermost sync on a fresh profile) can be told apart
    // from one where the user really did clear their docs.
    property var _sampleSections: []
    property var _sampleSnippets: []

    readonly property var contactPalette: Theme.swatches

    readonly property var accentPalette: [
        Theme.mStandup, Theme.mOneone, Theme.mSync, Theme.mFocus,
        Theme.accent, Theme.p0, Theme.p1, Theme.p2, Theme.p3, Theme.textMuted
    ]

    // ── Helpers ─────────────────────────────────────────────────────────────

    function totalDocs() {
        let n = 0;
        for (let i = 0; i < sections.length; i++) n += sections[i].items.length;
        return n;
    }
    function _matches(haystack) {
        const q = (root.searchText || "").toLowerCase().trim();
        if (q.length === 0) return true;
        return haystack.toLowerCase().indexOf(q) >= 0;
    }
    function passesSearch(item) {
        return _matches((item.ref || "") + " " + (item.title || "") + " " + (item.desc || "") + " " + (item.source || ""));
    }
    // Snippets and contacts used to be exempt from the search box: typing a
    // query filtered the reference sections and left both other panels showing
    // everything, so a hit in a snippet was unfindable.
    function snippetPassesSearch(s) {
        return _matches((s.title || "") + " " + (s.lang || "") + " " + (s.code || "") + " " + ((s.tags || []).join(" ")));
    }
    function contactPassesSearch(c) {
        return _matches((c.name || "") + " " + (c.role || "") + " " + (c.handle || "") + " " + (c.team || "") + " " + (c.note || ""));
    }

    readonly property int matchingSnippetCount: {
        let n = 0;
        for (let i = 0; i < snippets.length; i++) if (snippetPassesSearch(snippets[i])) n++;
        return n;
    }
    readonly property int matchingDocCount: {
        let n = 0;
        for (let i = 0; i < sections.length; i++)
            for (let j = 0; j < sections[i].items.length; j++) if (passesSearch(sections[i].items[j])) n++;
        return n;
    }
    // A query that matches nothing anywhere (design audit DES-13): every
    // section hid itself and the page went blank, which read as broken.
    readonly property bool searchFoundNothing: (root.searchText || "").trim().length > 0
        && root.matchingDocCount + root.matchingSnippetCount + root.matchingContactCount === 0
    readonly property int matchingContactCount: {
        let n = 0;
        for (let i = 0; i < contacts.length; i++) if (contactPassesSearch(contacts[i])) n++;
        return n;
    }

    // Focused by the global search shortcut when Docs is the active view.
    function focusSearch() {
        if (root.tab === "pages") {
            pagesPane.focusFilter();
            return;
        }
        docsSearch.forceActiveFocus();
        docsSearch.selectAll();
    }
    function initials(name) {
        const parts = (name || "").split(/\s+/);
        return (parts[0] ? parts[0][0] : "") + (parts[1] ? parts[1][0] : "");
    }
    function showToast(s) { if (toast) toast.show(s) }
    function showUndoToast(s, fn) {
        if (toast) toast.showWithAction(s, I18n.t("undo.action"), 5, fn);
    }

    // ── Persistence — JSON round-tripped through AppController.docsState ───

    property bool _loadedOnce: false
    property bool _persisting: false   // we wrote AppController.docsState ourselves
    property bool _reloading:  false   // external change (e.g. profile switch) — suppress persist()

    // Every catalogue entry gets an id of its own. Edit, delete, move and undo
    // used to find an entry by its Ref, which the user types and may leave
    // empty or repeat: two entries without a Ref were one entry to every
    // operation, so editing one overwrote the other and deleting one deleted
    // both. Entries saved before ids existed get one here, on load, and the
    // blob is written back so the ids stick. Returns true when it assigned any.
    function _newEntryId() {
        return "e-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36);
    }
    function _ensureIds(list) {
        const seen = ({});
        let changed = false;
        for (let i = 0; i < list.length; i++) {
            const items = list[i].items || [];
            for (let j = 0; j < items.length; j++) {
                const it = items[j];
                if (!it.id || seen[it.id]) {
                    it.id = root._newEntryId();
                    changed = true;
                }
                seen[it.id] = true;
            }
        }
        return changed;
    }

    property bool _migratedOnLoad: false
    function _loadFromController() {
        _reloading = true;
        const raw = AppController.docsState || "";
        let migrated = false;
        if (raw.length === 0) {
            sections = [];
            snippets = [];
            contacts = [];
        } else {
            try {
                const o = JSON.parse(raw);
                // A missing key is not an empty list. A contact sync writes
                // {contacts:[…]} into a blob that has never been saved, and
                // reading that back as sections=[] used to wipe the starter
                // docs. An explicitly empty array is still respected.
                const secs = o.sections !== undefined ? o.sections : JSON.parse(JSON.stringify(root._sampleSections));
                migrated = root._ensureIds(secs);
                sections = secs;
                snippets = o.snippets !== undefined ? o.snippets : root._sampleSnippets;
                contacts = o.contacts || [];
            } catch (e) { /* corrupt — keep current view */ }
        }
        _reloading = false;
        // Later, not now: on creation this runs before _loadedOnce is set.
        if (migrated) { if (_loadedOnce) persist(); else _migratedOnLoad = true; }
    }

    Component.onCompleted: {
        const starter = Starter.sections(I18n.lang, [Theme.mStandup, Theme.mOneone, Theme.mSync, Theme.mFocus]);
        root._ensureIds(starter);
        sections = starter;
        snippets = Starter.snippets(I18n.lang);
        contacts = Starter.contacts(I18n.lang);
        // Snapshot the starter content before anything can overwrite it — a
        // later profile switch reloads into `sections`, so reading it back then
        // would give that profile's docs instead of the samples.
        _sampleSections = sections;
        _sampleSnippets = snippets;
        const initiallyEmpty = ((AppController.docsState || "").length === 0);
        // On first run with an empty profile, keep the hardcoded sample
        // sections/snippets/contacts already declared as property defaults
        // and persist them so subsequent profile switches round-trip cleanly.
        if (!initiallyEmpty) _loadFromController();
        _loadedOnce = true;
        if (_migratedOnLoad) persist();
        if (initiallyEmpty && (sections.length > 0 || snippets.length > 0 || contacts.length > 0))
            persist();
    }
    // Debounced, the way NotesView already does it. persist() stringifies the
    // entire docs blob — every section, snippet and contact — and each write
    // schedules a whole-state save; there are 21 assignment sites to the three
    // properties below, so an edit that touches several in a row used to
    // serialise the lot once per assignment.
    Timer {
        id: persistTimer
        interval: 250
        repeat: false
        onTriggered: root.persistNow()
    }
    function persist() {
        if (!_loadedOnce || _reloading) return;
        persistTimer.restart();
    }
    function persistNow() {
        if (!_loadedOnce || _reloading) return;
        _persisting = true;
        AppController.docsState = JSON.stringify({ sections: sections, snippets: snippets, contacts: contacts });
        _persisting = false;
    }
    onSectionsChanged: persist()
    onSnippetsChanged: persist()
    onContactsChanged: persist()
    // A pending edit must not be lost to a view switch or a profile switch.
    function flushPending() {
        if (!persistTimer.running) return;
        persistTimer.stop();
        persistNow();
    }
    Component.onDestruction: flushPending()
    // Quit is not covered by onDestruction: the engine tears down its root
    // objects and the AppController singleton in an unspecified order, and
    // ~AppController's own flushSave() may already have run by then. Flush
    // here, while both are alive, and push the debounced state.json write.
    Connections {
        target: Qt.application
        function onAboutToQuit() {
            root.flushPending();
            AppController.flushSave();
        }
    }

    // External docsState change → reload (e.g. profile switch).
    Connections {
        target: AppController
        function onDocsStateChanged() {
            if (!root._loadedOnce || root._persisting) return;
            root._loadFromController();
        }
        // An export or a search is about to read the whole profile.
        function onFlushEditorsRequested() { root.flushPending() }
    }

    // ── Undo ────────────────────────────────────────────────────────────────
    // Deletions go on AppController's undo stack, the one Ctrl+Z and every
    // other Undo toast use. This view used to keep one pending deletion of its
    // own: deleting a snippet and then a contact lost the snippet for good,
    // and Ctrl+Z never reached either.
    //
    // The debounce is flushed first, so the recorded "before" is what was on
    // screen and the undo takes back the deletion and nothing else.
    function _beginUndoable() { flushPending(); }
    function _commitUndoable(label) {
        persistTimer.stop();
        _persisting = true;
        AppController.setDocsStateUndoable(JSON.stringify({ sections: sections, snippets: snippets, contacts: contacts }), label);
        _persisting = false;
    }

    // Kept for callers and tests that still ask the view: the stack is shared.
    function undoLastDeletion() { AppController.undo(); }
    // ── Section ops ─────────────────────────────────────────────────────────

    function _replaceSections(updater) {
        const copy = sections.map(function (s) {
            return Object.assign({}, s, { items: s.items.slice() });
        });
        updater(copy);
        sections = copy;
    }

    function _sortedItems(section) {
        const arr = (section.items || []).slice();
        const mode = section.sortBy || "manual";
        if (mode === "manual") return arr;
        const desc = !!section.sortDesc;
        const k = mode === "ref" ? "ref"
                : mode === "title" ? "title"
                : mode === "updated" ? "updated"
                : "";
        if (!k) return arr;
        arr.sort(function (a, b) {
            const va = String((a && a[k]) || "").toLowerCase();
            const vb = String((b && b[k]) || "").toLowerCase();
            if (va < vb) return desc ? 1 : -1;
            if (va > vb) return desc ? -1 : 1;
            return 0;
        });
        return arr;
    }

    function setSortBy(sectionId, sortBy, sortDesc) {
        _replaceSections(function (copy) {
            const s = copy.find(function (x) { return x.id === sectionId; });
            if (!s) return;
            s.sortBy = sortBy;
            s.sortDesc = !!sortDesc;
        });
    }

    function _reorderDoc(srcSectionId, srcId, dstSectionId, dstId, before) {
        _replaceSections(function (copy) {
            const src = copy.find(function (x) { return x.id === srcSectionId; });
            if (!src) return;
            const i = src.items.findIndex(function (it) { return it.id === srcId; });
            if (i < 0) return;
            const moved = src.items.splice(i, 1)[0];

            const dst = copy.find(function (x) { return x.id === dstSectionId; });
            if (!dst) { src.items.splice(i, 0, moved); return; }
            let j;
            if (dstId === "" || dstId === undefined) {
                j = dst.items.length;
            } else {
                j = dst.items.findIndex(function (it) { return it.id === dstId; });
                if (j < 0) j = dst.items.length;
                if (!before) j += 1;
            }
            dst.items.splice(j, 0, moved);
            dst.sortBy = "manual";
        });
    }

    function _reorderSection(srcId, dstId, before) {
        if (srcId === dstId) return;
        const copy = sections.slice();
        const i = copy.findIndex(function (s) { return s.id === srcId; });
        if (i < 0) return;
        const moved = copy.splice(i, 1)[0];
        let j = copy.findIndex(function (s) { return s.id === dstId; });
        if (j < 0) j = copy.length;
        if (!before) j += 1;
        copy.splice(j, 0, moved);
        sections = copy;
    }

    function _moveSectionByDelta(sectionId, delta) {
        const copy = sections.slice();
        const i = copy.findIndex(function (s) { return s.id === sectionId; });
        if (i < 0) return;
        const j = Math.max(0, Math.min(copy.length - 1, i + delta));
        if (i === j) return;
        const moved = copy.splice(i, 1)[0];
        copy.splice(j, 0, moved);
        sections = copy;
    }

    function _moveDocByDelta(sectionId, id, delta) {
        _replaceSections(function (copy) {
            const s = copy.find(function (x) { return x.id === sectionId; });
            if (!s) return;
            const i = s.items.findIndex(function (it) { return it.id === id; });
            if (i < 0) return;
            const j = Math.max(0, Math.min(s.items.length - 1, i + delta));
            if (i === j) return;
            const moved = s.items.splice(i, 1)[0];
            s.items.splice(j, 0, moved);
            s.sortBy = "manual";
        });
    }

    function _moveListItemByDelta(listName, idx, delta) {
        const list = (listName === "snippets" ? snippets : contacts).slice();
        const j = Math.max(0, Math.min(list.length - 1, idx + delta));
        if (idx === j) return;
        const moved = list.splice(idx, 1)[0];
        list.splice(j, 0, moved);
        if (listName === "snippets") snippets = list;
        else contacts = list;
    }

    function saveDoc(draft) {
        const targetSectionId = draft._sectionId || editor.sectionId;
        const cleaned = Object.assign({}, draft);
        delete cleaned._sectionId;
        delete cleaned._isNew;
        const editingId = editor.isNew ? "" : (editor.originalId || cleaned.id || "");
        if (!cleaned.id || editor.isNew) cleaned.id = root._newEntryId();
        if (editingId.length > 0) cleaned.id = editingId;

        _replaceSections(copy => {
            if (editor.isNew) {
                const target = copy.find(s => s.id === targetSectionId);
                if (target) target.items.push(cleaned);
            } else {
                for (let s of copy) {
                    if (s.id === editor.sectionId) {
                        if (targetSectionId === s.id) {
                            s.items = s.items.map(i => i.id === editingId ? cleaned : i);
                        } else {
                            s.items = s.items.filter(i => i.id !== editingId);
                        }
                    } else if (s.id === targetSectionId) {
                        s.items.push(cleaned);
                    }
                }
            }
        });
        showToast(I18n.t(editor.isNew ? "docs.toast.created" : "docs.toast.saved").arg(cleaned.ref || cleaned.title));
    }
    function deleteDoc(sectionId, id) {
        const sec = sections.find(function (s) { return s.id === sectionId; });
        if (!sec) return;
        const captured = sec.items.find(function (i) { return i.id === id; });
        if (!captured) return;

        _beginUndoable();
        _replaceSections(function (copy) {
            for (let s of copy)
                if (s.id === sectionId) s.items = s.items.filter(function (i) { return i.id !== id; });
        });
        const name = captured.ref || captured.title;
        _commitUndoable(I18n.t("docs.toast.restored").arg(name));
        showUndoToast(I18n.t("docs.toast.deleted").arg(name), function () {
            root.undoLastDeletion()
        });
    }

    function saveSnippet(draft, idx) {
        // The editor holds tags as a comma-separated string; store them as a
        // normalized array so search/persistence stay structured (HEAP-79).
        if (typeof draft.tags === "string") {
            draft.tags = draft.tags.split(",").map(function (s) { return s.trim(); })
                                   .filter(function (s) { return s.length > 0; });
        } else if (!Array.isArray(draft.tags)) {
            draft.tags = [];
        }
        const list = snippets.slice();
        if (idx < 0 || idx === undefined) {
            list.push(draft);
            showToast(I18n.t("docs.toast.snippet.created").arg(draft.title));
        } else {
            list[idx] = draft;
            showToast(I18n.t("docs.toast.snippet.saved").arg(draft.title));
        }
        snippets = list;
    }
    function deleteSnippet(idx) {
        if (idx < 0 || idx >= snippets.length) return;
        const captured = snippets[idx];
        _beginUndoable();
        const list = snippets.slice();
        list.splice(idx, 1);
        snippets = list;
        _commitUndoable(I18n.t("docs.toast.restored").arg(captured.title));
        showUndoToast(I18n.t("docs.toast.snippet.deleted").arg(captured.title), function () {
            root.undoLastDeletion()
        });
    }

    function saveContact(draft, idx) {
        const list = contacts.slice();
        if (idx < 0 || idx === undefined) {
            list.push(draft);
            showToast(I18n.t("docs.toast.contact.added").arg(draft.name));
        } else {
            list[idx] = draft;
            showToast(I18n.t("docs.toast.contact.saved").arg(draft.name));
        }
        contacts = list;
    }
    function saveSection(draft, originalId) {
        const copy = sections.map(function (s) {
            return Object.assign({}, s, { items: s.items.slice(), customFields: (s.customFields || []).slice() });
        });
        if (originalId === "" || originalId === undefined) {
            // create — generate id
            let base = String(draft.title || "section").toLowerCase()
                            .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
            if (base.length === 0) base = "section";
            let id = base;
            let n = 2;
            while (copy.some(function (s) { return s.id === id; })) { id = base + "-" + n; n++; }
            copy.push({
                id: id,
                title: draft.title || "",
                subtitle: draft.subtitle || "",
                accent: draft.accent || Theme.accent,
                customFields: (draft.customFields || []).slice(),
                items: []
            });
            sections = copy;
            showToast(I18n.t("docs.toast.section.created").arg(draft.title));
        } else {
            const i = copy.findIndex(function (s) { return s.id === originalId; });
            if (i < 0) return;
            copy[i].title        = draft.title || copy[i].title;
            copy[i].subtitle     = draft.subtitle || "";
            copy[i].accent       = draft.accent || copy[i].accent;
            copy[i].customFields = (draft.customFields || []).slice();
            sections = copy;
            showToast(I18n.t("docs.toast.section.saved").arg(draft.title));
        }
    }

    function deleteSection(sectionId) {
        const i = sections.findIndex(function (s) { return s.id === sectionId; });
        if (i < 0) return;
        const captured = sections[i];
        _beginUndoable();
        const copy = sections.slice();
        copy.splice(i, 1);
        sections = copy;
        _commitUndoable(I18n.t("docs.toast.section.restored").arg(captured.title));
        showUndoToast(I18n.t("docs.toast.section.deleted").arg(captured.title), function () {
            root.undoLastDeletion()
        });
    }

    function deleteContact(idx) {
        if (idx < 0 || idx >= contacts.length) return;
        const captured = contacts[idx];
        _beginUndoable();
        const list = contacts.slice();
        list.splice(idx, 1);
        contacts = list;
        // An imported contact would come back on the next sync; AppController
        // records the deletion where the importer can see it (and takes the
        // record back when the deletion is undone).
        _commitUndoable(I18n.t("docs.toast.restored").arg(captured.name));
        showUndoToast(I18n.t("docs.toast.contact.deleted").arg(captured.name), function () {
            root.undoLastDeletion()
        });
    }

    // "#name" is a link into the docs themselves: the page of that title (or
    // id) opens in the Pages tab. Anything else goes through the same confirm
    // step the notes preview uses — this view used to refuse an unusual link
    // with a toast where the preview asked about the very same URL.
    function openExternal(url) {
        if (!url) return;
        if (url.indexOf("#") === 0) {
            const want = url.substring(1).trim();
            const m = AppController.docPages;
            const rTitle = m.roleOf("title"), rId = m.roleOf("id");
            for (let i = 0; i < m.rowCount(); i++) {
                const idx = m.index(i, 0);
                const id = String(m.data(idx, rId));
                if (id === want || String(m.data(idx, rTitle)).toLowerCase() === want.toLowerCase()) {
                    root.tab = "pages";
                    AppController.activeDocPageId = id;
                    return;
                }
            }
            showToast(I18n.t("docs.wiki.missing").arg(want));
            return;
        }
        linkConfirm.openLink(url);
    }
    LinkConfirmDialog { id: linkConfirm }

    // ── Layout ──────────────────────────────────────────────────────────────

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // Pages are the long-form half; References is the catalog this view has
    // always been. It stays the default, because an existing profile has no
    // pages yet and landing on an empty tree would read as the docs being gone.
    property string tab: "references"

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Head bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: Theme.panel
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.border }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.inset; anchors.rightMargin: Theme.inset
                spacing: Theme.sp2xl

                ColumnLayout {
                    spacing: 1
                    Layout.alignment: Qt.AlignVCenter
                    Text { text: I18n.t("docs.header"); color: Theme.text; font.pixelSize: Theme.fsLg; font.weight: Theme.fwHeading }
                    Text {
                        text: I18n.t("docs.counts").arg(root.totalDocs()).arg(root.snippets.length).arg(root.contacts.length)
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.features: Theme.tabularNums
                        font.pixelSize: Theme.fsSm
                    }
                }

                // Pages | References
                Row {
                    spacing: 0
                    Repeater {
                        model: ["pages", "references"]
                        delegate: Rectangle {
                            required property var modelData
                            objectName: "docs-tab-" + modelData
                            width: 96; height: 26
                            color: root.tab === modelData ? Theme.withAlpha(Theme.accent, 0.16)
                                 : tabMA.hovered ? Theme.panel3 : Theme.panel2
                            border.color: root.tab === modelData ? Theme.accent : Theme.border
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: I18n.t("docs.tab." + modelData)
                                color: root.tab === modelData ? Theme.text : Theme.textDim
                                font.pixelSize: Theme.fsSm
                                font.weight: root.tab === modelData ? Theme.fwTitle : Theme.fwBody
                            }
                            ClickArea {
                                id: tabMA
                                label: I18n.t("docs.tab." + modelData)
                                role: Accessible.PageTab
                                checkable: true
                                checked: root.tab === modelData
                                showTip: false
                                onActivated: root.tab = modelData
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Search
                Rectangle {
                    Layout.preferredWidth: 320
                    Layout.preferredHeight: 28
                    radius: Theme.radiusMd
                    color: Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spSm
                        spacing: Theme.spSm
                        Text { text: "⌕"; color: Theme.textDim; font.pixelSize: Theme.fsSm }
                        TextField {
                            id: docsSearch
                            ContextMenu.menu: TextEditMenu { editor: docsSearch }
                            objectName: "docsSearchField"
                            Layout.fillWidth: true
                            placeholderText: I18n.t("docs.search.placeholder")
                            color: Theme.text
                            placeholderTextColor: Theme.textDim
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fsMd
                            background: Item {}
                            selectByMouse: true
                            text: root.searchText
                            onTextChanged: root.searchText = text
                        }
                        Rectangle {
                            visible: root.searchText.length > 0
                            width: 18; height: 18; radius: 9
                            color: clearMA.hovered ? Theme.panel3 : "transparent"
                            Text { anchors.centerIn: parent; text: "×"; color: Theme.textDim; font.pixelSize: Theme.fsLg }
                            ClickArea {
                                id: clearMA
                                objectName: "docs-search-clear"
                                label: I18n.t("docs.a11y.clearSearch")
                                onActivated: { root.searchText = ""; docsSearch.text = "" }
                            }
                        }
                    }
                }

            }
        }

        // Body — the page tree, or the catalog.
        DocsPagesPane {
            id: pagesPane
            objectName: "docs-pages-pane"
            visible: root.tab === "pages"
            Layout.fillWidth: true
            Layout.fillHeight: true
            onLinkActivated: (kind, target) => root.linkRequested(kind, target)
        }

        // Body — nav + scrollable content
        RowLayout {
            visible: root.tab === "references"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Nav rail
            Rectangle {
                Layout.preferredWidth: 220
                Layout.fillHeight: true
                color: Theme.panel
                Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.border }

                Column {
                    id: navCol
                    anchors.fill: parent
                    anchors.margins: Theme.spLg
                    spacing: Theme.sp2xs

                    Repeater {
                        model: root.sections
                        delegate: NavLink {
                            required property var modelData
                            required property int index
                            width: navCol.width
                            label: modelData.title
                            count: modelData.items.length
                            barColor: modelData.accent
                            anchorId: "sec-" + modelData.id
                            sectionId: modelData.id
                            sectionIndex: index
                        }
                    }

                    Item { width: navCol.width; height: 8 }
                    Rectangle { width: navCol.width; height: 1; color: Theme.border }
                    Item { width: navCol.width; height: 6 }

                    NavLink {
                        width: navCol.width
                        label: I18n.t("docs.snippets")
                        count: root.snippets.length
                        barColor: Theme.accent
                        anchorId: "sec-snippets"
                    }
                    NavLink {
                        width: navCol.width
                        label: I18n.t("docs.nav.contacts")
                        count: root.contacts.length
                        barColor: Theme.textMuted
                        anchorId: "sec-contacts"
                    }

                    Item { width: navCol.width; height: 10 }

                    Rectangle {
                        width: navCol.width
                        height: 28
                        radius: Theme.radiusMd
                        color: addSecMA.hovered ? Theme.accentSoft : Theme.panel2
                        border.color: Theme.border
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                            spacing: Theme.spSm
                            Text {
                                text: "+"
                                color: addSecMA.hovered ? Theme.accentStrong : Theme.textDim
                                font.pixelSize: Theme.fsLg
                            }
                            Text {
                                Layout.fillWidth: true
                                text: I18n.t("docs.newSection")
                                color: addSecMA.hovered ? Theme.accentStrong : Theme.text
                                font.pixelSize: Theme.fsMd
                            }
                        }
                        ClickArea {
                            id: addSecMA
                            objectName: "docs-new-section"
                            label: I18n.t("docs.newSection")
                            showTip: false
                            onActivated: root.openSectionCreate()
                        }
                    }
                }
            }

            // Body — explicit Flickable so we can fully control wheel speed
            // and pressDelay (so quick LMB-drag pans the page).
            Flickable {
                id: bodyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: bodyCol.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                pressDelay: 180

                NumberAnimation {
                    id: wheelAnim
                    target: bodyScroll
                    property: "contentY"
                    duration: Theme.durMove
                    easing.type: Theme.easeEnter
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const dy = event.angleDelta.y;
                        if (dy === 0) return;
                        const maxY = Math.max(0, bodyScroll.contentHeight - bodyScroll.height);
                        if (maxY <= 0) return;
                        // Subsequent wheel events build on the in-flight target,
                        // so several quick notches accumulate distance smoothly.
                        const base = wheelAnim.running ? wheelAnim.to : bodyScroll.contentY;
                        const newY = Math.max(0, Math.min(maxY, base - dy * 3));
                        if (newY === base) return;
                        wheelAnim.from = bodyScroll.contentY;
                        wheelAnim.to = newY;
                        wheelAnim.restart();
                    }
                }

                ScrollBar.vertical: ThinScrollBar {}

                ColumnLayout {
                    id: bodyCol
                    width: bodyScroll.width
                    spacing: Theme.sp3xl

                    // Nothing kept here yet (APP-191): what the page is for
                    // and where to start. The sections below stay, so their
                    // "+ Add" is right there.
                    EmptyState {
                        objectName: "docs-empty"
                        visible: root.searchText.trim().length === 0 && root.totalDocs() === 0
                                 && root.snippets.length === 0 && root.contacts.length === 0
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(bodyCol.width - 2 * Theme.sp3xl, 420)
                        Layout.topMargin: Theme.sp3xl
                        icon: "heap-08-docs"
                        title: I18n.t("docs.empty")
                        line: I18n.t("docs.empty.hint")
                    }

                    ColumnLayout {
                        objectName: "docs-no-matches"
                        visible: root.searchFoundNothing
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.sp3xl
                        spacing: Theme.spMd
                        EmptyState {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Math.min(bodyCol.width - 2 * Theme.sp3xl, 420)
                            title: I18n.t("docs.noMatches").arg(root.searchText.trim())
                            line: I18n.t("docs.noMatches.hint")
                        }
                        PillButton {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.t("docs.search.clear")
                            onClicked: { root.searchText = ""; docsSearch.text = ""; docsSearch.forceActiveFocus(); }
                        }
                    }

                    // Doc sections
                    Repeater {
                        model: root.sections
                        delegate: ColumnLayout {
                            id: secCol
                            required property var modelData
                            required property int index
                            property var section: modelData
                            property var filtered: root._sortedItems(section).filter(root.passesSearch)
                            visible: !(root.searchText.length > 0 && filtered.length === 0)
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.sp3xl
                            Layout.rightMargin: Theme.sp3xl
                            Layout.topMargin: index === 0 ? 20 : 0
                            spacing: Theme.spXl

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                id: secAnchor
                                objectName: "sec-" + secCol.section.id

                                // Hover drives the ✎ / × reveal below. It must be
                                // a HoverHandler, not this MouseArea: hover stops
                                // at the first item that accepts it, so the icons
                                // disappeared as soon as the pointer reached them.
                                property bool headerHovered: false
                                HoverHandler { onHoveredChanged: secAnchor.headerHovered = hovered }

                                MouseArea {
                                    id: secHover
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) sectionMenu.popup()
                                    }
                                }

                                AppMenu {
                                    id: sectionMenu
                                    AppMenuItem { text: I18n.t("docs.addEntry");       onTriggered: root.openDocCreate(secCol.section.id) }
                                    AppMenuItem { text: I18n.t("docs.menu.renameFields"); onTriggered: root.openSectionEdit(secCol.section) }
                                    AppMenu {
                                        title: I18n.t("docs.menu.sortBy")
                                        AppMenuItem { text: I18n.t("docs.menu.sort.manual");  onTriggered: root.setSortBy(secCol.section.id, "manual", false) }
                                        AppMenuItem { text: I18n.t("docs.menu.sort.ref");     onTriggered: root.setSortBy(secCol.section.id, "ref", false) }
                                        AppMenuItem { text: I18n.t("docs.menu.sort.title");   onTriggered: root.setSortBy(secCol.section.id, "title", false) }
                                        AppMenuItem { text: I18n.t("docs.menu.sort.updated"); onTriggered: root.setSortBy(secCol.section.id, "updated", true) }
                                    }
                                    AppMenuSeparator {}
                                    AppMenuItem { text: I18n.t("docs.menu.moveUp");   enabled: secCol.index > 0;                              onTriggered: root._moveSectionByDelta(secCol.section.id, -1) }
                                    AppMenuItem { text: I18n.t("docs.menu.moveDown"); enabled: secCol.index < root.sections.length - 1;       onTriggered: root._moveSectionByDelta(secCol.section.id, +1) }
                                    AppMenuSeparator {}
                                    AppMenuItem { danger: true; text: I18n.t("docs.menu.deleteSection"); onTriggered: root.deleteSection(secCol.section.id) }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.spXl
                                    Rectangle { width: 4; height: 32; radius: 2; color: secCol.section.accent }
                                    ColumnLayout {
                                        spacing: 0
                                        Layout.fillWidth: true
                                        RowLayout {
                                            spacing: Theme.spSm
                                            Text {
                                                text: secCol.section.title
                                                color: Theme.text
                                                font.pixelSize: Theme.fsLg
                                                font.weight: Theme.fwTitle
                                            }
                                            IconButton {
                                                objectName: "docs-section-edit"
                                                glyph: "✎"
                                                label: I18n.t("docs.menu.renameFields")
                                                revealed: secAnchor.headerHovered
                                                restColor: "transparent"
                                                onActivated: root.openSectionEdit(secCol.section)
                                            }
                                            IconButton {
                                                objectName: "docs-section-delete"
                                                glyph: "×"
                                                danger: true
                                                label: I18n.t("docs.menu.deleteSection")
                                                revealed: secAnchor.headerHovered
                                                restColor: "transparent"
                                                onActivated: root.deleteSection(secCol.section.id)
                                            }
                                        }
                                        Text { text: secCol.section.subtitle; color: Theme.textMuted; font.pixelSize: Theme.fsMd }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        visible: (secCol.section.sortBy || "manual") !== "manual"
                                        text: {
                                            const m = secCol.section.sortBy || "manual";
                                            const lbl = m === "ref" ? "ref" : m === "title" ? "title" : m === "updated" ? "upd" : m;
                                            return "▼ " + lbl + (secCol.section.sortDesc ? " ↓" : " ↑");
                                        }
                                        color: Theme.accentStrong
                                        font.family: Theme.fontUi
                                        font.features: Theme.tabularNums
                                        font.pixelSize: Theme.fsXs
                                    }
                                    Text {
                                        text: secCol.filtered.length + " / " + secCol.section.items.length
                                        color: Theme.textDim
                                        font.family: Theme.fontUi
                                        font.features: Theme.tabularNums
                                        font.pixelSize: Theme.fsSm
                                    }
                                    PillButton {
                                        text: I18n.t("docs.add")
                                        onClicked: root.openDocCreate(secCol.section.id)
                                    }
                                }

                            }

                            // Grid of cards (2 columns)
                            Grid {
                                id: cardGrid
                                Layout.fillWidth: true
                                columns: Math.max(1, Math.floor(width / 340))
                                columnSpacing: Theme.spXl
                                rowSpacing: Theme.spXl

                                Repeater {
                                    model: secCol.filtered
                                    delegate: DocCard {
                                        required property var modelData
                                        required property int index
                                        item: modelData
                                        accent: secCol.section.accent
                                        sectionId: secCol.section.id
                                        customFields: secCol.section.customFields || []
                                        width: (cardGrid.width - (cardGrid.columns - 1) * cardGrid.columnSpacing) / cardGrid.columns
                                    }
                                }

                                Rectangle {
                                    id: addEntryTile
                                    width: cardGrid.columns > 0
                                           ? ((cardGrid.width - (cardGrid.columns - 1) * cardGrid.columnSpacing) / cardGrid.columns)
                                           : cardGrid.width
                                    height: 100
                                    radius: Theme.radiusLg
                                    color: addCardMA.hovered ? Theme.panel2 : "transparent"
                                    border.color: Theme.border
                                    border.width: 1
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Theme.spXs
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "+"; color: Theme.textDim; font.pixelSize: Theme.fsXl }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: I18n.t("docs.addEntry"); color: Theme.textDim; font.pixelSize: Theme.fsSm }
                                    }
                                    ClickArea {
                                        id: addCardMA
                                        // Named after its section: six tiles all
                                        // read "Add entry" to a screen reader (SHELL-17).
                                        label: I18n.t("docs.a11y.addEntryTo").arg(secCol.section.title || "")
                                        showTip: false
                                        onActivated: root.openDocCreate(secCol.section.id)
                                    }
                                }
                            }
                        }
                    }

                    // Snippets
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.sp3xl
                        Layout.rightMargin: Theme.sp3xl
                        spacing: Theme.spXl
                        Item {
                            Layout.fillWidth: true; Layout.preferredHeight: 44
                            objectName: "sec-snippets"
                            RowLayout {
                                anchors.fill: parent
                                spacing: Theme.spXl
                                Rectangle { width: 4; height: 32; radius: 2; color: Theme.accent }
                                ColumnLayout {
                                    spacing: 0
                                    Text { text: I18n.t("docs.snippets"); color: Theme.text; font.pixelSize: Theme.fsLg; font.weight: Theme.fwTitle }
                                    Text {
                                        text: I18n.t("docs.cat.snippets.sub"); color: Theme.textMuted; font.pixelSize: Theme.fsMd
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    // Reflects the filter so the header does
                                    // not claim nine snippets above one card.
                                    text: root.matchingSnippetCount + ""
                                    color: Theme.textDim
                                    font.family: Theme.fontUi
                                    font.features: Theme.tabularNums
                                    font.pixelSize: Theme.fsSm
                                }
                                PillButton {
                                    text: I18n.t("docs.add")
                                    onClicked: root.openSnippetCreate()
                                }
                            }
                        }

                        Repeater {
                            // The full list stays the model and non-matching
                            // cards hide themselves: `idx` is the index into
                            // root.snippets that edit and delete act on, so a
                            // filtered model would make them act on the wrong
                            // snippet. A ColumnLayout skips invisible children.
                            model: root.snippets
                            delegate: SnippetCard {
                                required property var modelData
                                required property int index
                                visible: root.snippetPassesSearch(modelData)
                                snip: modelData
                                idx: index
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Contacts
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.sp3xl
                        Layout.rightMargin: Theme.sp3xl
                        Layout.bottomMargin: 32
                        spacing: Theme.spXl
                        Item {
                            Layout.fillWidth: true; Layout.preferredHeight: 44
                            objectName: "sec-contacts"
                            RowLayout {
                                anchors.fill: parent
                                spacing: Theme.spXl
                                Rectangle { width: 4; height: 32; radius: 2; color: Theme.textMuted }
                                ColumnLayout {
                                    spacing: 0
                                    Text { text: I18n.t("docs.contacts"); color: Theme.text; font.pixelSize: Theme.fsLg; font.weight: Theme.fwTitle }
                                    Text {
                                        text: I18n.t("docs.cat.contacts.sub"); color: Theme.textMuted; font.pixelSize: Theme.fsMd
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.matchingContactCount + ""
                                    color: Theme.textDim
                                    font.family: Theme.fontUi
                                    font.features: Theme.tabularNums
                                    font.pixelSize: Theme.fsSm
                                }
                                PillButton {
                                    text: I18n.t("docs.add")
                                    onClicked: root.openContactCreate()
                                }
                            }
                        }

                        Grid {
                            Layout.fillWidth: true
                            columns: Math.max(1, Math.floor(width / 280))
                            columnSpacing: Theme.spLg
                            rowSpacing: Theme.spMd
                            Repeater {
                                // Same as the snippets above: `idx` indexes
                                // root.contacts, so filter by visibility.
                                model: root.contacts
                                delegate: ContactCard {
                                    required property var modelData
                                    required property int index
                                    visible: root.contactPassesSearch(modelData)
                                    c: modelData
                                    idx: index
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Toast ───────────────────────────────────────────────────────────────
    Toast {
        id: toast
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.sp3xl
        anchors.horizontalCenter: parent.horizontalCenter
        z: 80
    }

    // ── Editor ──────────────────────────────────────────────────────────────
    DocsEditor {
        id: editor
        sections: root.sections
        contactPalette: root.contactPalette
        accentPalette: root.accentPalette
        onSavedDoc:     (draft) => root.saveDoc(draft)
        onDeletedDoc:   () => root.deleteDoc(editor.sectionId, editor.originalId)
        onSavedSnippet: (draft) => root.saveSnippet(draft, editor.idx)
        onDeletedSnippet: () => root.deleteSnippet(editor.idx)
        onSavedContact: (draft) => root.saveContact(draft, editor.idx)
        onDeletedContact: () => root.deleteContact(editor.idx)
        onSavedSection: (draft) => root.saveSection(draft, editor.sectionId)
        onDeletedSection: () => root.deleteSection(editor.sectionId)
    }

    function _sectionCustomFields(sectionId) {
        const s = sections.find(function (x) { return x.id === sectionId; });
        return s ? (s.customFields || []) : [];
    }
    function openDocCreate(sectionId) {
        editor.kind = "doc";
        editor.sectionId = sectionId;
        editor.originalRef = "";
        editor.originalId = "";
        editor.isNew = true;
        editor.docCustomFields = root._sectionCustomFields(sectionId);
        editor.draft = ({ ref: "", title: "", desc: "", url: "", source: "", version: "", updated: "", extra: {}, _sectionId: sectionId });
        editor.open();
    }
    function openDocEdit(sectionId, item) {
        editor.kind = "doc";
        editor.sectionId = sectionId;
        editor.originalRef = item.ref;
        editor.originalId = item.id || "";
        editor.isNew = false;
        editor.docCustomFields = root._sectionCustomFields(sectionId);
        editor.draft = Object.assign({ extra: {} }, item, { _sectionId: sectionId, extra: Object.assign({}, item.extra || {}) });
        editor.open();
    }
    function openSnippetCreate() {
        editor.kind = "snippet";
        editor.idx = -1;
        editor.isNew = true;
        editor.draft = ({ title: "", lang: "sh", code: "", tags: "" });
        editor.open();
    }
    function openSnippetEdit(idx) {
        editor.kind = "snippet";
        editor.idx = idx;
        editor.isNew = false;
        const d = Object.assign({}, root.snippets[idx]);
        d.tags = Array.isArray(d.tags) ? d.tags.join(", ") : (d.tags || "");
        editor.draft = d;
        editor.open();
    }
    function openContactCreate() {
        editor.kind = "contact";
        editor.idx = -1;
        editor.isNew = true;
        editor.draft = ({ name: "", role: "", channel: "", mattermost: "", color: root.contactPalette[0] });
        editor.open();
    }
    function openContactEdit(idx) {
        editor.kind = "contact";
        editor.idx = idx;
        editor.isNew = false;
        editor.draft = Object.assign({}, root.contacts[idx]);
        editor.open();
    }

    function openSectionCreate() {
        editor.kind = "section";
        editor.sectionId = "";        // empty = create
        editor.isNew = true;
        editor.draft = ({ title: "", subtitle: "", accent: root.accentPalette[0] });
        editor.open();
    }
    function openSectionEdit(s) {
        editor.kind = "section";
        editor.sectionId = s.id;
        editor.isNew = false;
        editor.draft = ({
            title: s.title,
            subtitle: s.subtitle,
            accent: String(s.accent),
            customFields: (s.customFields || []).slice()
        });
        editor.open();
    }

    // ── Inline components ───────────────────────────────────────────────────

    component NavLink: Rectangle {
        id: nav
        property string label: ""
        property int count: 0
        property color barColor: Theme.accent
        property string anchorId: ""
        property string sectionId: ""       // empty → not draggable (snippets/contacts links)
        property int    sectionIndex: -1
        readonly property bool draggable: sectionId.length > 0
        height: 30
        radius: Theme.radiusMd
        color: navMA.containsMouse ? Theme.panel2 : "transparent"
        opacity: navDragMA.drag.active ? 0.5 : 1.0
        // The drag stays a pointer thing (the section menu moves sections);
        // jumping to a section is on the Tab path too (design audit DES-19).
        signal jump()
        onJump: root.scrollToAnchor(nav.anchorId)
        activeFocusOnTab: true
        Accessible.role: Accessible.Link
        Accessible.name: nav.label
        Accessible.onPressAction: nav.jump()
        Keys.onReturnPressed: nav.jump()
        Keys.onEnterPressed: nav.jump()
        Keys.onSpacePressed: nav.jump()
        FocusRing {}

        Drag.active: navDragMA.drag.active
        Drag.dragType: Drag.Internal
        Drag.keys: ["nav-section"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        property real homeX: 0
        property real homeY: 0

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
            spacing: Theme.spMd
            Rectangle { width: 4; height: 16; radius: 2; color: nav.barColor }
            Text { text: nav.label; color: Theme.text; font.pixelSize: Theme.fsMd; Layout.fillWidth: true; elide: Text.ElideRight }
            Text { text: nav.count + ""; color: Theme.textDim; font.family: Theme.fontUi; font.features: Theme.tabularNums; font.pixelSize: Theme.fsSm }
        }
        MouseArea {
            id: navMA
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
        MouseArea {
            id: navDragMA
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            drag.target: nav.draggable ? nav : null
            drag.threshold: 6
            property bool didDrag: false
            onPressed: (mouse) => {
                nav.homeX = nav.x; nav.homeY = nav.y; didDrag = false;
                if (mouse.button === Qt.RightButton && nav.draggable) navMenu.popup();
            }
            onPositionChanged: if (drag.active) didDrag = true
            onReleased: (mouse) => {
                const wasDrag = didDrag;
                if (nav.draggable) nav.Drag.drop();
                nav.x = nav.homeX; nav.y = nav.homeY;
                didDrag = false;
                if (!wasDrag && mouse.button === Qt.LeftButton) scrollToAnchor(nav.anchorId);
            }
        }

        // Receive drops from sibling NavLinks — top/bottom halves decide insert side.
        DropArea {
            anchors.fill: parent
            keys: ["nav-section"]
            property bool insertBefore: true
            property bool over: false
            enabled: nav.draggable
            onEntered: over = true
            onExited:  over = false
            onPositionChanged: (drag) => { insertBefore = (drag.y < height / 2) }
            onDropped: (drop) => {
                over = false;
                const srcId = drop.source && drop.source.sectionId;
                if (srcId && srcId !== nav.sectionId) {
                    root._reorderSection(srcId, nav.sectionId, insertBefore);
                    drop.accept(Qt.MoveAction);
                }
            }
            Rectangle {
                visible: parent.over && parent.insertBefore
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: 2; color: Theme.accent
            }
            Rectangle {
                visible: parent.over && !parent.insertBefore
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                height: 2; color: Theme.accent
            }
        }

        AppMenu {
            id: navMenu
            AppMenuItem {
                text: I18n.t("docs.menu.renameFields")
                onTriggered: {
                    const s = root.sections.find(function (x) { return x.id === nav.sectionId; });
                    if (s) root.openSectionEdit(s);
                }
            }
            AppMenu {
                title: I18n.t("docs.menu.sortBy")
                AppMenuItem { text: I18n.t("docs.menu.sort.manual");  onTriggered: root.setSortBy(nav.sectionId, "manual", false) }
                AppMenuItem { text: I18n.t("docs.menu.sort.ref");     onTriggered: root.setSortBy(nav.sectionId, "ref", false) }
                AppMenuItem { text: I18n.t("docs.menu.sort.title");   onTriggered: root.setSortBy(nav.sectionId, "title", false) }
                AppMenuItem { text: I18n.t("docs.menu.sort.updated"); onTriggered: root.setSortBy(nav.sectionId, "updated", true) }
            }
            AppMenuSeparator {}
            AppMenuItem { text: I18n.t("docs.menu.moveUp");   enabled: nav.sectionIndex > 0;                              onTriggered: root._moveSectionByDelta(nav.sectionId, -1) }
            AppMenuItem { text: I18n.t("docs.menu.moveDown"); enabled: nav.sectionIndex < root.sections.length - 1;        onTriggered: root._moveSectionByDelta(nav.sectionId, +1) }
            AppMenuSeparator {}
            AppMenuItem { danger: true; text: I18n.t("docs.menu.deleteSection"); onTriggered: root.deleteSection(nav.sectionId) }
        }
    }

    function scrollToAnchor(objectName) {
        // "page:<id>" is a doc page, which lives in the Pages tab.
        if (objectName.indexOf("page:") === 0) {
            root.tab = "pages";
            AppController.activeDocPageId = objectName.substring(5);
            return;
        }
        if (root.tab !== "references") root.tab = "references";
        const target = findChildByName(bodyCol, objectName);
        if (!target) return;
        const p = target.mapToItem(bodyCol, 0, 0);
        const newY = Math.max(0, Math.min(p.y - 8, bodyScroll.contentHeight - bodyScroll.height));
        wheelAnim.from = bodyScroll.contentY;
        wheelAnim.to = newY;
        wheelAnim.restart();
    }
    function findChildByName(parentItem, name) {
        if (!parentItem) return null;
        const kids = parentItem.children;
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i];
            if (k && k.objectName === name) return k;
            const sub = findChildByName(k, name);
            if (sub) return sub;
        }
        return null;
    }

    component DocCard: Rectangle {
        id: card
        property var item: ({})
        property color accent: Theme.accent
        property string sectionId: ""
        property var customFields: []
        readonly property bool isInternal: (item.url || "").indexOf("#") === 0
        // Drag-source identifiers (read by DropArea.drop.source)
        property string docId: item.id || ""
        property string docSectionId: sectionId
        height: cardCol.implicitHeight + 24
        radius: Theme.radiusLg
        // Hover state comes from a handler, not from cardMA: the card-wide
        // MouseArea swallowed the hover of the overlay buttons on top of it, so
        // they blinked out as the pointer approached.
        property bool cardHovered: false
        HoverHandler { onHoveredChanged: card.cardHovered = hovered }
        color: cardHovered ? Theme.panel2 : Theme.panel
        border.color: cardHovered ? Theme.borderStrong : Theme.border
        border.width: 1
        opacity: handleMA.drag.active ? 0.5 : 1.0

        Drag.active: handleMA.drag.active
        Drag.dragType: Drag.Internal
        Drag.keys: ["doc"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: 24

        property real homeX: 0
        property real homeY: 0
        function openDoc() { root.openExternal(card.item.url); }

        ColumnLayout {
            id: cardCol
            anchors.fill: parent
            anchors.margins: Theme.spXl
            spacing: Theme.spSm

            RowLayout {
                spacing: Theme.spSm
                Rectangle {
                    radius: Theme.radiusSm
                    color: "transparent"
                    border.color: card.accent
                    border.width: 1
                    implicitWidth: refT.implicitWidth + 14
                    implicitHeight: 20
                    Text { id: refT; anchors.centerIn: parent
                           text: card.item.ref || ""
                           color: card.accent
                           font.family: Theme.fontMono
                           font.pixelSize: Theme.fsSm
                           font.weight: Theme.fwTitle }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: (card.item.version || "").length > 0
                    text: card.item.version || ""
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsSm
                }
                Text {
                    text: card.isInternal ? "→" : "↗"
                    color: card.cardHovered ? Theme.accentStrong : Theme.textDim
                    font.pixelSize: Theme.fsMd
                }
            }
            Text {
                Layout.fillWidth: true
                text: card.item.title || ""
                color: Theme.text
                font.pixelSize: Theme.fsMd
                font.weight: Theme.fwTitle
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: card.item.desc || ""
                color: Theme.textMuted
                font.pixelSize: Theme.fsSm
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            // Custom extras — render rows for each field defined on the section
            Repeater {
                model: card.customFields
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.spSm
                    visible: (card.item && card.item.extra && String(card.item.extra[modelData.key] || "").length > 0)
                    Text {
                        text: (modelData.label || modelData.key) + ":"
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsXs
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.item && card.item.extra ? String(card.item.extra[modelData.key] || "") : ""
                        color: Theme.text
                        font.pixelSize: Theme.fsSm
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spXs
                Text {
                    text: card.item.source || ""
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsXs
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: (card.item.updated || "").length > 0
                    text: I18n.t("docs.updatedPrefix").arg(card.item.updated || "")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsXs
                }
            }
        }

        // The card opens its document from the keyboard too: Tab to it,
        // Return opens, the menu key or Shift+F10 opens its menu.
        ClickArea {
            id: cardMA
            objectName: "docs-card-open"
            label: (card.item.ref ? card.item.ref + " " : "") + (card.item.title || "")
            showTip: false
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onActivated: card.openDoc()
            onContextRequested: docCardMenu.popup()
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                    docCardMenu.popup(card, Theme.spXl, Theme.spXl);
                    event.accepted = true;
                }
            }
        }

        // Hover-overlay icons: ⋮⋮ drag handle (LMB drag-source), ✎ edit, × delete.
        // Keeping the drag-source to a small handle frees the rest of the card
        // for click + page-pan via the parent Flickable.
        //
        // Declared after cardMA so it stacks above it — otherwise every click on
        // ✎ / × landed on the card-wide MouseArea and opened the document URL
        // instead, which made the buttons decorative.
        Row {
            visible: !handleMA.drag.active
            anchors.top: parent.top; anchors.right: parent.right
            anchors.margins: Theme.spSm
            spacing: Theme.spXs
            Rectangle {
                // The drag handle is a pointer affordance; the keyboard has
                // the section menu's Move up / Move down.
                opacity: card.cardHovered ? 1 : 0
                enabled: card.cardHovered
                Behavior on opacity {
                    NumberAnimation {
                        duration: card.cardHovered ? Theme.durTap : Theme.durTapOut
                        easing.type: card.cardHovered ? Theme.easeEnter : Theme.easeExit
                    }
                }
                width: 18; height: 22; radius: Theme.radiusSm
                color: handleMA.containsMouse ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                Text { anchors.centerIn: parent; text: "⋮⋮"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: Theme.fsSm }
                MouseArea {
                    id: handleMA
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    drag.target: card
                    drag.threshold: 4
                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onPressed: { card.homeX = card.x; card.homeY = card.y }
                    onReleased: { card.Drag.drop(); card.x = card.homeX; card.y = card.homeY }
                }
            }
            IconButton {
                objectName: "docs-card-edit"
                glyph: "✎"
                label: I18n.t("docs.menu.edit")
                revealed: card.cardHovered
                onActivated: root.openDocEdit(card.sectionId, card.item)
            }
            IconButton {
                objectName: "docs-card-delete"
                glyph: "×"
                danger: true
                label: I18n.t("common.delete")
                revealed: card.cardHovered
                onActivated: root.deleteDoc(card.sectionId, card.item.id)
            }
        }

        // Drop target — top half inserts BEFORE, bottom half inserts AFTER
        DropArea {
            id: cardDrop
            anchors.fill: parent
            keys: ["doc"]
            property bool insertBefore: true
            property bool over: false
            onEntered: over = true
            onExited:  over = false
            onPositionChanged: (drag) => { insertBefore = (drag.y < height / 2) }
            onDropped: (drop) => {
                over = false;
                const src = drop.source;
                if (src && src !== card && src.docId !== undefined && src.docSectionId !== undefined) {
                    root._reorderDoc(src.docSectionId, src.docId, card.sectionId, card.item.id, insertBefore);
                    drop.accept(Qt.MoveAction);
                }
            }
            Rectangle {
                visible: cardDrop.over && cardDrop.insertBefore
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: 3; radius: Theme.radiusXs; color: Theme.accent
            }
            Rectangle {
                visible: cardDrop.over && !cardDrop.insertBefore
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                height: 3; radius: Theme.radiusXs; color: Theme.accent
            }
        }

        AppMenu {
            id: docCardMenu
            AppMenuItem {
                text: card.isInternal ? I18n.t("docs.menu.openWiki") : I18n.t("docs.menu.openUrl")
                enabled: (card.item.url || "").length > 0
                onTriggered: root.openExternal(card.item.url)
            }
            AppMenuItem { text: I18n.t("docs.menu.edit"); onTriggered: root.openDocEdit(card.sectionId, card.item) }
            AppMenuSeparator {}
            AppMenuItem { text: I18n.t("docs.menu.moveUp");   onTriggered: root._moveDocByDelta(card.sectionId, card.item.id, -1) }
            AppMenuItem { text: I18n.t("docs.menu.moveDown"); onTriggered: root._moveDocByDelta(card.sectionId, card.item.id, +1) }
            AppMenuSeparator {}
            AppMenuItem { danger: true; text: I18n.t("common.delete"); onTriggered: root.deleteDoc(card.sectionId, card.item.id) }
        }
    }

    component SnippetCard: Rectangle {
        id: sCard
        property var snip: ({})
        property int idx: -1
        radius: Theme.radiusLg
        color: Theme.panel
        // See DocCard: a handler, so the ✎ / × on top don't steal the hover that
        // reveals them.
        property bool cardHovered: false
        HoverHandler { onHoveredChanged: sCard.cardHovered = hovered }
        border.color: cardHovered ? Theme.borderStrong : Theme.border
        border.width: 1
        implicitHeight: sCol.implicitHeight + 20
        function copyCode() {
            AppController.copyToClipboard(sCard.snip.code || "");
            root.showToast(I18n.t("docs.toast.copied").arg(sCard.snip.title || ""));
        }
        function editSnippet() { root.openSnippetEdit(sCard.idx); }
        function deleteSnippet() { root.deleteSnippet(sCard.idx); }

        MouseArea {
            id: snHover
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: (mouse) => { if (mouse.button === Qt.RightButton) snipMenu.popup() }
        }

        ColumnLayout {
            id: sCol
            anchors.fill: parent
            anchors.margins: Theme.spLg
            spacing: Theme.spMd

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spSm
                Text { text: sCard.snip.title || ""; color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Theme.fwTitle; Layout.fillWidth: true; elide: Text.ElideRight }
                Rectangle {
                    radius: Theme.radiusSm
                    color: Theme.panel2
                    border.color: Theme.border; border.width: 1
                    implicitWidth: lngT.implicitWidth + 12
                    implicitHeight: 18
                    Text { id: lngT; anchors.centerIn: parent; text: sCard.snip.lang || ""; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: Theme.fsXs }
                }
                Rectangle {
                    radius: Theme.radiusSm
                    color: copySnMA.hovered ? Theme.accentSoft : Theme.panel2
                    border.color: copySnMA.hovered ? Theme.accent : Theme.border
                    border.width: 1
                    implicitWidth: copyT.implicitWidth + 14
                    implicitHeight: 22
                    Text { id: copyT; anchors.centerIn: parent; text: I18n.t("docs.copyShort"); color: copySnMA.hovered ? Theme.accentStrong : Theme.textMuted; font.pixelSize: Theme.fsSm }
                    ClickArea {
                        id: copySnMA
                        objectName: "docs-snippet-copy"
                        label: I18n.t("docs.a11y.copySnippet").arg(sCard.snip.title || "")
                        showTip: false
                        onActivated: sCard.copyCode()
                    }
                }
                IconButton {
                    objectName: "docs-snippet-edit"
                    glyph: "✎"
                    label: I18n.t("docs.menu.edit")
                    revealed: sCard.cardHovered
                    onActivated: sCard.editSnippet()
                }
                IconButton {
                    objectName: "docs-snippet-delete"
                    glyph: "×"
                    danger: true
                    label: I18n.t("common.delete")
                    revealed: sCard.cardHovered
                    onActivated: sCard.deleteSnippet()
                }
            }
            Rectangle {
                Layout.fillWidth: true
                color: Theme.bg2
                radius: Theme.radiusMd
                border.color: Theme.border
                border.width: 1
                implicitHeight: codeText.implicitHeight + 18
                TextEdit {
                    id: codeText
                    anchors.fill: parent
                    anchors.margins: Theme.spLg
                    text: sCard.snip.code || ""
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsMd
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.NoWrap
                }
                CodeHighlighter {
                    target: codeText.textDocument
                    language: sCard.snip.lang || "text"
                    palette: Theme.codePalette
                }
            }
        }

        AppMenu {
            id: snipMenu
            AppMenuItem {
                text: I18n.t("docs.copy")
                onTriggered: {
                    AppController.copyToClipboard(sCard.snip.code || "");
                    root.showToast(I18n.t("docs.toast.copied").arg(sCard.snip.title || ""));
                }
            }
            AppMenuItem { text: I18n.t("docs.menu.edit"); onTriggered: root.openSnippetEdit(sCard.idx) }
            AppMenuSeparator {}
            AppMenuItem { text: I18n.t("docs.menu.moveUp");   enabled: sCard.idx > 0;                        onTriggered: root._moveListItemByDelta("snippets", sCard.idx, -1) }
            AppMenuItem { text: I18n.t("docs.menu.moveDown"); enabled: sCard.idx < root.snippets.length - 1; onTriggered: root._moveListItemByDelta("snippets", sCard.idx, +1) }
            AppMenuSeparator {}
            AppMenuItem { danger: true; text: I18n.t("common.delete"); onTriggered: root.deleteSnippet(sCard.idx) }
        }
    }

    component ContactCard: Rectangle {
        id: cc
        property var c: ({})
        property int idx: -1
        width: parent ? ((parent.width - (parent.columns - 1) * parent.columnSpacing) / parent.columns) : 240
        height: 56
        radius: Theme.radiusLg
        // See DocCard — handler-driven hover so the row buttons stay put.
        property bool cardHovered: false
        HoverHandler { onHoveredChanged: cc.cardHovered = hovered }
        color: cardHovered ? Theme.panel2 : Theme.panel
        border.color: cardHovered ? Theme.borderStrong : Theme.border
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spLg
            spacing: Theme.spLg
            Rectangle {
                width: 32; height: 32; radius: 16
                color: cc.c.color || Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: root.initials(cc.c.name || "")
                    color: Theme.textOnAccent
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsMd
                    font.weight: Theme.fwTitle
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spSm
                    // PlainText, not the AutoText default: these strings come
                    // from the Mattermost server, and a first_name of
                    // "<img src=…>" would otherwise be fetched on render.
                    Text { text: cc.c.name || ""; textFormat: Text.PlainText; color: Theme.text; font.pixelSize: Theme.fsMd; font.weight: Theme.fwTitle; elide: Text.ElideRight; Layout.fillWidth: true }
                    // Says where the card came from, so an edit that a later
                    // sync may overwrite is not a surprise.
                    Rectangle {
                        visible: !!cc.c.source
                        radius: Theme.radiusXs
                        color: Theme.panel3
                        implicitWidth: srcT.implicitWidth + 8
                        implicitHeight: 14
                        Text {
                            id: srcT
                            anchors.centerIn: parent
                            text: "MM"
                            color: Theme.textDim
                            font.family: Theme.fontUi; font.features: Theme.tabularNums; font.pixelSize: Theme.fsXs
                        }
                    }
                }
                Text { text: cc.c.role || ""; textFormat: Text.PlainText; color: Theme.textMuted; font.pixelSize: Theme.fsSm; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            ColumnLayout {
                spacing: 0
                Text { text: cc.c.channel || ""; textFormat: Text.PlainText; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: Theme.fsXs }
                Text { text: cc.c.mattermost || ""; textFormat: Text.PlainText; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: Theme.fsXs }
            }
            Row {
                spacing: Theme.spXs
                IconButton {
                    objectName: "docs-contact-edit"
                    glyph: "✎"
                    label: I18n.t("docs.menu.edit")
                    revealed: cc.cardHovered
                    onActivated: root.openContactEdit(cc.idx)
                }
                IconButton {
                    objectName: "docs-contact-delete"
                    glyph: "×"
                    danger: true
                    label: I18n.t("common.delete")
                    revealed: cc.cardHovered
                    onActivated: root.deleteContact(cc.idx)
                }
            }
        }
        MouseArea {
            id: ccMA
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) ccMenu.popup();
                else root.openContactEdit(cc.idx);
            }
            z: -1
        }

        AppMenu {
            id: ccMenu
            AppMenuItem { text: I18n.t("docs.menu.edit"); onTriggered: root.openContactEdit(cc.idx) }
            AppMenuSeparator {}
            AppMenuItem { text: I18n.t("docs.menu.moveUp");   enabled: cc.idx > 0;                          onTriggered: root._moveListItemByDelta("contacts", cc.idx, -1) }
            AppMenuItem { text: I18n.t("docs.menu.moveDown"); enabled: cc.idx < root.contacts.length - 1;   onTriggered: root._moveListItemByDelta("contacts", cc.idx, +1) }
            AppMenuSeparator {}
            AppMenuItem { danger: true; text: I18n.t("common.delete"); onTriggered: root.deleteContact(cc.idx) }
        }
    }
}
