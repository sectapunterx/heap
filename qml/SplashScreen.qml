// heap. — splash screen for Qt 6 / QML
//
// Drop-in replacement for the "06 · Splash" artboard from the brand book.
// Designed at 1280×800 but scales gracefully — anchor it to fill any window.
//
// Usage (in main.qml):
//
//     Window {
//         id: root
//         visible: true
//         width: 1280; height: 800
//         color: Brand.bg
//
//         SplashScreen {
//             id: splash
//             anchors.fill: parent
//             onFinished: { /* hide splash, show main UI */ }
//         }
//     }
//
// Or as a separate Window (frameless) shown until QQmlApplicationEngine
// finishes loading the main scene.

import QtQuick
import TodoCpp

Item {
    id: root

    // Public knobs
    property real progress: 0.0          // 0..1; bind to your loader's progress
    property string status: "initializing allocator…"
    property string buildInfo: "v" + AppController.appVersion
    property string channel: "stable · channel"
    property bool autoAnimate: true      // demo: animate the loading bar
    property int autoDuration: 1200

    signal finished()

    // Background
    Rectangle { anchors.fill: parent; color: Brand.bg }

    // Subtle grid pattern
    Canvas {
        anchors.fill: parent
        opacity: 0.6
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.strokeStyle = "rgba(255,255,255,0.025)";
            ctx.lineWidth = 1;
            var step = 48;
            for (var x = 0; x <= width; x += step) {
                ctx.beginPath(); ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, height); ctx.stroke();
            }
            for (var y = 0; y <= height; y += step) {
                ctx.beginPath(); ctx.moveTo(0, y + 0.5); ctx.lineTo(width, y + 0.5); ctx.stroke();
            }
        }
    }

    // Radial accent glow (simulated by a soft circle with low opacity)
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(parent.width, parent.height) * 0.9
        height: width
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.231, 0.800, 0.866, 0.10) }
            GradientStop { position: 0.55; color: "transparent" }
        }
    }

    // ── Centered content ──────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 34

        // Logo lockup
        BrandLogo {
            anchors.horizontalCenter: parent.horizontalCenter
            variant: "lockup"
            height: 92
        }

        // Tagline: Work, in one place.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Brand.tagline
            color: Brand.brandInk
            font.family: Brand.fontSans
            font.pixelSize: 14
            font.letterSpacing: 0.2
        }

        // Loading bar
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 200; height: 3

            Rectangle {                          // track
                anchors.fill: parent
                radius: 1.5
                color: Brand.border
            }

            Rectangle {                          // fill
                id: fill
                height: parent.height
                radius: 1.5
                width: parent.width * Math.max(0, Math.min(1, root.progress))
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(0.231, 0.800, 0.866, 0) }
                    GradientStop { position: 0.5; color: Brand.accent }
                    GradientStop { position: 1.0; color: Qt.rgba(0.231, 0.800, 0.866, 0) }
                }
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }

        // Status line
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Text { text: "$"; color: Brand.text4; font.family: Brand.fontMono; font.pixelSize: 11 }
            Text { text: root.status; color: Brand.text3; font.family: Brand.fontMono; font.pixelSize: 11 }
        }
    }

    // ── Footer rail ───────────────────────────────────────────
    Text {
        anchors.left: parent.left; anchors.bottom: parent.bottom
        anchors.margins: 32
        text: root.buildInfo.toUpperCase()
        color: Brand.text4
        font.family: Brand.fontMono
        font.pixelSize: 10
        font.letterSpacing: 1
    }
    Text {
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 32
        text: root.channel.toUpperCase()
        color: Brand.text4
        font.family: Brand.fontMono
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    // ── Demo auto-animation (disable in production: autoAnimate: false) ─
    NumberAnimation on progress {
        running: root.autoAnimate
        from: 0; to: 1
        duration: root.autoDuration
        easing.type: Easing.InOutCubic
        onFinished: root.finished()
    }
}
