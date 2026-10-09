// lowkey — the brand mark and wordmark, drawn with native QML primitives
// (APP-280; owner's pick 2026-10-08, logo sheet LK-06 column C). No SVG: the
// brand renders without Qt6::Svg or the qsvg plugin.
//
//   mark      an "l" with a low lavender bar (the app icon's glyph)
//   wordmark  "lowkey" in lowercase, Golos Text Medium, "low" underlined
//             by the same lavender bar
//   lockup    mark + wordmark
//
// Usage:
//   BrandLogo { variant: "wordmark"; height: 22 }
//   BrandLogo { variant: "mark"; height: 32 }

import QtQuick
import TodoCpp

Item {
    id: root

    // "wordmark" | "mark" | "lockup"
    property string variant: "wordmark"
    // "dark" | "light" | "mono"
    property string theme: "dark"
    // for "mono" — the one colour of the whole logo (the tray, a print)
    property color monoColor: Brand.text

    // Geometry of the production files (design/brand-export/lowkey,
    // geometry.json): the icon's glyph spans 342 × 380 of its 1024 grid; the
    // wordmark is 3141.9 × 925.8 font units (upem 1075), the bar sits 0.135 em
    // under the baseline and is 0.075 em thick.
    readonly property real markAspect: 342 / 380
    readonly property real wordmarkAspect: 3.39

    readonly property color _ink: theme === "light" ? "#0c0e11" : theme === "mono" ? monoColor : "#e9edf2"
    readonly property color _bar: theme === "light" ? "#5a4fb3" : theme === "mono" ? monoColor : "#b1a7f0"

    implicitHeight: 22
    implicitWidth: {
        const h = height > 0 ? height : implicitHeight;
        if (variant === "mark")
            return Math.round(h * markAspect);
        if (variant === "wordmark")
            return Math.ceil(word.contentWidth);
        return Math.round(h * markAspect) + Math.round(h * 0.4) + Math.ceil(word.contentWidth);
    }

    // ── Mark: the stem and the low bar ──
    Item {
        id: mark
        visible: root.variant !== "wordmark"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: root.height
        width: Math.round(height * root.markAspect)

        Rectangle {   // stem
            x: 0; y: 0
            width: Math.max(1, Math.round(parent.width * 76 / 342))
            height: parent.height
            radius: width / 2
            color: root._ink
        }
        Rectangle {   // bar
            x: 0
            height: Math.max(1, Math.round(parent.height * 76 / 380))
            y: parent.height - height
            width: parent.width
            radius: height / 2
            color: root._bar
        }
    }

    // ── Wordmark ──
    Text {
        id: word
        objectName: "brand-wordmark"
        visible: root.variant !== "mark"
        anchors.left: mark.visible ? mark.right : parent.left
        anchors.leftMargin: mark.visible ? Math.round(root.height * 0.4) : 0
        anchors.verticalCenter: parent.verticalCenter
        text: "lowkey"
        color: root._ink
        font.family: Brand.fontSans
        font.weight: Font.Medium
        // The x-height fills the logo's height the way the production
        // wordmark does: cap height ≈ 0.7 em.
        font.pixelSize: Math.max(8, Math.round(root.height / 0.95))
        font.letterSpacing: -font.pixelSize * 0.035

        TextMetrics {
            id: low
            font: word.font
            text: "low"
        }

        Rectangle {   // the bar under "low"
            x: 0
            width: low.advanceWidth + word.font.letterSpacing * 2
            height: Math.max(1, Math.round(word.font.pixelSize * 0.075))
            y: word.baselineOffset + Math.round(word.font.pixelSize * 0.135)
            radius: height / 2
            color: root._bar
        }
    }
}
