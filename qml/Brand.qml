// heap. — brand singleton for Qt 6 / QML
// Drop this in qml/ and register as a singleton in qt_add_qml_module().
// Then use Brand.accent, Brand.bg, Brand.fontMono, Brand.tagline, etc.

pragma Singleton
import QtQuick

QtObject {
    id: brand

    // ── Identity ──────────────────────────────────────────────
    readonly property string name:    "heap."
    readonly property string tagline: "heap.push(task)"
    readonly property string version: "0.4.2"

    // ── Color palette (dark, primary) ─────────────────────────
    readonly property color bg:        "#0b0e13"
    readonly property color bg2:       "#11151c"
    readonly property color panel:     "#14181f"
    readonly property color panel2:    "#1a1f29"
    readonly property color border:    "#262d39"

    readonly property color text:      "#e5ecf3"
    readonly property color text2:     "#b8c2cc"
    readonly property color text3:     "#8a94a3"
    readonly property color text4:     "#5f6878"

    // ── Accents ───────────────────────────────────────────────
    // accent (precise · cyan-teal)  ← oklch(0.78 0.12 205)
    readonly property color accent:     "#3bccdd"
    readonly property color accent2:    "#5fdaea"  // hover / highlight
    readonly property color accentSoft: Qt.rgba(0.231, 0.800, 0.866, 0.15)

    // ── Status / semantic colors ──────────────────────────────
    readonly property color statusTodo:       "#86a0bd"
    readonly property color statusInProgress: "#32b2e7"
    readonly property color statusReview:     "#bf94ec"
    readonly property color statusDone:       "#78be7a"
    readonly property color statusWarn:       "#fe9c3a"

    // ── Light theme (inverted) ────────────────────────────────
    readonly property color lightBg:      "#f3f5f8"
    readonly property color lightPanel:   "#ffffff"
    readonly property color lightBorder:  "#dde3ec"
    readonly property color lightText:    "#11151c"
    readonly property color lightText3:   "#5f6878"
    readonly property color lightAccent:  "#178ea0"

    // ── Typography ────────────────────────────────────────────
    readonly property string fontSans: "IBM Plex Sans"
    readonly property string fontMono: "JetBrains Mono"

    // Type scale (px)
    readonly property int sizeDisplay:  56
    readonly property int sizeH1:       32
    readonly property int sizeH2:       22
    readonly property int sizeBody:     14
    readonly property int sizeMono:     13
    readonly property int sizeCaption:  11

    // ── Geometry tokens ───────────────────────────────────────
    readonly property int radiusSm:  6
    readonly property int radiusMd:  8
    readonly property int radiusLg:  12
    readonly property int radiusPill: 999

    readonly property int spacing1:  4
    readonly property int spacing2:  8
    readonly property int spacing3:  12
    readonly property int spacing4:  16
    readonly property int spacing5:  24
    readonly property int spacing6:  32

    // ── Logo asset paths (resolved against the qrc you set up) ─
    readonly property string logoMark:       "qrc:/brand/logo/heap-mark.svg"
    readonly property string logoMarkLight:  "qrc:/brand/logo/heap-mark-light.svg"
    readonly property string logoMarkMono:   "qrc:/brand/logo/heap-mark-mono.svg"
    readonly property string logoLockup:     "qrc:/brand/logo/heap-lockup.svg"
    readonly property string logoLockupLight:"qrc:/brand/logo/heap-lockup-light.svg"
    readonly property string logoWordmark:   "qrc:/brand/logo/heap-wordmark.svg"
    readonly property string appIcon:        "qrc:/brand/icon/heap-icon.svg"
}
