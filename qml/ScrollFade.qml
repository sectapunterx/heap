// A soft edge over a Flickable's top and bottom while there is more of
// it to scroll that way (SCALE-1/2): a nav list cut mid-row read as
// broken, or as the end of the list. Put it next to the Flickable, over
// the same area, and give it the colour the list sits on.
//   ScrollFade { anchors.fill: navScroll; flick: navScroll; color: Theme.panel }
import QtQuick
import TodoCpp

Item {
    id: fade
    required property Flickable flick
    property color color: Theme.bg
    property int size: Theme.px(28)
    // Mouse and keys go to the list underneath.
    enabled: false

    readonly property bool moreAbove: fade.flick.contentY > 1
    readonly property bool moreBelow: fade.flick.contentY + fade.flick.height < fade.flick.contentHeight - 1

    Rectangle {
        objectName: "scroll-fade-top"
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: fade.size
        visible: fade.moreAbove
        gradient: Gradient {
            GradientStop { position: 0; color: fade.color }
            GradientStop { position: 1; color: Theme.withAlpha(fade.color, 0) }
        }
    }
    Rectangle {
        objectName: "scroll-fade-bottom"
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: fade.size
        visible: fade.moreBelow
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.withAlpha(fade.color, 0) }
            GradientStop { position: 1; color: fade.color }
        }
    }
}
