import QtQuick
import TodoCpp

Rectangle {
    id: root
    property string message: ""
    property string actionLabel: ""
    property var    onAction: null

    radius: 8
    color: Theme.panel3
    border.color: Theme.borderStrong
    border.width: 1
    opacity: 0
    visible: opacity > 0.02
    implicitWidth: rowL.implicitWidth + 28
    implicitHeight: rowL.implicitHeight + 14

    Row {
        id: rowL
        anchors.centerIn: parent
        spacing: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.message
            color: Theme.text
            font.pixelSize: 12
        }
        Rectangle {
            visible: root.actionLabel.length > 0
            anchors.verticalCenter: parent.verticalCenter
            radius: 5
            color: actionMA.containsMouse ? Theme.accentSoft : "transparent"
            border.color: Theme.accent
            border.width: 1
            implicitWidth: actionT.implicitWidth + 14
            implicitHeight: actionT.implicitHeight + 6
            Text {
                id: actionT
                anchors.centerIn: parent
                text: root.actionLabel
                color: Theme.accentStrong
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: actionMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const fn = root.onAction;
                    root.opacity = 0;
                    hideTimer.stop();
                    if (typeof fn === "function") fn();
                }
            }
        }
    }

    function show(s) {
        message = s; actionLabel = ""; onAction = null;
        opacity = 1;
        hideTimer.interval = 2400;
        hideTimer.restart();
    }
    function showWithAction(s, label, seconds, fn) {
        message = s; actionLabel = label; onAction = fn;
        opacity = 1;
        hideTimer.interval = (seconds && seconds > 0 ? seconds : 5) * 1000;
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
