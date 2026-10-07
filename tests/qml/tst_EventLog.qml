// The event log (APP-187) and a sync's news toast (APP-180) in the real
// Main.qml: Ctrl+Shift+L opens the log, an entry takes the user to what it is
// about, and "Show" on a sync's toast filters the board to `is:new`.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "EventLog"
    when: windowShown

    property var win: null
    property string savedSettings: ""

    function initTestCase() {
        tc.savedSettings = AppController.appSettingsJson;
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        verify(comp.status === Component.Ready, comp.errorString());
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tc.win.width = 1456;
        tc.win.height = 939;
        AppController.resetAllShortcuts();
        wait(1200);   // splash
        const w = popup("WelcomePopup");
        if (w && w.opened) w.close();
        tc.win.requestActivate();
        AppController.currentView = "board";
        tryVerify(function () { return tc.win.activeViewItem() !== null; }, 3000);
        wait(100);
    }

    function cleanupTestCase() {
        AppController.appSettingsJson = tc.savedSettings;
        if (tc.win) tc.win.destroy();
        tc.win = null;
    }

    function init() {
        const log = popup("EventLogDialog");
        if (log && log.opened) log.close();
        const t = toast();
        if (t) t.clear();
        AppController.currentView = "board";
        tc.win.searchText = "";
        tc.win.focusActiveView();
        wait(20);
    }

    function typeName(o) {
        const s = String(o);
        const i = s.indexOf("(");
        return i > 0 ? s.slice(0, i) : s;
    }
    function popup(prefix) {
        const cd = tc.win.contentData;
        for (let i = 0; i < cd.length; i++) {
            const o = cd[i];
            if (o && o.opened !== undefined && o.open !== undefined && typeName(o).indexOf(prefix) === 0) return o;
        }
        return null;
    }
    function find(root, pred) {
        if (!root) return null;
        if (pred(root)) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = find(kids[i], pred);
            if (r) return r;
        }
        if (root.contentItem && root.contentItem !== root) return find(root.contentItem, pred);
        return null;
    }
    function toast() {
        return find(tc.win.contentItem, function (it) { return it.maxVisible !== undefined && it.showWithAction !== undefined; });
    }

    function test_shortcut_is_in_the_catalog() {
        compare(AppController.shortcutFor("log.open"), "Ctrl+Shift+L");
    }

    function test_shortcut_opens_the_log_newest_first() {
        AppController.logEvent("warning", "older probe notice");
        AppController.logEvent("error", "newest probe notice", [], "settings:integrations");
        keyClick(Qt.Key_L, Qt.ControlModifier | Qt.ShiftModifier);
        const log = popup("EventLogDialog");
        verify(log !== null);
        tryCompare(log, "opened", true);
        const first = log.entries[0];
        compare(first.message, "newest probe notice");
        compare(first.kind, "error");
        verify(log.count <= 100);
        // Return opens the current (newest) entry: its place in the app.
        keyClick(Qt.Key_Return);
        tryCompare(log, "opened", false);
        tryCompare(AppController, "currentView", "settings");
    }

    function test_entry_without_a_target_stays_put() {
        AppController.logEvent("undo", "untargeted probe " + Date.now());
        const log = popup("EventLogDialog");
        log.showNow();
        tryCompare(log, "opened", true);
        verify(!log.hasTarget(log.entries[0]));
        log.activate(0);
        verify(log.opened, "an entry that leads nowhere closed the log");
        log.close();
    }

    function test_quiet_success_is_not_logged_but_a_qml_failure_is() {
        const before = AppController.eventLog.length;
        tc.win.notice("probe ok " + Date.now(), "success");
        compare(AppController.eventLog.length, before);
        tc.win.notice("probe failed " + Date.now(), "error");
        compare(AppController.eventLog[0].kind, "error");
    }

    function test_sync_news_toast_shows_the_new_cards() {
        const msg = "Jira: 5 new — HT-1 One, HT-2 Two, HT-3 Three, 2 more · 0 updated";
        AppController.syncNews(msg, ["jira-HT-1", "jira-HT-2"]);
        const t = toast();
        tryCompare(t, "count", 1);
        compare(t.message, msg);
        compare(t.actionLabel, I18n.t("sync.show"));
        AppController.currentView = "week";
        const action = find(t, function (it) { return it.objectName === "toast-action"; });
        verify(action !== null);
        mouseClick(action);
        tryCompare(AppController, "currentView", "board");
        compare(tc.win.searchText, "is:new");
    }
}
