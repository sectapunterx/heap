// heap. — reusable lockup component rendered with native QML primitives.
// The mark is the "stack" glyph: three stacked rounded bars (widest base,
// brighter crown). Drawing it with plain Rectangles avoids depending on
// Qt6::Svg / the qsvg image-format plugin, so the brand always renders even
// on minimal Qt installs.
//
// Usage:
//   BrandLogo { height: 28 }                       // horizontal lockup
//   BrandLogo { variant: "mark"; height: 32 }
//   BrandLogo { variant: "wordmark"; height: 24 }

import QtQuick
import QtQuick.Layouts
import TodoCpp

Item {
    id: root

    // "lockup" | "mark" | "wordmark"
    property string variant: "lockup"
    // "dark" | "light" | "mono"
    property string theme: "dark"
    // for "mono" variant — color used for the whole mark
    property color monoColor: Brand.text

    // Native aspect ratios (px) for layout sizing — matches the original SVGs.
    readonly property real lockupAspect:   3.8   // 380 / 100
    readonly property real wordmarkAspect: 3.11  // 280 / 90
    readonly property real markAspect:     1.0

    implicitHeight: 28
    implicitWidth: implicitHeight * (variant === "lockup"   ? lockupAspect
                                  : variant === "wordmark" ? wordmarkAspect
                                                           : markAspect)

    // Theme-resolved colors for the monochrome "stack" mark. On dark surfaces
    // the glyph is a quiet slate with a brighter (white) crown bar; on light it
    // inverts to near-black. "mono" collapses everything to monoColor.
    readonly property color _inkColor:   theme === "light" ? "#404b58"
                                       : theme === "mono"  ? monoColor
            : "#c6d0dc"
    readonly property color _crownColor: theme === "light" ? "#0b0e13"
                                       : theme === "mono"  ? monoColor
            : "#ffffff"
    readonly property color _textColor:  theme === "light" ? "#0b0e13"
                                       : theme === "mono"  ? monoColor
            : "#e8eef4"

    // ── Mark — three stacked bars (widest base → brighter crown) ──
    Item {
        id: markBox
        visible: root.variant !== "wordmark"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.height
        height: root.height

        // Geometry mirrors the 32-unit brand grid; radius = half the bar
        // height for fully rounded ends. Base + middle share the ink color;
        // the crown is the brighter accent bar.
        Rectangle {   // base — widest
            x: parent.width * (5 / 32);      y: parent.height * (20 / 32)
            width: parent.width * (22 / 32); height: parent.height * (4.4 / 32)
            radius: height / 2
            color: root._inkColor
        }
        Rectangle {   // middle
            x: parent.width * (8 / 32);      y: parent.height * (13.8 / 32)
            width: parent.width * (16 / 32); height: parent.height * (4.4 / 32)
            radius: height / 2
            color: root._inkColor
        }
        Rectangle {   // crown — narrowest, brightest
            x: parent.width * (11 / 32);     y: parent.height * (7.6 / 32)
            width: parent.width * (10 / 32); height: parent.height * (4.4 / 32)
            radius: height / 2
            color: root._crownColor
        }
    }

    // ── Wordmark — "heap" with a slightly brighter period ──────────────
    Text {
        visible: root.variant !== "mark"
        anchors.left: markBox.visible ? markBox.right : parent.left
        anchors.leftMargin: markBox.visible ? Math.round(parent.height * 0.18) : 0
        anchors.verticalCenter: parent.verticalCenter
        // RichText so the period can carry the brighter crown tone while
        // "heap" follows the surface text color.
        textFormat: Text.RichText
        text: "heap<span style=\"color:" + root._crownColor + "\">.</span>"
        color: root._textColor
        font.family: Brand.fontMono
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(root.height * 0.72)
        font.letterSpacing: -0.5
    }
}
