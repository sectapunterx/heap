// Every control the keyboard can reach is named for a screen reader
// (APP-168). Drives the real Main.qml, opens each view and each Settings
// section, and walks what is on screen: an item on the Tab path with no
// Accessible.name (and no text or placeholder a control would announce
// instead) is a control a screen reader can only call "button".
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "A11yWalk"
    when: windowShown

    property var win: null

    function initTestCase() {
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        verify(comp.status === Component.Ready, comp.errorString());
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tc.win.width = 1456;
        tc.win.height = 939;
        wait(1200);   // splash
        const cd = tc.win.contentData;
        for (let i = 0; i < cd.length; i++) {
            const o = cd[i];
            if (o && o.opened === true && o.close) o.close();
        }
        tc.win.requestActivate();
    }

    function cleanupTestCase() {
        AppController.currentView = "board";
        if (tc.win) tc.win.destroy();
        tc.win = null;
    }

    function typeName(o) {
        const s = String(o);
        const i = s.indexOf("(");
        return i > 0 ? s.slice(0, i) : s;
    }

    function spokenName(it) {
        const acc = it.Accessible ? String(it.Accessible.name || "") : "";
        if (acc.length > 0) return acc;
        // A Controls button announces its text, a field its placeholder.
        if (typeof it.text === "string" && it.text.length > 0 && it.checkable !== undefined) return it.text;
        if (typeof it.placeholderText === "string" && it.placeholderText.length > 0) return it.placeholderText;
        return "";
    }

    function walk(root, out, path) {
        if (!root || root.visible === false || root.opacity === 0) return;
        const here = path + "/" + (root.objectName || typeName(root));
        if (root.activeFocusOnTab === true && root.enabled !== false && spokenName(root).length === 0)
            out.push(here);
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) walk(kids[i], out, here);
    }

    function unnamedIn(view) {
        AppController.currentView = view;
        tryVerify(function () { return tc.win.activeViewItem() !== null; }, 3000);
        wait(300);
        const out = [];
        walk(tc.win.contentItem, out, "");
        return out;
    }

    function test_views_name_every_tab_stop_data() {
        return ["board", "list", "week", "month", "notes"].map(function (v) { return { tag: v, view: v }; });
    }
    function test_views_name_every_tab_stop(data) {
        const missing = unnamedIn(data.view);
        compare(missing.length, 0, data.view + ": unnamed tab stops:\n" + missing.join("\n"));
    }

    function popup(prefix) {
        const cd = tc.win.contentData;
        for (let i = 0; i < cd.length; i++) {
            const o = cd[i];
            if (o && o.opened !== undefined && o.open !== undefined && typeName(o).indexOf(prefix) === 0) return o;
        }
        return null;
    }

    // The dialogs and panels, open, the same way.
    function test_dialogs_name_every_tab_stop_data() {
        return ["TaskEditor", "CommandPalette", "WelcomePopup", "HotkeysPanel", "QuickCapturePopup"]
            .map(function (p) { return { tag: p, prefix: p }; });
    }
    function test_dialogs_name_every_tab_stop(data) {
        AppController.currentView = "board";
        const p = popup(data.prefix);
        verify(p !== null, "no " + data.prefix + " in Main");
        if (data.prefix === "TaskEditor") p.showFor(AppController.newTaskDraft("todo"));
        else p.open();
        tryCompare(p, "opened", true);
        wait(200);
        const out = [];
        walk(p.contentItem, out, data.prefix);
        p.close();
        tryCompare(p, "opened", false);
        if (data.prefix === "TaskEditor") {
            // A new draft's editor asks before it throws an edit away.
            const cd = tc.win.contentData;
            for (let i = 0; i < cd.length; i++) if (cd[i] && cd[i].opened === true && cd[i].close) cd[i].close();
        }
        compare(out.length, 0, data.prefix + ": unnamed tab stops:\n" + out.join("\n"));
    }

    function test_settings_sections_name_every_tab_stop() {
        AppController.currentView = "settings";
        tryVerify(function () { return tc.win.activeViewItem() !== null; }, 3000);
        const sv = tc.win.activeViewItem();
        verify(sv.sections && sv.sections.length > 0);
        const missing = [];
        for (let i = 0; i < sv.sections.length; i++) {
            const id = sv.sections[i].id;
            if (id === "help") continue;   // a document, walked by tst_HelpContent
            sv.openSection(id);
            wait(250);
            const out = [];
            walk(tc.win.contentItem, out, "");
            for (let j = 0; j < out.length; j++) missing.push(id + ": " + out[j]);
        }
        compare(missing.length, 0, "unnamed tab stops:\n" + missing.join("\n"));
    }
}
