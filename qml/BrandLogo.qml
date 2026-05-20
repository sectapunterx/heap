// heap. — reusable lockup component rendered with native QML primitives.
// Drawing the mark with Rectangle + Canvas (lines) avoids depending on
// Qt6::Svg / the qsvg image-format plugin, so the brand always renders
// even on minimal Qt installs.
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

    // Theme-resolved colors.
    readonly property color _fillColor:   theme === "light" ? Brand.lightAccent
                                        : theme === "mono"  ? monoColor
                                        :                     Brand.accent
    readonly property color _strokeColor: theme === "light" ? "#5f6878"
                                        : theme === "mono"  ? monoColor
                                        :                     "#8a94a3"
    readonly property color _textColor:   theme === "light" ? Brand.lightText
                                        : theme === "mono"  ? monoColor
                                        :                     Brand.text

    // ── Mark — root + 2 leaf rectangles wired by 2 diagonal connectors ──
    Item {
        id: markBox
        visible: root.variant !== "wordmark"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.height
        height: root.height

        // Connectors (the "tree" wiring) — drawn via Canvas because diagonal
        // lines aren't ergonomic with plain Rectangle.
        Canvas {
            id: wiring
            anchors.fill: parent
            // Repaint whenever theme/size changes so colors and stroke width
            // stay in sync with surrounding context.
            property color strokeColor: root._strokeColor
            onStrokeColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const s = width / 100.0;       // SVG was 100x100
                ctx.strokeStyle = strokeColor;
                ctx.globalAlpha = 0.4;
                ctx.lineWidth   = Math.max(1, 2 * s);
                ctx.lineCap     = "round";
                ctx.beginPath();
                ctx.moveTo(50 * s, 26 * s); ctx.lineTo(26 * s, 60 * s);
                ctx.moveTo(50 * s, 26 * s); ctx.lineTo(74 * s, 60 * s);
                ctx.stroke();
            }
        }

        // Root node — filled with accent.
        Rectangle {
            x: parent.width * 0.36
            y: parent.height * 0.08
            width:  parent.width * 0.28
            height: parent.height * 0.20
            radius: Math.max(2, width * 0.18)
            color: root._fillColor
        }
        // Left leaf — outlined.
        Rectangle {
            x: parent.width * 0.10
            y: parent.height * 0.60
            width:  parent.width * 0.28
            height: parent.height * 0.20
            radius: Math.max(2, width * 0.18)
            color: "transparent"
            border.color: root._strokeColor
            border.width: Math.max(1, parent.width * 0.025)
            opacity: 0.75
        }
        // Right leaf — outlined.
        Rectangle {
            x: parent.width * 0.62
            y: parent.height * 0.60
            width:  parent.width * 0.28
            height: parent.height * 0.20
            radius: Math.max(2, width * 0.18)
            color: "transparent"
            border.color: root._strokeColor
            border.width: Math.max(1, parent.width * 0.025)
            opacity: 0.75
        }
    }

    // ── Wordmark — "heap" with an accent-tinted period ────────────────
    Text {
        visible: root.variant !== "mark"
        anchors.left: markBox.visible ? markBox.right : parent.left
        anchors.leftMargin: markBox.visible ? Math.round(parent.height * 0.18) : 0
        anchors.verticalCenter: parent.verticalCenter
        // RichText so the accent dot stays brand-colored while "heap" follows
        // the surface text color.
        textFormat: Text.RichText
        text: "heap<span style=\"color:" + root._fillColor + "\">.</span>"
        color: root._textColor
        font.family: Brand.fontMono
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(root.height * 0.72)
        font.letterSpacing: -0.5
    }
}
