// Tests for qml/TweaksPanel.qml — the compact Tweaks popup.
// Surface: readonly themeChoices, and the settings-shadow functions
// (_reload / _setAppearance / _appearanceValue) that round-trip through the
// live AppController.appSettingsJson; and the search (APP-210) with its
// openSettingsItem signal.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TweaksPanel"
    when: windowShown
    visible: true
    width: 500
    height: 500

    Item { id: host; anchors.fill: parent }

    // AppController.appSettingsJson is global + persisted. Snapshot before every
    // test and restore after, so a failing compare can never leak state into the
    // next test (or a later run of the shared qttest profile).
    property string _savedSettings: ""
    function init()    { _savedSettings = AppController.appSettingsJson; }
    function cleanup() { AppController.appSettingsJson = _savedSettings; }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // smoke-load: the popup instantiates against the live singletons (Theme,
    // AppController, I18n) — a renamed property or missing type would null here.
    function test_smoke_load() {
        const p = make('import TodoCpp; TweaksPanel { }');
        verify(p !== null);
    }

    // One chip per theme, built-ins included, the showing slot's base first;
    // a click puts that theme into the slot that is showing.
    function test_theme_chips_pick_for_the_showing_slot() {
        const p = make('import TodoCpp; TweaksPanel { }');
        const saved = AppController.appSettingsJson;
        const savedTheme = AppController.theme;
        AppController.theme = "dark";
        const ids = p.themeChoices.map((t) => t.id);
        const first = p.themeChoices[0].base;
        p._setAppearance("darkPreset", "heap-light");
        const active = Theme.activePresetId;
        AppController.appSettingsJson = saved;
        AppController.theme = savedTheme;

        verify(ids.indexOf("heap-dark") >= 0, "heap-dark missing");
        verify(ids.indexOf("heap-light") >= 0, "heap-light missing");
        compare(first, "dark");
        compare(active, "heap-light");
    }

    // The three-way contrast writes itself and keeps highContrast in step.
    function test_set_contrast_writes_both_keys() {
        const p = make('import TodoCpp; TweaksPanel { }');
        const saved = AppController.appSettingsJson;
        p.setContrast("soft");
        const a = JSON.parse(AppController.appSettingsJson).appearance;
        const soft = Theme.softContrast;
        p.setContrast("high");
        const b = JSON.parse(AppController.appSettingsJson).appearance;
        AppController.appSettingsJson = saved;

        compare(a.contrast, "soft");
        compare(a.highContrast, false);
        compare(soft, true);
        compare(b.contrast, "high");
        compare(b.highContrast, true);
    }

    // _appearanceValue(key, fallback): reads settings.appearance[key], falling
    // back when absent — and, crucially, an explicit `false` must survive the
    // `!== undefined` guard rather than collapsing to the fallback.
    function test_appearance_value_contract() {
        const p = make('import TodoCpp; TweaksPanel { }');

        // Empty shadow → fallback.
        p.settings = ({});
        compare(p._appearanceValue("accent", "#fallback"), "#fallback");

        // Stored value wins over fallback.
        p.settings = ({ appearance: { accent: "#abcdef" } });
        compare(p._appearanceValue("accent", "#fallback"), "#abcdef");

        // Missing key inside a present appearance object → fallback.
        compare(p._appearanceValue("highContrast", true), true);

        // Explicit false is a real value, not "undefined".
        p.settings = ({ appearance: { reducedMotion: false } });
        compare(p._appearanceValue("reducedMotion", true), false);
    }

    // _reload() re-parses AppController.appSettingsJson into the shadow.
    function test_reload_parses_json() {
        const p = make('import TodoCpp; TweaksPanel { }');
        AppController.appSettingsJson = '{"appearance":{"accent":"#0a0b0c"}}';
        p._reload();
        compare(String(p._appearanceValue("accent", "x")), "#0a0b0c");
    }

    // _reload() swallows malformed JSON and resets to an empty shadow.
    function test_reload_invalid_json_clears() {
        const p = make('import TodoCpp; TweaksPanel { }');
        AppController.appSettingsJson = "not json {";
        p._reload();
        // Empty shadow ⇒ every read returns its fallback.
        compare(p._appearanceValue("accent", "#fb"), "#fb");
    }

    // _reload() on an empty string clears the shadow (the early-return branch).
    function test_reload_empty_clears() {
        const p = make('import TodoCpp; TweaksPanel { }');
        AppController.appSettingsJson = "";
        p._reload();
        compare(p._appearanceValue("accent", "#fb"), "#fb");
    }

    // _setAppearance(key, val) writes through to AppController.appSettingsJson
    // AND leaves the shadow readable via _appearanceValue.
    function test_set_appearance_writes_through() {
        const p = make('import TodoCpp; TweaksPanel { }');
        p._setAppearance("accent", "#123456");

        const parsed = JSON.parse(AppController.appSettingsJson);
        verify(parsed.appearance !== undefined, "appearance object must be written");
        compare(parsed.appearance.accent, "#123456");
        compare(String(p._appearanceValue("accent", "x")), "#123456");
    }

    // _setAppearance merges: setting one appearance key must not drop the others,
    // and must preserve unrelated top-level settings sections.
    function test_set_appearance_preserves_existing_keys() {
        const p = make('import TodoCpp; TweaksPanel { }');

        // Seed a shadow with a sibling appearance key + an unrelated section.
        AppController.appSettingsJson =
            '{"appearance":{"accent":"#111111","reducedMotion":true},"calendar":{"weekStart":"mon"}}';
        p._reload();

        p._setAppearance("highContrast", true);

        const parsed = JSON.parse(AppController.appSettingsJson);
        compare(parsed.appearance.accent, "#111111", "sibling appearance key dropped");
        compare(parsed.appearance.reducedMotion, true, "sibling appearance key dropped");
        compare(parsed.appearance.highContrast, true, "new key not written");
        verify(parsed.calendar !== undefined, "unrelated settings section dropped");
        compare(parsed.calendar.weekStart, "mon", "unrelated settings section dropped");
    }

    // ─── Search (APP-210) ─────────────────────────────────────────────

    SignalSpy { id: openSpy; signalName: "openSettingsItem" }

    function _open() {
        const p = make('import TodoCpp; TweaksPanel { }');
        p.open();
        tryVerify(() => p.opened);
        return p;
    }
    function _shown(p, name) {
        const it = findChild(p.contentItem, name);
        return it !== null && it.visible;
    }

    // Opened, typing goes into the search.
    function test_search_is_focused_on_open() {
        const p = _open();
        const field = findChild(p.contentItem, "tweaks-search");
        verify(field !== null);
        tryVerify(() => field.activeFocus, 2000, "the search box does not have focus");
        keyClick(Qt.Key_M);
        compare(p.query, "m");
        p.close();
    }

    // A tweak's own name leaves only that row, in either language.
    function test_query_keeps_only_the_matching_tweak() {
        const p = _open();
        p.query = "motion";
        verify(_shown(p, "tweaks-reduced-motion"), "Reduced motion hidden");
        verify(!_shown(p, "tweaks-contrast"), "contrast kept for 'motion'");
        verify(!_shown(p, "tweaks-appearance"), "appearance kept for 'motion'");
        verify(!_shown(p, "tweaks-themes"), "themes kept for 'motion'");

        p.query = I18n.t("settings.appearance.contrast");
        verify(_shown(p, "tweaks-contrast"));
        verify(!_shown(p, "tweaks-reduced-motion"));
        // Already in the panel: not listed again under Settings.
        verify(p.settingsMatches.every((m) => m.key !== "settings.appearance.contrast"));
        p.close();
    }

    // A theme's name leaves only that theme.
    function test_query_by_theme_name_keeps_that_theme() {
        const p = _open();
        p.query = "crimson";
        compare(p.visibleThemes.length, 1);
        compare(p.visibleThemes[0].id, "crimson");
        verify(_shown(p, "tweaks-themes"));
        verify(findChild(p.contentItem, "tweaks-theme-heap-dark") === null, "other themes still drawn");
        p.close();
    }

    // A setting that lives only in Settings is listed as "Section → item";
    // Enter opens Settings on it (focused there) and closes the panel.
    function test_settings_hit_opens_settings_on_the_item() {
        const p = _open();
        const sv = make('import TodoCpp; SettingsView { width: 900; height: 600 }');
        sv.activeSection = "profile";
        p.openSettingsItem.connect(sv.revealItem);
        openSpy.target = p;
        openSpy.clear();
        const text = I18n.t("settings.notif.weeklyRecap");
        p.query = text;
        verify(p.settingsMatches.length >= 1, "no settings hit for " + text);
        verify(!p.tweakHits);
        verify(_shown(p, "tweaks-settings-hit-0"));
        const field = findChild(p.contentItem, "tweaks-search");
        field.forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(openSpy.count, 1);
        compare(openSpy.signalArguments[0][0].section, "notifications");
        tryVerify(() => !p.opened, 2000, "the panel stayed open");
        compare(sv.activeSection, "notifications");
        tryVerify(() => {
            const f = sv.Window.activeFocusItem;
            for (let q = f; q; q = q.parent)
                if (q.label === text && q.hasLabel !== undefined) return true;
            return false;
        }, 2000, "the setting is not focused in Settings");
        openSpy.target = null;
    }

    // Nothing anywhere: the panel says so.
    function test_nothing_found() {
        const p = _open();
        p.query = "zzqxv-no-such-tweak";
        verify(p.nothingFound);
        verify(_shown(p, "tweaks-search-empty"));
        p.query = "";
        verify(!_shown(p, "tweaks-search-empty"));
        p.close();
    }

    // Esc clears the query first; the second Esc closes the panel.
    function test_escape_clears_then_closes() {
        const p = _open();
        const field = findChild(p.contentItem, "tweaks-search");
        tryVerify(() => field.activeFocus);
        p.query = "motion";
        keyClick(Qt.Key_Escape);
        compare(p.query, "");
        verify(p.opened, "the first Esc closed the panel");
        keyClick(Qt.Key_Escape);
        tryVerify(() => !p.opened, 2000, "the second Esc did not close the panel");
    }

    // ↓ from the search walks the results, ↑ goes back up to the search.
    function test_arrows_walk_the_results() {
        const p = _open();
        const field = findChild(p.contentItem, "tweaks-search");
        tryVerify(() => field.activeFocus);
        p.query = I18n.t("settings.appearance.contrast");
        keyClick(Qt.Key_Down);
        tryVerify(() => findChild(p.contentItem, "tweaks-contrast-soft").activeFocus, 2000, "Down did not reach the first result");
        keyClick(Qt.Key_Down);
        verify(findChild(p.contentItem, "tweaks-contrast-normal").activeFocus);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Up);
        verify(field.activeFocus, "Up did not come back to the search");
        p.close();
    }

    // Typing does not change the panel's height, so it never jumps.
    function test_height_stays_put_while_typing() {
        const p = _open();
        // The theme dots wrap a frame after the panel opens.
        wait(100);
        const h = p.height;
        verify(h > 100);
        const queries = ["m", "mo", "motion", "zzqxv", "a", I18n.t("settings.notif.weeklyRecap"), ""];
        for (let i = 0; i < queries.length; i++) {
            p.query = queries[i];
            wait(0);
            compare(p.height, h, "height changed for '" + queries[i] + "'");
        }
        p.close();
    }
}
