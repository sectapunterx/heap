// Tests for qml/TweaksPanel.qml — the compact Tweaks popup.
// Surface: readonly accentSwatches, and the settings-shadow functions
// (_reload / _setAppearance / _appearanceValue) that round-trip through the
// live AppController.appSettingsJson. No objectName / root signal exists, so
// there are no click- or signal-contract layers here.
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

    // accentSwatches is the fixed chip palette mirrored from the Settings accent
    // picker: exactly 7 hex colors, stable order.
    function test_accent_swatches() {
        const p = make('import TodoCpp; TweaksPanel { }');
        compare(p.accentSwatches.length, 7);
        compare(String(p.accentSwatches[0]).toLowerCase(), "#5cc2dd");
        compare(String(p.accentSwatches[6]).toLowerCase(), "#9aa3b4");
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
}
