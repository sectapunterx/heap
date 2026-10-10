// Contract tests for qml/BrandLogo.qml — the lowkey mark and wordmark drawn
// with native QML (APP-280): variants, sizing and theme → colour.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "BrandLogo"
    when: windowShown
    visible: true
    width: 400
    height: 300

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function find(it, name) {
        if (it.objectName === name) return it;
        for (let i = 0; i < it.children.length; i++) {
            const r = find(it.children[i], name);
            if (r) return r;
        }
        return null;
    }

    // The wordmark is the logo by default, on the dark theme.
    function test_smoke_load() {
        const bl = make('import TodoCpp; BrandLogo { }');
        compare(bl.variant, "wordmark");
        compare(bl.theme, "dark");
        compare(find(bl, "brand-wordmark").text, "lowkey");
    }

    // The mark's box follows the glyph's 342 × 380 proportion; the wordmark
    // takes the width its text needs; the lockup is both, with a gap.
    function test_implicit_width_by_variant() {
        const bl = make('import TodoCpp; BrandLogo { height: 40 }');
        bl.variant = "mark";
        compare(bl.implicitWidth, Math.round(40 * 342 / 380));
        bl.variant = "wordmark";
        const word = find(bl, "brand-wordmark");
        compare(bl.implicitWidth, Math.ceil(word.contentWidth));
        verify(bl.implicitWidth > 40 * 2, "the wordmark is wide: " + bl.implicitWidth);
        bl.variant = "lockup";
        verify(bl.implicitWidth > Math.ceil(word.contentWidth) + Math.round(40 * 342 / 380),
               "the lockup holds the mark and the wordmark side by side");
    }

    // Lavender bar, near-white ink on dark; darker lavender and near-black on light.
    function test_colors_by_theme() {
        const dark = make('import TodoCpp; BrandLogo { theme: "dark" }');
        verify(Qt.colorEqual(dark._ink, "#e9edf2"), "dark ink");
        verify(Qt.colorEqual(dark._bar, "#b1a7f0"), "dark bar");
        const light = make('import TodoCpp; BrandLogo { theme: "light" }');
        verify(Qt.colorEqual(light._ink, "#0c0e11"), "light ink");
        verify(Qt.colorEqual(light._bar, "#5a4fb3"), "light bar");
    }

    // Mono collapses the ink and the bar to one colour (tray, print).
    function test_colors_mono_theme() {
        const bl = make('import TodoCpp; BrandLogo { theme: "mono" }');
        bl.monoColor = "#ff0000";
        verify(Qt.colorEqual(bl._ink, "#ff0000"), "mono ink follows monoColor");
        verify(Qt.colorEqual(bl._bar, "#ff0000"), "mono bar follows monoColor");
    }

    function test_mono_color_default_is_brand_text() {
        const bl = make('import TodoCpp; BrandLogo { }');
        verify(Qt.colorEqual(bl.monoColor, Brand.text), "monoColor should default to Brand.text");
    }

    // The bar sits under "low" only: it starts at the word and ends before "key".
    function test_bar_underlines_low() {
        const bl = make('import TodoCpp; BrandLogo { height: 40 }');
        const word = find(bl, "brand-wordmark");
        let bar = null;
        for (let i = 0; i < word.children.length; i++)
            if (word.children[i].radius !== undefined) bar = word.children[i];
        verify(bar !== null);
        compare(bar.x, 0);
        verify(bar.width > word.contentWidth * 0.35 && bar.width < word.contentWidth * 0.6,
               "bar " + bar.width + " of " + word.contentWidth);
        verify(bar.y > word.baselineOffset, "below the baseline");
    }

    // UX-24: what is drawn stays inside the box, so centring the logo centres it.
    function test_wordmark_fits_its_box() {
        const bl = make('import TodoCpp; BrandLogo { height: 92; width: implicitWidth }');
        const word = find(bl, "brand-wordmark");
        const right = word.x + word.contentWidth;
        verify(right <= bl.width + 1, "wordmark ends at " + right + ", box is " + bl.width);
    }
}
