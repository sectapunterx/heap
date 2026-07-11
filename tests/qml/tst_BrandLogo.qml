// Property/theme-contract tests for qml/BrandLogo.qml (native-QML brand lockup).
// BrandLogo has no signals, functions, or objectName — it is a pure visual
// component, so coverage is smoke-load + variant/aspect + theme→color resolution.
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

    // Smoke: the component instantiates against the live TodoCpp module and
    // lands on its documented defaults (horizontal "lockup", dark theme).
    function test_smoke_load() {
        const bl = make('import TodoCpp; BrandLogo { }');
        compare(bl.variant, "lockup");
        compare(bl.theme, "dark");
    }

    // Native aspect-ratio constants mirror the original SVG geometry and drive
    // implicitWidth. 380/100 = 3.8, 280/90 ≈ 3.11, mark is square.
    function test_aspect_ratio_constants() {
        const bl = make('import TodoCpp; BrandLogo { }');
        compare(bl.lockupAspect, 3.8);
        compare(bl.wordmarkAspect, 3.11);
        compare(bl.markAspect, 1.0);
    }

    // implicitWidth = implicitHeight * aspect, and the variant selects which
    // aspect. Default implicitHeight is 28 → 106.4 / 28 / 87.08.
    function test_implicit_width_by_variant() {
        const bl = make('import TodoCpp; BrandLogo { }');
        compare(bl.implicitHeight, 28);

        bl.variant = "lockup";
        verify(Math.abs(bl.implicitWidth - 28 * 3.8) < 0.01,
               "lockup implicitWidth should be height*lockupAspect");

        bl.variant = "mark";
        verify(Math.abs(bl.implicitWidth - 28 * 1.0) < 0.01,
               "mark implicitWidth should be square (height*markAspect)");

        bl.variant = "wordmark";
        verify(Math.abs(bl.implicitWidth - 28 * 3.11) < 0.01,
               "wordmark implicitWidth should be height*wordmarkAspect");
    }

    // Dark theme (default): quiet slate ink, white crown, near-white text.
    function test_colors_dark_theme() {
        const bl = make('import TodoCpp; BrandLogo { theme: "dark" }');
        verify(Qt.colorEqual(bl._inkColor,   "#c6d0dc"), "dark ink");
        verify(Qt.colorEqual(bl._crownColor, "#ffffff"), "dark crown");
        verify(Qt.colorEqual(bl._textColor,  "#e8eef4"), "dark text");
    }

    // Light theme inverts: darker ink, near-black crown and text.
    function test_colors_light_theme() {
        const bl = make('import TodoCpp; BrandLogo { theme: "light" }');
        verify(Qt.colorEqual(bl._inkColor,   "#404b58"), "light ink");
        verify(Qt.colorEqual(bl._crownColor, "#0b0e13"), "light crown");
        verify(Qt.colorEqual(bl._textColor,  "#0b0e13"), "light text");
    }

    // Mono theme collapses every part of the mark to monoColor.
    function test_colors_mono_theme() {
        const bl = make('import TodoCpp; BrandLogo { theme: "mono" }');
        bl.monoColor = "#ff0000";
        verify(Qt.colorEqual(bl._inkColor,   "#ff0000"), "mono ink follows monoColor");
        verify(Qt.colorEqual(bl._crownColor, "#ff0000"), "mono crown follows monoColor");
        verify(Qt.colorEqual(bl._textColor,  "#ff0000"), "mono text follows monoColor");
    }

    // monoColor defaults to the Brand singleton's text color.
    function test_mono_color_default_is_brand_text() {
        const bl = make('import TodoCpp; BrandLogo { }');
        verify(Qt.colorEqual(bl.monoColor, Brand.text),
               "monoColor should default to Brand.text");
    }
}
