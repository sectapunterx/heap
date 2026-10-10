// APP-174: the keyboard cursor has a colour of its own. Settings → Appearance
// → Cursor colour picks it (appearance.cursorColor), none means the theme's
// accent, and every FocusRing — ClickArea, fields, lists, board cards — draws
// in it. Selection is told apart by form, not by this colour.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp
import "../../qml/ThemePresets.js" as Presets

TestCase {
    id: tc
    name: "CursorColor"
    when: windowShown
    visible: true
    width: 900
    height: 700

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""

    function initTestCase() { tc.savedSettings = AppController.appSettingsJson; }
    function cleanup() { AppController.appSettingsJson = tc.savedSettings; }

    function setCursorColor(c) {
        let s = {};
        try { s = JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { s = {}; }
        const a = Object.assign({}, s.appearance);
        if (c === undefined) delete a.cursorColor; else a.cursorColor = c;
        s.appearance = a;
        AppController.appSettingsJson = JSON.stringify(s);
    }

    // The logo's lavender, what no pick means since 0.8.0.
    function lavender() { return Theme.dark ? "#b1a7f0" : "#5a4fb3"; }

    function surfaces() {
        return [String(Theme.bg), String(Theme.panel), String(Theme.panel2), String(Theme.panel3)];
    }

    function find(item, pred) {
        if (!item) return null;
        if (pred(item)) return item;
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = find(kids[i], pred);
            if (r) return r;
        }
        if (item.contentItem && item.contentItem !== item) return find(item.contentItem, pred);
        return null;
    }

    function test_default_is_lavender() {
        setCursorColor(undefined);
        compare(Theme.cursorColorPick, tc.lavender());
        // No pick is the logo's lavender, on any theme (0.8.0).
        verify(Qt.colorEqual(Theme.focusRing, Presets.ensureContrast(tc.lavender(), surfaces(), 3.0)),
               "no pick is not lavender: " + Theme.focusRing);
    }

    function test_a_pick_recolours_every_ring() {
        const pick = Theme.swatches[0];
        const ring = createTemporaryQmlObject(
            'import QtQuick; import TodoCpp; Rectangle { width: 40; height: 20; activeFocusOnTab: true; FocusRing { objectName: "r" } }', host);
        const area = createTemporaryQmlObject(
            'import QtQuick; import TodoCpp; Rectangle { x: 60; width: 40; height: 20; ClickArea { label: "x" } }', host);
        const r1 = find(ring, (it) => it.objectName === "r");
        const r2 = find(area, (it) => it.objectName === "focus-ring");
        verify(r1 !== null && r2 !== null);
        setCursorColor(undefined);
        const before = String(Theme.focusRing);

        setCursorColor(pick);
        compare(Theme.cursorColorPick, pick.toLowerCase());
        verify(Qt.colorEqual(Theme.focusRing, Presets.ensureContrast(pick, surfaces(), 3.0)));
        verify(!Qt.colorEqual(Theme.focusRing, before), "the pick did not change the cursor");
        verify(Qt.colorEqual(r1.border.color, Theme.focusRing));
        verify(Qt.colorEqual(r2.border.color, Theme.focusRing));
        // The halo is the same colour, faint.
        const halo = find(r1, (it) => it.objectName === "focus-ring-halo");
        verify(halo !== null);
        compare(halo.border.color.a.toFixed(2), "0.22");

        setCursorColor(undefined);
        verify(Qt.colorEqual(r1.border.color, before), "clearing the pick did not go back to the accent");
    }

    function test_a_broken_pick_falls_back_to_the_accent() {
        setCursorColor(undefined);
        const accent = String(Theme.focusRing);
        setCursorColor("red");
        compare(Theme.cursorColorPick, tc.lavender());
        verify(Qt.colorEqual(Theme.focusRing, accent));
    }

    function test_selected_card_is_filled_and_ticked_not_ringed() {
        const d = AppController.newTaskDraft(AppController.statuses[0].id);
        d._isNew = true;
        d.title = "cursorcolour probe";
        verify(AppController.saveTask(d));
        const card = createTemporaryQmlObject('import TodoCpp; TaskCard { width: 260 }', host);
        card.task = AppController.taskById(d.id);
        const ring = find(card, (it) => it.objectName === "tc-cursor-ring");
        const mark = find(card, (it) => it.objectName === "tc-selected-mark");
        verify(ring !== null && mark !== null);

        AppController.setSelectedTaskIds([d.id]);
        tryVerify(() => mark.visible, 1000, "no check mark on a selected card");
        verify(!ring.visible, "a selected card drew the cursor ring");
        verify(!Qt.colorEqual(card.color, Theme.panel2), "a selected card has no fill");
        compare(card.border.width, 1);
        verify(!Qt.colorEqual(card.border.color, Theme.focusRing), "selection used the cursor colour");

        card.cursored = true;
        verify(ring.visible);
        verify(Qt.colorEqual(ring.border.color, Theme.focusRing));

        AppController.clearSelection();
        AppController.deleteTask(d.id);
        AppController.clearPendingUndo();
    }

    function test_settings_row_writes_the_pick() {
        const sv = createTemporaryQmlObject('import TodoCpp; SettingsView { anchors.fill: parent }', host);
        verify(sv.openSection("appearance"));
        let row = null;
        tryVerify(() => (row = find(sv, (it) => it.objectName === "settings-cursor-color")) !== null, 3000, "no cursor colour row");
        setCursorColor(undefined);
        // The theme's accent and the ten swatches.
        const accentDot = find(row, (it) => it.objectName === "cursor-color-accent");
        const third = find(row, (it) => it.objectName === "cursor-color-3");
        verify(accentDot !== null && third !== null);
        verify(find(row, (it) => it.objectName === "cursor-color-10") !== null);
        verify(accentDot.picked);

        row.selected(Theme.swatches[2]);
        compare(Theme.cursorColorPick, Theme.swatches[2].toLowerCase());
        tryVerify(() => third.picked && !accentDot.picked, 1000);
        compare(JSON.parse(AppController.appSettingsJson).appearance.cursorColor, Theme.swatches[2]);

        row.selected("");
        compare(Theme.cursorColorPick, tc.lavender());
        tryVerify(() => accentDot.picked, 1000);
    }
}
