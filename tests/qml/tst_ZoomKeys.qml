// Interface scale from the keyboard (APP-168): Ctrl+= / Ctrl+- / Ctrl+0 and
// their fixed aliases step Theme.scale through Theme.scaleSteps, store it
// where Settings → Appearance → Scale does (so the two agree), and say so in
// one toast that is replaced, not stacked. Live in a text field; not while the
// Hotkeys panel records a key.
//
// Drives the real Main.qml with real key events.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ZoomKeys"
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
        setScale(1);
        const t = toast();
        if (t) t.clear();
        AppController.currentView = "board";
        tc.win.focusActiveView();
        wait(20);
    }

    function setScale(s) {
        const o = JSON.parse(AppController.appSettingsJson || "{}");
        o.appearance = Object.assign({}, o.appearance || {}, { uiScale: s });
        AppController.appSettingsJson = JSON.stringify(o);
    }
    function storedScale() {
        const o = JSON.parse(AppController.appSettingsJson || "{}");
        return o.appearance ? o.appearance.uiScale : undefined;
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
        return null;
    }
    function toast() {
        return find(tc.win.contentItem, function (it) { return it.maxVisible !== undefined && it.showWithAction !== undefined; });
    }

    function test_keys_step_the_scale() {
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        tryCompare(Theme, "scale", 1.1);
        compare(storedScale(), 1.1);
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        compare(Theme.scale, 1.5);
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        compare(Theme.scale, 1.5, "the top end stays put");
        keyClick(Qt.Key_Minus, Qt.ControlModifier);
        compare(Theme.scale, 1.25);
        keyClick(Qt.Key_0, Qt.ControlModifier);
        compare(Theme.scale, AppController.defaultUiScale(Theme.scaleSteps));
        // Reset is the default size (the system's), not a pick of 100 %
        // (IDIOT-SHELL-14).
        compare(storedScale(), undefined);
        keyClick(Qt.Key_Minus, Qt.ControlModifier);
        keyClick(Qt.Key_Minus, Qt.ControlModifier);
        compare(Theme.scale, 0.9, "the bottom end stays put");
    }

    function test_aliases() {
        keyClick(Qt.Key_Plus, Qt.ControlModifier);
        compare(Theme.scale, 1.1, "Ctrl++");
        keyClick(Qt.Key_Equal, Qt.ControlModifier | Qt.ShiftModifier);
        compare(Theme.scale, 1.25, "Ctrl+Shift+=");
        keyClick(Qt.Key_Plus, Qt.ControlModifier | Qt.KeypadModifier);
        compare(Theme.scale, 1.5, "numpad Ctrl++");
        keyClick(Qt.Key_Minus, Qt.ControlModifier | Qt.KeypadModifier);
        compare(Theme.scale, 1.25, "numpad Ctrl+-");
        keyClick(Qt.Key_0, Qt.ControlModifier | Qt.KeypadModifier);
        compare(Theme.scale, AppController.defaultUiScale(Theme.scaleSteps), "numpad Ctrl+0");
    }

    function test_between_steps_snaps_that_way() {
        setScale(1.2);
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        compare(Theme.scale, 1.25);
        setScale(1.2);
        keyClick(Qt.Key_Minus, Qt.ControlModifier);
        compare(Theme.scale, 1.1);
    }

    function test_one_toast_replaced() {
        const t = toast();
        verify(t !== null);
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        tryCompare(t, "count", 1);
        compare(t.message, I18n.t("toast.uiScale").arg(110));
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        compare(t.count, 1, "pressed again, the toast is replaced");
        compare(t.message, I18n.t("toast.uiScale").arg(150));
        verify(t.message.indexOf("150") >= 0);
    }

    function test_settings_segrow_follows() {
        AppController.currentView = "settings";
        tryVerify(function () { return tc.win.activeViewItem() && tc.win.activeViewItem().openSection !== undefined; });
        const sv = tc.win.activeViewItem();
        verify(sv.openSection("appearance"));
        let seg = null;
        tryVerify(function () {
            seg = find(sv, function (it) { return it.objectName === "settings-ui-scale"; });
            return seg !== null;
        }, 3000, "no scale row");
        compare(seg.value, "100");
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        tryCompare(seg, "value", "110");
        // And the other way: the row's choice is where the keys go on from.
        seg.selected("125");
        compare(Theme.scale, 1.25);
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        tryCompare(seg, "value", "150");
        compare(storedScale(), 1.5);
        keyClick(Qt.Key_0, Qt.ControlModifier);
        tryCompare(seg, "value", String(Math.round(AppController.defaultUiScale(Theme.scaleSteps) * 100)));
    }

    function test_live_in_a_text_field() {
        AppController.currentView = "settings";
        tryVerify(function () { return tc.win.activeViewItem() && tc.win.activeViewItem().openSection !== undefined; });
        const search = find(tc.win.activeViewItem(), function (it) { return it.objectName === "settings-search"; });
        verify(search !== null);
        search.forceActiveFocus();
        search.text = "";
        verify(tc.win._typing);
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        compare(Theme.scale, 1.1);
        compare(search.text, "", "the key did not type into the field");
        keyClick(Qt.Key_0, Qt.ControlModifier);
        compare(Theme.scale, AppController.defaultUiScale(Theme.scaleSteps));
    }

    function test_not_while_recording_a_key() {
        const hk = popup("HotkeysPanel");
        verify(hk !== null);
        hk.capturingId = "theme.toggle";
        try {
            verify(!tc.win._zoomKeysOn);
            keyClick(Qt.Key_Equal, Qt.ControlModifier);
            compare(Theme.scale, 1);
        } finally {
            hk.capturingId = "";
        }
        verify(tc.win._zoomKeysOn);
    }

    // The capture window is a window of its own: the keys there are its own.
    function test_not_in_the_capture_window() {
        tc.win._capture("task");
        let cw = null;
        const d = tc.win.contentData;
        for (let i = 0; i < d.length; i++)
            if (d[i] && d[i].sourceComponent !== undefined && d[i].item && d[i].item.summon !== undefined) cw = d[i].item;
        try {
            verify(cw !== null, "no capture window");
            cw.requestActivate();
            tryVerify(function () { return cw.active; }, 3000, "capture window never became active");
            tryVerify(function () { return !tc.win._zoomKeysOn; }, 3000, "zoom keys still on");
            keyClick(Qt.Key_Equal, Qt.ControlModifier);
            compare(Theme.scale, 1);
        } finally {
            if (cw) cw.close();
            tc.win.requestActivate();
        }
        tryVerify(function () { return tc.win._zoomKeysOn; }, 3000);
    }

    function test_palette_lists_the_zoom_commands() {
        const pal = popup("CommandPalette");
        verify(pal !== null);
        const cmds = pal._commands();
        for (const id of ["zoom.in", "zoom.out", "zoom.reset"]) {
            let hit = null;
            for (let i = 0; i < cmds.length; i++) if (cmds[i].commandId === id) hit = cmds[i];
            verify(hit !== null, id);
            compare(hit.sub, AppController.shortcutText(id));
        }
        tc.win.runCommand("zoom.in");
        compare(Theme.scale, 1.1);
        tc.win.runCommand("zoom.reset");
        compare(Theme.scale, AppController.defaultUiScale(Theme.scaleSteps));
    }

    // SHELL-3: unset, the first Ctrl+= steps from the scale on screen — it
    // stored the 110 % already shown and did nothing.
    function test_unset_steps_from_the_default() {
        tc.win.runCommand("zoom.reset");
        const def = Theme.scale;
        compare(def, AppController.defaultUiScale(Theme.scaleSteps));
        keyClick(Qt.Key_Equal, Qt.ControlModifier);
        verify(Theme.scale > def, "the first Ctrl+= did nothing");
        tc.win.runCommand("zoom.reset");
        keyClick(Qt.Key_Minus, Qt.ControlModifier);
        const steps = Theme.scaleSteps;
        compare(Theme.scale, steps[Math.max(0, steps.indexOf(def) - 1)], "Ctrl+- skipped a step");
    }
}
