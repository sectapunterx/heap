// Brand (qml/Brand.qml): a pragma-Singleton token bank (no signals/functions/
// objectName), so this pins the public design-token contract the rest of the
// app binds to — Theme.qml maps straight onto Brand, SplashScreen/BrandLogo/
// SettingsView read it by name. Accessed as `Brand.x` (never instantiated).
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "Brand"
    when: windowShown
    visible: true
    width: 400
    height: 400

    Item { id: host; anchors.fill: parent }

    // ── Identity ──────────────────────────────────────────────
    // The wordmark + taglines callers render verbatim (SplashScreen.qml,
    // SettingsView.qml bind Brand.tagline; the "." in "heap." is load-bearing).
    function test_identity_strings() {
        compare(Brand.name, "heap.");
        compare(Brand.tagline, "Work, in one place.");
        compare(Brand.taglineLong, "A quiet place for the work you owe.");
        verify(Brand.name.length > 0);
        verify(Brand.tagline.length > 0);
        verify(Brand.taglineLong.length > 0);
    }

    // ── Typography ────────────────────────────────────────────
    function test_font_families() {
        compare(Brand.fontSans, "IBM Plex Sans");
        compare(Brand.fontMono, "JetBrains Mono");
        verify(Brand.fontSans.length > 0);
        verify(Brand.fontMono.length > 0);
    }

    // Core palette tokens are fully opaque — Theme composites panels/text on top
    // of these, so any accidental alpha would bleed through everywhere.
    function test_core_palette_opaque() {
        const opaque = [
            Brand.bg, Brand.bg2, Brand.panel, Brand.panel2, Brand.border,
            Brand.text, Brand.text2, Brand.text3, Brand.text4,
            Brand.accent, Brand.accent2,
            Brand.lightBg, Brand.lightPanel, Brand.lightBorder,
            Brand.lightText, Brand.lightText3, Brand.lightAccent
        ];
        for (let i = 0; i < opaque.length; ++i)
            fuzzyCompare(opaque[i].a, 1.0, 0.001, "palette color #" + i + " must be opaque");
    }

    // accentSoft is deliberately the accent color at a low alpha (used for
    // tinted fills). Pin both halves: same hue as accent, ~15% opacity.
    function test_accent_soft_is_accent_tint() {
        fuzzyCompare(Brand.accentSoft.a, 0.15, 0.005, "accentSoft must be a ~15% tint");
        fuzzyCompare(Brand.accentSoft.r, Brand.accent.r, 0.01, "accentSoft red must track accent");
        fuzzyCompare(Brand.accentSoft.g, Brand.accent.g, 0.01, "accentSoft green must track accent");
        fuzzyCompare(Brand.accentSoft.b, Brand.accent.b, 0.01, "accentSoft blue must track accent");
        // A tint, not the solid accent: the alpha genuinely differs.
        verify(Brand.accentSoft.a < Brand.accent.a);
    }

    // The text ramp text→text2→text3→text4 must dim monotonically on every
    // channel (dark-theme text hierarchy — brightest primary, dimmest quaternary).
    function test_text_ramp_dims_monotonically() {
        const ramp = [Brand.text, Brand.text2, Brand.text3, Brand.text4];
        for (let i = 1; i < ramp.length; ++i) {
            verify(ramp[i].r < ramp[i - 1].r, "text ramp red must decrease at step " + i);
            verify(ramp[i].g < ramp[i - 1].g, "text ramp green must decrease at step " + i);
            verify(ramp[i].b < ramp[i - 1].b, "text ramp blue must decrease at step " + i);
        }
    }

    // Type scale is strictly descending display→caption, with the exact px the
    // components hardcode against (e.g. sizeBody 14 / sizeCaption 11).
    function test_type_scale_descending() {
        compare(Brand.sizeDisplay, 56);
        compare(Brand.sizeH1, 32);
        compare(Brand.sizeH2, 22);
        compare(Brand.sizeBody, 14);
        compare(Brand.sizeMono, 13);
        compare(Brand.sizeCaption, 11);
        const scale = [Brand.sizeDisplay, Brand.sizeH1, Brand.sizeH2,
                       Brand.sizeBody, Brand.sizeMono, Brand.sizeCaption];
        for (let i = 1; i < scale.length; ++i)
            verify(scale[i] < scale[i - 1], "type scale must strictly descend at step " + i);
    }

    // Spacing scale is strictly ascending on the 4px grid Theme.pad/gap select
    // from (spacing2 / spacing3 / spacing4).
    function test_spacing_scale_ascending() {
        compare(Brand.spacing1, 4);
        compare(Brand.spacing2, 8);
        compare(Brand.spacing3, 12);
        compare(Brand.spacing4, 16);
        compare(Brand.spacing5, 24);
        compare(Brand.spacing6, 32);
        const s = [Brand.spacing1, Brand.spacing2, Brand.spacing3,
                   Brand.spacing4, Brand.spacing5, Brand.spacing6];
        for (let i = 1; i < s.length; ++i)
            verify(s[i] > s[i - 1], "spacing must strictly ascend at step " + i);
    }

    // Radius scale ascends sm→md→lg, and radiusPill is the "always fully round"
    // sentinel (>= any plausible half-height).
    function test_radius_scale() {
        compare(Brand.radiusSm, 6);
        compare(Brand.radiusMd, 8);
        compare(Brand.radiusLg, 12);
        compare(Brand.radiusPill, 999);
        verify(Brand.radiusSm < Brand.radiusMd);
        verify(Brand.radiusMd < Brand.radiusLg);
        verify(Brand.radiusLg < Brand.radiusPill);
    }

    // Status colors are opaque and pairwise distinct — the board/kanban legend
    // relies on todo/in-progress/review/done/warn being visually separable.
    function test_status_colors_opaque_and_distinct() {
        const st = [Brand.statusTodo, Brand.statusInProgress, Brand.statusReview,
                    Brand.statusDone, Brand.statusWarn];
        for (let i = 0; i < st.length; ++i)
            fuzzyCompare(st[i].a, 1.0, 0.001, "status color #" + i + " must be opaque");
        for (let i = 0; i < st.length; ++i)
            for (let j = i + 1; j < st.length; ++j)
                verify(!Qt.colorEqual(st[i], st[j]),
                       "status colors " + i + " and " + j + " must differ");
    }

    // Logo/icon asset refs are declared as non-empty qrc: strings (the paths
    // themselves are a known dead-resource issue — only the contract that these
    // properties exist and are resource URLs is asserted here).
    function test_asset_paths_are_declared_qrc_strings() {
        const paths = [
            Brand.logoMark, Brand.logoMarkLight, Brand.logoMarkMono,
            Brand.logoLockup, Brand.logoLockupLight,
            Brand.logoWordmark, Brand.logoWordmarkLight,
            Brand.appIcon, Brand.favicon
        ];
        for (let i = 0; i < paths.length; ++i) {
            verify(paths[i].length > 0, "asset path #" + i + " must be non-empty");
            verify(paths[i].indexOf("qrc:") === 0, "asset path #" + i + " must be a qrc: url");
        }
    }

    // Brand identity tokens are quieter than the product accent/text on purpose
    // (design intent: identity sits behind the product). brandInk is dimmer than
    // primary text; iconInk pushes one stop dimmer still for the app squircle.
    function test_identity_tokens_are_quieter_than_product() {
        // brandInk should be darker/quieter than the primary text.
        verify(Brand.brandInk.r < Brand.text.r, "brandInk must be quieter than primary text");
        // iconInk is a further stop down from brandInk for dock/taskbar contrast.
        verify(Brand.iconInk.r < Brand.brandInk.r, "iconInk must be quieter than brandInk");
        // The identity accent is muted relative to the product accent.
        verify(Brand.brandAccent.g < Brand.accent.g, "brandAccent must be muted vs product accent");
    }

    // Integration (read-only): Theme maps straight onto Brand for the tokens with
    // no high-contrast branch — bg / panel / textMuted must equal the Brand token
    // selected by the live Theme.dark flag. Reads Theme without mutating it.
    function test_theme_pulls_tokens_from_brand() {
        verify(Qt.colorEqual(Theme.bg, Theme.dark ? Brand.bg : Brand.lightBg),
               "Theme.bg must resolve to the Brand bg for the active mode");
        verify(Qt.colorEqual(Theme.panel, Theme.dark ? Brand.panel : Brand.lightPanel),
               "Theme.panel must resolve to the Brand panel for the active mode");
        verify(Qt.colorEqual(Theme.textMuted, Theme.dark ? Brand.text3 : Brand.lightText3),
               "Theme.textMuted must resolve to the Brand muted text for the active mode");
    }
}
