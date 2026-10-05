// Settings → Appearance → Theme (qml/ThemeSettings.qml): picking a theme per
// slot, editing a token (a built-in is copied first), reset, import, delete.
// The harness plays SettingsView: every setKey lands in settings.appearance
// and in AppController.appSettingsJson, which is what Theme repaints from.
import QtQuick
import QtTest
import TodoCpp
import "../../qml/ThemePresets.js" as Presets

TestCase {
    id: tc
    name: "ThemeSettings"
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
        AppController.appSettingsJson = "";
        AppController.theme = "dark";
    }
    function cleanup() {
        AppController.appSettingsJson = savedSettings;
        AppController.theme = savedTheme;
    }

    function make() {
        const ts = createTemporaryQmlObject('import TodoCpp; ThemeSettings { width: 880 }', host);
        verify(ts !== null);
        ts.setKey.connect(function (key, value) {
            const a = Object.assign({}, ts.appearance);
            a[key] = value;
            ts.appearance = a;
            AppController.appSettingsJson = JSON.stringify({ appearance: a });
        });
        // Theme cards wrap onto more rows than one; the Flow places them on
        // polish, so a click before that lands on whatever sits there first.
        waitForRendering(ts);
        return ts;
    }

    function test_a_card_click_fills_the_showing_slot() {
        const ts = make();
        const card = findChild(ts, "theme-card-heap-light");
        verify(card !== null);
        mouseClick(card);
        compare(ts.appearance.darkPreset, "heap-light");
        compare(ts.appearance.lightPreset, undefined);
        compare(Theme.activePresetId, "heap-light");
        compare(String(Theme.bg), "#f3f5f8");
    }

    // APP-119: the picker groups themes by contrast. Every built-in names its
    // group, a copy follows its source, and a theme with no source is measured.
    function test_themes_are_grouped_by_contrast() {
        const ts = make();
        const high = findChild(ts, "theme-cards-high");
        const low = findChild(ts, "theme-cards-low");
        verify(high !== null && low !== null);
        for (const id of ["heap-dark", "heap-light", "heap-ink", "crimson", "graphite"])
            compare(Presets.category(Presets.builtin(id), []), "high", id);
        for (const id of ["ochre", "fjord", "dusk", "minimal-dark"])
            compare(Presets.category(Presets.builtin(id), []), "low", id);
        for (const t of Presets.PRESETS)
            verify(t.contrast === "high" || t.contrast === "low", t.id + " has no contrast group");

        const copy = ts.duplicate("dusk");
        compare(Presets.category(ts._custom(copy), ts.customs), "low");
        const lowCards = ts.themes.filter((t) => Presets.category(t, ts.customs) === "low").map((t) => t.id);
        verify(lowCards.indexOf(copy) >= 0, "a copy of Dusk is not under low contrast");

        compare(Presets.category({ colors: { text: "#ffffff", bg: "#000000" } }, []), "high");
        compare(Presets.category({ colors: { text: "#9a9a9a", bg: "#202020" } }, []), "low");
        // a copy-of-a-copy cycle must not hang
        compare(Presets.category({ id: "a", from: "b", colors: { text: "#ffffff", bg: "#000000" } },
                                 [{ id: "b", from: "a" }]), "high");
    }

    // The colour editor opens folded; the header unfolds it.
    function test_colour_editor_folds() {
        const ts = make();
        verify(!ts.colorsOpen);
        const row = findChild(ts, "theme-token-danger");
        verify(row !== null);
        verify(!row.parent.parent.visible, "token rows show while folded");
        mouseClick(findChild(ts, "theme-colors-header"));
        verify(ts.colorsOpen);
        tryVerify(() => row.parent.parent.visible);
    }

    // Editing a built-in leaves it alone: a copy is made, put in the slot,
    // and carries the edit.
    function test_editing_a_builtin_edits_a_copy() {
        const ts = make();
        const hex = findChild(ts, "theme-hex-danger");
        verify(hex !== null);
        hex.text = "#ff00aa";
        hex.accepted();

        compare(ts.customs.length, 1);
        const id = ts.customs[0].id;
        compare(ts.appearance.darkPreset, id);
        compare(ts.customs[0].from, "heap-dark");
        compare(ts.customs[0].base, "dark");
        compare(String(Theme.danger), "#ff00aa");
        // everything else is still heap. dark
        compare(String(Theme.bg), "#0b0e13");
        // a second edit lands on the same copy
        ts.setToken("warning", "#123456");
        compare(ts.customs.length, 1);
        compare(String(Theme.warning), "#123456");
    }

    function test_reset_returns_a_token_to_its_origin() {
        const ts = make();
        ts.setToken("success", "#010203");
        compare(String(Theme.success), "#010203");
        ts.resetToken("success");
        compare(String(Theme.success), "#78be7a");
    }

    function test_an_invalid_hex_is_not_stored() {
        const ts = make();
        ts.setToken("danger", "red");
        compare(ts.customs.length, 0);
        compare(String(Theme.danger), "#e6624c");
    }

    function test_import_adds_a_theme_and_rejects_junk() {
        const ts = make();
        verify(!ts.importText("{ nope"));
        verify(ts.importError.length > 0);
        verify(!ts.importText(JSON.stringify({ colors: { nope: "#123456" } })));
        compare(ts.customs.length, 0);

        verify(ts.importText(JSON.stringify({ name: "Paper", base: "light", colors: { bg: "#fafafa", danger: "#aa0000" } })));
        compare(ts.importError, "");
        compare(ts.customs.length, 1);
        compare(ts.customs[0].name, "Paper");
        compare(Theme.activePresetId, ts.customs[0].id);
        compare(String(Theme.bg), "#fafafa");
        compare(String(Theme.danger), "#aa0000");
        // tokens the file did not name come from heap. light
        compare(String(Theme.panel), "#ffffff");
        compare(Theme.dark, false);
    }

    function test_deleting_the_theme_in_a_slot_resets_that_slot() {
        const ts = make();
        const id = ts.duplicate("heap-dark");
        compare(Theme.activePresetId, id);
        ts.remove(id);
        compare(ts.customs.length, 0);
        compare(ts.appearance.darkPreset, "heap-dark");
        compare(Theme.activePresetId, "heap-dark");
        // built-ins cannot be deleted
        ts.remove("heap-dark");
        compare(Theme.activePresetId, "heap-dark");
    }

    // UX-28: deleting a copy lands the slot on the theme it was copied from,
    // not on heap. dark — a copy of a copy included.
    function test_deleting_a_copy_falls_back_to_its_source() {
        const ts = make();
        ts.pick("crimson");
        const copy = ts.duplicate("crimson");
        const copyOfCopy = ts.duplicate(copy);
        compare(Theme.activePresetId, copyOfCopy);
        ts.remove(copyOfCopy);
        compare(ts.appearance.darkPreset, "crimson");
        ts.pick(copy);
        ts.remove(copy);
        compare(Theme.activePresetId, "crimson");
    }

    // APP-127: a second copy of the same theme is "… (2)", not a twin.
    function test_a_second_copy_gets_a_number() {
        const ts = make();
        const a = ts.duplicate("heap-dark");
        const b = ts.duplicate("heap-dark");
        const first = ts._custom(a).name;
        compare(ts._custom(b).name, first + " (2)");
    }

    function test_rename_and_base() {
        const ts = make();
        ts.duplicate("heap-dark");
        ts.rename("  Night  ");
        compare(ts.current.name, "Night");
        ts.setBase("light");
        compare(ts.customs[0].base, "light");
        compare(Theme.dark, false);
    }

    // The editor offers a row for every token, grouped.
    function test_every_token_has_a_row() {
        const ts = make();
        for (const key of ["bg", "danger", "toastBg", "scrim", "p0", "stBlocked", "nowLine", "synKeyword", "mdLink", "textOnAccent"])
            verify(findChild(ts, "theme-token-" + key) !== null, key + " row missing");
    }
}
