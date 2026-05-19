// heap. — reusable lockup component
// Usage:
//   BrandLogo { height: 28 }                       // horizontal lockup
//   BrandLogo { variant: "mark"; height: 32 }
//   BrandLogo { variant: "wordmark"; height: 24 }

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    // "lockup" | "mark" | "wordmark"
    property string variant: "lockup"
    // "dark" | "light" | "mono"
    property string theme: "dark"
    // for "mono" variant — color used for the whole mark
    property color monoColor: Brand.text

    // Native aspect ratios (px) for layout sizing
    readonly property real lockupAspect:   3.8   // 380 / 100
    readonly property real wordmarkAspect: 3.11  // 280 / 90
    readonly property real markAspect:     1.0

    implicitHeight: 28
    implicitWidth: implicitHeight * (variant === "lockup"   ? lockupAspect
                                  : variant === "wordmark" ? wordmarkAspect
                                                           : markAspect)

    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        source: {
            if (root.variant === "lockup")
                return root.theme === "light" ? Brand.logoLockupLight : Brand.logoLockup
            if (root.variant === "wordmark")
                return Brand.logoWordmark
            // mark
            if (root.theme === "mono")  return Brand.logoMarkMono
            if (root.theme === "light") return Brand.logoMarkLight
            return Brand.logoMark
        }
    }
}
