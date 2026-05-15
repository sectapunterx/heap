import QtQuick
import TodoCpp

Rectangle {
    id: root
    property string message: ""
    radius: 8
    color: Theme.panel3
    border.color: Theme.borderStrong
    border.width: 1
    opacity: 0
    visible: opacity > 0.02
    implicitWidth: msg.implicitWidth + 28
    implicitHeight: msg.implicitHeight + 16

    Text {
        id: msg
        anchors.centerIn: parent
        text: root.message
        color: Theme.text
        font.pixelSize: 12
    }

    function show(s) {
        message = s;
        opacity = 1;
        hideTimer.restart();
    }
    Timer {
        id: hideTimer
        interval: 2400
        repeat: false
        onTriggered: root.opacity = 0
    }
    Behavior on opacity { NumberAnimation { duration: 180 } }
}
