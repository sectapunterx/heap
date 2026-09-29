import QtQuick
import TodoCpp

Rectangle {
    id: root
    property string message: ""
    property string actionLabel: ""
    property var    onAction: null
    // "info" | "success" | "warning" | "error" — tints the dot and the
    // border with the theme's alert colour. Plain notices stay "info".
    property string kind: "info"
    readonly property color kindColor: Theme.alertColor(kind)

    radius: Theme.radius
    color: Theme.toastBg
    border.color: kind === "info" ? Theme.toastBorder : Theme.withAlpha(kindColor, 0.6)
    border.width: 1
    opacity: 0
    visible: opacity > 0.02
    implicitWidth: rowL.implicitWidth + 28
    implicitHeight: rowL.implicitHeight + 14

    Row {
        id: rowL
        anchors.centerIn: parent
        spacing: Theme.spXl
        Rectangle {
            objectName: "toast-kind-dot"
            anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4
            color: root.kindColor
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.message
            color: Theme.toastText
            font.pixelSize: Theme.fsMd
        }
        Rectangle {
            visible: root.actionLabel.length > 0
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.radiusSm
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
                font.pixelSize: Theme.fsSm
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

    function show(s, k) {
        message = s; actionLabel = ""; onAction = null;
        kind = k || "info";
        opacity = 1;
        hideTimer.interval = 2400;
        hideTimer.restart();
    }
    function showWithAction(s, label, seconds, fn, k) {
        message = s; actionLabel = label; onAction = fn;
        kind = k || "info";
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
    Behavior on opacity { NumberAnimation { duration: Theme.scaledMs(180) } }
}
