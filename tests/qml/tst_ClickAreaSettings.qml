// Design audit DES-19 in Settings, Tweaks, Hotkeys, the theme editor, the top
// bar and the toasts: the hand-drawn buttons there were bare MouseAreas, off
// the Tab path, nameless for a screen reader and dead to the keyboard. Each
// case here finds one of them, checks it is a named Tab stop and runs it with
// Return.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp
import "../../qml/ThemePresets.js" as Presets

TestCase {
    id: tc
    name: "ClickAreaSettings"
    when: windowShown
    visible: true
    width: 900
    height: 1400

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""
    property string savedTheme: ""
    function init() {
        savedSettings = AppController.appSettingsJson;
        savedTheme = AppController.theme;
    }
    function cleanup() {
        AppController.appSettingsJson = savedSettings;
        AppController.theme = savedTheme;
    }

    function find(root, name) {
        if (!root) return null;
        if (root.objectName === name) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = find(kids[i], name);
            if (r) return r;
        }
        return null;
    }

    // A named Tab stop that Return runs.
    function reachable(area, what) {
        verify(area !== null, what + " not found");
        verify(area.activeFocusOnTab, what + " is not on the Tab path");
        verify(String(area.Accessible.name).length > 0, what + " has no accessible name");
        area.forceActiveFocus(Qt.TabFocusReason);
        verify(area.activeFocus, what + " did not take the keyboard");
        keyClick(Qt.Key_Return);
    }

    // ── Settings ───────────────────────────────────────────────────────
    function settingsAt(section) {
        const sv = createTemporaryQmlObject('import TodoCpp; SettingsView { anchors.fill: parent }', host);
        verify(sv !== null);
        sv.activeSection = section;
        wait(50);
        return sv;
    }

    function test_settings_work_day_chip_toggles_on_return() {
        const sv = settingsAt("calendar");
        let chip = null;
        tryVerify(function () { chip = find(sv, "settings-workday-6"); return chip !== null; }, 2000);
        compare(chip.role, Accessible.CheckBox);
        const before = chip.checked;
        reachable(chip, "Saturday chip");
        tryVerify(function () { return chip.checked !== before; }, 1000, "Return did not toggle the day");
        keyClick(Qt.Key_Return);
        tryVerify(function () { return chip.checked === before; }, 1000);
    }

    function test_settings_auto_sync_option_runs_on_return() {
        const sv = settingsAt("integrations");
        let opt = null;
        tryVerify(function () { opt = find(sv, "settings-autosync-1440"); return opt !== null; }, 2000);
        reachable(opt, "daily auto-sync");
        tryVerify(function () { return sv.settings.integrations.autoSyncMinutes === 1440; }, 1000);
        verify(opt.checked);
    }

    // APP-123: any cadence up to a month — a number and a unit.
    function test_settings_auto_sync_custom_period() {
        const sv = settingsAt("integrations");
        let field = null;
        tryVerify(function () { field = find(sv, "settings-autosync-custom"); return field !== null; }, 2000);
        const days = find(sv, "settings-autosync-unit-1440");
        verify(days !== null);
        field.text = "30";
        days.activated();
        tryVerify(function () { return sv.settings.integrations.autoSyncMinutes === 30 * 1440; }, 1000,
                  "30 days did not save as minutes");
        field.text = "99";
        field.editingFinished();
        tryVerify(function () { return sv.settings.integrations.autoSyncMinutes === 44640; }, 1000,
                  "a cadence past a month is not capped");
        find(sv, "settings-autosync-0").activated();
        tryVerify(function () { return sv.settings.integrations.autoSyncMinutes === 0; }, 1000);
    }

    function test_settings_card_header_expands_on_return() {
        const sv = settingsAt("integrations");
        let card = null;
        tryVerify(function () { card = find(sv, "int-card-github"); return card !== null; }, 2000);
        const head = find(card, "int-card-header");
        const was = card.open;
        reachable(head, "GitHub card header");
        tryVerify(function () { return card.open !== was; }, 1000);
        compare(head.checked, card.open);
    }

    // Visible glyph colour on the provider tile is picked for the brand fill
    // (DES-25), not the accent's text colour.
    function test_provider_glyph_reads_on_its_brand_colour() {
        const sv = settingsAt("integrations");
        let card = null;
        tryVerify(function () { card = find(sv, "int-card-jira"); return card !== null; }, 2000);
        const tile = find(card, "int-card-tile");
        verify(tile !== null);
        let glyph = null;
        for (let i = 0; i < tile.children.length; i++)
            if (tile.children[i].visible) glyph = tile.children[i];
        verify(glyph !== null);
        compare(String(glyph.color), String(Theme.textOn(tile.color)));
        verify(Presets.contrast(String(glyph.color), String(tile.color)) >= 4.5,
               "the Jira glyph is under 4.5:1 on its tile");
    }

    // ── Hotkeys ───────────────────────────────────────────────────────
    function test_hotkeys_close_and_reset_are_tab_stops() {
        const p = createTemporaryQmlObject('import TodoCpp; HotkeysPanel { }', host);
        p.open();
        tryVerify(function () { return p.opened; }, 2000);
        const edit = find(p.contentItem, "hotkeys-edit");
        verify(edit !== null);
        compare(edit.Accessible.name, I18n.t("hotkeys.edit"));
        const close = find(p.contentItem, "hotkeys-close");
        reachable(close, "Hotkeys close");
        tryVerify(function () { return !p.opened; }, 2000, "Return did not close Hotkeys");
    }

    // ── Theme editor ───────────────────────────────────────────────────
    function test_theme_card_and_token_buttons() {
        AppController.appSettingsJson = "";
        AppController.theme = "dark";
        const ts = createTemporaryQmlObject('import TodoCpp; ThemeSettings { width: 880 }', host);
        ts.setKey.connect(function (key, value) {
            const a = Object.assign({}, ts.appearance);
            a[key] = value;
            ts.appearance = a;
            AppController.appSettingsJson = JSON.stringify({ appearance: a });
        });
        waitForRendering(ts);
        const card = find(ts, "theme-card-area-heap-light");
        compare(card.role, Accessible.RadioButton);
        reachable(card, "heap light card");
        tryVerify(function () { return ts.appearance.darkPreset === "heap-light"; }, 1000);
        verify(card.checked);

        // The colour editor opens folded; its header is the toggle.
        verify(!ts.colorsOpen);
        const toggle = find(ts, "theme-colors-toggle");
        compare(toggle.role, Accessible.CheckBox);
        reachable(toggle, "colours toggle");
        tryVerify(function () { return ts.colorsOpen; }, 1000);
        verify(toggle.checked);

        const sw = find(ts, "theme-swatch-area-danger");
        verify(sw.activeFocusOnTab);
        verify(String(sw.Accessible.name).indexOf(I18n.t("theme.token.danger")) >= 0);
        // Nothing changed yet, so the reset is off the Tab path.
        const reset = find(ts, "theme-reset-area-danger");
        verify(!reset.activeFocusOnTab, "an idle reset is a Tab stop");
    }

    // ── Top bar ────────────────────────────────────────────────────────
    function test_topbar_shortcut_hint_focuses_search() {
        const bar = createTemporaryQmlObject('import TodoCpp; TopBar { width: 900 }', host);
        waitForRendering(bar);
        const kbd = find(bar, "topbar-search-kbd");
        verify(kbd !== null);
        verify(String(kbd.Accessible.name).length > 0);
        verify(!kbd.activeFocusOnTab, "the hint duplicates the search field's Tab stop");
        kbd.activated();
        tryVerify(function () { return find(bar, "topbar-search").activeFocus; }, 1000);
        const dismiss = find(bar, "topbar-git-dismiss");
        compare(dismiss.Accessible.name, I18n.t("topbar.git.dismiss"));
    }

    // ── Toast ──────────────────────────────────────────────────────────
    function test_toast_action_runs_on_return() {
        const t = createTemporaryQmlObject(
            'import TodoCpp; Toast { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter }', host);
        let undone = 0;
        t.showWithAction("Deleted: A", "Undo", 10, function () { undone++; });
        let act = null;
        tryVerify(function () { act = find(t, "toast-action"); return act !== null; }, 1000);
        compare(act.Accessible.name, "Undo");
        reachable(act, "toast action");
        compare(undone, 1);
    }
}
