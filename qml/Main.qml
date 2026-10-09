import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import QtQuick.Dialogs
import TodoCpp
import "DocsStarter.js" as DocsStarter
import "ThemePresets.js" as Presets

ApplicationWindow {
    id: win
    // A login start (--minimized, APP-154) stays hidden in the tray; where
    // there is no tray it starts minimized instead (Component.onCompleted).
    visible: !(win._startHidden && win._minimizeToTray)
    width: 1440
    height: 900
    minimumWidth: 1100
    minimumHeight: 680
    // Every control that names no size of its own (a TextField, a combo's
    // text) reads the body size, so it follows the interface scale and the
    // system's text size with everything else (APP-183).
    font.pixelSize: Theme.fsMd

    // The OS draws the title bar and follows its own app mode, so a dark
    // heap on a light Windows sat under a white bar. Follow the theme, and
    // again once the window exists (a hidden start has no native frame yet).
    readonly property bool _frameDark: Theme.dark
    on_FrameDarkChanged: AppController.setWindowFrameDark(win, win._frameDark)
    onVisibleChanged: if (win.visible) AppController.setWindowFrameDark(win, win._frameDark)

    // ── Window geometry ───────────────────────────────────────────────
    // The window opened at a hardcoded 1440x900 in the same spot on every
    // launch, so resizing or moving it — or maximising it — was undone each
    // time the app started.
    //
    // Stored under settings.window in the same blob everything else uses.
    // SettingsView rewrites that blob wholesale but carries unknown top-level
    // keys across, so this survives a trip through the settings screen.
    property bool _geometryRestored: false
    readonly property bool _startHidden: typeof START_MINIMIZED !== "undefined" && START_MINIMIZED === true
    // A maximised window started hidden is maximised when first shown:
    // setting the visibility earlier would show it.
    property bool _maximizeOnShow: false

    // Builds the current view's loader on its first visit. Board, Notes and
    // Docs are never unloaded again.
    function activateCurrentView() {
        const v = AppController.currentView;
        if (v === "board") boardLoader.active = true;
        else if (v === "notes") notesLoader.active = true;
        else if (v === "docs") docsLoader.active = true;
    }

    // Whichever view is on screen. Four loaders now hold them — three kept
    // alive, one shared — so nothing outside should have to know which.
    function activeViewItem() {
        const v = AppController.currentView;
        if (v === "board") return boardLoader.item;
        if (v === "notes") return notesLoader.item;
        if (v === "docs") return docsLoader.item;
        return viewLoader.item;
    }

    // A #TICKET clicked in a note or doc page: the heap id, or a tracker key
    // ("PROJ-123") that a mirrored task carries.
    function openTaskById(key) {
        const t = AppController.taskById(AppController.taskIdForBranchMatch(key));
        if (t && t.id) taskEditor.showFor(Object.assign({}, t));
        else win.notice(I18n.t("notes.link.noTask").arg(key), "warning");
    }

    // A profile that has never opened Docs has no docs blob yet, so the
    // starter catalogue DocsView seeds on its first visit was unsearchable
    // from Ctrl+K until then. Seeded here instead, the same content in the
    // same language — DocsView reads it back as if it had written it.
    function seedStarterDocs() {
        if ((AppController.docsState || "").length > 0) return;
        AppController.docsState = JSON.stringify({
            sections: DocsStarter.sections(I18n.lang, [Theme.mStandup, Theme.mOneone, Theme.mSync, Theme.mFocus]),
            snippets: DocsStarter.snippets(I18n.lang),
            contacts: DocsStarter.contacts(I18n.lang)
        });
    }

    // The same link rules outside Notes: a doc page's [[note]] opens the note.
    function followMdLink(kind, target) {
        if (kind === "task") { win.openTaskById(target); return; }
        if (kind === "person") {
            const pid = AppController.personIdForHandle(target);
            if (pid.length > 0) personEditor.showFor(AppController.personById(pid));
            return;
        }
        if (kind === "note") {
            const hit = AppController.resolveNoteLink(target);
            if (hit.kind === "note" || hit.kind === "heading") {
                AppController.activeNoteId = hit.noteId;
                AppController.currentView = "notes";
                return;
            }
            const t = AppController.taskById(String(target).trim());
            if (t && t.id) { taskEditor.showFor(Object.assign({}, t)); return; }
            win.notice(I18n.t("notes.link.noNote").arg(target), "warning");
        }
    }

    function _settingsObject() {
        const raw = AppController.appSettingsJson || "";
        if (!raw.length) return ({});
        try { return JSON.parse(raw) || ({}); } catch (e) { return ({}); }
    }

    // True when at least a good part of `rect` lands on some screen. A window
    // restored onto a monitor that is no longer attached would otherwise open
    // off-screen with no way to drag it back.
    function _isOnAScreen(rect) {
        const screens = Qt.application.screens;
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            const ix = Math.max(0, Math.min(rect.x + rect.width,  s.virtualX + s.width)  - Math.max(rect.x, s.virtualX));
            const iy = Math.max(0, Math.min(rect.y + rect.height, s.virtualY + s.height) - Math.max(rect.y, s.virtualY));
            // A title bar's worth of overlap is enough to grab the window.
            if (ix >= 120 && iy >= 40) return true;
        }
        return false;
    }

    function _restoreGeometry() {
        const g = _settingsObject().window;
        if (!g) { win._geometryRestored = true; return; }

        const w = Math.max(win.minimumWidth,  Number(g.width)  || win.width);
        const h = Math.max(win.minimumHeight, Number(g.height) || win.height);
        const x = Number(g.x), y = Number(g.y);
        if (isFinite(x) && isFinite(y) && _isOnAScreen({ x: x, y: y, width: w, height: h })) {
            win.x = x;
            win.y = y;
        }
        win.width = w;
        win.height = h;
        if (g.maximized === true) {
            if (win.visible) win.visibility = Window.Maximized;
            else win._maximizeOnShow = true;
        }
        win._geometryRestored = true;
    }

    // x/y/width/height change continuously while a window is dragged or
    // resized, so the write is debounced rather than run per frame.
    Timer {
        id: geometrySaveTimer
        interval: 400
        onTriggered: win._saveGeometry()
    }

    function _saveGeometry() {
        if (!win._geometryRestored) return;
        const maximized = win.visibility === Window.Maximized;
        const s = _settingsObject();
        // While maximised, x/y/width/height describe the maximised frame —
        // keep the last normal geometry so unmaximising after a restart does
        // not snap the window to the full screen size.
        const prev = s.window || ({});
        s.window = maximized
            ? { x: prev.x, y: prev.y, width: prev.width, height: prev.height, maximized: true }
            : { x: win.x, y: win.y, width: win.width, height: win.height, maximized: false };
        AppController.appSettingsJson = JSON.stringify(s);
    }

    onXChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    onYChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    onWidthChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    onHeightChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    onVisibilityChanged: if (win._geometryRestored) geometrySaveTimer.restart()
    // Ends with the display name, so the OS title bar does not append it a
    // second time ("heap. — Work, in one place. - heap.").
    title: I18n.t("window.title")
    color: Theme.bg
    // The stock Basic controls (combo box lists, tooltips, scroll bars, and
    // anything not drawn by hand) take their colours from the palette. Left
    // alone it was the OS palette, which on Windows meant black popups with
    // white rows whatever the theme; this feeds it the theme's tokens.
    palette {
        window: Theme.panel
        windowText: Theme.text
        base: Theme.panel2
        alternateBase: Theme.panel3
        text: Theme.text
        button: Theme.panel2
        buttonText: Theme.text
        brightText: Theme.text
        highlight: Theme.accentSoft
        highlightedText: Theme.accentStrong
        light: Theme.panel2
        midlight: Theme.panel3
        mid: Theme.border
        dark: Theme.borderStrong
        shadow: Theme.scrim
        placeholderText: Theme.textDim
        link: Theme.mdLink
        toolTipBase: Theme.toastBg
        toolTipText: Theme.toastText
    }

    property string searchText: ""
    property var prioritiesFilter: ({})

    // The calendar + people column. It took 420px on every view, which on a
    // narrow window left two board columns. It folds away below
    // _rightPanelMinWidth unless asked for, and the choice on a wide window is
    // remembered in settings.
    // 1440, not 1280: a 1080p screen at 150% is 1280 logical px, and with both
    // side panels open that left the board about two columns.
    readonly property int _rightPanelMinWidth: 1440
    readonly property bool _narrow: win.width < _rightPanelMinWidth
    property bool _rightPanelWanted: _settingsObject().rightPanel !== false
    property bool _rightPanelOnNarrow: false
    // Week and month are a calendar already, and settings has nothing to plan
    // against: the panel's day grid next to them was a second calendar and
    // 420px less of the first. It stays folded there unless asked for, and
    // asking lasts until the app closes.
    readonly property bool _panelFoldedView: AppController.currentView === "week"
                                             || AppController.currentView === "month"
                                             || AppController.currentView === "settings"
    property bool _rightPanelInFoldedView: false
    readonly property bool rightPanelShown: AppController.currentView === "today" ? false
                                          : _narrow ? _rightPanelOnNarrow
                                          : _panelFoldedView ? _rightPanelInFoldedView
                                          : _rightPanelWanted
    function toggleRightPanel() {
        if (_narrow) {
            _rightPanelOnNarrow = !_rightPanelOnNarrow;
            return;
        }
        if (_panelFoldedView) {
            _rightPanelInFoldedView = !_rightPanelInFoldedView;
            return;
        }
        _rightPanelWanted = !_rightPanelWanted;
        const s = _settingsObject();
        s.rightPanel = _rightPanelWanted;
        AppController.appSettingsJson = JSON.stringify(s);
    }

    // Right panel width, dragged from its left edge. Clamped so the main
    // column keeps room for at least a couple of board columns; the stored
    // value is what the user dragged to, the clamp applies per window size.
    readonly property int rightPanelDefaultWidth: 420
    readonly property int rightPanelMinWidth: 300
    readonly property int rightPanelMaxWidth: Math.max(rightPanelMinWidth,
        Math.min(720, win.width - rail.width - 520))
    property int _rightPanelWidthWanted: {
        const w = Number(_settingsObject().rightPanelWidth);
        return isFinite(w) && w > 0 ? Math.round(w) : rightPanelDefaultWidth;
    }
    readonly property int rightPanelWidth: Math.max(rightPanelMinWidth,
        Math.min(rightPanelMaxWidth, _rightPanelWidthWanted))
    function setRightPanelWidth(w, persist) {
        _rightPanelWidthWanted = Math.max(rightPanelMinWidth, Math.min(rightPanelMaxWidth, Math.round(w)));
        if (persist) {
            const s = _settingsObject();
            s.rightPanelWidth = _rightPanelWidthWanted;
            AppController.appSettingsJson = JSON.stringify(s);
        }
    }

    // Left sidebar: labelled (expanded) or the 56px icon rail. The choice is
    // remembered; below _sideRailMinWidth it folds to the rail on its own
    // without overwriting what was chosen, same as the right panel.
    // heap 2 (APP-258): the sidebar folds to its icons below ~1100px.
    readonly property int _sideRailMinWidth: 1100
    property bool _sideRailWanted: _settingsObject().sideRailExpanded !== false
    property bool _sideRailOnNarrow: false
    readonly property bool sideRailExpanded: win.width < _sideRailMinWidth ? _sideRailOnNarrow : _sideRailWanted
    function toggleSideRail() {
        if (win.width < _sideRailMinWidth) {
            _sideRailOnNarrow = !_sideRailOnNarrow;
            return;
        }
        _sideRailWanted = !_sideRailWanted;
        const s = _settingsObject();
        s.sideRailExpanded = _sideRailWanted;
        AppController.appSettingsJson = JSON.stringify(s);
    }
    property bool showDoneTimeline: false
    property bool showArchived: false
    // Board column order. Lives on the window so it survives the board being
    // hidden, and so the filter bar and the board agree without either owning
    // the other.
    property string boardSortMode: "manual"

    // Search, priority chips, sort and the archived / done toggles survive a
    // restart (TASKS-22): they lived only on the window, so every launch
    // started from an unfiltered board. Kept in the UI settings blob, written
    // a moment after the last change rather than on every keystroke.
    property bool _filtersRestored: false
    function _restoreFilters() {
        const f = _settingsObject().filters || {};
        win.searchText = typeof f.search === "string" ? f.search : "";
        win.prioritiesFilter = (f.priorities && typeof f.priorities === "object") ? f.priorities : ({});
        win.boardSortMode = typeof f.sort === "string" && f.sort.length > 0 ? f.sort : "manual";
        win.showArchived = f.archived === true;
        win.showDoneTimeline = f.showDone === true;
        savedViewsHost.activeId = typeof f.savedView === "string" ? f.savedView : "";
        win._filtersRestored = true;
    }
    function _saveFiltersSoon() { if (win._filtersRestored) filterSaveTimer.restart(); }
    // The selection follows the filters: a card selected and then hidden by
    // the search left the selection with it, and Delete took it along with
    // the visible ones (TASKS-13, audit 2026-09-30). The Archive view lists
    // archived tasks whatever the toggle says; the timeline hides done ones
    // unless asked.
    function _syncSelectionFilter() {
        const v = AppController.currentView;
        const pri = [];
        for (const k in win.prioritiesFilter) if (win.prioritiesFilter[k]) pri.push(k);
        AppController.setSelectionFilter(win.searchText, pri, win.showArchived || v === "archive",
                                         v === "timeline" && !win.showDoneTimeline);
    }
    onSearchTextChanged: { _saveFiltersSoon(); _syncSelectionFilter(); }
    onPrioritiesFilterChanged: { _saveFiltersSoon(); _syncSelectionFilter(); }
    onBoardSortModeChanged: _saveFiltersSoon()
    onShowArchivedChanged: { _saveFiltersSoon(); _syncSelectionFilter(); }
    onShowDoneTimelineChanged: { _saveFiltersSoon(); _syncSelectionFilter(); }
    Connections {
        target: AppController
        function onCurrentViewChanged() { win._syncSelectionFilter(); }
    }
    Timer {
        id: filterSaveTimer
        interval: 400
        onTriggered: {
            const s = win._settingsObject();
            s.filters = { search: win.searchText, priorities: win.prioritiesFilter, sort: win.boardSortMode,
                          archived: win.showArchived, showDone: win.showDoneTimeline,
                          savedView: savedViewsHost.activeId };
            AppController.appSettingsJson = JSON.stringify(s);
        }
    }

    // Reactive task / status counts. statusCounts is one pass over the model,
    // recomputed when the model changes; these used to be four separate full
    // scans, re-run from all four of the model's signals.
    readonly property var _counts: AppController.statusCounts
    readonly property int _activeCount:  (_counts["prog"] || 0) + (_counts["half"] || 0)
    readonly property int _blockedCount: _counts["blocked"] || 0
    readonly property int _reviewCount:  _counts["review"] || 0
    readonly property var _activePriorities: {
        const out = [];
        for (const k in win.prioritiesFilter) if (win.prioritiesFilter[k]) out.push(k);
        return out;
    }

    // A built-in theme the update retired is kept as the user's own theme
    // with the palette it had, instead of being swapped for another (APP-127).
    function _keepRetiredThemes() {
        const s = _settingsObject();
        const next = Presets.adoptRetired(s.appearance);
        if (!next) return;
        s.appearance = next;
        AppController.appSettingsJson = JSON.stringify(s);
    }

    // Every attached ToolTip in the app is one shared instance. Dressed here
    // as the popup level of elevation (APP-182) — the control style drew a
    // square grey box in the system palette, unlike any menu or drop-down.
    property Item _tipSurface: PopupSurface {}
    property Item _tipText: Text {
        text: ToolTip.toolTip ? ToolTip.toolTip.text : ""
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.fsSm
        wrapMode: Text.Wrap
    }
    // An Item, since the window cannot take the ToolTip attached property.
    property Item _tipStyler: Item {
        Component.onCompleted: {
            const tt = ToolTip.toolTip;
            if (!tt) return;
            tt.background = win._tipSurface;
            tt.contentItem = win._tipText;
            tt.padding = Theme.spMd;
        }
    }

    Component.onCompleted: {
        AppController.setWindowFrameDark(win, win._frameDark);
        _keepRetiredThemes();
        _restoreGeometry();
        if (win._startHidden && !win._minimizeToTray) win.showMinimized();
        _restoreFilters();
        _syncSelectionFilter();
        win.seedStarterDocs();
        if (typeof INITIAL_VIEW !== "undefined" && INITIAL_VIEW && INITIAL_VIEW.length > 0)
            AppController.currentView = INITIAL_VIEW;
        // First run: greet the user once the overlay is ready. Otherwise, on
        // the first launch of a week, what moved last week (WEAK PECAP).
        if (!AppController.welcomeSeen)
            Qt.callLater(welcome.open);
        else
            Qt.callLater(win._maybeShowRecap);
        // Coming from 0.7: say once what the new sidebar moved (APP-258).
        if (AppController.shellNotice.length > 0)
            Qt.callLater(win._showShellNotice);
    }
    function _showShellNotice() {
        const msg = AppController.shellNotice;
        if (msg.length === 0) return;
        AppController.ackShellNotice();
        toast.showWithAction(msg, I18n.t("shell.notice.action"), 15, function () {
            rail.openHotkeys(rail.hotkeysAnchor);
        });
    }

    // Close-to-tray: on platforms that have a tray icon (Windows/macOS via the
    // notification tray fallback), the window hides instead of quitting so the
    // global capture hotkeys can summon it back. The tray menu's "Quit" calls
    // QCoreApplication::quit() directly, so a real exit bypasses this. On Linux
    // there is no tray icon, so closing quits as usual.
    readonly property bool _minimizeToTray: Qt.platform.os === "windows" || Qt.platform.os === "osx"
    // Whether the X button hides to the tray: settings.system.closeToTray.
    // Unset until the first close asks, because doing it silently left people
    // thinking heap had quit while it kept running.
    function _closeToTrayPref() {
        const sys = _settingsObject().system;
        return sys ? sys.closeToTray : undefined;
    }
    function _setCloseToTray(v) {
        const s = _settingsObject();
        s.system = Object.assign({}, s.system || ({}), { closeToTray: v });
        AppController.appSettingsJson = JSON.stringify(s);
    }
    onClosing: (close) => {
        // Hiding to the tray keeps the editor as it is; a quit asks about what
        // is typed in it first, then closes again (SHELL-29).
        const quits = !win._minimizeToTray || win._closeToTrayPref() === false;
        if (quits && taskEditor.isDirty()) {
            close.accepted = false;
            taskEditor.settleThen(() => win.close());
            return;
        }
        if (!win._minimizeToTray) return;
        const pref = win._closeToTrayPref();
        if (pref === false) return;   // a real quit
        close.accepted = false;
        if (pref === undefined) {
            closeAsk.open();
            return;
        }
        win.hide();
    }

    QQC.Dialog {
        id: closeAsk
        objectName: "close-to-tray-ask"
        modal: true
        Overlay.modal: ModalScrim {}
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 440
        padding: Theme.inset
        topPadding: Theme.spMd
        title: I18n.t("close.ask.title")
        background: ModalSurface {}
        // Drawn in the theme like every other dialog title; Basic's own
        // header was an unstyled bar in the palette's window colour.
        header: Text {
            text: closeAsk.title
            color: Theme.text
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
            leftPadding: Theme.inset; rightPadding: Theme.inset; topPadding: Theme.inset
            wrapMode: Text.Wrap
        }
        contentItem: Text {
            text: I18n.t("close.ask.body")
            color: Theme.textMuted
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
        // Inset from the dialog's edge; the buttons sat flush on the bottom.
        footer: Item {
            implicitHeight: closeAskRow.implicitHeight + Theme.inset
            RowLayout {
            id: closeAskRow
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: Theme.inset; anchors.rightMargin: Theme.inset
            spacing: Theme.spMd
            Item { Layout.fillWidth: true }
            PillButton {
                objectName: "close-ask-quit"
                text: I18n.t("close.ask.quit")
                onClicked: {
                    win._setCloseToTray(false);
                    closeAsk.close();
                    taskEditor.settleThen(() => {
                        AppController.flushSave();
                        Qt.quit();
                    });
                }
            }
            PillButton {
                objectName: "close-ask-tray"
                text: I18n.t("close.ask.tray")
                primary: true
                onClicked: {
                    win._setCloseToTray(true);
                    closeAsk.close();
                    win.hide();
                }
            }
            }
        }
    }

    // Open a side-rail popover next to its button — or close it if that same
    // button (or its shortcut) fired while the panel is already up.
    //
    // The popup is re-parented to the anchor so CloseOnPressOutsideParent means
    // "pressed outside the panel and outside the button that owns it": a press
    // anywhere else in the app dismisses it, while a press on the button itself
    // is left to the click handler below, which toggles. Positions are therefore
    // anchor-relative, but still clamped in window space so a rail button near
    // the bottom edge doesn't push the panel off-screen.
    // Everything that floats at the bottom centre — the selection bar, the
    // "continue tour" pill and the toast — used to be pinned to the same spot
    // and simply drew on top of each other (deleting a multi-selection put the
    // undo toast right over the selection bar). They stack instead.
    readonly property int _selectionBarSpace: AppController.selectionCount > 0 ? 68 : 0
    readonly property int _resumePillSpace: welcome.paused ? 52 : 0

    // True while anything modal-ish is up. A single-letter shortcut has to
    // stand down then: Qt only protects a focused text field, so a picker's
    // type-ahead or a read-only Text would otherwise swallow the keystroke or
    // let the shortcut fire over the dialog (HEAP-117).
    readonly property bool _overlayOpen: taskEditor.opened || eventEditor.opened
        || personEditor.opened || personPicker.opened || profileEditor.opened || welcome.opened
        || cmdPalette.opened || quickCapture.opened || quickCaptureNotes.opened
        || tweaks.opened || hotkeys.opened || closeAsk.opened || goToDatePopup.opened
        || weeklyRecap.opened || standupDraft.opened || timeMachine.opened || eventLog.opened || endOfDay.opened

    // ── Keyboard scope ────────────────────────────────────────────────
    // Board and calendar keys (Return, Esc, the arrows, bare letters) are
    // application shortcuts, so Qt offered them before the focused item —
    // Return in the header search opened the card under the cursor, Down in a
    // card's context menu moved the board cursor, Enter in "New column"
    // opened the task editor. They belong to whatever holds focus unless that
    // is the view itself.
    //
    // Focus in something that takes typed text: a search box, an inline
    // rename, a breadcrumb being edited.
    readonly property bool _typing: {
        const f = win.activeFocusItem;
        return !!f && typeof f.cursorPosition === "number" && f.readOnly !== true;
    }
    // Focus inside a popup, menu or dialog — including the ones a view owns
    // (add column, WIP limit, delete confirm, a card's context menu), which
    // Main has no id for. Every popup's item lives under the window overlay.
    readonly property bool _focusInPopup: {
        for (let p = win.activeFocusItem; p; p = p.parent)
            if (p === Overlay.overlay) return true;
        return false;
    }
    // Where the keyboard goes back to when a popup closes (design audit
    // DES-1). Qt hands focus to whatever focus scope is left in the window —
    // a bare ColumnLayout after Esc in the task editor — so J/K, Return and
    // the view's other keys were dead until the next click. The last item
    // that held focus outside every popup is kept here and gets it back; if
    // it is gone (a card rebuilt by the save, a view switched away), the view
    // does. A popup that hands focus on by itself (the palette opening an
    // editor, a click on a field) is left alone: this only steps in while
    // focus still sits where Qt dropped it.
    property Item _focusHome: null
    property bool _focusWasInPopup: false
    onActiveFocusItemChanged: {
        const it = win.activeFocusItem;
        if (!it) return;
        if (win._focusInPopup) {
            win._focusWasInPopup = true;
            return;
        }
        if (win._focusWasInPopup) {
            win._focusWasInPopup = false;
            if (it !== win._focusHome) {
                const landed = it;
                Qt.callLater(function () {
                    if (win.activeFocusItem === landed && !win._focusInPopup) win.returnFocusHome();
                });
            }
            return;
        }
        win._focusHome = it;
    }
    function returnFocusHome() {
        const h = win._focusHome;
        // An empty header search is not where anyone was working: it only
        // held focus because the button that opened the dialog takes none.
        // Sending focus back there put the caret and the query-syntax hint
        // over the view after every dialog, and the next click only cleared
        // it (PERO-1). The view gets it instead.
        const idleSearch = h && h.objectName === "topbar-search" && (h.text || "").length === 0;
        if (h && !idleSearch && h.visible && h.enabled && h.Window.window === win) h.forceActiveFocus();
        else win.focusActiveView();
    }
    // A view switch takes the keyboard into the new view: it used to stay on
    // the hidden board, so after Ctrl+7 nothing typed reached the note and Tab
    // walked the top bar (PERA-5). A popup that still holds focus hands it on
    // when it closes (above), and the header search keeps a query being typed.
    function _focusSwitchedView() {
        if (win._focusInPopup) return;
        const f = win.activeFocusItem;
        if (f && f.visible && win._typing && !win._insideView(f)) return;
        // Already in the new view (something put it there first).
        const v = win.activeViewItem();
        for (let p = f; p && v; p = p.parent)
            if (p === v) return;
        win.focusActiveView();
    }
    // Whether `it` sits in one of the four view loaders (any view, shown or not).
    function _insideView(it) {
        for (let p = it; p; p = p.parent)
            if (p === boardLoader || p === notesLoader || p === docsLoader || p === viewLoader) return true;
        return false;
    }
    // A modal (or dimming) popup is up somewhere — even one that did not take
    // focus, as most of the views' own confirm dialogs do not. Each puts its
    // dimmer on the overlay next to the popup items, so a visible overlay child
    // that is not a popup item is one.
    readonly property bool _dimmerShown: {
        const ov = Overlay.overlay;
        if (!ov) return false;
        const kids = ov.children;
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i];
            if (k.visible && k.opacity > 0 && String(k).indexOf("QQuickPopupItem") !== 0) return true;
        }
        return false;
    }
    // …and that popup is one of the two side-rail popovers, which leave the
    // app usable behind them.
    readonly property bool _focusInPopover: {
        for (let p = win.activeFocusItem; p; p = p.parent)
            if (p === tweaks.contentItem || p === hotkeys.contentItem) return true;
        return false;
    }
    // Focus on a control outside the view that was reached with Tab — a
    // filter chip, the mini week, the day panel, the people list. Its arrows
    // and Enter are its own; the board's cursor keys wait until focus goes
    // back to the view.
    readonly property bool _focusOnControl: {
        const f = win.activeFocusItem;
        if (!f) return false;
        const v = win.activeViewItem();
        for (let p = f; p; p = p.parent) {
            if (p === v) return false;
            // A view's own keyboard surface (the month grid) is the view:
            // it claims the keys it uses itself and leaves the rest.
            if (p.activeFocusOnTab === true) return p.viewSurface !== true;
        }
        return false;
    }
    // A view-local key (board cursor, calendar paging, Esc on the selection,
    // Delete, the bare-letter shortcuts) stands down while any of this holds.
    readonly property bool _viewKeysBlocked: hotkeys.isCapturing || _overlayOpen || _typing || _focusInPopup || _dimmerShown
                                             || _focusOnControl
    // Global shortcuts (switch view, new task, palette, undo…) stand down
    // behind a modal: Ctrl+3 used to switch the view under an open task
    // editor, Ctrl+K opened the palette over the welcome tour. The side-rail
    // popovers are not modal and keep them.
    readonly property bool _modalOpen: taskEditor.opened || eventEditor.opened
        || personEditor.opened || personPicker.opened || profileEditor.opened || welcome.opened
        || cmdPalette.opened || quickCapture.opened || quickCaptureNotes.opened
        || closeAsk.opened || goToDatePopup.opened || eventLog.opened
        || (_focusInPopup && !_focusInPopover) || _dimmerShown
    readonly property bool _globalKeysOn: !hotkeys.isCapturing && !_modalOpen

    // Esc in the header search with nothing left to clear hands the keyboard
    // back to the view, so J/K and Return work again without the mouse.
    // A view that knows better where typing should go (the note editor, a
    // list's current row) says so with takeFocus().
    function focusActiveView() {
        const v = win.activeViewItem();
        if (v && typeof v.takeFocus === "function") v.takeFocus();
        else if (v) v.forceActiveFocus();
        else win.contentItem.forceActiveFocus();
    }

    function _placePopover(pop, anchor) {
        const p = anchor.mapToItem(win.contentItem, 0, 0);
        const wantY = Math.max(8, Math.min(p.y, win.contentItem.height - pop.height - 8));
        pop.x = anchor.width + 6;
        pop.y = wantY - p.y;
    }
    function _togglePopover(pop, anchor) {
        if (pop.opened) {
            pop.close();
            return;
        }
        pop.parent = anchor;
        win._placePopover(pop, anchor);
        pop.open();
        // The Hotkeys panel sizes itself from its list's contentHeight, which is
        // still 0 on the very first open — re-clamp once it has a real height so
        // a bottom-anchored rail button can't push it off the window.
        Qt.callLater(function () { win._placePopover(pop, anchor); });
    }

    function activeCount() {
        return win._activeCount;
    }
    function scheduleMap() {
        const out = {};
        const m = AppController.events;
        const sel = AppController.selectedDate;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            const date = m.data(idx, Qt.UserRole + 7);
            const taskId = m.data(idx, Qt.UserRole + 8);
            if (!taskId) continue;
            if (date && sel && date.getFullYear() === sel.getFullYear()
                    && date.getMonth() === sel.getMonth()
                    && date.getDate() === sel.getDate()) {
                out[taskId] = AppController.eventHourLabel(m.data(idx, Qt.UserRole + 4));
            }
        }
        return out;
    }
    property var _scheduleMap: scheduleMap()
    Connections {
        target: AppController.events
        function onRowsInserted() { win._scheduleMap = win.scheduleMap() }
        function onRowsRemoved()  { win._scheduleMap = win.scheduleMap() }
        function onDataChanged()  { win._scheduleMap = win.scheduleMap() }
        function onModelReset()   { win._scheduleMap = win.scheduleMap() }
    }
    // Bring the window to the foreground from any state (minimized, hidden to
    // tray, or merely unfocused). Shared by the two global-capture hotkeys and
    // the tray "Show" affordance.
    // Where a "seen this before" hint points (APP-159): the note, doc page or
    // task that already mentions the error, in its own profile.
    function openSeenBefore(hit) {
        if (!hit || !hit.id) return;
        if (hit.kind === "task") {
            // Edits to the task already open are not swapped out unasked, and
            // its profile is left only after that (PRES-1).
            taskEditor.settleThen(() => {
                if (hit.profileId && hit.profileId !== AppController.activeProfileId)
                    AppController.activeProfileId = hit.profileId;
                const t = AppController.taskById(hit.id);
                if (t && t.id) taskEditor.showFor(Object.assign({}, t));
            });
            return;
        }
        if (hit.profileId && hit.profileId !== AppController.activeProfileId)
            AppController.activeProfileId = hit.profileId;
        if (hit.kind === "note") {
            AppController.activeNoteId = hit.id;
            AppController.currentView = "notes";
        } else if (hit.kind === "docPage") {
            AppController.activeDocPageId = hit.id;
            AppController.currentView = "docs";
            docsBridge.requestedAnchor = "page:" + hit.id;
        }
    }

    // Focus mode (APP-160) on the task in front of the user: the one open in
    // the editor, else whatever AppController picks (selection, branch).
    function toggleImmersion() {
        AppController.toggleImmersion(taskEditor.opened ? taskEditor._originalId : "");
    }

    // The tasks a safety-net notice is about: one opens in the editor, several
    // narrow the board to them. Only what is shown changes.
    // A toast QML says itself; what went wrong or was refused also goes to
    // the event log (APP-187), as the C++ side's do.
    function notice(msg, kind) {
        toast.show(msg, kind);
        if (kind === "error" || kind === "warning") AppController.logEvent(kind, msg);
    }

    // "Show" on a sync's toast (APP-180): the board, filtered to the cards
    // that sync brought in.
    function showSyncNew() {
        AppController.currentView = "board";
        topBar.searchText = "is:new";
        win.searchText = topBar.searchText;
    }

    // An event-log entry was opened (APP-187): the task it names, the cards
    // of a sync, or the place it points at.
    function openLogEntry(entry) {
        const ids = (entry && entry.taskIds) || [];
        if (ids.length > 0) {
            const latest = AppController.syncNewTaskIds;
            if (entry.kind === "sync" && ids.length > 1 && ids.every(id => latest.indexOf(id) >= 0)) win.showSyncNew();
            else win.showSafetyTasks(ids);
            return;
        }
        if (entry && entry.route) win.runCommand(entry.route);
    }

    function showSafetyTasks(ids) {
        const list = (ids || []).filter(id => id && id.length > 0);
        if (list.length === 0) return;
        AppController.currentView = "board";
        if (list.length === 1) {
            const t = AppController.taskById(list[0]);
            if (t && t.id) taskEditor.showFor(Object.assign({}, t));
            return;
        }
        topBar.searchText = list.join(" OR ");
        win.searchText = topBar.searchText;
    }

    function _summon() {
        if (win._maximizeOnShow) {
            win._maximizeOnShow = false;
            win.showMaximized();
        }
        if (win.visibility === Window.Minimized || win.visibility === Window.Hidden || !win.visible)
            win.show();
        win.raise();
        win.requestActivate();
    }

    Connections {
        target: AppController
        function onSelectedDateChanged() { win._scheduleMap = win.scheduleMap() }
        // OS-level global hotkeys. With heap focused the popup opens in the
        // app as usual; from anywhere else only the capture window comes up —
        // the main window stays minimized, in the tray or behind other apps.
        function onQuickCaptureRequested() {
            if (win.active) quickCapture.open();
            else win._capture("task");
        }
        function onQuickCaptureNotesRequested() {
            if (win.active) quickCaptureNotes.open();
            else win._capture("note");
        }
        // Tray click / "Show heap." menu entry — just restore the window.
        function onShowWindowRequested() { win._summon(); }
        function onToast(msg, kind) { toast.show(msg, kind || "info") }
        // A sync brought new cards (APP-180): the toast names them, and
        // "Show" filters the board to them.
        function onSyncNews(msg, taskIds) {
            toast.showWithAction(msg, I18n.t("sync.show"), 10, function () { win.showSyncNew() });
        }
        // A safety-net notice (APP-157…): one toast, and "Show" takes the
        // board to the tasks it is about.
        function onSafetyNotice(kind, title, body, taskIds) {
            const msg = title.length > 0 ? title + " · " + body : body;
            // The end-of-day check opens the day's summary (APP-190).
            if (kind === "endOfDay")
                toast.showWithAction(msg, I18n.t("eod.open"), 15, function () { endOfDay.showNow() });
            else if (taskIds && taskIds.length > 0)
                toast.showWithAction(msg, I18n.t("safety.show"), 10, function () { win.showSafetyTasks(taskIds) });
            else
                toast.show(msg, "info");
        }
        // Focus mode ended: one toast with how much was held back, and a way
        // to see it. Nothing arrives unless asked for.
        function onImmersionEnded(held, minutes) {
            const msg = I18n.t("immersion.ended").arg(held);
            if (held > 0) {
                // A toast with an action is in the event log too (APP-225).
                AppController.logEvent("info", msg);
                toast.showWithAction(msg, I18n.t("immersion.showHeld"), 15, function () { AppController.releaseImmersionHeld() });
            } else {
                toast.show(msg, "info");
            }
        }
        function onSafetyOpenTasksRequested(taskIds) {
            win._summon();
            win.showSafetyTasks(taskIds);
        }
        // The third mouse use of an action that has a key: one quiet line,
        // never repeated for it (APP-166).
        function onShortcutHintRequested(shortcutId, sequence, label) {
            toast.show(I18n.t("hint.shortcut").arg(sequence).arg(label), "info")
        }
        // The tracker is read-only for this card (outside the filter, gone):
        // the drop was refused. Open the issue, or archive the card (APP-204).
        function onTrackerReadOnlyMove(taskId, msg, url) {
            toast.showWithActions(msg, [
                { label: I18n.t("tracker.readOnly.open"), fn: function () { if (url) Qt.openUrlExternally(url) } },
                { label: I18n.t("tracker.readOnly.archive"), fn: function () { AppController.setArchived(taskId, true) } }
            ], 10, "warning");
        }
        function onTrackerPushNeedsConfirm(taskId, key, title, tracker, remoteStatus, target) {
            trackerPushConfirm.ask(taskId, key, title, tracker, remoteStatus, target);
        }
        // Once, after the update that made tracker writes opt-in (APP-243).
        function onTrackerWriteNotice(msg) {
            toast.showWithAction(msg, I18n.t("tracker.writeNotice.open"), 20, function () {
                win.runCommand("settings:integrations")
            });
        }
        function onTrackerPushFailed(taskId, msg) {
            toast.showWithAction(msg, I18n.t("sync.retry"), 10, function () {
                AppController.retryTrackerPush(taskId)
            }, "error");
        }
        function onSettingsReset(msg) {
            toast.showWithAction(msg, I18n.t("undo.action"), 10, function () {
                AppController.undoSettingsReset()
            });
        }
        function onUndoableToast(msg, secs) {
            // Undo takes back the action this toast names — not whatever was
            // done last, which after a silent reorder is something else.
            const serial = AppController.undoSerialForToast();
            toast.showWithAction(msg, I18n.t("undo.action"), secs, function () {
                AppController.undoEntry(serial)
            });
        }
        // A newer release was found. When heap can update this copy itself
        // the action downloads it (APP-125); otherwise it opens the release page.
        function onUpdateAvailable(version, url) {
            if (AppController.updateCanInstall) {
                toast.showWithAction(I18n.t("update.available").arg(version), I18n.t("update.install"), 10, function () {
                    AppController.downloadUpdate()
                });
                return;
            }
            toast.showWithAction(I18n.t("update.available").arg(version), I18n.t("update.download"), 10, function () {
                Qt.openUrlExternally(url)
            });
        }
        // Downloaded and matched against the release's SHA-256: offer the restart.
        function onUpdateReadyToInstall(version, sha256) {
            toast.showWithAction(I18n.t("update.ready").arg(version), I18n.t("update.restart"), 30, function () {
                AppController.installUpdate()
            });
        }
    }

    GridLayout {
        anchors.fill: parent
        columns: 3
        rows: 1
        columnSpacing: 0
        rowSpacing: 0

        // The heap 2 sidebar (APP-258).
        Sidebar {
            id: rail
            Layout.row: 0; Layout.column: 0
            Layout.fillHeight: true
            expanded: win.sideRailExpanded
            onToggleRequested: win.toggleSideRail()
            onNewTaskRequested: taskEditor.showFor(AppController.newTaskDraft("todo"))
            onSyncStatusRequested: win.runCommand("settings:integrations")
            onNewProfileRequested: profileEditor.showCreate()
            onRenameProfileRequested: {
                const list = AppController.profiles;
                const id = AppController.activeProfileId;
                for (let i = 0; i < list.length; i++) if (list[i].id === id)
                    profileEditor.showRename(list[i].id, list[i].name, list[i].color);
            }
            onDuplicateProfileRequested: {
                const list = AppController.profiles;
                const id = AppController.activeProfileId;
                for (let i = 0; i < list.length; i++) if (list[i].id === id)
                    profileEditor.showDuplicate(list[i].id, list[i].name, list[i].color);
            }
            onExportJsonRequested: {
                exportJsonDialog.currentFile = "file:///" + (
                    (AppController.activeProfileId || "profile") + ".todocpp.json"
                );
                exportJsonDialog.open();
            }
            onImportJsonRequested: importJsonDialog.open()
            onImportIcsRequested: importIcsDialog.open()
            onImportVaultRequested: importVaultDialog.open()
            onExportVaultRequested: exportVaultDialog.open()
            onExportIcsRequested: {
                exportIcsDialog.currentFile = "file:///" + (
                    (AppController.activeProfileId || "lowkey") + ".ics"
                );
                exportIcsDialog.open();
            }

            onOpenTweaks:  (anchor) => win._togglePopover(tweaks, anchor)
            onOpenHotkeys: (anchor) => win._togglePopover(hotkeys, anchor)
            activeSavedViewId: savedViewsHost.activeView ? savedViewsHost.activeId : ""
            savedViewModified: savedViewsHost.modified
            onSavedViewActivated: (id) => savedViewsHost.apply(id)
            onSavedViewRenameRequested: (id) => savedViewsHost.openRename(id)
            onSavedViewUpdateRequested: (id) => savedViewsHost.updateFromCurrent(id)
            onSaveViewRequested: savedViewsHost.openSave()
        }

        // Main column: filter bar + active view
        Item {
            id: mainColumn
            objectName: "main-column"
            Layout.row: 0; Layout.column: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // state.json unreadable / from a newer heap / not saving.
                StorageBanner { Layout.fillWidth: true }

                // First-run demo banner: offer to clear the seeded sample data.
                Rectangle {
                    Layout.fillWidth: true
                    visible: AppController.demoActive
                    implicitHeight: visible ? 40 : 0
                    color: Theme.panel2
                    border.color: Theme.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.sp2xl
                        anchors.rightMargin: Theme.spLg
                        spacing: Theme.spLg
                        Text {
                            text: "✦  " + I18n.t("demo.banner.text")
                            color: Theme.text
                            font.pixelSize: Theme.fsMd
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        // Two-step: the first click arms, the second wipes.
                        // One stray click used to take every task with it.
                        PillButton {
                            id: startFreshBtn
                            objectName: "demo-start-fresh"
                            property bool armed: false
                            text: armed ? I18n.t("demo.banner.startFresh.confirm") : I18n.t("demo.banner.startFresh")
                            // Quiet until armed (APP-198): a banner is no
                            // dialog, and its offer was the brightest spot.
                            danger: armed
                            onClicked: {
                                if (!armed) {
                                    armed = true;
                                    startFreshDisarm.restart();
                                    return;
                                }
                                armed = false;
                                startFreshDisarm.stop();
                                AppController.startFresh();
                            }
                            Timer { id: startFreshDisarm; interval: 4000; onTriggered: startFreshBtn.armed = false }
                        }
                        PillButton {
                            text: I18n.t("demo.banner.keep")
                            onClicked: AppController.dismissDemo()
                        }
                    }
                }

            TopBar {
                id: topBar
                Layout.fillWidth: true
                // The tasks and knowledge sections; Today and Settings carry
                // their own titles.
                visible: section === "tasks" || section === "knowledge"
                section: AppController.currentSection
                view: AppController.currentView
                onLensSelected: (id) => win.openLens(id)
                searchText: win.searchText
                // Typing reaches the views once the keys pause, not per key: a
                // keystroke that swaps most rows on a 3k-task board rebinds every
                // visible card (~100 ms), and a quick "priority:p0" used to pay
                // that for each intermediate state, including "priority:p" — which
                // matches nothing. The field itself updates instantly.
                onSearchTextChanged: searchApply.restart()
                Timer {
                    id: searchApply
                    interval: 120
                    onTriggered: win.searchText = topBar.searchText
                }
                onLeaveRequested: win.focusActiveView()
                onSeenBeforeActivated: (hit) => win.openSeenBefore(hit)
            }

                FilterBar {
                    Layout.fillWidth: true
                    // Archive brings its own header and its own counter, and the
                    // fall-through label used to caption it "Docs".
                    visible: AppController.currentView !== "docs"
                          && AppController.currentView !== "today"
                          && AppController.currentView !== "notes"
                          && AppController.currentView !== "settings"
                          && AppController.currentView !== "archive"
                    viewLabel: AppController.currentView === "timeline" ? I18n.t("siderail.timeline")
                             : AppController.currentView === "week" ? I18n.t("siderail.week")
                             : AppController.currentView === "month" ? I18n.t("siderail.month")
                             : I18n.t("siderail.board")
                    priorities: win.prioritiesFilter
                    // Under the filters the bar itself shows (TASKS-20): the
                    // counts used to include archived tasks and ignore the
                    // search and the priority chips.
                    readonly property var _fc: AppController.filteredCounts(win.searchText, win._activePriorities,
                        win.showArchived, AppController.currentView === "timeline" && !win.showDoneTimeline, win._counts)
                    totalCount: _fc.total
                    activeCount: _fc.active
                    blockedCount: _fc.blocked
                    reviewCount: _fc.review
                    showArchived: win.showArchived
                    showSort: AppController.currentView === "board"
                    sortMode: win.boardSortMode
                    // The weekly recap from the board (APP-211).
                    showRecap: AppController.currentView === "board"
                    recapUnseen: weeklyRecap.unseen
                    onRecapRequested: win.runCommand("recap.open")
                    onSortModeRequested: (mode) => win.boardSortMode = mode
                    onTogglePriority: (p) => {
                        const next = Object.assign({}, win.prioritiesFilter);
                        next[p] = !next[p];
                        win.prioritiesFilter = next;
                    }
                    onClearPriorities: win.prioritiesFilter = ({})
                    onToggleArchived: win.showArchived = !win.showArchived
                    savedViewName: savedViewsHost.activeView ? savedViewsHost.activeView.name : ""
                    savedViewModified: savedViewsHost.modified
                    onSaveViewRequested: savedViewsHost.openSave()
                    onSaveAsNewRequested: savedViewsHost.openSave()
                    onUpdateViewRequested: savedViewsHost.updateActive()
                    onLeaveViewRequested: savedViewsHost.leave()
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // A view wider than its column is cut at the column, not
                    // drawn under the right panel (SCALE-3).
                    clip: true
                    // Board, Notes and Docs are kept alive once visited.
                    // Swapping a Loader's sourceComponent destroys the item,
                    // and these three hold state the user notices losing: the
                    // board's scroll position and column focus, the note's
                    // caret, scroll and editor undo history, the docs
                    // section the user had scrolled to. Everything else is
                    // cheap to rebuild and stays on the shared loader below.
                    //
                    // They load lazily — `active` is flipped on first visit —
                    // so starting on the board does not build the notes
                    // editor and the docs catalogue too.
                    Loader {
                        id: boardLoader
                        anchors.fill: parent
                        visible: AppController.currentView === "board"
                        active: false
                        sourceComponent: boardComp
                    }
                    Loader {
                        id: notesLoader
                        anchors.fill: parent
                        visible: AppController.currentView === "notes"
                        active: false
                        sourceComponent: notesComp
                    }
                    Loader {
                        id: docsLoader
                        anchors.fill: parent
                        visible: AppController.currentView === "docs"
                        active: false
                        sourceComponent: docsComp
                    }

                    Loader {
                        id: viewLoader
                        anchors.fill: parent
                        visible: !boardLoader.visible && !notesLoader.visible && !docsLoader.visible
                        sourceComponent: {
                            if (AppController.currentView === "today") return todayComp;
                            if (AppController.currentView === "timeline") return timelineComp;
                            if (AppController.currentView === "week") return weekComp;
                            if (AppController.currentView === "month") return monthComp;
                            if (AppController.currentView === "archive") return archiveComp;
                            if (AppController.currentView === "settings") return settingsComp;
                            return null;
                        }
                    }

                    // Today's day hands its clicks up here, where the editors are.
                    Connections {
                        target: viewLoader.item as TodayView
                        ignoreUnknownSignals: true
                        function onEventClicked(id, occurrence) { win.openEvent(id, occurrence); }
                        function onCreateRequested(startHour, endHour, day) { win.createEventAt(startHour, endHour, day); }
                        function onTaskClicked(id) { win.openTask(id); }
                    }

                    // First visit to one of the kept-alive views builds it.
                    // The function lives on `win` because a Connections handler
                    // does not resolve names from the scope its parent item
                    // declares them in — calling it unqualified from there is a
                    // ReferenceError, and the two views would never activate.
                    Connections {
                        target: AppController
                        function onCurrentViewChanged() {
                            win.activateCurrentView();
                            Qt.callLater(win._focusSwitchedView);
                        }
                    }
                    Component.onCompleted: win.activateCurrentView()
                    SelectionBar {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Theme.sp2xl
                        z: 50
                    }
                }
                Component {
                    id: boardComp
                    KanbanBoard {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        scheduleMap: win._scheduleMap
                        showArchived: win.showArchived
                        sortMode: win.boardSortMode
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                        onCreateInStatus: (s) => taskEditor.showFor(AppController.newTaskDraft(s))
                    }
                }
                Component {
                    id: todayComp
                    TodayView {}
                }
                Component {
                    id: timelineComp
                    TimelineView {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        scheduleMap: win._scheduleMap
                        showDone: win.showDoneTimeline
                        showArchived: win.showArchived
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                        onToggleShowDone: win.showDoneTimeline = !win.showDoneTimeline
                    }
                }
                Component {
                    id: weekComp
                    WeekView {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        showArchived: win.showArchived
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                        onEventClicked: (id, occurrence) => occurrence ? eventEditor.showForOccurrence(occurrence) : eventEditor.showForId(id)
                        // A click on an empty slot opens the editor on a draft
                        // rather than saving an untitled event: the user names
                        // it before it exists.
                        onCreateRequested: (hour, day) => {
                            const draft = AppController.newEventDraft(hour, day);
                            eventEditor.showForDraft(draft);
                        }
                    }
                }
                Component {
                    id: monthComp
                    MonthView {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        showArchived: win.showArchived
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                        onEventClicked: (id, occurrence) => occurrence ? eventEditor.showForOccurrence(occurrence) : eventEditor.showForId(id)
                    }
                }
                Component {
                    id: archiveComp
                    ArchiveView {
                        searchText: win.searchText
                        prioritiesFilter: win.prioritiesFilter
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                    }
                }
                Component {
                    id: docsComp
                    DocsView {
                        id: docsView
                        onLinkRequested: (kind, target) => win.followMdLink(kind, target)
                        Connections {
                            target: docsBridge
                            function onRequestedAnchorChanged() {
                                if (docsBridge.requestedAnchor.length > 0) {
                                    Qt.callLater(function () {
                                        docsView.scrollToAnchor(docsBridge.requestedAnchor);
                                        docsBridge.requestedAnchor = "";
                                    });
                                }
                            }
                        }
                    }
                }
                Component {
                    id: notesComp
                    NotesView {
                        // A palette hit in a note asks for the line its
                        // section starts on; clearing it afterwards lets the
                        // same line be requested twice.
                        jumpToLine: notesBridge.requestedLine
                        onJumpConsumed: notesBridge.requestedLine = -1
                        onTaskRequested: (id) => win.openTaskById(id)
                        onPersonRequested: (id) => personEditor.showFor(AppController.personById(id))
                    }
                }
                Component {
                    id: settingsComp
                    SettingsView {
                        // Expose a "bus" the inner buttons can hit to open
                        // popups owned by Main (HotkeysPanel + FileDialog).
                        property var settingsBus: QtObject {
                            function openHotkeys() { rail.openHotkeys(rail.hotkeysAnchor) }
                            function exportJson()  { exportJsonDialog.open() }
                            function importJson()  { importJsonDialog.open() }
                            function openTimeMachine() { timeMachine.showNow() }
                        }
                    }
                }
            }
        }

        // Right column
        Rectangle {
            objectName: "right-panel"
            visible: win.rightPanelShown
            Layout.row: 0; Layout.column: 2
            Layout.preferredWidth: win.rightPanelWidth
            Layout.minimumWidth: win.rightPanelMinWidth
            Layout.maximumWidth: win.rightPanelMaxWidth
            Layout.fillHeight: true
            color: Theme.panel
            Rectangle {
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: 1
                color: rightResize.pressed ? Theme.accent
                     : rightResize.containsMouse ? Theme.borderStrong : Theme.border
            }
            // Drag handle on the left edge. Width follows the pointer live;
            // settings are written once, on release.
            MouseArea {
                id: rightResize
                objectName: "right-panel-resize"
                anchors.left: parent.left; anchors.leftMargin: -3
                anchors.top: parent.top; anchors.bottom: parent.bottom
                width: 7
                z: 10
                hoverEnabled: true
                cursorShape: Qt.SplitHCursor
                property real _startX: 0
                property int _startW: 0
                onPressed: (m) => {
                    _startX = mapToGlobal(m.x, 0).x;
                    _startW = win.rightPanelWidth;
                }
                onPositionChanged: (m) => {
                    if (pressed) win.setRightPanelWidth(_startW - (mapToGlobal(m.x, 0).x - _startX), false);
                }
                onReleased: win.setRightPanelWidth(win.rightPanelWidth, true)
                onDoubleClicked: win.setRightPanelWidth(win.rightPanelDefaultWidth, true)
                ToolTip.visible: containsMouse && !pressed
                ToolTip.delay: 800
                ToolTip.text: I18n.t("rightpanel.resizeTip")
                Rectangle {
                    anchors.centerIn: parent
                    width: 2; height: 32; radius: 1
                    color: Theme.text
                    opacity: rightResize.containsMouse || rightResize.pressed ? 0.5 : 0
                }
            }
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                MiniWeek { Layout.fillWidth: true }
                SplitView {
                    id: rightSplit
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    orientation: Qt.Vertical
                    // Remember where the calendar / people split was left.
                    onResizingChanged: if (!resizing) {
                        const s = win._settingsObject();
                        s.peopleListHeight = Math.round(peopleList.height);
                        AppController.appSettingsJson = JSON.stringify(s);
                    }

                    handle: Rectangle {
                        implicitHeight: 6
                        color: SplitHandle.pressed ? Theme.accent
                             : SplitHandle.hovered ? Theme.borderStrong
                             : Theme.border
                        Rectangle {
                            anchors.centerIn: parent
                            width: 32; height: 2; radius: 1
                            color: SplitHandle.hovered ? Theme.text : Theme.textDim
                            opacity: 0.6
                        }
                    }

                    DayCalendar {
                        SplitView.fillHeight: true
                        SplitView.minimumHeight: 120
                        onEventClicked: (id, occurrence) => occurrence ? eventEditor.showForOccurrence(occurrence) : eventEditor.showForId(id)
                        // A click or a drag on an empty slot opens the editor,
                        // the same as the week grid.
                        onCreateRequested: (startHour, endHour, day) => {
                            const draft = AppController.newEventDraft(startHour, day);
                            draft.end = endHour;
                            eventEditor.showForDraft(draft);
                        }
                        onTaskClicked: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
                    }
                    PeopleList {
                        id: peopleList
                        SplitView.preferredHeight: {
                            const h = Number(win._settingsObject().peopleListHeight);
                            return isFinite(h) && h >= 64 ? h : 220;
                        }
                        SplitView.minimumHeight: 64
                        onPersonRequested: (id) => personEditor.showFor(AppController.personById(id))
                        onPickPersonRequested: personPicker.open_()
                    }
                }
            }
        }
    }

    TaskEditor    {
        id: taskEditor
        objectName: "task-editor"
        onSeenBeforeActivated: (hit) => win.openSeenBefore(hit)
    }
    EventEditor   { id: eventEditor }
    PersonEditor  { id: personEditor }
    PersonPicker  {
        id: personPicker
        onDraftRequested: (draft) => personEditor.showFor(draft)
    }
    ProfileEditor { id: profileEditor }
    WelcomePopup {
        id: welcome
        // Per-step "open →" actions route here so the tour stays decoupled from
        // the popups/editors Main owns. Each _doAction() has paused the tour,
        // so the target surface is visible when we open it.
        onOpenAction: (id) => {
            if (id === "task-new")            taskEditor.showFor(AppController.newTaskDraft("todo"));
            else if (id === "quick-capture")  quickCapture.open();
            else if (id === "palette")        cmdPalette.open();
            else if (id === "hotkeys")        rail.openHotkeys(rail.hotkeysAnchor);
            // "Bring your stuff" (APP-169): the same pickers as the palette's.
            else if (id === "vault-import")   importVaultDialog.open();
            else if (id === "profile-import") importJsonDialog.open();
            else if (id === "integrations")   win.runCommand("settings:integrations");
        }
        // "Learn more →" — jump to Settings and scroll the Help doc to the anchor.
        onOpenHelp: (anchor) => {
            AppController.currentView = "settings";
            Qt.callLater(() => {
                const v = win.activeViewItem();
                if (v && v.openHelp)
                    v.openHelp(anchor);
            });
        }
    }

    // After a "delete all data" reset the controller rebuilds a fresh install;
    // jump back to the board and re-greet the user, mirroring true first-run.
    Connections {
        target: AppController
        function onFirstRunReset() {
            AppController.currentView = "board";
            welcome.step = 0;
            Qt.callLater(welcome.open);
        }
        // Settings → Help "Replay" re-opens the guide from the top without
        // touching any persisted onboarding flags.
        function onWelcomeReplayRequested() {
            welcome.step = 0;
            Qt.callLater(welcome.open);
        }
    }

    // Floating "continue tour" affordance, shown only while the welcome guide is
    // paused — i.e. the user tapped a step's "open →" / "Learn more →" and jumped
    // to a surface. Clicking the pill brings the tour back at the same step; the
    // ✕ gives up on it (marks it seen). This is what keeps an action from closing
    // the guide irreversibly.
    Rectangle {
        id: resumeGuidePill
        visible: welcome.paused
        enabled: visible
        z: 9000
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 + win._selectionBarSpace
        radius: 20
        height: 40
        width: pillRow.implicitWidth + 28
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1

        // Click anywhere on the pill → resume the tour.
        ClickArea {
            objectName: "resume-guide"
            label: I18n.t("welcome.resume")
            showTip: false
            onActivated: welcome.open()
        }
        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: Theme.spXl
            Text {
                text: I18n.t("welcome.resume")
                color: Theme.text
                font.pixelSize: Theme.fsMd
                font.weight: Theme.fwTitle
            }
            Rectangle { width: 1; height: 18; color: Theme.border }
            // Give up on the tour. Nested (declared last) so it wins the click
            // over the pill; sized to 22px because the glyph's own bounds were a
            // ~10px target sitting right next to a much larger "resume" action.
            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: Theme.radiusSm
                color: giveUpMA.hovered ? Theme.panel3 : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: giveUpMA.hovered ? Theme.text : Theme.textMuted
                    font.pixelSize: Theme.fsMd
                }
                ClickArea {
                    id: giveUpMA
                    objectName: "resume-guide-give-up"
                    label: I18n.t("welcome.giveUp")
                    onActivated: welcome._finish()
                }
            }
        }
    }
    QuickCapturePopup {
        id: quickCapture
        onCaptured: (title, body, taskId) => toast.show(title + " — " + body.replace(/\n/g, " · "))
        onSeenBeforeActivated: (hit) => {
            quickCapture.close();
            win.openSeenBefore(hit);
        }
    }
    QuickCaptureNotesPopup {
        id: quickCaptureNotes
        onCaptured: (title, body, taskId) => toast.show(title + " — " + body)
    }

    // The same two popups, for a capture made from outside heap. Created on
    // first use: most sessions never need a second window.
    function _capture(mode) {
        captureLoader.active = true;
        const cw = captureLoader.item as CaptureWindow;
        cw.hostScreen = win.screen;
        cw.summon(mode);
    }
    Loader {
        id: captureLoader
        active: false
        sourceComponent: CaptureWindow {
            // Nothing of heap is on screen to show it, so the confirmation is
            // an OS notification; clicking it opens the task.
            onCaptured: (title, body, taskId) => AppController.notifyCapture(taskId, title, body)
        }
    }
    // Outside the component, so `win` is in scope for qmllint (APP-159).
    Connections {
        target: captureLoader.item
        ignoreUnknownSignals: true
        function onSeenBeforeActivated(hit) {
            win._summon();
            win.openSeenBefore(hit);
        }
        // The zoom keys stand down while it has the keyboard (APP-168).
        // Window.active cannot tell: the capture window is this one's
        // transient child, and an active child counts as this one active.
        // Hiding it does not always say it went inactive, hence both.
        function onActiveChanged() {
            const cw = captureLoader.item as CaptureWindow;
            win._captureActive = !!cw && cw.visible && cw.active;
        }
        function onVisibleChanged() {
            const cw = captureLoader.item as CaptureWindow;
            win._captureActive = !!cw && cw.visible && cw.active;
        }
    }

    // GitWatcher → TaskEditor bridge: TopBar "Open" button on the focus
    // banner emits openTaskRequested; route it through the same showFor()
    // path used by Kanban / Timeline / palette.
    Connections {
        target: AppController
        function onOpenTaskRequested(taskId, profileId) {
            // Also reached from a notification click while heap is in the tray.
            win._summon();
            // Edits to the task already open are not swapped out unasked
            // (TASKS-18), and the task's profile becomes the active one only
            // after that: switched first, the open editor saved into the
            // other profile (PRES-1).
            taskEditor.settleThen(() => {
                if (profileId && profileId !== AppController.activeProfileId)
                    AppController.activeProfileId = profileId;
                taskEditor.showFor(Object.assign({}, AppController.taskById(taskId)));
            });
        }
        // "Open" on a meeting / standup reminder (APP-155): that day in the
        // week view, and the meeting itself when it is a stored event.
        function onOpenEventRequested(eventId, date) {
            win._summon();
            AppController.selectedDate = date;
            AppController.currentView = "week";
            if (eventId) eventEditor.showForId(eventId);
        }
    }

    // What a palette command does. Ids are the shortcut catalog's, so the
    // palette offers exactly what the keys do; "settings:<section>" opens a
    // Settings section, and a few have no key of their own.
    // Settings, opened on one setting: scrolled to and focused (APP-210).
    function openSettingsItem(item) {
        AppController.currentView = "settings";
        Qt.callLater(function () {
            const v = win.activeViewItem();
            if (v && v.revealItem) v.revealItem(item);
        });
    }
    // The day's hands, for Today and the day panel.
    function openEvent(id, occurrence) {
        if (occurrence) eventEditor.showForOccurrence(occurrence);
        else eventEditor.showForId(id);
    }
    function createEventAt(startHour, endHour, day) {
        const draft = AppController.newEventDraft(startHour, day);
        draft.end = endHour;
        eventEditor.showForDraft(draft);
    }
    function openTask(id) {
        taskEditor.showFor(Object.assign({}, AppController.taskById(id)));
    }
    // The calendar lens opens on the calendar last used (week or month).
    property string _calendarView: "week"
    Connections {
        target: AppController
        function onCurrentViewChanged() {
            const v = AppController.currentView;
            if (v === "week" || v === "month") win._calendarView = v;
        }
    }
    function openLens(id) {
        if (id === "list") AppController.currentView = "timeline";
        else if (id === "calendar") AppController.currentView = win._calendarView;
        else AppController.currentView = id;
    }
    function runCommand(id) {
        if (id.indexOf("section.") === 0) {
            AppController.openSection(id.slice(8));
            return;
        }
        if (id.indexOf("settings:") === 0) {
            const section = id.slice(9);
            AppController.currentView = "settings";
            Qt.callLater(function () {
                const v = win.activeViewItem();
                if (v && v.openSection) v.openSection(section);
            });
            return;
        }
        if (id.indexOf("view.") === 0) {
            AppController.currentView = id.slice(5);
            return;
        }
        if (id.indexOf("savedview:") === 0) {
            savedViewsHost.apply(id.slice(10));
            return;
        }
        if (id.indexOf("savedView.") === 0) {
            savedViewsHost.applyAt(Number(id.slice(10)));
            return;
        }
        // Notes actions run in the Notes view, so go there first (SHELL-1).
        if (id.indexOf("notes.") === 0) {
            AppController.currentView = "notes";
            Qt.callLater(function () {
                const v = win.activeViewItem();
                if (v && v.runNotesCommand) v.runNotesCommand(id.slice(6));
            });
            return;
        }
        if (id === "savedview.save") {
            // After the palette has closed, so the dialog gets the keyboard.
            Qt.callLater(savedViewsHost.openSave);
            return;
        }
        switch (id) {
        case "task.new":             taskEditor.showFor(AppController.newTaskDraft("todo")); break;
        case "quick-capture":        quickCapture.open(); break;
        case "quick-capture-notes":  quickCaptureNotes.open(); break;
        case "panel.right":          win.toggleRightPanel(); break;
        case "rail.toggle":          win.toggleSideRail(); break;
        case "theme.toggle":         AppController.theme = (AppController.theme === "dark" ? "light" : "dark"); break;
        case "person.new":           personPicker.open_(); break;
        case "profile.new":          profileEditor.showCreate(); break;
        case "profile.next":         win._cycleProfile(1); break;
        case "profile.prev":         win._cycleProfile(-1); break;
        case "profile.exportMd":     AppController.copyActiveProfileMarkdownToClipboard(); break;
        case "profile.weeklyReport": AppController.copyWeeklyReportToClipboard(); break;
        case "tweaks.open":          rail.openTweaks(rail.tweaksAnchor); break;
        case "hotkeys.open":         rail.openHotkeys(rail.hotkeysAnchor); break;
        case "search.focus":         win._focusSearch(); break;
        case "event.new":            eventEditor.showForDraft(AppController.newEventDraft(9, AppController.selectedDate)); break;
        case "welcome.replay":       AppController.replayWelcome(); break;
        case "recap.open":           weeklyRecap.showNow(); break;
        case "focus.immersion":      win.toggleImmersion(); break;
        case "standup.draft":        standupDraft.showNow(); break;
        case "timeMachine.open":     timeMachine.showNow(); break;
        case "log.open":             eventLog.showNow(); break;
        case "endOfDay.open":        endOfDay.showNow(); break;
        case "zoom.in":              win.zoomInterface(1); break;
        case "zoom.out":             win.zoomInterface(-1); break;
        case "zoom.reset":           win.zoomInterface(0); break;
        default:                     console.warn("palette: no command", id);
        }
    }

    function _cycleProfile(step) {
        const list = AppController.profiles;
        if (list.length === 0) return;
        let idx = -1;
        for (let i = 0; i < list.length; i++) if (list[i].id === AppController.activeProfileId) idx = i;
        const base = idx >= 0 ? idx : 0;
        AppController.activeProfileId = list[(base + step + list.length) % list.length].id;
    }

    // The top bar's box searches tasks. In a view that has a search of its
    // own — Docs, and Notes once it grows one — Ctrl+F used to focus that
    // task box anyway, where typing did nothing to what was on screen.
    // Duck-typed so a view picks this up by declaring focusSearch().
    function _focusSearch() {
        const view = win.activeViewItem();
        if (view && typeof view.focusSearch === "function") {
            view.focusSearch();
            return;
        }
        // Notes has no box of its own; the palette searches every note's
        // text, which is what Ctrl+F in a note is reaching for.
        if (AppController.currentView === "notes") {
            cmdPalette.open();
            return;
        }
        topBar.focusSearch();
    }

    // Saved views: the active one, applying one, Alt+1…9, the name dialog.
    SavedViewsHost {
        id: savedViewsHost
        objectName: "saved-views-host"
        host: win
        onActiveIdChanged: win._saveFiltersSoon()
    }

    CommandPalette {
        id: cmdPalette
        onCommandRequested: (id) => win.runCommand(id)
        onOpenTask: (taskId) => taskEditor.showFor(Object.assign({}, AppController.taskById(taskId)))
        onOpenPerson: (personId) => personEditor.showFor(AppController.personById(personId))
        onNavigateToDoc: (sectionId) => docsBridge.requestedAnchor = "sec-" + sectionId
        onNavigateToSnippets: docsBridge.requestedAnchor = "sec-snippets"
        onNavigateToContacts: docsBridge.requestedAnchor = "sec-contacts"
        onNavigateToNoteLine: (line) => notesBridge.requestedLine = line
        onNavigateToDocPage: (pageId) => docsBridge.requestedAnchor = "page:" + pageId
    }

    // Anchor bridge — DocsView listens for changes and scrolls to the
    // anchorId set here (set, then cleared after one tick).
    QtObject {
        id: docsBridge
        property string requestedAnchor: ""
    }

    // The same idea for notes: a search hit sets the line it wants, NotesView
    // watches and puts the caret there.
    QtObject {
        id: notesBridge
        property int requestedLine: -1
    }

    // ── Rebindable application shortcuts ──────────────────────────────
    // Each Shortcut's sequence is bound through _kbd(id), which depends on
    // AppController.shortcuts (a Q_PROPERTY) so the binding re-evaluates on
    // shortcutsChanged — rebinding in the Hotkeys panel applies instantly.
    function _kbd(id) {
        const list = AppController.shortcuts;
        for (let i = 0; i < list.length; i++)
            if (list[i].id === id) return list[i].sequence;
        return "";
    }

    Shortcut {
        sequence: _kbd("palette.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: cmdPalette.open()
    }
    // Built-in alias: Ctrl+P always opens the palette, independent of the
    // catalog. If the user rebinds palette.open elsewhere, this still works.
    Shortcut {
        sequence: "Ctrl+P"
        context: Qt.ApplicationShortcut
        enabled: win._globalKeysOn
        onActivated: cmdPalette.open()
    }

    Shortcut {
        sequence: _kbd("panel.right")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: win.toggleRightPanel()
    }
    Shortcut {
        sequence: _kbd("rail.toggle")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: win.toggleSideRail()
    }
    Shortcut {
        sequence: _kbd("task.new")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: taskEditor.showFor(AppController.newTaskDraft("todo"))
    }
    Shortcut {
        sequence: _kbd("quick-capture")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: quickCapture.open()
    }
    Shortcut {
        sequence: _kbd("quick-capture-notes")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: quickCaptureNotes.open()
    }
    Shortcut {
        sequence: win._kbd("section.today")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.openSection("today")
    }
    Shortcut {
        sequence: win._kbd("section.tasks")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.openSection("tasks")
    }
    Shortcut {
        sequence: win._kbd("section.knowledge")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.openSection("knowledge")
    }
    Shortcut {
        sequence: _kbd("view.board")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.currentView = "board"
    }
    Shortcut {
        sequence: _kbd("view.timeline")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.currentView = "timeline"
    }
    Shortcut {
        sequence: _kbd("view.week")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.currentView = "week"
    }
    Shortcut {
        sequence: _kbd("view.month")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.currentView = "month"
    }
    Shortcut {
        sequence: _kbd("view.docs")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.currentView = "docs"
    }
    Shortcut {
        sequence: _kbd("view.notes")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.currentView = "notes"
    }
    Shortcut {
        sequence: _kbd("view.settings")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.currentView = "settings"
    }
    Shortcut {
        sequence: _kbd("view.archive")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.currentView = "archive"
    }
    Shortcut {
        sequence: _kbd("theme.toggle")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.theme = (AppController.theme === "dark" ? "light" : "dark")
    }
    Shortcut {
        sequence: _kbd("person.new")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: personPicker.open_()
    }
    Shortcut {
        sequence: _kbd("profile.new")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: profileEditor.showCreate()
    }
    Shortcut {
        sequence: _kbd("profile.next")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: win._cycleProfile(1)
    }
    Shortcut {
        sequence: _kbd("profile.prev")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: win._cycleProfile(-1)
    }
    Shortcut {
        sequence: _kbd("profile.exportMd")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.copyActiveProfileMarkdownToClipboard()
    }
    // Focus mode (APP-160): on, and again to leave. Esc leaves it too when
    // nothing nearer would take the Esc (a selection, the board cursor, a
    // field, a dialog) — those stand the shortcut down, so the two never
    // compete for the same key.
    Shortcut {
        sequence: win._kbd("focus.immersion")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn && !!(AppController.safety && AppController.safety.immersion)
        onActivated: win.toggleImmersion()
    }
    // The 0.6 tools (APP-192): no key by default; live once one is bound in
    // Settings → Hotkeys, and they run what the palette runs.
    Shortcut {
        sequence: win._kbd("timeMachine.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: win.runCommand("timeMachine.open")
    }
    Shortcut {
        sequence: win._kbd("standup.draft")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn && !!(AppController.safety && AppController.safety.standupDraft)
        onActivated: win.runCommand("standup.draft")
    }
    Shortcut {
        sequence: win._kbd("recap.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: win.runCommand("recap.open")
    }
    Shortcut {
        sequence: win._kbd("endOfDay.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: win.runCommand("endOfDay.open")
    }
    Shortcut {
        sequence: win._kbd("welcome.replay")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: win.runCommand("welcome.replay")
    }
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: AppController.immersion && !win._viewKeysBlocked && AppController.selectionCount === 0
                 && !(AppController.currentView === "board" && !!boardLoader.item && boardLoader.item["cursorVisible"] === true)
        onActivated: AppController.stopImmersion()
    }
    // Interface scale (APP-168) from the keyboard: a step of Theme.scaleSteps
    // up or down, or back to 100 %, stored where Settings → Appearance → Scale
    // stores it. Live over dialogs and in text fields too (no editor binds
    // these keys), so a modal is no reason to stand down; only the hotkey
    // recorder, which wants the key itself, and the capture window, which is
    // a window of its own, keep them.
    function zoomInterface(direction) {
        const s = AppController.stepUiScale(direction, Theme.scaleSteps);
        toast.show(I18n.t("toast.uiScale").arg(Math.round(s * 100)), "info", "uiScale");
    }
    property bool _captureActive: false
    readonly property bool _zoomKeysOn: !hotkeys.isCapturing && !win._captureActive
    // The fixed aliases match kBuiltinKeys in AppController.cpp. Where one key
    // matches two of them (Ctrl+Shift+= is also Ctrl++), Qt reports it as
    // ambiguous: that is still one press.
    Shortcut {
        context: Qt.ApplicationShortcut
        enabled: win._zoomKeysOn
        objectName: "shortcut-zoom-in"
        sequences: [win._kbd("zoom.in"), "Ctrl++", "Ctrl+Shift+=", "Ctrl+Num++"]
        onActivated: win.zoomInterface(1)
        onActivatedAmbiguously: win.zoomInterface(1)
    }
    Shortcut {
        context: Qt.ApplicationShortcut
        enabled: win._zoomKeysOn
        objectName: "shortcut-zoom-out"
        sequences: [win._kbd("zoom.out"), "Ctrl+Num+-"]
        onActivated: win.zoomInterface(-1)
        onActivatedAmbiguously: win.zoomInterface(-1)
    }
    Shortcut {
        context: Qt.ApplicationShortcut
        enabled: win._zoomKeysOn
        objectName: "shortcut-zoom-reset"
        sequences: [win._kbd("zoom.reset"), "Ctrl+Num+0"]
        onActivated: win.zoomInterface(0)
        onActivatedAmbiguously: win.zoomInterface(0)
    }
    Shortcut {
        sequence: _kbd("profile.weeklyReport")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: AppController.copyWeeklyReportToClipboard()
    }
    Shortcut {
        sequence: _kbd("tweaks.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: rail.openTweaks(rail.tweaksAnchor)
    }
    // The event log (APP-187).
    Shortcut {
        objectName: "shortcut-log-open"
        sequence: win._kbd("log.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: eventLog.showNow()
    }
    Shortcut {
        sequence: _kbd("hotkeys.open")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: rail.openHotkeys(rail.hotkeysAnchor)
    }
    // `?` opens the same cheat-sheet (APP-166), as in most keyboard-first
    // apps. A view key: it stands down while anything takes typed text, so a
    // question mark in a title is still a question mark. Shift+/ is what the
    // key reports on layouts where Qt does not fold it into Key_Question, and
    // Shift+? where the event keeps the Shift it took to type it.
    Shortcut {
        objectName: "shortcut-question-cheatsheet"
        sequences: ["?", "Shift+?", "Shift+/"]
        context: Qt.ApplicationShortcut
        enabled: !win._viewKeysBlocked && !hotkeys.opened
        onActivated: rail.openHotkeys(rail.hotkeysAnchor)
        // Where a layout reports the key both ways, both sequences match.
        onActivatedAmbiguously: rail.openHotkeys(rail.hotkeysAnchor)
    }
    Shortcut {
        sequence: _kbd("undo")
        context: Qt.ApplicationShortcut
        // Not behind an open editor or dialog: it would change what the dialog
        // is showing (and could delete the task being edited). Inside a text
        // field Ctrl+Z belongs to the field, which takes it first.
        enabled: sequence.length > 0 && win._globalKeysOn && AppController.hasPendingUndo && !win._overlayOpen
            && !(boardLoader.item && boardLoader.item.dialogOpen === true)
        onActivated: AppController.undo()
    }
    Shortcut {
        sequence: _kbd("redo")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn && AppController.canRedo && !win._overlayOpen
            && !(boardLoader.item && boardLoader.item.dialogOpen === true)
        onActivated: AppController.redo()
    }
    Shortcut {
        sequence: _kbd("search.focus")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && win._globalKeysOn
        onActivated: win._focusSearch()
    }

    Shortcut {
        sequence: _kbd("selection.selectAll")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !win._viewKeysBlocked
            && (AppController.currentView === "board"
                || AppController.currentView === "timeline"
                || AppController.currentView === "week"
                || AppController.currentView === "archive")
        onActivated: {
            const v = win.activeViewItem();
            if (v && v.selectAllVisible) v.selectAllVisible();
        }
    }
    // Esc lets go of the selection and, on the board, of the keyboard
    // cursor — last. It stays out of the way (enabled only when there is
    // something to let go of, and never while a popup, menu, editor or text
    // field holds the keyboard) so the innermost thing closes first: one Esc
    // closes the editor or the menu, the next one lets go of the selection.
    Shortcut {
        sequence: _kbd("selection.clearSel")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !win._viewKeysBlocked
            && (AppController.selectionCount > 0
                || (AppController.currentView === "board"
                    && !!boardLoader.item && boardLoader.item["cursorVisible"] === true))
        onActivated: {
            AppController.clearSelection();
            if (boardLoader.item && boardLoader.item.clearCursor) boardLoader.item.clearCursor();
        }
    }
    // Esc on a tabbed-to control outside the view (filter chip, mini week, day
    // panel…) hands the keyboard back to the view.
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: win._focusOnControl && !win._typing && !win._focusInPopup && !win._overlayOpen
                 && !hotkeys.isCapturing
        onActivated: win.focusActiveView()
    }
    Shortcut {
        sequence: _kbd("selection.deleteSel")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !win._viewKeysBlocked
            && AppController.selectionCount > 0
        onActivated: AppController.deleteSelectedTasks()
    }
    // Open the selected (or hovered) mirrored issue in its tracker (HEAP-117).
    // This is the first bare letter in the catalog. Qt hands a focused text
    // field the ShortcutOverride for an unmodified key, so typing "o" still
    // types it — but a read-only Text or a ComboBox's type-ahead would lose,
    // so the shortcut also stands down while any overlay is open.
    // ── Board keyboard cursor ─────────────────────────────────────────
    // The board was mouse-only: no way to move between cards, open one or
    // move one without dragging. Each of these stands down while an overlay
    // is open and off the board, exactly like task.openExternal below.
    //
    // The catalog holds the vim letter so it can be rebound; the arrow key is
    // a fixed alias alongside it, the way Ctrl+P aliases the palette.
    // A calendar view is week or month; the day panel follows the same selected
    // date, so moving it moves everything that is on screen.
    component CalKey: Shortcut {
        context: Qt.ApplicationShortcut
        enabled: sequences.length > 0 && !win._viewKeysBlocked
            && (AppController.currentView === "week" || AppController.currentView === "month")
    }

    // The day panel follows the selected date in every view it sits beside,
    // so today, go-to-date and a day at a time work from those too — they
    // used to be week/month only. They stand down like every other view key:
    // G opened go-to-date over the profile menu and a "Delete column?"
    // confirm, Alt+← moved the day from the header search (SHELL-3).
    component DayKey: Shortcut {
        context: Qt.ApplicationShortcut
        enabled: sequences.length > 0 && !win._viewKeysBlocked
            && ["board", "timeline", "week", "month", "archive"].indexOf(AppController.currentView) >= 0
    }
    DayKey {
        sequences: [_kbd("cal.today")]
        onActivated: AppController.selectedDate = AppController.today
    }
    DayKey {
        sequences: [_kbd("cal.prevDay")]
        onActivated: {
            const d = AppController.selectedDate;
            AppController.selectedDate = new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1);
        }
    }
    DayKey {
        sequences: [_kbd("cal.nextDay")]
        onActivated: {
            const d = AppController.selectedDate;
            AppController.selectedDate = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1);
        }
    }
    // A new event from the keyboard: the editor opens on the next free slot
    // of the selected day, named before it exists.
    Shortcut {
        sequences: [_kbd("cal.newEvent")]
        context: Qt.ApplicationShortcut
        // Behind a modal, a menu or a view's own dialog it stands down like
        // every other global key; it used to open over a delete confirmation
        // (SHELL-2, audit 2026-09-30). In a text field AltGrGuard keeps the
        // chord for the field (AltGr+E is € on a German layout).
        enabled: sequences.length > 0 && win._globalKeysOn && !win._overlayOpen
        onActivated: {
            const day = AppController.selectedDate;
            const draft = AppController.newEventDraft(AppController.nextFreeSlot(day, 1), day);
            eventEditor.showForDraft(draft);
        }
    }
    CalKey {
        sequences: [_kbd("cal.prev")]
        onActivated: { const v = win.activeViewItem(); if (v && v.step) v.step(-1); }
    }
    CalKey {
        sequences: [_kbd("cal.next")]
        onActivated: { const v = win.activeViewItem(); if (v && v.step) v.step(1); }
    }
    // What a drag does in Week, Month and Timeline, from the keyboard
    // (APP-249): the task that has the keyboard (or the pointer) moves a day,
    // a week, or a grid step. Ctrl+arrows are the board's own card moves;
    // these are live only in the three views that drag dates.
    readonly property bool _moveKeysOn: !win._viewKeysBlocked
        && ["week", "month", "timeline"].indexOf(AppController.currentView) >= 0
    function _moveViewTask(days, steps) {
        const v = win.activeViewItem();
        if (!v) return;
        if (days !== 0 && v.moveKeyTaskByDays) v.moveKeyTaskByDays(days);
        else if (steps !== 0 && v.moveKeyTaskByTime) v.moveKeyTaskByTime(steps);
    }
    Shortcut {
        sequences: [win._kbd("cal.taskEarlier")]
        context: Qt.ApplicationShortcut
        enabled: win._moveKeysOn && win._kbd("cal.taskEarlier").length > 0
        onActivated: win._moveViewTask(-1, 0)
    }
    Shortcut {
        sequences: [win._kbd("cal.taskLater")]
        context: Qt.ApplicationShortcut
        enabled: win._moveKeysOn && win._kbd("cal.taskLater").length > 0
        onActivated: win._moveViewTask(1, 0)
    }
    Shortcut {
        sequences: [win._kbd("cal.taskEarlierWeek")]
        context: Qt.ApplicationShortcut
        enabled: win._moveKeysOn && win._kbd("cal.taskEarlierWeek").length > 0
        onActivated: win._moveViewTask(-7, 0)
    }
    Shortcut {
        sequences: [win._kbd("cal.taskLaterWeek")]
        context: Qt.ApplicationShortcut
        enabled: win._moveKeysOn && win._kbd("cal.taskLaterWeek").length > 0
        onActivated: win._moveViewTask(7, 0)
    }
    Shortcut {
        sequences: [win._kbd("cal.taskTimeEarlier")]
        context: Qt.ApplicationShortcut
        enabled: win._moveKeysOn && win._kbd("cal.taskTimeEarlier").length > 0
        onActivated: win._moveViewTask(0, -1)
    }
    Shortcut {
        sequences: [win._kbd("cal.taskTimeLater")]
        context: Qt.ApplicationShortcut
        enabled: win._moveKeysOn && win._kbd("cal.taskTimeLater").length > 0
        onActivated: win._moveViewTask(0, 1)
    }
    DayKey {
        sequences: [_kbd("cal.goToDate")]
        onActivated: goToDatePopup.openAt(AppController.selectedDate, win.contentItem)
    }

    // The Monday recap: last week's column moves (WEAK PECAP). Opens itself
    // on the first launch of a week, and when the app is left running into
    // Monday; the palette opens it any time.
    // The time machine (APP-162): Settings → Data and the palette open it.
    TimeMachineDialog {
        id: timeMachine
    }

    EventLogDialog {
        id: eventLog
        onEntryActivated: (entry) => win.openLogEntry(entry)
    }

    WeeklyRecapDialog {
        id: weeklyRecap
        onTaskActivated: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
        onStandupDraftRequested: standupDraft.showNow()
    }
    // The recap opens by itself only where it can be seen (APP-211): the
    // window on screen and in front, nothing open over it. A week that
    // turns while heap sits in the tray, minimised, behind other windows or
    // under the task editor waits for the next of these: the day turning
    // (midnight, resume from sleep), the window coming back to the front, an
    // overlay closing.
    function _maybeShowRecap() {
        if (!AppController.welcomeSeen) return;
        const onScreen = win.visible && win.visibility !== Window.Minimized && win.visibility !== Window.Hidden;
        weeklyRecap.showIfDue(onScreen, win.active && !win._captureActive, win._overlayOpen);
    }
    onActiveChanged: if (win.active) Qt.callLater(win._maybeShowRecap)
    on_OverlayOpenChanged: if (!win._overlayOpen) Qt.callLater(win._maybeShowRecap)
    // The standup draft (APP-170): text to edit and copy, sent nowhere.
    StandupDraftDialog { id: standupDraft }
    // "Send the status anyway?" for an issue the check found outside the
    // filter (APP-204). Cancel is the default.
    TrackerPushConfirmDialog { id: trackerPushConfirm }
    // The day's summary (APP-190): closed, carrying over, timers. Read-only.
    EndOfDayDialog {
        id: endOfDay
        onTaskActivated: (id) => taskEditor.showFor(Object.assign({}, AppController.taskById(id)))
    }
    Connections {
        target: AppController
        function onTodayChanged() {
            win._maybeShowRecap();
        }
    }

    // Jump straight to a day rather than paging to it. Anchored to the window
    // rather than to a view, because the view under it is swapped out.
    DatePickerPopup {
        id: goToDatePopup
        objectName: "go-to-date"
        // Centred over the window (a third of the way down, where the eye
        // is), not pinned to its top-left corner over the logo.
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 3) : 0
        onPicked: (value) => AppController.selectedDate = value
    }

    // Type to search on the board (APP-117): a letter that is not one of the
    // board's own shortcuts, typed with no text field focused, starts a search
    // in the top bar. Esc clears it; Return hands the keyboard back to the
    // board cursor, which walks what the search left.
    TypeAhead {
        id: boardTypeAhead
        // A card's menu is a popup, so _viewKeysBlocked already covers it.
        enabled: AppController.currentView === "board" && !win._viewKeysBlocked
        onTyped: (text) => topBar.typeAhead(text)
    }

    component BoardKey: Shortcut {
        context: Qt.ApplicationShortcut
        // Not while a card's menu is up: its arrows and letters belong to it.
        enabled: sequences.length > 0 && !win._viewKeysBlocked
            && AppController.currentView === "board"
            && !(boardLoader.item && boardLoader.item.cardMenuOpen === true)
    }

    BoardKey {
        sequences: [_kbd("board.cursorDown"), "Down"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursor) b.moveCursor(0, 1); }
    }
    BoardKey {
        sequences: [_kbd("board.cursorUp"), "Up"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursor) b.moveCursor(0, -1); }
    }
    BoardKey {
        sequences: [_kbd("board.cursorLeft"), "Left"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursor) b.moveCursor(-1, 0); }
    }
    BoardKey {
        sequences: [_kbd("board.cursorRight"), "Right"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursor) b.moveCursor(1, 0); }
    }
    BoardKey {
        sequences: [_kbd("board.open"), "Enter"]
        onActivated: { const b = win.activeViewItem(); if (b && b.openCursor) b.openCursor(); }
    }
    BoardKey {
        sequences: [_kbd("board.toggleSelect")]
        onActivated: { const b = win.activeViewItem(); if (b && b.toggleCursorSelection) b.toggleCursorSelection(); }
    }
    BoardKey {
        sequences: [win._kbd("board.moveDown"), "Ctrl+Down"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursorCard) b.moveCursorCard(0, 1); }
    }
    BoardKey {
        sequences: [win._kbd("board.moveUp"), "Ctrl+Up"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveCursorCard) b.moveCursorCard(0, -1); }
    }
    BoardKey {
        sequences: [win._kbd("board.moveLeft"), "Ctrl+Left"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveSelectionOrCard) b.moveSelectionOrCard(-1); }
    }
    BoardKey {
        sequences: [win._kbd("board.moveRight"), "Ctrl+Right"]
        onActivated: { const b = win.activeViewItem(); if (b && b.moveSelectionOrCard) b.moveSelectionOrCard(1); }
    }
    // Selecting from the keyboard (APP-128).
    BoardKey {
        sequences: [win._kbd("board.selectDown")]
        onActivated: { const b = win.activeViewItem(); if (b && b.extendSelection) b.extendSelection(1); }
    }
    BoardKey {
        sequences: [win._kbd("board.selectUp")]
        onActivated: { const b = win.activeViewItem(); if (b && b.extendSelection) b.extendSelection(-1); }
    }
    BoardKey {
        sequences: [win._kbd("board.selectColumnLeft")]
        onActivated: { const b = win.activeViewItem(); if (b && b.selectColumnAndStep) b.selectColumnAndStep(-1); }
    }
    BoardKey {
        sequences: [win._kbd("board.selectColumnRight")]
        onActivated: { const b = win.activeViewItem(); if (b && b.selectColumnAndStep) b.selectColumnAndStep(1); }
    }
    // The card menu, archive and fold, for the card/column the keyboard is on
    // (TASKS-32 / UX-26).
    BoardKey {
        sequences: [_kbd("board.cardMenu"), "Menu"]
        onActivated: { const b = win.activeViewItem(); if (b && b.openCursorMenu) b.openCursorMenu(); }
    }
    BoardKey {
        sequences: [_kbd("board.archive")]
        onActivated: { const b = win.activeViewItem(); if (b && b.archiveCursor) b.archiveCursor(); }
    }
    BoardKey {
        sequences: [_kbd("board.collapseColumn")]
        onActivated: { const b = win.activeViewItem(); if (b && b.toggleCursorColumn) b.toggleCursorColumn(); }
    }

    Shortcut {
        sequence: _kbd("task.openExternal")
        context: Qt.ApplicationShortcut
        enabled: sequence.length > 0 && !win._viewKeysBlocked
            && (AppController.currentView === "board"
                || AppController.currentView === "archive"
                || AppController.currentView === "timeline"
                || AppController.currentView === "week")
        onActivated: {
            // One selected card is unambiguous. Otherwise act on whatever the
            // cursor is over — never on a whole multi-selection, which would
            // open a browser tab per card.
            let id = "";
            if (AppController.selectionCount === 1) {
                id = AppController.selectedTaskIds[0];
            } else if (AppController.selectionCount === 0) {
                const v = win.activeViewItem();
                if (v && v.hoveredTaskId) id = v.hoveredTaskId;
            }
            if (id) AppController.openTaskExternal(id);
        }
    }

    Connections {
        target: AppController
        function onActiveProfileChanged() {
            win.searchText = "";
            win.prioritiesFilter = ({});
            savedViewsHost.leave();   // views belong to the profile being left
            AppController.selectedDate = AppController.today;
            Qt.callLater(win.seedStarterDocs);
        }
    }

    // Tweaks + Hotkeys popovers (opened from the side rail)
    // Re-clamped whenever their height settles: on the first open the panel
    // measures itself after it is placed, and the Tweaks panel hung 24px
    // below a 720px window.
    TweaksPanel  {
        id: tweaks
        onHeightChanged: if (opened && parent) win._placePopover(tweaks, parent)
        // A setting found by the panel's search (APP-210).
        onOpenSettingsItem: (item) => win.openSettingsItem(item)
    }
    HotkeysPanel {
        id: hotkeys
        onHeightChanged: if (opened && parent) win._placePopover(hotkeys, parent)
    }

    // ── Profile import / export via JSON file ──────────────────────────
    FileDialog {
        id: exportJsonDialog
        fileMode: FileDialog.SaveFile
        nameFilters: ["heap. profile (*.json)", "All files (*)"]
        defaultSuffix: "json"
        title: I18n.t("dialog.exportProfile.title")
        onAccepted: {
            if (AppController.exportActiveProfileToFile(selectedFile))
                toast.show(I18n.t("toast.profile.exported"), "success");
            else
                win.notice(I18n.t("toast.profile.exportFail"), "error");
        }
    }
    FileDialog {
        id: importJsonDialog
        fileMode: FileDialog.OpenFile
        nameFilters: ["heap. profile (*.json)", "All files (*)"]
        title: I18n.t("dialog.importProfile.title")
        onAccepted: {
            const err = AppController.importProfileFromJson === undefined
                ? "" : AppController.importProfileFromFile(selectedFile, true);
            if (err && err.length > 0)
                win.notice(I18n.t("toast.profile.importFail") + err, "error");
        }
    }

    // ── Calendar import / export via .ics ──────────────────────────────
    FileDialog {
        id: importIcsDialog
        fileMode: FileDialog.OpenFile
        nameFilters: ["Calendar (*.ics)", "All files (*)"]
        title: I18n.t("dialog.importIcs.title")
        onAccepted: {
            const r = AppController.importIcs(selectedFile);
            if (r.error) {
                win.notice(r.error, "error");
                return;
            }
            // Counts, not a bare "done": a file that brought in nine events
            // and skipped one is neither a success nor a failure.
            // What was degraded is said, not only logged: an unsupported
            // rule means a series that shows as a single event.
            const warns = r.warnings || [];
            let msg = I18n.t("toast.ics.imported").arg(r.imported).arg(r.updated).arg(r.skipped);
            if (warns.length > 0)
                msg += " · " + (warns.length === 1 ? warns[0] : I18n.t("toast.ics.warnings").arg(warns.length).arg(warns[0]));
            win.notice(msg, (r.skipped > 0 || warns.length > 0) ? "warning" : "success");
            for (let i = 0; i < warns.length; i++) console.warn("[ics]", warns[i]);
        }
    }
    FileDialog {
        id: exportIcsDialog
        fileMode: FileDialog.SaveFile
        nameFilters: ["Calendar (*.ics)", "All files (*)"]
        defaultSuffix: "ics"
        title: I18n.t("dialog.exportIcs.title")
        onAccepted: {
            const ok = AppController.exportIcsToFile(selectedFile);
            win.notice(ok ? I18n.t("toast.ics.exported") : I18n.t("toast.ics.exportFail"),
                       ok ? "success" : "error");
        }
    }

    // ── Notes as a folder of .md files ─────────────────────────────────
    FileDialog {
        id: importVaultDialog
        fileMode: FileDialog.OpenFile
        // A folder picker, not a file picker: the user chooses any file in the
        // vault and heap takes the directory, because FolderDialog on Windows
        // hides the contents and people cannot tell which folder they are in.
        nameFilters: ["Markdown (*.md *.markdown)", "All files (*)"]
        title: I18n.t("dialog.importVault.title")
        // Nothing is imported from here: the folder is previewed first, so
        // what is about to change is visible before it does.
        onAccepted: vaultImportConfirm.openFor(currentFolder)
    }
    VaultImportDialog {
        id: vaultImportConfirm
        onImported: (r) => {
            if (r.error) { win.notice(r.error, "error"); return; }
            const trouble = r.skipped > 0 || r.conflicts > 0;
            win.notice(I18n.t("toast.notes.importedFull")
                       .arg(r.imported).arg(r.updated).arg(r.kept).arg(r.conflicts).arg(r.skipped),
                       trouble ? "warning" : "success");
            for (let i = 0; i < r.warnings.length; i++) console.warn("[vault]", r.warnings[i]);
        }
    }
    FileDialog {
        id: exportVaultDialog
        fileMode: FileDialog.SaveFile
        nameFilters: ["All files (*)"]
        title: I18n.t("dialog.exportVault.title")
        // The typed name becomes the new folder the notes go into; nothing
        // already in the chosen directory is written over.
        onAccepted: {
            const file = String(selectedFile);
            const name = decodeURIComponent(file.substring(file.lastIndexOf("/") + 1));
            const r = AppController.exportNotesFolder(currentFolder, name);
            win.notice(r.error ? r.error
                               : I18n.t("toast.notes.exportedTo").arg(r.written).arg(r.folder),
                       r.error ? "error" : "success");
        }
    }

    // Spans the work area (the main column, beside the side rail and the
    // right panel): a wide one gets the stack in its bottom-right corner,
    // a narrow one its bottom centre (APP-225). Popups and dialogs sit on
    // the overlay above it, so a toast never covers Quick Capture or a
    // dialog's buttons.
    Toast {
        id: toast
        objectName: "toast"
        x: mainColumn.x
        width: mainColumn.width
        areaWidth: mainColumn.width
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 + win._selectionBarSpace + win._resumePillSpace
        z: 100
    }

    // Launch splash — covers the window until the scene is ready, then fades.
    // Honours reduced motion (no bar animation, no fade, dismissed promptly).
    SplashScreen {
        id: splash
        objectName: "splash"
        anchors.fill: parent
        z: 9999
        autoAnimate: !Theme.reducedMotion
        autoDuration: 900
        onFinished: splashFade.start()

        // Swallow input while the splash is up.
        MouseArea { anchors.fill: parent }

        // Reduced motion: the internal progress animation is off, so dismiss
        // via a short timer instead.
        Component.onCompleted: if (Theme.reducedMotion) splashReducedDismiss.start()
        Timer { id: splashReducedDismiss; interval: 250; onTriggered: splash.finished() }

        NumberAnimation {
            id: splashFade
            target: splash; property: "opacity"; to: 0
            duration: Theme.durMoveOut; easing.type: Theme.easeExit
            onFinished: splash.visible = false
        }
    }
}
